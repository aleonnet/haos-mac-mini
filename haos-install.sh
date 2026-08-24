#!/usr/bin/env bash
# shellcheck disable=SC2034
# SC2034: o padrão IFS='|' read descompacta todos os campos dos registros do
#         catálogo mesmo quando nem todos são usados numa dada função.
# =============================================================================
# haos-install.sh — instala Home Assistant OS numa VM VirtualBox em Mac Apple
#                   Silicon.
#
# Local:  bash haos-install.sh [opções]
# Remoto: curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash -s -- [opções]
#
# Sem opções e com terminal: sonda a máquina, oferece o seletor, mostra o plano
# e pede confirmação. Nada é escrito antes disso.
#
# Licença MIT. https://github.com/aleonnet/haos-mac-mini
# =============================================================================
set -Eeuo pipefail

HAOS_INSTALL_VERSION="0.1.0-dev"
HAOS_REF_CORE="2026.8.3"      # versão do HA contra a qual o contrato foi verificado
HAOS_REF_OS="18.2"
HAOS_RAW_URL="https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh"

# ── imagem do HAOS ───────────────────────────────────────────────────────────
# versão|URL|SHA-256|bytes
#
# O hash vive AQUI porque o GitHub não publica um .sha256 ao lado do asset —
# medido em 23/08: o `<url>.sha256` responde 404. Sem hash de origem não há
# como separar download truncado de imagem adulterada, e um .vdi corrompido só
# se manifestaria no boot da VM, tarde demais e com erro incompreensível.
#
# O tamanho é conferido ANTES do hash: é comparação de metadado, não leitura de
# 380 MiB, e descarta o caso comum (arquivo pela metade) sem custo.
HAOS_IMAGE_DB=(
"18.2|https://github.com/home-assistant/operating-system/releases/download/18.2/haos_generic-aarch64-18.2.vdi.zip|cd2d6b2336b50e7a47d548862f6271db78c8563afb3fdd8bd4a6a59f02639787|397964849"
)

# Exit codes — convenção do projeto:
#   0 ok · 2 uso incorreto · 3 validação · 4 dependência ausente · 10 conexão
#   130 cancelado pelo usuário
E_USO=2; E_VALID=3; E_DEP=4; E_CONEXAO=10; E_CANCELADO=130

# =============================================================================
# F0 — PREÂMBULO
# =============================================================================

# ── limpeza ──────────────────────────────────────────────────────────────────
# Um único trap, do instalador. Bibliotecas não instalam trap: `trap` é global
# do shell e quem chama por último vence — um trap dentro de lib APAGARIA este,
# em silêncio, levando junto a limpeza de temporários e o desfazer de fase.
TMPFILES=()
FASE_ATUAL=""
VBOX_PONTO=""
limpar() {
    local rc=$?
    local f
    for f in "${TMPFILES[@]:-}"; do
        if [ -n "$f" ]; then rm -rf "$f" 2>/dev/null || true; fi
    done
    # Imagem montada também é sujeira, e some do radar com facilidade.
    if [ -n "$VBOX_PONTO" ]; then desmontar "$VBOX_PONTO"; fi
    if declare -F ha_show_cursor >/dev/null 2>&1; then
        ha_show_cursor
    elif [ -t 1 ]; then
        tput cnorm 2>/dev/null || true
    fi
    # O espelho da execução sai AQUI, no trap: uma execução que morre no meio é
    # exatamente a que mais precisa de registro. Dry-run e os modos que só leem
    # nunca chegam a MAIN_INICIADO=1, então não escrevem nada.
    if [ "${MAIN_INICIADO:-0}" = "1" ] && [ "${OP_DRYRUN:-0}" != "1" ]; then
        escrever_last_run "$rc" || true
    fi
    if [ "$rc" != "0" ] && [ -n "$FASE_ATUAL" ]; then
        printf '\n%s\n' "$(msg interrompido "$FASE_ATUAL")" >&2
        printf '%s\n' "$(msg reexecutar_seguro)" >&2
        if [ -n "${LOG_FILE:-}" ] && [ -s "${LOG_FILE:-/nonexistent}" ]; then
            printf '%s\n' "$(msg log_em "$LOG_FILE")" >&2
        fi
    fi
    # Sucesso limpa o log; falha o preserva — ele acabou de ser nomeado acima.
    if [ "$rc" = "0" ] && [ -n "${LOG_FILE:-}" ]; then
        rm -f "$LOG_FILE" 2>/dev/null || true
    fi
    exit "$rc"
}
# O trap é REGISTRADO lá embaixo, depois da guarda de biblioteca: instalar um
# trap de EXIT aqui vazaria para quem faz `source` deste arquivo (a bancada).

mktempfile() { local f; f="$(mktemp)"; TMPFILES+=("$f"); printf '%s' "$f"; }
mktempdir()  { local d; d="$(mktemp -d)"; TMPFILES+=("$d"); printf '%s' "$d"; }

# ── idioma ───────────────────────────────────────────────────────────────────
# pt-BR quando o locale do Mac for português; en-US no resto. Uma chave sem par
# nas duas línguas é erro de CI, não string faltando em runtime.
IDIOMA="en"
case "${LANG:-}${LC_ALL:-}" in *pt_BR*|*pt_PT*|*pt*) IDIOMA="pt" ;; esac
[ "${HAOS_LANG:-}" = "pt" ] && IDIOMA="pt"
[ "${HAOS_LANG:-}" = "en" ] && IDIOMA="en"

msg() {
    local chave="$1"; shift
    local linha pt en
    for linha in "${MSG_DB[@]}"; do
        case "$linha" in "$chave|"*)
            linha="${linha#*|}"; pt="${linha%%|*}"; en="${linha#*|}"
            # `printf --` é obrigatório: mensagem que começa com "--" (ex.:
            # "--dry-run: nada foi escrito") seria lida como opção do printf.
            # shellcheck disable=SC2059
            [ "$IDIOMA" = "pt" ] && printf -- "$pt" "$@" || printf -- "$en" "$@"
            return 0 ;;
        esac
    done
    printf '%s' "$chave"   # chave desconhecida aparece crua, não some
}

