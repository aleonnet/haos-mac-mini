# Referência de APIs — contrato verificado do instalador

> **Verificado em 2026-08-23 contra documentação oficial e código-fonte oficial.**
>
> Este documento é a base do contrato do arnês de manutenção do instalador. Ele distingue
> explicitamente:
>
> - superfícies públicas/documentadas;
> - superfícies existentes no código, mas não documentadas como External API;
> - fatos observados empiricamente na instância/binário de teste;
> - decisões de projeto do próprio instalador.
>
> **Regra:** nenhuma superfície `SOURCE-PINNED` deve ser tratada como API pública estável apenas
> porque existe no Core.

---

## 0. Semântica de evidência

| Marcador | Significado |
|---|---|
| `PUBLIC-DOC` | Contrato descrito em documentação pública oficial do fabricante/projeto |
| `SOURCE-PINNED` | Implementação confirmada no código-fonte oficial da versão indicada, mas sem contrato público equivalente |
| `EMPÍRICO` | Comportamento observado na instância/binário de teste; não é promessa de compatibilidade |
| `POLÍTICA` | Regra adotada pelo instalador/arnês |
| `DOC-GAP` | Documentação oficial é incompleta, contraditória ou não fecha sozinha a tradução para a implementação |

### Regra de precedência do instalador

```text
PUBLIC-DOC
    ↓
SOURCE-PINNED na versão exata
    ↓
probe do binário/runtime
    ↓
EMPÍRICO
```

Em caso de divergência, o instalador **não deve inferir silenciosamente**. Deve falhar o contrato,
registrar a diferença e exigir atualização do adaptador.

---

## 0.1 Versões de referência

| Alvo | Versão de referência | Situação |
|---|---|---|
| Home Assistant Core | **2026.8.3** | documentação oficial + código oficial tag `2026.8.3` |
| Home Assistant OS | **18.2** | release oficial |
| Imagem HAOS Apple Silicon | **`haos_generic-aarch64-18.2.vdi.zip`** | link oficial usado pela documentação de instalação |
| VirtualBox | **7.2.16**, build **174877** | diretório oficial de distribuição Oracle |

### Fontes

Home Assistant Core / docs:

- https://www.home-assistant.io/
- https://github.com/home-assistant/core/tree/2026.8.3

Home Assistant OS 18.2:

- https://github.com/home-assistant/operating-system/releases/tag/18.2
- https://github.com/home-assistant/operating-system/releases/download/18.2/haos_generic-aarch64-18.2.vdi.zip

VirtualBox 7.2.16:

- https://download.virtualbox.org/virtualbox/7.2.16/
- https://download.virtualbox.org/virtualbox/7.2.16/SDKRef.pdf
- https://download.virtualbox.org/virtualbox/7.2.16/UserManual.pdf

---

# 1. Home Assistant — REST API documentada

**Evidência:** `PUBLIC-DOC`

Fonte oficial:

- https://developers.home-assistant.io/docs/api/rest/

Autenticação documentada:

```http
Authorization: Bearer <token>
```

## 1.1 Quantidade

A referência pública documenta **20 combinações método + caminho** relevantes na página.

É mais preciso dizer **“20 combinações método+caminho documentadas”** do que simplesmente
“20 endpoints”, porque um mesmo caminho pode aceitar mais de um método.

## 1.2 Superfície documentada

| Método | Caminho |
|---|---|
| GET | `/api/` |
| GET | `/api/config` |
| GET | `/api/components` |
| GET | `/api/events` |
| GET | `/api/services` |
| GET | `/api/states` |
| GET | `/api/states/<entity_id>` |
| GET | `/api/history/period/<timestamp>` |
| GET | `/api/logbook/<timestamp>` |
| GET | `/api/error_log` |
| GET | `/api/camera_proxy/<entity_id>` |
| GET | `/api/calendars` |
| GET | `/api/calendars/<entity_id>?start=<timestamp>&end=<timestamp>` |
| POST | `/api/states/<entity_id>` |
| POST | `/api/events/<event_type>` |
| POST | `/api/services/<domain>/<service>` |
| POST | `/api/template` |
| POST | `/api/config/core/check_config` |
| POST | `/api/intent/handle` |
| DELETE | `/api/states/<entity_id>` |

### Correção aplicada

No rascunho anterior, a chamada:

```text
GET /api/calendars/<entity_id>
```

estava sem explicitar os parâmetros de consulta requeridos pela documentação:

```text
?start=<timestamp>&end=<timestamp>
```

## 1.3 O que essa API cobre

A formulação anterior:

> “Cobrem ler estado e chamar serviços — não configuram nada.”

era estreita demais.

A REST API documentada cobre, entre outras coisas:

- configuração geral de runtime (`/api/config`);
- componentes;
- eventos;
- serviços;
- estados;
- histórico;
- logbook;
- error log;
- proxy de câmera;
- calendários;
- disparo de eventos;
- chamadas de serviços;
- avaliação de templates;
- validação de configuração YAML;
- intent handling.

### Importante sobre `/api/states/<entity_id>`

