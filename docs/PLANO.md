# PLANO do instalador — aprovado em 2026-08-23

> Movido da raiz em 2026-08-24 (layout navblue: engenharia vive em `docs/`).
> O estado vivo da frente está no HANDOFF mais novo de `docs/roadmap/`.

# PLANO — `haos-install.sh` · v6

> **APROVADO em 2026-08-23.** v5 foi corrigida por ele em 12 pontos. O nº 12 mudou a moldura:
> **isto NÃO é migração. É setup novo.** Toda semântica de migração sai do plano.
> Repositório: **https://github.com/aleonnet/haos-mac-mini** · Licença: **MIT**.
> Aprovado por ele em 23/08/2026.

---

## 1. Contexto

Instalador de Home Assistant OS numa VM VirtualBox em Mac Apple Silicon. **Um propósito, não
dois:** uma ferramenta pública para a comunidade HAOS+Mac, que o dono também usa para montar
o HAOS do Mac mini dele.

O Raspberry Pi CM4 que roda HA hoje **não é origem de nada**. O inventário lido dele foi
**cardápio** para montar o catálogo — esse trabalho já está feito. **Não há migração, não há
coexistência, não há rollback para o Pi, não há backup a restaurar.** As cenas, os dispositivos
e as entidades **nascem das integrações** quando o HAOS subir.

### 1.1 O que a decisão "setup novo" apaga do plano

| saía do plano | por quê |
|---|---|
| portão de F1 *"backup do Supervisor não confirmado"* | não há instância anterior a preservar |
| `--resume`/`RUNBOOK` com **rollback para o Pi** | o rollback é `--uninstall`, e só |
| coexistência de duas instâncias · `.15` transitório · herança do `.10` | eram mecânica de migração |
| *"75 cenas não migram"* como consequência aceita | **erro meu** — cenas vêm das integrações |
| `INVENTARIO.md` como fonte normativa | cumpriu o papel de cardápio; sai da lista |
| 3 dos 4 acoplamentos com a frente do cutover (R6) | eram sobre janela de migração |
| `--migrate-from`, detecção de instância preexistente | não existe |

**Sobra um acoplamento real com o cutover, e é genérico:** se a internet estiver fora, os
config flows de nuvem (`tuya`, `smartthings`, `cast`) falham de forma indistinguível de
credencial errada. Vira **checagem de conectividade na F1**, não regra de janela.

O endereçamento transitório e a herança de IP eram mecânica de coexistência. Sem migração,
não existem. A VM pega o endereço que a rede der; o instalador é transparente a IP.

---

## 2. Fontes normativas, em precedência

| # | documento | papel |
|---|---|---|
| 1 | `docs/API-REFERENCE_20260823_verificado.md` (1.655 l.) | contrato de API |
| 2 | `docs/homeassistant_installer_tiers_curadoria_2026-08-23.md` (1.456 l.) | tiers e schema |
| 3 | `CLAUDE.md` | convenções — **e está caduco, ver §8** |
| 4 | `docs/base_tarifaria_RJ_home_assistant.md` (2.105 l.) | regras do pacote `casa ABHOME` |
| 5 | `mac_env_install.sh` (3.390 l.) | estrutura, não aparência |

Saem da lista: `INVENTARIO.md`/`inventario/` (cardápio cumprido, e `.gitignore`d);
`PROXIMO-PROMPT.md` (**rascunho meu**, não especificação dele — ver §3);
`ARQUITETURA` (rede é assunto dele, não do instalador).

---

## 3. Decisões dele nesta rodada

| # | decisão |
|---|---|
| 1 | `studio_code_server` **não volta** — a pergunta caiu junto com o item 5 |
| 2·4 | `custos` e `cameras` viram **um pacote `casa ABHOME`** |
| 3 | **A taxonomia A/B/C/D/E sai.** Era invenção minha num rascunho meu que a banca leu como especificação dele. E duplica pior o que `setup_sources` + `requires` já dizem |
| 5 | `--all` **sem HACS**. Os dois scripts Tapo **saem do instalador** — ele os executa à parte |
| 6 | O Mac mini tem Ethernet: para ele, não-problema. O portão só machuca o produto público |
| 7 | **Boot automático entra**, com autorização pedida ao usuário. **Passthrough de USB entra** |
| 8 | **MIT** |
| 10 | Sem BLE hoje, mas o **passthrough de USB/Bluetooth/BLE deve ser possível** |
| 11 | Não migra estado do Pi, então não migra defeito. Questão dissolvida |
| 12 | **Setup novo, não migração** — ver §1.1 |

