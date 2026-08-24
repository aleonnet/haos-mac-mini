# =============================================================================
# ha-api.py — o braço do instalador DENTRO do Home Assistant.
#
# bash não fala WebSocket e não deve falar JSON na unha — este helper fala os
# dois, só com a stdlib (a máquina do usuário não tem pip garantido).
# Embutido no haos-install.sh via tools/embed.sh (bloco HELPER); a fonte de
# verdade é este arquivo.
#
# CONTRATO DE SEGREDO (banca 24/08):
#   - credenciais entram por STDIN: linha 1 = usuário, linha 2 = senha,
#     linhas seguintes = payload JSON quando o comando pedir. NUNCA argv/env.
#   - erro imprime SÓ "ERRO <status> <rota>" no stderr — nunca corpo de
#     request/response (o stderr pode ir para o LOG_FILE preservado).
#   - tokens vivem só na memória deste processo.
#
# Superfícies (docs/API-REFERENCE_20260823_verificado.md):
#   /auth/token é Authentication API pública; onboarding, config_entries e o
#   comando WS supervisor/api são SOURCE-PINNED no Core 2026.8.3 — daí toda
#   escrita conferir a PÓS-CONDIÇÃO, nunca só o status HTTP.
#
# Saída (contrato com o instalador): exit 0 = fez agora · 100 = já estava ·
# 1 = erro. Comandos que devolvem dados imprimem UMA linha por dado no stdout.
# =============================================================================
import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("HAOS_BASE", "").rstrip("/")
LANG = os.environ.get("HAOS_HELPER_LANG", "pt")
JA = 100


def erro(rota, status):
    print(f"ERRO {status} {rota}", file=sys.stderr)
    sys.exit(1)


class _SemRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):  # noqa: D102
        return None


_opener = urllib.request.build_opener(_SemRedirect)


def http(caminho, metodo="GET", dados=None, token=None, form=False, timeout=30):
    """(status, corpo). Segue 3xx PRESERVANDO método e corpo — medido em
    24/08: antes do onboarding a API mora na porta 80 e a 8123 devolve 307."""
    url = BASE + caminho
    corpo = None
    cab = {}
    if dados is not None:
        if form:
            corpo = urllib.parse.urlencode(dados).encode()
            cab["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            corpo = json.dumps(dados).encode()
            cab["Content-Type"] = "application/json"
    if token:
        cab["Authorization"] = f"Bearer {token}"
    for _ in range(4):
        req = urllib.request.Request(url, data=corpo, headers=cab, method=metodo)
        try:
            with _opener.open(req, timeout=timeout) as r:
                texto = r.read().decode("utf-8", "replace")
                try:
                    return r.status, json.loads(texto)
                except json.JSONDecodeError:
                    return r.status, texto
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 307, 308) and e.headers.get("Location"):
                url = urllib.parse.urljoin(url, e.headers["Location"])
                continue
            texto = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(texto)
            except json.JSONDecodeError:
                return e.code, texto
        except (urllib.error.URLError, OSError):
            return 0, ""
    return 0, ""


def _cid():
    return BASE.rstrip("/") + "/"


def _troca_code(code, rota):
    st, r = http("/auth/token", "POST", {
        "grant_type": "authorization_code", "code": code, "client_id": _cid(),
    }, form=True)
    if st != 200 or not isinstance(r, dict) or "access_token" not in r:
        erro(rota, st)
    return r["access_token"], r.get("refresh_token", "")


def onboarding_estado():
    """(status, lista-de-passos). 404 = onboarding já terminou."""
    return http("/api/onboarding")


def login(usuario, senha):
    """login_flow → token. Para instância JÁ onboardada."""
    st, r = http("/auth/login_flow", "POST", {
        "client_id": _cid(), "handler": ["homeassistant", None],
        "redirect_uri": _cid(),
    })
    if st != 200 or not isinstance(r, dict) or "flow_id" not in r:
        erro("/auth/login_flow", st)
    st, r = http(f"/auth/login_flow/{r['flow_id']}", "POST", {
        "username": usuario, "password": senha, "client_id": _cid(),
    })
    if st != 200 or not isinstance(r, dict) or r.get("type") != "create_entry":
        erro("/auth/login_flow (credencial)", st)
    return _troca_code(r["result"], "/auth/token")