`POST /api/states/<entity_id>` **cria ou atualiza uma representação de estado** no state machine.
A própria documentação ressalta que isso **não significa controlar fisicamente um dispositivo** e
que o estado criado nem precisa corresponder a uma entidade real provida por uma integração.

## 1.4 Limite relevante ao instalador

**[PUBLIC-DOC / FATO]**

A referência REST acima **não documenta** operações para:

- criar `config_entry`;
- iniciar/avançar `config_flow`;
- executar onboarding;
- ignorar discovery flow;
- instalar/configurar integração pela UI;
- configurar dashboards.

Portanto:

```text
REST External API != API de configuração do frontend
```

---

# 2. Home Assistant — WebSocket API documentada

**Evidência:** `PUBLIC-DOC`

Fonte oficial:

- https://developers.home-assistant.io/docs/api/websocket/

## 2.1 Correção: não fixar “21 comandos”

O rascunho dizia:

> “21 comandos”

e enumerava 21 nomes.

Isso não é uma descrição tecnicamente robusta do protocolo, porque a lista mistura:

- mensagens da **fase de autenticação**;
- comandos da **command phase**;
- respostas emitidas pelo servidor.

Exemplos:

```text
auth  = mensagem cliente → servidor da fase de autenticação
pong  = resposta servidor → cliente ao ping
```

Logo, o contrato do instalador deve depender dos **tipos de mensagem pelo nome e direção**, e não
de um contador global que pode mudar quando a documentação acrescentar outra operação.

## 2.2 Conjunto documentado usado pelo instalador

| `type` | Direção principal | Observação |
|---|---|---|
| `auth` | cliente → servidor | fase de autenticação |
| `supported_features` | cliente → servidor | negociação de features |
| `subscribe_events` | cliente → servidor | assinatura |
| `unsubscribe_events` | cliente → servidor | cancelamento |
| `subscribe_trigger` | cliente → servidor | assinatura de trigger |
| `fire_event` | cliente → servidor | mutação/runtime |
| `call_service` | cliente → servidor | mutação/runtime |
| `get_states` | cliente → servidor | leitura |
| `get_config` | cliente → servidor | leitura |
| `get_services` | cliente → servidor | leitura |
| `get_panels` | cliente → servidor | leitura |
| `ping` | cliente → servidor | keepalive/teste |
| `pong` | servidor → cliente | resposta ao `ping` |
| `validate_config` | cliente → servidor | validação |
| `extract_from_target` | cliente → servidor | helper |
| `get_triggers_for_target` | cliente → servidor | helper |
| `get_conditions_for_target` | cliente → servidor | helper |
| `get_services_for_target` | cliente → servidor | helper |
| `config/entity_registry/list_for_display` | cliente → servidor | leitura resumida do entity registry |
| `homeassistant/expose_entity/list` | cliente → servidor | leitura |
| `homeassistant/expose_entity` | cliente → servidor | **muta** exposição da entidade |

### Correção aplicada

Não é correto dizer que tudo nessa lista é de leitura exceto serviços/eventos.

`homeassistant/expose_entity` altera imediatamente se uma entidade deve ser exposta a um assistente.

## 2.3 Limite da referência genérica WebSocket

**[PUBLIC-DOC / FATO, escopo restrito à página acima]**

Essa referência genérica **não documenta**:

- criação/listagem completa de `config_entries`;
- `config_flow`;
- `config_entries/ignore_flow`;
- mutação de area registry;
- mutação de device registry;
- configuração de dashboards.

O comando relacionado ao entity registry explicitamente presente nessa referência é:

```text
config/entity_registry/list_for_display
```

e é de leitura.

### Nota

Isso **não significa** que não existam outras rotas WebSocket no Core. Significa apenas que elas
não fazem parte da superfície descrita por essa página pública genérica.

---

# 3. Home Assistant — Authentication API documentada

**Evidência:** `PUBLIC-DOC`

Fonte oficial:

- https://developers.home-assistant.io/docs/auth_api/

Esta seção precisa existir separadamente da REST API genérica e da API interna.

## 3.1 Fluxo público/documentado

A documentação oficial descreve o fluxo OAuth2/IndieAuth:

```text
GET /auth/authorize
        ↓
authorization code
        ↓
POST /auth/token
        ↓
access token + refresh token
```

## 3.2 `/auth/token`

**[CORREÇÃO MATERIAL]**

`POST /auth/token` **não é API privada do frontend**.

Ele é documentado oficialmente pela Authentication API.

Content type:

```http
Content-Type: application/x-www-form-urlencoded
```

Para troca de authorization code:

```text
grant_type=authorization_code
code=<authorization_code>
client_id=<mesmo_client_id_usado_na_autorizacao>
```

## 3.3 Regra de `client_id`

A formulação anterior:

> “client_id precisa ser URL canônica IndieAuth”

era imprecisa.

A documentação estabelece que:

- `client_id` é a URL que identifica o aplicativo;
- para clientes IndieAuth, essa URL é também a página do cliente;
- por padrão, `redirect_uri` precisa compartilhar **host e porta** com o `client_id`;
- a documentação prevê mecanismo por `<link rel="redirect_uri">` na página do `client_id` para
  autorizar redirects adicionais;
- na troca do authorization code, deve ser usado o **mesmo `client_id`** empregado na autorização.

## 3.4 Regra para o instalador

```text
Fluxo de autenticação suportado/publicado:
    /auth/authorize → /auth/token
```

O instalador não deve substituir esse fluxo por `/auth/login_flow` e depois tratá-lo como contrato
público.

---

# 4. Home Assistant — superfície SOURCE-PINNED, não External API

**Evidência:** `SOURCE-PINNED`

Estas rotas foram confirmadas no código-fonte oficial da tag:

```text
home-assistant/core 2026.8.3
```

Elas existem nessa versão, porém **não constam das referências públicas REST/WebSocket acima como
External API de configuração**.

Isso é diferente de dizer que são “inventadas” ou “não oficiais”: elas estão no Core oficial.
A diferença é **contratual**.

## 4.1 Política de compatibilidade

O rascunho anterior afirmava:

> “Não há política de depreciação para esta superfície. API pública do HA tem aviso prévio; esta não.”

A primeira metade é plausível como cautela, mas a segunda transforma uma ausência observada em uma
promessa formal.

### Formulação verificada

**[POLÍTICA DO INSTALADOR]**

Não foi encontrada, nas referências External API citadas neste documento, uma promessa formal de
janela de compatibilidade/depreciação para as rotas internas abaixo.

Por isso o instalador deve tratá-las como:

```text
version-sensitive
```

e o arnês deve validar contrato após upgrade.

Isso é uma **decisão de engenharia do instalador**, não uma garantia declarada pelo Home Assistant.

---

## 4.2 Auth login flow interno

Código oficial 2026.8.3:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/auth/login_flow.py

### Rotas

```text
POST /auth/login_flow
POST /auth/login_flow/{flow_id}
```

### Correção de nomenclatura

Não chamar genericamente isso de:

```text
“Login por usuário/senha”
```

O mecanismo é um **login flow de auth provider/MFA**.

Quando o provider é o provider local `homeassistant`, o formulário pode ser o fluxo convencional de
usuário/senha; outros providers ou MFA podem produzir passos diferentes.

### Estado no arnês

```text
[EMPÍRICO] exercitado em 2026-08-23
[SOURCE-PINNED] confirmado no Core 2026.8.3
```

---

# 5. Config entries / config flows

**Evidência:** `SOURCE-PINNED`

Código oficial:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/config/config_entries.py

## 5.1 Listar config entries

```http
GET /api/config/config_entries/entry
```

**[EMPÍRICO]** No teste informado em 2026-08-23, retornou **46 entries**.

O valor `46` é apenas estado da instância testada, **não faz parte do contrato**.

## 5.2 Iniciar config flow

```http
POST /api/config/config_entries/flow
Content-Type: application/json
```

Forma mínima compatível com o caso comum:

```json
{
  "handler": "<domain>"
}
```

O código ainda aceita contexto/opções adicionais conforme o tipo de flow.

### Segurança

A implementação exige permissões administrativas/adequadas ao gerenciamento de config entries.

## 5.3 Avançar config flow

```http
POST /api/config/config_entries/flow/{flow_id}
Content-Type: application/json
```

O payload depende do `step_id` e do schema devolvido pelo flow.

### Regra do arnês

Nunca hard-code o formulário inteiro sem primeiro ler a resposta do passo atual.

Fluxo:

```text
POST /flow
   ↓
ler type / flow_id / step_id / data_schema
   ↓
POST /flow/{flow_id}
   ↓
verificar result
```

## 5.4 Estado empírico

```text
listar entries       ✅ exercitado
iniciar config flow  ⚠️ a exercitar
avançar config flow  ⚠️ a exercitar
```

---

# 6. Ignorar discovery/config flow

**Evidência:** `SOURCE-PINNED`

Código oficial:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/config/config_entries.py

Comando WebSocket:

```text
config_entries/ignore_flow
```

## 6.1 Correções aplicadas

O rascunho dizia apenas que “exige flow em progresso”.

Isso é incompleto.

O schema exige:

```json
{
  "type": "config_entries/ignore_flow",
  "flow_id": "<flow_id>",
  "title": "<title>"
}
```

Além disso, a implementação:

1. procura o `flow_id` entre flows em progresso;
2. exige que o contexto do flow tenha `unique_id`;
3. usa esse `unique_id` para iniciar um flow com source `ignore`.

### Portanto

Pré-condições relevantes:

```text
flow em progresso
AND unique_id presente
AND title fornecido
AND usuário autorizado/admin
```

### Estado empírico

```text
⚠️ a exercitar
```

---

# 7. Onboarding

**Evidência:** `SOURCE-PINNED`

Código oficial 2026.8.3:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/onboarding/views.py

Estas rotas pertencem ao componente `onboarding`.

## 7.1 Status

```http
GET /api/onboarding
```

