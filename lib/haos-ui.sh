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
  if [[ "$HAOS_UI_DEPTH" == 0 ]]; then printf '%s' "$s"; return; fi
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
# Máscara do logo do Home Assistant, por pixel:
#   .  fora    #  corpo da casa    o  circuito
# HA_BX/HA_BY são o contorno JÁ ORDENADO, em vetores PARALELOS: é o caminho
# que o traço percorre, começando embaixo no centro e subindo pela esquerda,
# como no logo oficial. Dois vetores em vez de "x,y" numa string evitam
# fatiar texto no laço mais quente do render.
HA_W=48
HA_H=48
HA_MASK=(
'................................................'
'................................................'
'.....................######.....................'
'....................########....................'
'...................##########...................'
'..................############..................'
'.................##############.................'
'................################................'
'...............##################...............'
'..............####################..............'
'.............######################.............'
'...........#########################............'
'..........###########oooooo###########..........'
'.........############oooooo############.........'
'........############oooooooo############........'
'.......#############oooooooo#############.......'
'......##############oooooooo##############......'
'.....###############oooooooo###############.....'
'....#################oooooo#################....'
'...###################oooo###################...'
'..####################oooo####################..'
'.#####################oooo#####################.'
'######################oooo######################'
'######################oooo######################'
'######################oooo#######oooooo#########'
'######################oooo#######oooooo#########'
'######################oooo######oooooooo########'
'######################oooo######oooooooo########'
'######################oooo######oooooooo########'
'######################oooo#####ooooooooo########'
'######################oooo####ooooooooo#########'
'##########oooo########oooo###ooooooooo##########'
'#########oooooo#######oooo#ooooooo##############'
'########oooooooo######oooooooooo################'
'########oooooooo######ooooooooo#################'
'########oooooooo######oooooooo##################'
'########ooooooooo#####ooooooo###################'
'#########ooooooooo####oooooo####################'
'##########oooooooooo##oooo######################'
'##############ooooooo#oooo######################'
'################oooooooooo######################'
'#################ooooooooo######################'
'##################oooooooo######################'
'###################ooooooo######################'
'#####################ooooo######################'
'.#####################oooo#####################.'
'.######################oo######################.'
'...##########################################...'
)
HA_BX=(23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 46 46 45 44 43 42 41 40 39 38 37 36 35 34 33 32 31 30 29 28 27 26 25 24)
HA_BY=(47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 46 46 45 44 43 42 41 40 39 38 37 36 35 34 33 32 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 11 10 9 8 7 6 5 4 3 2 2 2 2 2 2 3 4 5 6 7 8 9 10 11 12 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 46 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47 47)

# ── logo: meio-bloco, dois pixels por célula ─────────────────────────────────
# A célula do terminal é ~2:1. Com "▀" ela vira DOIS pixels de cor
# independente — frente em cima, fundo embaixo — e o pixel resultante fica
# quase quadrado. É a maior resolução com cor por subpixel que o terminal dá.
# Braille daria 2x4, mas só UMA cor por célula: o azul e o branco não caberiam
# juntos no mesmo caractere, e o logo tem os dois encostados.
#
# A animação é a oficial do Home Assistant: um traço branco percorre o
# CONTORNO da casa, como uma caneta desenhando o perímetro.

HA_MIN_COLS=50
HA_ATRASO=0.016
HA_QUADROS=44       # quadros da volta: metade desenha, metade retrai. 44 x ~55ms
                    # = ~2,4 s — o vídeo de referência leva ~4,2 s por ciclo, mas
                    # numa abertura que roda UMA vez isso é tempo demais parado.

# Escapes pré-computados: montar cor por célula com $(...) seria um subshell
# por pixel — 1152 por quadro. Aqui o laço interno é só concatenação.
ha_logo_init() {
  [ -n "${HA_LOGO_PRONTO:-}" ] && return 0
  if [[ "$HAOS_UI_DEPTH" == 24 ]]; then
    HA_FG_AZUL=$'\033[38;2;3;169;244m';   HA_BG_AZUL=$'\033[48;2;3;169;244m'
    HA_FG_BRANCO=$'\033[38;2;236;242;248m'; HA_BG_BRANCO=$'\033[48;2;236;242;248m'
    HA_FG_TRACO=$'\033[38;2;255;255;255m';  HA_BG_TRACO=$'\033[48;2;255;255;255m'
  else
    HA_FG_AZUL=$'\033[38;5;39m';  HA_BG_AZUL=$'\033[48;5;39m'
    HA_FG_BRANCO=$'\033[38;5;255m'; HA_BG_BRANCO=$'\033[48;5;255m'
    HA_FG_TRACO=$'\033[38;5;231m';  HA_BG_TRACO=$'\033[48;5;231m'
  fi
  HA_LOGO_PRONTO=1
}

