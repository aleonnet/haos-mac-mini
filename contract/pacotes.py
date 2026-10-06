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

Tokens de falha, um por garantia:
    ESTADO DE FABRICA:  REFERENCIA INEXISTENTE:  SOMA PARCIAL:
    FATURA NAO REPRODUZ:  CONFERENCIA CEGA:  CAMPO NAO PERSISTE:
    CICLO NAO ZERA:  MEDIDOR NAO ACOMPANHA:  AGUA NAO REPRODUZ:
    GAS NAO REPRODUZ:
Sucesso: PACOTES OK

Exit: 0 íntegro · 3 alguma garantia quebrou · 4 dependência ausente

Limites declarados:
  · As fases de teste são sensores de energia criados pelo fluxo de
    configuração da integração `template`, e o domínio procurado é trocado de
    'shelly' para 'template' antes de o texto ir ao motor do HA. Prova-se a
    descoberta pelo registro, a regra de disponibilidade e a soma — não um
    Shelly de verdade, nem a sequência real de uma recarga da integração.
  · O fechamento do ciclo é exercitado por data passada, por data futura, na
    repetição da mesma data e no início do Home Assistant. O gatilho do
    meio-dia é só CONFERIDO no arquivo (existe e marca 12:00): fazê-lo disparar
    exigiria mexer no relógio.
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
ULTIMA = "input_datetime.fatura_ultima_leitura"
PROXIMA = "input_datetime.fatura_proxima_leitura"

DOMINIO_DAS_FASES = "== 'shelly'"               # como o package escolhe as fases
FASES = ["sensor.arnes_fase_a", "sensor.arnes_fase_b", "sensor.arnes_fase_c"]
DEVOLVIDA = "sensor.arnes_returned_energy"       # energia devolvida à rede: NÃO entra na soma
ATRIB_FASE = {"device_class": "energy", "state_class": "total_increasing",
              "unit_of_measurement": "kWh"}

# Duas faturas reais, com os números impressos nelas. `total` é o TOTAL A PAGAR.
FATURAS = {
    "agosto": dict(kwh=304, preco=1.36636, tarifa=0.96678, icms=24.0, pis=1.23,
                   cofins=5.67, cosip=64.60, complementos=2.08, bonus=10.13,
                   total=471.92),
    "outubro": dict(kwh=354, preco=1.34405, tarifa=0.96335, icms=24.0, pis=1.01,
                    cofins=4.68, cosip=64.60, complementos=2.08, bonus=0.0,
                    total=542.46),
}
# Consumo posto em ponta e intermediário na simulação: sem isso os preços
# desses dois postos ficariam sem cerca.
EM_PONTA, EM_INTERMEDIARIO = 10, 20


class Arnes:
    def __init__(self, base: str, token: str) -> None:
        self.base, self.token = base, token
        self.falhas: list[str] = []
        self.oks = 0

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

    def fecha_ciclo(self, proxima: datetime.date) -> bool:
        """Informa uma leitura nova (a anterior, 30 dias antes) e dispara."""
        ok = self.data(ULTIMA, proxima - datetime.timedelta(days=30))
        ok = self.data(PROXIMA, proxima) and ok
        return bool(ok) and self.dispara_fechamento()

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
        if dominio != "input_number":
            continue
        n += 1
        v = a.numero(f"input_number.{chave}")
        if v != 0:
            a.falha(token, f"input_number.{chave} nasce em {v} numa instalação nova (campo sem "
                           "valor inicial nasce no `min:` — o mínimo tem de ser zero)")
    for eid in ("sensor.encargos_fixos_do_mes", "sensor.fatura_mensal_convencional",
                "sensor.fatura_mensal_branca", "sensor.preco_convencional"):
        v = a.numero(eid)
        if v != 0:
            a.falha(token, f"{eid} mostra {v} antes de qualquer número ser digitado (esperava 0)")
    for eid in ("sensor.fatura_do_ciclo_fechado", "sensor.desvio_da_conferencia"):
        v = a.estado(eid)
        if v != "unavailable":
            a.falha(token, f"{eid} mostra {v} antes do primeiro fechamento de ciclo "
                           "(não há ciclo fechado: deveria estar indisponível)")
    if a.estado(ULTIMA) != a.estado(PROXIMA):
        a.falha(token, "as duas datas de leitura nascem diferentes — a automação poderia "
                       "fechar um ciclo que o usuário nunca informou")
    if len(a.falhas) == antes:
        a.ok(f"instalação nova: {n} campos em zero, faturas em zero, ciclo fechado indisponível")


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