Retorna o estado dos passos de onboarding.

## 7.2 Installation type

```http
GET /api/onboarding/installation_type
```

É uma rota específica do fluxo de onboarding; seu comportamento é condicionado pelo estado do
onboarding.

## 7.3 Criar usuário inicial

```http
POST /api/onboarding/users
```

Campos relevantes exigidos pelo código 2026.8.3:

```text
name
username
password
client_id
language
```

A operação cria o primeiro usuário/admin e retorna um authorization code para o fluxo subsequente.

### Estado empírico

```text
⚠️ a exercitar
```

## 7.4 Core config

```http
POST /api/onboarding/core_config
```

Na implementação 2026.8.3, esse passo inicia flows de onboarding para integrações como:

```text
google_translate
met
radio_browser
shopping_list
```

e garante setup do componente `analytics`.

Isso é importante para o instalador porque evita duplicar automaticamente config entries que o
próprio onboarding já cria.

## 7.5 Integration

```http
POST /api/onboarding/integration
```

Participa do fechamento do onboarding e da emissão de authorization code após validação do cliente
e redirect.

## 7.6 Espera de integração

```http
POST /api/onboarding/integration/wait
```

Permite aguardar carregamento de determinado domínio no fluxo de onboarding.

## 7.7 Analytics

```http
POST /api/onboarding/analytics
```

Trata o passo de analytics do onboarding.

### Estado empírico dos demais passos

```text
⚠️ a exercitar
```

---

# 8. Backup — NÃO é onboarding

**[CORREÇÃO MATERIAL]**

As operações abaixo existem no Core 2026.8.3, mas pertencem à integração/componente **Backup**,
não a `onboarding`.

Fontes oficiais do código:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/backup/websocket.py
- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/backup/http.py

## 8.1 Backup info

Protocolo:

```text
WebSocket
```

Comando:

```json
{
  "type": "backup/info"
}
```

Requer usuário administrador na implementação.

## 8.2 Upload de backup

Protocolo:

```text
HTTP
```

Rota:

```http
POST /api/backup/upload
```

A implementação exige administrador e trabalha com agente(s) de backup; o `agent_id` faz parte da
seleção do destino/agente.

## 8.3 Restore

Protocolo:

```text
WebSocket
```

Comando:

```text
backup/restore
```

A implementação exige administrador e campos como backup/agente, além das opções de restauração
aplicáveis.

## 8.4 Download

O Core também implementa:

```http
GET /api/backup/download/{backup_id}
```

com contexto de agente/autorização.

Inclua no contrato apenas se o instalador realmente consumir essa operação.

## 8.5 Estado empírico

```text
backup/info     ⚠️ a exercitar
backup/upload   ⚠️ a exercitar
backup/restore  ⚠️ a exercitar
```

---

# 9. Supervisor API e `/api/hassio/*`

Esta área precisa separar **duas superfícies diferentes**.

---

## 9.1 Supervisor API direta

**Evidência:** `PUBLIC-DOC`, porém **context-scoped**

Fonte:

- https://developers.home-assistant.io/docs/api/supervisor/endpoints/

A documentação oficial do Supervisor descreve endpoints que usam token de Supervisor no contexto
apropriado, normalmente disponibilizado para Home Assistant/Apps como:

```text
SUPERVISOR_TOKEN
```

Um access token normal de usuário do Home Assistant **não deve ser tratado como equivalente a
`SUPERVISOR_TOKEN`** para chamadas diretas ao Supervisor.

---

## 9.2 Proxy Core `/api/hassio/{path}`

**Evidência:** `SOURCE-PINNED`

Código oficial 2026.8.3:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/hassio/http.py

### Correção material

O rascunho dizia:

> “O proxy do Supervisor (`/api/hassio/*`) recusa token de usuário — devolveu 401.”

Isso é **geral demais**.

A implementação do Core:

1. recebe a chamada em `/api/hassio/{path}`;
2. determina o contexto/autorização do usuário;
3. mantém allowlists distintas para caminhos sem auth e caminhos de admin;
4. rejeita com 401 caminhos que não estejam autorizados;
5. quando encaminha uma chamada autorizada ao Supervisor, usa o token interno de Supervisor.

### Formulação correta

```text
Um 401 em /api/hassio/* não prova que todo access token de usuário é recusado.
O proxy é allowlistado e sensível ao caminho/permissão.
```

### Observação empírica

```text
[EMPÍRICO] a chamada testada anteriormente devolveu 401.
```

O contrato deve registrar **qual path exato** produziu esse 401 antes de transformá-lo em teste de
regressão.

---

# 10. Home Assistant — conclusão sobre superfícies de API

## Pública/documentada

```text
REST External API
WebSocket External API
Authentication API
Supervisor API (context-scoped)
```

## Confirmada no Core, mas version-sensitive para o instalador

```text
/auth/login_flow
/api/config/config_entries/*
config_entries/ignore_flow
/api/onboarding/*
backup/info
/api/backup/*
backup/restore
/api/hassio/{path} proxy
```

### Regra do arnês

