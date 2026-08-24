#!/usr/bin/env bash
# probe-host.sh — sonda de capacidade do Mac hospedeiro.
#
# Emite APENAS dados (pares chave=valor). Nenhuma cor, nenhuma animação, nenhuma
# decisão. A camada visual e a de decisão consomem isto — separadas de propósito,
# para que a sonda seja testável e comparável entre máquinas.
#
#   ./probe-host.sh            pares chave=valor (padrão, para consumo)
#   ./probe-host.sh --table    tabela legível
#   source probe-host.sh       expõe probe_all() e as probe_* individuais
#
# Compatível com bash 3.2 (o que o macOS traz): sem namerefs, sem arrays
# associativos, sem process substitution em caminho crítico.
#
# Fontes de cada medida estão no comentário da respectiva função — nenhuma delas
# é estimada.
set -uo pipefail

PROBE_VERSION="0.1.0"

# ── util ────────────────────────────────────────────────────────────────────
_kv() { printf '%s=%s\n' "$1" "$2"; }
_sysctl() { sysctl -n "$1" 2>/dev/null || echo ""; }
_have() { command -v "$1" >/dev/null 2>&1; }

# bytes -> MiB inteiro (sem bc: bash 3.2 não tem aritmética de ponto flutuante)
_mib() { [ -n "${1:-}" ] && [ "$1" -gt 0 ] 2>/dev/null && echo $(( $1 / 1048576 )) || echo 0; }

# ── identidade da máquina ───────────────────────────────────────────────────
# Fonte: sysctl hw.model / machdep.cpu.brand_string · sw_vers
probe_identity() {
  _kv host.model      "$(_sysctl hw.model)"
  _kv host.cpu        "$(_sysctl machdep.cpu.brand_string)"
  _kv host.arch       "$(uname -m)"
  _kv host.macos      "$(sw_vers -productVersion 2>/dev/null)"
  _kv host.build      "$(sw_vers -buildVersion 2>/dev/null)"
  _kv host.name       "$(scutil --get LocalHostName 2>/dev/null)"
  # Apple Silicon é pré-requisito: a imagem do HAOS é aarch64.
  case "$(uname -m)" in
    arm64) _kv host.apple_silicon 1 ;;
    *)     _kv host.apple_silicon 0 ;;
  esac
}

# ── CPU ─────────────────────────────────────────────────────────────────────
# Apple Silicon tem dois níveis de performance. hw.ncpu sozinho ENGANA:
# soma núcleos P e E, que não são intercambiáveis para dimensionar vCPU.
# Fonte: sysctl hw.perflevel0.* (performance) e hw.perflevel1.* (efficiency)
probe_cpu() {
  local p e
  p="$(_sysctl hw.perflevel0.logicalcpu)"
  e="$(_sysctl hw.perflevel1.logicalcpu)"
  _kv cpu.logical     "$(_sysctl hw.logicalcpu)"
  _kv cpu.physical    "$(_sysctl hw.physicalcpu)"
  _kv cpu.performance "${p:-0}"
  _kv cpu.efficiency  "${e:-0}"
  # carga média de 1 min — indica se a máquina já está ocupada
  _kv cpu.load1       "$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
}

# ── memória ─────────────────────────────────────────────────────────────────
# "Total" é o número errado para dimensionar: o que importa é o que SOBRA.
# macOS não expõe "disponível" direto — calcula-se por vm_stat.
# Usado real = (active + wired + compressed) * pagesize   [modelo do Activity Monitor]
# Fonte: sysctl hw.memsize · hw.pagesize · vm_stat · sysctl vm.swapusage
# ⚠️ CUIDADO COM O QUE "DISPONÍVEL" SIGNIFICA.
# A primeira versão calculava disponível = total - (active + wired + compressed),
# o que EXCLUI todo o cache reclamável. Medido num Mac de 36 GB: dava 4,6 GB, e
# duas execuções minutos depois davam 4673 e 5841 MiB — número volátil demais
# para servir de portão que aborta, e que ainda fazia o perfil "Recomendado"
# ficar MENOR que o "Equilibrado".
#
# O macOS devolve inactive, speculative e purgeable sob demanda. Elas contam.
probe_memory() {
  local total pagesize vs active wired compressed inactive spec purge free used avail
  total="$(_sysctl hw.memsize)"
  pagesize="$(_sysctl hw.pagesize)"; pagesize="${pagesize:-4096}"
  _kv mem.total_mib "$(_mib "${total:-0}")"

  vs="$(vm_stat 2>/dev/null)"
  if [ -n "$vs" ]; then
    _pg() { printf '%s\n' "$vs" | awk -v pat="$1" '$0 ~ pat {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.?$/){gsub(/\./,"",$i); print $i; exit}}'; }
    free="$(_pg 'Pages free')";                       free="${free:-0}"
    active="$(_pg 'Pages active')";                   active="${active:-0}"
    inactive="$(_pg 'Pages inactive')";               inactive="${inactive:-0}"
    spec="$(_pg 'Pages speculative')";                spec="${spec:-0}"
    wired="$(_pg 'Pages wired down')";                wired="${wired:-0}"
    compressed="$(_pg 'Pages occupied by compressor')"; compressed="${compressed:-0}"
    purge="$(_pg 'Pages purgeable')";                  purge="${purge:-0}"

    used=$(( (active + wired + compressed) * pagesize ))
    # reclamável: o sistema entrega isto sem swap
    avail=$(( (free + inactive + spec + purge) * pagesize ))
    [ "$avail" -lt 0 ] && avail=0
    _kv mem.used_mib      "$(_mib "$used")"
    _kv mem.available_mib "$(_mib "$avail")"
    _kv mem.reclaimable_mib "$(_mib $(( (inactive + spec + purge) * pagesize )))"
    if [ "${total:-0}" -gt 0 ]; then _kv mem.used_pct $(( used * 100 / total )); else _kv mem.used_pct 0; fi
  fi

  # swap em uso indica pressão real, não folga aparente
  _kv mem.swap_used "$(_sysctl vm.swapusage | awk '{for(i=1;i<=NF;i++) if($i=="used"){print $(i+2); exit}}')"
}

