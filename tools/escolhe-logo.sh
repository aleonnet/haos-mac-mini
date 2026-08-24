#!/usr/bin/env bash
# =============================================================================
# escolhe-logo.sh — desenha as variantes do logo, uma depois da outra.
#
# Existe porque a escolha é dele e é visual: número não decide se um logo ficou
# "menor e delicado". A variante 0 é o lib/haos-ui.sh ATUAL, sourceado como
# está — a comparação é com o que roda hoje, não com uma reconstrução. As
# demais saem de tools/gera-logo.py na hora.
#
# NADA aqui altera a lib. Depois de escolher:
#     ./tools/gera-logo.py --variante N   > o fragmento a aplicar
#
#   ./tools/escolhe-logo.sh            todas, animadas
#   ./tools/escolhe-logo.sh --so 2     só a variante 2
#   ./tools/escolhe-logo.sh --parado   um quadro estático de cada
#
# ANDAIME: sai do repositório quando a escolha estiver aplicada. A função
# desenha_faixa() abaixo é a que vai para lib/haos-ui.sh no mesmo passo — se
# você editar uma, edite a outra.
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=../lib/haos-ui.sh
source "$RAIZ/lib/haos-ui.sh"

PARADO=0
SO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --parado)  PARADO=1 ;;
    --so)      SO="${2:-}"; shift ;;
    -h|--help) sed -n '3,17p' "$0"; exit 0 ;;
    *)         printf 'opção desconhecida: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# A biblioteca não instala trap — quem usa é que cuida do cursor.
escolhe_cleanup() { ha_show_cursor; }
trap escolhe_cleanup EXIT INT TERM

if [[ "$HAOS_UI_UTF8" == 0 ]] || [[ "$HAOS_UI_DEPTH" == 0 ]]; then
  printf 'Sem UTF-8 ou sem cor: o logo não desenha neste terminal.\n' >&2
  printf 'A camada visual degrada para texto, e é isso que o produto faz.\n' >&2
  exit 1
fi

# ── render da FAIXA ──────────────────────────────────────────────────────────
# O contorno de 1 px do lib atual anda por ÍNDICE de pixel. Uma faixa espessa
# não pode: vários pixels dividem a mesma posição no caminho, e fatiar por
# índice faria a cabeça avançar em espiral em vez de contornar. Aqui cabeça e
# cauda andam em posição de ARCO (HA_TT), que é o que o gerador grava.
desenha_faixa() {
  local n="$1" y1 y2 x c1 c2 saida chave
  ha_logo_init

  local -a linha_acesa
  if [ "$n" -ge 0 ]; then
    local meio=$(( HA_QUADROS / 2 )) cabeca cauda i tt ty
    if [ "$n" -lt "$meio" ]; then
      cabeca=$(( n * HA_CAMINHO / meio )); cauda=0                  # desenha
    else
      cabeca=$HA_CAMINHO; cauda=$(( (n - meio) * HA_CAMINHO / meio ))  # retrai
    fi
    local total=${#HA_TX[@]}
    for (( i = 0; i < total; i++ )); do
      tt=${HA_TT[i]}
      [ "$tt" -lt "$cauda" ] && continue
      # HA_TT sai ordenado do gerador, então o primeiro fora da janela encerra.
      [ "$tt" -ge "$cabeca" ] && break
      ty=${HA_TY[i]}
      linha_acesa[ty]="${linha_acesa[ty]:- } ${HA_TX[i]} "
    done
  fi

  for (( y1 = 0; y1 < HA_H; y1 += 2 )); do
    y2=$(( y1 + 1 ))
    saida=''
    for (( x = 0; x < HA_W; x++ )); do
      c1="${HA_MASK[$y1]:$x:1}"
      c2="${HA_MASK[$y2]:$x:1}"
      case "${linha_acesa[$y1]:-}" in *" $x "*) c1='t' ;; esac
      case "${linha_acesa[$y2]:-}" in *" $x "*) c2='t' ;; esac
      chave="$c1$c2"
      case "$chave" in
        '..') saida+="${NC} " ;;
        '.#') saida+="${NC}${HA_FG_AZUL}▄" ;;
        '.o') saida+="${NC}${HA_FG_BRANCO}▄" ;;
        '.t') saida+="${NC}${HA_FG_TRACO}▄" ;;
        '#.') saida+="${NC}${HA_FG_AZUL}▀" ;;
        'o.') saida+="${NC}${HA_FG_BRANCO}▀" ;;
        't.') saida+="${NC}${HA_FG_TRACO}▀" ;;
        '##') saida+="${HA_FG_AZUL}${HA_BG_AZUL}▀" ;;
        'oo') saida+="${HA_FG_BRANCO}${HA_BG_BRANCO}▀" ;;
        'tt') saida+="${HA_FG_TRACO}${HA_BG_TRACO}▀" ;;
        '#o') saida+="${HA_FG_AZUL}${HA_BG_BRANCO}▀" ;;
        'o#') saida+="${HA_FG_BRANCO}${HA_BG_AZUL}▀" ;;
        '#t') saida+="${HA_FG_AZUL}${HA_BG_TRACO}▀" ;;
        't#') saida+="${HA_FG_TRACO}${HA_BG_AZUL}▀" ;;
        'ot') saida+="${HA_FG_BRANCO}${HA_BG_TRACO}▀" ;;
        'to') saida+="${HA_FG_TRACO}${HA_BG_BRANCO}▀" ;;
        *)    saida+="${NC} " ;;
      esac
    done
    printf '%s%s\n' "$saida" "$NC"
  done
}

