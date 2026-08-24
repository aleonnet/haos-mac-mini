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

# ── the mark: Home Assistant sitting on a Mac mini ──────────────────────────
# The story the picture tells is the product: the HA house RISES OUT OF the Mac.
# That is why ignition runs bottom-up — the machine appears first, the house
# grows from it — instead of the usual top-down wipe.
HA_MARK=(
'                    ▟▙                    '
'                  ▟████▙                  '
'                ▟████████▙                '
'              ▟████████████▙              '
'            ▟████████████████▙            '
'          ▟████████████████████▙          '
'        ▟████████████████████████▙        '
'      ▟████████████████████████████▙      '
'    ▟████████████████████████████████▙    '
'   ██████████████████████████████████████ '
'   ██████   ●          ●          ●   ███ '
'   ██████   │          │          │   ███ '
'   ██████   └────┐     │     ┌────┘   ███ '
'   ██████        └─────●─────┘        ███ '
'   ██████              │              ███ '
'   ██████              ●              ███ '
'   ██████████████████████████████████████ '
'                                          '
'  ▗▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▖  '
'  ▐                                 ·  ▌  '
'  ▝▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▘  '
)
HA_LINHAS=${#HA_MARK[@]}
HA_QUADROS=26
HA_ATRASO=0.045
HA_MIN_COLS=46
# Onde começa a base do Mac mini: dali para baixo a cor é cinza-azulado, não
# a rampa do Home Assistant. O LED de energia pulsa em vez de ficar fixo.
HA_MAC_LINHA=18

# ha_celula <linha> <coluna> <quadro> — cor de UMA célula.
#
# O realce é um PONTO que varre em onda triangular, e cada célula escurece com a
# distância até ele. Uma rampa horizontal ao longo da arte inteira deixa o
# volume chapado: a variação dentro das ~40 colunas é pequena demais para o olho
# ler como luz. O ponto dá relevo.
ha_celula() {
  local lin="$1" col="$2" q="$3" tri hlc d n r g b
  tri=$(( q % 20 )); [ "$tri" -gt 10 ] && tri=$(( 20 - tri ))
  hlc=$(( 6 + tri * 3 ))                   # o ponto de luz varre da esquerda
  d=$(( col > hlc ? col - hlc : hlc - col ))
  [ "$d" -gt 24 ] && d=24
  n=$(( 100 - d * 3 ))                     # 100 no foco, 28 na borda
  [ "$n" -lt 28 ] && n=28
  # rampa da identidade: HA_DEEP -> HA_BLUE -> HA_CYAN, modulada pela distância
  if [ "$lin" -ge "$HA_MAC_LINHA" ]; then  # base do Mac: cinza-azulado, discreto
    r=$(( 70 * n / 100 )); g=$(( 84 * n / 100 )); b=$(( 96 * n / 100 ))
  else
    r=$(( (HA_DEEP_R + (HA_CYAN_R - HA_DEEP_R) * lin / HA_LINHAS) * n / 100 ))
    g=$(( (HA_DEEP_G + (HA_CYAN_G - HA_DEEP_G) * lin / HA_LINHAS) * n / 100 ))
    b=$(( (HA_DEEP_B + (HA_CYAN_B - HA_DEEP_B) * lin / HA_LINHAS) * n / 100 ))
  fi
  rgb "$r" "$g" "$b"
}

# ha_quadro <n> — pinta a arte inteira no estado do quadro n.
ha_quadro() {
  local q="$1" lin col ch linha revela saida led
  # Ignição de baixo para cima: o quadro q revela q linhas a partir da base.
  revela=$(( HA_LINHAS - q * 2 ))
  [ "$revela" -lt 0 ] && revela=0
  for (( lin = 0; lin < HA_LINHAS; lin++ )); do
    linha="${HA_MARK[lin]}"
    if [ "$lin" -lt "$revela" ]; then
      printf '%*s\n' "${#linha}" ''        # ainda não acendeu
      continue
    fi
    if [[ "$HAOS_UI_DEPTH" == 0 ]]; then
      printf '%s\n' "$linha"; continue
    fi
    saida=''
    for (( col = 0; col < ${#linha}; col++ )); do
      ch="${linha:col:1}"
      if [[ "$ch" == " " ]]; then saida+=' '; continue; fi
      # o LED pulsa: aceso nos quadros pares depois da ignição da base
      if [[ "$ch" == "·" ]]; then
        if (( q % 4 < 2 )); then led="$(rgb 120 255 170)"; else led="$(rgb 40 90 70)"; fi
        saida+="${led}●"; continue
      fi
      saida+="$(ha_celula "$lin" "$col" "$q")${ch}"
    done
    printf '%s%s\n' "$saida" "$NC"
  done
}

# ha_banner [título] [subtítulo]
ha_banner() {
  local title="${1:-Home Assistant OS}" sub="${2:-}" q cols
  cols="$(tput cols 2>/dev/null || echo 0)"
  case "$cols" in ''|*[!0-9]*) cols=0 ;; esac

  # Degrada para UM quadro estático — o último, que é a arte completa — quando
  # não há animação ou o terminal é estreito demais. Nunca meia animação.
  # Sem UTF-8 não há arte: os glifos sairiam como lixo. Um cabeçalho honesto
  # em ASCII diz a mesma coisa.
  if [[ "$HAOS_UI_UTF8" == 0 ]]; then
    printf '  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi
  if [[ "$HAOS_UI_ANIM" == 0 ]] || [ "$cols" -lt "$HA_MIN_COLS" ]; then
    ha_quadro "$HA_QUADROS"
    printf '\n  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi

  # Sem trap aqui: a biblioteca não instala trap, e o cursor é restaurado pelo
  # cleanup de quem chama, via ha_show_cursor. Um trap aqui APAGARIA o do
  # instalador — trap é global do shell e quem chama por último vence.
  _hide
  for (( q = 0; q <= HA_QUADROS; q++ )); do
    (( q > 0 )) && { tput cuu "$HA_LINHAS" 2>/dev/null || break; }
    ha_quadro "$q"
    (( q < HA_QUADROS )) && sleep "$HA_ATRASO"
  done
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
