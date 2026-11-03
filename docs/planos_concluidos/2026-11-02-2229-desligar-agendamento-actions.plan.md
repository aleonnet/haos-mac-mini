# Parar o gasto de armazenamento do GitHub Actions e desligar o que roda sozinho

project: ~/Development/ABHOME-infra/ABHOME-haos-macmini
status: aceito

## Context

O GitHub avisou 0,54 GB usados de 0,5 GB de armazenamento do Actions. O dono perguntou o que consome
e mandou desligar o que estiver automático.

**O que consome (medido em 2026-11-02 22:51 UTC):** o `witrace`, repositório privado, guarda 146 artefatos
ativos, 9.272,9 MiB = 9,06 GB. São 30 execuções de 3 a 7 de outubro, cada uma com até 5 pacotes do servidor
(cerca de 319 MiB). Ficam guardados 90 dias, até 1 a 5 de janeiro de 2027. A última execução foi em 7 de outubro.
Não é automático: é sobra de envios feitos à mão, mantida pelo prazo padrão de 90 dias.

**Por que 0,54 GB, se são 9 GB:** a cobrança acumula por hora e divide pelas horas do mês (fonte:
docs.github.com/en/billing/concepts/product-billing/github-actions, "Storage charges accrue every hour").
9,15 GB × cerca de 43 h ÷ 720 h = 0,54 GB. Ao preço de US$ 0,25 por GB-mês, dá os US$ 0,14 da tela.

**`haos-mac-mini` não consome armazenamento:** 0 artefatos e 0 cache. Os US$ 0,35 são tempo de máquina a preço
de tabela, em duas execuções agendadas: (19 min Linux × US$ 0,006 + 1 min macOS × US$ 0,062) × 2 = US$ 0,352.
Conforme a mesma página, máquina padrão em repositório público é gratuita. O valor líquido da conta não foi lido:
o token do `gh` não tem a permissão `user`.

**O que é automático, em todos os repositórios não arquivados:**

| Repositório | Agendamento | Execuções |
|---|---|---|
| `haos-mac-mini` | `ci.yml`, diário | 31 em outubro, 2 em novembro |
| `microduck` (fork) | `prune-dev-releases.yml` semanal, `turn-endpoint.yml` diário | 0, desde sempre |
| `vectorcraft` (fork) | `windows-arm64.yml` e `windows7.yml`, semanais | 0, desde sempre |

**Resultado esperado:** apagar os artefatos para o acúmulo parar agora; encurtar o prazo no `witrace` para não
voltar; desligar os cinco agendamentos.