# ── 3 e 4. a fatura sai dos números da fatura ───────────────────────────────
def kwh_por_posto(f: dict) -> tuple[int, int, int]:
    return EM_PONTA, EM_INTERMEDIARIO, f["kwh"] - EM_PONTA - EM_INTERMEDIARIO


def digita_fatura(a: Arnes, f: dict) -> list[str]:
    campos = {"fatura_preco_com_tributos": f["preco"], "fatura_tarifa_unit": f["tarifa"],
              "aliquota_icms": f["icms"], "aliquota_pis": f["pis"],
              "aliquota_cofins": f["cofins"], "encargo_cosip": f["cosip"],
              "encargo_complementos": f["complementos"], "encargo_bonus": f["bonus"],
              "fatura_conferencia": f["total"]}
    recusados = [c for c, v in campos.items()
                 if not a.servico("input_number", "set_value",
                                  {"entity_id": f"input_number.{c}", "value": v})]
    if not a.calibra("fatura_energy", kwh_por_posto(f)):
        recusados.append("sensor.fatura_energy_*")
    return recusados


def fator_de(f: dict) -> float:
    i, p, c = f["icms"] / 100, f["pis"] / 100, f["cofins"] / 100
    return 1 / (1 - i - (p + c) * (1 - i))


def confere_fatura(a: Arnes, nome: str) -> None:
    f = FATURAS[nome]
    token = "FATURA NAO REPRODUZ"
    recusados = digita_fatura(a, f)
    if recusados:
        a.falha(token, f"{nome}: o HA recusou {', '.join(recusados)} "
                       "(campo ou medidor da fatura inexistente)")
        return

    visto: dict[str, float] = {}

    def confere(eid: str, alvo: float, tol: float, que: str) -> bool:
        v = a.espera_numero(eid, alvo, tol, 12)
        if v is None or abs(v - alvo) > tol:
            a.falha(token, f"{nome}: {que} ({eid}) deveria ser {alvo:.2f}; veio {v}")
            return False
        visto[eid] = v
        return True

    # 1) o ciclo em curso: o que se pagaria se a leitura fosse agora
    if not confere("sensor.fatura_mensal_convencional", f["total"], 0.0101,
                   f"{f['kwh']} kWh no ciclo em curso"):
        return
    # a Branca usa a tabela do pacote + a bandeira e o fator tirados da conta
    tab = a.atributos("sensor.tabela_tarifaria")
    fixos = f["cosip"] + f["complementos"] - f["bonus"]
    try:
        bandeira = f["tarifa"] - float(tab["convencional"])
        tarifas = (float(tab["ponta"]), float(tab["intermediaria"]), float(tab["fora_ponta"]))
    except (KeyError, TypeError, ValueError):
        a.falha(token, f"{nome}: a tabela tarifária não expõe convencional/ponta/intermediaria/fora_ponta")
        return
    branca = sum(k * (t + bandeira) for k, t in zip(kwh_por_posto(f), tarifas)) * fator_de(f) + fixos
    if not confere("sensor.fatura_mensal_branca", branca, 0.0151,
                   "Branca com consumo nos três postos"):
        return

    # 2) o ciclo fechado: é ELE que se compara com a conta de papel
    if not a.fecha_ciclo(a.hoje() - datetime.timedelta(days=1)):
        a.falha(token, f"{nome}: não há como fechar o ciclo (automação ou datas de leitura ausentes)")
        return
    energia = round(f["kwh"] * f["preco"], 2)
    icms = energia * f["icms"] / 100
    base = energia - icms
    for eid, alvo, tol, que in (
            ("sensor.consumo_do_ciclo_fechado", f["kwh"], 0.001, "consumo do ciclo fechado"),
            ("sensor.fatura_do_ciclo_fechado", f["total"], 0.0101, "fatura do ciclo fechado"),
            ("sensor.fatura_icms", icms, 0.0101, "ICMS"),
            ("sensor.fatura_pis", base * f["pis"] / 100, 0.0101, "PIS"),
            ("sensor.fatura_cofins", base * f["cofins"] / 100, 0.0101, "COFINS"),
            ("sensor.desvio_da_conferencia", 0.0, 0.0101, "desvio contra o total digitado"),
            ("sensor.fatura_mensal_convencional", fixos, 0.0101, "ciclo novo, só encargos fixos")):
        if not confere(eid, alvo, tol, que):
            return
    a.ok(f"fatura de {nome}: {f['kwh']} kWh → painel {visto['sensor.fatura_do_ciclo_fechado']:.2f}, "
         f"conta {f['total']:.2f} (ciclo em curso e fechado); impostos, desvio e Branca nos três postos")


