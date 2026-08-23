# =============================================================================
# catalog.bash — FONTE DE VERDADE do catálogo do instalador HAOS.
#
# O haos-install.sh é autocontido: distribuído por `curl | bash`, ele embute
# uma cópia destas tabelas. Este arquivo existe para que a cópia possa ser
# CONFERIDA — o CI compara o que está no script com o que está aqui, e deriva
# vira erro detectável em vez de bug silencioso.
#
# Sintaxe: fragmento bash, mesmo padrão do mac_env_install.sh. Sem parser,
# sem formato inventado. `source` este arquivo e as tabelas estão na mão.
#
# Verificado em 2026-08-23 contra:
#   Home Assistant Core 2026.8.3 · HAOS 18.2 · VirtualBox 7.2.16
#   doc oficial de default_config · analytics.home-assistant.io (532.394 bases)
#   config_entries.py (SOURCE_* — 18 constantes)
# =============================================================================

# -----------------------------------------------------------------------------
# CATEGORY_DB — id|rótulo|descrição
# -----------------------------------------------------------------------------
CATEGORY_DB=(
    "vanilla|Vanilla|piso do produto — o que o HAOS instala sozinho; remover é opção, não escolha"
    "consenso|Consenso|acima de 75% de adoção na telemetria oficial e ausentes de fábrica"
    "conectado|Conectado|faixa de 27% a 51% de adoção — protocolos e ecossistemas"
    "casa|Casa|dispositivos desta instalação"
    "ferramentas|Ferramentas|apps oficiais de manutenção do HAOS"
    "custos|Custos de utilidades|packages de energia, gás e água com regras brasileiras"
    "cameras|Câmeras|extras das Tapo C210"
    "extensoes|Extensões de terceiros|HACS — só a instalação, nada de dentro dele"
)

# -----------------------------------------------------------------------------
# VANILLA_DB — o que o HAOS instala sozinho. NÃO é escolha: é o piso.
# Os 24 do default_config conferidos na DOC OFICIAL (a doc lista 3 a mais que o
# manifest: backup, config e image_upload — dependências transitivas), mais os
# três que nascem com source system/onboarding numa instalação real.
# -----------------------------------------------------------------------------
VANILLA_DB=(
    assist_pipeline backup bluetooth cloud config conversation dhcp
    energy file go2rtc history homeassistant_alerts image_upload
    logbook media_source mobile_app my ssdp stream sun
    usage_prediction usb webhook zeroconf
    hassio analytics met
)