**O aviso de 100% continua até 1º de dezembro:** o que já acumulou não sai da conta ("Storage already accrued
during the current billing cycle remains in your total"). Sem apagar, novembro fecha com cerca de US$ 2,16 de
excedente, e dezembro com outro tanto. Apagando hoje, novembro fecha com cerca de US$ 0,05.

**Ordem do dono (2026-11-02):** depois do resumo em português simples, pediu a submissão deste plano, sem mudança
de conteúdo.

## Risk band

**standard.** Toca configuração de CI e dados que não voltam, nada do produto nem da casa.

## Impact sweep (commands run now)

```
gh repo list aleonnet --limit 200 --json name,visibility --jq '.[] | [.name,.visibility] | @tsv'
gh repo list aleonnet --limit 200 --no-archived --json name,isFork --jq '.[] | [.name,.isFork] | @tsv'
gh api repos/aleonnet/witrace/actions/permissions/artifact-and-log-retention
gh release list -R $R --limit 10
git grep -n -E 'gh run|gh api|actions/artifacts|run-id|github-token' -- ':!docs/mockups/*'
git grep -n 'servidor\.yml' -- ':!docs/*' ':!.github/*'
git grep -n -E 'ci\.yml|workflows/|on: *schedule|schedule' -- ':!docs/*' ':!.github/*' ':!tarifas/*'
```

O que mediram:

- Armazenamento: `witrace` 9.272,9 MiB, `alumia-app` 93,3 MiB, `alumia` (público) 70,7 MiB; os demais, nada. Cache: 0 em todos.
- Prazo do `witrace`: 90 dias.
- Quem usa os artefatos do `witrace`: só o próprio workflow, dentro da mesma execução (`.github/workflows/servidor.yml`,
  linhas 122, 164 e 187). Nenhum script busca artefato. O site baixa da versão publicada (`site/README.md`,
  `gh release download`). O `prepara_pendrive.sh` monta na própria máquina. Houve um único uso manual, já passado,
  de um artefato de branch (`docs/2026-10-06-2240-firewall-do-servidor.md:345`).
- Versões publicadas intactas: 1.3.0, 1.3.1, 1.3.2, 1.3.3, 1.4.0 e 1.4.1, com 6 arquivos cada. A execução da
  `1.4.0-2` não tem versão publicada nem marca hoje; ela foi substituída pela 1.4.1.
- Quem cita o `ci.yml` neste repositório, fora de `docs/`, `.github/` e `tarifas/`: só o selo do CI nos dois READMEs,
  que continua válido. Nenhuma trava lê o agendamento.

## Changes, per file

- **`witrace`, artefatos (ato que não se desfaz):** `gh api -X DELETE repos/aleonnet/witrace/actions/artifacts/<id>`
  nos 146. Antes, salvar a lista (id, nome, tamanho, execução, digest) em
  `witrace-artefatos-apagados.tsv`, no rascunho da sessão.
  Os pacotes de versão seguem nas versões publicadas. Os de branch nunca foram publicados e só voltam montando
  o commit de novo.
- **`.github/workflows/servidor.yml` do `witrace`:** `retention-days: 1` nos dois
  `actions/upload-artifact@v4` (linhas 92 e 173). A documentação da ação define o mínimo de 1 dia, e o artefato só
  serve dentro da execução. Um mês como outubro (30 execuções) acumularia 0,31 GB, abaixo do limite. Custo:
  `gh run download` de um pacote de branch só funciona por 1 dia; depois disso, repetir a execução inteira.
  Commit em `main` com `[skip ci]` na mensagem: o arquivo está no filtro de caminhos da linha 27 e, sem isso, o
  envio dispararia uma montagem paga. A documentação confirma que `[skip ci]` vale para `push`, e o repositório já
  usa esse recurso.
- **Forks, sem alterar código:** `gh workflow disable` em `microduck` (403623723, 403623725) e `vectorcraft`
  (381386275, 381386278). Volta com `gh workflow enable`.
- **`.github/workflows/ci.yml`:** remover as linhas 7 a 11 (o bloco `schedule` e seu comentário). `push` e
  `pull_request` ficam. Não uso `gh workflow disable` aqui porque ele desligaria também o CI de envio.
  **Custo:** o aviso de que uma versão nova do Home Assistant quebrou o instalador deixa de chegar sozinho e passa
  a aparecer só no próximo envio. Esse agendamento é gratuito e não causou o aviso; sai porque o dono mandou
  desligar o automático. Volta revertendo o commit.
- **Memória do projeto:** registrar que o número do armazenamento é acúmulo por hora, e não o tamanho guardado,
  com um ponteiro no `MEMORY.md`.

Commits sem linha de ferramenta, como manda a regra global. Sem bump: nada do produto muda.

## Scope

```
.github/workflows/ci.yml
```

O `servidor.yml` é de outro repositório, sem frente aberta, e fica fora desta trava. A mudança está declarada acima.

## Acceptance (EARS)

| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | os artefatos forem apagados | o `witrace` fica com zero artefatos ativos | `gh api "repos/aleonnet/witrace/actions/artifacts?per_page=1" --jq .total_count` | qualquer valor diferente de `0` |
| 2 | os artefatos forem apagados | as seis versões publicadas ficam intactas | `gh release view <tag> -R aleonnet/witrace --json assets --jq '.assets\|length'` nas seis | qualquer valor diferente de `6` |
| 3 | o `witrace` montar um pacote | o artefato vive 1 dia | `grep -c 'retention-days: 1' .github/workflows/servidor.yml` | valor diferente de `2` |
| 4 | o commit do `witrace` for enviado | nenhuma execução nova começa | `gh run list -R aleonnet/witrace --limit 1` | data posterior a 2026-10-07 |
| 5 | os forks forem desligados | os quatro workflows ficam desligados | `gh api repos/aleonnet/<fork>/actions/workflows/<id> --jq .state` | qualquer valor diferente de `disabled_manually` |
| 6 | o `ci.yml` for enviado | o CI roda pelo envio e fica verde | `gh run list -R aleonnet/haos-mac-mini --limit 1 --event push` | conclusão diferente de `success` |
| 7 | passar o horário do cron | não surge execução agendada | `gh run list -R aleonnet/haos-mac-mini --event schedule --limit 1` | data posterior à do envio; só se confere no dia seguinte, e fica declarado como pendente |

## Verification (after the last commit)

```
./tools/gate.sh
! grep -nE '^\s*(schedule:|- cron:)' .github/workflows/ci.yml && grep -qE '^  push:' .github/workflows/ci.yml && grep -qE '^  pull_request:' .github/workflows/ci.yml
```

Expected: o portão termina verde, e a segunda linha sai com código 0 e sem imprimir nada.

## Refutation

- A segunda linha da verificação reprova antes da edição, porque o `ci.yml` ainda tem o agendamento (linhas 7 e 11):
  rodar antes de editar e registrar a saída.
- O item 3 reprova antes da edição, com `0`: rodar antes de editar e registrar a saída.

## Out of scope

- `alumia-app` (93,3 MiB, último vencimento em 2027-01-07): sozinho fica abaixo do limite.
- `alumia`: público, 70,7 MiB. A documentação lida não confirma se armazenamento de repositório público é cobrado;
  mesmo se for, não muda a conclusão.
- Limite de gastos na conta: exige a permissão `user` no token e a decisão é do dono.
- Permissão `user` no `gh` e leitura do valor líquido da conta.

## Overnight policy

- Decidido à noite, com fonte: nada.
- Reservado ao dono: a frente inteira (apagar, enviar). Não roda sem acompanhamento.

## Open questions

Nenhuma. Se a chave física recusar um envio (`agent refused operation`, medido hoje no `git fetch` do `witrace`),
eu paro nesse envio e peço o toque; não troco de caminho para contornar a chave.