Para cada dependência `SOURCE-PINNED`, armazenar pelo menos:

```text
component
route_or_type
protocol
http_method
minimum_required_fields
auth_requirement
source_tag
source_file
postcondition
rollback_or_failure_behavior
```

---

# 11. VirtualBox 7.2.16 — Main API

**Evidência:** `PUBLIC-DOC`

Fontes exatas da release:

- https://download.virtualbox.org/virtualbox/7.2.16/SDKRef.pdf
- https://download.virtualbox.org/virtualbox/7.2.16/UserManual.pdf
- https://download.virtualbox.org/virtualbox/7.2.16/

Versão:

```text
VirtualBox 7.2.16
build 174877
```

## 11.1 O que a SDK Reference estabelece

A substância do trecho citado no rascunho está correta, mas não é necessário manter uma longa
citação literal no contrato.

A documentação oficial descreve que:

- a Main API expõe a funcionalidade do engine de virtualização;
- a GUI e `VBoxManage` são frontends da Main API;
- eles não recebem um “backdoor” funcional separado da API documentada;
- no Windows a interface local usa COM;
- nos demais hosts usa XPCOM;
- o web service expõe remotamente quase toda a Main API.

### Correção de linguagem

Evitar:

> “O caminho gráfico não tem privilégio nenhum.”

Isso pode ser interpretado como privilégio de processo/OS.

Formulação segura:

> **A GUI não possui uma superfície funcional oculta de virtualização distinta da Main API.**

Isso não implica que todos os processos tenham permissões de sistema operacional idênticas.

## 11.2 Compatibilidade

A SDK Reference 7.2 informa, em essência, que o VirtualBox procura manter compatibilidade da Main API
**dentro de uma major release**.

Isso torna a Main API um contrato muito mais explícito que as rotas internas do frontend do Home
Assistant.

---

# 12. `VBoxManage` e `vboxwebsrv`

`VBoxManage` é um frontend oficial de primeira classe da Main API.

Para automação **local**, o instalador pode usar:

```text
VBoxManage
```

sem precisar subir o serviço web.

## `vboxwebsrv`

A documentação oficial o apresenta para controle remoto via web service.

Portanto:

```text
orquestração local via VBoxManage → vboxwebsrv não é necessário
```

Evitar a expressão “peso morto” no contrato; prefira “dependência desnecessária para este desenho”.

---

# 13. VirtualBox — rótulo da GUI ≠ argumento CLI

Esta regra do rascunho está correta e deve permanecer como política central.

**[POLÍTICA]**

Nenhum rótulo visto no wizard deve ser convertido em argumento de CLI apenas por semelhança textual.

O instalador deve validar contra:

1. documentação da release;
2. `VBoxManage --help` / subcommand `--help`;
3. probes do próprio binário;
4. quando necessário, código-fonte oficial.

---

# 14. Apple Silicon — arquitetura da VM

Fonte oficial VirtualBox 7.2 User Manual.

`createvm` oferece:

```text
--platform-architecture=x86|arm
```

e a arquitetura da plataforma é obrigatória ao criar a VM.

Para Apple Silicon:

```bash
VBoxManage createvm \
  --name "<VM>" \
  --platform-architecture arm \
  --register
```

**[PUBLIC-DOC]** A necessidade de informar a arquitetura está documentada.

---

# 15. Guest OS type — Oracle Linux ARM64

A documentação de instalação do Home Assistant manda selecionar, no wizard:

```text
Type: Linux
Subtype: Oracle Linux
Version: Oracle Linux (ARM 64-bit)
```

Entretanto, o instalador CLI não deve transformar esse label em ID apenas por inferência.

## 15.1 Probe documentado

O VirtualBox fornece `VBoxManage list ostypes` para listar os IDs válidos.

Portanto a estratégia robusta é:

```text
1. consultar ostypes do binário instalado;
2. localizar a entrada Oracle Linux ARM64;
3. usar o ID devolvido pelo próprio runtime;
4. falhar se o ID esperado não existir.
```

### Sobre `Oracle_arm64`

O código-fonte oficial do VirtualBox possui a definição ARM64 de Oracle Linux, e o ID usado no
ambiente testado pode ser `Oracle_arm64`.

Mas, para um **contrato de instalador**, o valor não deve ser hard-coded sem probe:

```bash
VBoxManage list ostypes
```

ou a variante de filtro suportada pela release instalada.

### Classificação

```text
rótulo “Oracle Linux (ARM 64-bit)” → PUBLIC-DOC
ID CLI exato                          → PROBE DO BINÁRIO
```

---

# 16. EFI / UEFI

Home Assistant exige UEFI para boot da VM.

Fonte oficial HA:

- https://www.home-assistant.io/installation/macos/

VirtualBox fornece configuração de firmware por `modifyvm`.

Forma usada:

```bash
VBoxManage modifyvm "<VM>" --firmware efi
```

Classificação:

```text
requisito UEFI   = PUBLIC-DOC Home Assistant
opção CLI EFI    = PUBLIC-DOC VirtualBox
```

---

