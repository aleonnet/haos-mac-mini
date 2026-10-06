#!/usr/bin/env python3
"""
pacotes.py — arnês dos packages BR contra um Home Assistant de verdade.

O arnês de contrato (check.py) prova que a superfície do HA de que o INSTALADOR
depende continua existindo. Este prova outra coisa: que os PACKAGES que o
instalador entrega fazem a conta que prometem. Nasceu de defeito de campo
(2026-10-06): três referências a entidades inexistentes, escondidas por valor
padrão de template, e uma soma que tratava "sem resposta" como zero — nada
disso era visível para um portão que só conferia se o arquivo foi escrito.

A instância tem de ter subido COM os packages do repositório em /config/packages
(é o que tools/pacotes-arnes.sh faz) e estar NOVA: a primeira garantia lê o
estado de fábrica. O identificador de cada entidade é o que o próprio Home
Assistant gerou — o arnês não reimplementa a regra de nomes.

    ./pacotes.py --url http://127.0.0.1:18123 --bootstrap

A conta de energia não é mais digitada: o arnês informa só as datas de leitura
e o consumo, e compara cada número do Home Assistant com a calculadora de
referência (tarifas/fatura.py), que lê o mesmo arquivo de dados.

Tokens de falha, um por garantia:
    ESTADO DE FABRICA:  REFERENCIA INEXISTENTE:  SOMA PARCIAL:
    FORMULA DIVERGE:  AJUSTE IGNORADO:  CAMPO NAO PERSISTE:
    CICLO NAO ZERA:  MEDIDOR NAO ACOMPANHA:  AGUA NAO REPRODUZ:
    GAS NAO REPRODUZ:  ERRO NO REGISTRO:
Sucesso: PACOTES OK

Exit: 0 íntegro · 3 alguma garantia quebrou · 4 dependência ausente

Limites declarados:
  · As fases de teste são sensores de energia criados pelo fluxo de
    configuração da integração `template`, e o domínio procurado é trocado de
    'shelly' para 'template' antes de o texto ir ao motor do HA. Prova-se a
    descoberta pelo registro, a regra de disponibilidade e a soma — não um
    Shelly de verdade, nem a sequência real de uma recarga da integração.
  · O fechamento do ciclo é exercitado por data passada, por data futura, na
    repetição do disparo e no início do Home Assistant. O gatilho da meia-noite
    é só CONFERIDO no arquivo (existe e marca 00:00): fazê-lo disparar exigiria
    mexer no relógio.
  · A grade de fórmulas usa ciclos já encerrados, em que consumo projetado e
    consumo coincidem. A projeção do ciclo que ainda corre é conferida à parte,
    com o relógio do próprio Home Assistant e tolerância de 0,08 kWh (o
    template que usa a hora é reavaliado uma vez por minuto).
  · O medidor é exercitado escrevendo o total da casa direto na máquina de
    estados (o contêiner não tem Shelly): prova o que o medidor faz com a
    fonte indo e voltando, não o que a fonte publica — isso é o item da soma.
  · O painel monitor_haos.yaml fica fora da conferência de referências: ele
    cita sensores de integrações que este contêiner não tem.
"""
from __future__ import annotations

import argparse
import datetime
import re
import sys
import time
from pathlib import Path

from check import autenticar, bootstrap, http

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "tarifas"))
import fatura as referencia  # noqa: E402 — a calculadora de referência

PACOTES = ["packages/energia_br.yaml", "packages/gas_br.yaml", "packages/agua_br.yaml"]
PAINEIS = ["dashboards/custos_br.yaml"]

# Dependências que os packages declaram e NÃO criam: vêm de integração que o
# usuário configura. Toda outra referência tem de existir na instância.
EXTERNAS = {"binary_sensor.workday_sensor"}

DOMINIOS = ("sensor|binary_sensor|input_number|input_select|input_datetime|"
            "input_boolean|input_text|select|switch|number|script|automation")
REF = re.compile(r"\b(?:%s)\.[a-z0-9_]+\b" % DOMINIOS)
# nomes de SERVIÇO têm a mesma forma de um identificador de entidade
SERVICOS = {"turn_on", "turn_off", "toggle", "select_option", "set_value",
            "set_datetime", "reload", "press", "trigger"}

POSTOS = ("peak", "shoulder", "offpeak")
MEDIDORES = ("daily_energy", "monthly_energy", "fatura_energy")
FECHA_CICLO = "energia_br_fecha_ciclo_fatura"   # o `id` da automação no package
POSTO = "energia_br_posto_tarifario"
ULTIMA = "input_datetime.fatura_ultima_leitura"
PROXIMA = "input_datetime.fatura_proxima_leitura"
FECHADO_INI = "input_datetime.fatura_fechado_inicio"
FECHADO_FIM = "input_datetime.fatura_fechado_fim"
PARAMETROS = "sensor.parametros_do_ciclo"
PARAMETROS_FECHADO = "sensor.parametros_do_ciclo_fechado"
# ajuste manual → nome do mesmo ajuste na calculadora de referência
AJUSTES = {"tarifa": "tarifa", "bandeira": "bandeira", "icms": "icms", "pis": "pis",
           "cofins": "cofins", "iluminacao": "iluminacao"}

DOMINIO_DAS_FASES = "== 'shelly'"               # como o package escolhe as fases
FASES = ["sensor.arnes_fase_a", "sensor.arnes_fase_b", "sensor.arnes_fase_c"]
DEVOLVIDA = "sensor.arnes_returned_energy"       # energia devolvida à rede: NÃO entra na soma
ATRIB_FASE = {"device_class": "energy", "state_class": "total_increasing",
              "unit_of_measurement": "kWh"}

DADOS = referencia.carrega()


def D(texto: str) -> datetime.date:
    return datetime.date.fromisoformat(texto)


def mes_seguinte(d: datetime.date) -> datetime.date:
    """O mesmo dia do mês seguinte; mês mais curto fica no último dia."""
    ano, mes = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    ultimo = (datetime.date(ano + (mes == 12), mes % 12 + 1, 1) - datetime.timedelta(days=1)).day
    return datetime.date(ano, mes, min(d.day, ultimo))