anima() {   # anima <função-de-quadro>
  local desenhar="$1" n
  if [ "$PARADO" = "1" ]; then
    "$desenhar" -1
    return 0
  fi
  # O laço sobe o cursor HA_H/2 linhas antes de cada quadro, então precisa
  # dessas linhas já existirem abaixo do cabeçalho.
  for (( n = 0; n < HA_H / 2; n++ )); do printf '\n'; done
  _hide
  for (( n = 0; n < HA_QUADROS; n++ )); do
    printf '\033[%dA' "$(( HA_H / 2 ))"
    "$desenhar" "$n"
    sleep 0.055
  done
  _show
}

cabecalho() {   # cabecalho <n> <titulo> <medida>
  printf '\n\033[1m  variante %s — %s\033[0m\n' "$1" "$2"
  printf '  \033[2m%s\033[0m\n\n' "$3"
}

espera() {
  if [ -t 0 ]; then
    printf '\n  \033[2m[Enter] próxima · [q] sair\033[0m '
    local k; IFS= read -r k
    case "$k" in q|Q) exit 0 ;; esac
  else
    printf '\n'
  fi
}

# ── variante 0: o lib ATUAL, exatamente como está ────────────────────────────
mostra_atual() {
  clear 2>/dev/null || true
  local med
  med="$(python3 - "$RAIZ/lib/haos-ui.sh" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
mask = [l.strip().strip("'") for l in re.search(r"HA_MASK=\(\n(.*?)\n\)", s, re.S).group(1).split("\n")]
bx = [int(v) for v in re.search(r"HA_BX=\((.*?)\)", s, re.S).group(1).split()]
by = [int(v) for v in re.search(r"HA_BY=\((.*?)\)", s, re.S).group(1).split()]
casa = sum(1 for r in mask for c in r if c in '#o')
come = sum(1 for x, y in zip(bx, by) if mask[y][x] in '#o')
print(f"canvas={len(mask[0])}x{len(mask)}px ({len(mask[0])} col x {len(mask)//2} linhas)  "
      f"casa={casa}  traco={len(bx)}  come={come} ({100.0*come/casa:.1f}%)  "
      f"traco/casa={len(bx)/casa:.2f}")
PY
)"
  cabecalho 0 "o que roda HOJE — contorno de 1 px" "$med"
  anima ha_logo_quadro
  espera
}

# ── variantes 1..7: geradas na hora ──────────────────────────────────────────
mostra_variante() {   # mostra_variante <n> <rotulo>
  local v="$1" rotulo="$2" frag med
  frag="$(mktemp)"
  if ! python3 "$RAIZ/tools/gera-logo.py" --variante "$v" > "$frag" 2>&1; then
    printf 'variante %s falhou:\n' "$v" >&2; cat "$frag" >&2; rm -f "$frag"; return 1
  fi
  med="$(python3 "$RAIZ/tools/gera-logo.py" --variante "$v" --medir | tail -1)"
  (
    # shellcheck disable=SC1090
    source "$frag"
    clear 2>/dev/null || true
    cabecalho "$v" "$rotulo" "$med"
    anima desenha_faixa
    espera
  )
  local rc=$?
  rm -f "$frag"
  return $rc
}

# bash 3.2 não tem array associativo, e indireção por eval é opaca para a
# análise estática, que reprovou — com razão. Uma função com case diz o mesmo
# sem eval. (E o comentário não pode começar com a palavra reservada que a
# ferramenta lê como diretiva: ela tenta parsear e reprova o arquivo inteiro.)
rotulo_de() {
  case "$1" in
    1) printf '%s' "casa 24 · traço 2.0 — o mais discreto dos que não comem a casa" ;;
    2) printf '%s' "casa 24 · traço 2.6 — meio-termo" ;;
    3) printf '%s' "casa 24 · traço 3.0 — traço marcado" ;;
    4) printf '%s' "casa 20 · traço 2.6 — o menor de todos, 32 colunas" ;;
    5) printf '%s' "casa 28 · traço 2.6 · ápice mais redondo — casa maior, sem entalhe" ;;
    6) printf '%s' "casa 28 · traço 2.6 · ápice normal — MOSTRA o entalhe no bico (3,4%%)" ;;
    7) printf '%s' "casa 24 · traço 3.6 — traço bem grosso, o extremo do pedido" ;;
    *) printf 'variante %s' "$1" ;;
  esac
}

VARIANTES="1 2 3 4 5 6 7"

if [ -n "$SO" ]; then
  if [ "$SO" = "0" ]; then mostra_atual; else mostra_variante "$SO" "$(rotulo_de "$SO")"; fi
  exit 0
fi

mostra_atual
for v in $VARIANTES; do
  mostra_variante "$v" "$(rotulo_de "$v")" || exit 1
done

clear 2>/dev/null || true
printf '\n\033[1m  Resumo\033[0m\n\n'
# A coluna ASCII vem primeiro de propósito: o printf do bash pada por BYTE, não
# por caractere, então rótulo acentuado no meio desalinharia a tabela.
printf '  %-4s %-14s %s\n' "#" "come da casa" "geometria"
printf '  %-4s %-14s %s\n' "0" "8,0%" "48 px, contorno de 1 px — o que roda hoje"
for v in $VARIANTES; do
  med="$(python3 "$RAIZ/tools/gera-logo.py" --variante "$v" --medir | tail -1)"
  come="$(printf '%s' "$med" | sed -n 's/.*come=[0-9]* (\([^)]*\)).*/\1/p')"
  rot="$(rotulo_de "$v")"
  printf '  %-4s %-14s %s\n' "$v" "$come" "${rot%% —*}"
done
printf '\n  Escolhida a variante N, o próximo passo é aplicá-la à lib.\n'
printf '  \033[2mReferência: a tentativa reprovada (84d15a1) comia 42,1%%.\033[0m\n\n'
