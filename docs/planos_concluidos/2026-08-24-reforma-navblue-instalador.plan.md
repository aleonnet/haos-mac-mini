# Adoção das práticas navblue + reforma do haos-install.sh — v2 PÓS-BANCA

## Contexto

Três direções suas: (1) a regra "sem cores" do monorepo não deveria existir — o
padrão é o dos irmãos (`AtlasFile/install.sh`, `mac_env_install.sh`); (2) gap
analysis com os 3 códigos lidos por inteiro, adotando as melhores práticas dos
dois; (3) adotar as práticas do navblue-monorepo: banca adversarial, modo
madrugada, HANDOFF como forma de report, bancada com resultado esperado.

**Norte de UX confirmado:** o leigo roda **um comando**, assiste a uma abertura
com identidade HA, responde no máximo **tier + senha**, e termina com
`http://homeassistant.local:8123` na tela — enquanto o mesmo script, num log de
CI, produz texto limpo e grepável.

**Banca adversarial RODADA sobre este plano** (3 lentes independentes: ordem ·
cercas · regressão): **3× REPROVA na v1, 36 achados, 7 bloqueadores** — todos
incorporados abaixo, marcados `[B-n]`. A banca também inocentou: `embed.sh` por
commit; `trap EXIT` vs subshell (testado em bash 3.2.57); compatibilidade 3.2
do código a portar.

---

## Gap analysis — veredito

**O `haos-install.sh` REPROVA como produto** (3 lentes) — 14 achados, 6
bloqueiam. A fundação de verificação é a melhor dos três e fica: i18n pt/en por
locale · degradação UTF-8 medida · portão único local=CI · arnês de contrato vs
`2026.8.3`+`latest` · probe-first · bash 3.2.

### Lente 1 — OPERAÇÃO
| # | achado | evidência | grav. |
|---|---|---|---|
| 1 | Zero estado local (manifesto, log, last-run) | `grep STATE\|manifest\|log` vazio | 🔴 |
| 2 | O `0/100` de `garantir_virtualbox`/`fase_imagem` É o sinal created/preexisting — e ninguém grava | AtlasFile `:756` (`pending` antes de tentar), `:927` (`created` nunca rebaixa) | 🔴 |
| 3 | Falha de rede sai crua, sem log nem assinatura | AtlasFile `af_falha_de_rede :361` explica e ensina reexecutar | 🟡 |
| 4 | Runtime lê `"./$zipnome"` — resquício de clone | `haos-install.sh:401` | 🟡 |

### Lente 2 — PROMESSA
| # | achado | evidência | grav. |
|---|---|---|---|
| 5 | `--profile last` prometido no help e morre com `perfil desconhecido` | usage `:1106` vs `perfil_valido :1040` | 🔴 |
| 6 | 6 flags no help (`--doctor --uninstall --resume --upgrade --upgrade-only --self-update`), todas caem em `morrer "não implementado"` | `:1118-1135` vs `:1487-1490` | 🔴 |
| 7 | Flags de valor engolem a flag seguinte (`--profile --help`) | AtlasFile valida shape no parser `:191-209` | 🟡 |

### Lente 3 — GRAMÁTICA
| # | achado | evidência | grav. |
|---|---|---|---|
| 8 | Fases falam `[OK]` (5 funções, ~48 call-sites); a calha `ha_*` (✔ ▲ ✖, barra, spinner) só na demo | AtlasFile `:294`: "duas gramáticas visuais era o defeito" | 🔴 |
| 9 | `ha_spin`/`ha_bar` definidos, nunca chamados por fase | `:825,:840` | 🔴 |
| 10 | Sem `run_step` (spinner+tempo+placar) nem wrap de calha — e o produto imprime caminhos longos | AtlasFile `:387`, `af_wrap :560` | 🟡 |
| 11 | Sem relatório final: placar, próximos passos contextuais, caixa de endereço | mac-env `:2778`; AtlasFile `:3448` | 🟡 |
| 12 | Sem CHANGELOG nem disciplina de release | ambos os irmãos têm | 🟡 |
| 13 | Backup datado só na F3 (`.origem`) | mac-env `backup_and_install_file :2004` | 🟢 |
| 14 | Sem `--self-update` | mac-env `:2886` (bash -n + hash + .bak) | 🟢 |

---

## Os 7 bloqueadores da banca sobre o plano — e a correção de cada um

