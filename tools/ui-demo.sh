#!/usr/bin/env bash
# =============================================================================
# ui-demo.sh — demonstração da camada visual.
#
# Vive AQUI, e não dentro de lib/haos-ui.sh, por dois motivos que custaram caro:
#
#  1. A guarda `[[ "${BASH_SOURCE[0]}" == "$0" ]]` erra nos DOIS modos que o
#     produto usa. Concatenada num script autocontido, ela vira verdadeira e a
#     demo roda em produção. Vinda de stdin (`curl | bash`), o array BASH_SOURCE
#     é vazio e, com `set -u`, aborta o instalador na primeira linha.
#
#  2. A demo antiga afirmava fatos: "VirtualBox 7.2.16 encontrado" numa máquina
#     sem VirtualBox, "SHA conferido" sem ter conferido nada, e o inventário de
#     uma casa específica. Demonstração que afirma fato mente para quem lê.
#
# Aqui todo valor é obviamente falso, e todo rótulo diz [DEMO].
#
#   ./tools/ui-demo.sh              com animação
#   ./tools/ui-demo.sh --no-anim    um quadro estático
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=../lib/haos-ui.sh
source "$RAIZ/lib/haos-ui.sh"

[ "${1:-}" = "--no-anim" ] && HAOS_UI_ANIM=0

# A biblioteca não instala trap — quem usa é que cuida do cursor.
demo_cleanup() { ha_show_cursor; }
trap demo_cleanup EXIT INT TERM

clear 2>/dev/null || true
ha_banner "Home Assistant OS" "[DEMO] camada visual — nenhum valor abaixo é real"

ha_phase "[DEMO] Pré-voo"
ha_ok   "[DEMO] VirtualBox X.Y.Z encontrado"
ha_info "[DEMO] imagem haos_generic-aarch64-X.Y.vdi.zip — 000 MiB"
ha_warn "[DEMO] só há interface Wi-Fi: a bridge pode não obter lease"
ha_skip "[DEMO] item que não se aplica a esta plataforma"

ha_phase "[DEMO] Integrações"
for i in $(seq 0 12); do ha_bar "$i" 12 "[DEMO] config flow"; sleep 0.05; done
( sleep 1.2 ) & ha_spin "[DEMO] aguardando passo do fluxo" $!
( sleep 0.8 ) & ha_spin "[DEMO] lendo a entry de volta para conferir" $!

printf '\n'; ha_rule
ha_shimmer "  [DEMO] 12 itens · 0 falhas"
printf '\n'