MSG_DB=(
"cabecalho|Instalador de Home Assistant OS para Mac|Home Assistant OS installer for Mac"
"preflight|Pré-voo|Pre-flight"
"selecao|Seleção|Selection"
"plano|Plano|Plan"
"so_apple_silicon|Este instalador é só para Mac com Apple Silicon (a imagem do HAOS é aarch64). Detectado: %s|This installer is for Apple Silicon Macs only (the HAOS image is aarch64). Detected: %s"
"so_macos|Este instalador é só para macOS. Detectado: %s|This installer is for macOS only. Detected: %s"
"sem_vbox|VirtualBox não encontrado.|VirtualBox not found."
"vbox_versao|VirtualBox %s|VirtualBox %s"
"vbox_antigo|VirtualBox %s é anterior à 7.1, que trouxe host ARM e --platform-architecture. Atualize.|VirtualBox %s predates 7.1, which introduced ARM hosts and --platform-architecture. Please upgrade."
"sem_python|python3 não encontrado. É dependência real: instalar app no Home Assistant exige o comando WebSocket supervisor/api, e bash não fala WebSocket.|python3 not found. This is a hard dependency: installing add-ons requires the supervisor/api WebSocket command, and bash cannot speak WebSocket."
"sem_python_como|  Instale as Command Line Tools:  xcode-select --install|  Install the Command Line Tools:  xcode-select --install"
"disco_curto|Espaço livre insuficiente em %s: %s MiB. A imagem do HAOS precisa de pelo menos %s MiB.|Not enough free space on %s: %s MiB. The HAOS image needs at least %s MiB."
"sem_rede|Sem acesso à internet. O primeiro boot do HAOS baixa o Core, e os fluxos de nuvem falham sem rede — e falham de um jeito indistinguível de credencial errada.|No internet access. The first HAOS boot downloads Core, and cloud flows fail without network - in a way indistinguishable from a wrong credential."
"aviso_ram|Memória disponível agora: %s MiB. O perfil escolhido pede %s MiB. Pode faltar sob carga.|Memory available right now: %s MiB. The chosen profile asks for %s MiB. It may fall short under load."
"aviso_wifi|Só há interface Wi-Fi. A VM usa bridge, e sobre 802.11 o quadro com MAC de origem alheio costuma ser descartado: a VM pode não obter endereço. Se falhar, use um adaptador USB-Ethernet.|Only Wi-Fi interfaces found. The VM uses bridged networking, and over 802.11 a frame with a foreign source MAC is usually dropped: the VM may not get an address. If it fails, use a USB-Ethernet adapter."
"sem_interface|Nenhuma interface de rede utilizável.|No usable network interface."
"maquina|Máquina|Machine"
"memoria|Memória|Memory"
"disco|Disco|Disk"
"rede|Rede|Network"
"cabeada|cabeada|wired"
"sem_fio|sem fio|wireless"
"perfil_vm|Perfil da VM|VM profile"
"degrau|Degrau|Tier"
"ortogonais|Extras|Extras"
"itens|itens|items"
"nada_escrito|--dry-run: nada foi escrito.|--dry-run: nothing was written."
"sem_tty_titulo|Sem terminal interativo.|No interactive terminal."
"sem_tty_como|Passe um degrau, por exemplo:|Pass a tier, for example:"
"cancelado|Cancelado.|Cancelled."
"confirmar|Instalar agora? [s/N] |Install now? [y/N] "
"portoes_pendentes|%s pré-requisito(s) não atendido(s). O plano acima é o que aconteceria depois de resolvê-los.|%s prerequisite(s) not met. The plan above is what would happen once they are resolved."
"piso_sempre|Piso: %s componentes que a própria instalação cria — não são escolha.|Floor: %s components the installation creates by itself - not a choice."
"nada_alem_do_piso|(nada além do piso; os itens deste degrau são opt-in)|(nothing beyond the floor; this tier is opt-in)"
"sem_sudo|sudo não encontrado.|sudo not found."
"pede_senha|O próximo passo instala o VirtualBox e precisa da senha de administrador. Quem pergunta é o sudo; o instalador não guarda nem repassa a senha.|The next step installs VirtualBox and needs the administrator password. sudo is what asks; this installer never stores or forwards it."
"sudo_sem_tty|sudo precisa de senha e não há terminal interativo. Rode \x27sudo -v\x27 antes, ou use --install-deps num terminal.|sudo needs a password and there is no interactive terminal. Run \x27sudo -v\x27 first, or use --install-deps from a terminal."
"vbox_ausente|VirtualBox não encontrado.|VirtualBox not found."
"vbox_instalar|Baixar e instalar o VirtualBox %s da Oracle?|Download and install Oracle VirtualBox %s?"
"vbox_baixando|Baixando VirtualBox %s (~153 MB)...|Downloading VirtualBox %s (~153 MB)..."
"vbox_download_falhou|Falha ao baixar o VirtualBox.|Failed to download VirtualBox."
"vbox_sem_sha|Não consegui obter o SHA256SUMS da Oracle — sem ele não instalo.|Could not fetch Oracle SHA256SUMS - refusing to install without it."
"vbox_sha_diverge|O SHA-256 do arquivo baixado NÃO confere com o publicado pela Oracle.|The downloaded file SHA-256 does NOT match the one Oracle publishes."
"vbox_sha_ok|SHA-256 confere com o publicado pela Oracle|SHA-256 matches the one Oracle publishes"
"vbox_mount_falhou|Não consegui montar a imagem.|Could not mount the disk image."
"vbox_sem_pkg|A imagem não contém o pacote de instalação.|The image contains no installer package."
"vbox_instalando|Instalando (installer -pkg, sem interface gráfica)...|Installing (installer -pkg, no GUI)..."
"vbox_installer_falhou|O installer(8) falhou. Rode com --verbose para ver a saída.|installer(8) failed. Run with --verbose to see the output."
"vbox_ok|VirtualBox %s instalado|VirtualBox %s installed"
"vbox_bloqueado|VirtualBox instalado, mas o VBoxManage não responde. O macOS costuma BLOQUEAR a extensão de sistema da Oracle na primeira instalação: abra Ajustes do Sistema, Privacidade e Segurança, e Permitir o software da Oracle. Pode exigir reinício. Depois rode este instalador de novo.|VirtualBox installed, but VBoxManage does not respond. macOS usually BLOCKS the Oracle system extension on first install: open System Settings, Privacy & Security, and Allow the Oracle software. A restart may be required. Then run this installer again."
"vbox_nao_desmontou|Não consegui desmontar %s — algum processo ainda a segura. Desmonte com: hdiutil detach -force %s|Could not unmount %s - some process still holds it. Unmount with: hdiutil detach -force %s"
"subtitulo|numa VM VirtualBox no Mac|on a VirtualBox VM on Mac"
"nao_implementado|As fases de execução ainda não estão implementadas nesta versão (%s).|Execution phases are not implemented yet in this version (%s)."
"imagem|Imagem|Image"
"img_sem_tabela|Não há imagem catalogada para a versão %s do HAOS.|No image catalogued for HAOS version %s."
"img_ja|Imagem %s já está em %s — nada a baixar.|Image %s already at %s - nothing to download."
"img_local|Encontrei o arquivo local %s e o hash confere: não vou baixar de novo.|Found local file %s and the hash matches: not downloading again."
"img_local_descartado|O arquivo local %s não confere com a tabela e foi ignorado.|Local file %s does not match the table and was ignored."
"img_baixando|Baixando a imagem do HAOS %s — %s MiB.|Downloading the HAOS %s image - %s MiB."
"img_download_falhou|Falhou o download da imagem do HAOS.|HAOS image download failed."
"img_sem_baixador|Nem curl nem wget estão disponíveis para baixar a imagem.|Neither curl nor wget is available to download the image."
"img_sem_unzip|O comando unzip não está disponível, e a imagem vem compactada.|The unzip command is unavailable, and the image ships compressed."
"img_tamanho_diverge|A imagem baixada tem %s bytes; a tabela diz %s. Download incompleto.|The downloaded image has %s bytes; the table says %s. Incomplete download."
"img_sha_ok|SHA-256 da imagem confere.|Image SHA-256 matches."
"img_sha_diverge|O SHA-256 da imagem NÃO confere. Não vou descompactar.|The image SHA-256 does NOT match. Not extracting."
"img_descompactando|Descompactando a imagem.|Extracting the image."
"img_sem_vdi|O arquivo compactado não contém nenhum .vdi.|The archive contains no .vdi file."
"img_pronta|Imagem pronta: %s|Image ready: %s"
"interrompido|Interrompido na fase %s. Nada além dela foi alterado.|Interrupted during phase %s. Nothing beyond it was changed."
"reexecutar_seguro|Reexecutar é seguro: o instalador continua de onde parou.|Re-running is safe: the installer continues from where it stopped."
"log_em|Saída das ferramentas desta execução: %s|Tool output of this run: %s"
"log_ultimas|últimas linhas do log (%s):|last log lines (%s):"
"rede_titulo|Isto parece problema de REDE, não da sua máquina:|This looks like a NETWORK problem, not a problem with your machine:"
"rede_dica1|verifique a conexão — VPN, proxy e firewall são os suspeitos de sempre|check your connection - VPN, proxy or firewall are the usual suspects"
"rede_dica2|nada ficou pela metade: rodar o mesmo comando de novo continua de onde parou|nothing was left half-done: running the same command again continues from where it stopped"
"flag_sem_valor|%s exige um valor|%s requires a value"
"opcao_desconhecida|opção desconhecida: %s|unknown option: %s"
"python3_versao|python3 %s|python3 %s"
"fase_vm|VM|VM"
"relatorio_salvo|Relatório da execução: %s|Run report: %s"
)

# ── saída ────────────────────────────────────────────────────────────────────
# UMA gramática visual: a calha da camada embutida (ha_ok · ha_info · ha_warn ·
# ha_err · ha_skip), a mesma dos dois instaladores irmãos. Os glifos degradam
# para ASCII sob locale não-UTF-8 e a cor some sem TTY/NO_COLOR — nenhuma
# informação vive só na cor. A voz antiga, de prefixos textuais em funções
# próprias, era uma segunda gramática no mesmo produto, e o verify.sh agora
# reprova a volta dela. As definições vivem na camada visual embutida, mais
# abaixo; bash resolve função em runtime, então a ordem no arquivo não importa.

# ha_fase <título> — cabeçalho de fase que também alimenta o estado global:
# FASE_ATUAL é o que a mensagem de interrupção do limpar() imprime, e a barra
# de fase da calha anda junto. A camada visual não conhece esse estado — é o
# instalador que o mantém (achado da banca: mover fase() para a lib perderia
# FASE_ATUAL em silêncio).
ha_fase() {
    FASE_ATUAL="$1"
    HA_BAR_N=$(( ${HA_BAR_N:-0} + 1 ))
    ha_phase "$1"
}

morrer() { local code="$1"; shift; ha_err "$*"; exit "$code"; }

# Em --dry-run, portão duro não aborta: reporta e segue, para o operador
# conseguir VER o plano numa máquina que ainda não tem tudo. Achado R5 da banca:
# o único modo que existe para inspecionar a ferramenta não pode exigir que a
# máquina já esteja pronta.
PORTOES_ABERTOS=0
portao() {
    local code="$1"; shift
    if [ "$OP_DRYRUN" = "1" ]; then
        ha_warn "$*"
        PORTOES_ABERTOS=$(( PORTOES_ABERTOS + 1 ))
        return 0
    fi
    ha_err "$*"; exit "$code"
}

# ── terminal interativo ──────────────────────────────────────────────────────
# Testa /dev/tty, NUNCA stdin: em `curl | bash` stdin é o cano, e testar stdin
# faria o instalador se declarar não-interativo justamente no modo em que é
# distribuído. -r/-w não bastam — sessão detached falha no open.
tem_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ] || return 1
    ( : </dev/tty ) 2>/dev/null || return 1
    return 0
}
perguntar() {
    local prompt="$1" resp=""
    tem_tty || return 1
    printf '%s' "$prompt" >/dev/tty
    IFS= read -r resp </dev/tty || true
    [[ "${resp:-N}" =~ ^[sSyY]$ ]]
}

# ── sudo ─────────────────────────────────────────────────────────────────────
# A credencial é PRIMADA antes, uma vez só, lendo o terminal de verdade. Sem
# isso um prompt de senha cairia dentro de um passo com spinner e travaria — e
# em `curl | bash` stdin é o cano, então tem de vir de $TTY_DEV.
# O instalador NUNCA guarda, ecoa ou passa a senha adiante: quem pergunta é o
# sudo, e o cache é do sistema.
TTY_DEV="${TTY_DEV:-/dev/tty}"