| # | bloqueador (lente) | correção incorporada |
|---|---|---|
| B-1 | **Ciclo bancada↔push**: a bancada usava `curl <raw>`, mas `origin/main`=`84d15a1` não tem a F3; `--self-update` apontaria para um main atrasado, REBAIXANDO o script | Bancada roda do arquivo local (`cat haos-install.sh \| bash -s --`); `--self-update` só com guarda de downgrade e depois do push |
| B-2 | **Cerca da gramática tarde e estreita**: nascia em F-D, 3 commits após a migração, e cobria só `[OK]` — a voz antiga são 5 funções (`ok/info/aviso/erro/fase`) + `[!]` no `limpar()` | Cerca nasce **no mesmo commit** de F-A; proíbe as **definições** das 5 funções; escopo: só `haos-install.sh`, fora dos blocos `>>> EMBUTIDO`, padrão `\[(OK\|ERRO\|AVISO\|\*)\]` — `extras/`, `verify.sh`, `gate.sh` seguem no contrato `[OK]` deles |
| B-3 | **Glifos ✔▲✖ sem degradação UTF-8**: `ha_ok/warn/err` imprimem multibyte incondicional; a cerca de locale do gate só exercita `ha_banner`; **o Mac mini alvo tem `LC_CTYPE=C` por SSH**; e o spinner do AtlasFile fatia `${frames:$i:1}` POR BYTE sob locale C | Fallback ASCII (`[OK]/[!]/[X]`) quando `HAOS_UI_UTF8=0` em `ha_ok/warn/err/skip/spin/bar`; a cerca do `gate.sh:137` passa a exercitar essas funções sob `LC_ALL=C`, não só o banner — **antes** da migração |
| B-4 | **Help mentiroso sobrevivia até F-C sem cerca** — o achado de maior superfície | Flags não implementadas saem do `uso()` **no 1º commit de F-A**; cerca em forma de call-site: cada flag extraída da saída real de `--help` é executada e reprova se emitir `nao_implementado` |
| B-5 | **Versionar docs em repo público ANTES de cerca de segredo** — histórico git não esquece | Cerca "nenhum arquivo versionado contém IP privado / e-mail / hostname interno da casa" nasce e passa **antes** do commit que altera o `.gitignore` |
| B-6 | **`run_step` portado quebraria o que funciona**: roda em subshell de background → perderia `VBOX_PONTO`/`TMPFILES`/`HAOS_VDI` (o `.dmg` ficaria montado para sempre — defeito já medido em 23/08); `wait \|\| fail` mataria o contrato 0/100/1; prompt de sudo cairia dentro do spinner | `ha_run_step` embrulha **só comando externo folha** (`curl`, `unzip`, `shasum`, `VBoxManage`), nunca fase; aceita lista de rc (`0 100`); sudo e confirmações primadas **antes** do primeiro `run_step` |
| B-7 | **Cercas sem seam**: `verify.sh` nunca executa o instalador; a cerca do uninstall leria o `~/.config` REAL do dev; `un_build_plan` "testável" era inalcançável num monolito que termina em `main "$@"` | Gate de biblioteca `HAOS_INSTALL_LIB=1` (`return 0 2>/dev/null \|\| exit 0`) antes do `main`; `HAOS_STATE_DIR` derivado de `$HOME` **em runtime**; cerca do uninstall roda no `gate.sh` com `env -i HOME=<sandbox>` |

Correções 🟡 da banca que mudam o desenho: **`--image` SOMA, não substitui** — o
`./$zipnome` continua candidato (o zip de 398 MB do dono está na raiz do repo e
no Mac mini; removê-lo custaria 380 MiB de re-download) · `LOG_FILE` por
`mktemp` FORA de `TMPFILES` (senão o `limpar()` apaga o log que o erro acabou de
nomear), limpo só no sucesso · `FASE_ATUAL` preservado no wrapper da calha (a
mensagem de interrupção depende dele) · primitivas portadas renomeadas `ha_*`
com paleta mapeada (`$GUT/$GREEN` não existem aqui; `set -u` abortaria) ·
`last` whitelistado em `perfil_valido()` e a cerca confere contra a **função**,
não contra o catálogo · cerca do `./` vira comportamento (isca com o nome do
zip num cwd temporário; F3 não pode consumi-la) · estado dir + `write_run_log`
nascem em F-A junto do log (não em F-B — evitaria reescrever as mesmas linhas) ·
**dry-run não escreve NADA, nem log** — cercado por snapshot de `$HOME`
sintético antes/depois · i18n: cerca que reprova literal humano fora de `msg()`
nasce **antes** da primeira string do uninstall; cerca de par pt|en passa a ler
a tabela em runtime (via gate de biblioteca) · `tools/ui-demo.sh` entra no
escopo de F-A (o portão o executa e exige stderr vazio) e a lib não pode
depender de `msg()` · `--vm-profile` e `--with` entram na cerca de enumerados ·
shape de flags de valor ganha cerca · a memória `haos-macmini-frente` do projeto
**pai** + os dois `MEMORY.md` + `.gitignore` mudam no MESMO commit que absorve o
`ESTADO.md`.

