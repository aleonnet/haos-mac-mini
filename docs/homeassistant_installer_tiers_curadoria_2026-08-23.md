# Home Assistant — Curadoria e tiers para um instalador

**Data da validação:** 23/08/2026  
**Objetivo:** definir fontes confiáveis e regras de classificação para alimentar um instalador de Home Assistant OS (HAOS), evitando listas estáticas, duplicação de integrações criadas automaticamente e decisões baseadas apenas em popularidade.

---

## 1. Resposta curta: existe um site com curadoria?

### Sim, mas nenhum site sozinho resolve corretamente o problema de um instalador.

Existem duas fontes particularmente úteis, com propósitos diferentes:

1. **Home Assistant Analytics — oficial**
   - https://analytics.home-assistant.io/integrations/
   - https://analytics.home-assistant.io/apps/
   - Mede **adoção real** entre instalações que optaram por compartilhar analytics.
   - É a melhor fonte pública para responder: **“o que é mais usado?”**
   - Não é uma lista de “recomendados” e não deve, sozinha, decidir o que instalar.

2. **Awesome Home Assistant — curadoria comunitária**
   - https://www.awesome-ha.com/
   - Repositório: https://github.com/frenck/awesome-home-assistant
   - É explicitamente uma **lista curada** de recursos do ecossistema: custom integrations, cards, apps, ferramentas etc.
   - Porém, a própria documentação informa que **os itens não possuem ordem/ranking preestabelecido**.
   - Portanto serve muito bem para **descoberta/curadoria**, mas não como base única e automática para um instalador.

### Conclusão

Para um instalador, a fonte correta não é um único ranking.

A abordagem mais defensável é compor os dados oficiais e comunitários:

```text
Home Assistant Core / manifests
        +
default_config / onboarding
        +
Home Assistant Analytics
        +
Integration Quality Scale
        +
repositório oficial de Apps
        +
HACS / Awesome Home Assistant (somente community/custom)
        ↓
     ITEM_DB
        ↓
regra determinística de tiers
```

---

# 2. Fontes recomendadas para o instalador

## 2.1 Home Assistant Analytics — popularidade real

### Integrações

https://analytics.home-assistant.io/integrations/

Na validação de 23/08/2026:

| # | Integração | Adoção |
|---:|---|---:|
| 1 | Sun | 99,6% |
| 2 | Backup | 94,4% |
| 3 | Google Translate TTS | 92,6% |
| 4 | Mobile App | 86,1% |
| 5 | Met.no | 83,5% |
| 6 | Radio Browser | 82,1% |
| 7 | Home Assistant Supervisor | 80,9% |
| 8 | Shopping List | 75,0% |
| 9 | Google Cast | 50,9% |
| 10 | Bluetooth | 49,0% |
| 11 | MQTT | 48,6% |
| 12 | Matter | 39,8% |
| 13 | Thread | 37,1% |
| 18 | Tuya | 29,5% |
| 21 | ESPHome | 27,0% |
| 24 | Shelly | 25,0% |

Fonte:

https://analytics.home-assistant.io/integrations/

A amostra é **opt-in**. O Home Assistant deixa isso explicitamente claro; portanto os percentuais são excelentes como **ranking relativo de adoção**, mas não devem ser tratados como estimativa exata de toda a população Home Assistant.

Documentação do Analytics:

https://www.home-assistant.io/integrations/analytics/

---

## 2.2 Home Assistant Analytics — Apps

https://analytics.home-assistant.io/apps/

Na validação de 23/08/2026:

| # | App | Adoção |
|---:|---|---:|
| 1 | File editor | 63,6% |
| 2 | Mosquitto broker | 56,4% |
| 3 | Matter Server | 52,9% |
| 4 | SSH server | 40,7% |
| 5 | SSH & Web Terminal | 33,7% |
| 6 | Studio Code Server | 30,6% |
| 7 | ESPHome | 30,0% |
| 8 | Samba share | 26,8% |
| 9 | Tailscale | 14,7% |
| 10 | Node-RED | 13,8% |
| 23 | UPS Tools | 3,3% |

Fonte:

https://analytics.home-assistant.io/apps/