garantir_sudo() {
    [ "$(id -u)" = "0" ] && return 0
    command -v sudo >/dev/null 2>&1 || { ha_err "$(msg sem_sudo)"; return 1; }
    if sudo -n true 2>/dev/null; then return 0; fi
    if [ -r "$TTY_DEV" ]; then
        ha_info "$(msg pede_senha)"
        # shellcheck disable=SC2024
        # O aviso é sobre redirecionar SAÍDA com sudo. Aqui o redirecionamento é
        # de ENTRADA, e é o ponto: o sudo tem de ler a senha do terminal real,
        # porque em `curl | bash` o stdin do script é o cano.
        sudo -v < "$TTY_DEV" || return 1
        return 0
    fi
    ha_err "$(msg sudo_sem_tty)"
    return 1
}

# confirmar "pergunta" — 0 = sim. Lê o terminal real, seguro sob `curl | bash`.
# Sem TTY: só --install-deps ou --no-input decidem; o padrão é não.
confirmar_dep() {
    local q="$1" r=""
    [ "$OP_INSTALL_DEPS" = "1" ] && return 0
    [ -r "$TTY_DEV" ] || return 1
    [ "$OP_NOINPUT" = "1" ] && return 1
    printf '%s [s/N] ' "$q" > "$TTY_DEV"
    IFS= read -r r < "$TTY_DEV" || true
    case "${r:-N}" in s|S|y|Y) return 0 ;; *) return 1 ;; esac
}

# ── VirtualBox ───────────────────────────────────────────────────────────────
# Contrato de retorno: 0 instalou agora · 100 já estava · 1 falhou.
#
# Por que o .dmg da Oracle e não o Homebrew: o cask apenas embrulha ESTE mesmo
# .dmg e roda o mesmo .pkg. Passar pelo brew obrigaria a instalar um gerenciador
# de pacotes inteiro que o usuário pode não querer, e pediria a senha DUAS vezes
# — uma para criar /opt/homebrew, outra para o pkg. Medido em 23/08 no Mac mini
# alvo: não havia Homebrew.
#
# Sem interface gráfica em momento nenhum: `installer(8)` é a mesma ferramenta
# que o Installer.app usa por baixo.
# `hdiutil detach` falha com "Resource busy" enquanto qualquer processo segurar
# o volume — medido em 23/08: o Installer.app segurava o .pkg. Sem -force o
# volume ficava montado para sempre, e um `|| true` esconderia isso.
desmontar() {
    local ponto="$1" i=0
    [ -n "$ponto" ] || return 0
    [ -d "$ponto" ] || { VBOX_PONTO=""; return 0; }
    while [ "$i" -lt 3 ]; do
        if hdiutil detach -quiet "$ponto" 2>/dev/null; then VBOX_PONTO=""; return 0; fi
        i=$(( i + 1 )); sleep 1
    done
    if hdiutil detach -force -quiet "$ponto" 2>/dev/null; then VBOX_PONTO=""; return 0; fi
    ha_warn "$(msg vbox_nao_desmontou "$ponto")"
    VBOX_PONTO=""
    return 1
}

VBOX_VERSAO="7.2.16"
VBOX_BUILD="174877"
VBOX_DMG="VirtualBox-${VBOX_VERSAO}-${VBOX_BUILD}-macOSArm64.dmg"
VBOX_BASE="https://download.virtualbox.org/virtualbox/${VBOX_VERSAO}"

garantir_virtualbox() {
    command -v VBoxManage >/dev/null 2>&1 && return 100

    ha_warn "$(msg vbox_ausente)"
    confirmar_dep "$(msg vbox_instalar "$VBOX_VERSAO")" || return 1
    garantir_sudo || return 1

    local dir dmg sha_arq esperado obtido ponto pkg
    dir="$(mktempdir)"; dmg="$dir/$VBOX_DMG"

    ha_run_step "$(msg vbox_baixando "$VBOX_VERSAO")" \
        curl -fL -sS --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
        -o "$dmg" "$VBOX_BASE/$VBOX_DMG" || { ha_err "$(msg vbox_download_falhou)"; return 1; }

    # Hash SEMPRE. --force não pula isto: montar imagem não verificada é
    # executar binário de origem não confirmada.
    sha_arq="$dir/SHA256SUMS"
    curl -fsSL --proto '=https' -o "$sha_arq" "$VBOX_BASE/SHA256SUMS" 2>/dev/null         || { ha_err "$(msg vbox_sem_sha)"; return 1; }
    esperado="$(awk -v f="$VBOX_DMG" '$0 ~ f {print $1; exit}' "$sha_arq")"
    obtido="$(shasum -a 256 "$dmg" | awk '{print $1}')"
    if [ -z "$esperado" ] || [ "$esperado" != "$obtido" ]; then
        ha_err "$(msg vbox_sha_diverge)"
        printf '    esperado: %s\n    obtido  : %s\n' "${esperado:-<ausente>}" "$obtido" >&2
        return 1
    fi
    ha_ok "$(msg vbox_sha_ok)"

    ponto="$(hdiutil attach -nobrowse -readonly -quiet "$dmg" 2>/dev/null              | awk -F'\t' '/Volumes/{print $NF}' | tail -1)"
    [ -n "$ponto" ] || { ha_err "$(msg vbox_mount_falhou)"; return 1; }
    # desmonta aconteça o que acontecer, inclusive em erro no meio
    VBOX_PONTO="$ponto"

    pkg="$(find "$ponto" -maxdepth 1 -name '*.pkg' | head -1)"
    if [ -z "$pkg" ]; then
        desmontar "$ponto"
        ha_err "$(msg vbox_sem_pkg)"; return 1
    fi

    # sudo já foi primado no topo desta função — o installer roda com -n
    # implícito no cache; nenhum prompt pode cair dentro do spinner.
    local rc_inst=0
    ha_run_step "$(msg vbox_instalando)" sudo installer -pkg "$pkg" -target / || rc_inst=$?
    desmontar "$ponto"
    if [ "$rc_inst" != "0" ]; then ha_err "$(msg vbox_installer_falhou)"; return 1; fi

    # Re-sonda: instalado não é o mesmo que utilizável. Se o macOS bloqueou a
    # extensão de sistema, o binário existe e não funciona — e dizer isso aqui
    # é melhor que falhar na criação da VM com erro incompreensível.
    if command -v VBoxManage >/dev/null 2>&1 && VBoxManage --version >/dev/null 2>&1; then
        ha_ok "$(msg vbox_ok "$(VBoxManage --version 2>/dev/null | tr -d '\r')")"
        return 0
    fi
    ha_err "$(msg vbox_bloqueado)"
    return 1
}

# ── download ─────────────────────────────────────────────────────────────────
baixador() {
    if command -v curl >/dev/null 2>&1; then printf 'curl'; return 0; fi
    if command -v wget >/dev/null 2>&1; then printf 'wget'; return 0; fi
    return 1
}

# ── log da execução ──────────────────────────────────────────────────────────
# Um arquivo por execução, criado SÓ quando o primeiro passo real roda — assim
# o --dry-run continua não escrevendo nada, nem em /tmp. Fica FORA de TMPFILES
# de propósito: o limpar() apagaria exatamente o arquivo que a mensagem de erro
# acabou de nomear. Sucesso limpa; falha preserva e imprime o caminho.
LOG_FILE=""
garantir_log() {
    [ -n "$LOG_FILE" ] && return 0
    LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/haos-install-XXXXXX" 2>/dev/null)" \
        || LOG_FILE="${TMPDIR:-/tmp}/haos-install-$$.log"
    return 0
}

# Assina uma falha de REDE a partir do que a ferramenta escreveu no log. As
# frases são as que curl/wget realmente emitem — não um palpite.
falha_de_rede() {
    [ -n "$LOG_FILE" ] && [ -s "$LOG_FILE" ] || return 1
    LC_ALL=C tail -40 "$LOG_FILE" | LC_ALL=C grep -qiE \
        'could not resolve host|failed to connect|connection refused|connection timed out|network is unreachable|no route to host|ssl|tls|operation timed out|temporary failure in name resolution'
}