---

## PARTE A — Regras (CLAUDE.md do monorepo)

### A1. Regra de cores reescrita [ajustada pela banca]
A regra nova fala do **produto público distribuído por `curl | bash`**
(`haos-install.sh`), não do repositório: cor com degradação verificada
(`-t 1` · `NO_COLOR` · `TERM=dumb` · UTF-8). Prefixo textual `[OK]`/`[ERRO]`
continua contrato de: scripts do **cutover**, scripts de **`extras/`** (Tapo —
`CLAUDE.md:284` já os contratualiza) e ferramentas de build
(`verify.sh`/`gate.sh`/`embed.sh`).

### A2. Práticas navblue adotadas
Bloco "Como trabalhamos nesta frente": **banca adversarial** antes de plano
grande (3 lentes, veredito, achado com `file:line`, bloqueador corrige antes do
1º commit) · **HANDOFF** como porta de entrada
(`docs/roadmap/HANDOFF-<data>.md`, SUPERSEDE/SUPERADO; seções fixas:
estado-confira-no-git · decisões com custo+reversibilidade · dívidas · achados
não tratados · o-que-falta com push/bump **só sob ordem** · lições) · **modo
madrugada** (diário timestampado em `docs/roadmap/decisoes/`; proibido por
regra: push, bump, release, rede/hardware da casa) · **bancada** com tabela
Passo|Ação|RESULTADO ESPERADO + prompts prontos · **checklist de fechamento**
(plano→`planos_concluidos/`+README, bump SemVer, CHANGELOG Keep-a-Changelog,
README) · **forma de report**: veredito primeiro, tabelas, evidência
`file:line`, zero prosa de processo.

Para o CLAUDE.md nunca descrever artefato inexistente: **HANDOFF e CHANGELOG
nascem como esqueleto já em F-A**, no mesmo commit da regra.

### A3. Estrutura do repo (layout navblue)
```
CHANGELOG.md                       nasce em F-A (esqueleto), alimentado por fase
docs/roadmap/HANDOFF-<data>.md     nasce em F-A; absorve o ESTADO.md em F-D
docs/roadmap/decisoes/             diários
docs/planos_concluidos/ + README   índice
docs/PLANO.md · docs/INVENTARIO.md em F-D, LIMPOS, após a cerca de segredo [B-5]
```

---

## PARTE B — Execução em 4 fases (cada uma fecha com `./tools/gate.sh` + commit)

### F-A — Gramática única + esqueleto de operação
Arquivos: `haos-install.sh`, `lib/haos-ui.sh`, `tools/gate.sh`, `verify.sh`,
`tools/ui-demo.sh`, `../CLAUDE.md`, `CHANGELOG.md` (novo), `docs/roadmap/` (novo).
1. Fallback ASCII em `ha_ok/warn/err/skip/spin/bar` sob `HAOS_UI_UTF8=0` [B-3]
   e cerca do gate estendida a elas — **antes** da migração.
2. Fases migram para a calha via wrappers que preservam `FASE_ATUAL`; as 5
   funções antigas REMOVIDAS; cerca da gramática no MESMO commit [B-2].
3. `uso()` honesto (flags mortas saem) + cerca help∩`nao_implementado`=∅ [B-4].
4. `LOG_FILE` (`mktemp`, fora de `TMPFILES`, limpo só no sucesso) +
   `fail_with_log` com assinatura de rede via `MSG_DB`.
5. `ha_run_step` (nomes `ha_*`, paleta mapeada, rc-list `0 100`, só comando
   folha; sudo primado antes) em F1/F3 [B-6]. `ha_wrap`. Barra por fase.
6. Parser: shape das flags de valor + cerca.
7. Estado dir (`HAOS_STATE_DIR` derivado em runtime) + `write_run_log` + gate
   de biblioteca `HAOS_INSTALL_LIB` [B-7]. Dry-run não escreve nada — cerca por
   snapshot.
8. `tools/ui-demo.sh` atualizado; CLAUDE.md (A1+A2) + esqueletos de
   HANDOFF/CHANGELOG.
9. Cerca de i18n (literal fora de `msg()`) + cerca de par em runtime.