# 17. VirtioSCSI — atenção a DOC-GAP

Home Assistant, para Apple Silicon, manda configurar:

```text
Controller: VirtioSCSI
```

Fonte:

- https://www.home-assistant.io/installation/macos/

O User Manual 7.2 também descreve VirtIO SCSI para VMs ARM.

Entretanto há uma inconsistência importante na documentação textual do `storagectl`:

- a documentação reconhece VirtIO SCSI;
- a sinopse publicada de `storagectl --add` não enumera `virtio-scsi` de forma consistente;
- o código oficial do frontend `VBoxManageStorageController.cpp` aceita os aliases
  `virtio-scsi`/`virtio` para o bus correspondente.

Código oficial:

- https://github.com/VirtualBox/virtualbox/blob/main/src/VBox/Frontends/VBoxManage/VBoxManageStorageController.cpp

### Classificação

```text
Controller VirtioSCSI necessário no Apple Silicon = PUBLIC-DOC
CLI `storagectl --add virtio-scsi`                 = SOURCE + RUNTIME-PROBE
sinopse 7.2                                       = DOC-GAP
```

### Regra do instalador

Antes de usar:

```bash
VBoxManage storagectl ... --add virtio-scsi
```

validar no binário instalado:

```bash
VBoxManage storagectl --help
```

ou executar um contract test descartável.

Isso é especialmente importante porque a documentação 7.2 e a implementação não estão perfeitamente
alinhadas nessa opção.

---

# 18. `storageattach`, SSD/discard e Apple Silicon

A página oficial do Home Assistant mostra a configuração opcional para permitir reclaim de espaço:

```bash
VBoxManage storageattach <VM name> \
  --storagectl "SATA" \
  --port 0 \
  --device 0 \
  --nonrotational on \
  --discard on
```

E determina que, no Apple Silicon, seja substituído:

```text
SATA
```

por:

```text
VirtioSCSI
```

Fonte:

- https://www.home-assistant.io/installation/macos/

### Formulação correta

Não dizer genericamente que é “o único comando de terminal de toda a fonte include”.

Dizer:

> **É o comando `VBoxManage` apresentado na página macOS renderizada para habilitar non-rotational/discard e permitir reclaim de espaço.**

Isso evita depender de números de linha e de branches condicionais do include compartilhado.

---

# 19. Temas — não dependem de HACS

**Evidência:** `PUBLIC-DOC`

Fonte oficial:

- https://www.home-assistant.io/integrations/frontend/

A afirmação principal do rascunho está correta.

Temas são recurso nativo da integração:

```text
frontend
```

e podem ser definidos em YAML.

Exemplo:

```yaml
frontend:
  themes: !include_dir_merge_named my_themes
```

A documentação também suporta formas como:

```yaml
frontend:
  themes: !include themes.yaml
```

ou temas inline.

## 19.1 Aplicação e reload

A documentação oficial cobre:

```text
perfil do usuário
frontend.set_theme
frontend.reload_themes
```

## 19.2 HACS

A página oficial de `frontend` não estabelece HACS como requisito para temas.

Portanto:

```text
HACS = canal opcional de distribuição/gerência de conteúdo community
HACS != pré-requisito técnico para o mecanismo nativo de themes
```

### Correção editorial

Evitar usar “o documento tem N linhas” ou “ZERO menções” como parte do contrato.
Contagem de linhas é frágil e não agrega compatibilidade.

O fato contratual é simplesmente:

> A documentação oficial ensina configuração nativa de temas sem exigir HACS.

---

# 20. HAOS em macOS — documentação oficial

**Evidência:** `PUBLIC-DOC`

Fonte:

- https://www.home-assistant.io/installation/macos/

A página oficial renderizada foi conferida em 2026-08-23.

---

## 20.1 Recursos mínimos

A página especifica:

```text
RAM mínima: 2 GB
vCPU mínimo: 2
```

e orienta dimensionamento de acordo com a carga esperada.

**Status:** ✅ correto.

---

## 20.2 Apple Silicon — guest type

A página orienta:

```text
Type: Linux
Subtype: Oracle Linux
Version: Oracle Linux (ARM 64-bit)
```

**Status:** ✅ correto.

---

## 20.3 EFI

A página diz que Home Assistant requer UEFI para boot.

Configuração no wizard:

```text
Enable EFI
```

**Status:** ✅ correto.

---

## 20.4 Storage controller

Para Apple Silicon:

```text
Controller: VirtioSCSI
```

**Status:** ✅ correto.

---

## 20.5 Rede e Wi‑Fi

A documentação orienta usar:

```text
Bridged Adapter
```

e, se o computador usa Wi‑Fi, selecionar o adaptador Wi‑Fi.

Formulação correta:

> **A página oficial aceita bridge sobre o adaptador Wi‑Fi do host no fluxo descrito.**

**Status:** ✅ correto.

---

## 20.6 Disk reclaim

A página mostra `storageattach` com:

```text
--nonrotational on
--discard on
```

e explica que o VirtualBox não reclaim espaço não utilizado por padrão nesse cenário.

