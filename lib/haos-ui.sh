#!/usr/bin/env bash
# haos-ui.sh — camada visual do instalador do HAOS, identidade Home Assistant.
# Source it as a library, or run it directly for the demo:  ./lib/haos-ui.sh --demo
#
# Design notes:
#   - Palette is Home Assistant's own: #03A9F4 primary, #00E5FF cyan, #FFC107 amber.
#   - Truecolor when available, 256-color fallback, plain text when neither.
#   - Every animation degrades to a single static frame when stdout is not a TTY,
#     when NO_COLOR is set, or when --no-anim is passed. A piped log stays readable.
set -uo pipefail

# ── capability detection ────────────────────────────────────────────────────
HAOS_UI_ANIM=1
[[ -t 1 ]] || HAOS_UI_ANIM=0
[[ -n "${NO_COLOR:-}" ]] && HAOS_UI_ANIM=0
[[ "${HAOS_NO_ANIM:-0}" == "1" ]] && HAOS_UI_ANIM=0

# ── UTF-8 ────────────────────────────────────────────────────────────────────
# A arte é toda de caracteres multibyte. Sob locale C o bash conta e fatia
# BYTES: `${linha:col:1}` devolveria um terço de caractere, e a tela receberia
# UTF-8 inválido. Medido em 23/08 num Mac mini por SSH, onde LC_CTYPE=C: a
# mesma linha media 42 aqui e 118 lá.
#
# E se o locale não é UTF-8, o terminal provavelmente não desenha os glifos de
# qualquer forma. Então a resposta certa não é forçar o locale do usuário — é
# degradar para texto simples.
HAOS_UI_UTF8=0
if [ "$(LC_ALL="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" /bin/bash -c 's=▟▙; printf %s "${#s}"')" = "2" ]; then
  HAOS_UI_UTF8=1
fi
[[ "$HAOS_UI_UTF8" == 0 ]] && HAOS_UI_ANIM=0

case "${COLORTERM:-}" in
  truecolor|24bit) HAOS_UI_DEPTH=24 ;;
  *) [[ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]] && HAOS_UI_DEPTH=8 || HAOS_UI_DEPTH=0 ;;
esac
[[ -t 1 ]] || HAOS_UI_DEPTH=0
[[ -n "${NO_COLOR:-}" ]] && HAOS_UI_DEPTH=0

# ── Home Assistant palette ──────────────────────────────────────────────────
# Compatível com bash 3.2 (o que o macOS traz): sem namerefs, sem array indirection.
HA_BLUE_R=3;    HA_BLUE_G=169; HA_BLUE_B=244    # #03A9F4  primary
HA_CYAN_R=0;    HA_CYAN_G=229; HA_CYAN_B=255    # #00E5FF  accent
HA_DEEP_R=1;    HA_DEEP_G=87;  HA_DEEP_B=155    # #01579B  deep
if [[ "$HAOS_UI_DEPTH" == 0 ]]; then NC=''; BOLD=''; DIM=''
else NC=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; fi

# ── glifos, com fallback ASCII ───────────────────────────────────────────────
# UMA fonte para todo caractere multibyte das linhas de status. Sob locale
# não-UTF-8 o terminal recebe os bytes crus de "✔" — medido num Mac mini por
# SSH com LC_CTYPE=C. A cerca do portão exercita ESTAS funções sob LC_ALL=C,
# não só o banner (achado B-3 da banca).
if [[ "$HAOS_UI_UTF8" == 1 ]]; then
  HA_G_OK='✔'; HA_G_INFO='•'; HA_G_WARN='▲'; HA_G_ERR='✖'; HA_G_SKIP='◦'
  HA_G_DOTS='…'; HA_G_REGUA='─'; HA_G_MARCA='▎'
  HA_G_SEP='·'; HA_G_DASH='—'
  HA_G_CHEIO='━'; HA_G_VAZIO='╌'; HA_G_BON='▰'; HA_G_BOFF='▱'
  HA_SPIN_F='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; HA_SPIN_N=10
else
  HA_G_OK='[OK]'; HA_G_INFO='[i]'; HA_G_WARN='[!]'; HA_G_ERR='[X]'; HA_G_SKIP='[-]'
  HA_G_DOTS='...'; HA_G_REGUA='-'; HA_G_MARCA='>'
  HA_G_SEP='-'; HA_G_DASH='--'
  HA_G_CHEIO='#'; HA_G_VAZIO='-'; HA_G_BON='#'; HA_G_BOFF='-'
  HA_SPIN_F='-\|/'; HA_SPIN_N=4
fi

rgb() { # rgb R G B -> escape
  case "$HAOS_UI_DEPTH" in
    24) printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3" ;;
    8)  printf '\033[38;5;%dm' "$(( 16 + 36*($1*5/255) + 6*($2*5/255) + ($3*5/255) ))" ;;
    *)  printf '' ;;
  esac
}
# Escapes pré-computados uma vez: mais rápido que um subshell por chamada.
C_BLUE="$(rgb 3 169 244)";   C_CYAN="$(rgb 0 229 255)"
C_AMBER="$(rgb 255 193 7)";  C_GREEN="$(rgb 76 175 80)"
C_RED="$(rgb 244 67 54)";    C_MUTED="$(rgb 96 125 139)"

