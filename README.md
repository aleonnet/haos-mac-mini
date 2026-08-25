# haos-mac-mini

![CI](https://github.com/aleonnet/haos-mac-mini/actions/workflows/ci.yml/badge.svg)

> 🇺🇸 **English version:** [README_EN_US.md](README_EN_US.md)

Instalador de **Home Assistant OS** numa VM VirtualBox em **Mac Apple Silicon**, em um
único script Bash — idempotente, bilíngue (pt-BR/en-US pelo idioma do Mac) e pronto para
rodar direto via `curl`. Identidade visual do próprio Home Assistant, com degradação
verificada: em log, CI ou terminal sem UTF-8 a saída vira texto limpo e grepável.

> **Estado: funcional de ponta a ponta (0.3.0).** Um comando leva do Mac vazio ao
> **Home Assistant no ar**: valida a máquina, instala o VirtualBox (SHA-256 da
> Oracle), baixa e confere a imagem oficial do HAOS, cria a VM (argumentos
> sondados no VBoxManage ARM real, com flush de disco honesto desde o
> nascimento), dá o boot e espera pelo MAC da VM, cria sua
> conta (onboarding com analytics desligado), instala os apps escolhidos via
> WebSocket do Supervisor, configura as integrações que fecham sem credencial,
> escreve packages e dashboards em `/config` por SMB — e termina com o
> **endereço real** na tela e o navegador aberto. Auto-start no login,
> **desligamento limpo** no logout/reboot (vm-guard) e **backup diário trazido
> para fora da VM** (o cofre, com `--backup`/`--restore`) incluídos. O
> [CHANGELOG](CHANGELOG.md) diz exatamente o que existe em cada versão.
>
> ⚠️ Se você JÁ tem um Home Assistant na rede, `homeassistant.local` continua
> apontando para ele — o instalador acha a VM pelo MAC e imprime o IP real.

## Instalação

### Remota (recomendada)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash
```

Em terminal interativo, **sem flag nenhuma**, abre o cardápio com
[gum](https://github.com/charmbracelet/gum) (baixado em temp com SHA-256
verificado, nunca instalado): degrau com setas, extras marcados por **espaço**,
**ajuste item a item com busca** (digite para filtrar, **TAB** marca, enter
confirma — no filtro o espaço pertence à busca) e perfil de VM — depois o plano e a confirmação, antes de escrever
qualquer coisa. Sem TTY ou com `HAOS_USE_GUM=0`, degrada para o seletor
numerado simples. O pré-voo ainda avisa quando há instalador ou release do
HAOS mais novos publicados. As flags existem para o modo headless/CI. Cada execução real salva a seleção (`--profile last` a repete) e um relatório em
`~/.config/haos-mac-mini/`; uma falha preserva o log das ferramentas e imprime o
caminho. O que o instalador cria fica registrado num manifesto
(`created`/`preexisting`) — e o `--uninstall` remove **só** o que ele provar
que fez: o que já existia na máquina é preservado, com a razão dita no plano.

### Headless / sem interação

```bash
# perfil pronto, sem perguntas
curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash -s -- --profile haos_casa --no-input --install-deps

# só ver o que seria feito (não escreve nada, nem log)
curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash -s -- --dry-run --profile haos_casa
```

## Perfis

Os degraus **somam**; os extras marcam-se à parte, em qualquer degrau.

| Perfil | O que cobre |
|---|---|
| `haos_vanilla` | o piso — o que o HAOS instala sozinho |
| `haos_conectado` | + infraestrutura de conectividade (MQTT, Matter, Thread, ESPHome, Cast) |
| `haos_casa` | + integrações de hardware de casa (Hue, Tuya, Shelly, TP-Link, SmartThings…) |

Extras (`--with`): `ferramentas` (SSH, Studio Code Server, Samba) · `casa_abhome` (packages de
custo com regras brasileiras) · `extensoes` (HACS — só a instalação, e nunca no `--all`).

Quando o System Monitor está na seleção, o instalador também **habilita a lista
curada de sensores** (a integração nasce com tudo desabilitado — escolhas suas
são respeitadas) e entrega o **dashboard Monitor** na barra lateral: CPU, RAM,
disco, swap, carga, rede da VM; consumo do Core e do Supervisor; atualizações e
o estado do cofre de backup.

Veja o catálogo completo com `--list`.

## Opções

| Flag | Efeito |
|---|---|
| `--profile <id>` | `haos_vanilla` \| `haos_conectado` \| `haos_casa` \| `last` (repete a última seleção salva), sem interação |
| `--with a,b,c` | extras: `ferramentas`, `casa_abhome`, `extensoes` |
| `--all`, `-a` | `haos_casa` + extras (exceto o que exige opt-in nominal) |
| `--vm-profile <id>` | `vm_minimo` \| `vm_equilibrado` \| `vm_recomendado` (derivado da máquina) |
| `--vm-name <nome>` | nome da VM (padrão `HomeAssistant`) |
| `--dry-run`, `-n` | mostra o plano e sai — não escreve nada, nem log |
| `--list` | lista o catálogo e sai |
| `--image <arquivo>` | usa este `.zip` da imagem do HAOS (verificado por tamanho e SHA-256 — arquivo que não confere é erro, não fallback) |
| `--keep-image` | preserva o `.zip` baixado da imagem do HAOS |
| `--install-deps` | instala pré-requisitos ausentes sem perguntar (VirtualBox) |
| `--no-input` | não pergunta nada; falha se faltar dado obrigatório |
| `--force`, `-f` | refaz artefato já presente — **não** pula portão nem verificação de hash |
| `--verbose`, `-v` | mostra a saída crua de cada ferramenta |
| `--quiet`, `-q` | suprime a saída normal |
| `--doctor` | diagnóstico read-only: sistema, manifesto, imagem, **armazenamento da VM** (controller + `IgnoreFlush` + versão do VirtualBox sob a qual a VM foi validada), estado (exit 1 com problema) |
| `--uninstall` | remove **só o que este instalador criou** (plano + confirmação; `--dry-run` mostra o plano; `--confirm=<nome-da-vm>` confirma sem terminal) |
| `--self-update` | atualiza o script pelo publicado — valida sintaxe, recusa downgrade, deixa backup `.bak` |
| `--backup` | cria um backup **agora** e o traz para o cofre (`~/Documents/HAOS-backups`) — o gêmeo manual do agente diário das 04:10, com o resultado dito na tela |
| `--restore <tar>` | restaura um backup do cofre (`~/Documents/HAOS-backups`) na VM — conta, integrações e dashboards voltam inteiros |
| `--no-open` | não abre o navegador no fim |
| `--version` / `--help` | versão e ajuda |

Variáveis de ambiente: `HAOS_LANG=pt|en` força o idioma; `NO_COLOR` desliga cor e
animação; `HAOS_STATE_DIR` muda o diretório de estado (padrão
`~/.config/haos-mac-mini`).

## Comportamentos importantes

- **Idempotente**: artefato já presente e íntegro reporta "já está" e não é refeito.
  Reexecutar depois de uma falha continua de onde parou.
- **Nada sem verificação**: o `.dmg` do VirtualBox é conferido contra o `SHA256SUMS` da
  Oracle e a imagem do HAOS contra o hash publicado na tabela do script — `--force` não
  pula nenhum dos dois. Um download truncado é descartado pelo tamanho antes de custar a
  leitura de 380 MiB.
- **Uma senha, uma vez**: quem pergunta é o `sudo`, no terminal; o instalador nunca vê,
  guarda ou repassa a senha.
- **Falha explica**: erro de rede é reconhecido pela assinatura e dito como tal (com a
  dica de reexecutar), em vez de despejar o stack da ferramenta; as últimas linhas do log
  saem na tela e o arquivo completo fica em `$TMPDIR`.
- **Degrada bem**: sem TTY, sem UTF-8 ou com `NO_COLOR`, os glifos viram ASCII e a
  animação some — a mesma execução fica legível num log de CI.
- **O cofre é a autoridade única de backup**: cria sem senha (a restauração
  dispensa chave), guarda 7 no Mac e mantém só os 2 últimos dentro da VM. Um
  tar **criptografado** (backup automático ligado na interface do HA) é
  **recusado com aviso** — o cofre não teria como restaurá-lo sem a chave do
  Emergency Kit. Recomendação: deixe o backup automático da interface
  desligado e use `--backup`/o agente diário; se optar pelo caminho da
  interface, guarde o kit — a chave é sua, o instalador nunca a vê.

## Requisitos

- Mac com **Apple Silicon** (a imagem do HAOS é aarch64)
- macOS com `curl` (de fábrica) · `python3` (via Command Line Tools: `xcode-select --install`)
- VirtualBox ≥ 7.1 — o instalador oferece instalar se faltar

## Desenvolvimento

O repositório é a fonte do script: `catalog/catalog.bash` é a fonte de verdade do
catálogo, `lib/` da camada visual e da sonda, e `tools/embed.sh` embute as cópias no
`haos-install.sh` (o CI reprova divergência). Portão de qualidade único, local e no CI:

```bash
./tools/gate.sh
```

Documentos de engenharia (contrato de API verificado, curadoria do catálogo, handoffs de
frente) vivem em [`docs/`](docs/). Licença **MIT**.

## O guia oficial e os buracos que este instalador cobre

O [guia oficial de HAOS em macOS/VirtualBox](https://www.home-assistant.io/installation/macos/)
para no "crie a VM e dê boot". Na prática (tudo medido em campo, 24–25/08/2026):

| O guia | A realidade | Aqui |
|---|---|---|
| Silêncio sobre flush de disco | **O VirtualBox ignora flushes do guest por padrão** ([documentado pela Oracle](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/Troubleshooting.html), só IDE/SATA têm a chave de correção) — o journal do ext4 vira ficção; nesta bancada, um desligamento sujo zerou o `/data` do HAOS duas vezes | `IgnoreFlush=0` gravado na criação da VM (controller AHCI, exatamente onde a Oracle documenta a chave); validado com 5 quedas de energia simuladas sem perder um byte (cerca no CI); o `--doctor` confere controller e chave na VM real |
| Manda usar VirtioSCSI em Apple Silicon | O `VBoxManage` ARM **recusa** VirtioSCSI ("Invalid controller type") — e a Oracle o marca como experimental, sem `IgnoreFlush` documentado | SATA/AHCI sondado no binário real antes de criar |
| Nada sobre desligamento seguro | Reboot/logout do Mac mata a VM a seco | **vm-guard**: `ha host shutdown` limpo no logout, fallback `poweroff` honesto (cercado nos dois cenários; `savestate` fica proibido por decisão de engenharia: quebrou o runtime de containers do guest em campo, e a Oracle registra saved states ARM incompatíveis entre 7.1→7.2) |
| Nada sobre backup | O backup nativo do HA fica DENTRO da VM — morre com ela | **Cofre**: backup criado na instalação e trazido para `~/Documents/HAOS-backups` no Mac, agente diário às 04:10, `--backup` para um backup imediato sob demanda, e `--restore <tar>` devolve a instância inteira em um comando (cercas cobrem criar/trazer/podar/restaurar/recusar adulterado) |
| Onboarding, add-ons, integrações: "use o navegador" | horas de cliques | fases 07–10 automatizam o que não exige credencial sua |