No Apple Silicon, o nome do storage controller deve ser `VirtioSCSI`.

**Status:** ✅ correto.

---

## 20.7 Acesso após boot

A página orienta acessar:

```text
http://homeassistant.local:8123
```

ou o endereço IP da VM quando o hostname não estiver disponível.

**Status:** ✅ correto.

---

## 20.8 UTM

A página menciona UTM como alternativa quando VirtualBox não é suportado/adequado no host, porém não
fornece nessa página um procedimento completo equivalente ao walkthrough do VirtualBox.

**Status:** ✅ correto.

---

# 21. Alegação removida: “primeiro boot baixa o Core da internet”

O rascunho atribuía à página macOS:

> “Primeiro boot baixa o Core da internet — a espera é longa.”

Essa frase pode aparecer em conteúdo compartilhado/branches do source include, mas **não foi
confirmada como conteúdo da página macOS renderizada que constitui a fonte citada**.

Para um documento de contrato rigoroso:

```text
REMOVER essa afirmação desta seção.
```

Ela só deve voltar se houver fonte oficial diretamente aplicável ao fluxo HAOS/macOS 18.2 que
declare esse comportamento.

### Motivo

O objetivo aqui não é decidir se o comportamento é tecnicamente plausível.
O objetivo é que **cada dependência do instalador seja sustentada pela fonte que o documento diz
sustentá-la**.

---

# 22. Resumo das correções aplicadas ao rascunho

| Item | Rascunho | Verificação |
|---|---|---|
| REST | “20 endpoints” | ✅ conteúdo bate; renomeado para **20 combinações método+caminho** |
| Calendar REST | caminho sem query | ⚠️ corrigido com `start` e `end` |
| Escopo REST | “ler estado/chamar serviços” | ⚠️ ampliado; REST faz mais operações de runtime |
| Config flow via REST pública | não existe | ✅ correto |
| WebSocket | “21 comandos” | ❌ contador/termo inadequado; `auth` é auth phase e `pong` é resposta |
| `homeassistant/expose_entity` | implicitamente leitura | ⚠️ é mutação documentada |
| `/auth/token` | API privada | ❌ **é Authentication API documentada** |
| `client_id` | “URL canônica IndieAuth” | ⚠️ regra refinada conforme auth docs |
| `/auth/login_flow` | login usuário/senha | ⚠️ é auth-provider/MFA flow interno; username/password é um caso |
| Compatibilidade HA interna | “nenhuma deprecation policy” como fato | ⚠️ transformado em **política cautelosa do instalador** |
| Config entries | endpoints | ✅ confirmados no Core 2026.8.3 |
| `ignore_flow` | exige flow ativo | ⚠️ também exige `title`, `unique_id` e autorização |
| Onboarding | users/core_config/analytics/integration | ✅ confirmados no Core 2026.8.3 |
| Backup | colocado sob onboarding | ❌ movido para componente **Backup** |
| `backup/info` | sem protocolo explícito | ⚠️ WebSocket |
| `/api/backup/upload` | misturado com WS | ⚠️ HTTP POST |
| `backup/restore` | sem protocolo explícito | ⚠️ WebSocket |
| `/api/hassio/*` | “recusa token de usuário” | ❌ generalização removida; proxy é allowlistado |
| Main API VirtualBox | GUI/VBoxManage como frontends | ✅ substância correta |
| “GUI sem privilégio” | absoluto | ⚠️ reformulado como ausência de API funcional oculta |
| `vboxwebsrv` local | desnecessário | ✅ correto para orquestração local via VBoxManage |
| `createvm --platform-architecture arm` | obrigatório | ✅ documentado |
| `Oracle_arm64` | hard-coded a partir do label | ⚠️ preferir probe `list ostypes` |
| `--firmware efi` | tradução da GUI | ✅ documentado |
| `--add virtio-scsi` | argumento | ⚠️ implementação aceita; existe **DOC-GAP** no manual 7.2; testar binário |
| Themes sem HACS | nativo | ✅ correto |
| macOS 2GB/2vCPU | mínimo | ✅ correto |
| macOS Oracle Linux ARM64 | seleção | ✅ correto |
| macOS UEFI | obrigatório | ✅ correto |
| macOS VirtioSCSI | Apple Silicon | ✅ correto |
| macOS Wi‑Fi | bridge por adaptador Wi‑Fi | ✅ correto |
| macOS discard/nonrotational | comando mostrado | ✅ correto |
| `homeassistant.local` | acesso | ✅ correto |
| UTM | alternativa citada | ✅ correto |
| “primeiro boot baixa Core” | atribuído à página macOS | ❌ removido por falta de suporte na página renderizada |

---

# 23. Contrato mínimo recomendado para o arnês

O arquivo de máquina derivado deste documento deveria representar cada dependência com algo
equivalente a:

```yaml
- id: config_entries_start_flow
  product: home_assistant_core
  reference_version: 2026.8.3
  stability: source_pinned
  protocol: http
  method: POST
  path: /api/config/config_entries/flow
  auth: admin
  required:
    handler: string
  source:
    type: github_tag
    url: https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/config/config_entries.py
  verify:
    - response_has: type
    - response_has_any: [flow_id, result]
```