# Depois de um passo falhar: diz se parece rede (em vez de despejar stack de
# ferramenta como se fosse culpa da máquina) e mostra as últimas linhas do log.
# NÃO sai do script — o chamador mantém o próprio código de erro (contrato
# 0/100/1 das funções de fase; achado B-6 da banca).
diagnostico_log() {
    if falha_de_rede; then
        ha_warn "$(msg rede_titulo)"
        ha_info "$(msg rede_dica1)"
        ha_info "$(msg rede_dica2)"
    fi
    if [ -n "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        printf '   %s\n' "$(msg log_ultimas "$LOG_FILE")" >&2
        tail -12 "$LOG_FILE" | sed 's/^/    | /' >&2
    fi
    return 0
}

# ── ha_run_step: um passo com spinner, tempo e log ──────────────────────────
# REGRA DA BANCA (B-6): só embrulha COMANDO EXTERNO FOLHA (curl, unzip, shasum,
# installer, VBoxManage) — nunca função de fase. O comando roda em background, e
# num subshell qualquer variável global gravada se perde: foi assim que o .dmg
# ficaria montado para sempre. Prompt nenhum pode acontecer aqui dentro: sudo e
# confirmações são primados ANTES, pelos chamadores.
# HA_STEP_OK lista os códigos aceitos (padrão "0"); volta ao padrão a cada uso.
RUN_STEPS=""
HA_STEP_OK="0"
ha_run_step() { # <rótulo já traduzido> <cmd...>
    local rotulo="$1"; shift
    garantir_log
    local t0="$SECONDS" rc=0 aceitos="$HA_STEP_OK"
    HA_STEP_OK="0"
    if [ "$OP_VERBOSE" = "1" ]; then
        # Verbose = ver a ferramenta crua, na tela. É o modo de diagnóstico;
        # essas linhas não vão para o log (tee num pipeline sob pipefail
        # esconderia o rc do comando — bash 3.2 não dá as duas coisas).
        ha_info "$rotulo"
        "$@" || rc=$?
    else
        "$@" >>"$LOG_FILE" 2>&1 &
        ha_spin "$rotulo" "$!" || rc=$?
    fi
    RUN_STEPS="${RUN_STEPS}${rotulo}|$(( SECONDS - t0 ))
"
    if tem_na_lista "$rc" "$aceitos"; then return "$rc"; fi
    diagnostico_log
    return "$rc"
}

# ── estado local: ~/.config/haos-mac-mini ────────────────────────────────────
# Derivado de $HOME NO MOMENTO DA CHAMADA, nunca congelado no topo: é o que
# permite à bancada apontar um $HOME sintético (achado B-7). HAOS_STATE_DIR é a
# costura de teste documentada.
haos_state_dir() { printf '%s' "${HAOS_STATE_DIR:-$HOME/.config/haos-mac-mini}"; }

# Espelho da execução, no espírito do last-run.log dos irmãos: o log guarda a
# saída das ferramentas; ISTO guarda o que o instalador fez. Best-effort —
# escrituração nunca derruba uma instalação.
escrever_last_run() { # <rc>
    local rc="$1" d linha
    d="$(haos_state_dir)"
    mkdir -p "$d" 2>/dev/null || return 0
    {
        printf 'haos-install.sh %s — %s\n' "$HAOS_INSTALL_VERSION" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'rc=%s' "$rc"
        [ -n "${FASE_ATUAL:-}" ] && printf ' · fase=%s' "$FASE_ATUAL"
        [ -n "${SEL_DEGRAU:-}" ] && printf ' · degrau=%s' "$SEL_DEGRAU"
        [ -n "${SEL_EXTRAS:-}" ] && printf ' · extras=%s' "$SEL_EXTRAS"
        printf '\n\n'
        printf '%s' "$RUN_STEPS" | while IFS='|' read -r linha segs; do
            [ -n "$linha" ] && printf '  %-52s %ss\n' "$linha" "$segs"
        done
        [ -n "${LOG_FILE:-}" ] && [ -s "${LOG_FILE:-/nonexistent}" ] \
            && printf '\nlog das ferramentas: %s\n' "$LOG_FILE"
    } > "$d/last-run.log" 2>/dev/null || true
    return 0
}


# ── F3: a imagem do HAOS ─────────────────────────────────────────────────────
# Contrato de retorno, o mesmo do garantir_virtualbox: 0 fez agora · 100 já
# estava · 1 falhou.
#
# Idempotência sem hash do .vdi: hashear o disco descompactado a cada execução
# custaria minutos, então ao lado dele fica um arquivo .origem com a versão, o
# hash do .zip de onde saiu e o tamanho gravado. Bate os três, não refaz nada.
# É proveniência conferível, não fé no nome do arquivo.
HAOS_VDI=""

fase_imagem() {
    ha_fase "$(msg imagem)"

    local ver="$HAOS_REF_OS" r rv url sha bytes achou=0
    for r in "${HAOS_IMAGE_DB[@]}"; do
        IFS='|' read -r rv url sha bytes <<< "$r"
        [ "$rv" = "$ver" ] && { achou=1; break; }
    done
    if [ "$achou" != "1" ]; then ha_err "$(msg img_sem_tabela "$ver")"; return 1; fi

    local destdir vdi origem nome
    destdir="$HOME/VirtualBox VMs/$OP_VM_NOME"
    nome="haos_generic-aarch64-${ver}.vdi"
    vdi="$destdir/$nome"
    origem="$destdir/.${nome}.origem"
    HAOS_VDI="$vdi"

    # ── já está? ────────────────────────────────────────────────────────────
    if [ "$OP_FORCE" != "1" ] && [ -f "$vdi" ] && [ -f "$origem" ]; then
        local ov osha otam tam_atual
        IFS='|' read -r ov osha otam < "$origem"
        tam_atual="$(wc -c < "$vdi" 2>/dev/null | tr -d ' ')"
        if [ "$ov" = "$ver" ] && [ "$osha" = "$sha" ] && [ "$otam" = "$tam_atual" ]; then
            ha_ok "$(msg img_ja "$ver" "$vdi")"
            return 100
        fi
    fi

    mkdir -p "$destdir" || return 1

    # ── já existe um .zip que sirva? ────────────────────────────────────────
    # Tamanho primeiro: é metadado, e descarta o arquivo pela metade sem ler
    # 380 MiB. Só o que passa no tamanho paga o hash.
    local cache zipnome zip="" cand tam baixamos=0
    cache="$HOME/Library/Caches/haos-mac-mini"
    zipnome="$(basename "$url")"
    for cand in "$cache/$zipnome" "./$zipnome"; do
        [ -f "$cand" ] || continue
        tam="$(wc -c < "$cand" 2>/dev/null | tr -d ' ')"
        [ "$tam" = "$bytes" ] || { ha_warn "$(msg img_local_descartado "$cand")"; continue; }
        if [ "$(shasum -a 256 "$cand" | awk '{print $1}')" = "$sha" ]; then
            ha_ok "$(msg img_local "$cand")"; zip="$cand"; break
        fi
        ha_warn "$(msg img_local_descartado "$cand")"
    done

    # ── baixar ──────────────────────────────────────────────────────────────
    if [ -z "$zip" ]; then
        baixamos=1
        local dl
        dl="$(baixador)" || { ha_err "$(msg img_sem_baixador)"; return 1; }
        mkdir -p "$cache" || return 1
        zip="$cache/$zipnome"
        ha_info "$(msg img_baixando "$ver" "$(( bytes / 1048576 ))")"
        # O parcial vai para um nome à parte: interrompido no meio, um arquivo
        # com o nome final e o tamanho errado seria "encontrado" na próxima
        # execução e reprovado no hash — ruído em vez de retomada.
        local parcial="$zip.parcial"
        rm -f "$parcial"
        # Barra de progresso só quando há terminal. Em log, CI ou pipe, o curl
        # escreve dezenas de linhas de estatística em stderr e afoga a saída
        # útil — medido: 87 s de download viraram uma linha ilegível de 8 KB.
        # Com TTY o download fica FORA do ha_run_step de propósito: para
        # 380 MiB a barra nativa do curl informa mais que um spinner. Sem TTY,
        # o stderr vai para o log e uma falha ganha o diagnóstico de rede.
        local rc_dl=0
        if [ -t 2 ]; then
            case "$dl" in
                curl) curl -fL --progress-bar --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
                           -o "$parcial" "$url" || rc_dl=$? ;;
                wget) wget -q --https-only -O "$parcial" "$url" || rc_dl=$? ;;
            esac
        else
            garantir_log
            case "$dl" in
                curl) curl -fL -sS --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
                           -o "$parcial" "$url" >>"$LOG_FILE" 2>&1 || rc_dl=$? ;;
                wget) wget -q --https-only -O "$parcial" "$url" >>"$LOG_FILE" 2>&1 || rc_dl=$? ;;
            esac
        fi
        if [ "$rc_dl" != "0" ]; then
            rm -f "$parcial"
            ha_err "$(msg img_download_falhou)"
            diagnostico_log
            return 1
        fi
        tam="$(wc -c < "$parcial" 2>/dev/null | tr -d ' ')"
        if [ "$tam" != "$bytes" ]; then
            ha_err "$(msg img_tamanho_diverge "$tam" "$bytes")"; rm -f "$parcial"; return 1
        fi
        mv "$parcial" "$zip"
    fi

    # ── hash SEMPRE, inclusive no arquivo local e sob --force ───────────────
    # Descompactar sem conferir é executar conteúdo de origem não confirmada.
    local obtido
    obtido="$(shasum -a 256 "$zip" | awk '{print $1}')"
    if [ "$obtido" != "$sha" ]; then
        ha_err "$(msg img_sha_diverge)"
        printf '    esperado: %s\n    obtido  : %s\n' "$sha" "$obtido" >&2
        return 1
    fi
    ha_ok "$(msg img_sha_ok)"

    # ── descompactar ────────────────────────────────────────────────────────
    command -v unzip >/dev/null 2>&1 || { ha_err "$(msg img_sem_unzip)"; return 1; }

    # Descompacta DENTRO do destino, num diretório temporário irmão: o mv final
    # fica no mesmo sistema de arquivos e é atômico. Extrair em /var/folders e
    # mover para $HOME atravessaria sistemas de arquivos, e aí `mv` vira cópia
    # — que interrompida deixa um .vdi truncado com o nome definitivo.
    local tmpx="$destdir/.haos-extraindo.$$"
    rm -rf "$tmpx"; mkdir -p "$tmpx" || return 1
    if ! ha_run_step "$(msg img_descompactando)" unzip -o -q "$zip" -d "$tmpx"; then
        rm -rf "$tmpx"; return 1
    fi
    local extraido
    extraido="$(find "$tmpx" -maxdepth 2 -name '*.vdi' | head -1)"
    if [ -z "$extraido" ]; then rm -rf "$tmpx"; ha_err "$(msg img_sem_vdi)"; return 1; fi

    mv -f "$extraido" "$vdi" || { rm -rf "$tmpx"; return 1; }
    rm -rf "$tmpx"
    printf '%s|%s|%s\n' "$ver" "$sha" "$(wc -c < "$vdi" | tr -d ' ')" > "$origem"

    # Só apaga o que ESTE script baixou. O .zip que o usuário já tinha no
    # diretório é dele: encontrá-lo e apagá-lo em seguida seria cobrar 380 MiB
    # de download pelo favor de ter reaproveitado o arquivo.
    if [ "$baixamos" = "1" ] && [ "$OP_KEEP_IMAGE" != "1" ]; then rm -f "$zip"; fi
    ha_ok "$(msg img_pronta "$vdi")"
    return 0
}

