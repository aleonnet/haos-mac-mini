#!/usr/bin/env python3
"""
fatura.py — a calculadora de referência da fatura de energia.

Entra o consumo medido (kWh) e as duas datas de leitura; sai a fatura
decomposta. Os parâmetros vêm de um arquivo de dados com fonte para cada
número (tarifas/energia_light_rj.json); as fórmulas estão numeradas em
docs/2026-10-06-1600-formulas-da-fatura-de-energia.md, e cada função abaixo
traz o número da sua (F1…F13).

O package do Home Assistant (packages/energia_br.yaml) implementa as mesmas
fórmulas em template; tools/pacotes-arnes.sh sobe um Home Assistant e reprova
se algum número dele diferir do que sai daqui.

    python3 tarifas/fatura.py --confere
    python3 tarifas/fatura.py --inicio 2026-09-03 --fim 2026-10-06 --kwh 354 \\
        --cosip-media 425 --outros 2.08

O --confere refaz, só com consumo e datas, as faturas reais guardadas no
arquivo de dados (`casos_de_conferencia`) e os preços com tributos que a
distribuidora publica para cada faixa de ICMS (`casos_de_preco`).

Só biblioteca padrão. Tokens de falha do --confere:
    DADO SEM FONTE:   CONTA NAO REPRODUZ:
Sucesso: FATURAS OK
"""
from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path

DADOS = Path(__file__).resolve().parent / "energia_light_rj.json"

# Os ajustes manuais: cada um, quando presente, vale no lugar do padrão.
AJUSTES = ("tarifa", "bandeira", "icms", "pis", "cofins", "iluminacao")


def carrega(caminho: Path = DADOS) -> dict:
    return json.loads(Path(caminho).read_text(encoding="utf-8"))


def ultimo_conhecido(tabela: dict, mes: str):
    """O valor do mês pedido; sem ele, o do último mês conhecido antes; sem
    nenhum antes, o do primeiro mês da tabela. Devolve (valor, é_estimado)."""
    if mes in tabela:
        return tabela[mes], False
    antes = [m for m in sorted(tabela) if m <= mes]
    return tabela[antes[-1] if antes else sorted(tabela)[0]], True


def dias_do_ciclo(inicio: datetime.date, fim: datetime.date) -> list[datetime.date]:
    """F1 — os dias que a fatura conta: do dia seguinte à leitura anterior até
    o dia da leitura atual, inclusive."""
    return [inicio + datetime.timedelta(days=n) for n in range(1, (fim - inicio).days + 1)]


def bandeira_do_ciclo(d: dict, inicio: datetime.date, fim: datetime.date) -> tuple[float, bool]:
    """F2 — média, pelos dias do ciclo, do adicional da bandeira de cada mês
    (R$/kWh)."""
    dias = dias_do_ciclo(inicio, fim)
    if not dias:
        return 0.0, False
    b = d["bandeira"]
    soma, estimado = 0.0, False
    for dia in dias:
        nome, est = ultimo_conhecido(b["acionada"], dia.strftime("%Y-%m"))
        soma += b["adicional"][nome]
        estimado = estimado or est
    return soma / len(dias) / 1000, estimado


def icms_da_faixa(d: dict, kwh: float) -> float:
    """F4 — alíquota (%) pela faixa do consumo do ciclo, em kWh inteiros."""
    inteiro = round(kwh)
    for ate, aliquota in d["icms"]["faixas"]:
        if ate is None or inteiro <= ate:
            return aliquota
    return d["icms"]["faixas"][-1][1]


def pis_cofins_do_mes(d: dict, fim: datetime.date) -> tuple[float, float, bool]:
    """F5 — PIS e COFINS (%) do mês da leitura."""
    (pis, cofins), est = ultimo_conhecido(d["pis_cofins"]["por_mes"], fim.strftime("%Y-%m"))
    return pis, cofins, est


def fator_de_tributos(icms: float, pis: float, cofins: float) -> float:
    """F6 — tributos "por dentro": ICMS sobre o bruto, PIS/COFINS sobre o
    líquido de ICMS. Alíquota impossível (100 % ou mais) dá fator zero."""
    den = (1 - icms / 100) * (1 - (pis + cofins) / 100)
    return 1 / den if den > 0 else 0.0