# ── gradient across a string, HA_DEEP -> HA_BLUE -> HA_CYAN ─────────────────
ha_gradient() {
  local s="$1" n=${#1} i out='' t r g b
  (( n == 0 )) && return
  # Sob locale não-UTF-8, ${s:i:1} fatia BYTES: inserir escape de cor entre os
  # bytes de um caractere multibyte quebra a sequência na tela. Texto plano.
  if [[ "$HAOS_UI_DEPTH" == 0 || "$HAOS_UI_UTF8" == 0 ]]; then printf '%s' "$s"; return; fi
  for (( i=0; i<n; i++ )); do
    t=$(( i * 200 / (n>1 ? n-1 : 1) ))
    if (( t <= 100 )); then
      r=$(( HA_DEEP_R + (HA_BLUE_R-HA_DEEP_R)*t/100 ))
      g=$(( HA_DEEP_G + (HA_BLUE_G-HA_DEEP_G)*t/100 ))
      b=$(( HA_DEEP_B + (HA_BLUE_B-HA_DEEP_B)*t/100 ))
    else
      local u=$(( t-100 ))
      r=$(( HA_BLUE_R + (HA_CYAN_R-HA_BLUE_R)*u/100 ))
      g=$(( HA_BLUE_G + (HA_CYAN_G-HA_BLUE_G)*u/100 ))
      b=$(( HA_BLUE_B + (HA_CYAN_B-HA_BLUE_B)*u/100 ))
    fi
    out+="$(rgb "$r" "$g" "$b")${s:i:1}"
  done
  printf '%s%s' "$out" "$NC"
}

# ── cursor ───────────────────────────────────────────────────────────────────
# A biblioteca NÃO instala trap: `trap` é global do shell e quem chama por
# último vence — um trap aqui apagaria o cleanup do instalador. Quem usa chama
# ha_show_cursor no próprio cleanup.
_hide() { if [[ "$HAOS_UI_ANIM" == 1 ]]; then tput civis 2>/dev/null || true; fi; }
_show() { if [[ "$HAOS_UI_ANIM" == 1 ]]; then tput cnorm 2>/dev/null || true; fi; }
ha_show_cursor() { _show; }

# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────
# Geometria conferida contra o vídeo oficial: beiral, ápice pontudo,
# base com raio moderado. Máscara por pixel: . fora · # casa · o circuito.
# HA_TX/HA_TY/HA_TT: faixa do traço ordenada pela posição no caminho —
# cabeça e cauda animam por posição de ARCO, não por índice de pixel.
# HA_PX/HA_PY/HA_PD: pixels dos 3 discos (1 topo · 2 direita · 3 esquerda).
HA_W=34
HA_H=34
HA_CAMINHO=342
HA_MASK=(
'..................................'
'..................................'
'..................................'
'..................................'
'..................................'
'...............####...............'
'..............######..............'
'.............########.............'
'............##########............'
'...........############...........'
'..........######oo######..........'
'........#######oooo#######........'
'.......#######oooooo#######.......'
'......#########oooo#########......'
'.....##########oooo##########.....'
'....############oo############....'
'....############oo###ooo######....'
'....############oo##ooooo#####....'
'....############oo##ooooo#####....'
'....############oo##ooooo#####....'
'....######ooo###oo#oooooo#####....'
'....#####ooooo##ooooo#########....'
'....#####ooooo##oooo##########....'
'....#####ooooo##ooo###########....'
'....######ooooo#oo############....'
'....#########ooooo############....'
'....##########oooo############....'
'....###########ooo############....'
'....############oo############....'
'.....########################.....'
'..................................'
'..................................'
'..................................'
'..................................'
)
HA_TX=(16 16 15 15 14 14 13 13 12 12 11 11 10 10 9 9 8 8 7 7 6 6 5 5 5 4 4 3 3 4 3 2 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 3 4 4 4 5 5 5 6 6 6 7 7 7 8 8 8 9 9 9 10 10 10 11 11 12 12 12 13 13 13 14 14 14 15 15 15 16 16 17 17 18 18 18 19 19 20 19 20 20 21 21 22 21 23 22 23 24 23 24 25 24 25 26 25 26 26 27 27 28 27 28 29 28 29 30 29 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 31 30 29 30 29 30 29 28 28 28 27 27 26 26 25 25 24 24 23 23 22 22 21 21 20 20 19 19 18 18 17 17)
HA_TY=(30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 31 30 29 30 29 30 29 28 28 28 27 27 26 26 25 25 24 24 23 23 22 22 21 21 20 20 19 19 18 18 17 17 16 16 15 15 14 15 14 13 14 13 12 13 12 11 12 11 10 11 10 9 10 9 8 9 8 7 8 7 8 7 6 7 6 5 6 5 4 5 4 3 4 3 3 4 3 4 5 4 5 5 6 6 7 6 7 7 8 7 8 8 8 9 9 9 10 10 10 11 11 12 11 12 12 13 13 13 14 14 14 15 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 28 29 29 30 30 29 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31)
HA_TT=(2 2 6 6 10 10 14 14 18 18 22 22 26 26 30 30 34 34 38 38 42 42 44 45 46 47 49 49 51 52 53 54 56 56 60 60 64 64 68 68 72 72 76 76 80 80 84 84 88 88 92 92 96 96 100 100 103 104 105 105 108 110 110 113 116 116 119 121 122 124 127 127 130 133 133 135 138 138 141 144 144 147 147 150 152 153 155 158 158 161 163 164 166 168 169 170 172 173 174 176 178 179 181 184 184 187 189 190 192 195 195 198 198 201 204 204 207 209 209 212 215 215 218 220 221 223 226 226 229 232 232 234 237 237 238 239 242 242 246 246 250 250 254 254 258 258 262 262 266 266 270 270 274 274 278 278 282 282 286 286 288 289 290 291 293 293 295 296 297 298 300 300 304 304 308 308 312 312 316 316 320 320 324 324 328 328 332 332 336 336 340 340)
HA_PX=(16 17 15 16 17 18 14 15 16 17 18 19 15 16 17 18 15 16 17 18 21 22 23 20 21 22 23 24 20 21 22 23 24 20 21 22 23 24 10 11 12 21 22 23 24 9 10 11 12 13 9 10 11 12 13 9 10 11 12 13 10 11 12)
HA_PY=(10 10 11 11 11 11 12 12 12 12 12 12 13 13 13 13 14 14 14 14 16 16 16 17 17 17 17 17 18 18 18 18 18 19 19 19 19 19 20 20 20 20 20 20 20 21 21 21 21 21 22 22 22 22 22 23 23 23 23 23 24 24 24)
HA_PD=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 3 3 3 2 2 2 2 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3)
# Partículas do assemble: destino (AX,AY), origem (AOX,AOY), atraso (ADL).
HA_AX=(15 16 17 18 14 15 16 17 18 19 13 14 15 16 17 18 19 20 12 13 14 15 16 17 18 19 20 21 11 12 13 14 15 16 17 18 19 20 21 22 10 11 12 13 14 15 16 17 18 19 20 21 22 23 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28)
HA_AY=(5 5 5 5 6 6 6 6 6 6 7 7 7 7 7 7 7 7 8 8 8 8 8 8 8 8 8 8 9 9 9 9 9 9 9 9 9 9 9 9 10 10 10 10 10 10 10 10 10 10 10 10 10 10 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29)
HA_AOX=(33 36 39 41 32 35 39 42 45 41 27 30 34 37 41 44 47 50 23 26 30 33 37 41 45 48 51 45 19 22 25 29 34 38 43 47 43 45 47 49 13 16 20 24 29 30 35 39 43 47 50 52 54 55 8 9 11 14 17 21 26 32 39 38 42 46 49 50 52 53 54 55 4 5 6 8 10 13 18 24 31 33 39 44 48 50 52 53 54 55 46 47 0 0 0 1 3 5 8 14 19 26 34 42 48 52 54 55 47 47 48 49 49 50 -5 -5 -5 0 0 1 2 4 8 13 22 35 40 46 49 50 50 51 51 51 52 44 45 45 -5 -6 -6 -7 -7 -7 -1 -1 0 1 5 13 30 49 55 47 47 47 47 47 48 48 49 49 42 43 -7 -7 -8 -9 -9 -10 -10 -4 -4 -4 -4 -1 13 53 51 50 42 43 43 44 44 45 46 46 47 41 -7 -8 -9 -10 -11 -12 -13 -14 -8 -9 -11 -14 -17 20 36 40 42 38 39 40 41 42 43 43 44 45 -8 -9 -10 -11 -12 -14 -15 -17 -18 -12 -14 -15 -11 4 20 28 33 37 34 36 37 38 39 40 41 42 -16 -10 -11 -12 -13 -15 -16 -18 -19 -21 -13 -12 -8 0 11 20 26 30 33 31 33 35 36 37 38 39 -17 -18 -11 -12 -14 -15 -16 -18 -19 -20 -20 -10 -6 0 7 14 20 24 28 31 29 31 33 34 35 37 -17 -18 -19 -12 -13 -15 -16 -17 -18 -18 -18 -15 -5 0 5 10 15 20 23 26 29 28 30 31 33 34 -17 -18 -19 -21 -13 -14 -15 -16 -16 -16 -16 -13 -10 0 3 8 12 16 20 23 25 28 27 29 30 31 -16 -18 -19 -20 -21 -13 -14 -15 -15 -15 -14 -12 -9 -5 3 6 10 13 17 20 22 25 27 26 28 29 -16 -17 -18 -19 -20 -21 -13 -13 -13 -13 -12 -10 -8 -5 -1 5 8 11 14 17 20 22 24 26 25 27 -15 -16 -17 -18 -19 -20 -20 -12 -12 -11 -10 -9 -7 -4 -1 1 7 10 12 15 17 20 22 24 26 25 -14 -15 -16 -17 -18 -18 -19 -19 -10 -10 -9 -8 -6 -4 -1 0 3 9 11 13 15 18 20 22 23 25 -13 -14 -15 -16 -16 -17 -17 -17 -17 -9 -8 -7 -5 -3 -1 0 3 5 10 12 14 16 18 20 21 23 -21 -13 -14 -15 -15 -16 -16 -16 -16 -15 -7 -6 -5 -3 -1 0 2 4 7 11 13 14 16 18 20 21 -20 -21 -12 -13 -13 -14 -14 -13 -13 -12 -11 -3 -2 0 0 2 4 6 8 10 13 15 17 18)
HA_AOY=(-8 -8 -7 -5 -13 -13 -12 -10 -8 -1 -12 -12 -11 -10 -9 -7 -4 -2 -12 -13 -12 -12 -10 -8 -6 -3 0 5 -14 -15 -15 -15 -14 -12 -10 -7 0 3 6 9 -17 -18 -19 -19 -19 -10 -8 -6 -3 0 3 7 10 13 -12 -13 -15 -16 -17 -18 -18 -17 -14 -4 -1 2 6 10 13 16 19 21 -10 -12 -13 -15 -16 -18 -19 -19 -18 -8 -4 0 4 9 13 17 20 23 23 24 -10 -12 -13 -15 -17 -18 -20 -13 -14 -14 -11 -6 0 7 13 18 21 23 25 27 28 30 -11 -13 -14 -8 -9 -11 -13 -15 -17 -19 -20 -16 -2 6 14 19 23 26 28 30 32 30 31 32 -7 -8 -9 -10 -11 -13 -7 -8 -10 -12 -15 -18 -17 -2 13 21 26 28 31 32 34 35 36 37 33 34 -4 -5 -6 -7 -8 -9 -10 -4 -5 -7 -9 -12 -18 13 30 35 33 34 35 36 37 38 39 39 40 35 -2 -2 -3 -3 -4 -4 -4 -5 0 0 1 4 20 52 48 46 45 39 39 39 40 40 41 41 42 42 0 0 0 0 0 0 0 1 2 8 12 19 34 49 52 51 50 49 42 42 42 42 43 43 43 44 -1 2 2 3 3 4 5 7 9 13 19 27 37 46 51 52 52 52 51 43 43 44 44 44 45 45 1 1 5 6 7 8 9 12 15 20 26 30 38 44 49 51 52 52 52 52 44 44 45 45 45 46 4 4 5 9 10 11 13 16 20 24 30 37 38 43 47 49 51 52 52 53 53 45 45 46 46 46 7 7 8 10 13 14 17 19 23 27 32 38 44 42 45 48 50 51 52 53 53 53 45 46 46 47 9 10 11 13 15 17 19 22 25 29 34 39 43 48 44 46 48 50 51 52 53 53 54 46 46 47 11 12 14 15 17 20 21 24 27 31 35 39 43 47 50 45 47 49 50 51 52 53 53 54 46 46 13 14 16 18 20 22 25 25 28 32 35 39 42 46 49 52 46 47 49 50 51 52 53 53 54 46 15 16 18 20 22 24 27 30 29 32 35 39 42 45 48 51 53 46 48 49 50 51 52 53 53 54 17 18 19 21 23 25 28 31 34 33 35 38 41 44 47 49 51 53 46 48 49 50 51 52 53 54 18 19 21 22 24 27 29 32 35 38 35 38 41 43 46 48 50 52 54 47 48 49 50 51 52 53 21 23 23 25 27 29 32 34 37 40 43 39 41 44 46 48 50 52 53 55 47 48 49 50)
HA_ADL=(9 10 11 9 10 11 9 10 11 9 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1)
# Centros dos discos (sonar), em pixel inteiro: topo, direita, esquerda.
HA_SCX=(17 22 11)
HA_SCY=(12 18 22)