Essa é a melhor fonte pública para ordenar Apps por adoção.

---

# 3. Datasets públicos do Home Assistant Analytics

O próprio código-fonte oficial do site Analytics contém uma página que gera datasets JSON públicos.

Código-fonte:

https://github.com/home-assistant/analytics.home-assistant.io/blob/dev/site/src/datasets.liquid

O código declara explicitamente estes datasets:

```text
custom_integrations
addons
data
current_data
```

e os publica como:

```text
/custom_integrations.json
/addons.json
/data.json
/current_data.json
```

Portanto existem endpoints destinados ao consumo de dados, e não apenas as páginas HTML:

```text
https://analytics.home-assistant.io/custom_integrations.json
https://analytics.home-assistant.io/addons.json
https://analytics.home-assistant.io/data.json
https://analytics.home-assistant.io/current_data.json
```

### Recomendação

O instalador pode consumir esses datasets, mas deve:

- validar schema antes de importar;
- armazenar `fetched_at`;
- manter o último snapshot válido;
- não substituir a base em produção caso o schema mude inesperadamente;
- tratar Analytics como sinal de **adoção**, não como regra de instalação.

---

# 4. Fonte oficial de metadata das integrações

O Home Assistant gera um catálogo de integrações diretamente a partir do Core:

https://github.com/home-assistant/core/blob/dev/homeassistant/generated/integrations.json

Esse arquivo é especialmente útil para um instalador porque contém metadata como:

```text
domain
name
integration_type
config_flow
iot_class
single_config_entry
supported_by
```

Para cada integração individual, o `manifest.json` do Core pode ainda informar:

```text
dependencies
after_dependencies
dhcp
zeroconf
bluetooth
ssdp
usb
mqtt
requirements
quality_scale
codeowners
integration_type
iot_class
```

Documentação oficial do manifest:

https://developers.home-assistant.io/docs/creating_integration_manifest/

### Recomendação

Para o instalador, o **manifest é a autoridade para capacidade técnica e discovery**.

O Analytics deve complementar o manifest, não substituí-lo.

---

# 5. Integration Quality Scale

O Home Assistant possui uma classificação oficial de qualidade:

- Bronze
- Silver
- Gold
- Platinum

Além de classificações especiais:

- Internal
- Legacy
- Custom

Fonte oficial:

https://developers.home-assistant.io/docs/core/integration-quality-scale/

A escala avalia aspectos como:

- configuração via UI;
- estabilidade;
- recuperação de falhas;
- documentação;
- reautenticação;
- discovery;
- diagnostics;
- cobertura de testes;
- qualidade e eficiência do código.

### Uso recomendado no instalador

Adicionar ao `ITEM_DB` algo como:

```text
quality_scale
```

Exemplo:

```text
shelly:
  quality_scale: platinum
```

Na versão atual do Core validada, Shelly está marcada como `platinum`.

Manifest:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/shelly/manifest.json

### Importante

`quality_scale` mede **qualidade técnica**, não popularidade.

Portanto:

```text
Analytics = adoção
Quality Scale = qualidade
Manifest = comportamento/capacidade
Tier do instalador = decisão de produto
```

---

# 6. Awesome Home Assistant

Site:

https://www.awesome-ha.com/

Repositório:

https://github.com/frenck/awesome-home-assistant

É provavelmente o site que mais se aproxima da ideia de uma **curadoria humana do ecossistema Home Assistant**.

Inclui:

- custom integrations;
- dashboards;
- themes;
- icon packs;
- apps oficiais;
- apps de terceiros;
- ferramentas;
- projetos relacionados.

### Limitação importante

A própria lista declara que seus itens **não possuem uma ordem preestabelecida**.

Assim:

```text
Awesome HA = "é um recurso suficientemente relevante para entrar numa lista curada?"
```

e não:

```text
Awesome HA = "devo instalar isso por padrão?"
```

### Uso recomendado

Usar como sinal adicional para:

```text
origem = custom/community
```

e especialmente para alimentar uma futura categoria:

```text
curated = true
curated_source = awesome_home_assistant
```

Não usar diretamente para decidir `padrao=1`.