def consumo_projetado(kwh: float, inicio: datetime.date, fim: datetime.date, agora: datetime.datetime, *,
                      medido_desde: datetime.datetime | None = None,
                      fechado_kwh: float = 0.0, fechado_dias: float = 0.0) -> float:
    """F13 — o consumo que o ciclo em curso deve fechar. Serve só para escolher
    a faixa do ICMS e a da iluminação antes de o ciclo terminar.

        projetado = já medido + taxa diária × dias do ciclo que a medição não cobriu

    Os dias cobertos contam de `medido_desde` (ou do início do ciclo, o que
    for mais tarde): quem instala no meio do ciclo mediu só uma parte dele.
    A taxa é a do ciclo anterior (consumo ÷ dias MEDIDOS dele) quando ele
    cobriu ao menos um dia; sem isso, a do próprio ciclo, com o primeiro dia
    contado inteiro. Ciclo encerrado ou sem datas: o próprio consumo."""
    total = (fim - inicio).days
    comeco = datetime.datetime.combine(inicio, datetime.time.min)
    if total <= 0 or agora >= datetime.datetime.combine(fim, datetime.time.min):
        return kwh
    desde = max(comeco, medido_desde) if medido_desde is not None else comeco
    cobertos = max((agora - desde).total_seconds() / 86400, 0)
    taxa = fechado_kwh / fechado_dias if fechado_kwh > 0 and fechado_dias >= 1 else kwh / max(cobertos, 1)
    return kwh + taxa * max(total - cobertos, 0)


def consumo_de_faixa_do_fechado(kwh: float, dias: int, dias_medidos: float) -> float:
    """F13b — ciclo fechado que só foi medido em parte (o primeiro depois da
    instalação): a faixa é a do consumo na proporção dos dias. Medido por
    inteiro, ou sem saber quantos dias, é o próprio consumo."""
    return kwh * dias / dias_medidos if 1 <= dias_medidos < dias else kwh


def iluminacao_publica(d: dict, base_kwh: float, fim: datetime.date) -> tuple[float, bool]:
    """F10 — parcela fixa da faixa + coeficiente × (TEIP + bandeira do mês
    anterior ao da leitura), limitado ao teto."""
    ip = d["iluminacao_publica"]
    ante = (fim.replace(day=1) - datetime.timedelta(days=1)).strftime("%Y-%m")
    nome, est = ultimo_conhecido(d["bandeira"]["acionada"], ante)
    adicional = d["bandeira"]["adicional"][nome]
    for ate, fixa, coef in ip["faixas"]:
        if ate is None or base_kwh <= ate:
            if fixa == 0 and coef == 0:
                return 0.0, est
            return min(round(fixa + round(coef * (ip["teip_brl_mwh"] + adicional), 2), 2), ip["teto"]), est
    return 0.0, est