# ── disco ───────────────────────────────────────────────────────────────────
# O .vdi do HAOS vem com 32 GB e CRESCE. O VirtualBox não devolve espaço por
# padrão — daí o --discard on. Medimos o volume que vai hospedar a VM.
# Fonte: df -k
probe_disk() {
  local vmdir avail_kb
  vmdir="${HOME}/VirtualBox VMs"
  [ -d "$vmdir" ] || vmdir="$HOME"
  avail_kb="$(df -k "$vmdir" 2>/dev/null | awk 'NR==2 {print $4}')"
  _kv disk.vm_path       "$vmdir"
  _kv disk.available_mib "$(( ${avail_kb:-0} / 1024 ))"
  _kv disk.root_used_pct "$(df -k / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
}

# ── VirtualBox ──────────────────────────────────────────────────────────────
# O instalador NÃO instala o VirtualBox: é cask com senha de admin e aprovação
# de extensão de sistema. A sonda só reporta o estado.
probe_virtualbox() {
  if _have VBoxManage; then
    _kv vbox.present 1
    _kv vbox.version "$(VBoxManage --version 2>/dev/null | tr -d '\r')"
    _kv vbox.path    "$(command -v VBoxManage)"
  else
    _kv vbox.present 0
    _kv vbox.version ""
    _kv vbox.hint    "brew install --cask virtualbox"
  fi
  if [ -d /Applications/VirtualBox.app ]; then _kv vbox.app 1; else _kv vbox.app 0; fi
}

# ── rede ────────────────────────────────────────────────────────────────────
# Insumo do adaptador de bridge. A doc do HA aceita Wi-Fi E Ethernet, então
# reportamos as duas — a escolha é de quem decide, não da sonda.
# Fonte: networksetup -listallhardwareports · ifconfig · VBoxManage list bridgedifs
probe_network() {
  local port dev ip status n=0
  while IFS= read -r line; do
    case "$line" in
      "Hardware Port: "*) port="${line#Hardware Port: }" ;;
      "Device: "*)
        dev="${line#Device: }"
        ip="$(ipconfig getifaddr "$dev" 2>/dev/null)"
        status="$(ifconfig "$dev" 2>/dev/null | awk '/status:/{print $2}')"
        # Meio físico pelo `media` do ifconfig, NUNCA pelo nome do port: a
        # interface cabeada desta máquina chama-se "USB 10/100/1000 LAN", e em
        # outras "Thunderbolt Ethernet Slot 1" ou o modelo do chip. Casar por
        # substring "Ethernet" rejeita cabo de verdade.
        media="$(ifconfig "$dev" 2>/dev/null | awk '/media:/{print; exit}')"
        wired=0
        case "$media" in
          *baseT*|*10Gbase*) wired=1 ;;
        esac
        case "$media" in *"IEEE 802.11"*|*none*) wired=0 ;; esac
        # Wi-Fi não tem `media: ... baseT`; o port do 802.11 é reportado como
        # "Wi-Fi" e o media vem vazio ou como autoselect sem tipo de par.
        [ "$port" = "Wi-Fi" ] && wired=0
        # Listamos TAMBÉM interface sem IP: cabo plugado sem lease é invisível
        # se filtrarmos por IP, e aí o portão acusa "sem interface cabeada" com
        # o cabo na mão.
        if [ -n "$ip" ] || [ "${status:-}" = "active" ]; then
          n=$(( n + 1 ))
          _kv "net.${n}.device" "$dev"
          _kv "net.${n}.port"   "$port"
          _kv "net.${n}.ip"     "${ip:-}"
          _kv "net.${n}.status" "${status:-unknown}"
          _kv "net.${n}.wired"  "$wired"
        fi
        ;;
    esac
  done <<EOF
