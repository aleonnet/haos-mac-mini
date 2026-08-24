# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) ·
versionamento [SemVer](https://semver.org/lang/pt-BR/). O instalador ainda não teve
release público ainda; as versões abaixo marcam os fechamentos de fase.

## [Unreleased]

### Fixed
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

### Added
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