# =============================================================================
# CAMADA VISUAL — cópia embutida de lib/haos-ui.sh. NÃO editar aqui.
# O shebang e o `set` da origem são removidos na cópia: valendo aqui, mudariam
# as opções do instalador em silêncio.
# =============================================================================
# >>> UI EMBUTIDO >>>
# haos-ui.sh — camada visual do instalador do HAOS, identidade Home Assistant.
# Source it as a library, or run it directly for the demo:  ./lib/haos-ui.sh --demo
#
# Design notes:
#   - Palette is Home Assistant's own: #03A9F4 primary, #00E5FF cyan, #FFC107 amber.
#   - Truecolor when available, 256-color fallback, plain text when neither.
#   - Every animation degrades to a single static frame when stdout is not a TTY,
#     when NO_COLOR is set, or when --no-anim is passed. A piped log stays readable.

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
  local line=''; printf -v line '%*s' "$w" ''; line=${line// /$HA_G_REGUA}
  printf '%s\n' "$(ha_gradient "$line")"
}

# ── barra de fase, viva na última linha ─────────────────────────────────────
# Conta FASES, não itens (o desenho do AtlasFile): o que existe de discreto e
# conhecido aqui são as fases, e um total de passos inventado é pior que barra
# nenhuma. Só aparece depois da 1ª fase, e só com animação — em log seria lixo.
# Apagar ANTES de qualquer mensagem é o que impede a barra de virar sujeira no
# meio do texto; `\033[2K` apaga a linha inteira sem depender de TERM.
HA_BAR_TOTAL=0; HA_BAR_N=0; HA_BAR_VISIVEL=0
ha_bar_limpa() {
  if [[ "$HA_BAR_VISIVEL" == 1 ]]; then printf '\r\033[2K'; HA_BAR_VISIVEL=0; fi
  return 0
}
ha_bar_mostra() {
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
# <<< UI EMBUTIDO <<<

# =============================================================================
# CATÁLOGO — cópia embutida. NÃO editar aqui: a fonte é catalog/catalog.bash,
# ./tools/embed.sh copia, e ./verify.sh reprova a divergência.
# =============================================================================
# >>> CATALOGO EMBUTIDO >>>
# =============================================================================
# catalog.bash — FONTE DE VERDADE do catálogo do instalador HAOS.
#
# O haos-install.sh é autocontido: distribuído por `curl | bash`, ele embute
# uma cópia destas tabelas. Este arquivo existe para que a cópia possa ser
# CONFERIDA — o CI compara o que está no script com o que está aqui, e deriva
# vira erro detectável em vez de bug silencioso.
#
# Sintaxe: fragmento bash, compatível com bash 3.2 (o que o macOS traz).
# Sem parser, sem formato inventado: `source` este arquivo e as tabelas estão
# na mão. Sem arrays associativos, sem namerefs.
#
# -----------------------------------------------------------------------------
# Verificado em 2026-08-23 contra:
#   Home Assistant Core 2026.8.3 (source na tag) · HAOS 18.2 · VirtualBox 7.2.16
#   doc oficial de default_config · analytics.home-assistant.io
#   manifest.json e config_flow.py de cada domínio, lidos na tag 2026.8.3
#   store do Supervisor de uma instância real (80 apps, 5 repositórios)
# =============================================================================

# -----------------------------------------------------------------------------
# CATEGORY_DB — id|rótulo|descrição
# -----------------------------------------------------------------------------
CATEGORY_DB=(
    "vanilla|Vanilla|piso do produto — o que o HAOS instala sozinho; remover é opção, não escolha"
    "conectado|Conectado|infraestrutura e protocolos de conectividade com adoção relevante"
    "casa|Casa|integrações de hardware ou serviço presente na casa"
    "ferramentas|Ferramentas|apps de manutenção e observabilidade do HAOS"
    "casa_abhome|Casa ABHOME|packages de custo com regras brasileiras — específicos desta casa"
    "extensoes|Extensões de terceiros|HACS — só a instalação, nada de dentro dele"
)

# =============================================================================
# O PISO — três partes, com procedência. O instalador precisa conhecê-lo para
# NÃO DUPLICAR o que a própria instalação já cria.
# =============================================================================

# 24 itens. Fonte: doc oficial de default_config.
DEFAULT_CONFIG_DB=(
    assist_pipeline backup bluetooth cloud config conversation dhcp
    energy file go2rtc history homeassistant_alerts image_upload
    logbook media_source mobile_app my ssdp stream sun
    usage_prediction usb webhook zeroconf
)

# Intrínsecos do HAOS. Medidos com source=system numa instância real.
# `analytics`: o COMPONENTE é piso; o ENVIO de telemetria é consentimento,
# perguntado no onboarding. Nunca assumir habilitado.
HAOS_INTRINSIC_DB=(
    "hassio|integração com o Supervisor"
    "analytics|componente presente; envio = consentimento do usuário"
)

# Criados pelo onboarding. Fonte: components/onboarding/views.py @ 2026.8.3 —
# POST /api/onboarding/core_config inicia os flows destes quatro.
ONBOARDING_DB=(
    "google_translate|texto para voz"
    "met|previsão do tempo"
    "radio_browser|catálogo de rádios"
    "shopping_list|lista de compras"
)

# =============================================================================
# ITEM_DB — 20 itens
#
# id|cat|rotulo|origem|slug|padrao|discovery|setup|preferred|requires|flags|desc
#
#  origem    core     = homeassistant/components/
#            oficial  = repositório home-assistant/addons
#            community= repositório de terceiro (exige adicionar o repositório)
#            proprio  = deste projeto
#            custom   = fora dos anteriores
#
#  slug      identificador do app no Supervisor. É `<repositório>_<app>`, NUNCA
#            o nome curto. `-` quando não é app.
#            ⚠️ O prefixo de repositório de terceiro é HASH DA URL (ex.: a0d7b954)
#            — descobrir depois de adicionar o repositório, jamais fixar.
#
#  padrao    1 pré-marcado · 0 só por escolha explícita · cond avaliado em runtime
#
#  discovery os matchers declarados no manifest. `-` = o manifest não declara
#            nenhum. NÃO é o mesmo que setup.
#
#  setup     como uma entry pode NASCER. É CERCA DE CONJUNTO: cria, lê de volta,
#            e confere se o source lido PERTENCE a esta lista. NUNCA igualdade —
#            um domínio guarda legitimamente entries com sources diferentes.
#
#  requires  dependências. Sufixo `:ha` = o próprio config flow do HA instala e
#            gerencia; o instalador NÃO deve instalar por fora, duplicaria.
#
#  flags     single_entry  o manifest declara single_config_entry: true — não
#                          tentar criar a segunda
#            schema_flow   usa SchemaConfigFlowHandler: os passos são DADOS
#                          (`CONFIG_FLOW = {"user": ...}`), não métodos
#                          `async def`. Procurar só por método dá falso negativo
#            repo_terceiro exige adicionar repositório antes de instalar
# =============================================================================
ITEM_DB=(
    # ── conectado ────────────────────────────────────────────────────────────
    "cast|conectado|Google Cast|core|-|0|zeroconf|zeroconf user|zeroconf|-|single_entry|Chromecast e telas — 50,9% de adoção"
    "mqtt|conectado|MQTT|core|-|0|-|user hassio|user|mosquitto:ha|single_entry|broker para Zigbee2MQTT, ESPHome e sensores DIY — 48,6%"
    "matter|conectado|Matter|core|-|0|zeroconf|zeroconf user|zeroconf|matter_server:ha|-|padrão aberto — 39,8%; comissionamento costuma exigir rádio"
    "thread|conectado|Thread|core|-|0|zeroconf|zeroconf user|zeroconf|openthread_border_router|single_entry|37,1%; exige border router, que NÃO é gerenciado pelo flow"
    "esphome|conectado|ESPHome|core|-|0|zeroconf dhcp mqtt|zeroconf user|zeroconf|-|-|firmware para ESP32/ESP8266 — 27,0%"

    # ── casa ─────────────────────────────────────────────────────────────────
    "hue|casa|Philips Hue|core|-|1|zeroconf homekit|user zeroconf homekit|user|-|-|iluminação — o passo 'link' pede o botão da bridge"
    "tuya|casa|Tuya|core|-|1|dhcp|user dhcp|user|-|-|SmartLife — credencial de nuvem; o flow tem passo de QR"
    "broadlink|casa|Broadlink|core|-|1|dhcp|user dhcp|dhcp|-|-|infravermelho — passos auth e unlock; exige modo de pareamento"
    "shelly|casa|Shelly|core|-|1|zeroconf bluetooth|user zeroconf bluetooth|zeroconf|-|-|medição de energia — base dos packages de custo"
    "tplink|casa|TP-Link Smart Home|core|-|1|dhcp|user dhcp integration_discovery|dhcp|-|-|câmeras Tapo — exige Camera Account criada no app do celular"
    "smartthings|casa|SmartThings|core|-|1|dhcp|user dhcp|user|application_credentials|-|aparelhos Samsung — OAuth, não token pessoal"

    # ── ferramentas ──────────────────────────────────────────────────────────
    "advanced_ssh|ferramentas|SSH & Web Terminal|community|DESCOBRIR_ssh|1|-|-|-|-|repo_terceiro|terminal com Docker API; 33,7% — repositório hassio-addons"
    "file_editor|ferramentas|File editor|oficial|core_configurator|1|-|-|-|-|-|editor ciente das entidades da instância — 63,6%"
    "samba|ferramentas|Samba share|oficial|core_samba|1|-|-|-|-|-|/config montável no Finder por smb:// — 26,8%"
    "systemmonitor|ferramentas|System Monitor|core|-|0|-|user|user|-|single_entry schema_flow|CPU, memória e disco do host; schema VAZIO — cria com {}"

    # ── casa_abhome ──────────────────────────────────────────────────────────
    "workday|casa_abhome|Workday|core|-|1|-|user|user|-|schema_flow|feriados nacionais e estaduais — o energia_br NÃO funciona sem isto"
    "energia_br|casa_abhome|Custo de energia (BR)|proprio|-|1|-|-|-|shelly workday samba|-|reproduz a fatura na vírgula; simula Convencional x Branca"
    "gas_br|casa_abhome|Custo de gás canalizado (BR)|proprio|-|1|-|-|-|samba|-|cascata por faixa, volume corrigido por P,T,Z e PCS"
    "agua_br|casa_abhome|Custo de água e esgoto (BR)|proprio|-|1|-|-|-|samba|-|simula a concessionária e compara com o rateio do condomínio"

    # ── extensoes ────────────────────────────────────────────────────────────
    "hacs|extensoes|HACS|custom|-|0|-|user|user|samba|repo_terceiro|só a instalação; nunca por perfil, nunca em --all"
)

# -----------------------------------------------------------------------------
# ITEM_META_DB — id|quality_scale|analytics_pct
# Informativo. Fica FORA do ITEM_DB de propósito: nada no caminho quente consome
# isto hoje, e inchar a tabela operacional é como se erra a ordem de um campo.
# quality_scale do manifest; adoção da telemetria oficial.
# -----------------------------------------------------------------------------
ITEM_META_DB=(
    "mqtt|platinum|48.6"
    "esphome|platinum|27.0"
    "shelly|platinum|25.0"
    "smartthings|bronze|-"
    "cast|-|50.9"
    "matter|-|39.8"
    "thread|-|37.1"
    "tuya|-|29.5"
    "file_editor|-|63.6"
    "samba|-|26.8"
    "advanced_ssh|-|33.7"
)

# -----------------------------------------------------------------------------
# VM_PROFILE_DB — id|rótulo|RAM MiB|vCPU|origem do número
#
# "derivado" é calculado pela sonda no momento da execução, e NUNCA pode ficar
# abaixo do vm_equilibrado — senão o perfil chamado "Recomendado" fica menor que
# o "Equilibrado" e o rótulo mente.
# Se a sonda falhar, o perfil NÃO é ofertado — nunca cai num valor inventado.
#
# Disco não é dimensão: o .vdi do HAOS traz 32 GiB de capacidade virtual.
# -----------------------------------------------------------------------------
VM_PROFILE_DB=(
    "vm_minimo|Mínimo|2048|2|documentação oficial do HA"
    "vm_equilibrado|Equilibrado|4096|2|medido — cobre os 2,5 GB de uma instância real"
    "vm_recomendado|Recomendado|derivado|derivado|calculado da sonda, com piso no equilibrado"
)

# -----------------------------------------------------------------------------
# HAOS_PROFILE_DB — id|rótulo|categorias.  A ESCADA SOMA. Só isto é escada.
# As demais categorias são ORTOGONAIS: marcam-se à parte, em qualquer degrau.
# -----------------------------------------------------------------------------
HAOS_PROFILE_DB=(
    "haos_vanilla|Vanilla|vanilla"
    "haos_conectado|Conectado|vanilla conectado"
    "haos_casa|Casa|vanilla conectado casa"
)

ORTOGONAL_DB=(ferramentas casa_abhome extensoes)

# -----------------------------------------------------------------------------
# NAO_APLICA_DB — id|motivo
#
# REGRA: preferir o oficial QUANDO O OFICIAL COBRE A NECESSIDADE.
# Não é "sem repositório de terceiro" — essa formulação não se sustentava, e era
# ela que criava a contradição com o advanced_ssh.
#
# Serve para o gerador de proposta não sugerir para sempre o que já foi
# decidido, e para registrar o MOTIVO — senão uma sessão futura "conserta" a
# ausência. Fica fora do ITEM_DB para não poluir o seletor.
# -----------------------------------------------------------------------------
NAO_APLICA_DB=(
    "raspberry_pi|não existe hardware Raspberry Pi numa VM em Mac"
    "rpi_power|mede a fonte do Raspberry Pi"
    "smartir|é pacote de dentro do HACS — a regra é não instalar nada de lá"
    "studio_code_server|file_editor e samba, ambos oficiais, cobrem edição"
    "core_ssh|oficial, mas NÃO cobre: o config.yaml não declara docker_api, e Protection mode só libera o que o app declara"
)
# <<< CATALOGO EMBUTIDO <<<

# ── acessores do catálogo ────────────────────────────────────────────────────
cat_rotulo() {
    local r id rot desc
    for r in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id rot desc <<< "$r"
        [ "$id" = "$1" ] && { printf '%s' "$rot"; return 0; }
    done
    printf '%s' "$1"
}
item_campo() {   # item_campo <id> <n>  — n é 1-based na ordem do schema
    local r campos
    for r in "${ITEM_DB[@]}"; do
        [ "${r%%|*}" = "$1" ] || continue
        IFS='|' read -r -a campos <<< "$r"
        printf '%s' "${campos[$(( $2 - 1 ))]}"
        return 0
    done
    return 1
}
tem_na_lista() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

# =============================================================================
# ARGUMENTOS
# =============================================================================
OP_PERFIL=""; OP_WITH=""; OP_VM_PERFIL=""; OP_VM_NOME="HomeAssistant"
OP_DRYRUN=0; OP_LIST=0; OP_NOINPUT=0; OP_FORCE=0
OP_QUIET=0; OP_VERBOSE=0; OP_ALL=0
OP_KEEP_IMAGE=0; OP_INSTALL_DEPS=0

# O help só promete o que EXISTE. As flags das fases futuras (--doctor,
# --uninstall, --self-update, --resume, --upgrade, --bridge, --json, `last`)
# entram AQUI no mesmo commit em que a implementação entra — o gate executa
# cada flag publicada e reprova a que responder "não implementado" (B-4).
uso() {
    cat <<'USO'
haos-install.sh — Home Assistant OS numa VM VirtualBox em Mac Apple Silicon

  bash haos-install.sh [opções]
  curl -fsSL <raw-url> | bash -s -- [opções]

SELEÇÃO
  --profile <id>     haos_vanilla | haos_conectado | haos_casa
  --with a,b,c       extras: ferramentas, casa_abhome, extensoes
  -a, --all          haos_casa + todos os extras (exceto o que exige opt-in)

VM
  --vm-profile <id>  vm_minimo | vm_equilibrado | vm_recomendado
  --vm-name <nome>   padrão: HomeAssistant

NÃO INSTALAM NADA
  -n, --dry-run      imprime o plano e sai
  --list             lista o catálogo e sai
  --version          versão do instalador e a referência de compatibilidade
  -h, --help         esta ajuda

OUTRAS
  --keep-image       preserva o .zip baixado da imagem do HAOS
  -v, --verbose      mostra a saída crua de cada ferramenta
  -q, --quiet        suprime a saída normal
  --no-input         não pergunta nada; falha se faltar dado obrigatório
  -f, --force        refaz artefato já presente. NÃO pula portão nem hash.
  --install-deps     instala pré-requisitos ausentes sem perguntar (VirtualBox)

Ambiente: HAOS_LANG=pt|en · NO_COLOR
USO
}

versao() {
    printf 'haos-install.sh %s\n' "$HAOS_INSTALL_VERSION"
    printf 'contrato verificado contra Home Assistant Core %s · HAOS %s\n' "$HAOS_REF_CORE" "$HAOS_REF_OS"
    printf 'https://github.com/aleonnet/haos-mac-mini · MIT\n'
}

# Flag de valor valida o shape NA HORA: sem isto, `--profile --help` engole a
# flag seguinte e o erro aparece longe da causa (achado 7 do gap analysis; o
# AtlasFile faz o mesmo no parser dele).
exige_valor() { # <flag> <valor?>
    case "${2:-}" in ''|-*) morrer "$E_USO" "$(msg flag_sem_valor "$1")" ;; esac
}