def calcula(d: dict, inicio: datetime.date, fim: datetime.date, kwh: float, *,
            kwh_ponta: float = 0.0, kwh_intermediario: float = 0.0,
            cosip_media_kwh: float = 0.0, outros_debitos: float = 0.0, creditos: float = 0.0,
            ajustes: dict | None = None, kwh_faixa: float | None = None) -> dict:
    """A fatura inteira. `kwh` é o consumo total do ciclo; ponta e
    intermediário só importam para a simulação da Tarifa Branca. `kwh_faixa`
    é o consumo que escolhe as faixas (ICMS e iluminação): o do ciclo, quando
    ele já fechou; o projetado (F13), enquanto corre."""
    if kwh_faixa is None:
        kwh_faixa = kwh
    aj = {k: v for k, v in (ajustes or {}).items() if v is not None}
    tarifa = aj.get("tarifa", d["tarifa"]["convencional"])
    bandeira, est_b = bandeira_do_ciclo(d, inicio, fim)
    if "bandeira" in aj:
        bandeira, est_b = aj["bandeira"], False
    icms = aj.get("icms", icms_da_faixa(d, kwh_faixa))
    pis, cofins, est_p = pis_cofins_do_mes(d, fim)
    if "pis" in aj:
        pis = aj["pis"]
    if "cofins" in aj:
        cofins = aj["cofins"]
    if "pis" in aj and "cofins" in aj:
        est_p = False
    fator = fator_de_tributos(icms, pis, cofins)                       # F6
    tarifa_com_bandeira = tarifa + bandeira                            # F3
    preco = tarifa_com_bandeira * fator                                # F7
    energia = kwh * preco                                              # F8
    icms_valor = energia * icms / 100                                  # F9
    base = energia - icms_valor
    ilum, est_i = iluminacao_publica(d, cosip_media_kwh if cosip_media_kwh > 0 else kwh_faixa, fim)
    if "iluminacao" in aj:
        ilum, est_i = aj["iluminacao"], False
    fixos = ilum + outros_debitos - creditos
    # F12 — a Branca troca só a tarifa de cada posto; bandeira e tributos são os mesmos
    br = d["tarifa"]["branca"]
    fora = kwh - kwh_ponta - kwh_intermediario
    energia_branca = (kwh_ponta * (br["ponta"] + bandeira) + kwh_intermediario * (br["intermediaria"] + bandeira)
                      + fora * (br["fora_ponta"] + bandeira)) * fator
    return {
        "preco_ponta": (br["ponta"] + bandeira) * fator,
        "preco_intermediario": (br["intermediaria"] + bandeira) * fator,
        "preco_fora_ponta": (br["fora_ponta"] + bandeira) * fator,
        "energia_branca": round(energia_branca, 2),
        "encargos": round(fixos, 2),
        "dias": len(dias_do_ciclo(inicio, fim)),
        "tarifa": tarifa, "bandeira": bandeira, "tarifa_com_bandeira": tarifa_com_bandeira,
        "icms": icms, "pis": pis, "cofins": cofins, "fator": fator, "preco": preco,
        "energia": round(energia, 2),
        "icms_valor": round(icms_valor, 2),
        "pis_valor": round(base * pis / 100, 2),
        "cofins_valor": round(base * cofins / 100, 2),
        "iluminacao": ilum,
        "total": round(energia + fixos, 2),                            # F11
        "total_branca": round(energia_branca + fixos, 2),
        "estimado": bool(est_b or est_p or est_i),
    }


# ── --confere ───────────────────────────────────────────────────────────────
CERTEZAS = ("lido na fonte", "deduzido de fatura")
SEM_PARAMETRO = ("distribuidora", "sem_fonte")     # blocos que não trazem parâmetro de cálculo


def sem_fonte(d: dict) -> list[str]:
    """Todo bloco de parâmetros diz de onde veio, o que a fonte diz, quando
    foi conferido e com que certeza. Vale para bloco que venha a ser criado:
    a lista não é fixa. Endereço só é dispensado no que vem da própria fatura."""
    faltas = []

    def confere(nome: str, fonte) -> None:
        if not isinstance(fonte, dict):
            faltas.append(f"{nome}: sem bloco de fonte")
            return
        for campo in ("documento", "citacao", "conferido_em", "certeza"):
            if not fonte.get(campo):
                faltas.append(f"{nome}: fonte sem '{campo}'")
        if fonte.get("certeza") and fonte["certeza"] not in CERTEZAS:
            faltas.append(f"{nome}: certeza '{fonte['certeza']}' não é uma de {CERTEZAS}")
        try:
            datetime.date.fromisoformat(str(fonte.get("conferido_em")))
        except ValueError:
            if fonte.get("conferido_em"):
                faltas.append(f"{nome}: 'conferido_em' não é data ({fonte['conferido_em']})")
        if not fonte.get("url") and fonte.get("certeza") != "deduzido de fatura":
            faltas.append(f"{nome}: fonte sem endereço")

    for grupo, bloco in d.items():
        if isinstance(bloco, dict) and grupo not in SEM_PARAMETRO:
            confere(grupo, bloco.get("fonte"))
    confere("bandeira.rateio", d.get("bandeira", {}).get("rateio", {}).get("fonte"))
    for nome, item in d.get("sem_fonte", {}).items():
        if item.get("certeza") != "sem fonte" or not item.get("tratamento"):
            faltas.append(f"sem_fonte.{nome}: tem de declarar certeza 'sem fonte' e o tratamento")
    return faltas