def autenticar(usuario, senha):
    """Fresca ou onboardada, devolve (access, refresh)."""
    st, passos = onboarding_estado()
    if st == 200 and isinstance(passos, list) \
            and not all(p.get("done") for p in passos):
        pend = {p["step"] for p in passos if not p.get("done")}
        if "user" in pend:
            st, r = http("/api/onboarding/users", "POST", {
                "name": usuario, "username": usuario, "password": senha,
                "client_id": _cid(), "language": LANG,
            })
            if st != 200 or not isinstance(r, dict) or "auth_code" not in r:
                erro("/api/onboarding/users", st)
            return _troca_code(r["auth_code"], "/auth/token")
    return login(usuario, senha)


def _le_credencial():
    usuario = sys.stdin.readline().strip()
    senha = sys.stdin.readline().rstrip("\n")
    if not usuario or not senha:
        erro("credencial ausente no stdin", 0)
    return usuario, senha


# ── onboarding (F6) ──────────────────────────────────────────────────────────
def cmd_conta():
    usuario, senha = _le_credencial()
    st, passos = onboarding_estado()
    if st == 404 or (st == 200 and isinstance(passos, list)
                     and all(p.get("done") for p in passos)):
        login(usuario, senha)  # valida a credencial agora, não na F7
        sys.exit(JA)
    if st != 200 or not isinstance(passos, list):
        erro("/api/onboarding", st)
    token, _ = autenticar(usuario, senha)
    pend = {p["step"] for p in passos if not p.get("done")}
    if "core_config" in pend:
        st, _r = http("/api/onboarding/core_config", "POST", {}, token=token)
        if st != 200:
            erro("/api/onboarding/core_config", st)
    if "analytics" in pend:
        # consentimento NUNCA assumido: o passo é concluído sem ligar envio
        st, _r = http("/api/onboarding/analytics", "POST", {}, token=token)
        if st != 200:
            erro("/api/onboarding/analytics", st)
    if "integration" in pend:
        st, _r = http("/api/onboarding/integration", "POST", {
            "client_id": _cid(), "redirect_uri": _cid(),
        }, token=token)
        if st != 200:
            erro("/api/onboarding/integration", st)
    # pós-condição: acabou de verdade?
    st, passos = onboarding_estado()
    if st == 200 and isinstance(passos, list) \
            and not all(p.get("done") for p in passos):
        erro("/api/onboarding (pós-condição)", st)
    sys.exit(0)