# A grade: (nome, leitura anterior, leitura, kWh ponta, intermediário, fora de
# ponta, média que define a faixa da iluminação, outros débitos, créditos).
# Cobre as três faixas do ICMS e as duas bordas, ciclo dentro de um mês de
# bandeira única e atravessando bandeiras diferentes, mês sem PIS conhecido,
# faixa da iluminação pela média e pelo consumo do ciclo, isenção e teto.
GRADE = [
    ("fatura de agosto", "2026-07-03", "2026-08-05", 10, 20, 274, 425, 2.08, 10.13),
    ("fatura de outubro", "2026-09-03", "2026-10-06", 10, 20, 324, 425, 2.08, 0.0),
    ("288 kWh, ICMS de 18 %, mês sem PIS conhecido", "2026-08-05", "2026-09-03", 30, 18, 240, 425, 2.08, 0.0),
    ("40 kWh, isento de ICMS e de iluminação", "2026-04-03", "2026-05-06", 0, 0, 40, 0, 0.0, 0.0),
    ("300 kWh, borda de baixo do ICMS", "2026-06-05", "2026-07-03", 25, 25, 250, 0, 0.0, 0.0),
    ("301 kWh, borda de cima do ICMS", "2026-06-05", "2026-07-03", 25, 25, 251, 0, 0.0, 0.0),
    ("460 kWh, iluminação pelo consumo do ciclo", "2026-09-03", "2026-10-06", 60, 40, 360, 0, 0.0, 0.0),
    ("1.200 kWh, da bandeira amarela para a verde", "2025-12-05", "2026-01-06", 150, 100, 950, 0, 0.0, 0.0),
    ("60.000 kWh, iluminação no teto", "2026-09-03", "2026-10-06", 0, 0, 60000, 0, 0.0, 0.0),
]


class Arnes:
    def __init__(self, base: str, token: str) -> None:
        self.base, self.token = base, token
        self.falhas: list[str] = []
        self.oks = 0
        self.registro: list[str] = []

    # ── fala com o HA ────────────────────────────────────────────────────────
    def get(self, caminho: str):
        return http(self.base + caminho, token=self.token)

    def post(self, caminho: str, dados):
        return http(self.base + caminho, "POST", dados, token=self.token)

    def servico(self, dominio: str, nome: str, dados: dict) -> bool:
        st, _ = self.post(f"/api/services/{dominio}/{nome}", dados)
        return st == 200

    def estado(self, eid: str) -> str | None:
        st, r = self.get(f"/api/states/{eid}")
        return r.get("state") if st == 200 and isinstance(r, dict) else None

    def atributos(self, eid: str) -> dict:
        st, r = self.get(f"/api/states/{eid}")
        return r.get("attributes", {}) if st == 200 and isinstance(r, dict) else {}

    def numero(self, eid: str) -> float | None:
        try:
            return float(self.estado(eid))  # type: ignore[arg-type]
        except (TypeError, ValueError):
            return None

    def espera_numero(self, eid: str, alvo: float, tol: float, seg: int = 25) -> float | None:
        """Template e medidor reagem a evento: dá tempo de o valor assentar."""
        visto = None
        for _ in range(seg * 2):
            visto = self.numero(eid)
            if visto is not None and abs(visto - alvo) <= tol:
                return visto
            time.sleep(0.5)
        return visto

    def template(self, texto: str) -> str:
        st, r = self.post("/api/template", {"template": texto})
        return str(r).strip() if st == 200 else f"<erro {st}: {str(r)[:120]}>"

    def poe_estado(self, eid: str, valor: str, atributos: dict | None = None) -> None:
        self.post(f"/api/states/{eid}", {"state": valor, "attributes": atributos or {}})

    def hoje(self) -> datetime.date:
        """A data do Home Assistant, não a de quem roda o arnês (fuso)."""
        return datetime.date.fromisoformat(self.template("{{ now().date().isoformat() }}"))

    def data(self, eid: str, quando: datetime.date) -> bool:
        return self.servico("input_datetime", "set_datetime",
                            {"entity_id": eid, "date": quando.isoformat()})

    def automacao(self, ident: str) -> str | None:
        """Acha a automação pelo `id` do YAML — o entity_id sai do alias."""
        st, todos = self.get("/api/states")
        for e in todos if st == 200 else []:
            if e["entity_id"].startswith("automation.") and e["attributes"].get("id") == ident:
                return e["entity_id"]
        return None

    def soma(self, prefixo: str) -> float | None:
        vs = [self.numero(f"sensor.{prefixo}_{p}") for p in POSTOS]
        return None if any(v is None for v in vs) else sum(vs)  # type: ignore[arg-type]

    def calibra(self, prefixo: str, valores) -> bool:
        ok = True
        for posto, v in zip(POSTOS, valores):
            ok &= self.servico("utility_meter", "calibrate",
                               {"entity_id": f"sensor.{prefixo}_{posto}", "value": str(v)})
        return bool(ok)

    def dispara_fechamento(self) -> bool:
        """Dispara a automação COM a condição dela."""
        eid = self.automacao(FECHA_CICLO)
        if eid is None:
            return False
        time.sleep(1)
        self.servico("automation", "trigger", {"entity_id": eid, "skip_condition": False})
        time.sleep(3)
        return True

    def fecha_ciclo(self, proxima: datetime.date, ultima: datetime.date | None = None) -> bool:
        """Informa as duas datas de leitura e dispara o fechamento."""
        ok = self.data(ULTIMA, ultima or proxima - datetime.timedelta(days=30))
        ok = self.data(PROXIMA, proxima) and ok
        return bool(ok) and self.dispara_fechamento()

    def texto(self, eid: str, valor) -> bool:
        return self.servico("input_text", "set_value", {"entity_id": eid, "value": "" if valor is None else str(valor)})

    def limpa_ajustes(self) -> bool:
        ok = True
        for nome in list(AJUSTES) + ["outros_debitos", "creditos"]:
            ok &= self.texto(f"input_text.ajuste_{nome}", "")
        return bool(ok)

    def agora(self) -> datetime.datetime:
        """O relógio do Home Assistant, no fuso dele, sem o fuso."""
        return datetime.datetime.fromisoformat(self.template("{{ now().isoformat() }}")).replace(tzinfo=None)

    def guarda_registro(self) -> None:
        """Recolhe do registro do Core o que é erro, e o aviso de variável de
        template (atributo lido de quem não existe). O registro recomeça a
        cada início: quem reinicia recolhe antes."""
        st, texto = self.get("/api/error_log")
        if st != 200 or not isinstance(texto, str):
            self.registro.append(f"não consegui ler o registro do Core (HTTP {st})")
            return
        for linha in texto.splitlines():
            m = re.match(r"^\S+ \S+ (ERROR|WARNING) \([^)]*\) \[([^\]]+)\] (.*)", linha)
            if m and (m.group(1) == "ERROR" or m.group(2).startswith("homeassistant.helpers.template")):
                self.registro.append(f"{m.group(1)} [{m.group(2)}] {m.group(3)[:200]}")

    def p(self, eid: str) -> dict:
        """O dicionário de parâmetros que o sensor do ciclo publica."""
        v = self.atributos(eid).get("p")
        return v if isinstance(v, dict) else {}

    # ── placar ───────────────────────────────────────────────────────────────
    def ok(self, texto: str) -> None:
        self.oks += 1
        print(f"[OK]    {texto}")

    def falha(self, token: str, texto: str) -> None:
        self.falhas.append(token)
        print(f"[ERRO]  {token}: {texto}")


