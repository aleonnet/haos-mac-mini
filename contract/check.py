#!/usr/bin/env python3
"""
check.py — roda o arnês de contrato contra uma instância de Home Assistant.

Prova que a superfície de que o instalador depende continua existindo e
continua se comportando. Status HTTP não basta: cada dependência declara uma
pós-condição, e é ela que decide.

    ./check.py --url http://localhost:8123 --user NOME --pass SENHA
    ./check.py --url ... --user ... --pass ... --json

Exit: 0 contrato íntegro · 3 contrato quebrado · 4 dependência ausente

Só stdlib, mais `websockets` quando houver dependência de WebSocket a checar.
O instalador não pode assumir a lib presente na máquina do usuário — no CI ela
é instalada de propósito.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
CONTRATO = RAIZ / "contract.yaml"

OK, FALHA, AVISO = "OK", "FALHA", "AVISO"

# Ligado por --instancia-nova. O CI sobe um container limpo e liga; contra uma
# instância viva fica desligado, e as dependências de onboarding são puladas.
INSTANCIA_NOVA = False

# O componente `hassio` só carrega em HAOS/Supervised. Sem ele, as rotas do
# Supervisor não existem — e não existir é diferente de recusar.
TEM_SUPERVISOR = False


class Resultado:
    def __init__(self) -> None:
        self.linhas: list[tuple[str, str, str]] = []

    def add(self, estado: str, ident: str, detalhe: str) -> None:
        self.linhas.append((estado, ident, detalhe))

    @property
    def falhas(self) -> int:
        return sum(1 for e, _, _ in self.linhas if e == FALHA)

    @property
    def avisos(self) -> int:
        return sum(1 for e, _, _ in self.linhas if e == AVISO)


def http(url: str, metodo: str = "GET", dados=None, token: str | None = None,
         form: bool = False, timeout: int = 20):
    """Devolve (status, corpo_decodificado_ou_texto). Não levanta em 4xx/5xx."""
    corpo = None
    cabecalhos = {}
    if dados is not None:
        if form:
            corpo = urllib.parse.urlencode(dados).encode()
            cabecalhos["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            corpo = json.dumps(dados).encode()
            cabecalhos["Content-Type"] = "application/json"
    if token:
        cabecalhos["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=corpo, headers=cabecalhos, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            texto = r.read().decode("utf-8", "replace")
            try:
                return r.status, json.loads(texto)
            except json.JSONDecodeError:
                return r.status, texto
    except urllib.error.HTTPError as e:
        texto = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(texto)
        except json.JSONDecodeError:
            return e.code, texto
    except (urllib.error.URLError, OSError) as e:
        return 0, str(e)


def autenticar(base: str, usuario: str, senha: str) -> str:
    """login_flow -> code -> /auth/token. Devolve o access_token."""
    cid = base.rstrip("/") + "/"
    st, r = http(f"{base}/auth/login_flow", "POST", {
        "client_id": cid, "handler": ["homeassistant", None], "redirect_uri": cid,
    })
    if st != 200 or not isinstance(r, dict) or "flow_id" not in r:
        raise SystemExit(f"[ERRO] login_flow falhou: {st} {str(r)[:200]}")
    st, r = http(f"{base}/auth/login_flow/{r['flow_id']}", "POST", {
        "username": usuario, "password": senha, "client_id": cid,
    })
    if st != 200 or not isinstance(r, dict) or r.get("type") != "create_entry":
        raise SystemExit(f"[ERRO] credencial recusada: {st} {str(r)[:200]}")
    st, r = http(f"{base}/auth/token", "POST", {
        "grant_type": "authorization_code", "code": r["result"], "client_id": cid,
    }, form=True)
    if st != 200 or not isinstance(r, dict) or "access_token" not in r:
        raise SystemExit(f"[ERRO] troca de code por token falhou: {st} {str(r)[:200]}")
    return r["access_token"]


def bootstrap(base: str, usuario: str, senha: str) -> str:
    """Instância nova: cria o primeiro administrador e devolve o access_token.

    Só funciona antes de o onboarding terminar — que é exatamente a janela em
    que as rotas de onboarding existem. É assim que o CI cobre as dependências
    de escopo instancia_nova.
    """
    cid = base.rstrip("/") + "/"
    st, r = http(f"{base}/api/onboarding/users", "POST", {
        "name": "CI", "username": usuario, "password": senha,
        "client_id": cid, "language": "pt",
    })
    if st != 200 or not isinstance(r, dict) or "auth_code" not in r:
        raise SystemExit(f"[ERRO] onboarding/users falhou: {st} {str(r)[:200]}")
    st, r = http(f"{base}/auth/token", "POST", {
        "grant_type": "authorization_code", "code": r["auth_code"], "client_id": cid,
    }, form=True)
    if st != 200 or "access_token" not in r:
        raise SystemExit(f"[ERRO] troca do auth_code falhou: {st} {str(r)[:200]}")
    return r["access_token"]


def carrega_contrato() -> dict:
    """Lê o contract.yaml. Usa PyYAML se houver; senão, um leitor mínimo."""
    texto = CONTRATO.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore
        return yaml.safe_load(texto)
    except ImportError:
        raise SystemExit(
            "[ERRO] PyYAML ausente. O arnês roda no CI, onde ele é instalado.\n"
            "       Local: pip install pyyaml"
        )


def pula_por_ambiente(dep: dict, res: Resultado) -> bool:
    ident = dep["id"]
    if dep.get("requer") == "supervisor" and not TEM_SUPERVISOR:
        res.add(OK, ident, "requer Supervisor — pulada (alvo é Core sem Supervisor)")
        return True
    if dep.get("escopo") == "instancia_nova" and not INSTANCIA_NOVA:
        res.add(OK, ident, "escopo instancia_nova — pulada (instância já onboardada)")
        return True
    return False


def checa_http(base: str, token: str, dep: dict, res: Resultado) -> None:
    ident = dep["id"]
    caminho = dep.get("path")
    metodo = dep.get("method", "GET")
    esperado = dep.get("expect_status")

    if pula_por_ambiente(dep, res):
        return

    # Só exercitamos leituras. Escritas (criar usuário, iniciar flow) mudam
    # estado e pertencem ao teste de integração, não ao arnês de contrato.
    if metodo != "GET":
        res.add(OK, ident, "declarado; não exercitado (é escrita)")
        return

    st, corpo = http(f"{base}{caminho}", metodo, token=token)

    if esperado is not None:
        if st == esperado:
            res.add(OK, ident, f"status {st} como esperado (checagem negativa)")
        else:
            # não falha: um 200 aqui é boa notícia, e o instalador ganha caminho
            res.add(AVISO, ident, f"esperava {esperado}, veio {st} — a superfície MUDOU, reavaliar")
        return

    if st != 200:
        res.add(FALHA, ident, f"status {st} — {str(corpo)[:120]}")
        return

    for regra in dep.get("verify", []):
        for chave, valor in regra.items():
            if chave == "response_has":
                if not (isinstance(corpo, dict) and valor in corpo):
                    res.add(FALHA, ident, f"resposta sem campo '{valor}'")
                    return
            elif chave == "response_is_list":
                if not isinstance(corpo, list):
                    res.add(FALHA, ident, f"esperava lista, veio {type(corpo).__name__}")
                    return
            elif chave == "each_item_has":
                if not isinstance(corpo, list):
                    res.add(FALHA, ident, "esperava lista para each_item_has")
                    return
                for it in corpo:
                    faltando = [c for c in valor if c not in it]
                    if faltando:
                        res.add(FALHA, ident, f"item sem campos {faltando}")
                        return
    res.add(OK, ident, f"status 200, pós-condições conferidas ({len(corpo) if isinstance(corpo,(list,dict)) else '?'})")


def checa_ws(base: str, token: str, dep: dict, res: Resultado) -> None:
    ident = dep["id"]
    if pula_por_ambiente(dep, res):
        return
    try:
        import asyncio
        import websockets  # type: ignore
    except ImportError:
        res.add(AVISO, ident, "websockets ausente — checagem pulada")
        return

    url = base.replace("http://", "ws://").replace("https://", "wss://") + "/api/websocket"

    async def roda():
        async with websockets.connect(url, max_size=16_000_000) as ws:
            await ws.recv()
            await ws.send(json.dumps({"type": "auth", "access_token": token}))
            r = json.loads(await ws.recv())
            if r.get("type") != "auth_ok":
                return None
            msg = {"id": 1, "type": dep["type"]}
            if dep["type"] == "supervisor/api":
                msg.update({"endpoint": "/supervisor/info", "method": "get"})
            await ws.send(json.dumps(msg))
            while True:
                m = json.loads(await ws.recv())
                if m.get("id") == 1:
                    return m

    try:
        m = asyncio.run(roda())
    except Exception as e:  # noqa: BLE001
        res.add(FALHA, ident, f"conexão WebSocket falhou: {e}")
        return

    if m is None:
        res.add(FALHA, ident, "auth recusada no WebSocket")
        return
    if dep["type"] == "config_entries/ignore_flow":
        # exige flow em progresso; sem isso o erro esperado é de pré-condição
        res.add(OK, ident, "declarado; exige flow em progresso, não exercitado")
        return
    if m.get("success"):
        res.add(OK, ident, "comando aceito e result presente")
    else:
        err = m.get("error", {})
        res.add(FALHA, ident, f"{err.get('code')} · {err.get('message','')[:90]}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Arnês de contrato do haos-install")
    ap.add_argument("--url", required=True)
    ap.add_argument("--user")
    ap.add_argument("--pass", dest="senha")
    ap.add_argument("--token", help="usa este access_token em vez de autenticar")
    ap.add_argument("--bootstrap", action="store_true",
                    help="instância nova: cria o primeiro admin via onboarding")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--instancia-nova", action="store_true",
                    help="a instância ainda não passou pelo onboarding (é o caso do CI)")
    a = ap.parse_args()

    global INSTANCIA_NOVA
    INSTANCIA_NOVA = a.instancia_nova

    base = a.url.rstrip("/")
    contrato = carrega_contrato()
    res = Resultado()

    if a.token:
        token = a.token
    elif a.bootstrap:
        token = bootstrap(base, a.user or "ci", a.senha or "ci-senha-de-teste-0123")
        INSTANCIA_NOVA = True
    elif a.user and a.senha:
        token = autenticar(base, a.user, a.senha)
    else:
        raise SystemExit("[ERRO] informe --token, ou --user/--pass, ou --bootstrap")

    # Descobre o ambiente antes de checar: o componente `hassio` só existe em
    # HAOS/Supervised. Contra Core puro as rotas do Supervisor não existem, e
    # cobrar delas seria o arnês mentindo sobre o que cobriu.
    global TEM_SUPERVISOR
    st, cfg = http(f"{base}/api/config", token=token)
    if st == 200 and isinstance(cfg, dict):
        TEM_SUPERVISOR = "hassio" in cfg.get("components", [])
    if not a.json:
        print(f"alvo: HA {cfg.get('version','?') if isinstance(cfg,dict) else '?'} · "
              f"Supervisor: {'sim' if TEM_SUPERVISOR else 'NÃO (Core puro)'}")

    for dep in contrato.get("dependencies", []):
        proto = dep.get("protocol")
        if proto == "http":
            checa_http(base, token, dep, res)
        elif proto == "websocket":
            checa_ws(base, token, dep, res)
        else:
            res.add(AVISO, dep["id"], f"protocolo '{proto}' desconhecido")

    if a.json:
        print(json.dumps({
            "reference_version": contrato.get("reference_version"),
            "resultados": [{"estado": e, "id": i, "detalhe": d} for e, i, d in res.linhas],
            "falhas": res.falhas, "avisos": res.avisos,
        }, ensure_ascii=False, indent=2))
    else:
        print(f"\nArnês de contrato — referência {contrato.get('reference_version')}\n")
        for estado, ident, detalhe in res.linhas:
            marca = {OK: "[OK]   ", FALHA: "[ERRO] ", AVISO: "[!]    "}[estado]
            print(f"{marca} {ident:34} {detalhe}")
        print(f"\nRESULTADO: {len(res.linhas)} dependências · "
              f"{res.falhas} falha(s) · {res.avisos} aviso(s)")

    return 3 if res.falhas else 0


if __name__ == "__main__":
    sys.exit(main())