# ── a abertura: constelação → traço → sonar → respiração ─────────────────────
# Quatro atos, ~3 s. O que cada um é, e por quê:
#   1. CONSTELAÇÃO — cada pixel da casa é uma partícula que voa de fora da
#      tela em trajetória radial (com um giro de 40°) e ASSENTA no lugar,
#      construindo a casa de baixo para cima. Trajetórias pré-computadas pelo
#      gerador; o runtime só interpola inteiros.
#   2. O TRAÇO OFICIAL — a caneta branca desenha o contorno INTEIRO e se
#      retrai, por posição de arco (conferido contra o vídeo do logo).
#   3. SONAR — cada disco do circuito emite dois anéis ciano que varrem o
#      corpo azul: os dispositivos entrando na rede, visível.
#   4. RESPIRAÇÃO — o azul pulsa uma vez mais claro e assenta.
# O corpo azul tem GRADIENTE VERTICAL (mais claro no topo): volume, não sprite.
# Sem animação: um quadro final parado. Sem UTF-8 ou sem cor: só o título.

HA_MIN_COLS=36
HA_ATRASO=0.03
HA_A_DUR=8           # quadros de voo de cada partícula
HA_Q_MONTA=22        # constelação (delay máx + voo)
HA_Q_TRACO=34        # metade desenha, metade retrai
HA_Q_SONAR=15        # 3 discos x 5 raios
HA_Q_GLOW=5
HA_QUADROS=$(( HA_Q_MONTA + HA_Q_TRACO + HA_Q_SONAR + HA_Q_GLOW ))
HA_LINHAS=$(( HA_H / 2 ))