def carrega_yaml(rel: str) -> dict:
    try:
        import yaml  # type: ignore
    except ImportError:
        raise SystemExit("[ERRO] PyYAML ausente. Local: pip install pyyaml") from None
    return yaml.safe_load((RAIZ / rel).read_text(encoding="utf-8")) or {}


def sensor_do_pacote(pacote: dict, unique_id: str) -> dict:
    for bloco in pacote.get("template", []) or []:
        for s in bloco.get("sensor", []) or []:
            if s.get("unique_id") == unique_id:
                return s
    return {}


def campos_dos_pacotes() -> list[tuple[str, str, dict]]:
    """(domínio, chave, configuração) de todo campo que o usuário preenche."""
    achados = []
    for rel in PACOTES:
        pacote = carrega_yaml(rel)
        for dominio in ("input_number", "input_select", "input_datetime", "input_text", "input_boolean"):
            for chave, cfg in (pacote.get(dominio) or {}).items():
                achados.append((dominio, chave, cfg or {}))
    return achados


# ── 0. o estado de fábrica: instalação nova não inventa número ──────────────
def confere_fabrica(a: Arnes) -> None:
    token = "ESTADO DE FABRICA"
    antes = len(a.falhas)
    n = 0
    for dominio, chave, _ in campos_dos_pacotes():
        if dominio == "input_number":
            n += 1
            v = a.numero(f"input_number.{chave}")
            if v != 0:
                a.falha(token, f"input_number.{chave} nasce em {v} numa instalação nova (campo sem "
                               "valor inicial nasce no `min:` — o mínimo tem de ser zero)")
        elif dominio == "input_text":
            n += 1
            v = a.estado(f"input_text.{chave}")
            if v not in ("", "unknown"):
                a.falha(token, f"input_text.{chave} nasce com {v!r} — um ajuste manual não pode vir preenchido")
    for eid in ("sensor.encargos_fixos_do_mes", "sensor.fatura_mensal_convencional",
                "sensor.fatura_mensal_branca", "sensor.fatura_projetada_do_ciclo", "sensor.ajustes_ativos"):
        v = a.numero(eid)
        if v != 0:
            a.falha(token, f"{eid} mostra {v} antes de haver consumo ou ajuste (esperava 0)")
    for eid in ("sensor.fatura_do_ciclo_fechado", "sensor.desvio_da_conferencia"):
        v = a.estado(eid)
        if v != "unavailable":
            a.falha(token, f"{eid} mostra {v} antes do primeiro fechamento de ciclo "
                           "(não há ciclo fechado: deveria estar indisponível)")
    if a.estado(ULTIMA) != a.estado(PROXIMA):
        a.falha(token, "as duas datas de leitura nascem diferentes — a automação poderia "
                       "fechar um ciclo que o usuário nunca informou")
    preco = a.numero("sensor.preco_convencional")
    if preco is None or not 0.5 < preco < 3:
        a.falha(token, f"sem nenhum ajuste, o preço do kWh deveria sair do arquivo de dados; veio {preco}")
    if len(a.falhas) == antes:
        a.ok(f"instalação nova: {n} campos vazios ou em zero, faturas em zero, preço padrão {preco:.5f}, "
             "ciclo fechado indisponível")


# ── 1. toda referência existe ───────────────────────────────────────────────
def confere_referencias(a: Arnes) -> None:
    st, todos = a.get("/api/states")
    existentes = {e["entity_id"] for e in todos} if st == 200 else set()
    total = 0
    antes = len(a.falhas)
    for rel in PACOTES + PAINEIS:
        for n, linha in enumerate((RAIZ / rel).read_text(encoding="utf-8").splitlines(), 1):
            if linha.lstrip().startswith("#"):
                continue
            for eid in REF.findall(linha):
                if eid.split(".", 1)[1] in SERVICOS or eid in EXTERNAS:
                    continue
                total += 1
                if eid not in existentes:
                    a.falha("REFERENCIA INEXISTENTE", f"{eid} em {rel}:{n}")
    if len(a.falhas) == antes:
        a.ok(f"{total} referências em {len(PACOTES + PAINEIS)} arquivos, todas existem na instância")


# ── 2. a soma não é publicada com fase sem valor ────────────────────────────
def cria_fases(a: Arnes) -> bool:
    """Três sensores de energia REGISTRADOS, cada um com a sua entrada de
    configuração — é assim que uma fase de verdade existe para o registro."""
    for nome in ("Arnes Fase A", "Arnes Fase B", "Arnes Fase C", "Arnes Returned Energy"):
        st, r = a.post("/api/config/config_entries/flow", {"handler": "template"})
        if st != 200 or not isinstance(r, dict) or "flow_id" not in r:
            return False
        fluxo = r["flow_id"]
        st, r = a.post(f"/api/config/config_entries/flow/{fluxo}", {"next_step_id": "sensor"})
        if st != 200:
            return False
        st, r = a.post(f"/api/config/config_entries/flow/{fluxo}", {
            "name": nome, "state": "{{ 0 }}", "unit_of_measurement": "kWh",
            "device_class": "energy", "state_class": "total_increasing"})
        if st != 200 or not isinstance(r, dict) or r.get("type") != "create_entry":
            return False
    for _ in range(20):
        if all(a.estado(f) is not None for f in FASES + [DEVOLVIDA]):
            return True
        time.sleep(0.5)
    return False


