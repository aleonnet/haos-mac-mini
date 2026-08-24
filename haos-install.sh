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
limpar() {
    local rc=$?
    local f
    for f in "${TMPFILES[@]:-}"; do [ -n "$f" ] && rm -rf "$f" 2>/dev/null || true; done
    if declare -F ha_show_cursor >/dev/null 2>&1; then ha_show_cursor; else
        [ -t 1 ] && tput cnorm 2>/dev/null || true
    fi
    if [ "$rc" != "0" ] && [ -n "$FASE_ATUAL" ]; then
        printf '\n[!] interrompido na fase %s. Nada além dela foi alterado.\n' "$FASE_ATUAL" >&2
        printf '    Para desfazer: %s --uninstall\n' "${0##*/}" >&2
    fi
    exit "$rc"
}
trap limpar EXIT INT TERM

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
"sem_vbox|VirtualBox não encontrado. Instale antes de continuar:|VirtualBox not found. Install it before continuing:"
"sem_vbox_como|  brew install --cask virtualbox|  brew install --cask virtualbox"
"sem_vbox_porque|O instalador não instala o VirtualBox: o cask pede senha de administrador e aprovação de extensão de sistema, que não se faz por script sem avisar.|This installer does not install VirtualBox: the cask needs an admin password and a system extension approval, which no script should do silently."
"vbox_versao|VirtualBox %s|VirtualBox %s"
"vbox_antigo|VirtualBox %s é anterior à 7.1, que trouxe host ARM e --platform-architecture. Atualize.|VirtualBox %s predates 7.1, which introduced ARM hosts and --platform-architecture. Please upgrade."
"sem_python|python3 não encontrado. É dependência real: instalar app no Home Assistant exige o comando WebSocket supervisor/api, e bash não fala WebSocket.|python3 not found. This is a hard dependency: installing add-ons requires the supervisor/api WebSocket command, and bash cannot speak WebSocket."
"sem_python_como|  Instale as Command Line Tools:  xcode-select --install|  Install the Command Line Tools:  xcode-select --install"
"disco_curto|Espaço livre insuficiente em %s: %s MiB. A imagem do HAOS precisa de pelo menos %s MiB.|Not enough free space on %s: %s MiB. The HAOS image needs at least %s MiB."
"sem_rede|Sem acesso à internet. O primeiro boot do HAOS baixa o Core, e os fluxos de nuvem falham sem rede — e falham de um jeito indistinguível de credencial errada.|No internet access. The first HAOS boot downloads Core, and cloud flows fail without network — in a way indistinguishable from a wrong credential."
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
"piso_sempre|Piso: %s componentes que a própria instalação cria — não são escolha.|Floor: %s components the installation creates by itself — not a choice."
"nada_alem_do_piso|(nada além do piso; os itens deste degrau são opt-in)|(nothing beyond the floor; this tier is opt-in)"
"nao_implementado|As fases de execução ainda não estão implementadas nesta versão (%s).|Execution phases are not implemented yet in this version (%s)."
)

# ── saída ────────────────────────────────────────────────────────────────────
# Prefixos textuais são o contrato. Cor é enfeite: some sem TTY e com NO_COLOR,
# e nenhuma informação vive só na cor.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_AZUL=$'\033[38;5;39m'; C_VERDE=$'\033[38;5;42m'; C_AMBAR=$'\033[38;5;214m'
    C_VERM=$'\033[38;5;203m'; C_FRACO=$'\033[38;5;245m'; C_ZERO=$'\033[0m'
else
    C_AZUL=''; C_VERDE=''; C_AMBAR=''; C_VERM=''; C_FRACO=''; C_ZERO=''
fi

ok()    { printf '%s[OK]%s     %s\n'  "$C_VERDE" "$C_ZERO" "$*"; }
info()  { printf '%s[*]%s      %s\n'  "$C_FRACO" "$C_ZERO" "$*"; }
aviso() { printf '%s[AVISO]%s  %s\n'  "$C_AMBAR" "$C_ZERO" "$*"; }
erro()  { printf '%s[ERRO]%s   %s\n'  "$C_VERM"  "$C_ZERO" "$*" >&2; }
fase()  { FASE_ATUAL="$1"; printf '\n%s── %s %s%s\n' "$C_AZUL" "$1" "$(printf '─%.0s' $(seq 1 $((60 - ${#1}))))" "$C_ZERO"; }

morrer() { local code="$1"; shift; erro "$*"; exit "$code"; }