ha_logo_init() {
  [ -n "${HA_LOGO_PRONTO:-}" ] && return 0
  local y r g b t
  # Azul HA com gradiente vertical: do #35b6f8 (topo) ao #0277BD (base).
  # Um escape de frente e um de fundo POR LINHA, pré-computados uma vez.
  HA_FGA=(); HA_BGA=()
  for (( y = 0; y < HA_H; y++ )); do
    t=$(( y * 100 / (HA_H - 1) ))
    r=$(( 53 - (53 - 2) * t / 100 ))
    g=$(( 182 - (182 - 119) * t / 100 ))
    b=$(( 248 - (248 - 189) * t / 100 ))
    if [[ "$HAOS_UI_DEPTH" == 24 ]]; then
      HA_FGA[y]=$'\033[38;2;'"$r;$g;$b"m
      HA_BGA[y]=$'\033[48;2;'"$r;$g;$b"m
    else
      HA_FGA[y]=$'\033[38;5;39m'; HA_BGA[y]=$'\033[48;5;39m'
    fi
  done
  if [[ "$HAOS_UI_DEPTH" == 24 ]]; then
    HA_FG_BRANCO=$'\033[38;2;236;242;248m'; HA_BG_BRANCO=$'\033[48;2;236;242;248m'
    HA_FG_TRACO=$'\033[38;2;255;255;255m';  HA_BG_TRACO=$'\033[48;2;255;255;255m'
    HA_FG_PULSO=$'\033[38;2;0;229;255m';    HA_BG_PULSO=$'\033[48;2;0;229;255m'
    HA_FG_FAGULHA=$'\033[38;2;120;220;255m'
    HA_FG_GLOW=$'\033[38;2;120;214;255m';   HA_BG_GLOW=$'\033[48;2;120;214;255m'
  else
    HA_FG_BRANCO=$'\033[38;5;255m'; HA_BG_BRANCO=$'\033[48;5;255m'
    HA_FG_TRACO=$'\033[38;5;231m';  HA_BG_TRACO=$'\033[48;5;231m'
    HA_FG_PULSO=$'\033[38;5;51m';   HA_BG_PULSO=$'\033[48;5;51m'
    HA_FG_FAGULHA=$'\033[38;5;117m'
    HA_FG_GLOW=$'\033[38;5;117m';   HA_BG_GLOW=$'\033[48;5;117m'
  fi
  HA_LOGO_PRONTO=1
}