# ha_logo_quadro <n> — pinta o logo no quadro n de HA_QUADROS.
# n < 0 desenha o logo parado, sem traço.
#
# O movimento é o do logo oficial, conferido quadro a quadro no vídeo que ele
# mandou: NÃO é um cometa de comprimento fixo dando voltas. A cabeça sai de
# baixo, no centro, e corre o perímetro INTEIRO; só então a cauda a persegue e
# o traço se retrai até sumir. É o stroke-dashoffset de sempre — e a diferença
# aparece na tela: com comprimento fixo o desenho nunca fecha, e fechar é o que
# dá a sensação de conclusão.
ha_logo_quadro() {
  local n="$1" y1 y2 x c1 c2 saida chave
  ha_logo_init

  # Índice POR LINHA. A primeira versão guardava um conjunto único "x,y" e
  # buscava nele a cada pixel: 2.300 buscas de substring em string de 140
  # elementos por quadro, e o quadro levava 51 ms. Indexando por linha, cada
  # busca varre só os poucos pixels de contorno daquela linha.
  # Índice POR LINHA. A primeira versão guardava um conjunto único "x,y" e
  # buscava nele a cada pixel: 2.300 buscas de substring por quadro, e o quadro
  # levava 51 ms. Por linha, cada busca varre só os poucos pixels daquela linha.
  local -a linha_acesa
  if [ "$n" -ge 0 ]; then
    local total=${#HA_BX[@]} meio=$(( HA_QUADROS / 2 )) cabeca cauda i k by
    if [ "$n" -lt "$meio" ]; then
      cabeca=$(( n * total / meio )); cauda=0                  # desenha
    else
      cabeca=$total; cauda=$(( (n - meio) * total / meio ))    # retrai
    fi
    for (( i = cauda; i < cabeca; i++ )); do
      k=$(( i % total ))
      by=${HA_BY[k]}
      linha_acesa[by]="${linha_acesa[by]:- } ${HA_BX[k]} "
    done
  fi

  for (( y1 = 0; y1 < HA_H; y1 += 2 )); do
    y2=$(( y1 + 1 ))
    saida=''
    for (( x = 0; x < HA_W; x++ )); do
      c1="${HA_MASK[$y1]:$x:1}"
      c2="${HA_MASK[$y2]:$x:1}"
      # o traço sobrepõe a máscara
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

HA_LINHAS=$(( 48 / 2 ))

# ha_banner [título] [subtítulo]
ha_banner() {
  local title="${1:-Home Assistant OS}" sub="${2:-}" n cols
  cols="$(tput cols 2>/dev/null || echo 0)"
  case "$cols" in ''|*[!0-9]*) cols=0 ;; esac
  HA_LINHAS=$(( HA_H / 2 ))

  # Sem UTF-8 os glifos sairiam partidos; sem cor o logo vira mancha.
  if [[ "$HAOS_UI_UTF8" == 0 ]] || [[ "$HAOS_UI_DEPTH" == 0 ]]; then
    printf '  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi

  # Terminal estreito ou sem animação: UM quadro, o logo parado. Nunca meia
  # animação, e nada que o movimento mostre existe só nele.
  if [[ "$HAOS_UI_ANIM" == 0 ]] || [ "$cols" -lt "$HA_MIN_COLS" ]; then
    ha_logo_quadro -1
    printf '\n  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi

  # Sem trap aqui: a lib não instala trap, e o cursor volta pelo cleanup de
  # quem chama, via ha_show_cursor.
  _hide
  for (( n = 0; n < HA_QUADROS; n++ )); do
    (( n > 0 )) && { tput cuu "$HA_LINHAS" 2>/dev/null || break; }
    ha_logo_quadro "$n"
    sleep "$HA_ATRASO"
  done
  tput cuu "$HA_LINHAS" 2>/dev/null && ha_logo_quadro -1   # assenta sem o traço
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
  local line=''; printf -v line '%*s' "$w" ''; line=${line// /─}
  printf '%s\n' "$(ha_gradient "$line")"
}

# ── phase header ────────────────────────────────────────────────────────────
HA_PHASE_N=0
ha_phase() {
  HA_PHASE_N=$(( HA_PHASE_N + 1 ))
  printf '\n%s%s▎%s %s%02d%s  %s\n' "$BOLD" "${C_BLUE}" "$NC" \
    "${C_MUTED}" "$HA_PHASE_N" "$NC" "$(ha_gradient "$1")"
  ha_rule
}

# ── status lines ────────────────────────────────────────────────────────────
ha_ok()    { printf ' %s✔%s %s\n'  "${C_GREEN}" "$NC" "$1"; }
ha_info()  { printf ' %s•%s %s%s%s\n' "${C_BLUE}" "$NC" "${C_MUTED}" "$1" "$NC"; }
ha_warn()  { printf ' %s▲%s %s\n'  "${C_AMBER}" "$NC" "$1"; }
ha_err()   { printf ' %s✖%s %s\n'  "${C_RED}"  "$NC" "$1" >&2; }
ha_skip()  { printf ' %s◦%s %s%s%s\n' "${C_MUTED}" "$NC" "$DIM" "$1" "$NC"; }

# ── orbit spinner around a label ────────────────────────────────────────────
ha_spin() { # ha_spin "label" <pid>
  local label="$1" pid="$2" frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  if [[ "$HAOS_UI_ANIM" == 0 ]]; then printf ' … %s\n' "$label"; wait "$pid"; return $?; fi
  _hide
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r %s%s%s %s' "${C_CYAN}" "${frames:$(( i % 10 )):1}" "$NC" "$label"; i=$(( i + 1 ))
    sleep 0.07
  done
  wait "$pid"; local rc=$?
  printf '\r\033[K'; _show
  if (( rc == 0 )); then ha_ok "$label"; else ha_err "$label  (exit $rc)"; fi
  return "$rc"
}

# ── progress bar, HA rounded style ──────────────────────────────────────────
ha_bar() { # ha_bar <done> <total> "label"
  local d="$1" t="$2" label="${3:-}" w=32 f i out=''
  # Em log (nao-TTY) uma barra por frame vira lixo: so a linha final importa.
  if [[ "$HAOS_UI_ANIM" == 0 ]]; then (( d >= t )) && printf ' %d/%d %s\n' "$d" "$t" "$label"; return; fi
  (( t == 0 )) && t=1
  f=$(( d * w / t ))
  if [[ "$HAOS_UI_DEPTH" == 0 ]]; then
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