### 3.1 A cascata do item 5

Os dois scripts Tapo fora do instalador derrubam uma cadeia inteira:

```
tapo_tls_fix sai  →  ninguém precisa de `docker exec` dentro do HAOS
tapo_ptz_overlay sai  →  a categoria `cameras` desaparece
                      →  some metade do dominó da F7
```

**`advanced_ssh_web_terminal` FICA — decisão dele.** Não pelo `docker exec`, que saiu, mas
por ser superior ao oficial e por ser necessário eventualmente. Consequências que continuam
valendo e precisam de passo próprio:

- **F7 tem passo explícito de adicionar o repositório de terceiro** (`hassio-addons`) via API
  do Supervisor, com a URL declarada — é o R8, que não caducou.
- **O `NAO_APLICA_DB` mantém a regra revista:** preferir o oficial **quando o oficial cobre a
  necessidade**. `ssh_server` oficial fica fora por não cobrir; `studio_code_server` fica fora
  porque `configurator` + `samba` cobrem edição.
- Para uma ferramenta pública, instalar de repositório de terceiro **por padrão** é decisão
  registrada, não detalhe de implementação.

---

## 4. O catálogo

**Categorias — 6** (`cameras` sai; `custos` vira `casa_abhome`):
`vanilla` · `conectado` · `casa` · `ferramentas` · `casa_abhome` · `extensoes`

**`VANILLA_DB` — 30:** `default_config` (24) + `hassio`/`analytics` + onboarding
(`google_translate`, `met`, `radio_browser`, `shopping_list` — confirmados no source do Core
2026.8.3, `_verificado` §7.4).

**Colunas do `ITEM_DB`**, com o que a banca exigiu de volta:

```
id | slug | cat | rotulo | origem | padrao | discovery_sources | setup_sources
   | preferred | requires | condicao | single_entry | quality_scale | analytics_pct
```

- **`slug`** (P6) — os reais são `configurator`, `samba`, `ssh`; sem isso a F7 não nomeia o que instala
- **`padrao` (1/0)** (R10) — sem ele, marcar `casa` marca **tudo** em `casa`
- **`condicao`** (R16) — predicado avaliável, não texto perdido
- **`single_entry`** (P4) — em **4** itens: `mqtt`, `thread`, `cast`, `systemmonitor`
- **`quality_scale` / `analytics_pct`** (P9) — a curadoria dá fonte; eu os tinha cortado em silêncio
- **sem** `default_policy` (vocabulário sem fonte) e **sem** `classe` A/B/C/D/E (decisão 3)

**Correções de dado da banca, já aplicadas:**

| item | correção |
|---|---|
| `hue` | `setup_sources: zeroconf homekit user` — com só `user`, a cerca da F8 **reprovava instalação bem-sucedida** (P3) |
| `mqtt` | `discovery: hassio` no HAOS (`after_dependencies: [hassio]`, P12) · `requires: mosquitto` (P7) |
| `thread` | `requires: openthread_border_router` + rádio (P7) |
| `esphome` | **dois** caminhos, não três — `dhcp: registered_devices` é refresh de IP, não descoberta (P10) |
| `smartthings` | `requires: application_credentials` = **OAuth**, não PAT (P11) · `quality_scale: bronze` |
| **`workday`** | **item novo** — sem ele o `energia_br` nunca troca de posto tarifário (R3) |
| ferramentas | `advanced_ssh_web_terminal` **fica** (decisão dele) · `configurator` · `samba` · `ssh_server` oficial fora, por não cobrir |

---

## 5. Fases

| # | fase | nota |
|---|---|---|
| F0 | preâmbulo | `${BASH_SOURCE[0]:-$0}` em todo lugar (O1) |
| F1 | pré-voo read-only | portões: não-Apple-Silicon · `VBoxManage` ausente · **versão/capacidade do VBox** (O7) · **`python3`** (O6) · disco · conectividade externa. **RAM e Wi-Fi viram aviso** |
| F2 | seleção | `--dry-run` e `--list` saem **antes** dos portões de recurso (R5) |
| F3 | imagem | SHA-256 antes de descompactar |
| F4 | VM | `--ostype` por **probe** (`list ostypes`), não hard-code · MAC **com o que vier**, e **impresso** (R13) |
| F5 | boot e espera | verifica o lease — é aqui que a bridge sobre Wi-Fi se prova ou não |
| **F5b** | **auto-start** | **LaunchAgent do usuário** → `VBoxManage startvm <vm> --type headless` no login. Sem senha de admin. `--uninstall` remove |
| F6 | onboarding | consentimento de analytics perguntado |
| F7 | add-ons | `ssh` · `configurator` · `samba` · `mosquitto`/`otbr` quando exigidos |
| F8 | integrações | cerca: `source ∈ setup_sources` |
| F9 | pacote `casa ABHOME` | packages BR, com `source:` **parametrizado** da entry do Shelly (R3) |
| F10 | relatório | imprime o MAC e o endereço de acesso |