---

# 7. HACS como filtro de community/custom

HACS possui requisitos para que um repositório seja incluído entre seus repositórios padrão.

Documentação:

https://hacs.xyz/docs/publish/include/

Entre os requisitos estão:

- repositório público no GitHub;
- HACS Action válida;
- Hassfest para integrações;
- release oficial;
- submissão/revisão para inclusão.

Isso funciona como um **filtro mínimo de distribuição**, embora não seja uma auditoria de segurança nem uma recomendação universal.

### Uso recomendado

Adicionar metadata:

```text
hacs_default: true|false
```

e manter:

```text
origem = custom
```

Não transformar automaticamente `hacs_default=true` em `padrao=1`.

---

# 8. `haos_fabrica` — correção

A documentação oficial de `default_config` contém atualmente **24 integrações**.

Fonte:

https://www.home-assistant.io/integrations/default_config/

Lista correta:

```text
assist_pipeline
backup
bluetooth
config
conversation
dhcp
energy
file
go2rtc
history
homeassistant_alerts
cloud
image_upload
logbook
media_source
mobile_app
my
ssdp
stream
sun
usage_prediction
usb
webhook
zeroconf
```

### Correção em relação à lista anterior

Onde constava:

```text
cp
```

o correto é:

```text
config
```

Também estavam ausentes na listagem:

```text
conversation
dhcp
stream
sun
```

---

# 9. Baseline do HAOS não deve ser confundido com apenas `default_config`

Para um instalador de HAOS é útil distinguir três tipos de baseline:

```text
haos_fabrica
├── default_config
├── haos_intrinsic
└── onboarding
```

## `default_config`

Os 24 itens listados anteriormente.

## HAOS intrinsic

```text
hassio
```

`hassio` representa a integração com o Supervisor no HAOS.

## onboarding

A instalação normal do Home Assistant cria automaticamente integrações durante o onboarding.

Entre os elementos encontrados/validados no fluxo atual estão:

```text
google_translate
met
radio_browser
shopping_list
```

Isso explica por que essas integrações aparecem com adoção extremamente alta no Analytics.

### Consequência

Alta adoção desses itens **não significa que os usuários os escolheram manualmente**.

Portanto não devem formar um tier “Consenso”.

---

# 10. `analytics`

`analytics` merece tratamento separado.

O componente faz parte do fluxo do Home Assistant, mas **o envio de telemetria é opt-in**.

Não modelar:

```text
analytics = enabled
```

como comportamento de fábrica.

Melhor:

```text
analytics_component_available = true
analytics_reporting_enabled = user_consent
```

Fonte:

https://www.home-assistant.io/integrations/analytics/

---

# 11. `haos_consenso` — remover

O tier anterior era:

```text
google_translate
radio_browser
```

com a justificativa:

```text
>75% na telemetria e ausentes do default_config
```

Isso não é correto para um instalador.

Ambos são criados pelo fluxo padrão/onboarding.

O mesmo raciocínio alcança:

```text
met
shopping_list
```

### Resultado

Se a regra for:

```text
consenso =
    alta adoção
    AND
    não pertencente ao baseline automático
```

o tier praticamente desaparece.

### Recomendação

Remover:

```text
haos_consenso
```

e usar:

```text
haos_fabrica
    ↓
haos_conectado
    ↓
haos_casa
```

Isso é mais determinístico e mais fiel ao comportamento real do Home Assistant.

---

# 12. `haos_conectado`

A seleção anterior:

```text
cast
mqtt
matter
esphome
```

é defensável.

Mas deve ser acrescentado:

```text
thread
```

Adoção oficial atual:

```text
cast     50,9%
mqtt     48,6%
matter   39,8%
thread   37,1%
esphome  27,0%
```

Fonte:

https://analytics.home-assistant.io/integrations/

### Tier recomendado

```text
haos_conectado:
  - cast
  - mqtt
  - matter
  - thread
  - esphome
```

### Não usar apenas um limite percentual

Uma regra como:

```text
27% <= adoption <= 51%
```

seria incorreta, pois incluiria também itens semanticamente diferentes, como:

- Template;
- Input Boolean;
- UPnP;
- Group;
- Tuya;
- IPP;
- DLNA.

A regra correta deve combinar:

```text
categoria_semantica = infraestrutura/conectividade
AND
adoção_relevante = true
```

---

# 13. Matter e Matter Server

`matter` é uma integração do Core.

`Matter Server` é um App.

O instalador deve tratar isso como uma relação de dependência, e não como dois itens independentes selecionados cegamente.

Modelo recomendado:

```text
matter:
  type: integration
  app_dependency:
    slug: matter_server
    managed_by_ha: true
```

Evitar instalar o Matter Server duplicadamente quando o fluxo oficial do Home Assistant puder administrá-lo.

---

# 14. `haos_casa`

A categoria deve representar integrações correspondentes aos dispositivos/serviços realmente presentes na residência.

Itens anteriores:

```text
hue
tuya
broadlink
shelly
tplink
smartthings
```

estão semanticamente corretos nesse tier.

### Regra recomendada

```text
haos_casa =
    integração correspondente a hardware/serviço detectado
    OU explicitamente declarado pelo usuário
```

Popularidade não deve ser o único critério.

Exemplo:

Tuya possui adoção muito maior que várias integrações, mas isso não significa que deva ser instalada numa residência sem nenhum dispositivo Tuya.

---

# 15. `systemmonitor`

`systemmonitor` não representa um dispositivo residencial.

Ele monitora:

- CPU;
- memória;
- disco;
- rede;
- processos;
- uptime;
- temperatura quando disponível;

do sistema em que o Home Assistant está rodando.

Fonte:

https://www.home-assistant.io/integrations/systemmonitor/

Portanto:

```text
systemmonitor
```

deve sair de:

```text
casa
```

e ir para:

```text
ferramentas
```

ou, preferencialmente:

```text
observabilidade
```

### Source

A configuração moderna ocorre pela UI:

```text
Settings
→ Devices & services
→ Add Integration
→ System monitor
```

Logo, para novas instalações:

```text
source = user
```

é mais adequado que:

```text
source = import
```

`import` deve ser reservado a migrações/configurações legadas quando aplicável.

---

# 16. Ferramentas / Apps

Os itens:

```text
file_editor
terminal_ssh
samba_share
```

são escolhas defensáveis, com forte adoção.

Porém existe uma distinção importante.

## Oficial

O repositório oficial de Apps do Home Assistant contém:

```text
File editor
SSH server
Samba share
Mosquitto broker
MariaDB
Duck DNS
...
```

Fonte:

https://github.com/home-assistant/addons

README oficial:

https://github.com/home-assistant/addons/blob/master/README.md

## Community

O Analytics também mostra:

```text
SSH & Web Terminal
```

mas ele é diferente do:

```text
SSH server
```

oficial.

Portanto o banco não deve chamar genericamente um deles de `Terminal & SSH` e marcar `origem=oficial` sem especificar qual App está sendo usado.

### Modelo recomendado

```text
ssh_server:
  rotulo: SSH server
  cat: ferramentas
  origem: oficial

advanced_ssh_web_terminal:
  rotulo: SSH & Web Terminal
  cat: ferramentas
  origem: community
```

---

# 17. Discovery/source das integrações da casa

Para o instalador, a coluna `source` deve representar preferencialmente o discovery real suportado pelo manifest.

## Broadlink

Manifest atual declara `dhcp`.

Fonte:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/broadlink/manifest.json

```text
broadlink → dhcp
```

## Shelly

Manifest atual declara:

```text
bluetooth
zeroconf
```

Fonte:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/shelly/manifest.json

O Core atual marca Shelly como:

```text
quality_scale = platinum
```

## SmartThings

Manifest atual contém matchers DHCP.

Fonte:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/smartthings/manifest.json

```text
smartthings → dhcp discovery possível
```

Embora sua configuração posterior envolva o serviço/cloud.

## TP-Link Smart Home

Manifest atual possui uma lista extensa de matchers DHCP.

Fonte:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/tplink/manifest.json

Portanto, em vez de:

```text
tplink | source=user
```

é melhor permitir:

```text
discovery:
  - dhcp

fallback_setup:
  - user
```