def confere_conferencia(a: Arnes) -> None:
    f = FATURAS["outubro"]
    if digita_fatura(a, f):
        a.falha("CONFERENCIA CEGA", "os campos da fatura não existem — não há o que conferir")
        return
    certo = a.espera_numero("sensor.conferencia_do_preco", 0.0, 0.00011, 12)
    if certo is None or abs(certo) > 0.00011:
        a.falha("CONFERENCIA CEGA", f"com a conta digitada certa a conferência deveria ser zero; veio {certo}")
        return
    a.servico("input_number", "set_value", {"entity_id": "input_number.aliquota_pis", "value": 1.23})
    errado = None
    for _ in range(24):
        errado = a.numero("sensor.conferencia_do_preco")
        if errado is not None and abs(errado) > 0.001:
            break
        time.sleep(0.5)
    a.servico("input_number", "set_value", {"entity_id": "input_number.aliquota_pis", "value": f["pis"]})
    if errado is None or abs(errado) <= 0.001:
        a.falha("CONFERENCIA CEGA", f"PIS digitado errado (1,23 em vez de 1,01) e a conferência ficou em {errado}")
    else:
        a.ok(f"conferência do preço: {certo:.4f} com a conta certa, {errado:+.4f} com um imposto errado")


# ── 5. o que o dono digita sobrevive ao reinício ────────────────────────────
# Valores que NÃO coincidem com nenhum padrão plausível: um `initial:` de volta
# num campo com o mesmo número passaria despercebido.
PERSISTEM = [
    ("input_number", "fatura_preco_com_tributos", 1.37911),
    ("input_number", "fatura_tarifa_unit", 0.91357),
    ("input_number", "aliquota_icms", 23.57),
    ("input_number", "aliquota_pis", 1.13),
    ("input_number", "aliquota_cofins", 4.91),
    ("input_number", "encargo_cosip", 61.37),
    ("input_number", "encargo_complementos", 2.71),
    ("input_number", "encargo_bonus", 3.21),
    ("input_number", "fatura_conferencia", 537.19),
    ("input_number", "gas_consumo_ciclo_m3", 23.0),
    ("input_number", "gas_fator_correcao", 1.02913),
    ("input_number", "gas_fatura_conferencia", 251.33),
    ("input_number", "agua_consumo_m3", 17.0),
    ("input_number", "agua_valor_condominio", 298.77),
]