def confere_soma(a: Arnes) -> None:
    token = "SOMA PARCIAL"
    sensor = sensor_do_pacote(carrega_yaml("packages/energia_br.yaml"), "energy_total")
    disp, soma = str(sensor.get("availability", "")), str(sensor.get("state", ""))
    if DOMINIO_DAS_FASES not in disp or DOMINIO_DAS_FASES not in soma:
        a.falha(token, "o total da casa não escolhe as fases pelo domínio da entrada de "
                       "configuração no registro — a lista de entidades VIVAS de uma integração "
                       "perde as fases uma a uma numa recarga, e a soma das que sobram passa por total")
        return
    if not cria_fases(a):
        a.falha(token, "não consegui criar as três fases de teste no Home Assistant")
        return
    disp_t = disp.replace(DOMINIO_DAS_FASES, "== 'template'")
    soma_t = soma.replace(DOMINIO_DAS_FASES, "== 'template'")

    def cena(valores: list[str], extra: dict | None = None) -> tuple[str, str]:
        for fase, v in zip(FASES, valores):
            atr = dict(ATRIB_FASE)
            if v == "unavailable" and extra:
                atr.update(extra)
            a.poe_estado(fase, v, atr)
        a.poe_estado(DEVOLVIDA, "50", ATRIB_FASE)   # sempre respondendo, sempre fora da conta
        time.sleep(0.3)
        return a.template(disp_t), a.template(soma_t)

    antes = len(a.falhas)
    d, s = cena(["100", "200", "300"])
    try:
        completo = d == "True" and abs(float(s) - 600) <= 0.001
    except ValueError:
        completo = False
    if not completo:
        a.falha(token, f"com as três fases respondendo esperava disponível e 600; veio {d} e {s} "
                       "(650 = a energia devolvida à rede entrou na soma)")
    for rotulo, valores, extra in (
            ("uma fase indisponível", ["100", "unavailable", "300"], None),
            ("uma fase restaurada do registro, como numa recarga da integração",
             ["unavailable", "200", "300"], {"restored": True}),
            ("uma fase desconhecida", ["unknown", "200", "300"], None),
            ("as três sem valor", ["unavailable"] * 3, None)):
        d, s = cena(valores, extra)
        if d != "False":
            a.falha(token, f"com {rotulo} o total continuou disponível e publicaria {s}")
    if a.template(disp.replace(DOMINIO_DAS_FASES, "== 'dominio_que_nao_existe'")) != "False":
        a.falha(token, "sem nenhuma fase descoberta o total continuou disponível")
    if len(a.falhas) == antes:
        a.ok("total da casa: fases achadas pelo registro; disponível só com todas numéricas (6 cenários)")


# ── 3. cada número do Home Assistant é o da calculadora de referência ───────
CONTA = 100.0   # o "total da conta" digitado em toda a grade: o desvio é total − 100

PARES = (("bandeira", 5e-7, "bandeira do ciclo"), ("icms", 1e-9, "ICMS"), ("pis", 1e-9, "PIS"),
         ("cofins", 1e-9, "COFINS"), ("preco", 5e-7, "preço do kWh"), ("iluminacao", 0.001, "iluminação pública"))


def prepara_ciclo(a: Arnes, caso, ajustes: dict | None = None) -> dict | None:
    """Põe o caso no ciclo EM CURSO e devolve o que a referência calcula."""
    nome, ini, fim, ponta, inter, fora, media, outros, creditos = caso
    ok = a.limpa_ajustes()
    for chave, valor in (ajustes or {}).items():
        ok &= a.texto(f"input_text.ajuste_{chave}", valor)
    ok &= a.texto("input_text.ajuste_outros_debitos", outros if outros else "")
    ok &= a.texto("input_text.ajuste_creditos", creditos if creditos else "")
    ok &= a.servico("input_number", "set_value", {"entity_id": "input_number.cosip_media_kwh", "value": media})
    ok &= a.servico("input_number", "set_value", {"entity_id": "input_number.fatura_conferencia", "value": CONTA})
    ok &= a.data(ULTIMA, D(ini)) and a.data(PROXIMA, D(fim))
    ok &= a.calibra("fatura_energy", (ponta, inter, fora))
    if not ok:
        return None
    return referencia.calcula(DADOS, D(ini), D(fim), ponta + inter + fora, kwh_ponta=ponta,
                              kwh_intermediario=inter, cosip_media_kwh=media, outros_debitos=outros,
                              creditos=creditos,
                              ajustes={AJUSTES[k]: float(str(v).replace(",", "."))
                                       for k, v in (ajustes or {}).items()})


def compara(a: Arnes, token: str, nome: str, pares) -> bool:
    for eid, alvo, tol, que in pares:
        v = a.espera_numero(eid, alvo, tol, 12)
        if v is None or abs(v - alvo) > tol:
            a.falha(token, f"{nome}: {que} ({eid}) — a calculadora dá {alvo:.5f}, o Home Assistant {v}")
            return False
    return True


def compara_parametros(a: Arnes, token: str, nome: str, eid: str, r: dict) -> bool:
    for _ in range(24):
        p = a.p(eid)
        if p and all(abs(float(p.get(k, 1e9)) - r[k]) <= tol for k, tol, _ in PARES):
            break
        time.sleep(0.5)
    p = a.p(eid)
    for chave, tol, que in PARES:
        if chave not in p or abs(float(p[chave]) - r[chave]) > tol:
            a.falha(token, f"{nome}: {que} — a calculadora dá {r[chave]:.6f}, o Home Assistant {p.get(chave)}")
            return False
    if bool(p.get("estimado")) != r["estimado"]:
        a.falha(token, f"{nome}: a calculadora marca estimado={r['estimado']} e o Home Assistant {p.get('estimado')}")
        return False
    return True


