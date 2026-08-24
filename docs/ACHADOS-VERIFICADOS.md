# Achados verificados — referência de engenharia

> Extraído do antigo `ESTADO.md` da raiz em 2026-08-24, limpo para o repositório
> público. O ESTADO (onde parei, próximos passos) vive nos HANDOFFs de
> `docs/roadmap/`; AQUI ficam só os fatos medidos que custam caro se esquecidos.

## 🔴 NÃO é migração. É setup novo.

O Home Assistant que roda hoje num Raspberry Pi CM4 **não é origem de nada**. O inventário
lido dele foi **cardápio** para montar o catálogo, e esse trabalho está feito.

**Não existe:** coexistência de instâncias · rollback para o Pi · backup a restaurar ·
`.15` transitório · herança do `.10` · `--migrate-from`. Cenas, dispositivos e entidades
**nascem das integrações** quando o HAOS subir.

*(Uma sessão anterior tratou isto como migração e contaminou o plano inteiro. Se algum
documento ainda falar em migrar, ele está caduco — corrija.)*

## Decisões fechadas — não reabrir

| # | decisão |
|---|---|
| 1 | Instância nova, montada de propósito. **Não é clone, não é migração** |
| 2 | **VirtualBox**, Apple Silicon. Fundamentado: é o único caminho documentado pelo HA, e a 7.2.16 lista host ARM sem ressalva de preview. UTM é o plano B nomeado pela própria doc |
| 3 | Interface **en-US + pt-BR**, pelo locale do Mac |
| 4 | Script **autocontido**, `curl \| bash`, com as tabelas embutidas |
| 5 | `catalog/catalog.bash` é a **fonte de verdade**; o script embute cópia e o **CI compara** |
| 6 | Núcleo em **bash 3.2**; Python só onde bash não alcança |
| 7 | **HACS ofertado, nada de dentro dele.** E **fora do `--all`** |
| 8 | **Os dois scripts Tapo saem do instalador** — ele os executa à parte |
| 9 | **`advanced_ssh_web_terminal` fica** (superior ao oficial). Exige passo de adicionar repositório de terceiro |
| 10 | `custos` e `cameras` viram **um pacote `casa ABHOME`**, isolado e condicional |
| 11 | **A taxonomia A/B/C/D/E foi descartada** — era invenção minha; `setup_sources` + `requires` já dizem melhor |
| 12 | **Boot automático no login** (LaunchAgent, headless) e **passthrough de USB** entram. Extension Pack instalado junto |

## ✅ Passo 0 — RESOLVIDO em 23/08/2026, medido na instância real

Era o maior risco do plano: se nenhuma rota instalasse app, caíam **5 das 7 categorias**.

**O proxy REST `/api/hassio/*` está fechado.** Token de usuário **confirmado admin**
(`GET /api/config/config_entries/entry` → 200). **9 caminhos testados, todos 401:**
`supervisor/info` · `core/info` · `addons` · `store` · `store/addons` · `host/info` ·
`os/info` · `network/info` · `addons/core_ssh/info`. O `/api/hassio/` sem path dá 404.
*(Isto refuta a hipótese de que só um caminho específico recusava — recusa tudo.)*

**O comando WebSocket `supervisor/api` FUNCIONA** com o mesmo token:

```
{"type":"supervisor/api","endpoint":"/addons","method":"get"}   → OK
{"type":"supervisor/api","endpoint":"/supervisor/info",...}     → OK
{"type":"supervisor/api","endpoint":"/store","method":"get"}    → OK  (80 apps, 5 repos)
```

`hassio/addons` → `unknown_command`. **`supervisor/api` é a rota, e é única.**
Confirma a decisão #6: bash não fala WebSocket, então o auxiliar Python é obrigatório —
e `python3` vira **portão da F1**, não descoberta na F7.

### Slugs reais, lidos do store da instância

**O slug é `<repo>_<app>`, não o nome curto** — o plano estava errado:

| o plano dizia | slug real | nome na tela | instalado |
|---|---|---|---|
| `configurator` | `core_configurator` | File editor | não |
| `samba` | `core_samba` | Samba share | **sim** |
| `ssh` | `core_ssh` | Terminal & SSH | não |
| — | `core_mosquitto` | Mosquitto broker | não |
| — | `core_matter_server` | Matter Server | **sim** |
| — | `core_openthread_border_router` | OpenThread Border Router | não |
| `advanced_ssh_web_terminal` | **`a0d7b954_ssh`** | Advanced SSH & Web Terminal | **sim** |

🔴 **`a0d7b954` é hash da URL do repositório, não constante.** O instalador tem de
**adicionar o repositório e descobrir o slug resultante** — nunca fixá-lo. Repositórios
configurados na instância: `local`, `core`, `a0d7b954` (Community Apps), `5c53de3b`
(ESPHome), `d5369777` (Music Assistant).

## ✅ Passo 2 — RESOLVIDO em 23/08/2026, lido do source na tag `2026.8.3`

`config_flow.py` de 13 domínios, conferido por `grep` — sem modelo no meio.
**Os 13 aceitam fluxo de usuário**, então `user` entra em `setup_sources` de todos.

### 🔴 Existem DOIS padrões de config flow, e a cerca precisa saber

`systemmonitor` **não tem** `async def async_step_user`. Não é lacuna: ele usa
`SchemaConfigFlowHandler`, onde os passos são **dados**, não métodos:

```python
CONFIG_FLOW = {"user": SchemaFlowFormStep(schema=vol.Schema({}))}
class SystemMonitorConfigFlowHandler(SchemaConfigFlowHandler, domain=DOMAIN):
```

O passo `user` existe e o **schema é vazio** — o instalador cria com `{}`.
**Procurar só por `async def async_step_*` daria falso negativo.** A cerca da F8 tem de
cobrir os dois padrões.

### 🔴 `mqtt` e `matter` instalam o próprio app — o instalador NÃO deve

Os dois trazem `AddonManager` e passos próprios de instalação:

| domínio | evidência no `config_flow.py` |
|---|---|
| `mqtt` | `from homeassistant.components.hassio import AddonManager` · `addon_manager.async_schedule_install_addon()` · `async_step_install_addon` · `async_step_start_addon` · `async_step_hassio` |
| `matter` | `get_addon_manager` · `async_step_install_addon` · `async_step_start_addon` · `async_step_on_supervisor` |

**Consequência:** `requires: mosquitto` e `requires: matter_server` são
**`managed_by_ha`** — o instalador seleciona a integração e o **HA instala o app sozinho**.
Instalar por fora duplicaria. Isso confirma a curadoria §13 e **encolhe mais a F7**.

### 🔴 `tplink` tem passo de Camera Account no fluxo, e é condicional

`CONF_CAMERA_CREDENTIALS` · `STEP_CAMERA_AUTH_DATA_SCHEMA` ·
`async_step_camera_auth_confirm` · `_async_supports_camera_credentials(device)`.
Confirma o achado R18: a conta de câmera é **criada no app do celular** e depois pedida
num passo próprio, disparado só se o aparelho suportar. Não é a credencial da nuvem.

### Passos por domínio — o que o instalador vai encontrar

| domínio | passos além de `user` que importam |
|---|---|
| `hue` | `link` (apertar o botão da bridge) · `zeroconf` · `homekit` |
| `tplink` | `camera_auth_confirm` · `discovery_auth_confirm` · `integration_discovery` · `dhcp` |
| `shelly` | `credentials` · `zeroconf` · `bluetooth` · `wifi_scan` · `do_provision` |
| `broadlink` | `auth` · `unlock` · `reset` · `dhcp` |
| `smartthings` | só `reauth`/`reauth_confirm` — o resto é OAuth |
| `esphome` | `encryption_key` · `authenticate` · `zeroconf` · `dhcp` · `mqtt` |
| `thread` | `confirm` · `zeroconf` · `import` |
| `cast` | `config` · `confirm` · `zeroconf` |
| `tuya` | `scan` (QR) · `reauth_user_code` |
| `workday` | `init`/`options` — schema-based |

## Achados verificados que custam caro se esquecidos