# -----------------------------------------------------------------------------
# ITEM_DB — id|categoria|rótulo|padrão|origem|source|descrição
#
#   padrão : 1 marcado · 0 só por escolha explícita · cond avaliado em runtime
#   origem : core    = homeassistant/components/
#            oficial = home-assistant/addons
#            custom  = fora dos dois
#            proprio = deste projeto
#   source : valor de config_entries.py que a entry deve ter DEPOIS de criada.
#            É CERCA, não rótulo: cria, lê de volta, compara. "-" quando não se aplica.
# -----------------------------------------------------------------------------
ITEM_DB=(
    "google_translate|consenso|Google Translate TTS|1|core|user|texto para voz — 92,6% da base"
    "radio_browser|consenso|Radio Browser|1|core|user|catálogo de rádios para o media player — 82,1%"

    "cast|conectado|Google Cast|0|core|zeroconf|Chromecast e telas — 50,9%"
    "mqtt|conectado|MQTT|0|core|user|broker para Zigbee2MQTT, ESPHome e sensores DIY — 48,6%"
    "matter|conectado|Matter|0|core|zeroconf|padrão aberto; comissionamento pelo app do celular — 39,8%"
    "esphome|conectado|ESPHome|0|core|zeroconf|firmware para ESP32/ESP8266 — 27,0%"

    "hue|casa|Philips Hue|1|core|user|iluminação — apertar o botão da bridge durante o fluxo"
    "tuya|casa|Tuya|1|core|user|SmartLife, inclui as persianas — credencial de nuvem"
    "broadlink|casa|Broadlink|1|core|dhcp|infravermelho — exige o aparelho em modo de pareamento"
    "shelly|casa|Shelly|1|core|zeroconf|medição de energia — base dos packages de custo"
    "tplink|casa|TP-Link Smart Home|1|core|user|câmeras Tapo — pré-requisito do overlay PTZ"
    "smartthings|casa|SmartThings|1|core|dhcp|aparelhos Samsung — credencial de nuvem"
    "systemmonitor|casa|System Monitor|1|core|user|CPU, memória e disco — na VM a interface é eth0"

    "terminal_ssh|ferramentas|Terminal & SSH|1|oficial|-|o instalador usa para levar os .sh ao /config"
    "file_editor|ferramentas|File editor|1|oficial|-|editor que insere entidades e serviços da instância"
    "samba_share|ferramentas|Samba share|1|oficial|-|/config montável no Finder por smb://"

    "energia_br|custos|Custo de energia (BR)|1|proprio|-|reproduz a fatura na vírgula; simula Convencional x Branca"
    "gas_br|custos|Custo de gás canalizado (BR)|1|proprio|-|cascata por faixa, volume corrigido, ICMS de base reduzida"
    "agua_br|custos|Custo de água e esgoto (BR)|1|proprio|-|simula a concessionária e compara com o rateio do condomínio"

    "tapo_ptz_overlay|cameras|Overlay PTZ Tapo C210|1|proprio|-|PTZ sobre os cartões PADRÃO do HA, sem HACS"
    "tapo_tls_fix|cameras|Correção TLS ECDHE|cond|proprio|-|só se o log acusar SSLV3_ALERT_HANDSHAKE_FAILURE"

    "hacs|extensoes|HACS|0|custom|user|só a instalação; nunca por perfil; nada de dentro dele"
)

# -----------------------------------------------------------------------------
# VM_PROFILE_DB — id|rótulo|RAM MiB|vCPU|origem do número
#
# "derivado" é calculado pela sonda no momento da execução:
#     RAM  = min(50% da RAM DISPONÍVEL, 8192)
#     vCPU = hw.perflevel0.logicalcpu   (núcleos de performance)
# Se a sonda falhar, o perfil NÃO é ofertado — nunca cai num valor inventado.
#
# Disco não é dimensão: o .vdi do HAOS traz 32 GiB de capacidade virtual (lido
# do cabeçalho VDI) e o banco de uma instância de anos tem 885 MB.
# -----------------------------------------------------------------------------
VM_PROFILE_DB=(
    "vm_minimo|Mínimo|2048|2|documentação oficial do HA"
    "vm_equilibrado|Equilibrado|4096|2|medido — cobre os 2,5 GB de uma instância real"
    "vm_recomendado|Recomendado|derivado|derivado|calculado da sonda do hospedeiro"
)

# -----------------------------------------------------------------------------
# HAOS_PROFILE_DB — id|rótulo|categorias
# ESCADA: cada degrau SOMA ao anterior.
# -----------------------------------------------------------------------------
HAOS_PROFILE_DB=(
    "haos_vanilla|Vanilla|vanilla"
    "haos_consenso|Consenso|vanilla consenso"
    "haos_conectado|Conectado|vanilla consenso conectado"
    "haos_casa|Casa|vanilla consenso conectado casa ferramentas"
    "haos_abhome|ABHOME|vanilla consenso conectado casa ferramentas custos cameras"
)

# -----------------------------------------------------------------------------
# NÃO_APLICA_DB — id|motivo estrutural
# Nunca ofertado, nunca sugerido pelo --sync-catalog. O motivo é da plataforma,
# não preferência, e por isso vive fora do ITEM_DB — não polui o seletor.
# -----------------------------------------------------------------------------
NAO_APLICA_DB=(
    "raspberry_pi|não existe hardware Raspberry Pi numa VM em Mac"
    "rpi_power|mede a fonte do Raspberry Pi"
    "smartir|é pacote de dentro do HACS — a regra é não instalar nada de lá"
    "studio_code_server|exige adicionar repositório de terceiro; Samba entrega drag-and-drop sendo oficial"
)