def confere_formulas(a: Arnes) -> None:
    token = "FORMULA DIVERGE"
    antes = len(a.falhas)
    feitos = 0
    for caso in GRADE:
        nome, ini, fim, ponta, inter, fora, *_ = caso
        r = prepara_ciclo(a, caso)
        if r is None:
            a.falha(token, f"{nome}: o Home Assistant recusou datas, ajustes ou medidor do ciclo "
                           "(entidade do cálculo por consumo inexistente)")
            return
        kwh = ponta + inter + fora
        # ciclo em curso (as datas já passaram, então projeção = consumo)
        if not compara_parametros(a, token, nome + ", em curso", PARAMETROS, r):
            continue
        if not compara(a, token, nome + ", em curso", (
                ("sensor.consumo_do_ciclo", kwh, 0.001, "consumo"),
                ("sensor.fatura_mensal_convencional", r["total"], 0.0051, "fatura"),
                ("sensor.fatura_projetada_do_ciclo", r["total"], 0.0051, "fatura projetada"),
                ("sensor.fatura_mensal_branca", r["total_branca"], 0.0051, "fatura na Tarifa Branca"))):
            continue
        # ciclo fechado: os mesmos números têm de sobreviver ao fechamento
        if not a.dispara_fechamento():
            a.falha(token, f"{nome}: não há automação de fechamento")
            return
        if not compara_parametros(a, token, nome + ", fechado", PARAMETROS_FECHADO, r):
            continue
        if not compara(a, token, nome + ", fechado", (
                ("sensor.consumo_do_ciclo_fechado", kwh, 0.001, "consumo"),
                ("sensor.fatura_do_ciclo_fechado", r["total"], 0.0051, "fatura"),
                ("sensor.fatura_icms", r["icms_valor"], 0.0051, "ICMS em reais"),
                ("sensor.fatura_pis", r["pis_valor"], 0.0051, "PIS em reais"),
                ("sensor.fatura_cofins", r["cofins_valor"], 0.0051, "COFINS em reais"),
                ("sensor.desvio_da_conferencia", r["total"] - CONTA, 0.0051, "diferença para a conta digitada"))):
            continue
        feitos += 1
    # as duas faturas reais: além de igual à calculadora, a um centavo da conta
    for caso, conta in zip(GRADE[:2], DADOS["casos_de_conferencia"]):
        r = referencia.calcula(DADOS, D(caso[1]), D(caso[2]), sum(caso[3:6]), cosip_media_kwh=caso[6],
                               outros_debitos=caso[7], creditos=caso[8])
        if abs(r["total"] - conta["esperado"]["total"]) > 0.0101:
            a.falha(token, f"{caso[0]}: a calculadora dá {r['total']:.2f} e a conta {conta['esperado']['total']:.2f}")
    confere_projecao(a, token)
    if len(a.falhas) == antes:
        a.ok(f"{feitos} ciclos: bandeira, ICMS, PIS, COFINS, preço, iluminação, impostos em reais e totais "
             "iguais aos da calculadora, em curso e fechados")


def confere_projecao(a: Arnes, token: str) -> None:
    """Ciclo que ainda corre: as faixas saem do consumo PROJETADO, não do já
    medido. 120 kWh em 10 dias de 30 fecham acima de 300: ICMS de 24 %."""
    hoje = a.hoje()
    ini, fim = hoje - datetime.timedelta(days=10), hoje + datetime.timedelta(days=20)
    for nome, anterior in (("sem ciclo anterior", 0), ("com ciclo anterior de 900 kWh em 30 dias", 900)):
        # o ciclo anterior: fecha um de 30 dias com o consumo dado
        a.limpa_ajustes()
        a.servico("input_number", "set_value", {"entity_id": "input_number.cosip_media_kwh", "value": 0})
        a.calibra("fatura_energy", (0, 0, anterior))
        a.fecha_ciclo(ini, ini - datetime.timedelta(days=30))
        a.data(ULTIMA, ini)
        a.data(PROXIMA, fim)
        a.calibra("fatura_energy", (10, 10, 100))
        time.sleep(2)
        proj = referencia.consumo_projetado(120, ini, fim, a.agora(), fechado_kwh=anterior,
                                            fechado_dias=30 if anterior else 0)
        v = a.espera_numero("sensor.consumo_projetado_do_ciclo", proj, 0.08, 12)
        if v is None or abs(v - proj) > 0.08:
            a.falha(token, f"consumo projetado, {nome}: a calculadora dá {proj:.3f} kWh, o Home Assistant {v}")
            continue
        r = referencia.calcula(DADOS, ini, fim, 120, kwh_ponta=10, kwh_intermediario=10, kwh_faixa=v)
        if r["icms"] != 24.0:
            raise SystemExit("[ERRO] o cenário da projeção deixou de atravessar a faixa do ICMS")
        if not compara_parametros(a, token, f"ciclo em curso, {nome}", PARAMETROS, r):
            continue
        rp = referencia.calcula(DADOS, ini, fim, v, kwh_faixa=v)
        compara(a, token, f"ciclo em curso, {nome}", (
            ("sensor.fatura_mensal_convencional", r["total"], 0.0051, "fatura até agora"),
            ("sensor.fatura_projetada_do_ciclo", rp["total"], 0.0051, "fatura projetada")))


# ── 4. o ajuste manual vale; apagado, volta o padrão ────────────────────────
def confere_ajustes(a: Arnes) -> None:
    token = "AJUSTE IGNORADO"
    antes = len(a.falhas)
    caso = GRADE[1]
    padrao = prepara_ciclo(a, caso)
    if padrao is None or not compara_parametros(a, token, "sem ajuste", PARAMETROS, padrao):
        if padrao is None:
            a.falha(token, "os campos de ajuste manual não existem")
        return
    # a vírgula é como o dono digita: tem de valer igual ao ponto
    valores = {"tarifa": 0.91357, "bandeira": 0.02113, "icms": 20.0, "pis": "1,47", "cofins": 6.11,
               "iluminacao": "51,37"}
    for chave, valor in valores.items():
        r = prepara_ciclo(a, caso, {chave: valor})
        if not compara_parametros(a, token, f"ajuste de {chave} = {valor}", PARAMETROS, r):
            continue
        compara(a, token, f"ajuste de {chave} = {valor}",
                (("sensor.fatura_mensal_convencional", r["total"], 0.0051, "fatura"),
                 ("sensor.ajustes_ativos", 2 if caso[7] else 1, 0, "contagem de ajustes ativos")))
    # texto que o campo aceita e não é número não é ajuste: vale o padrão
    prepara_ciclo(a, caso)
    a.texto("input_text.ajuste_pis", ".")
    time.sleep(1)
    if a.estado("input_text.ajuste_pis") != ".":
        a.falha(token, "o campo de ajuste recusou '.', e a guarda do template contra texto que não é "
                       "número ficou sem exercício")
    compara_parametros(a, token, "ajuste com texto que não é número", PARAMETROS, padrao)
    compara(a, token, "ajuste com texto que não é número",
            (("sensor.ajustes_ativos", 1, 0, "contagem de ajustes ativos"),))
    # apagado, volta o padrão
    prepara_ciclo(a, caso)
    compara_parametros(a, token, "ajustes apagados", PARAMETROS, padrao)
    if len(a.falhas) == antes:
        a.ok(f"{len(valores)} ajustes manuais: preenchido vale o do dono; apagado ou inválido, volta o padrão")