# O quadro é montado num buffer de MÁSCARA mutável (QM), linha a linha, e um
# render único pinta as classes: . fora · # azul · o branco · t traço ·
# p pulso ciano · a partícula em voo · g glow. Substituição posicional de
# string é O(1) por pixel — é o que deixa 470 partículas por quadro baratas.
ha_qm_reset_vazio() { local y; QM=(); for (( y = 0; y < HA_H; y++ )); do QM[y]="$HA_QM_VAZIA"; done; }
ha_qm_reset_mask()  { local y; QM=(); for (( y = 0; y < HA_H; y++ )); do QM[y]="${HA_MASK[y]}"; done; }
ha_qm_poe() { # <x> <y> <classe>
  [ "$2" -ge 0 ] && [ "$2" -lt "$HA_H" ] && [ "$1" -ge 0 ] && [ "$1" -lt "$HA_W" ] || return 0
  QM[$2]="${QM[$2]:0:$1}$3${QM[$2]:$(( $1 + 1 ))}"
}

ha_render_qm() {
  local y1 y2 x c1 c2 saida
  for (( y1 = 0; y1 < HA_H; y1 += 2 )); do
    y2=$(( y1 + 1 ))
    saida=''
    local fa1="${HA_FGA[y1]}" fa2bg="${HA_BGA[y2]}" fa2="${HA_FGA[y2]}"
    for (( x = 0; x < HA_W; x++ )); do
      c1="${QM[$y1]:$x:1}"; c2="${QM[$y2]:$x:1}"
      case "$c1$c2" in
        '..') saida+="${NC} " ;;
        '.#') saida+="${NC}${fa2}▄" ;;
        '#.') saida+="${NC}${fa1}▀" ;;
        '##') saida+="${fa1}${fa2bg}▀" ;;
        '.o') saida+="${NC}${HA_FG_BRANCO}▄" ;;
        'o.') saida+="${NC}${HA_FG_BRANCO}▀" ;;
        'oo') saida+="${HA_FG_BRANCO}${HA_BG_BRANCO}▀" ;;
        '#o') saida+="${fa1}${HA_BG_BRANCO}▀" ;;
        'o#') saida+="${HA_FG_BRANCO}${fa2bg}▀" ;;
        '.t') saida+="${NC}${HA_FG_TRACO}▄" ;;
        't.') saida+="${NC}${HA_FG_TRACO}▀" ;;
        'tt') saida+="${HA_FG_TRACO}${HA_BG_TRACO}▀" ;;
        '#t') saida+="${fa1}${HA_BG_TRACO}▀" ;;
        't#') saida+="${HA_FG_TRACO}${fa2bg}▀" ;;
        'ot') saida+="${HA_FG_BRANCO}${HA_BG_TRACO}▀" ;;
        'to') saida+="${HA_FG_TRACO}${HA_BG_BRANCO}▀" ;;
        '.p') saida+="${NC}${HA_FG_PULSO}▄" ;;
        'p.') saida+="${NC}${HA_FG_PULSO}▀" ;;
        'pp') saida+="${HA_FG_PULSO}${HA_BG_PULSO}▀" ;;
        '#p') saida+="${fa1}${HA_BG_PULSO}▀" ;;
        'p#') saida+="${HA_FG_PULSO}${fa2bg}▀" ;;
        'op') saida+="${HA_FG_BRANCO}${HA_BG_PULSO}▀" ;;
        'po') saida+="${HA_FG_PULSO}${HA_BG_BRANCO}▀" ;;
        '.a') saida+="${NC}${HA_FG_FAGULHA}▄" ;;
        'a.') saida+="${NC}${HA_FG_FAGULHA}▀" ;;
        'aa') saida+="${HA_FG_FAGULHA}${HA_BG_PULSO}▀" ;;
        'a#') saida+="${HA_FG_FAGULHA}${fa2bg}▀" ;;
        '#a') saida+="${fa1}${HA_BG_PULSO}▀" ;;
        'ao') saida+="${HA_FG_FAGULHA}${HA_BG_BRANCO}▀" ;;
        'oa') saida+="${HA_FG_BRANCO}${HA_BG_PULSO}▀" ;;
        '.g') saida+="${NC}${HA_FG_GLOW}▄" ;;
        'g.') saida+="${NC}${HA_FG_GLOW}▀" ;;
        'gg') saida+="${HA_FG_GLOW}${HA_BG_GLOW}▀" ;;
        'go') saida+="${HA_FG_GLOW}${HA_BG_BRANCO}▀" ;;
        'og') saida+="${HA_FG_BRANCO}${HA_BG_GLOW}▀" ;;
        *)    saida+="${NC} " ;;
      esac
    done
    printf '%s%s\n' "$saida" "$NC"
  done
}

