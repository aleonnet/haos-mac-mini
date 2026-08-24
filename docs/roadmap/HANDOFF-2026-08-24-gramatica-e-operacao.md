# HANDOFF — gramática única e esqueleto de operação (F-A) · 2026-08-24

> **LEIA-ME PRIMEIRO.** Porta de entrada da frente do instalador. Supersede o
> `ESTADO.md` da raiz para o estado DESTA frente (o restante do ESTADO.md será
> absorvido e o arquivo removido na fase F-D). Plano em execução:
> `~/.claude/plans/linear-frolicking-wren.md` (v2 pós-banca — 3 lentes, 36
> achados, 7 bloqueadores incorporados).

## 0. ESTADO — confira no git, não neste parágrafo

- Repo `haos-mac-mini`, branch `main`. Antes desta frente: `9b7d887` (F3),
  **não empurrado** — `origin/main` está em `84d15a1`.
- Portão: `./tools/gate.sh` **limpo** (shellcheck 0.10.0 fixado, 24 checagens
  do verify, cercas novas incluídas).
- Clone do Mac mini (`~/haos-mac-mini`): **2+ commits atrás**, precisa de
  `git pull` após o push.
- Push, bump e release: **só sob ordem**.

## 1. O QUE MUDA PARA QUEM USA

| Antes | Agora |
|---|---|
| Duas gramáticas — fases em `[OK]`, demo em ✔ | Uma calha só (✔ · ▲ ✖), com barra de fase |
| Por SSH com locale C, glifos viravam lixo binário | Fallback ASCII verificado por cerca |
| Falha de curl despejava stack cru | Assinatura de rede reconhecida + últimas linhas do log + caminho do log preservado |
| `--help` prometia 6 flags que morriam em "não implementado" | Help só promete o que executa — e há cerca que roda cada flag publicada |
| `--profile --help` engolia a flag seguinte | Flag de valor valida shape na hora |
| Nenhum registro de execução | `~/.config/haos-mac-mini/last-run.log` com fases, tempos e rc |

## 2. DECISÕES DESTA FRENTE (registro, não pergunta)

1. **`ha_run_step` só embrulha comando-folha** (curl, unzip, installer) — nunca
   função de fase. Custo: fases não ganham spinner de graça; ganho: nenhum
   estado global se perde em subshell (era o caminho para o `.dmg` montado para
   sempre). Reversível por chamada.
2. **O download de 380 MiB da F3 fica FORA do spinner** com TTY: a barra nativa
   do curl informa mais. Sem TTY, stderr vai ao log e falha ganha diagnóstico.
3. **Metade en do MSG_DB é ASCII puro** (`—` → `-`): é a metade que o locale C
   seleciona. A pt mantém acentos — pt só é escolhido por locale pt_*, UTF-8 na
   prática.
4. **`--json` e `--bridge` saíram do produto** (não só do help): nunca
   publicados, não faziam o que diziam. Voltam com as fases que os usarem.

## 3. DÍVIDAS DECLARADAS

1. `listar()` (--list) tem cabeçalhos pt hardcoded ("PISO — …", "Degraus") —
   fora da cerca de i18n, que cobre só os call-sites da calha. Migrar quando
   `--list` for revisitada.
2. `versao()` imprime `·` multibyte — fora do caminho coberto pela cerca de
   locale (que exercita o dry-run). Inofensivo em UTF-8; sob C imprime 2 bytes.
3. `HAOS_LANG=pt` sob locale C produz pt com acentos em terminal que não os
   desenha — combinação pedida explicitamente, não default; sem tratamento.
4. Os documentos `ESTADO.md`/`PLANO.md`/`INVENTARIO.md` ainda estão na raiz,
   gitignorados — saem na F-D, DEPOIS da cerca de segredo (bloqueador B-5 da
   banca: repo público, histórico não esquece).

## 4. O QUE FALTA (ordem do plano)

- **F-B**: manifesto host/VM (`created`/`preexisting`/`pending`),
  `--profile last`, `--image` somando ao candidato local.
- **F-C**: `--uninstall` (fatos→plano→confirmação→execução), `--doctor`,
  `--self-update` com recusa de downgrade.
- **F-D**: cerca de segredo → docs para `docs/` limpos → este handoff absorve o
  ESTADO.md → CHANGELOG/bump/plano concluído.
- Bancada de 12 passos (no plano) — **local até o push**.

## 5. LIÇÕES QUE CUSTARAM DEFEITO NESTA FRENTE

1. **Cópia embutida atrasada valida o nada**: rodei a cerca de locale com o
   embed velho e ela deu "0 bytes" porque o script MORRIA antes de imprimir
   (unbound var) — verde pelo motivo errado. Regra: `embed.sh` imediatamente
   após QUALQUER edição na lib, antes de qualquer teste.
2. **`wait` solto sob `set -e` aborta antes do `return`** — o `ha_spin`
   original nunca reportaria a falha que existia para reportar.
3. **Cerca de texto pega o próprio comentário**: a primeira versão da cerca de
   gramática reprovou o comentário que a explicava e a expansão `${X[*]}` do
   bash. Cerca de string precisa excluir comentário e conhecer a sintaxe da
   linguagem que varre.