### F-B — Manifesto e memória de seleção
`~/.config/haos-mac-mini/`: `host-prereqs` + `vms/<nome>.manifest` — porta de
`manifest_get/set` do AtlasFile com as 3 regras (`pending` antes de tentar;
`created` nunca rebaixa; ausente = `preexisting`; escrituração best-effort) ·
`garantir_virtualbox`/`fase_imagem` gravam no retorno · `--profile last` com
`last` whitelistado em `perfil_valido()` e filtro de ids mortos (mac-env `:761`)
· `--image` **somando** ao candidato `./` · cerca de enumerados (`--profile`,
`--vm-profile`, `--with`) contra o parser real, não contra o texto do help.

### F-C — `--uninstall` + `--doctor` + `--self-update`
Uninstall no desenho AtlasFile (`:1288-2136`): fatos read-only (`un_collect`) →
plano REMOVED/PRESERVED (`un_build_plan`, função pura, testável via gate de
biblioteca) → 1 confirmação (`--confirm=<nome-da-vm>` sem TTY) → execução
prestando contas passo a passo; `preexisting`/ausente **nunca** remove;
`--keep-image`; para-na-falha preservando as ferramentas de tentar de novo;
`un_dir_is_safe`; o registro sai por último. Cobre hoje: VirtualBox, Extension
Pack, `.vdi`, cache — cada fase futura entra com o inverso e a chave dela.
Doctor com `DOC_MISSING`×`DOC_BLOCKERS` e veredito contado. `--self-update` com
`bash -n`+hash+`.bak` e **recusa de downgrade** [B-1]. Todas as strings via
`msg()` (a cerca de F-A já cobra o par pt/en).

### F-D — Docs, repo e fechamento
1. **Cerca de segredo primeiro** [B-5]; só então `.gitignore` muda e
   `docs/PLANO.md`/`docs/INVENTARIO.md` entram limpos (medido: 4 ocorrências no
   ESTADO, 4 no INVENTARIO — SSH real, IPs, e-mail —, 0 no PLANO).
2. HANDOFF absorve o `ESTADO.md`; no MESMO commit: memória
   `haos-macmini-frente` (projeto pai), os dois `MEMORY.md` e `.gitignore`.
3. Cerca do `./` por comportamento (isca no cwd temporário).
4. CHANGELOG alimentado · bump minor de `HAOS_INSTALL_VERSION` · plano →
   `docs/planos_concluidos/` + README.

---

## Bancada (pós-banca: local até o push [B-1]; 1 pré-condição, 1 esperado)

| Passo | Ação | RESULTADO ESPERADO |
|---|---|---|
| 1 | `cat haos-install.sh \| bash -s -- --dry-run --profile haos_casa` em `/tmp` | calha ✔/▲, plano completo, exit 0 |
| 2 | idem com `NO_COLOR=1 \| cat` | mesmos glifos, zero escape ANSI |
| 3 | idem com `LC_ALL=C` | fallback ASCII, zero byte partido |
| 4 | dry-run com `$HOME` sintético; diff antes/depois | **vazio** — nem log |
| 5 | execução real (aborta em F1 sem VBox) com `$HOME` sintético | `host-prereqs` existe; `last-run.log` existe |
| 6 | `--profile last` sem state | erro claro nomeando o arquivo; exit `E_USO` |
| 7 | `--profile last` com state gravado | seleção idêntica à gravada |
| 8 | `--doctor` com snapshot do state dir | seções+veredito; diff vazio |
| 9 | `--uninstall --dry-run`, manifesto sintético `vbox preexisting`, HOME sandbox | plano PRESERVA o VirtualBox nomeando o porquê |
| 10 | F3 `--image` cópia com 1 byte trocado (MESMO tamanho) | recusa antes de descompactar, esperado/obtido |
| 11 | F3 `--image` cópia truncada | descartada por tamanho, sem ler 380 MiB |
| 12 | zip íntegro no cwd, SEM `--image` | reaproveitado (`img_local`) — o fluxo do dono sobrevive |

**Prompts prontos** — Funcionou: `Bancada OK nos passos <lista>. Execute o
fechamento: bump, CHANGELOG, HANDOFF, push.` · Falhou: `Passo <N>: esperado
<...>, observado <...>. Saída literal: <colar>. Diagnostique antes de alterar.`

## Fechamento
HANDOFF · plano→`planos_concluidos/` · bump minor · CHANGELOG · README · **push
só sob ordem** (leva junto `9cc0070`/`9b7d887` e destrava a bancada via
`curl <raw>`).

## Pendências do dono (inalteradas)
Escolha do logo (`./tools/escolhe-logo.sh`) · apagar `$TMPDIR/ha.tok` (o `rm`
foi negado pelo hook) · trocar a senha da HGU que passou pelo chat (depois eu atualizo os 2
arquivos do cutover).