# ha_logo_quadro <n> — compõe o quadro n. n < 0: quadro final parado.
ha_logo_quadro() {
  local n="$1"
  ha_logo_init
  [ -n "${HA_QM_VAZIA:-}" ] || printf -v HA_QM_VAZIA '%*s' "$HA_W" ''; HA_QM_VAZIA="${HA_QM_VAZIA// /.}"
  local -a QM

  if [ "$n" -lt 0 ]; then
    ha_qm_reset_mask; ha_render_qm; return 0
  fi

  if [ "$n" -lt "$HA_Q_MONTA" ]; then
    # ── ato 1: constelação ──────────────────────────────────────────────────
    ha_qm_reset_vazio
    local total=${#HA_AX[@]} i d t x y
    for (( i = 0; i < total; i++ )); do
      d=${HA_ADL[i]}
      if [ "$n" -ge $(( d + HA_A_DUR )) ]; then
        ha_qm_poe "${HA_AX[i]}" "${HA_AY[i]}" "${HA_MASK[${HA_AY[i]}]:${HA_AX[i]}:1}"
      elif [ "$n" -ge "$d" ]; then
        t=$(( (n - d) * 100 / HA_A_DUR ))
        x=$(( HA_AOX[i] + (HA_AX[i] - HA_AOX[i]) * t / 100 ))
        y=$(( HA_AOY[i] + (HA_AY[i] - HA_AOY[i]) * t / 100 ))
        ha_qm_poe "$x" "$y" a
      fi
    done
    ha_render_qm; return 0
  fi

  if [ "$n" -lt $(( HA_Q_MONTA + HA_Q_TRACO )) ]; then
    # ── ato 2: o traço desenha e retrai, por posição de ARCO ────────────────
    ha_qm_reset_mask
    local k=$(( n - HA_Q_MONTA )) meio=$(( HA_Q_TRACO / 2 )) cabeca cauda i tt
    if [ "$k" -lt "$meio" ]; then
      cabeca=$(( k * HA_CAMINHO / meio )); cauda=0
    else
      cabeca=$HA_CAMINHO; cauda=$(( (k - meio) * HA_CAMINHO / meio ))
    fi
    local total=${#HA_TX[@]}
    for (( i = 0; i < total; i++ )); do
      tt=${HA_TT[i]}
      [ "$tt" -lt "$cauda" ] && continue
      [ "$tt" -ge "$cabeca" ] && break
      ha_qm_poe "${HA_TX[i]}" "${HA_TY[i]}" t
    done
    ha_render_qm; return 0
  fi

  if [ "$n" -lt $(( HA_Q_MONTA + HA_Q_TRACO + HA_Q_SONAR )) ]; then
    # ── ato 3: sonar — anéis ciano saindo de cada disco ─────────────────────
    ha_qm_reset_mask
    local k=$(( n - HA_Q_MONTA - HA_Q_TRACO ))
    local disco=$(( k / 5 )) passo=$(( k % 5 ))
    local cx=${HA_SCX[disco]} cy=${HA_SCY[disco]}
    local r=$(( (passo + 1) * 3 )) r2min r2max x y dx dy d2
    r2min=$(( (r - 2) * (r - 2) )); r2max=$(( r * r ))
    for (( y = 0; y < HA_H; y++ )); do
      for (( x = 0; x < HA_W; x++ )); do
        [ "${HA_MASK[$y]:$x:1}" = '#' ] || continue
        dx=$(( x - cx )); dy=$(( y - cy ))
        d2=$(( dx * dx + dy * dy ))
        if [ "$d2" -ge "$r2min" ] && [ "$d2" -le "$r2max" ]; then
          ha_qm_poe "$x" "$y" p
        fi
      done
    done
    ha_render_qm; return 0
  fi

  # ── ato 4: respiração — o azul pulsa e assenta ────────────────────────────
  local k=$(( n - HA_Q_MONTA - HA_Q_TRACO - HA_Q_SONAR )) y
  ha_qm_reset_mask
  if [ "$k" = "1" ] || [ "$k" = "2" ]; then
    for (( y = 0; y < HA_H; y++ )); do QM[y]="${QM[y]//#/g}"; done
  fi
  ha_render_qm
}

# ha_banner [título] [subtítulo]
ha_banner() {
  local title="${1:-Home Assistant OS}" sub="${2:-}" n cols
  cols="$(tput cols 2>/dev/null || echo 0)"
  case "$cols" in ''|*[!0-9]*) cols=0 ;; esac

  # Sem UTF-8 os glifos sairiam partidos; sem cor o logo vira mancha.
  if [[ "$HAOS_UI_UTF8" == 0 ]] || [[ "$HAOS_UI_DEPTH" == 0 ]]; then
    printf '  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi

  # Terminal estreito ou sem animação: UM quadro, tudo assentado. Nunca meia
  # animação, e nada que o movimento mostre existe só nele.
  if [[ "$HAOS_UI_ANIM" == 0 ]] || [ "$cols" -lt "$HA_MIN_COLS" ]; then
    ha_logo_quadro -1
    printf '\n  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi

  _hide
  for (( n = 0; n < HA_QUADROS; n++ )); do
    (( n > 0 )) && { tput cuu "$HA_LINHAS" 2>/dev/null || break; }
    ha_logo_quadro "$n"
    sleep "$HA_ATRASO"
  done
  tput cuu "$HA_LINHAS" 2>/dev/null && ha_logo_quadro -1   # assenta
  _show
  printf '\n'
  ha_shimmer "  ${title}"
  [ -n "$sub" ] && printf '  %s%s%s\n' "${C_MUTED}" "$sub" "$NC"
  printf '\n'
}

# ── shimmer: a highlight travels once across the text ───────────────────────
ha_shimmer() {
  local s="$1" n=${#1} p i out
  if [[ "$HAOS_UI_ANIM" == 0 || "$HAOS_UI_DEPTH" == 0 ]]; then printf '%s%s%s\n' "$BOLD" "$s" "$NC"; return
  fi
  _hide
  for (( p=-6; p<=n+6; p+=2 )); do
    out=''
    for (( i=0; i<n; i++ )); do
      local d=$(( i>p ? i-p : p-i ))
      if (( d <= 3 )); then out+="${BOLD}$(rgb 255 255 255)${s:i:1}"
      elif (( d <= 6 )); then out+="${C_CYAN}${s:i:1}"
      else out+="${C_BLUE}${s:i:1}"; fi
    done
    printf '\r%s%s' "$out" "$NC"; sleep 0.012
  done
  printf '\r%s%s%s%s\n' "$BOLD" "$(ha_gradient "$s")" "$NC" ""
  _show
}

# ── gradient rule across the terminal ───────────────────────────────────────
ha_rule() {
  local w; w=$(tput cols 2>/dev/null || echo 72); (( w > 78 )) && w=78
  local line=''; printf -v line '%*s' "$w" ''; line=${line// /$HA_G_REGUA}
  printf '%s\n' "$(ha_gradient "$line")"
}

# ── barra de fase, viva na última linha ─────────────────────────────────────
# Conta FASES, não itens (o desenho do AtlasFile): o que existe de discreto e
# conhecido aqui são as fases, e um total de passos inventado é pior que barra
# nenhuma. Só aparece depois da 1ª fase, e só com animação — em log seria lixo.
# Apagar ANTES de qualquer mensagem é o que impede a barra de virar sujeira no
# meio do texto; `\033[2K` apaga a linha inteira sem depender de TERM.
HA_BAR_TOTAL=0; HA_BAR_N=0; HA_BAR_VISIVEL=0; HA_BAR_SUSPENSA=0
ha_bar_limpa() {
  if [[ "$HA_BAR_VISIVEL" == 1 ]]; then printf '\r\033[2K'; HA_BAR_VISIVEL=0; fi
  return 0
}
# Durante uma PERGUNTA a barra não existe: prompt e barra disputando a última
# linha foi medido em campo (o "[s/N]" colado em "fase 1/4"). É a disciplina
# do ask() do AtlasFile: quem pergunta suspende, quem termina retoma.
ha_bar_suspende() { ha_bar_limpa; HA_BAR_SUSPENSA=1; }
ha_bar_retoma()   { HA_BAR_SUSPENSA=0; ha_bar_mostra; }
ha_bar_mostra() {
  [[ "${HA_BAR_SUSPENSA:-0}" == 0 ]] || return 0
  [[ "$HAOS_UI_ANIM" == 1 && "$HA_BAR_TOTAL" -gt 0 && "$HA_BAR_N" -gt 0 ]] || return 0
  local w=20 f i out=''
  f=$(( HA_BAR_N * w / HA_BAR_TOTAL ))
  for (( i = 0; i < w; i++ )); do
    if (( i < f )); then out+="${C_CYAN}${HA_G_BON}"; else out+="${C_MUTED}${HA_G_BOFF}"; fi
  done
  printf ' %s%s %sfase %d/%d%s' "$out" "$NC" "${C_MUTED}" "$HA_BAR_N" "$HA_BAR_TOTAL" "$NC"
  HA_BAR_VISIVEL=1
  return 0
}

# ── phase header ────────────────────────────────────────────────────────────
HA_PHASE_N=0
ha_phase() {
  ha_bar_limpa
  HA_PHASE_N=$(( HA_PHASE_N + 1 ))
  printf '\n%s%s%s%s %s%02d%s  %s\n' "$BOLD" "${C_BLUE}" "$HA_G_MARCA" "$NC" \
    "${C_MUTED}" "$HA_PHASE_N" "$NC" "$(ha_gradient "$1")"
  ha_rule
  ha_bar_mostra
}

# ── status lines ────────────────────────────────────────────────────────────
ha_ok()    { ha_bar_limpa; printf ' %s%s%s %s\n'  "${C_GREEN}" "$HA_G_OK" "$NC" "$1"; ha_bar_mostra; }
ha_info()  { ha_bar_limpa; printf ' %s%s%s %s%s%s\n' "${C_BLUE}" "$HA_G_INFO" "$NC" "${C_MUTED}" "$1" "$NC"; ha_bar_mostra; }
ha_warn()  { ha_bar_limpa; printf ' %s%s%s %s\n'  "${C_AMBER}" "$HA_G_WARN" "$NC" "$1"; ha_bar_mostra; }
ha_err()   { ha_bar_limpa; printf ' %s%s%s %s\n'  "${C_RED}"  "$HA_G_ERR" "$NC" "$1" >&2; }
ha_skip()  { ha_bar_limpa; printf ' %s%s%s %s%s%s\n' "${C_MUTED}" "$HA_G_SKIP" "$NC" "$DIM" "$1" "$NC"; ha_bar_mostra; }

# ── quebra de linha na largura do terminal ──────────────────────────────────
# Existe porque o produto imprime CAMINHOS (`~/VirtualBox VMs/...`), e caminho
# que o terminal quebra sozinho sai sem recuo e não pode ser copiado inteiro.
# Palavra maior que a largura transborda em vez de ser partida — caminho
# quebrado no meio não cola. Largura por bytes menos bytes de continuação
# UTF-8: dá caracteres nos dois locales (a armadilha do ${#s} sob LC_ALL=C).
ha_strwidth() { # <texto>
  local b c
  b=$(printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' ')
  c=$(printf '%s' "$1" | LC_ALL=C tr -dc '\200-\277' | LC_ALL=C wc -c | tr -d ' ')
  printf '%s' $(( b - c ))
}
ha_wrap() { # <prefixo_1a_linha> <prefixo_continuacao> <colunas_do_prefixo> <texto>
  local p1="$1" p2="$2" pw="$3" texto="$4" linha='' palavra util w glob_ligado=1
  w=$(tput cols 2>/dev/null || echo 72); case "$w" in ''|*[!0-9]*) w=72 ;; esac
  (( w > 92 )) && w=92
  util=$(( w - pw )); [ "$util" -lt 20 ] && util=20
  # Texto pode conter glob (`*.vdi`); sem `set -f` a divisão em palavras
  # expandiria contra o diretório corrente.
  case "$-" in *f*) glob_ligado=0 ;; esac
  set -f
  for palavra in $texto; do
    if [ -z "$linha" ]; then linha="$palavra"
    elif [ "$(ha_strwidth "${linha} ${palavra}")" -le "$util" ]; then linha="${linha} ${palavra}"
    else printf '%s%s\n' "$p1" "$linha"; p1="$p2"; linha="$palavra"; fi
  done
  [ "$glob_ligado" = "1" ] && set +f
  printf '%s%s\n' "$p1" "$linha"
}

# ── orbit spinner around a label ────────────────────────────────────────────
ha_spin() { # ha_spin "label" <pid>
  local label="$1" pid="$2" i=0 rc=0
  # `wait` com código != 0 sob `set -e` abortaria o chamador antes do return —
  # por isso todo wait aqui é `|| rc=$?`, nunca solto.
  if [[ "$HAOS_UI_ANIM" == 0 ]]; then
    printf ' %s %s\n' "$HA_G_DOTS" "$label"
    wait "$pid" || rc=$?
    return "$rc"
  fi
  ha_bar_limpa
  _hide
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r %s%s%s %s' "${C_CYAN}" "${HA_SPIN_F:$(( i % HA_SPIN_N )):1}" "$NC" "$label"; i=$(( i + 1 ))
    sleep 0.07
  done
  wait "$pid" || rc=$?
  printf '\r\033[2K'; _show
  if (( rc == 0 )); then ha_ok "$label"; else ha_err "$label  (exit $rc)"; fi
  return "$rc"
}

# ── progress bar, HA rounded style ──────────────────────────────────────────
ha_bar() { # ha_bar <done> <total> "label"
  local d="$1" t="$2" label="${3:-}" w=32 f i out=''
  # Em log (nao-TTY) uma barra por frame vira lixo: so a linha final importa.
  if [[ "$HAOS_UI_ANIM" == 0 ]]; then (( d >= t )) && printf ' %d/%d %s\n' "$d" "$t" "$label"; return; fi
  ha_bar_limpa
  (( t == 0 )) && t=1
  f=$(( d * w / t ))
  if [[ "$HAOS_UI_DEPTH" == 0 || "$HAOS_UI_UTF8" == 0 ]]; then
    printf '\r [%-*s] %d/%d %s' "$w" "$(printf '%*s' "$f" '' | tr ' ' '#')" "$d" "$t" "$label"
  else
    for (( i=0; i<w; i++ )); do
      if (( i < f )); then
        local u=$(( w>1 ? i*200/(w-1) : 0 )) r g b
        if (( u <= 100 )); then r=$(( HA_DEEP_R+(HA_BLUE_R-HA_DEEP_R)*u/100 )); g=$(( HA_DEEP_G+(HA_BLUE_G-HA_DEEP_G)*u/100 )); b=$(( HA_DEEP_B+(HA_BLUE_B-HA_DEEP_B)*u/100 ))
        else local v=$(( u-100 )); r=$(( HA_BLUE_R+(HA_CYAN_R-HA_BLUE_R)*v/100 )); g=$(( HA_BLUE_G+(HA_CYAN_G-HA_BLUE_G)*v/100 )); b=$(( HA_BLUE_B+(HA_CYAN_B-HA_BLUE_B)*v/100 )); fi
        out+="$(rgb "$r" "$g" "$b")━"
      else out+="${C_MUTED}╌"; fi
    done
    printf '\r %s%s %s%d/%d%s %s' "$out" "$NC" "${C_MUTED}" "$d" "$t" "$NC" "$label"
  fi
  (( d >= t )) && printf '\n'
}

# A demonstração vive em tools/ui-demo.sh. Biblioteca é biblioteca:
# ela não desenha sozinha, não instala trap e não afirma fatos.