**USB passthrough**: `VBoxManage usbfilter add` para dongle Zigbee/BLE/Thread. O **Extension
Pack do VirtualBox é instalado junto**, na F1 — versão casada com a do VirtualBox instalado,
verificada por SHA-256 antes de `extpack install`.

---

## 6. O que pode custar funcionalidade

| risco | como evitar |
|---|---|
| **F7 — instalar add-on** | continua sendo o passo 0: medir qual path deu 401 e se está na allowlist. Mas **encolheu muito** — sem os Tapo, sem `docker exec`, sem repositório de terceiro |
| **bridge sobre Wi-Fi** | portão **suave** + prova empírica na F5. Para ele, não-problema: o Mac mini tem Ethernet |
| **`--upgrade` sobre arquivo editado** | marcadores de região, como `# Fim da Configuração` da referência (`:2270`) |

---

## 7. Correções pendentes da banca que continuam valendo

- **O1** `${BASH_SOURCE[0]:-$0}` — hoje o `curl \| bash` morre na linha 2
- **O2** teste de TTY por `( : </dev/tty )`, não por stdin
- **O9** nenhum `lib/*.sh` instala `trap` no topo — `haos-ui.sh:90` apaga o `cleanup` do instalador
- **O24** demo sai da biblioteca para `tools/ui-demo.sh`
- **O5/O4b** fórmula de RAM e detecção de meio físico da interface
- **O14** `--force` com semântica única · **O17** matriz de precedência de modos
- **O10** token em `install -m 0600`, revogado no `--uninstall`
- **R11/R17** preservar edição do usuário; `configuration.yaml` é edição linha-a-linha
- **R27** dados de fatura dele saem para arquivo local
- **R12** estado do `--resume` com caminho e filtragem de ids

---

## 7A. Manutenção do script frente a HA e VirtualBox

O plano tinha `--self-update` (canal) e `--upgrade` (artefatos), e **não tinha o mecanismo que
detecta que é preciso atualizar**. A banca não pegou. Três camadas, da mais barata à mais cara.

### Camada 1 — probe em runtime: sobrevive sem edição nenhuma

O que se descobre do binário não quebra quando o fabricante muda:

| em vez de fixar | probe |
|---|---|
| `--ostype Oracle_arm64` | `VBoxManage list ostypes` e usar o ID devolvido |
| `storagectl --add virtio-scsi` | `VBoxManage storagectl --help` antes de usar (é `DOC-GAP` declarado) |
| nome da interface de bridge | `VBoxManage list bridgedifs` |
| versão do Extension Pack | casada com `VBoxManage --version` no momento |

**Atualização do VirtualBox, na prática, não exige mexer no script** — é para isso que o
`_verificado` §13 e §24.3 mandam preferir probe a enum fixo.

### Camada 2 — arnês de contrato: detecta a quebra do HA sozinho

O lado do HA é o frágil: `config_entries`, `onboarding`, `ignore_flow` e o proxy `hassio` são
**`SOURCE-PINNED`** — existem no Core mas não têm promessa de compatibilidade. O
`_verificado` §10 e §23 **já especificam o arnês** e eu não o pus como entregável:

```yaml
- id: config_entries_start_flow
  reference_version: 2026.8.3
  stability: source_pinned
  protocol: http
  method: POST
  path: /api/config/config_entries/flow
  auth: admin
  required: { handler: string }
  verify:
    - response_has: type
    - response_has_any: [flow_id, result]
```

Um arquivo desses por dependência, com `postcondition` e `rollback_or_failure_behavior`.

**O CI roda o arnês contra duas versões:** a fixada (`2026.8.3`) e a **`latest`** do HA. É o
que transforma *"descobrimos quando um usuário reclama"* em *"o CI fica vermelho no dia em que
o HA publica"*. `_verificado` §24.1: **não testar só status HTTP** — validar a pós-condição.