# ── 5. o que o dono digita sobrevive ao reinício ────────────────────────────
# Valores que NÃO coincidem com nenhum padrão plausível: um `initial:` de volta
# num campo com o mesmo número passaria despercebido.
PERSISTEM = [
    ("input_text", "ajuste_tarifa", "0.91357"),
    ("input_text", "ajuste_bandeira", "0.02113"),
    ("input_text", "ajuste_icms", "23.57"),
    ("input_text", "ajuste_pis", "1,13"),
    ("input_text", "ajuste_cofins", "4.91"),
    ("input_text", "ajuste_iluminacao", "61.37"),
    ("input_text", "ajuste_outros_debitos", "2.71"),
    ("input_text", "ajuste_creditos", "3.21"),
    ("input_number", "cosip_media_kwh", 437.0),
    ("input_number", "fatura_conferencia", 537.19),
    ("input_number", "gas_consumo_ciclo_m3", 23.0),
    ("input_number", "gas_fator_correcao", 1.02913),
    ("input_number", "gas_fatura_conferencia", 251.33),
    ("input_number", "agua_consumo_m3", 17.0),
    ("input_number", "agua_valor_condominio", 298.77),
]
DATAS = ("fatura_proxima_leitura", "fatura_ultima_leitura", "fatura_fechado_inicio", "fatura_fechado_fim")


def confere_persistencia(a: Arnes, espera_volta) -> None:
    token = "CAMPO NAO PERSISTE"
    antes = len(a.falhas)
    # a) nenhum campo declara valor inicial — com ele o HA não restaura
    cobertos = {(d, c) for d, c, _ in PERSISTEM} | {("input_datetime", c) for c in DATAS} | {
        ("input_select", "agua_area")}
    for dominio, chave, cfg in campos_dos_pacotes():
        if "initial" in cfg:
            a.falha(token, f"{dominio}.{chave} declara `initial:` — o que o usuário digita seria "
                           "descartado a cada início")
        if (dominio, chave) not in cobertos:
            a.falha(token, f"{dominio}.{chave} é campo novo e o arnês não o exercita no reinício")

    # b) digitar, reiniciar, reler. A mesma parada prova o fechamento do ciclo
    #    no INÍCIO: leitura com data passada, Home Assistant parado na hora.
    #    As duas datas de leitura persistem se o ciclo fechado as recebe.
    ontem = a.hoje() - datetime.timedelta(days=1)
    anterior = ontem - datetime.timedelta(days=30)
    for dominio, campo, valor in PERSISTEM:
        a.servico(dominio, "set_value", {"entity_id": f"{dominio}.{campo}", "value": valor})
    a.servico("input_select", "select_option",
              {"entity_id": "input_select.agua_area", "option": "Área B"})
    a.calibra("fatura_energy", (11, 11, 11))
    a.data(ULTIMA, anterior)
    a.data(PROXIMA, ontem)
    time.sleep(2)
    a.guarda_registro()
    a.servico("homeassistant", "restart", {})
    if not espera_volta():
        a.falha(token, "o Home Assistant não voltou do reinício")
        return
    for dominio, campo, valor in PERSISTEM:
        if dominio == "input_text":
            v = a.estado(f"{dominio}.{campo}")
            if v != valor:
                a.falha(token, f"{dominio}.{campo}: digitado {valor!r}, depois do reinício {v!r}")
            continue
        v = a.numero(f"{dominio}.{campo}")
        if v is None or abs(v - valor) > 1e-6:
            a.falha(token, f"{dominio}.{campo}: digitado {valor}, depois do reinício {v}")
    if a.estado("input_select.agua_area") != "Área B":
        a.falha(token, "input_select.agua_area: escolhido Área B, depois do "
                f"reinício {a.estado('input_select.agua_area')}")

    for _ in range(40):
        if a.soma("fatura_energy") == 0 and a.estado(FECHADO_FIM) == ontem.isoformat():
            break
        time.sleep(0.5)
    datas = {"início do ciclo fechado": (FECHADO_INI, anterior), "fim do ciclo fechado": (FECHADO_FIM, ontem)}
    for que, (eid, alvo) in datas.items():
        if a.estado(eid) != alvo.isoformat():
            a.falha(token, f"{que} ({eid}): a data de leitura digitada antes do reinício era "
                           f"{alvo.isoformat()}, e depois dele o ciclo fechou com {a.estado(eid)}")
    if len(a.falhas) == antes:
        a.ok(f"{len(PERSISTEM) + 3} campos do dono mantiveram o valor depois de um reinício; nenhum com valor inicial")

    antes = len(a.falhas)
    if a.soma("fatura_energy") != 0:
        a.falha("CICLO NAO ZERA", "a leitura já tinha passado quando o Home Assistant iniciou e o "
                                  f"ciclo não fechou no início: o medidor da fatura mostra {a.soma('fatura_energy')}")
    elif a.estado(ULTIMA) != ontem.isoformat():
        a.falha("CICLO NAO ZERA", "o ciclo fechou no início mas a data da última leitura não foi gravada")
    if len(a.falhas) == antes:
        a.ok("ciclo da fatura: fecha no primeiro início depois da data de leitura")