$(networksetup -listallhardwareports 2>/dev/null)
EOF
  _kv net.count "$n"
  # nome que o VBoxManage espera em --bridgeadapter1 NÃO é o device (en0):
  # é o nome de exibição do 'list bridgedifs'. Só existe com VirtualBox presente.
  if _have VBoxManage; then
    _kv net.bridged_names "$(VBoxManage list bridgedifs 2>/dev/null | awk -F': *' '/^Name:/{printf "%s|", $2}')"
  fi
}

# ── o que já roda ───────────────────────────────────────────────────────────
# Capacidade nominal não basta: se a máquina já serve outras coisas, o que
# importa é o que sobra. Reporta os 5 maiores consumidores de memória.
probe_workload() {
  local n=0
  while read -r rss comm; do
    [ -z "${rss:-}" ] && continue
    n=$(( n + 1 ))
    _kv "load.${n}.mib"  "$(( rss / 1024 ))"
    _kv "load.${n}.proc" "$(basename "$comm" 2>/dev/null)"
    [ "$n" -ge 5 ] && break
  done <<EOF
$(ps -A -o rss=,comm= -r 2>/dev/null | head -20 | sort -rn | head -5)
EOF
  _kv load.count "$n"
  _kv load.uptime "$(uptime 2>/dev/null | sed 's/.*up //; s/,.*users.*//')"
}

probe_all() {
  _kv probe.version "$PROBE_VERSION"
  _kv probe.epoch   "$(date +%s)"
  probe_identity; probe_cpu; probe_memory; probe_disk
  probe_virtualbox; probe_network; probe_workload
}

# ── tabela legível ──────────────────────────────────────────────────────────
_table() {
  local kv; kv="$(probe_all)"
  _g() { printf '%s\n' "$kv" | awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); print; exit}'; }

  printf '\n  SONDA DO HOSPEDEIRO  ·  probe-host.sh v%s\n' "$PROBE_VERSION"
  printf '  %s\n\n' "$(printf '%.0s-' $(seq 1 66))"
  printf '  Máquina    %s · %s\n' "$(_g host.model)" "$(_g host.cpu)"
  printf '  macOS      %s (%s) · arch %s\n' "$(_g host.macos)" "$(_g host.build)" "$(_g host.arch)"
  [ "$(_g host.apple_silicon)" = "1" ] || printf '  ATENÇÃO    não é Apple Silicon — a imagem do HAOS é aarch64\n'
  printf '\n  CPU        %s lógicos = %s performance + %s eficiência · carga %s\n' \
    "$(_g cpu.logical)" "$(_g cpu.performance)" "$(_g cpu.efficiency)" "$(_g cpu.load1)"
  printf '  Memória    %s MiB totais · %s em uso (%s%%) · %s MiB disponíveis\n' \
    "$(_g mem.total_mib)" "$(_g mem.used_mib)" "$(_g mem.used_pct)" "$(_g mem.available_mib)"
  printf '  Swap       %s\n' "$(_g mem.swap_used)"
  printf '  Disco      %s MiB livres em %s\n' "$(_g disk.available_mib)" "$(_g disk.vm_path)"
  if [ "$(_g vbox.present)" = "1" ]; then
    printf '  VirtualBox %s\n' "$(_g vbox.version)"
  else
    printf '  VirtualBox AUSENTE — %s\n' "$(_g vbox.hint)"
  fi
  printf '\n  Interfaces com IP:\n'
  local i=1 n; n="$(_g net.count)"
  while [ "$i" -le "${n:-0}" ]; do
    printf '    %-6s %-22s %-15s %s\n' "$(_g net.$i.device)" "$(_g net.$i.port)" "$(_g net.$i.ip)" "$(_g net.$i.status)"
    i=$(( i + 1 ))
  done
  printf '\n  Maiores consumidores de memória:\n'
  i=1; n="$(_g load.count)"
  while [ "$i" -le "${n:-0}" ]; do
    printf '    %6s MiB  %s\n' "$(_g load.$i.mib)" "$(_g load.$i.proc)"
    i=$(( i + 1 ))
  done
  printf '\n  Ligado há %s\n\n' "$(_g load.uptime)"
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  case "${1:-}" in
    --table) _table ;;
    --help|-h) sed -n '2,14p' "$0" ;;
    *) probe_all ;;
  esac
fi