ler_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)      exige_valor --profile "${2:-}";    OP_PERFIL="$2"; shift ;;
            --profile=*)    exige_valor --profile "${1#*=}";   OP_PERFIL="${1#*=}" ;;
            --with)         exige_valor --with "${2:-}";       OP_WITH="$2"; shift ;;
            --with=*)       exige_valor --with "${1#*=}";      OP_WITH="${1#*=}" ;;
            --vm-profile)   exige_valor --vm-profile "${2:-}"; OP_VM_PERFIL="$2"; shift ;;
            --vm-profile=*) exige_valor --vm-profile "${1#*=}"; OP_VM_PERFIL="${1#*=}" ;;
            --vm-name)      exige_valor --vm-name "${2:-}";    OP_VM_NOME="$2"; shift ;;
            --vm-name=*)    exige_valor --vm-name "${1#*=}";   OP_VM_NOME="${1#*=}" ;;
            -a|--all)       OP_ALL=1 ;;
            -n|--dry-run)   OP_DRYRUN=1 ;;
            --list)         OP_LIST=1 ;;
            --no-input)     OP_NOINPUT=1 ;;
            -f|--force)     OP_FORCE=1 ;;
            -q|--quiet)     OP_QUIET=1 ;;
            -v|--verbose)   OP_VERBOSE=1 ;;
            --keep-image)   OP_KEEP_IMAGE=1 ;;
            --install-deps) OP_INSTALL_DEPS=1 ;;
            --version)      versao; exit 0 ;;
            -h|--help)      uso; exit 0 ;;
            *)              ha_err "$(msg opcao_desconhecida "$1")"; printf '\n'; uso >&2; exit "$E_USO" ;;
        esac
        shift
    done
}