# ── 6. o ciclo fecha na data da leitura, uma vez, e só o medidor da fatura ──
def confere_ciclo(a: Arnes) -> None:
    token = "CICLO NAO ZERA"
    # o gatilho da meia-noite não dá para disparar sem mexer no relógio:
    # confere-se que ele e o do início estão no arquivo, e que não há outro
    # horário (um fechamento ao meio-dia parte o dia da leitura em dois).
    auto = next((x for x in carrega_yaml("packages/energia_br.yaml").get("automation", [])
                 if x.get("id") == FECHA_CICLO), {})
    gatilhos = auto.get("trigger") or auto.get("triggers") or []
    horas = [str(g.get("at")) for g in gatilhos if (g.get("platform") or g.get("trigger")) == "time"]
    tem_inicio = any((g.get("platform") or g.get("trigger")) == "homeassistant" and g.get("event") == "start"
                     for g in gatilhos)
    if horas != ["00:00:00"] or not tem_inicio:
        a.falha(token, "a automação de fechamento tem de disparar à meia-noite e no início do Home "
                       f"Assistant, e só neles (horários: {horas}, início={tem_inicio})")
        return

    hoje = a.hoje()
    if not (a.calibra("fatura_energy", (40, 40, 40)) and a.calibra("monthly_energy", (7, 7, 7))
            and a.fecha_ciclo(hoje + datetime.timedelta(days=5))):
        a.falha(token, "medidor da fatura, automação de fechamento ou datas de leitura inexistentes")
        return
    if a.soma("fatura_energy") != 120:
        a.falha(token, "com a leitura só daqui a 5 dias o medidor da fatura mudou: "
                       f"{a.soma('fatura_energy')} (esperava 120)")
        return
    # a data de leitura é HOJE: o dia inteiro já é do ciclo novo
    anterior = hoje - datetime.timedelta(days=30)
    a.fecha_ciclo(hoje, anterior)
    f, m = a.soma("fatura_energy"), a.soma("monthly_energy")
    if f != 0:
        a.falha(token, f"a data de leitura é hoje e o medidor da fatura não zerou: {f} "
                       "(o ciclo fecha à meia-noite da data de leitura)")
        return
    if m != 21:
        a.falha(token, f"o fechamento do ciclo mexeu no medidor de calendário: {m} (esperava 21)")
        return
    if a.estado(ULTIMA) != hoje.isoformat():
        a.falha(token, "o ciclo zerou mas a data da última leitura não foi gravada: "
                       f"{a.estado(ULTIMA)} (esperava {hoje.isoformat()})")
        return
    if (a.estado(FECHADO_INI), a.estado(FECHADO_FIM)) != (anterior.isoformat(), hoje.isoformat()):
        a.falha(token, "o ciclo fechou sem guardar as duas datas dele: "
                       f"{a.estado(FECHADO_INI)} → {a.estado(FECHADO_FIM)} "
                       f"(esperava {anterior.isoformat()} → {hoje.isoformat()})")
        return
    if a.estado(PROXIMA) != mes_seguinte(hoje).isoformat():
        a.falha(token, f"fechado o ciclo, a próxima leitura deveria passar a {mes_seguinte(hoje).isoformat()} "
                       f"(um mês depois); ficou em {a.estado(PROXIMA)}")
        return
    # não fecha duas vezes: o consumo novo fica, o ciclo fechado também
    a.calibra("fatura_energy", (5, 5, 5))
    a.dispara_fechamento()
    guardado = a.numero("sensor.consumo_do_ciclo_fechado")
    if a.soma("fatura_energy") != 15 or guardado != 120:
        a.falha(token, "o mesmo ciclo fechou de novo: o medidor da fatura foi a "
                       f"{a.soma('fatura_energy')} (esperava 15) e o ciclo fechado a {guardado} (esperava 120)")
        return
    # o dono corrige a próxima leitura: a data dele vale
    corrigida = hoje + datetime.timedelta(days=27)
    a.data(PROXIMA, corrigida)
    a.dispara_fechamento()
    if a.estado(PROXIMA) != corrigida.isoformat() or a.soma("fatura_energy") != 15:
        a.falha(token, "a próxima leitura corrigida pelo dono não foi respeitada")
        return
    a.ok("ciclo da fatura: não zera antes da data; zera à meia-noite dela, uma vez; guarda as duas "
         "datas; assume a próxima um mês depois; só o medidor da fatura")


# ── 6b. a fonte some e volta: o medidor não perde nem inventa consumo ───────
def confere_medidor(a: Arnes) -> None:
    token = "MEDIDOR NAO ACOMPANHA"
    total = "sensor.energy_total"
    atrib = {"device_class": "energy", "state_class": "total_increasing",
             "unit_of_measurement": "kWh"}
    antes = len(a.falhas)
    for m in MEDIDORES:
        a.calibra(m, (0, 0, 0))
    for valor in ("1000", "1001"):
        a.poe_estado(total, valor, atrib)
        time.sleep(1)
    andou = {m: a.soma(m) for m in MEDIDORES}
    a.poe_estado(total, "unavailable", atrib)
    time.sleep(1)
    durante = {m: a.soma(m) for m in MEDIDORES}
    a.poe_estado(total, "1003", atrib)
    time.sleep(1)
    depois = {m: a.soma(m) for m in MEDIDORES}
    a.poe_estado(total, "unavailable", atrib)
    for m in MEDIDORES:
        if andou[m] != 1:
            a.falha(token, f"{m}: 1000 → 1001 kWh deveria somar 1; o medidor mostra {andou[m]}")
        elif durante[m] != 1:
            a.falha(token, f"{m}: com o total da casa indisponível o medidor deixou de mostrar o valor ({durante[m]})")
        elif depois[m] != 3:
            a.falha(token, f"{m}: o total sumiu em 1001 e voltou em 1003: o medidor deveria ir a 3 "
                           f"(os 2 kWh do intervalo são consumo), e foi a {depois[m]}")
    # Os três medidores trocam de posto JUNTOS. Todo seletor nasce no primeiro
    # posto da lista; a automação, ao iniciar, leva-os ao posto da hora. Um
    # medidor fora da lista dela ficaria para trás, com todo o consumo do
    # ciclo no posto errado.
    postos = {m: a.estado(f"select.{m}") for m in MEDIDORES}
    if len(set(postos.values())) != 1 or None in postos.values():
        a.falha(token, f"os medidores não estão no mesmo posto tarifário: {postos}")
    if len(a.falhas) == antes:
        a.ok("medidores (diário, mensal, da fatura): no mesmo posto; visíveis com a fonte fora; na volta somam só o intervalo")


