# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) ·
versionamento [SemVer](https://semver.org/lang/pt-BR/). O instalador ainda não teve
release público ainda; as versões abaixo marcam os fechamentos de fase.

## [Unreleased]

### Added
- **F11 — o Cofre**: a instalação só se declara completa com um backup FORA
  da VM. A fase garante o add-on SSH (infra do cofre), instala o
  `backup-pull.sh` + agente diário (04:10) que cria backup via
  `ha backups new`, o traz por cano de cat (o add-on não expõe SFTP), valida
  o tar e poda além de 7 — e executa o PRIMEIRO backup na hora. `--restore
  <tar>` fecha o ciclo: empurra o tar de volta, `ha backups restore` pelo
  slug lido do próprio arquivo, espera a instância voltar — funciona até
  contra VM virgem (conta de resgate + add-on automáticos). Cercas para TODOS
  os cenários: cofre feliz + poda, vigia limpo e fallback (script real sob
  TERM, com seams `VBM_BIN`/`GUARD_TIMEOUT`), restore feliz + tar corrompido
  recusado. De quebra, o sandbox pegou um bug de máquina virgem
  (`~/Library/LaunchAgents` inexistente).
- **README**: seção nova citando o guia oficial de macOS e os buracos dele
  que este instalador cobre (flush, VirtioSCSI/ARM, shutdown, backup).
- **`--doctor` ganhou a seção "Armazenamento da VM"** (adoção do §8.3 da
  análise externa de 25/08 — "nunca inferir semântica de storage de um
  controller a partir da documentação de outro"): lê o controller REAL da VM
  (`showvminfo --machinereadable`) e o valor efetivo de `IgnoreFlush`;
  AHCI + `Value: 0` aprova, AHCI sem a chave REPROVA (a Oracle só documenta
  a correção para IDE/SATA), controller diferente vira aviso em vez de
  promessa. Medido no 7.2.16: `getextradata` devolve rc=0 mesmo sem valor —
  o veredito sai do texto. De quebra, T5 documental: a fase da VM grava sob
  qual VirtualBox ela foi validada (`vbox_validada` no manifesto) e o doctor
  avisa quando a versão corrente divergir (upgrade de hypervisor sem
  reteste). Cerca nova no gate com 4 cenários.

- **Flag `--backup`** — o gêmeo manual do agente das 04:10, nascido de campo:
  o dono rodou o `backup-pull.sh` na mão e recebeu silêncio absoluto (o
  script é mudo por design, foi escrito para o launchd). A flag usa a mesma
  lógica com voz de gente: diz onde o tar ficou e quantos há no cofre;
  cofre já atual é dito como tal; falha explica e sai com rc≠0; cofre
  inexistente é erro de uso. Não pede credencial (o transporte é a chave
  SSH plantada). A interface `--backup`/`--restore` fecha o par que a
  análise externa (§11) aponta como requisito de produto. Cerca no gate
  com 4 cenários, mutation-testada.

### Changed
- **README fact-checkado contra as fontes primárias** (Oracle Troubleshooting
  7.2, reverificada em 25/08): a perda de `/data` em desligamento sujo é
  relatada como o fato medido nesta bancada (duas ocorrências), não como
  destino universal; o banimento do `savestate` agora cita a justificativa
  completa — incidente medido em campo + saved states ARM documentadamente
  incompatíveis entre VirtualBox 7.1→7.2.


### Fixed
- 🔴🔴 **A causa-raiz das perdas de dados, encontrada e morta: por padrão o
  VirtualBox IGNORA os flushes de disco do guest** — o journal do ext4 vira
  ficção e um desligamento sujo zera o `/data` do HAOS (aconteceu DUAS vezes
  em campo em 24/08). A fase da VM agora grava
  `VBoxInternal/Devices/ahci/0/LUN#0/Config/IgnoreFlush=0` na criação —
  validado com **5 quedas de energia simuladas** (poweroff seco) sem perder
  um byte. Cerca F4 exige a chamada.
- **vm-guard v3**: o desligamento no logout virou LIMPO — `ha host shutdown`
  via SSH (IP em `vm-guard.env`, escrito pela fase de boot) com fallback
  `poweroff` (seguro com flushes honestos) — **savestate foi BANIDO**: o
  resume quebrou o runtime de containers do guest e o par savestate+discard
  zerou o `/data` (terceira perda da noite, em teste). Provado ao vivo:
  TERM → VM desliga limpa em 30 s; religa em boot frio de ~50 s. Cerca F5
  exige `ha host shutdown` + `poweroff` e **reprova** `controlvm savestate`.


### Fixed
- 🔴 **DEFEITO GRAVE, medido em perda real (24/08, noite): o auto-start só
  LIGAVA a VM — o shutdown do Mac matava o VBoxHeadless a seco**, o `/data`
  do HAOS corrompia e a recuperação o zerava (instância configurada foi ao
  chão). O LaunchAgent agora roda o **vm-guard**: sobe a VM no login e, no
  SIGTERM do launchd (logout/shutdown), faz `controlvm savestate` — congela
  em disco sem cooperação do guest (HAOS ignora ACPI, medido) e o próximo
  login retoma do ponto exato; `ExitTimeOut 180` dá ao launchd a paciência
  do save. O `--uninstall` aprendeu `discardstate` (VM salva não é
  "running") e remove o vigia. Cerca da F5 atualizada: plist aponta o
  vm-guard com o nome em argv (sem `sh -c`), vigia executável com savestate.


### Added
- **SmartIR no catálogo** (item explícito, nunca padrão — categoria casa):
  termostato IR para ar-condicionado via Broadlink RM4, **sem canal HACS** —
  instalação direta com release 1.18.1 fixada por SHA-256 + tamanho, entregue
  pela fase Arquivos via SMB em `custom_components/smartir`. O `NAO_APLICA`
  registra a reversão: a regra da casa visava o canal, não o código. O
  instalador de componente-zip foi generalizado (`instala_componente_zip`,
  zip-raiz e zip-com-subdiretório) e a cerca de adulteração agora exercita as
  duas formas. ⚠️ documentado: archive de tag do GitHub não tem
  byte-estabilidade garantida — divergência de SHA recusa e pede re-pinagem.


### Added
- **Dashboard "Custos" entregue pelo instalador** (barra lateral): energia
  Convencional × Branca (faturas, economia, conferência), gás e água — como
  dashboard yaml-mode PRÓPRIO (`dashboards/custos_br.yaml` + bloco
  `lovelace:` no configuration.yaml, ambos desired-state com backup); o
  dashboard principal do usuário (`.storage`) nunca é tocado; bloco
  `lovelace:` alheio = aviso, nunca palpite.
- **gas_br cria a própria fonte de consumo**: `input_number.
  gas_consumo_ciclo_m3` + `sensor.gas_consumo_medido` nascem do package —
  caiu o "crie um input na mão" do comentário (mesma classe do
  energy_total).

### Changed
- **Studio Code Server substitui o File editor** no catálogo (decisão do
  dono, 24/08; reversão registrada no NAO_APLICA). `DESCOBRIR_<sufixo>`
  generalizado para qualquer app do repositório hassio-addons.
- **energia_br define `sensor.energy_total` sozinho** (soma dinâmica das
  fases da Shelly via `integration_entities`) — nenhum auxiliar manual;
  `utility_meter` já nasce ligado.
- **Mensagem de integração diz o lugar certo**: com descoberta pendente,
  "espera você no painel"; sem descoberta (tuya, tplink ainda mudo no DHCP),
  "precisa ser adicionado por você" — apontado contra o painel real.

### Fixed
- Packages conforme a doc do template integration: `attributes` são
  TEMPLATES — listas embrulhadas em Jinja, `null` eliminado
  (`vigencia_fim`, `faixa_4_ate`) e `|float(default)` em toda leitura com
  aritmética (a soma virava concatenação de strings).

## [0.3.0] — 2026-08-24

**O instalador agora entrega o Home Assistant NO AR**: um comando, cardápio,
senha — e o navegador abre no endereço real. F5–F10 fechadas no mesmo dia,
testadas de ponta a ponta contra a VM real (3 execuções: instala → converge →
idempotente em 18 s).

### Added
- **F5 — Boot e espera (fase 06)**: `startvm --type headless` com três
  estados (rodando espera, pausada retoma, resto liga); a espera acha a VM
  **pelo MAC no ARP** e sonda as duas portas candidatas — no HAOS 18.2 a URL
  canônica é a **porta 80** (medido; a 8123 fecha pós-onboarding).
  `homeassistant.local` nunca é consultado: com outro HA vivo na rede o nome
  resolve para ELE (medido nesta casa — aponta para a instância antiga).
- **F5b — auto-start no login**: LaunchAgent desired-state com argv direto
  (sem `sh -c` — banca: nome interpolado em shell seria injeção persistente);
  caminho completo do bundle porque launchd não tem `/usr/local/bin`.
  `--vm-name` validado no parser.
- **F6 — Conta (fase 07)**: onboarding real pelo helper Python embutido
  (users → core_config → **analytics DESLIGADO** → integration) com
  pós-condição; já onboardado valida a credencial via login_flow e converge.
  Senha pedida oculta (2x) no terminal ou `HAOS_HA_USER`/`HAOS_HA_PASSWORD`;
  segredo SÓ por stdin do helper — cerca de sentinela prova que não vaza
  para log, estado nem manifesto.
- **F7 — Apps (fase 08)** via WebSocket `supervisor/api` (cliente RFC 6455
  completo em stdlib: máscara, comprimentos 126/127, PING/PONG): instala,
  configura e inicia por item do catálogo; prefixo de repositório de
  terceiro **descoberto** (`a0d7b954` confirmado), nunca fixado; samba ganha
  usuário `haos` + senha gerada (releitura desired-state do Supervisor);
  `advanced_ssh` recebe a chave ed25519 `~/.ssh/haos-mac-mini` — **options
  aninhadas** (`ssh.authorized_keys`, medido) com merge/diff recursivos e
  restart do app quando a option muda. SSH à VM provado em campo.
- **F8 — Integrações (fase 09)**: só flow que fecha **sem dado do usuário**
  (systemmonitor `{}`, workday por defaults — provados 0→100); flow que pede
  credencial/escolha (ou aborta, como o tuya sem nuvem) é DESFEITO e vira
  "espera você no painel"; cerca de conjunto lê a entry de volta e REMOVE se
  `source` fora do `setup` do catálogo. Descobertas reais contadas via WS
  `flow/progress` (a rota REST dá 405, medido).
- **F9 — Arquivos (fase 10)**: `/config` montado por SMB com `expect`
  respondendo o prompt (senha nunca em argv; keychain não abre em SSH,
  medido); os 3 packages BR embutidos escritos desired-state com backup
  datado; `configuration.yaml` ganha o bloco `homeassistant:/packages:` só
  no formato reconhecido (estranho = aborta com instrução); **HACS 2.0.5
  fixado por SHA-256 + tamanho** — download adulterado é recusado;
  `check_config` antes do restart; espera o Core CAIR e VOLTAR. O umount
  mora no `limpar()` ANTES do rm dos temporários (um rm com SMB montado
  apagaria o /config da VM).
- **F10 — Relatório final**: endereço REAL do HA + navegador aberto
  (`--no-open` desliga), credencial do samba para o Finder, chave SSH,
  descobertas aguardando, aviso sobre `homeassistant.local`.
- **`--profile last` agora preserva o Personalizado** (a lista de itens vai
  ao state; ids mortos caem fora) — antes regredia aos padrões e derrubava
  hacs/systemmonitor (pego em campo).
- Portão: **HA dublado** (REST + WebSocket com frame >64 KiB), cerca de
  sentinela de segredo, `conf_estado` nos 3 formatos, HACS adulterado,
  cerca negativa do caminho do LaunchAgent; verify: metade **en** de toda
  mensagem é ASCII pura (estática). `embed.sh` com blocos `var:` para
  python/yaml e cerca de completude de `packages/`.

- **F4 — a máquina virtual**: fase 05 cria e registra a VM no VirtualBox com
  o disco da fase anterior conectado. Cada argumento foi **sondado no
  VBoxManage 7.2.16 ARM real** (24/08, com uma VM descartável): `createvm`
  exige `--platform-architecture arm`; ostype `Linux_arm64`; storage é
  **SATA/IntelAhci** — `VirtIO` SCSI é *recusado* na plataforma ARM ("Invalid
  controller type 11"); gráfico `qemuramfb`; firmware EFI; NIC `virtio` em
  **ponte pela interface sondada** (rota default → varredura das ativas),
  nunca um nome fixo. Contrato 0/100/1: VM já registrada converge sem tocar
  nada; falha no meio desfaz o parcial **sem apagar o .vdi**. O `--uninstall`
  ganhou o inverso (solta o medium antes de desregistrar) e o manifesto a
  chave `vm_registrada`. Cerca de ponta a ponta no portão com VBoxManage
  dublado que grava cada chamada. O relatório final lista a VM e o aviso
  agora diz a verdade nova: falta só o primeiro boot.

- **Personalizado é opção do MENU, no início** (o desenho do mac-env): todos
  os componentes do catálogo num filtro com busca, padrões do Casa
  pré-marcados, HACS nunca pré-marcado; extras derivados do que foi
  escolhido. Preset voltou a ser preset — o filtro não aparece mais depois
  de escolher Casa/Conectado/Vanilla. E as opções do gum agora saem do
  `msg()`: o menu misturava pt e en conforme o locale.
- **Relatório final** no fechamento do mac-env: `╰──` fecha a calha, placar
  com tempo total e passos executados, artefatos prontos (VirtualBox, imagem)
  — em cartão gum quando o seletor rico está ativo — e **próximos passos
  contextuais**. A execução que instala VirtualBox e imagem termina em
  placar, não mais num "não implementado" com cara de erro.
- **Seletor rico com gum** (porta do mac-env-setup): baixado em temp com
  SHA-256 conferido contra o checksums.txt da release, tema na paleta HA —
  degrau por setas, extras por **espaço**, **ajuste item a item com busca**
  (`gum filter` com os padrões pré-marcados), confirmação `gum confirm`.
  Fallback: o seletor numerado, sem TTY/rede ou com `HAOS_USE_GUM=0`.
- **Verificação de novidades no pré-voo** (melhor-esforço, 3 s de teto,
  silêncio na falha): avisa quando há instalador publicado mais novo
  (`--self-update`) e quando o HAOS lançou release acima da fixada na tabela.
- **A calha vertical** (`│`), a gramática dos irmãos: toda linha — status,
  menus do cardápio, plano, plano de remoção, dump do doctor — pendura numa
  trilha contínua; cada etapa abre com `├── NN Título ───`. Inputs ganharam
  o glifo próprio (`?` âmbar, `[?]` sob locale C). Pedido do dono no segundo
  teste real: "linhas soltas leem como lista; a calha lê como fluxo".
- **Cercas de ponta a ponta no portão**: a F1 INTEIRA roda com um DMG
  sintético e `hdiutil` de verdade (rede/sudo/VBoxManage dublados por
  função); o `--self-update` é exercitado por arquivo nos dois sentidos
  (atualiza com backup, RECUSA downgrade); o diagnóstico de rede é provado
  contra a assinatura real do curl. A lição: caminho que nunca rodou é
  caminho quebrado que ainda não foi visto.
- **O cardápio**: sem flags e com terminal, o instalador pergunta degrau,
  extras e perfil de VM (com "repetir a última" quando há seleção salva) — no
  desenho dos irmãos: menu na tela, resposta lida do terminal real
  (`$TTY_DEV`, que é também a costura da bancada), inválido repete, vazio
  assume o padrão. Antes, terminal sem flags caía em `haos_casa` em silêncio.
- **Abertura em 4 atos** (constelação → traço oficial → sonar → respiração):
  cada pixel da casa voa de fora da tela e se monta de baixo para cima; o
  traço branco desenha o contorno e se retrai (movimento do vídeo oficial);
  os discos do circuito emitem anéis ciano; o azul pulsa e assenta. Preview
  fiel em `docs/previews/2026-08-24-abertura/abertura.gif`.
- **Geometria do logo refeita contra o vídeo oficial**: BEIRAL (o telhado
  ultrapassa as paredes, com degrau), ápice pontudo, base com raio moderado,
  traço 1,75 px abraçando a borda (come 9% da casa; a tentativa reprovada
  comia 42%), gradiente vertical no azul.
- Cerca nova do logo no `verify.sh`: além da integridade da máscara, o limiar
  de RAZÃO traço/casa (≤ 12%) — a cerca que teria pego a tentativa reprovada.

### Fixed
- **VirtualBox instalado era "not found" em shell sem `/usr/local/bin`**
  (SSH não-interativo, launchd): a sonda agora cai para
  `/Applications/VirtualBox.app/Contents/MacOS` quando o symlink não está no
  PATH — o app bundle é o fato, o PATH é detalhe. Pego no teste de campo por
  SSH.
- **O relatório final responde "o que foi instalado e onde"**: VirtualBox com
  versão e caminho em `/Applications`, o disco do HAOS verificado por SHA-256
  com o caminho completo, a seleção salva — e, em aviso destacado, **o que
  AINDA NÃO existe**: a VM e o Home Assistant rodando; nada responde em
  `http://homeassistant.local:8123` nesta versão, que para na preparação
  verificada. Saíram a duplicação cartão+linhas e a contagem enganosa de
  passos.
- **A barra de download é a nossa**, não o "jogo da velha" do curl: bytes
  gravados no disco contra o total da tabela, no estilo da calha, a cada
  300 ms.
- **As teclas do seletor, medidas com expect num pty real**: ESPAÇO marca no
  `gum choose` (extras); TAB marca no `gum filter` (Personalizado — o espaço
  pertence à busca). O cabeçalho do Personalizado ensinava a tecla errada.
  Cerca no portão dirige o gum de verdade e confere que cada tela ensina a
  SUA tecla. O binário do gum ganhou cache por versão em
  `~/Library/Caches/haos-mac-mini/`.
- **F1 morria em "Could not mount"** no primeiro teste real: `hdiutil attach
  -quiet` SUPRIME a listagem do ponto de montagem e o parse recebia vazio.
  Agora o parse é do `-plist`, com `</dev/null` (em `curl | bash` o stdin é o
  cano) e diagnóstico de log na falha.
- **Prompt colado na barra de fase** (`fase 1/4Download and install...?`):
  perguntas agora SUSPENDEM a barra (disciplina do ask() do AtlasFile) e
  escrevem o prompt no stdout, não direto no tty.
- O DMG do VirtualBox agora mora no CACHE com SHA conferido: a reexecução
  após o macOS bloquear a extensão (o desfecho provável da 1ª vez) não paga
  os 153 MB de novo. O `--uninstall` sabe removê-lo.

### Removed
- `tools/escolhe-logo.sh` (andaime da escolha, superado pela direção do dono;
  preservado em `.lixo-24-08/`).

## [0.2.0] — 2026-08-24

### Added
- **`--uninstall`**: fatos (read-only) → plano REMOVE/PRESERVA → UMA
  confirmação (`--confirm=<nome-da-vm>` sem terminal — o nome exato, não um
  sim) → execução prestando contas item a item. Remove SÓ o que o manifesto
  prova `created`; `preexisting`, `pending` e chave ausente preservam, cada um
  com a própria frase no plano. Sem `rm -rf`: arquivos um a um com guarda de
  prefixo, diretório só por `rmdir`. **O VirtualBox nunca é removido
  automaticamente** (extensão de sistema) — `created` ganha a instrução do
  desinstalador oficial da Oracle.
- **`--doctor`**: diagnóstico read-only em cinco seções (sistema,
  pré-requisitos, manifesto, imagem, estado), separando o que o instalador
  resolve (aviso) do que só o usuário resolve (falha); exit 1 com problema.
- **`--self-update`**: baixa o publicado, valida com `bash -n`, **recusa
  downgrade** por comparação de versão, confirma e troca com backup `.bak`.
  Via pipe (curl | bash) explica que já se roda o remoto.
- **Manifesto de instalação** (`~/.config/haos-mac-mini/`): `host-prereqs`
  (VirtualBox) e `vms/<nome>.manifest` (imagem), com `created`/`preexisting`/
  `pending` — `pending` gravado ANTES de tentar, `created` nunca rebaixado,
  ausente lê como `preexisting`. É a base do `--uninstall` que só remove o que
  o instalador provar que criou.
- **`--profile last`**: repete a última seleção salva, filtrando ids que
  saíram do catálogo; sem seleção salva, erro claro nomeando o arquivo.
- **`--image <arquivo>`**: usa um `.zip` local da imagem (verificado por
  tamanho e SHA-256). Arquivo explícito que não confere é **erro**, não
  fallback; os candidatos implícitos (cache, diretório corrente) continuam
  valendo.
- **Cerca de enumerados**: todo valor listado nas linhas `--profile`/
  `--vm-profile`/`--with` do `--help` é executado contra o parser real.
- **Gramática visual única**: as fases falam a calha da camada visual (✔ · ▲ ✖),
  a mesma dos instaladores irmãos, com fallback ASCII verificado sob locale
  não-UTF-8 e barra de progresso por fase. A voz antiga de prefixos `[OK]`
  saiu, e o `verify.sh` reprova a volta dela.
- **Log de execução** por rodada (`$TMPDIR/haos-install-*`): falha preserva o
  log, reconhece assinatura de **falha de rede** e explica em vez de despejar
  stack; sucesso limpa. Relatório do que o instalador fez em
  `~/.config/haos-mac-mini/last-run.log`.
- **`ha_run_step`**: passos com spinner e tempo medido para os comandos-folha
  (downloads, `installer`, `unzip`).
- **Guarda de biblioteca** (`HAOS_INSTALL_LIB=1`) e costura de estado
  (`HAOS_STATE_DIR`): a bancada de teste alcança as funções sem executar nada.
- **Cercas novas no portão**: toda flag publicada no `--help` é executada e
  reprova se responder "não implementado"; dry-run é conferido como read-only
  por snapshot de `$HOME` sintético; locale C é exercitado nas funções de fase,
  não só no banner; i18n conferida em runtime.
- **F3 — imagem do HAOS**: baixa (ou reaproveita um `.zip` local íntegro),
  confere tamanho e SHA-256 antes de descompactar, descompacta atomicamente e
  registra proveniência para a idempotência (`.origem`).

### Changed
- `--help` só promete o que existe: as flags das fases futuras (`--doctor`,
  `--uninstall`, `--self-update`, `--resume`, `--upgrade`) entram junto com a
  implementação.
- Flags de valor validam o shape na hora (`--profile --help` não engole mais a
  flag seguinte).
- README reescrito para o usuário final.

### Fixed
- `ha_spin` abortava o chamador sob `set -e` quando o processo esperado falhava.
- Glifos multibyte (spinner, réguas, separadores) vazavam crus sob
  `LC_CTYPE=C` — medido por SSH num Mac mini.

## Antes do changelog (2026-08-23)

Fundação registrada no histórico do git: esqueleto F0–F2 (pré-voo por sonda,
seleção por perfis, plano, `--dry-run`/`--list`), condução da instalação do
VirtualBox com SHA-256 da Oracle, catálogo com 20 itens e cercas de schema,
camada visual com logo animado do HA, portão único local=CI (`tools/gate.sh`) e
arnês de contrato contra o HA Core fixado e `latest`.