# =============================================================================
# --list
# =============================================================================
listar() {
    printf '%s\n\n' "$(msg cabecalho)"
    printf 'PISO — o que a instalação já cria sozinha (%s)\n' \
        "$(( ${#DEFAULT_CONFIG_DB[@]} + ${#HAOS_INTRINSIC_DB[@]} + ${#ONBOARDING_DB[@]} ))"
    printf '  default_config (%s): %s\n' "${#DEFAULT_CONFIG_DB[@]}" "${DEFAULT_CONFIG_DB[*]}" | fold -s -w 78 | sed '2,$s/^/    /'
    local r id d
    printf '  intrínsecos:'; for r in "${HAOS_INTRINSIC_DB[@]}"; do printf ' %s' "${r%%|*}"; done; printf '\n'
    printf '  onboarding: ';  for r in "${ONBOARDING_DB[@]}";     do printf ' %s' "${r%%|*}"; done; printf '\n'

    local c cid crot cdesc
    for c in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r cid crot cdesc <<< "$c"
        [ "$cid" = "vanilla" ] && continue
        printf '\n%s — %s\n' "$crot" "$cdesc"
        local it iid icat irot iorigem islug ipadrao
        for it in "${ITEM_DB[@]}"; do
            IFS='|' read -r iid icat irot iorigem islug ipadrao _ <<< "$it"
            [ "$icat" = "$cid" ] || continue
            local marca="  "; [ "$ipadrao" = "1" ] && marca="* "
            printf '  %s%-26s %s\n' "$marca" "$iid" "$irot"
        done
    done
    printf '\nDegraus (somam): '; for r in "${HAOS_PROFILE_DB[@]}"; do printf '%s ' "${r%%|*}"; done
    printf '\nExtras (à parte): %s\n' "${ORTOGONAL_DB[*]}"
    printf '\n* = pré-marcado quando a categoria é escolhida\n'
}

# =============================================================================
# F1 — PRÉ-VOO. Só lê. Nada é escrito nesta fase.
# =============================================================================
PROBE=""
sonda() { PROBE="$(probe_all 2>/dev/null || true)"; }
p_get() { printf '%s\n' "$PROBE" | awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); print; exit}'; }

# Sonda embutida — mesma lógica de lib/probe-host.sh, só dados.
probe_all() {
    local total pagesize vs free active inactive spec wired comp purge used avail
    printf 'host.model=%s\n' "$(sysctl -n hw.model 2>/dev/null || true)"
    printf 'host.cpu=%s\n'   "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    printf 'host.arch=%s\n'  "$(uname -m)"
    printf 'host.os=%s\n'    "$(uname -s)"
    printf 'host.macos=%s\n' "$(sw_vers -productVersion 2>/dev/null || true)"

    total="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    pagesize="$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
    printf 'mem.total_mib=%s\n' $(( total / 1048576 ))
    vs="$(vm_stat 2>/dev/null || true)"
    if [ -n "$vs" ]; then
        _pg() { printf '%s\n' "$vs" | awk -v pat="$1" '$0 ~ pat {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.?$/){gsub(/\./,"",$i); print $i; exit}}'; }
        free="$(_pg 'Pages free')";        free="${free:-0}"
        inactive="$(_pg 'Pages inactive')"; inactive="${inactive:-0}"
        spec="$(_pg 'Pages speculative')";  spec="${spec:-0}"
        purge="$(_pg 'Pages purgeable')";   purge="${purge:-0}"
        avail=$(( (free + inactive + spec + purge) * pagesize ))
        printf 'mem.available_mib=%s\n' $(( avail / 1048576 ))
    fi

    printf 'cpu.performance=%s\n' "$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 0)"

    local vmdir; vmdir="$HOME/VirtualBox VMs"; [ -d "$vmdir" ] || vmdir="$HOME"
    printf 'disk.path=%s\n' "$vmdir"
    printf 'disk.available_mib=%s\n' "$(( $(df -k "$vmdir" 2>/dev/null | awk 'NR==2{print $4}' || echo 0) / 1024 ))"

    if command -v VBoxManage >/dev/null 2>&1; then
        printf 'vbox.present=1\n'
        printf 'vbox.version=%s\n' "$(VBoxManage --version 2>/dev/null | tr -d '\r')"
    else
        printf 'vbox.present=0\n'
    fi

    command -v python3 >/dev/null 2>&1 && printf 'python3.present=1\n' || printf 'python3.present=0\n'

    local n=0 port dev ip status media wired_f
    while IFS= read -r line; do
        case "$line" in
            "Hardware Port: "*) port="${line#Hardware Port: }" ;;
            "Device: "*)
                dev="${line#Device: }"
                ip="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
                status="$(ifconfig "$dev" 2>/dev/null | awk '/status:/{print $2}')"
                media="$(ifconfig "$dev" 2>/dev/null | awk '/media:/{print; exit}')"
                wired_f=0
                case "$media" in *baseT*|*10Gbase*) wired_f=1 ;; esac
                [ "$port" = "Wi-Fi" ] && wired_f=0
                if [ -n "$ip" ] || [ "${status:-}" = "active" ]; then
                    n=$(( n + 1 ))
                    printf 'net.%s.device=%s\n' "$n" "$dev"
                    printf 'net.%s.port=%s\n'   "$n" "$port"
                    printf 'net.%s.ip=%s\n'     "$n" "${ip:-}"
                    printf 'net.%s.wired=%s\n'  "$n" "$wired_f"
                fi ;;
        esac
    done <<EOF
$(networksetup -listallhardwareports 2>/dev/null || true)
EOF
    printf 'net.count=%s\n' "$n"
}

TEM_CABEADA=0
pre_voo() {
    ha_fase "$(msg preflight)"
    sonda

    # ── portões duros: impossibilidade de plataforma ──────────────────────────
    local os arch
    os="$(p_get host.os)"; arch="$(p_get host.arch)"
    [ "$os" = "Darwin" ]  || portao "$E_VALID" "$(msg so_macos "$os")"
    [ "$arch" = "arm64" ] || portao "$E_VALID" "$(msg so_apple_silicon "$arch")"
    ha_ok "$(msg maquina): $(p_get host.model) ${HA_G_SEP} $(p_get host.cpu) ${HA_G_SEP} macOS $(p_get host.macos)"

    if [ "$(p_get vbox.present)" != "1" ]; then
        # Conduz, não delega: baixa da Oracle, confere o hash e instala por
        # installer(8). Uma senha, no terminal, pedida pelo sudo.
        if [ "$OP_DRYRUN" = "1" ]; then
            portao "$E_DEP" "$(msg sem_vbox)"
        else
            local rc_vb=0
            garantir_virtualbox || rc_vb=$?
            if [ "$rc_vb" != "0" ] && [ "$rc_vb" != "100" ]; then
                exit "$E_DEP"
            fi
            sonda   # re-sonda: a máquina mudou
        fi
    fi
    if [ "$(p_get vbox.present)" = "1" ]; then
        local vv maj min
        vv="$(p_get vbox.version)"; maj="${vv%%.*}"; min="${vv#*.}"; min="${min%%.*}"
        if [ "${maj:-0}" -lt 7 ] || { [ "${maj:-0}" = "7" ] && [ "${min:-0}" -lt 1 ]; }; then
            portao "$E_DEP" "$(msg vbox_antigo "$vv")"
        else
            ha_ok "$(msg vbox_versao "$vv")"
        fi
    fi

    # python3: dependência REAL. Instalar app exige o comando WebSocket
    # supervisor/api, e bash não fala WebSocket. Descobrir isso na fase de apps,
    # depois da VM criada, seria descobrir tarde.
    if [ "$(p_get python3.present)" != "1" ]; then
        portao "$E_DEP" "$(msg sem_python) $(msg sem_python_como)"
    else
        ha_ok "$(msg python3_versao "$(python3 -V 2>&1 | awk '{print $2}')")"
    fi

    local livre; livre="$(p_get disk.available_mib)"
    local minimo=12000
    if [ "${livre:-0}" -ge "$minimo" ]; then ha_ok "$(msg disco): ${livre} MiB"
    else portao "$E_VALID" "$(msg disco_curto "$(p_get disk.path)" "$livre" "$minimo")"; fi

    # ── portões suaves: avisam, não abortam ──────────────────────────────────
    local n i
    n="$(p_get net.count)"; [ "${n:-0}" -ge 1 ] || portao "$E_VALID" "$(msg sem_interface)"
    i=1
    while [ "$i" -le "${n:-0}" ]; do
        [ "$(p_get "net.$i.wired")" = "1" ] && TEM_CABEADA=1
        i=$(( i + 1 ))
    done
    if [ "$TEM_CABEADA" = "1" ]; then
        ha_ok "$(msg rede): $(p_get net.1.port) ($(msg cabeada))"
    else
        # Aviso, NÃO portão. A doc oficial do HA aceita escolher o adaptador
        # Wi-Fi, e nenhum MacBook tem porta Ethernet desde 2016: abortar aqui
        # recusaria a maior parte dos Macs. A prova é empírica, na F5.
        ha_warn "$(msg aviso_wifi)"
    fi
}