### Recomendação estrutural

Uma única coluna `source` fica limitada para um instalador.

Melhor separar:

```text
discovery_sources
setup_sources
preferred_source
```

Exemplo:

```yaml
tplink:
  discovery_sources:
    - dhcp
  setup_sources:
    - dhcp
    - user
  preferred_source: dhcp
```

---

# 18. ITEM_DB — estrutura recomendada

Em vez de:

```text
id
cat
rotulo
padrao
origem
source
```

recomenda-se evoluir para:

```text
id
cat
rotulo
origem
default_policy
discovery_sources
setup_sources
preferred_source
quality_scale
analytics_pct
curated
curated_source
requires
conflicts
conditional
```

Exemplo:

```yaml
shelly:
  cat: casa
  rotulo: Shelly
  origem: core
  default_policy: device_detected
  discovery_sources:
    - zeroconf
    - bluetooth
  setup_sources:
    - zeroconf
    - bluetooth
    - user
  preferred_source: zeroconf
  quality_scale: platinum
  analytics_pct: 25.0
  conditional: true
```

Isso permite que o instalador tome decisões muito melhores que um simples:

```text
padrao = 0|1
```

---

# 19. Regra recomendada dos tiers

## `haos_fabrica`

Instalar/configurar apenas o que não seja automaticamente garantido pela própria instalação.

O banco deve conhecer o baseline para **não duplicá-lo**.

```text
default_config
+ HAOS intrinsic
+ onboarding
```

## `haos_conectado`

Infraestrutura/protocolos de alta utilidade:

```text
cast
mqtt
matter
thread
esphome
```

Mas cada item deve respeitar:

```text
detecção
hardware disponível
dependências
opção do usuário
```

## `haos_casa`

Integrações diretamente relacionadas aos equipamentos presentes:

```text
hue
tuya
broadlink
shelly
tplink
smartthings
...
```

## `ferramentas`

Ferramentas operacionais:

```text
file_editor
ssh_server
samba_share
systemmonitor
```

ou separar:

```text
ferramentas
observabilidade
```

## `custos`

Projeto específico:

```text
energia_br
gas_br
agua_br
```

## `cameras`

Projeto específico:

```text
tapo_ptz_overlay
tapo_tls_fix
```

## `extensoes`

```text
hacs
```

sempre como opt-in/custom.

---

# 20. Escada final recomendada

```text
HAOS_PROFILE_DB

haos_fabrica
    ├── default_config (24)
    ├── hassio / Supervisor
    └── onboarding automático

haos_conectado
    ├── cast
    ├── mqtt
    ├── matter
    ├── thread
    └── esphome

haos_casa
    ├── hue
    ├── tuya
    ├── broadlink
    ├── shelly
    ├── tplink
    └── smartthings

ferramentas
    ├── file_editor
    ├── ssh_server
    ├── samba_share
    └── systemmonitor

custos
    ├── energia_br
    ├── gas_br
    └── agua_br

cameras
    ├── tapo_ptz_overlay
    └── tapo_tls_fix

extensoes
    └── hacs
```

### Remover

```text
haos_consenso
```

---

# 21. Como o instalador deve se atualizar

Uma rotina automatizada pode atualizar a curadoria em camadas.

## Camada 1 — Core

Consultar periodicamente:

```text
home-assistant/core
```

para obter:

- integrações existentes;
- manifests;
- `quality_scale`;
- discovery;
- dependências;
- integração removida/renomeada.

Principal arquivo agregado:

https://github.com/home-assistant/core/blob/dev/homeassistant/generated/integrations.json

---

## Camada 2 — Analytics

Consultar:

```text
https://analytics.home-assistant.io/current_data.json
https://analytics.home-assistant.io/addons.json
https://analytics.home-assistant.io/custom_integrations.json
```

para atualizar:

```text
analytics_pct
analytics_rank
analytics_installations
last_seen
```

Nunca utilizar percentuais sozinhos para alterar `default_policy`.

---

## Camada 3 — Apps oficiais

Consultar:

https://github.com/home-assistant/addons

para atualizar:

- Apps oficiais existentes;
- slugs;
- versões;
- Apps removidos;
- documentação;
- arquiteturas suportadas.

---

## Camada 4 — HACS

Consultar as listas/default repositories do HACS para atualizar:

```text
hacs_default
```

Documentação:

https://hacs.xyz/docs/publish/include/

---

## Camada 5 — Awesome Home Assistant

Consultar:

https://github.com/frenck/awesome-home-assistant

para marcar itens comunitários com:

```text
curated = true
curated_source = awesome_home_assistant
```

Não alterar automaticamente:

```text
default_policy
```

com base apenas nessa inclusão.

---

# 22. Política de atualização sugerida

```text
Core/manifests       → diariamente ou a cada release
Analytics            → diariamente
Apps oficiais        → diariamente
HACS defaults        → semanalmente
Awesome HA           → semanalmente
```

Antes de publicar uma nova base:

```text
1. fetch
2. validar schema
3. normalizar IDs
4. comparar snapshot anterior
5. detectar removidos/renomeados
6. aplicar regras de tier
7. executar testes
8. somente então promover para produção
```

---

# 23. Regra importante: popularidade ≠ instalação automática

Exemplos:

```text
Google Translate = 92,6%
Radio Browser    = 82,1%
```

Isso poderia sugerir forte “consenso”.

Mas ambos fazem parte do comportamento automático de onboarding, portanto esse número não representa necessariamente uma decisão explícita do usuário.

Da mesma forma:

```text
Tuya = 29,5%
```

não significa que 29,5% seja um threshold adequado para instalar Tuya em todas as casas.

### Portanto

A decisão deve seguir:

```text
baseline automático
    ↓
compatibilidade / discovery
    ↓
dependências
    ↓
tipo semântico
    ↓
qualidade
    ↓
adoção
    ↓
preferência do usuário
```

e nunca apenas:

```text
adoção > X%
```

---

# 24. Fontes principais

## Oficiais

### Home Assistant Analytics

https://analytics.home-assistant.io/

https://analytics.home-assistant.io/integrations/

https://analytics.home-assistant.io/apps/

https://www.home-assistant.io/integrations/analytics/

### Datasets Analytics

https://github.com/home-assistant/analytics.home-assistant.io/blob/dev/site/src/datasets.liquid

### Default Config

https://www.home-assistant.io/integrations/default_config/

### Catálogo de integrações do Core

https://github.com/home-assistant/core/blob/dev/homeassistant/generated/integrations.json

### Integration manifest

https://developers.home-assistant.io/docs/creating_integration_manifest/

### Integration Quality Scale

https://developers.home-assistant.io/docs/core/integration-quality-scale/

### Apps oficiais

https://github.com/home-assistant/addons

https://www.home-assistant.io/apps

### System Monitor

https://www.home-assistant.io/integrations/systemmonitor/

### Manifests específicos

Broadlink:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/broadlink/manifest.json

Shelly:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/shelly/manifest.json

SmartThings:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/smartthings/manifest.json

TP-Link:

https://github.com/home-assistant/core/blob/dev/homeassistant/components/tplink/manifest.json

## Comunitárias/curadas

### Awesome Home Assistant

https://www.awesome-ha.com/

https://github.com/frenck/awesome-home-assistant

### HACS

https://hacs.xyz/

https://hacs.xyz/docs/publish/include/

---

# 25. Conclusão

Não existe hoje uma única fonte que possa ser usada com segurança como:

```text
"lista oficial de coisas que um instalador deve instalar"
```

Mas existem fontes públicas suficientes para construir isso de forma objetiva e autoatualizável.

A combinação recomendada é:

```text
Core manifest
+ default_config/onboarding
+ Analytics
+ Quality Scale
+ Apps oficiais
+ HACS
+ Awesome HA
```

E a classificação recomendada fica:

```text
Fábrica
    ↓
Conectado
    ↓
Casa
```

com categorias ortogonais para:

```text
Ferramentas
Observabilidade
Custos
Câmeras
Extensões
```

O tier:

```text
Consenso
```

deve ser removido, pois estava misturando **popularidade observada** com **itens automaticamente criados pelo Home Assistant**.