# ── WebSocket RFC 6455, só stdlib (F7) ──────────────────────────────────────
class WS:
    """Cliente mínimo: máscara obrigatória no cliente, comprimentos 126/127,
    PING→PONG, fragmentação, timeout de socket dos dois lados."""

    def __init__(self, timeout=60):
        u = urllib.parse.urlparse(BASE)
        self.sock = socket.create_connection(
            (u.hostname, u.port or 80), timeout=timeout)
        chave = base64.b64encode(secrets.token_bytes(16)).decode()
        pedido = (
            f"GET /api/websocket HTTP/1.1\r\n"
            f"Host: {u.hostname}:{u.port or 80}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {chave}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(pedido.encode())
        resposta = b""
        while b"\r\n\r\n" not in resposta:
            peda = self.sock.recv(4096)
            if not peda:
                erro("/api/websocket (handshake)", 0)
            resposta += peda
        cabeca, _, resto = resposta.partition(b"\r\n\r\n")
        if b" 101 " not in cabeca.split(b"\r\n", 1)[0]:
            erro("/api/websocket (upgrade)", 0)
        esperado = base64.b64encode(hashlib.sha1(
            (chave + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
        ).digest())
        if esperado not in cabeca:
            erro("/api/websocket (accept)", 0)
        self.buf = resto
        self.n = 0

    def _le(self, quanto):
        while len(self.buf) < quanto:
            peda = self.sock.recv(65536)
            if not peda:
                erro("/api/websocket (conexão caiu)", 0)
            self.buf += peda
        dado, self.buf = self.buf[:quanto], self.buf[quanto:]
        return dado

    def envia_texto(self, texto):
        dado = texto.encode()
        mascara = secrets.token_bytes(4)
        corpo = bytes(b ^ mascara[i % 4] for i, b in enumerate(dado))
        tam = len(dado)
        if tam < 126:
            cab = struct.pack("!BB", 0x81, 0x80 | tam)
        elif tam < 65536:
            cab = struct.pack("!BBH", 0x81, 0x80 | 126, tam)
        else:
            cab = struct.pack("!BBQ", 0x81, 0x80 | 127, tam)
        self.sock.sendall(cab + mascara + corpo)

    def _quadro(self):
        b1, b2 = struct.unpack("!BB", self._le(2))
        fim, opcode = b1 & 0x80, b1 & 0x0F
        tam = b2 & 0x7F
        if tam == 126:
            (tam,) = struct.unpack("!H", self._le(2))
        elif tam == 127:
            (tam,) = struct.unpack("!Q", self._le(8))
        if b2 & 0x80:  # servidor não mascara; tolerar se mascarar
            mascara = self._le(4)
            dado = bytes(b ^ mascara[i % 4] for i, b in enumerate(self._le(tam)))
        else:
            dado = self._le(tam)
        return fim, opcode, dado

    def recebe(self):
        partes = b""
        while True:
            fim, opcode, dado = self._quadro()
            if opcode == 0x9:   # PING → PONG com o mesmo payload
                mascara = secrets.token_bytes(4)
                corpo = bytes(b ^ mascara[i % 4] for i, b in enumerate(dado))
                self.sock.sendall(
                    struct.pack("!BB", 0x8A, 0x80 | len(dado)) + mascara + corpo)
                continue
            if opcode == 0x8:
                erro("/api/websocket (close do servidor)", 0)
            if opcode in (0x1, 0x2, 0x0):
                partes += dado
                if fim:
                    return json.loads(partes.decode("utf-8", "replace"))

    def auth(self, token):
        m = self.recebe()
        if m.get("type") != "auth_required":
            erro("/api/websocket (auth_required)", 0)
        self.envia_texto(json.dumps({"type": "auth", "access_token": token}))
        m = self.recebe()
        if m.get("type") != "auth_ok":
            erro("/api/websocket (auth)", 0)

    def chama(self, corpo):
        self.n += 1
        corpo = dict(corpo, id=self.n)
        self.envia_texto(json.dumps(corpo))
        while True:
            m = self.recebe()
            if m.get("id") == self.n and m.get("type") == "result":
                return m


def sup(ws, endpoint, metodo="get", dados=None, timeout=None):
    """supervisor/api — a ÚNICA rota que funciona com token de usuário para
    falar com o Supervisor (o proxy REST /api/hassio/* devolve 401, medido)."""
    corpo = {"type": "supervisor/api", "endpoint": endpoint, "method": metodo}
    if dados is not None:
        corpo["data"] = dados
    if timeout is not None:
        corpo["timeout"] = timeout
    m = ws.chama(corpo)
    if not m.get("success"):
        erro(f"supervisor/api {endpoint}", 0)
    return m.get("result")


def _ws_autenticado():
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    ws = WS(timeout=300)
    ws.auth(token)
    return ws, token


# ── apps (F7) ────────────────────────────────────────────────────────────────
def cmd_repo_ensure(url, sufixo):
    """Garante o repositório e imprime o slug real `<hash>_<sufixo>` —
    o prefixo é hash da URL: descobrir SEMPRE, nunca fixar."""
    ws, _tok = _ws_autenticado()
    loja = sup(ws, "/store")
    repos = {r.get("source"): r.get("slug") for r in loja.get("repositories", [])}
    if url not in repos:
        sup(ws, "/store/repositories", "post", {"repository": url}, timeout=120)
        loja = sup(ws, "/store")
        repos = {r.get("source"): r.get("slug")
                 for r in loja.get("repositories", [])}
    prefixo = repos.get(url)
    if not prefixo:
        erro("/store/repositories (pós-condição)", 0)
    for a in loja.get("addons", []):
        if a.get("slug") == f"{prefixo}_{sufixo}":
            print(a["slug"])
            return
    erro(f"/store (sem app _{sufixo} no repositório)", 0)


def _opt_mescla(atu, nov):
    m = dict(atu)
    for k, v in nov.items():
        if isinstance(v, dict):
            m[k] = _opt_mescla(atu.get(k) or {}, v)
        else:
            m[k] = v
    return m


def _opt_difere(atu, nov):
    for k, v in nov.items():
        if isinstance(v, dict):
            if _opt_difere(atu.get(k) or {}, v):
                return True
        elif isinstance(v, list):
            tem = atu.get(k) or []
            if not all(x in tem for x in v):
                return True
        elif atu.get(k) != v:
            return True
    return False


def cmd_addon_ensure(slug, com_options):
    """Instala (se preciso), aplica options (stdin, se pedido) e inicia.
    Pós-condição: info.state == started. exit 100 quando nada mudou.
    Ordem do stdin importa: credencial primeiro, payload depois."""
    ws, _tok = _ws_autenticado()
    opcoes = None
    if com_options:
        bruto = sys.stdin.read()
        opcoes = json.loads(bruto) if bruto.strip() else None
    st_info = sup(ws, f"/addons/{slug}/info") if _addon_existe(ws, slug) else None
    mudou = False
    if st_info is None or not st_info.get("version"):
        sup(ws, f"/store/addons/{slug}/install", "post", timeout=1800)
        st_info = sup(ws, f"/addons/{slug}/info")
        if not st_info.get("version"):
            erro(f"/store/addons/{slug}/install (pós-condição)", 0)
        mudou = True
    if opcoes:
        atuais = st_info.get("options") or {}
        # options podem ser ANINHADAS (advanced_ssh guarda em ssh.*, medido
        # em campo: o merge raso deixava a chave fora e o diff nunca zerava).
        # Lista: em dia quando tudo que pedimos está lá (o app normaliza).
        if _opt_difere(atuais, opcoes):
            sup(ws, f"/addons/{slug}/options", "post",
                {"options": _opt_mescla(atuais, opcoes)})
            mudou = True
            aplicou_opts = True
        else:
            aplicou_opts = False
    else:
        aplicou_opts = False
    if st_info.get("state") != "started":
        sup(ws, f"/addons/{slug}/start", "post", timeout=300)
        mudou = True
    elif aplicou_opts:
        # option nova num app RODANDO só vale depois de reiniciá-lo
        sup(ws, f"/addons/{slug}/restart", "post", timeout=300)
    st_info = sup(ws, f"/addons/{slug}/info")
    if st_info.get("state") != "started":
        erro(f"/addons/{slug}/start (pós-condição)", 0)
    sys.exit(0 if mudou else JA)


def _addon_existe(ws, slug):
    lista = sup(ws, "/addons")
    return any(a.get("slug") == slug for a in lista.get("addons", []))


def cmd_addon_option(slug, chave):
    """Imprime UMA option do app (ex.: a senha do samba na reexecução —
    desired-state: quem detém a verdade é o Supervisor)."""
    ws, _tok = _ws_autenticado()
    if not _addon_existe(ws, slug):
        erro(f"/addons/{slug} (ausente)", 0)
    info = sup(ws, f"/addons/{slug}/info")
    valor = (info.get("options") or {}).get(chave)
    if valor is None:
        erro(f"/addons/{slug}/info (sem option {chave})", 0)
    print(valor)


# ── integrações (F8) ─────────────────────────────────────────────────────────
def _entries(token, dominio):
    st, r = http("/api/config/config_entries/entry", token=token)
    if st != 200 or not isinstance(r, list):
        erro("/api/config/config_entries/entry", st)
    return [e for e in r if e.get("domain") == dominio]


PRECISA_USUARIO = 3


def cmd_entry_ensure(dominio, fontes):
    """Cria a entry SÓ quando o flow fecha sem dado do usuário (regra da
    curadoria: credencial NUNCA). Flow que pede dado ou escolha → exit 3,
    depois de DESFAZER o flow aberto (não deixar lixo no painel).
    CERCA DE CONJUNTO: lê a entry de volta e confere source ∈ fontes;
    fora do conjunto → REMOVE a entry e falha."""
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    if _entries(token, dominio):
        sys.exit(JA)
    st, r = http("/api/config/config_entries/flow", "POST",
                 {"handler": dominio}, token=token)
    if st != 200 or not isinstance(r, dict):
        erro("/api/config/config_entries/flow", st)

    def _desiste():
        fid = r.get("flow_id")
        if fid:
            http(f"/api/config/config_entries/flow/{fid}", "DELETE",
                 token=token)
        sys.exit(PRECISA_USUARIO)

    for _ in range(4):  # nunca postar formulário sem ler o schema (contrato)
        if r.get("type") in ("create_entry", "abort"):
            break
        if r.get("type") != "form":
            _desiste()  # menu, progress, credencial externa — é do usuário
        schema = r.get("data_schema") or []
        if any(c.get("required") and c.get("default") is None for c in schema):
            _desiste()
        corpo = {c["name"]: c["default"] for c in schema
                 if c.get("default") is not None}
        st, r = http(f"/api/config/config_entries/flow/{r['flow_id']}",
                     "POST", corpo, token=token)
        if st != 200 or not isinstance(r, dict):
            erro(f"/api/config/config_entries/flow/{dominio}", st)
    criadas = _entries(token, dominio)
    if not criadas:
        # abort (ex.: tuya sem credencial de nuvem — medido em campo) ou um
        # flow que nunca fecha só com defaults: é do USUÁRIO, não erro nosso
        _desiste()
    permitidas = fontes.split(",")
    for e in criadas:
        if e.get("source") not in permitidas:
            http(f"/api/config/config_entries/entry/{e['entry_id']}",
                 "DELETE", token=token)
            erro(f"flow {dominio} (source {e.get('source')} fora do conjunto)", 0)
    sys.exit(0)


def cmd_flows_pendentes():
    """Imprime 'dominio contagem' dos discovery flows esperando o usuário.
    Listar flows em progresso não tem rota REST (405, medido em 24/08) —
    é o comando WS config_entries/flow/progress."""
    ws, _tok = _ws_autenticado()
    m = ws.chama({"type": "config_entries/flow/progress"})
    if not m.get("success"):
        erro("config_entries/flow/progress", 0)
    contagem = {}
    for f in m.get("result") or []:
        d = f.get("handler", "?")
        contagem[d] = contagem.get(d, 0) + 1
    for d in sorted(contagem):
        print(d, contagem[d])


# ── configuração do Core (F9) ────────────────────────────────────────────────
def cmd_core_check():
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    st, r = http("/api/config/core/check_config", "POST", {}, token=token)
    if st != 200 or not isinstance(r, dict) or r.get("result") != "valid":
        erro("/api/config/core/check_config", st)


def cmd_core_restart():
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    st, _r = http("/api/services/homeassistant/restart", "POST", {},
                  token=token, timeout=10)
    # o restart derruba a conexão no meio — status 0 aqui não é erro
    if st not in (0, 200):
        erro("/api/services/homeassistant/restart", st)


def main():
    if not BASE:
        erro("HAOS_BASE ausente", 0)
    args = sys.argv[1:]
    if not args:
        erro("comando ausente", 0)
    cmd, resto = args[0], args[1:]
    if cmd == "conta":
        cmd_conta()
    elif cmd == "repo-ensure":
        cmd_repo_ensure(resto[0], resto[1])
    elif cmd == "addon-ensure":
        cmd_addon_ensure(resto[0], len(resto) > 1 and resto[1] == "--options-stdin")
    elif cmd == "addon-option":
        cmd_addon_option(resto[0], resto[1])
    elif cmd == "entry-ensure":
        cmd_entry_ensure(resto[0], resto[1])
    elif cmd == "flows-pendentes":
        cmd_flows_pendentes()
    elif cmd == "core-check":
        cmd_core_check()
    elif cmd == "core-restart":
        cmd_core_restart()
    else:
        erro(f"comando desconhecido {cmd}", 0)


main()