def confere_persistencia(a: Arnes, espera_volta) -> None:
    token = "CAMPO NAO PERSISTE"
    antes = len(a.falhas)
    # a) nenhum campo declara valor inicial — com ele o HA não restaura
    cobertos = {(d, c) for d, c, _ in PERSISTEM} | {
        ("input_datetime", "fatura_proxima_leitura"), ("input_datetime", "fatura_ultima_leitura"),
        ("input_select", "agua_area")}
    for dominio, chave, cfg in campos_dos_pacotes():
        if "initial" in cfg:
            a.falha(token, f"{dominio}.{chave} declara `initial:` — o que o usuário digita seria "
                           "descartado a cada início")
        if (dominio, chave) not in cobertos:
            a.falha(token, f"{dominio}.{chave} é campo novo e o arnês não o exercita no reinício")

    # b) digitar, reiniciar, reler. A mesma parada prova o fechamento do ciclo
    #    no INÍCIO: leitura com data passada, Home Assistant parado na hora.
    ontem = a.hoje() - datetime.timedelta(days=1)
    for dominio, campo, valor in PERSISTEM:
        a.servico(dominio, "set_value", {"entity_id": f"{dominio}.{campo}", "value": valor})
    a.servico("input_select", "select_option",
              {"entity_id": "input_select.agua_area", "option": "Área B"})
    a.calibra("fatura_energy", (11, 11, 11))
    a.data(ULTIMA, ontem - datetime.timedelta(days=30))
    a.data(PROXIMA, ontem)
    time.sleep(2)
    a.servico("homeassistant", "restart", {})
    if not espera_volta():
        a.falha(token, "o Home Assistant não voltou do reinício")
        return
    for dominio, campo, valor in PERSISTEM:
        v = a.numero(f"{dominio}.{campo}")
        if v is None or abs(v - valor) > 1e-6:
            a.falha(token, f"{dominio}.{campo}: digitado {valor}, depois do reinício {v}")
    if a.estado(PROXIMA) != ontem.isoformat():
        a.falha(token, f"{PROXIMA}: digitado {ontem.isoformat()}, depois do reinício {a.estado(PROXIMA)}")
    if a.estado("input_select.agua_area") != "Área B":
        a.falha(token, "input_select.agua_area: escolhido Área B, depois do "
                f"reinício {a.estado('input_select.agua_area')}")
    if len(a.falhas) == antes:
        a.ok(f"{len(PERSISTEM) + 2} campos do dono mantiveram o valor depois de um reinício; nenhum com valor inicial")

    antes = len(a.falhas)
    for _ in range(40):
        if a.soma("fatura_energy") == 0:
            break
        time.sleep(0.5)
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
    # o gatilho do meio-dia não dá para disparar sem mexer no relógio: confere-se
    # que ele e o do início estão no arquivo.
    auto = next((x for x in carrega_yaml("packages/energia_br.yaml").get("automation", [])
                 if x.get("id") == FECHA_CICLO), {})
    gatilhos = auto.get("trigger") or auto.get("triggers") or []
    tem_meio_dia = any((g.get("platform") or g.get("trigger")) == "time" and str(g.get("at")) == "12:00:00"
                       for g in gatilhos)
    tem_inicio = any((g.get("platform") or g.get("trigger")) == "homeassistant" and g.get("event") == "start"
                     for g in gatilhos)
    if not tem_meio_dia or not tem_inicio:
        a.falha(token, "a automação de fechamento perdeu um gatilho (precisa do meio-dia e do início "
                       f"do Home Assistant; meio-dia={tem_meio_dia}, início={tem_inicio})")
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
    ontem = hoje - datetime.timedelta(days=1)
    a.fecha_ciclo(ontem)
    f, m = a.soma("fatura_energy"), a.soma("monthly_energy")
    if f != 0:
        a.falha(token, f"data de leitura já passada e o medidor da fatura não zerou: {f}")
        return
    if m != 21:
        a.falha(token, f"o fechamento do ciclo mexeu no medidor de calendário: {m} (esperava 21)")
        return
    if a.estado(ULTIMA) != ontem.isoformat():
        a.falha(token, "o ciclo zerou mas a data da última leitura não foi gravada — "
                       "zeraria de novo no dia seguinte")
        return
    # a MESMA data não fecha duas vezes: o consumo novo fica, o ciclo fechado também
    a.calibra("fatura_energy", (5, 5, 5))
    a.dispara_fechamento()
    guardado = a.numero("sensor.consumo_do_ciclo_fechado")
    if a.soma("fatura_energy") != 15 or guardado != 120:
        a.falha(token, "a mesma data de leitura fechou o ciclo de novo: o medidor da fatura foi a "
                       f"{a.soma('fatura_energy')} (esperava 15) e o ciclo fechado a {guardado} (esperava 120)")
        return
    a.ok("ciclo da fatura: não zera antes da data, zera depois dela, uma vez só, e só o medidor da fatura")


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
    confere_fatura(a, "agosto")
    confere_fatura(a, "outubro")
    confere_conferencia(a)
    confere_ciclo(a)
    confere_medidor(a)
    confere_agua_e_gas(a)

    if a.falhas:
        resumo = ", ".join(sorted(set(a.falhas)))
        print(f"\nRESULTADO: {a.oks} garantia(s) íntegra(s) · {len(a.falhas)} falha(s) — {resumo}")
        return 3
    print(f"\nPACOTES OK — {a.oks} garantias conferidas contra o Home Assistant")
    return 0


if __name__ == "__main__":
    sys.exit(main())