- 🔴 **`curl \| bash` + `set -u` + `${BASH_SOURCE[0]}` = `unbound variable` na linha 2.**
  Vindo de stdin o array é **vazio**. Usar `${BASH_SOURCE[0]:-$0}`. Está em
  `probe-host.sh:214` e `haos-ui.sh:210`. **`bash -n` e `shellcheck` não pegam.**
- 🔴 **Biblioteca não instala `trap` no topo.** `haos-ui.sh:90` **apaga** o `trap cleanup EXIT`
  do chamador — trap é global, quem chama por último vence. Silencioso.
- **Prompt se testa por `( : </dev/tty )`, não por stdin** — em `curl | bash` stdin é o cano.
- **`--ostype` sai de `VBoxManage list ostypes`**, nunca fixo. `storagectl --add virtio-scsi`
  é `DOC-GAP`: validar com `--help` antes.
- **`storageattach` da doc oficial usa `--storagectl "SATA"`** — nós criamos `virtio-scsi`; o
  nome passado tem de ser o da controladora criada, senão o disco não anexa.
- **`default_config` são 24**, e o onboarding cria mais quatro (`google_translate`, `met`,
  `radio_browser`, `shopping_list`) — confirmado no source do Core 2026.8.3.
- **`single_config_entry: true`** em `mqtt`, `thread`, `cast` e `systemmonitor` — o instalador
  não pode tentar a segunda entry.
- **Slugs reais dos add-ons:** `configurator`, `samba`, `ssh` — não `file_editor`,
  `samba_share`, `ssh_server`.
- **`smartthings` usa `application_credentials` = OAuth**, não Personal Access Token.
- **`energia_br.yaml` exige a integração `workday`** — sem ela o `utility_meter` nunca troca
  de posto tarifário. E `:298` tem **placeholder** (`sensor.energy_total`) que o `--upgrade`
  cego devolveria por cima da correção do usuário.
- **O `ssh` oficial não declara `docker_api`** — Protection mode só libera o que o app declara.
- **`/auth/token` é Authentication API pública**, não superfície interna.
- **Um 401 em `/api/hassio/*` não prova recusa geral** — o proxy é allowlistado por caminho.
- **`input_number` tem step mínimo 0,001** — não guarda tarifa de 5 casas. Confirmado na doc.
- **macOS não traz Python desde a 12.3.** É portão da F1, não descoberta na F7.
- **Não comparar catálogo contra a instância do Pi como gabarito** — produz falso positivo
  em massa (17 entries `ignore`, `sun`/`systemmonitor` em `import`).

## Dívidas técnicas conhecidas

- ~~`lib/haos-ui.sh:90` instala `trap` no topo~~ — **RESOLVIDO**: a lib não
  instala trap, e o portão tem cerca (`nenhuma lib mexeu no trap EXIT`).
- ~~bloco de demo dentro da lib~~ — **RESOLVIDO**: virou `tools/ui-demo.sh`.
- `lib/haos-ui.sh:3` ainda manda rodar `./lib/haos-ui.sh --demo`, que **não
  existe**. Corrigir junto com a aplicação do logo.
- `lib/probe-host.sh`: `mem.available_mib` exclui cache reclamável — mede 4,6 GB numa máquina
  de 36 GB, e faz `vm_recomendado` ficar **menor** que `vm_equilibrado`.
- `lib/probe-host.sh`: não classifica meio físico da interface, e só emite interface que já
  tem IP.
- `packages/energia_br.yaml`: o ato citado é `REH 3.571/2026`, mas a pesquisa tarifária nomeia
  **`REH 3570/2026`** e o atribui à **Enel**, enquanto o CNPJ gravado é o da **Light**. Um dos
  dois está errado — **[CONFIRMAR]** antes de publicar. Os valores de fatura pessoal já foram
  zerados (23/08); o CNPJ ainda pende de mover para o pacote `casa ABHOME`.
- `packages/gas_br.yaml`: uma vigência atrás (a tabela CEG vigente é de 01/08/2026).
- `catalog/*.psv` e `lib/haos-splash.*`: formato e artefatos descartados, ainda no disco.
