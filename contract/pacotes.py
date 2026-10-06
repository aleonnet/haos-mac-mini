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
  · A comparação bit a bit (regra, projeção, próxima leitura) avalia o TEXTO
    do package no motor do Home Assistant com as entradas trocadas por
    variáveis: prova a conta, não a leitura das entradas — essa é a grade de
    ciclos, com as entidades.
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
import ast
import datetime
import json
import random
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
MEDIDO_DESDE = "input_datetime.fatura_medido_desde"
DIAS_MEDIDOS = "input_number.fatura_fechado_dias_medidos"
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


def proxima_depois_de(leitura: datetime.date, hoje: datetime.date) -> datetime.date:
    """O mesmo dia do mês seguinte ao da leitura (mês mais curto: o último
    dia); se essa data já passou, o primeiro mês que ainda não chegou."""
    for k in range(1, 121):
        t = leitura.month - 1 + k
        ano, mes = leitura.year + t // 12, t % 12 + 1
        ultimo = (datetime.date(ano + (mes == 12), mes % 12 + 1, 1) - datetime.timedelta(days=1)).day
        candidata = datetime.date(ano, mes, min(leitura.day, ultimo))
        if candidata > hoje:
            return candidata
    raise ValueError(leitura)


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
    ("300,4 kWh, que contam como 300", "2026-06-05", "2026-07-03", 25.2, 25.1, 250.1, 0, 0.0, 0.0),
    ("300,6 kWh, que contam como 301", "2026-06-05", "2026-07-03", 25.2, 25.1, 250.3, 0, 0.0, 0.0),
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

    def data_hora(self, eid: str, quando: datetime.datetime) -> bool:
        return self.servico("input_datetime", "set_datetime",
                            {"entity_id": eid, "datetime": quando.strftime("%Y-%m-%d %H:%M:%S")})

    def espera_estado(self, eid: str, alvo: str, seg: int = 12) -> str | None:
        visto = None
        for _ in range(seg * 2):
            visto = self.estado(eid)
            if visto == alvo:
                return visto
            time.sleep(0.5)
        return visto

    def avalia(self, modelo: str, casos: list, nomes: str) -> list[str] | str:
        """Avalia um texto de template para cada caso (as variáveis `nomes`
        recebem os campos do caso) e devolve os resultados, na ordem."""
        saida: list[str] = []
        for i in range(0, len(casos), 100):
            lote = casos[i:i + 100]
            st, r = self.post("/api/template", {"template": (
                "{% set o = namespace(l=[]) %}{% for " + nomes + " in " + json.dumps(lote)
                + " %}{% set r %}" + modelo + "{% endset %}{% set o.l = o.l + [r | trim] %}{% endfor %}"
                "{{ o.l | join('@') }}")})
            partes = str(r).split("@") if st == 200 else []
            if len(partes) != len(lote):
                return f"HTTP {st}: {str(r)[:200]}"
            saida += partes
        return saida

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
    if not str(a.estado(MEDIDO_DESDE)).startswith(a.hoje().isoformat()):
        a.falha(token, f"{MEDIDO_DESDE} nasce em {a.estado(MEDIDO_DESDE)} — a medição de uma instalação nova "
                       "começa no dia da instalação")
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
    ok &= a.texto("input_text.ajuste_outros_debitos", str(outros).replace(".", ",") if outros else "")
    ok &= a.texto("input_text.ajuste_creditos", str(creditos).replace(".", ",") if creditos else "")
    ok &= a.servico("input_number", "set_value", {"entity_id": "input_number.cosip_media_kwh", "value": media})
    ok &= a.servico("input_number", "set_value", {"entity_id": "input_number.fatura_conferencia", "value": CONTA})
    ok &= a.data(ULTIMA, D(ini)) and a.data(PROXIMA, D(fim))
    ok &= a.calibra("fatura_energy", (ponta, inter, fora))
    if not ok:
        return None
    return referencia.calcula(DADOS, D(ini), D(fim), round(ponta + inter + fora, 3), kwh_ponta=ponta,
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
        kwh = round(ponta + inter + fora, 3)
        # ciclo em curso (as datas já passaram, então projeção = consumo)
        if not compara_parametros(a, token, nome + ", em curso", PARAMETROS, r):
            continue
        if not compara(a, token, nome + ", em curso", (
                ("sensor.consumo_do_ciclo", kwh, 0.001, "consumo"),
                ("sensor.consumo_projetado_do_ciclo", kwh, 0.001, "consumo projetado de ciclo encerrado"),
                ("sensor.preco_convencional", r["preco"], 6e-7, "preço do kWh (o do painel de Energia)"),
                ("sensor.bandeira_do_ciclo", r["bandeira"], 6e-7, "bandeira"),
                ("sensor.icms_do_ciclo", r["icms"], 1e-9, "ICMS"),
                ("sensor.pis_do_ciclo", r["pis"], 1e-9, "PIS"),
                ("sensor.cofins_do_ciclo", r["cofins"], 1e-9, "COFINS"),
                ("sensor.fator_de_tributos", r["fator"], 6e-7, "fator de tributos"),
                ("sensor.iluminacao_publica_do_ciclo", r["iluminacao"], 0.001, "iluminação pública"),
                ("sensor.encargos_fixos_do_mes", r["encargos"], 0.0051, "encargos fixos"),
                ("sensor.preco_ponta", r["preco_ponta"], 6e-7, "preço da Branca na ponta"),
                ("sensor.preco_intermediario", r["preco_intermediario"], 6e-7, "preço da Branca no intermediário"),
                ("sensor.preco_fora_ponta", r["preco_fora_ponta"], 6e-7, "preço da Branca fora de ponta"),
                ("sensor.energia_mensal_convencional", r["energia"], 0.0051, "energia sem encargos"),
                ("sensor.energia_mensal_branca", r["energia_branca"], 0.0051, "energia na Branca sem encargos"),
                ("sensor.fatura_mensal_convencional", r["total"], 0.0051, "fatura"),
                ("sensor.fatura_projetada_do_ciclo", r["total"], 0.0051, "fatura projetada"),
                ("sensor.fatura_mensal_branca", r["total_branca"], 0.0051, "fatura na Tarifa Branca"),
                ("sensor.economia_com_tarifa_branca", r["total"] - r["total_branca"], 0.0101,
                 "economia com a Tarifa Branca"))):
            continue
        # ciclo fechado: os mesmos números têm de sobreviver ao fechamento
        if not a.dispara_fechamento():
            a.falha(token, f"{nome}: não há automação de fechamento")
            return
        if not compara_parametros(a, token, nome + ", fechado", PARAMETROS_FECHADO, r):
            continue
        estimou = "sim" if r["estimado"] else "não"
        if a.espera_estado("sensor.ciclo_fechado_com_estimativa", estimou) != estimou:
            a.falha(token, f"{nome}, fechado: o aviso de estimativa deveria dizer {estimou!r} e diz "
                           f"{a.estado('sensor.ciclo_fechado_com_estimativa')!r}")
            continue
        if not compara(a, token, nome + ", fechado", (
                ("sensor.consumo_do_ciclo_fechado", kwh, 0.001, "consumo"),
                ("sensor.consumo_de_faixa_do_ciclo_fechado", kwh, 0.001, "consumo de faixa"),
                ("sensor.preco_do_ciclo_fechado", r["preco"], 6e-7, "preço do kWh"),
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
    # os dois sensores que não dependem do ciclo
    dias = (D(DADOS["tarifa"]["vigencia_fim"]) - a.hoje()).days
    compara(a, token, "tarifa", (("sensor.dias_ate_reajuste_tarifario", dias, 0, "dias até o fim da vigência"),))
    posto = {"peak": "Ponta", "shoulder": "Intermediário", "offpeak": "Fora Ponta"}.get(
        str(a.estado("select.monthly_energy")), "?")
    if a.espera_estado("sensor.posto_tarifario_atual", posto, 5) != posto:
        a.falha(token, f"posto tarifário mostrado: {a.estado('sensor.posto_tarifario_atual')!r}; o medidor "
                       f"está em {posto!r}")
    confere_projecao(a, token)
    if len(a.falhas) == antes:
        a.ok(f"{feitos} ciclos: cada sensor calculado (parâmetros, preços, energia, faturas, impostos em reais, "
             "encargos, avisos) igual à calculadora, em curso e fechado")


PROJECAO = (      # entradas do texto da projeção → variáveis
    ("states('sensor.consumo_do_ciclo') | float(0)", "c_kwh", 1),
    ("states('input_datetime.fatura_ultima_leitura') | as_datetime", "c_ini | as_datetime", 1),
    ("states('input_datetime.fatura_proxima_leitura') | as_datetime", "c_fim | as_datetime", 1),
    ("states('input_datetime.fatura_medido_desde') | as_datetime", "c_md | as_datetime", 1),
    ("states('sensor.consumo_do_ciclo_fechado') | float(0)", "c_fk", 1),
    ("states('input_number.fatura_fechado_dias_medidos') | float(0)", "c_fd", 1),
    ("now()", "(c_agora | as_datetime | as_local)", 2),
)
FAIXA_FECHADO = (
    ("states('sensor.consumo_do_ciclo_fechado') | float(0)", "c_fk", 1),
    ("states('input_datetime.fatura_fechado_inicio') | as_datetime", "c_ini | as_datetime", 1),
    ("states('input_datetime.fatura_fechado_fim') | as_datetime", "c_fim | as_datetime", 1),
    ("states('input_number.fatura_fechado_dias_medidos') | float(0)", "c_fd", 1),
)


def texto_com_variaveis(a: Arnes, token: str, unique_id: str, trocas) -> str | None:
    texto = str(sensor_do_pacote(carrega_yaml("packages/energia_br.yaml"), unique_id).get("state", ""))
    for entrada, variavel, vezes in trocas:
        if texto.count(entrada) != vezes:
            a.falha(token, f"não achei no sensor {unique_id} a entrada que o arnês troca por variável "
                           f"({entrada}) — o arnês precisa acompanhar a mudança")
            return None
        texto = texto.replace(entrada, variavel)
    return texto


def projecoes_sorteadas(quantas: int = 400) -> list:
    sorteio = random.Random(20261007)
    casos = []
    for _ in range(quantas):
        ini = datetime.datetime(2025, 1, 1) + datetime.timedelta(days=sorteio.randrange(0, 900))
        total = sorteio.choice([28, 29, 30, 31, 32, 33, 34, 35, 31, 30, 0, -2])
        agora = ini + datetime.timedelta(seconds=sorteio.randrange(-2 * 86400, (max(total, 1) + 3) * 86400))
        medido = sorteio.choice([None, None, ini - datetime.timedelta(days=sorteio.randrange(1, 40)),
                                 ini + datetime.timedelta(seconds=sorteio.randrange(0, (max(total, 1) + 1) * 86400))])
        casos.append((ini.date().isoformat(), (ini + datetime.timedelta(days=total)).date().isoformat(),
                      agora.strftime("%Y-%m-%d %H:%M:%S"), medido.strftime("%Y-%m-%d %H:%M:%S") if medido else "",
                      round(sorteio.uniform(0, 600), 3), sorteio.choice([0, 0, round(sorteio.uniform(20, 900), 3)]),
                      sorteio.choice([0, 0.5, 0.99, 1, round(sorteio.uniform(1, 35), 2)])))
    return casos


def confere_projecao(a: Arnes, token: str) -> None:
    """Ciclo que ainda corre: as faixas saem do consumo PROJETADO, não do já
    medido; e a projeção só conta como cobertos os dias de fato medidos."""
    # a) o texto da projeção e o da faixa do ciclo fechado, contra a calculadora
    modelo = texto_com_variaveis(a, token, "consumo_projetado_ciclo", PROJECAO)
    faixa = texto_com_variaveis(a, token, "consumo_faixa_ciclo_fechado", FAIXA_FECHADO)
    if modelo is None or faixa is None:
        return
    casos = projecoes_sorteadas()
    partes = a.avalia(modelo, casos, "c_ini, c_fim, c_agora, c_md, c_kwh, c_fk, c_fd")
    partes_f = a.avalia(faixa, casos, "c_ini, c_fim, c_agora, c_md, c_kwh, c_fk, c_fd")
    if isinstance(partes, str) or isinstance(partes_f, str):
        a.falha(token, f"o motor de templates não avaliou a projeção do package ({partes if isinstance(partes, str) else partes_f})")
        return
    ruins = []
    for (ini, fim, agora, md, kwh, fk, fd), texto, texto_f in zip(casos, partes, partes_f):
        ref = round(referencia.consumo_projetado(
            kwh, D(ini), D(fim), datetime.datetime.fromisoformat(agora),
            medido_desde=datetime.datetime.fromisoformat(md) if md else None, fechado_kwh=fk, fechado_dias=fd), 3)
        ref_f = round(referencia.consumo_de_faixa_do_fechado(fk, (D(fim) - D(ini)).days, fd), 3)
        try:
            ha, ha_f = float(texto), float(texto_f)
        except ValueError:
            ha = ha_f = float("nan")
        if ha != ref:
            ruins.append(f"projeção de {kwh} kWh, ciclo {ini} → {fim}, agora {agora}, medido desde {md or 'o início'}, "
                         f"anterior {fk} kWh em {fd} dias: {ha} ≠ {ref}")
        if ha_f != ref_f:
            ruins.append(f"consumo de faixa do ciclo fechado {ini} → {fim}, {fk} kWh medidos em {fd} dias: {ha_f} ≠ {ref_f}")
    for linha in ruins[:5]:
        a.falha(token, "projeção do package ≠ calculadora — " + linha)
    if len(ruins) > 5:
        a.falha(token, f"... e mais {len(ruins) - 5} projeção(ões) sorteada(s) com diferença")

    # b) com as entidades e o relógio do Home Assistant
    hoje = a.hoje()
    meia_noite = datetime.datetime.combine(hoje, datetime.time.min)
    ini, fim = hoje - datetime.timedelta(days=10), hoje + datetime.timedelta(days=20)
    for nome, anterior, dias_ant, desde, postos in (
            ("sem ciclo anterior", 0, 0, 10, (10, 10, 100)),
            ("com ciclo anterior de 900 kWh medidos em 30 dias", 900, 30, 10, (10, 10, 100)),
            ("instalado no meio do ciclo, medindo há 4 dias", 0, 0, 4, (5, 5, 50))):
        kwh = sum(postos)
        medido = meia_noite - datetime.timedelta(days=desde)
        a.limpa_ajustes()
        a.servico("input_number", "set_value", {"entity_id": "input_number.cosip_media_kwh", "value": 0})
        a.calibra("fatura_energy", (0, 0, anterior))
        a.fecha_ciclo(ini, ini - datetime.timedelta(days=30))       # o ciclo anterior
        a.servico("input_number", "set_value", {"entity_id": DIAS_MEDIDOS, "value": dias_ant})
        a.data(ULTIMA, ini)
        a.data(PROXIMA, fim)
        a.data_hora(MEDIDO_DESDE, medido)
        a.calibra("fatura_energy", postos)
        time.sleep(2)
        proj = referencia.consumo_projetado(kwh, ini, fim, a.agora(), medido_desde=medido,
                                            fechado_kwh=anterior, fechado_dias=dias_ant)
        v = a.espera_numero("sensor.consumo_projetado_do_ciclo", proj, 0.08, 12)
        if v is None or abs(v - proj) > 0.08:
            a.falha(token, f"consumo projetado, {nome}: a calculadora dá {proj:.3f} kWh, o Home Assistant {v}")
            continue
        r = referencia.calcula(DADOS, ini, fim, kwh, kwh_ponta=postos[0], kwh_intermediario=postos[1], kwh_faixa=v)
        if r["icms"] != 24.0 or referencia.icms_da_faixa(DADOS, kwh) == 24.0:
            raise SystemExit("[ERRO] o cenário da projeção deixou de atravessar a faixa do ICMS")
        if not compara_parametros(a, token, f"ciclo em curso, {nome}", PARAMETROS, r):
            continue
        rp = referencia.calcula(DADOS, ini, fim, v, kwh_faixa=v)
        compara(a, token, f"ciclo em curso, {nome}", (
            ("sensor.fatura_mensal_convencional", r["total"], 0.0051, "fatura até agora"),
            ("sensor.fatura_projetada_do_ciclo", rp["total"], 0.0051, "fatura projetada")))

    # c) ciclo FECHADO medido em parte: a automação grava os dias medidos e a
    #    faixa sai do consumo na proporção dos dias
    a.limpa_ajustes()
    a.data(ULTIMA, hoje - datetime.timedelta(days=30))
    a.data(PROXIMA, hoje)
    medido = meia_noite - datetime.timedelta(days=10)
    a.data_hora(MEDIDO_DESDE, medido)
    a.calibra("fatura_energy", (10, 10, 110))
    antes_de_fechar = a.agora()
    a.dispara_fechamento()
    esperado = (antes_de_fechar - medido).total_seconds() / 86400
    dm = a.espera_numero(DIAS_MEDIDOS, esperado, 0.02, 8)
    if dm is None or abs(dm - esperado) > 0.02:
        a.falha(token, f"ciclo fechado medido em parte: a automação deveria gravar {esperado:.2f} dias medidos "
                       f"(de {medido} até o fechamento); gravou {dm}")
        return
    fx = round(referencia.consumo_de_faixa_do_fechado(130, 30, dm), 3)
    r = referencia.calcula(DADOS, hoje - datetime.timedelta(days=30), hoje, 130, kwh_faixa=fx)
    if r["icms"] != 24.0:
        raise SystemExit("[ERRO] o cenário do ciclo fechado em parte deixou de atravessar a faixa do ICMS")
    compara(a, token, "ciclo fechado medido em parte",
            (("sensor.consumo_de_faixa_do_ciclo_fechado", fx, 0.001, "consumo de faixa"),
             ("sensor.consumo_do_ciclo_fechado", 130, 0.001, "consumo medido")))
    compara_parametros(a, token, "ciclo fechado medido em parte", PARAMETROS_FECHADO, r)
    novo = str(a.estado(MEDIDO_DESDE))
    try:
        atraso = abs((datetime.datetime.fromisoformat(novo) - antes_de_fechar).total_seconds())
    except ValueError:
        atraso = 1e9
    if atraso > 120:
        a.falha(token, f"fechado o ciclo, a medição do ciclo novo deveria começar agora; ficou em {novo}")


# ── 3b. a regra do package é a da calculadora, bit a bit ────────────────────
# As entradas do texto da regra (as duas datas, o consumo e a média) são
# trocadas por variáveis, e o MESMO texto é avaliado pelo motor do Home
# Assistant para centenas de ciclos sorteados: bordas de todas as faixas,
# virada de ano, meses que a tabela não tem, datas iguais e invertidas.
ENTRADAS = (
    ("{%- set fechado = this.entity_id.endswith('_fechado') -%}", ""),
    ("{%- set ini = states('input_datetime.fatura_fechado_inicio' if fechado else "
     "'input_datetime.fatura_ultima_leitura') | as_datetime -%}", "{%- set ini = c_ini | as_datetime -%}"),
    ("{%- set fim = states('input_datetime.fatura_fechado_fim' if fechado else "
     "'input_datetime.fatura_proxima_leitura') | as_datetime -%}", "{%- set fim = c_fim | as_datetime -%}"),
    ("{%- set kwh = states('sensor.consumo_de_faixa_do_ciclo_fechado' if fechado else "
     "'sensor.consumo_projetado_do_ciclo') | float(0) -%}", "{%- set kwh = c_kwh -%}"),
    ("{%- set media = states('input_number.cosip_media_kwh') | float(0) -%}", "{%- set media = c_media -%}"),
)
EXATOS = ("dias", "bandeira", "icms", "pis", "cofins", "fator", "preco", "iluminacao", "estimado")


def ciclos_sorteados(quantos: int = 600) -> list[tuple[str, str, float, float]]:
    sorteio = random.Random(20261006)        # semente fixa: a mesma grade em toda rodada
    limites = sorted({float(x[0]) for x in DADOS["iluminacao_publica"]["faixas"] if x[0] is not None}
                     | {float(x[0]) for x in DADOS["icms"]["faixas"] if x[0] is not None})
    bordas = [0.0, 0.4] + [v + d for v in limites for d in (-0.5, -0.001, 0, 0.001, 0.4, 0.5, 0.51, 1)]
    medias = [0, 0, 0, 425, 100, 119, 121, 130, 451, 99999, 250000]
    casos = []
    for n in range(quantos):
        ini = datetime.date(2024, 11, 1) + datetime.timedelta(days=sorteio.randrange(0, 1000))
        dias = sorteio.choice([28, 29, 30, 31, 32, 33, 34, 35, 30, 31, 33, 1, 2, 60, 0, -3])
        kwh = sorteio.choice(bordas) if n % 2 else round(sorteio.uniform(0, 1500), 3)
        casos.append((ini.isoformat(), (ini + datetime.timedelta(days=dias)).isoformat(), kwh,
                      sorteio.choice(medias)))
    return casos


def confere_identidade(a: Arnes) -> None:
    token = "FORMULA DIVERGE"
    pacote = carrega_yaml("packages/energia_br.yaml")
    regra = str(sensor_do_pacote(pacote, "parametros_ciclo").get("attributes", {}).get("p", ""))
    if regra != str(sensor_do_pacote(pacote, "parametros_ciclo_fechado").get("attributes", {}).get("p", "")):
        a.falha(token, "o ciclo em curso e o fechado não usam o mesmo texto de regra")
        return
    for entrada, variavel in ENTRADAS:
        if regra.count(entrada) != 1:
            a.falha(token, "não achei no package a linha de entrada da regra que o arnês troca por variável "
                           f"({entrada[:60]}…) — o arnês precisa acompanhar a mudança")
            return
        regra = regra.replace(entrada, variavel)
    a.limpa_ajustes()
    time.sleep(1)
    casos, ruins, feitos = ciclos_sorteados(), [], 0
    partes = a.avalia(regra, casos, "c_ini, c_fim, c_kwh, c_media")
    if isinstance(partes, str):
        a.falha(token, f"o motor de templates não avaliou a regra do package ({partes})")
        return
    for (ini, fim, kwh, media), texto in zip(casos, partes):
        try:
            p = ast.literal_eval(texto)
        except (ValueError, SyntaxError):
            p = {}
        ref = referencia.calcula(DADOS, D(ini), D(fim), kwh, cosip_media_kwh=media)
        difere = [k for k in EXATOS if p.get(k) != ref[k]]
        feitos += 1
        if difere:
            ruins.append(f"{ini} → {fim}, {kwh} kWh, média {media}: "
                         + ", ".join(f"{k} {p.get(k)} ≠ {ref[k]}" for k in difere))
    for linha in ruins[:6]:
        a.falha(token, "regra do package ≠ calculadora — " + linha)
    if len(ruins) > 6:
        a.falha(token, f"... e mais {len(ruins) - 6} ciclo(s) sorteado(s) com diferença")
    if not ruins:
        a.ok(f"{feitos} ciclos sorteados: a regra do package dá exatamente o que a calculadora dá "
             "(bandeira, ICMS, PIS, COFINS, fator, preço, iluminação, dias e estimativa)")


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
    # com VÍRGULA, que é como o dono digita — em todos os campos
    valores = {"tarifa": "0,91357", "bandeira": "0,02113", "icms": "20,5", "pis": "1,47", "cofins": "6,11",
               "iluminacao": "51,37"}
    for chave, valor in valores.items():
        r = prepara_ciclo(a, caso, {chave: valor})
        if not compara_parametros(a, token, f"ajuste de {chave} = {valor}", PARAMETROS, r):
            continue
        compara(a, token, f"ajuste de {chave} = {valor}",
                (("sensor.fatura_mensal_convencional", r["total"], 0.0051, "fatura"),
                 ("sensor.ajustes_ativos", 2 if caso[7] else 1, 0, "contagem de ajustes ativos")))
    # débitos e créditos: caso[7] e caso[8] já vão com vírgula; aqui os dois juntos
    r = prepara_ciclo(a, caso[:7] + (7.31, 4.19))
    compara(a, token, "outros débitos 7,31 e créditos 4,19",
            (("sensor.encargos_fixos_do_mes", r["encargos"], 0.0051, "encargos fixos"),
             ("sensor.fatura_mensal_convencional", r["total"], 0.0051, "fatura"),
             ("sensor.ajustes_ativos", 2, 0, "contagem de ajustes ativos")))
    # alíquota impossível não derruba o cálculo: o preço vai a zero
    r = prepara_ciclo(a, caso, {"icms": "100"})
    compara_parametros(a, token, "ajuste de ICMS = 100", PARAMETROS, r)
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
    # o aviso de estimativa: ciclo anterior à tabela (bandeira, PIS/COFINS e a
    # bandeira da iluminação saem do último valor conhecido). Cada ajuste tira
    # a sua parte do aviso; só com todos ele some.
    antigo = ("ciclo anterior à tabela", "2024-11-05", "2024-12-05", 30, 20, 304, 425, 0.0, 0.0)
    passos = (({}, True), ({"pis": "1,2", "cofins": "5,5"}, True),
              ({"pis": "1,2", "cofins": "5,5", "bandeira": "0,01"}, True),
              ({"pis": "1,2", "cofins": "5,5", "bandeira": "0,01", "iluminacao": "60"}, False),
              ({"pis": "1,2", "bandeira": "0,01", "iluminacao": "60"}, True))
    for ajustes, estimado in passos:
        r = prepara_ciclo(a, antigo, ajustes)
        if r["estimado"] is not estimado:
            raise SystemExit("[ERRO] o cenário do aviso de estimativa deixou de exercitar o que devia")
        compara_parametros(a, token, f"aviso de estimativa com os ajustes {sorted(ajustes) or 'nenhum'}",
                           PARAMETROS, r)
    # apagado, volta o padrão
    prepara_ciclo(a, caso)
    compara_parametros(a, token, "ajustes apagados", PARAMETROS, padrao)
    if len(a.falhas) == antes:
        a.ok(f"{len(valores) + 2} ajustes manuais, todos com vírgula: preenchido vale o do dono; apagado ou "
             "inválido, volta o padrão; o aviso de estimativa segue cada ajuste")


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
    # (os dois últimos são gravados pela automação a cada fechamento: o
    #  reinício abaixo fecha um ciclo, e o que se confere é o que ela gravou)
    cobertos = {(d, c) for d, c, _ in PERSISTEM} | {("input_datetime", c) for c in DATAS} | {
        ("input_select", "agua_area"), ("input_number", "fatura_fechado_dias_medidos"),
        ("input_datetime", "fatura_medido_desde")}
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
    elif not str(a.estado(MEDIDO_DESDE)).startswith(a.hoje().isoformat()):
        a.falha("CICLO NAO ZERA", "o ciclo fechou no início mas a medição do ciclo novo não recomeçou agora: "
                                  f"{MEDIDO_DESDE} = {a.estado(MEDIDO_DESDE)}")
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
    seguinte = proxima_depois_de(hoje, hoje).isoformat()
    if a.estado(PROXIMA) != seguinte:
        a.falha(token, f"fechado o ciclo, a próxima leitura deveria passar a {seguinte} "
                       f"(um mês depois); ficou em {a.estado(PROXIMA)}")
        return
    # "um mês depois", para toda data: o texto da automação avaliado para três
    # anos de leituras (fins de mês, bissexto, virada de ano, e leituras tão
    # atrasadas que o mês seguinte também já passou).
    passo = next((x for x in auto.get("action", []) if "variables" in x), {})
    texto = str(passo.get("variables", {}).get("seguinte", ""))
    entrada = "states('input_datetime.fatura_proxima_leitura') | as_datetime"
    if texto.count(entrada) != 1:
        a.falha(token, "não achei na automação o cálculo da próxima leitura que o arnês avalia")
        return
    datas = [hoje + datetime.timedelta(days=n) for n in range(-800, 400)]
    partes = a.avalia(texto.replace(entrada, "c_data | as_datetime"), [d.isoformat() for d in datas], "c_data")
    if isinstance(partes, str):
        a.falha(token, f"o motor de templates não avaliou o cálculo da próxima leitura ({partes})")
        return
    erradas = [(d.isoformat(), v, proxima_depois_de(d, hoje).isoformat()) for d, v in zip(datas, partes)
               if v != proxima_depois_de(d, hoje).isoformat()]
    if erradas:
        d, v, certo = erradas[0]
        a.falha(token, f"próxima leitura depois de {d}: a automação daria {v}, o certo é {certo} "
                       f"({len(erradas)} de {len(datas)} datas erradas)")
        return
    # leitura tão atrasada que o mês seguinte já passou: fecha UMA vez
    a.calibra("fatura_energy", (30, 30, 30))
    a.fecha_ciclo(hoje - datetime.timedelta(days=40), hoje - datetime.timedelta(days=70))
    a.calibra("fatura_energy", (1, 1, 1))
    a.dispara_fechamento()
    if a.numero("sensor.consumo_do_ciclo_fechado") != 90 or a.soma("fatura_energy") != 3:
        a.falha(token, "leitura atrasada em mais de um mês: o ciclo fechou duas vezes — o fechado mostra "
                       f"{a.numero('sensor.consumo_do_ciclo_fechado')} (esperava 90) e o medidor "
                       f"{a.soma('fatura_energy')} (esperava 3)")
        return
    a.calibra("fatura_energy", (40, 40, 40))
    a.fecha_ciclo(hoje, anterior)
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
    a.ok("ciclo da fatura: não zera antes da data; zera à meia-noite dela, uma vez, mesmo com mais de um "
         f"mês de atraso; guarda as duas datas; assume a próxima um mês depois ({len(datas)} datas "
         "conferidas); só o medidor da fatura")


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
    confere_identidade(a)
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
