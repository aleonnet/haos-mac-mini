# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) ·
versionamento [SemVer](https://semver.org/lang/pt-BR/). O instalador ainda não teve
release público ainda; as versões abaixo marcam os fechamentos de fase.

## [Unreleased]

_Nada ainda._

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
