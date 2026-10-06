#!/usr/bin/env python3
"""
tarifas-bloco.py — leva o arquivo de dados da tarifa para dentro do package.

A fonte da verdade dos parâmetros da fatura é tarifas/energia_light_rj.json
(cada número com fonte). O package de energia não pode ler arquivo ao lado —
viaja embutido no instalador —, então dois blocos dele são GERADOS daqui:

  DADOS DA FATURA     o sensor que publica os parâmetros como atributos
  POSTOS TARIFARIOS   a automação que troca o posto nos horários da distribuidora

Editar um bloco à mão é o erro que isto existe para tornar detectável.

    ./tools/tarifas-bloco.py           regenera os dois blocos
    ./tools/tarifas-bloco.py --check   só confere (exit 3 se divergir)

Só biblioteca padrão. Token de falha: DIVERGE
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DADOS = RAIZ / "tarifas" / "energia_light_rj.json"
PACOTE = RAIZ / "packages" / "energia_br.yaml"
ORIGEM = "tools/tarifas-bloco.py a partir de tarifas/energia_light_rj.json; não edite à mão"


def literal(valor, largura: int = 96, recuo: str = "            ") -> str:
    """O valor como literal de template, quebrado em linhas curtas. O `repr`
    do Python é literal válido no motor de templates (None, True e False
    incluídos), e número de ponto flutuante volta idêntico."""
    if isinstance(valor, dict):
        itens = [f"{k!r}: {v!r}" for k, v in valor.items()]
        abre, fecha = "{", "}"
    else:
        itens = [repr(v) for v in valor]
        abre, fecha = "[", "]"
    linhas, atual = [], "{{ " + abre
    for n, item in enumerate(itens):
        pedaco = item + ("," if n < len(itens) - 1 else "")
        if len(atual) + len(pedaco) + 1 > largura:
            linhas.append(atual)
            atual = "   " + pedaco
        else:
            atual += ("" if atual.endswith(abre) else " ") + pedaco
    linhas.append(atual + fecha + " }}")
    return ("\n" + recuo).join(linhas)


def bloco_dados(d: dict) -> str:
    t, b, ip = d["tarifa"], d["bandeira"], d["iluminacao_publica"]
    escalares = [
        ("distribuidora", json.dumps(d["distribuidora"]["nome"], ensure_ascii=False)),
        ("vigencia_fim", json.dumps(t["vigencia_fim"])),
        ("tarifa_convencional", f'"{{{{ {t["convencional"]!r} }}}}"'),
        ("tarifa_ponta", f'"{{{{ {t["branca"]["ponta"]!r} }}}}"'),
        ("tarifa_intermediaria", f'"{{{{ {t["branca"]["intermediaria"]!r} }}}}"'),
        ("tarifa_fora_ponta", f'"{{{{ {t["branca"]["fora_ponta"]!r} }}}}"'),
        ("ip_teip", f'"{{{{ {ip["teip_brl_mwh"]!r} }}}}"'),
        ("ip_teto", f'"{{{{ {ip["teto"]!r} }}}}"'),
    ]
    compostos = [
        ("bandeira_adicional", b["adicional"]),
        ("bandeira_acionada", b["acionada"]),
        ("icms_faixas", d["icms"]["faixas"]),
        ("pis_cofins", d["pis_cofins"]["por_mes"]),
        ("ip_faixas", ip["faixas"]),
    ]
    s = [
        '      - name: "Dados da Fatura"',
        "        unique_id: dados_da_fatura",
        "        icon: mdi:database-outline",
        f'        state: "{d["atualizado_em"]}"',
        "        attributes:",
    ]
    s += [f"          {nome}: {valor}" for nome, valor in escalares]
    for nome, valor in compostos:
        s += [f"          {nome}: >-", "            " + literal(valor)]
    return "\n".join(s) + "\n"


def bloco_postos(d: dict) -> str:
    p = d["postos"]
    antes = p.get("intermediario_inicio")      # só onde há intermediário ANTES da ponta
    gatilhos = ([(antes, "shoulder")] if antes else []) + [
        (p["ponta_inicio"], "peak"), (p["ponta_fim"], "shoulder"), (p["intermediario_fim"], "offpeak")]
    inter = f"'{p['ponta_fim']}' <= agora < '{p['intermediario_fim']}'"
    if antes:
        inter = f"'{antes}' <= agora < '{p['ponta_inicio']}' or " + inter
    s = [
        "  - id: energia_br_posto_tarifario",
        '    alias: "Energia BR — seleciona o posto tarifário"',
        "    description: >",
        "      Troca o posto dos três medidores nos horários da distribuidora. Em dia",
        "      não útil tudo é fora de ponta. Recalcula no início do Home Assistant e",
        "      quando o dia útil muda, para não ficar preso no posto errado.",
        "    mode: single",
        "    trigger:",
    ]
    for hora, posto in gatilhos:
        s += ["      - platform: time", f'        at: "{hora}:00"', f"        variables: {{posto: {posto}}}"]
    s += [
        "      - platform: state",
        "        entity_id: binary_sensor.workday_sensor",
        "        variables: {posto: recalcular}",
        "      - platform: homeassistant",
        "        event: start",
        "        variables: {posto: recalcular}",
        "    action:",
        "      - variables:",
        "          util: \"{{ is_state('binary_sensor.workday_sensor','on') }}\"",
        "          agora: \"{{ now().strftime('%H:%M') }}\"",
        "          alvo: >",
        "            {% if not util %}offpeak",
        "            {% elif posto != 'recalcular' %}{{ posto }}",
        f"            {{% elif '{p['ponta_inicio']}' <= agora < '{p['ponta_fim']}' %}}peak",
        f"            {{% elif {inter} %}}shoulder",
        "            {% else %}offpeak",
        "            {% endif %}",
        "      - service: select.select_option",
        "        target:",
        "          entity_id:",
        "            - select.daily_energy",
        "            - select.monthly_energy",
        "            - select.fatura_energy",
        "        data:",
        '          option: "{{ alvo | trim }}"',
    ]
    return "\n".join(s) + "\n"


BLOCOS = (("DADOS DA FATURA", "      ", bloco_dados), ("POSTOS TARIFARIOS", "  ", bloco_postos))


def marcadores(nome: str, recuo: str) -> tuple[str, str]:
    return f"{recuo}# >>> {nome} — gerado por {ORIGEM} >>>\n", f"{recuo}# <<< {nome} <<<\n"


def main() -> int:
    confere = sys.argv[1:] == ["--check"]
    if sys.argv[1:] and not confere:
        print(__doc__)
        return 2
    d = json.loads(DADOS.read_text(encoding="utf-8"))
    texto = PACOTE.read_text(encoding="utf-8")
    falhou = False
    for nome, recuo, gera in BLOCOS:
        abre, fecha = marcadores(nome, recuo)
        if texto.count(abre) != 1 or texto.count(fecha) != 1:
            print(f"[ERRO] {PACOTE.relative_to(RAIZ)}: marcadores do bloco {nome} ausentes ou repetidos",
                  file=sys.stderr)
            return 3
        ini, fim = texto.index(abre) + len(abre), texto.index(fecha)
        novo = gera(d)
        if texto[ini:fim] == novo:
            if confere:
                print(f"[OK] bloco {nome} do package idêntico ao gerado de {DADOS.relative_to(RAIZ)}")
            continue
        if confere:
            print(f"[ERRO] bloco {nome} do package DIVERGE de {DADOS.relative_to(RAIZ)} — "
                  "rode ./tools/tarifas-bloco.py", file=sys.stderr)
            falhou = True
            continue
        texto = texto[:ini] + novo + texto[fim:]
        print(f"[OK] bloco {nome} regenerado ({novo.count(chr(10))} linhas)")
    if confere:
        return 3 if falhou else 0
    if texto != PACOTE.read_text(encoding="utf-8"):
        PACOTE.write_text(texto, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