# ── 6c. os horários dos postos são os do arquivo de dados ───────────────────
def confere_postos(a: Arnes) -> None:
    token = "MEDIDOR NAO ACOMPANHA"
    auto = next((x for x in carrega_yaml("packages/energia_br.yaml").get("automation", [])
                 if x.get("id") == POSTO), {})
    gatilhos = auto.get("trigger") or auto.get("triggers") or []
    achado = sorted((str(g.get("at"))[:5], (g.get("variables") or {}).get("posto"))
                    for g in gatilhos if (g.get("platform") or g.get("trigger")) == "time")
    po = DADOS["postos"]
    esperado = sorted([(po["ponta_inicio"], "peak"), (po["ponta_fim"], "shoulder"),
                       (po["intermediario_fim"], "offpeak")])
    if achado != esperado:
        a.falha(token, f"os horários dos postos na automação ({achado}) não são os do arquivo de dados ({esperado})")
    else:
        a.ok(f"postos tarifários: ponta {po['ponta_inicio']}–{po['ponta_fim']}, intermediário até "
             f"{po['intermediario_fim']}, como no arquivo de dados")


# ── 8. o Core não registrou erro enquanto os packages trabalhavam ───────────
def confere_registro(a: Arnes) -> None:
    a.guarda_registro()
    if a.registro:
        for linha in sorted(set(a.registro)):
            a.falha("ERRO NO REGISTRO", linha)
    else:
        a.ok("registro do Core: nenhum erro e nenhum aviso de variável de template, antes e depois do reinício")


# ── 7. água e gás devolvem os exemplos validados ────────────────────────────
def confere_agua_e_gas(a: Arnes) -> None:
    a.servico("input_select", "select_option", {"entity_id": "input_select.agua_area", "option": "Área A"})
    a.servico("input_number", "set_value", {"entity_id": "input_number.agua_consumo_m3", "value": 21})
    a.servico("input_number", "set_value", {"entity_id": "input_number.agua_valor_condominio", "value": 356.39})
    ruins = []
    for e, alvo, tol in (("sensor.agua_e_esgoto_simulado", 419.40, 0.011),
                         ("sensor.agua_diferenca_vs_condominio", -63.01, 0.011),
                         ("sensor.agua_preco_efetivo_concessionaria", 19.9714, 0.0006),
                         ("sensor.agua_preco_efetivo_condominio", 16.971, 0.0006)):
        v = a.espera_numero(e, alvo, tol, 10)
        if v is None or abs(v - alvo) > tol:
            ruins.append((e, alvo, v))
    if ruins:
        for e, alvo, v in ruins:
            a.falha("AGUA NAO REPRODUZ", f"{e} deveria ser {alvo}; veio {v}")
    else:
        a.ok("água: 21 m³ na Área A → 419,40 simulado, −63,01 contra o condomínio")

    a.servico("input_number", "set_value", {"entity_id": "input_number.gas_consumo_ciclo_m3", "value": 19})
    a.servico("input_number", "set_value", {"entity_id": "input_number.gas_fator_correcao", "value": 1.03372})
    a.servico("input_number", "set_value", {"entity_id": "input_number.gas_fatura_conferencia", "value": 229.01})
    ruins = []
    for e, alvo, tol in (("sensor.gas_volume_corrigido", 20, 0.001),
                         ("sensor.gas_custo_fornecimento", 229.01, 0.011),
                         ("sensor.gas_desvio_da_conferencia", 0.0, 0.011),
                         ("sensor.gas_tributos_total", 46.12, 0.021)):
        v = a.espera_numero(e, alvo, tol, 10)
        if v is None or abs(v - alvo) > tol:
            ruins.append((e, alvo, v))
    if ruins:
        for e, alvo, v in ruins:
            a.falha("GAS NAO REPRODUZ", f"{e} deveria ser {alvo}; veio {v}")
    else:
        a.ok("gás: 19 m³ × 1,03372 → 20 m³ faturados, 229,01, desvio zero")


def main() -> int:
    ap = argparse.ArgumentParser(description="Arnês dos packages BR")
    ap.add_argument("--url", required=True)
    ap.add_argument("--user")
    ap.add_argument("--pass", dest="senha")
    ap.add_argument("--bootstrap", action="store_true",
                    help="instância nova: cria o primeiro admin via onboarding")
    a_ = ap.parse_args()
    base = a_.url.rstrip("/")
    if a_.bootstrap:
        token = bootstrap(base, a_.user or "ci", a_.senha or "ci-senha-de-teste-0123")
    elif a_.user and a_.senha:
        token = autenticar(base, a_.user, a_.senha)
    else:
        raise SystemExit("[ERRO] informe --user/--pass ou --bootstrap")

    a = Arnes(base, token)

    def rodando(voltas: int) -> bool:
        for _ in range(voltas):
            s, r = a.get("/api/config")
            if s == 200 and isinstance(r, dict) and r.get("state") == "RUNNING":
                return True
            time.sleep(2)
        return False

    def espera_volta() -> bool:
        time.sleep(8)  # dar tempo de o Core CAIR: um GET imediato acerta o velho
        if not rodando(150):
            return False
        time.sleep(3)
        return True

    # o HTTP responde antes de os packages terminarem de carregar
    if not rodando(90):
        print("[ERRO]  o Home Assistant não chegou ao estado RUNNING")
        return 3
    _, cfg = a.get("/api/config")
    print(f"alvo: HA {cfg.get('version', '?') if isinstance(cfg, dict) else '?'}")

    confere_fabrica(a)          # tem de ser a primeira: lê antes de qualquer escrita
    confere_referencias(a)
    confere_soma(a)
    confere_persistencia(a, espera_volta)
    confere_formulas(a)
    confere_ajustes(a)
    confere_ciclo(a)
    confere_medidor(a)
    confere_postos(a)
    confere_agua_e_gas(a)
    confere_registro(a)

    if a.falhas:
        resumo = ", ".join(sorted(set(a.falhas)))
        print(f"\nRESULTADO: {a.oks} garantia(s) íntegra(s) · {len(a.falhas)} falha(s) — {resumo}")
        return 3
    print(f"\nPACOTES OK — {a.oks} garantias conferidas contra o Home Assistant")
    return 0


if __name__ == "__main__":
    sys.exit(main())
