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
    "smartir|casa|SmartIR (clima IR)|custom|-|0|-|-|-|broadlink|-|termostato IR p/ ar-condicionado via RM4 — release fixada, instalação direta (sem HACS)"
    "smartthings|casa|SmartThings|core|-|1|dhcp|user dhcp|user|application_credentials|-|aparelhos Samsung — OAuth, não token pessoal"

    # ── ferramentas ──────────────────────────────────────────────────────────
    "advanced_ssh|ferramentas|SSH & Web Terminal|community|DESCOBRIR_ssh|1|-|-|-|-|repo_terceiro|terminal com Docker API; 33,7% — repositório hassio-addons"
    "studio_code_server|ferramentas|Studio Code Server|community|DESCOBRIR_vscode|1|-|-|-|-|repo_terceiro|VS Code no navegador, ciente das entidades — repositório hassio-addons"
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
    "studio_code_server|-|-"
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
    # smartir SAIU desta lista em 24/08/2026: a regra visava o CANAL HACS, não
    # o código — entrou no ITEM_DB como instalação direta com release fixada
    # e SHA-256 (decisão do dono, para os ar-condicionados via RM4)
    "file_editor|substituído pelo Studio Code Server por decisão do dono (24/08/2026) — a regra 'preferir o oficial quando cobre' cedeu à experiência de edição"
    "core_ssh|oficial, mas NÃO cobre: o config.yaml não declara docker_api, e Protection mode só libera o que o app declara"
)