# Em --dry-run, portão duro não aborta: reporta e segue, para o operador
# conseguir VER o plano numa máquina que ainda não tem tudo. Achado R5 da banca:
# o único modo que existe para inspecionar a ferramenta não pode exigir que a
# máquina já esteja pronta.
PORTOES_ABERTOS=0
portao() {
    local code="$1"; shift
    if [ "$OP_DRYRUN" = "1" ]; then
        aviso "$*"
        PORTOES_ABERTOS=$(( PORTOES_ABERTOS + 1 ))
        return 0
    fi
    erro "$*"; exit "$code"
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

# ── download ─────────────────────────────────────────────────────────────────
baixador() {
    if command -v curl >/dev/null 2>&1; then printf 'curl'; return 0; fi
    if command -v wget >/dev/null 2>&1; then printf 'wget'; return 0; fi
    return 1
}

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
OP_BRIDGE=""; OP_DRYRUN=0; OP_LIST=0; OP_NOINPUT=0; OP_FORCE=0
OP_QUIET=0; OP_VERBOSE=0; OP_JSON=0; OP_ALL=0
OP_MODO=""            # doctor | uninstall | upgrade | upgrade-only | self-update | resume
OP_CONFIRM=""; OP_KEEP_IMAGE=0

uso() {
    cat <<'USO'
haos-install.sh — Home Assistant OS numa VM VirtualBox em Mac Apple Silicon

  bash haos-install.sh [opções]
  curl -fsSL <raw-url> | bash -s -- [opções]

SELEÇÃO
  --profile <id>     haos_vanilla | haos_conectado | haos_casa | last
  --with a,b,c       extras: ferramentas, casa_abhome, extensoes
  -a, --all          haos_casa + todos os extras (exceto o que exige opt-in)

VM
  --vm-profile <id>  vm_minimo | vm_equilibrado | vm_recomendado
  --vm-name <nome>   padrão: HomeAssistant
  --bridge <nome>    interface de bridge; padrão é a cabeada

NÃO INSTALAM NADA
  -n, --dry-run      imprime o plano e sai
  --list             lista o catálogo e sai
  --doctor           diagnóstico; nada é alterado
  --version          versão do instalador e a referência de compatibilidade
  -h, --help         esta ajuda

ATUALIZAÇÃO
  --upgrade          aplica atualizações dos artefatos que o instalador escreve
  --upgrade-only     só atualiza o que existe, não instala nada novo, e sai
  --self-update      atualiza este script

REMOÇÃO
  --uninstall        desfaz a instalação
  --confirm=<nome>   obrigatório para --uninstall sem terminal
  --keep-image       preserva o .vdi baixado

OUTRAS
  --resume           retoma da fase onde parou
  -v, --verbose      saída completa
  -q, --quiet        suprime a saída normal
  --json             saída legível por máquina
  --no-input         não pergunta nada; falha se faltar dado obrigatório
  -f, --force        reinstala item já presente. NÃO pula portão nem hash.

Ambiente: HAOS_LANG=pt|en · NO_COLOR

--upgrade NUNCA toca versão de Core, HAOS ou app: isso é do Supervisor.
USO
}

versao() {
    printf 'haos-install.sh %s\n' "$HAOS_INSTALL_VERSION"
    printf 'contrato verificado contra Home Assistant Core %s · HAOS %s\n' "$HAOS_REF_CORE" "$HAOS_REF_OS"
    printf 'https://github.com/aleonnet/haos-mac-mini · MIT\n'
}

modo_unico() {
    [ -z "$OP_MODO" ] || morrer "$E_USO" "--$1 não combina com --$OP_MODO"
    OP_MODO="$1"
}

ler_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)      OP_PERFIL="${2:-}"; shift ;;
            --profile=*)    OP_PERFIL="${1#*=}" ;;
            --with)         OP_WITH="${2:-}"; shift ;;
            --with=*)       OP_WITH="${1#*=}" ;;
            --vm-profile)   OP_VM_PERFIL="${2:-}"; shift ;;
            --vm-profile=*) OP_VM_PERFIL="${1#*=}" ;;
            --vm-name)      OP_VM_NOME="${2:-}"; shift ;;
            --vm-name=*)    OP_VM_NOME="${1#*=}" ;;
            --bridge)       OP_BRIDGE="${2:-}"; shift ;;
            --bridge=*)     OP_BRIDGE="${1#*=}" ;;
            --confirm=*)    OP_CONFIRM="${1#*=}" ;;
            -a|--all)       OP_ALL=1 ;;
            -n|--dry-run)   OP_DRYRUN=1 ;;
            --list)         OP_LIST=1 ;;
            --no-input)     OP_NOINPUT=1 ;;
            -f|--force)     OP_FORCE=1 ;;
            -q|--quiet)     OP_QUIET=1 ;;
            -v|--verbose)   OP_VERBOSE=1 ;;
            --json)         OP_JSON=1 ;;
            --keep-image)   OP_KEEP_IMAGE=1 ;;
            --doctor)       modo_unico doctor ;;
            --uninstall)    modo_unico uninstall ;;
            --upgrade)      modo_unico upgrade ;;
            --upgrade-only) modo_unico upgrade-only ;;
            --self-update)  modo_unico self-update ;;
            --resume)       modo_unico resume ;;
            --version)      versao; exit 0 ;;
            -h|--help)      uso; exit 0 ;;
            *)              erro "opção desconhecida: $1"; printf '\n'; uso >&2; exit "$E_USO" ;;
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
    fase "$(msg preflight)"
    sonda

    # ── portões duros: impossibilidade de plataforma ──────────────────────────
    local os arch
    os="$(p_get host.os)"; arch="$(p_get host.arch)"
    [ "$os" = "Darwin" ]  || portao "$E_VALID" "$(msg so_macos "$os")"
    [ "$arch" = "arm64" ] || portao "$E_VALID" "$(msg so_apple_silicon "$arch")"
    ok "$(msg maquina): $(p_get host.model) · $(p_get host.cpu) · macOS $(p_get host.macos)"

    if [ "$(p_get vbox.present)" != "1" ]; then
        portao "$E_DEP" "$(msg sem_vbox) $(msg sem_vbox_como)"
        [ "$OP_DRYRUN" = "1" ] || printf '%s\n' "$(msg sem_vbox_porque)" >&2
    else
        local vv maj min
        vv="$(p_get vbox.version)"; maj="${vv%%.*}"; min="${vv#*.}"; min="${min%%.*}"
        if [ "${maj:-0}" -lt 7 ] || { [ "${maj:-0}" = "7" ] && [ "${min:-0}" -lt 1 ]; }; then
            portao "$E_DEP" "$(msg vbox_antigo "$vv")"
        else
            ok "$(msg vbox_versao "$vv")"
        fi
    fi

    # python3: dependência REAL. Instalar app exige o comando WebSocket
    # supervisor/api, e bash não fala WebSocket. Descobrir isso na fase de apps,
    # depois da VM criada, seria descobrir tarde.
    if [ "$(p_get python3.present)" != "1" ]; then
        portao "$E_DEP" "$(msg sem_python) $(msg sem_python_como)"
    else
        ok "python3 $(python3 -V 2>&1 | awk '{print $2}')"
    fi

    local livre; livre="$(p_get disk.available_mib)"
    local minimo=12000
    if [ "${livre:-0}" -ge "$minimo" ]; then ok "$(msg disco): ${livre} MiB"
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
        ok "$(msg rede): $(p_get net.1.port) ($(msg cabeada))"
    else
        # Aviso, NÃO portão. A doc oficial do HA aceita escolher o adaptador
        # Wi-Fi, e nenhum MacBook tem porta Ethernet desde 2016: abortar aqui
        # recusaria a maior parte dos Macs. A prova é empírica, na F5.
        aviso "$(msg aviso_wifi)"
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
    fase "$(msg selecao)"

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
        erro "$(msg sem_tty_titulo)"
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
    ok "$(msg degrau): $(cat_rotulo "${SEL_DEGRAU#haos_}") · $(msg ortogonais): ${SEL_EXTRAS:--}"
}