Para um item público:

```yaml
- id: ha_rest_services
  product: home_assistant_core
  reference_version: 2026.8.3
  stability: public_documented
  protocol: http
  method: GET
  path: /api/services
  source:
    type: official_docs
    url: https://developers.home-assistant.io/docs/api/rest/
```

Para um item com gap de documentação:

```yaml
- id: vbox_virtioscsi_add
  product: virtualbox
  reference_version: 7.2.16
  stability: runtime_probe_required
  cli:
    subcommand: storagectl
    argument: "--add virtio-scsi"
  source_status: doc_gap
  preflight:
    - VBoxManage storagectl --help
```

---

# 24. Princípios de manutenção

## 24.1 Não testar só status HTTP

Para rotas internas, validar também pós-condição.

Exemplo:

```text
iniciar config flow
    ↓
HTTP 200 não basta
    ↓
flow_id/result precisa ser estruturalmente válido
```

## 24.2 Não usar contagens como contrato quando nomes bastam

Evitar:

```text
“21 comandos WS”
```

Preferir:

```text
“dependemos destes types: [...]”
```

Assim a inclusão de um novo comando oficial não quebra o contrato sem necessidade.

## 24.3 Não hard-codear enum de CLI quando o fabricante oferece probe

Para VirtualBox:

```text
VBoxManage list ostypes
VBoxManage <subcommand> --help
```

devem ser preferidos a inferências a partir do rótulo da GUI.

## 24.4 Pin de versão para APIs internas

Para Home Assistant:

```text
Core 2026.8.3
```

deve apontar sempre para URLs de source tag `2026.8.3`, nunca para `dev`/`master`.

## 24.5 Separar “documentado” de “funciona hoje”

```text
documentado publicamente
!=
presente no source
!=
observado no ambiente
```

As três evidências têm valores distintos e devem permanecer distintas no banco do instalador.

---

# 25. Fontes oficiais verificadas

## Home Assistant — External APIs

REST:

- https://developers.home-assistant.io/docs/api/rest/

WebSocket:

- https://developers.home-assistant.io/docs/api/websocket/

Authentication:

- https://developers.home-assistant.io/docs/auth_api/

Supervisor:

- https://developers.home-assistant.io/docs/api/supervisor/endpoints/

---

## Home Assistant — Core 2026.8.3 source

Auth login flow:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/auth/login_flow.py

Config entries/config flows:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/config/config_entries.py

Onboarding:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/onboarding/views.py

Backup HTTP:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/backup/http.py

Backup WebSocket:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/backup/websocket.py

Hassio/Supervisor proxy:

- https://github.com/home-assistant/core/blob/2026.8.3/homeassistant/components/hassio/http.py

---

## Home Assistant — user documentation

macOS / HAOS VM:

- https://www.home-assistant.io/installation/macos/

Frontend/themes:

- https://www.home-assistant.io/integrations/frontend/

---

## Home Assistant OS 18.2

Release:

- https://github.com/home-assistant/operating-system/releases/tag/18.2

Apple Silicon VDI:

- https://github.com/home-assistant/operating-system/releases/download/18.2/haos_generic-aarch64-18.2.vdi.zip

---

## Oracle VirtualBox 7.2.16

Release directory:

- https://download.virtualbox.org/virtualbox/7.2.16/

SDK Reference:

- https://download.virtualbox.org/virtualbox/7.2.16/SDKRef.pdf

User Manual:

- https://download.virtualbox.org/virtualbox/7.2.16/UserManual.pdf

Oracle VirtualBox 7.2 documentation:

- https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/

Storage controller implementation:

- https://github.com/VirtualBox/virtualbox/blob/main/src/VBox/Frontends/VBoxManage/VBoxManageStorageController.cpp

> **Nota:** para comportamentos de CLI em que a documentação 7.2 apresenta lacuna, o contrato final
> deve ser fechado pelo próprio binário 7.2.16 instalado (`--help`/probe), e não apenas pelo branch
> corrente do mirror de source.

---

# 26. Veredito

O rascunho original estava **majoritariamente bem fundamentado**, mas ainda não era seguro como
contrato rígido de um instalador sem as correções acima.

As correções mais importantes são:

1. mover `/auth/token` para a **Authentication API pública**;
2. não chamar a lista WebSocket de “21 comandos”;
3. separar Backup de Onboarding;
4. completar o contrato de `config_entries/ignore_flow`;
5. remover a generalização de que `/api/hassio/*` rejeita qualquer user token;
6. tratar `Oracle_arm64` por probe do runtime em vez de inferência do label;
7. marcar `virtio-scsi` como **DOC-GAP + runtime probe**;
8. remover da seção macOS a alegação “primeiro boot baixa o Core” enquanto a fonte citada não a
   sustentar diretamente.

Com essas correções, este documento pode servir como **referência humana verificada** para gerar o
arquivo de contrato do arnês.