### Camada 3 — release do script: só quando o contrato quebra

- **Versão de referência fixada** no cabeçalho; **SemVer** no script.
- **Matriz de compatibilidade no README**: qual versão do instalador cobre quais faixas de
  HA Core, HAOS e VirtualBox.
- Bump quando o arnês acusa deriva, ou quando se quer capacidade nova. **Não** a cada release.
- `--doctor` compara a versão de referência do script com a instalada e **avisa** quando a
  distância for grande — sem bloquear.

### O que envelhece por fora do contrato

| artefato | gatilho | quem detecta |
|---|---|---|
| imagem HAOS (`18.2`) | novo release muda URL e SHA | tabela versionada + CI que confere o link |
| catálogo (integrações, manifests, adoção) | release do Core | curadoria §21-22 — **frente própria**, não o instalador |
| tarifas do `casa ABHOME` | fim de vigência | o próprio package já alerta |

---

## 8. `CLAUDE.md` — correções AUTORIZADAS, a aplicar na execução

Ele autorizou (*"CLAUDE.md está maluco, corrija"*). A banca achou **seis** pontos caducos:

| linha | está | deve ser |
|---|---|---|
| `:107` | *"Sem cores ANSI em nenhum script deste monorepo"* | exceção declarada para o instalador público, que degrada corretamente fora de TTY |
| `:10-14` | três subprojetos | **quatro** — falta `ABHOME-haos-macmini/` |
| `:16` | *"próxima frente… ainda não iniciada"* | iniciada, com repositório próprio |
| `:92-94` | *"não é repositório git, não existe `.git` nem `.gitignore`"* | falso no subprojeto: `.git`, 5 commits, `.gitignore` ativo |
| `:95` | *"não existe lint, CI"* | o plano exige `shellcheck` e CI |
| `:395` | *"`NET-001` … `NET-015`"* | `NET-016` existe |

**E o ponteiro (R1):** `grep -rn "ABHOME-haos-macmini"` em `CLAUDE.md`, `README.md`,
`PROXIMO-PROMPT.md` e `ARQUITETURA` devolve **zero**. Pela regra dele, o subprojeto não
existe. Quatro inserções, no passo 2 da ordem.

---

## 9. Ordem de construção

| # | entrega |
|---|---|
| 0 | medir o 401 do `/api/hassio/` — decide se a F7 existe |
| 1 | corrigir `CLAUDE.md` (§8) e criar os ponteiros |
| 2 | fechar `async_step_user` nos `config_flow.py` |
| 3 | aplicar §4 no `catalog.bash`; reescrever `ESTADO.md:30-31` na mesma tarefa |
| 4 | `verify.sh` + CI — schema **e** conteúdo · **arnês de contrato (§7A) contra `2026.8.3` e `latest`** |
| 5 | esqueleto F0–F2, testado **por stdin** |
| 6 | F3–F4–F5–F5b e o inverso de cada uma |
| 7 | `--doctor` · `--uninstall` sobre manifesto de artefatos |
| 8 | F6 · F7 ou degradação · F8 · F9 · F10 |
| 9 | `RUNBOOK.md` público (rollback = `--uninstall`) |

---

## 10. Verificação

| o quê | como |
|---|---|
| execução por stdin | `cat haos-install.sh \| bash -s -- --help` — `bash -n` e `shellcheck` não pegam o O1 |
| contaminação de biblioteca | após carregar `lib/*.sh`, conferir `trap -p EXIT`, `set -o`, cursor |
| schema do catálogo | `verify.sh` compara schema, não só conteúdo |
| zona de usuário | editar `source:` do `utility_meter`, rodar `--upgrade`, confirmar que **não** voltou o placeholder |
| regionalidade | locale não-BR não vê nada do `casa ABHOME` |
| **auto-start** | reiniciar o Mac e confirmar que a VM sobe headless sozinha |
| idempotência | 2 runs: a 2ª reporta `100` em tudo |
| rollback | matar em cada fase; o inverso devolve ao estado anterior |
| MAC | F10 imprime |

---

## 11. Estado do processo

| passo | estado |
|---|---|
| 1. Plano | ✅ v6 |
| 2. Banca — 3 lentes | ✅ ~80 achados, 19 bloqueadores |
| 3. Correção | ✅ v5 e v6 |
| 4. Apresentar para aprovação | ⏳ |
| 5. Executar | ⏳ |