plano() {
    fase "$(msg plano)"
    local ram cpu r id rot rm cp orig
    for r in "${VM_PROFILE_DB[@]}"; do
        IFS='|' read -r id rot rm cp orig <<< "$r"
        [ "$id" = "$SEL_VM" ] || continue
        if [ "$rm" = "derivado" ]; then ram="$(vm_derivado_ram)"; cpu="$(vm_derivado_cpu)"
        else ram="$rm"; cpu="$cp"; fi
    done

    printf '  %-14s %s\n' "$(msg perfil_vm):" "$SEL_VM — ${ram} MiB RAM · ${cpu} vCPU"
    printf '  %-14s %s\n' "VM:" "$OP_VM_NOME"
    printf '  %-14s %s\n' "$(msg degrau):" "$SEL_DEGRAU"
    [ -n "$SEL_EXTRAS" ] && printf '  %-14s %s\n' "$(msg ortogonais):" "$SEL_EXTRAS"

    local disp; disp="$(p_get mem.available_mib)"
    if [ "${disp:-0}" -lt "${ram:-0}" ]; then aviso "$(msg aviso_ram "$disp" "$ram")"; fi

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

    case "$OP_MODO" in
        doctor|uninstall|upgrade|upgrade-only|self-update|resume)
            morrer "$E_VALID" "$(msg nao_implementado "$HAOS_INSTALL_VERSION")" ;;
    esac

    [ "$OP_QUIET" = "1" ] || printf '\n%s %s\n' "$(msg cabecalho)" "v$HAOS_INSTALL_VERSION"

    pre_voo
    resolver_selecao
    plano

    if [ "$OP_DRYRUN" = "1" ]; then
        printf '\n'
        if [ "$PORTOES_ABERTOS" -gt 0 ]; then
            aviso "$(msg portoes_pendentes "$PORTOES_ABERTOS")"
        fi
        info "$(msg nada_escrito)"
        exit 0
    fi

    if [ "$OP_NOINPUT" != "1" ]; then
        perguntar "$(msg confirmar)" || { info "$(msg cancelado)"; exit "$E_CANCELADO"; }
    fi

    fase "F3"
    morrer "$E_VALID" "$(msg nao_implementado "$HAOS_INSTALL_VERSION")"
}

main "$@"
