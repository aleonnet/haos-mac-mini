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
    out+="$(rgb $r $g $b)${s:i:1}"
  done
  printf '%s%s' "$out" "$NC"
}

# ── the Home Assistant mark: house silhouette + circuit ─────────────────────
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
)

_hide() { if [[ "$HAOS_UI_ANIM" == 1 ]]; then tput civis 2>/dev/null || true; fi; }
_show() { if [[ "$HAOS_UI_ANIM" == 1 ]]; then tput cnorm 2>/dev/null || true; fi; }

# Library must not install a trap. `trap` is global to the shell and the last
# caller wins: a trap here would silently REPLACE the caller's cleanup handler,
# leaking temp files and skipping the rollback of a half-created VM on Ctrl-C.
# The caller invokes ha_show_cursor from its own cleanup instead.
ha_show_cursor() { _show; }

# ── banner: sweep-reveal, then three breathing pulses ───────────────────────
ha_banner() {
  local title="${1:-Home Assistant OS}" sub="${2:-}"
  local L=${#HA_MARK[@]} i j w=${#HA_MARK[0]}
  if [[ "$HAOS_UI_ANIM" == 0 ]]; then
    printf '%s\n' "${HA_MARK[@]}"; printf '  %s\n' "$title" "${sub:+$sub}"; return
  fi
  _hide
  # 1. reveal: each line wipes in left-to-right
  for (( i=0; i<L; i++ )); do
    for (( j=4; j<=w; j+=6 )); do
      printf '\r%s' "$(ha_gradient "${HA_MARK[i]:0:j}")"
      sleep 0.004
    done
    printf '\r%s\n' "$(ha_gradient "${HA_MARK[i]}")"
  done
  # 2. breathe: redraw the whole mark at varying luminance
  local -a steps=(45 70 100 70 45 70 100)
  for s in "${steps[@]}"; do
    tput cuu "$L" 2>/dev/null || break
    for (( i=0; i<L; i++ )); do
      local r=$(( HA_BLUE_R*s/100 )) g=$(( HA_BLUE_G*s/100 )) b=$(( HA_BLUE_B*s/100 ))
      printf '%s%s%s\n' "$(rgb $r $g $b)" "${HA_MARK[i]}" "$NC"
    done
    sleep 0.055
  done
  # 3. settle on the gradient
  tput cuu "$L" 2>/dev/null || true
  for (( i=0; i<L; i++ )); do printf '%s\n' "$(ha_gradient "${HA_MARK[i]}")"; done
  _show
  printf '\n'
  ha_shimmer "  ${title}"
  [[ -n "$sub" ]] && printf '  %s%s%s\n' "${C_MUTED}" "$sub" "$NC"
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
  return $rc
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
        out+="$(rgb $r $g $b)━"
      else out+="${C_MUTED}╌"; fi
    done
    printf '\r %s%s %s%d/%d%s %s' "$out" "$NC" "${C_MUTED}" "$d" "$t" "$NC" "$label"
  fi
  (( d >= t )) && printf '\n'
}

# A demonstração vive em tools/ui-demo.sh. Biblioteca é biblioteca:
# ela não desenha sozinha, não instala trap e não afirma fatos.