# =============================================================================
# F2 — SELEÇÃO
# =============================================================================
SEL_DEGRAU=""; SEL_EXTRAS=""; SEL_VM=""; SEL_ITENS=""

perfil_valido() {
    local r
    for r in "${HAOS_PROFILE_DB[@]}"; do [ "${r%%|*}" = "$1" ] && return 0; done
    return 1
}
degrau_categorias() {
    local r id rot cats
    for r in "${HAOS_PROFILE_DB[@]}"; do
        IFS='|' read -r id rot cats <<< "$r"
        [ "$id" = "$1" ] && { printf '%s' "$cats"; return 0; }
    done
    return 1
}

# vm_recomendado deriva do TOTAL, não do disponível: o disponível varia entre
# execuções na mesma máquina, e derivar dele faria o perfil "Recomendado" ficar
# menor que o "Equilibrado" — o rótulo mentiria. Piso no equilibrado.
vm_derivado_ram() {
    local total metade=4096
    total="$(p_get mem.total_mib)"
    [ "${total:-0}" -gt 0 ] && metade=$(( total / 2 ))
    [ "$metade" -gt 8192 ] && metade=8192
    [ "$metade" -lt 4096 ] && metade=4096
    printf '%s' "$metade"
}
vm_derivado_cpu() {
    local p; p="$(p_get cpu.performance)"
    [ "${p:-0}" -lt 2 ] && p=2
    [ "${p:-2}" -gt 4 ] && p=4
    printf '%s' "$p"
}

resolver_selecao() {
    ha_fase "$(msg selecao)"

    if [ "$OP_ALL" = "1" ]; then
        SEL_DEGRAU="haos_casa"; SEL_EXTRAS="ferramentas casa_abhome"
        # `extensoes` (HACS) fica FORA do --all de propósito: é código de fora
        # do canal oficial, e opt-in nominal é o certo para isso.
    elif [ -n "$OP_PERFIL" ]; then
        perfil_valido "$OP_PERFIL" || morrer "$E_USO" "perfil desconhecido: $OP_PERFIL"
        SEL_DEGRAU="$OP_PERFIL"
    elif tem_tty && [ "$OP_NOINPUT" != "1" ]; then
        SEL_DEGRAU="haos_casa"   # o seletor interativo entra aqui na próxima fase
    else
        ha_err "$(msg sem_tty_titulo)"
        printf '%s\n' "$(msg sem_tty_como)" >&2
        printf '  curl -fsSL %s | bash -s -- --profile haos_casa\n' "$HAOS_RAW_URL" >&2
        exit "$E_USO"
    fi

    [ -n "$OP_WITH" ] && SEL_EXTRAS="$(printf '%s' "$OP_WITH" | tr ',' ' ')"
    local e
    for e in $SEL_EXTRAS; do
        tem_na_lista "$e" "${ORTOGONAL_DB[*]}" || morrer "$E_USO" "extra desconhecido: $e"
    done

    SEL_VM="${OP_VM_PERFIL:-vm_equilibrado}"
    local r vid
    local achou=0
    for r in "${VM_PROFILE_DB[@]}"; do [ "${r%%|*}" = "$SEL_VM" ] && achou=1; done
    [ "$achou" = "1" ] || morrer "$E_USO" "perfil de VM desconhecido: $SEL_VM"

    # itens: os de padrao=1 das categorias escolhidas
    local cats; cats="$(degrau_categorias "$SEL_DEGRAU") $SEL_EXTRAS"
    local it iid icat irot iorigem islug ipadrao
    for it in "${ITEM_DB[@]}"; do
        IFS='|' read -r iid icat irot iorigem islug ipadrao _ <<< "$it"
        tem_na_lista "$icat" "$cats" || continue
        [ "$ipadrao" = "1" ] && SEL_ITENS="$SEL_ITENS $iid"
    done
    ha_ok "$(msg degrau): $(cat_rotulo "${SEL_DEGRAU#haos_}") ${HA_G_SEP} $(msg ortogonais): ${SEL_EXTRAS:--}"
}

plano() {
    ha_fase "$(msg plano)"
    local ram cpu r id rot rm cp orig
    for r in "${VM_PROFILE_DB[@]}"; do
        IFS='|' read -r id rot rm cp orig <<< "$r"
        [ "$id" = "$SEL_VM" ] || continue
        if [ "$rm" = "derivado" ]; then ram="$(vm_derivado_ram)"; cpu="$(vm_derivado_cpu)"
        else ram="$rm"; cpu="$cp"; fi
    done

    printf '  %-14s %s\n' "$(msg perfil_vm):" "$SEL_VM ${HA_G_DASH} ${ram} MiB RAM ${HA_G_SEP} ${cpu} vCPU"
    printf '  %-14s %s\n' "VM:" "$OP_VM_NOME"
    printf '  %-14s %s\n' "$(msg degrau):" "$SEL_DEGRAU"
    [ -n "$SEL_EXTRAS" ] && printf '  %-14s %s\n' "$(msg ortogonais):" "$SEL_EXTRAS"

    local disp; disp="$(p_get mem.available_mib)"
    if [ "${disp:-0}" -lt "${ram:-0}" ]; then ha_warn "$(msg aviso_ram "$disp" "$ram")"; fi

    # O piso vem de qualquer jeito — dizer só "0 itens" seria enganoso.
    printf '\n  %s\n' "$(msg piso_sempre "$(( ${#DEFAULT_CONFIG_DB[@]} + ${#HAOS_INTRINSIC_DB[@]} + ${#ONBOARDING_DB[@]} ))")"

    local n=0 it
    printf '\n'
    for it in $SEL_ITENS; do
        n=$(( n + 1 ))
        printf '    %-26s %s\n' "$it" "$(item_campo "$it" 3)"
    done
    if [ "$n" = "0" ]; then
        printf '    %s\n' "$(msg nada_alem_do_piso)"
    else
        printf '\n  %s %s\n' "$n" "$(msg itens)"
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    ler_args "$@"

    # `--list | head` fecha o cano; SIGPIPE com pipefail viraria erro do script
    [ "$OP_LIST" = "1" ] && { trap - PIPE; listar 2>/dev/null || true; exit 0; }

    # A partir daqui a execução conta como execução: o limpar() espelha o
    # last-run mesmo numa morte no meio — exceto em dry-run, que não escreve
    # NADA (cerca de snapshot no portão).
    MAIN_INICIADO=1
    if [ "$OP_DRYRUN" = "1" ]; then HA_BAR_TOTAL=3; else HA_BAR_TOTAL=4; fi

    # O logo só aparece quando há terminal e o usuário não pediu silêncio.
    # Em log, CI ou --quiet, um cabeçalho de uma linha. A animação nunca é
    # informação: tudo que ela mostra também está no texto.
    if [ "$OP_QUIET" != "1" ]; then
        if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
            ha_banner "Home Assistant OS" "$(msg subtitulo) ${HA_G_SEP} v${HAOS_INSTALL_VERSION}"
        else
            printf '\n%s v%s\n' "$(msg cabecalho)" "$HAOS_INSTALL_VERSION"
        fi
    fi

    pre_voo
    resolver_selecao
    plano

    if [ "$OP_DRYRUN" = "1" ]; then
        printf '\n'
        if [ "$PORTOES_ABERTOS" -gt 0 ]; then
            ha_warn "$(msg portoes_pendentes "$PORTOES_ABERTOS")"
        fi
        ha_info "$(msg nada_escrito)"
        exit 0
    fi

    if [ "$OP_NOINPUT" != "1" ]; then
        perguntar "$(msg confirmar)" || { ha_info "$(msg cancelado)"; exit "$E_CANCELADO"; }
    fi

    local rc_img=0
    fase_imagem || rc_img=$?
    [ "$rc_img" = "0" ] || [ "$rc_img" = "100" ] || exit "$E_VALID"

    ha_fase "$(msg fase_vm)"
    morrer "$E_VALID" "$(msg nao_implementado "$HAOS_INSTALL_VERSION")"
}

# ── guarda de biblioteca ─────────────────────────────────────────────────────
# `HAOS_INSTALL_LIB=1 source haos-install.sh` para AQUI: a bancada de teste
# alcança as funções sem executar nada. O `exit` de fallback existe porque sob
# `curl | bash` não há função de onde retornar. O trap vem DEPOIS da guarda —
# um trap de EXIT instalado no source vazaria para o shell da bancada (B-7).
MAIN_INICIADO=0
if [ -n "${HAOS_INSTALL_LIB:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

trap limpar EXIT INT TERM
main "$@"