# tarifa e preço vêm impressos com 5 casas; a iluminação é valor de tabela e
# tem de sair exata; o resto, um centavo.
TOLERANCIA = {"tarifa_com_bandeira": 0.000006, "preco": 0.000011, "iluminacao": 0.001}


def confere(d: dict) -> int:
    falhas = 0
    for falta in sem_fonte(d):
        falhas += 1
        print(f"DADO SEM FONTE: {falta}")
    for caso in d["casos_de_conferencia"]:
        r = calcula(d, datetime.date.fromisoformat(caso["leitura_anterior"]),
                    datetime.date.fromisoformat(caso["leitura"]), caso["kwh"],
                    cosip_media_kwh=caso["cosip_media_kwh"], outros_debitos=caso["outros_debitos"],
                    creditos=caso["creditos"])
        ruins = [f"{k}: conta {v}, calculado {r[k]:.5f}" for k, v in caso["esperado"].items()
                 if abs(r[k] - v) > TOLERANCIA.get(k, 0.0101)]
        if r["estimado"]:
            ruins.append("usou valor estimado: falta no arquivo de dados algum mês deste ciclo")
        if ruins:
            falhas += 1
            for linha in ruins:
                print(f"CONTA NAO REPRODUZ: {caso['nome']} — {linha}")
        else:
            print(f"[OK] {caso['nome']}: {caso['kwh']} kWh em {r['dias']} dias → {r['total']:.2f} "
                  f"(conta: {caso['esperado']['total']:.2f}) · preço {r['preco']:.5f} · "
                  f"iluminação {r['iluminacao']:.2f}")
    # os preços com tributos que a distribuidora publica, um por faixa de ICMS
    precos = d["casos_de_preco"]
    for caso in precos["casos"]:
        dia = datetime.date.fromisoformat(d["atualizado_em"])
        r = calcula(d, dia - datetime.timedelta(days=30), dia, caso["kwh"], ajustes=precos["ajustes"])
        if abs(r["preco"] - caso["preco"]) > TOLERANCIA["preco"]:
            falhas += 1
            print(f"CONTA NAO REPRODUZ: preço publicado, {caso['nome']} — tabela {caso['preco']}, "
                  f"calculado {r['preco']:.5f} (ICMS {r['icms']} %)")
        else:
            print(f"[OK] preço publicado, {caso['nome']}: {caso['kwh']} kWh → ICMS {r['icms']:g} % → "
                  f"{r['preco']:.5f} (tabela: {caso['preco']:.5f})")
    if falhas:
        print(f"RESULTADO: {falhas} falha(s)")
        return 3
    print("FATURAS OK")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dados", default=str(DADOS))
    ap.add_argument("--confere", action="store_true")
    ap.add_argument("--inicio", help="data da leitura anterior (AAAA-MM-DD)")
    ap.add_argument("--fim", help="data da leitura atual (AAAA-MM-DD)")
    ap.add_argument("--kwh", type=float)
    ap.add_argument("--ponta", type=float, default=0.0)
    ap.add_argument("--intermediario", type=float, default=0.0)
    ap.add_argument("--cosip-media", type=float, default=0.0)
    ap.add_argument("--outros", type=float, default=0.0)
    ap.add_argument("--creditos", type=float, default=0.0)
    for nome in AJUSTES:
        ap.add_argument(f"--ajuste-{nome}", type=float)
    o = ap.parse_args()
    d = carrega(Path(o.dados))
    if o.confere:
        return confere(d)
    if not (o.inicio and o.fim and o.kwh is not None):
        ap.error("informe --confere, ou --inicio, --fim e --kwh")
    r = calcula(d, datetime.date.fromisoformat(o.inicio), datetime.date.fromisoformat(o.fim), o.kwh,
                kwh_ponta=o.ponta, kwh_intermediario=o.intermediario, cosip_media_kwh=o.cosip_media,
                outros_debitos=o.outros, creditos=o.creditos,
                ajustes={n: getattr(o, f"ajuste_{n}") for n in AJUSTES})
    print(json.dumps(r, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
