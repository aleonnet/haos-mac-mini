# HANDOFF — reforma navblue fechada em código: F-A a F-D · 2026-08-24

> **LEIA-ME PRIMEIRO.** Porta de entrada da frente do instalador. Supersede
> `HANDOFF-2026-08-24-gramatica-e-operacao.md`. Plano executado (v2 pós-banca,
> 3 lentes, 7 bloqueadores): `docs/planos_concluidos/2026-08-24-reforma-navblue-instalador.plan.md`.

## 0. ESTADO — confira no git, não neste parágrafo

- **Empurrado em 24/08/2026 sob ordem do dono** — main local = origin/main
  (logo · F3 · F-A · docs · F-B · F-C · F-D · logo v2 · quinas).
- Versão **0.2.0** (bump de fechamento) · CHANGELOG com a release datada.
- Portão `./tools/gate.sh` **limpo** — inclui as cercas novas: locale nas
  funções de fase e no cano inteiro, help executado flag a flag, enumerados
  contra o parser, dry-run read-only por snapshot, segredo em arquivo
  versionado, isca no cwd.
- CI do push: **verde nos 4 jobs** (portão · bash 3.2/stdin · contrato
  fixado · contrato stable). O raw publica a **0.2.0** — medido pelo cano.
- Clone do Mac mini: **pendente** — a máquina estava desligada na hora do
  push (`No route to host`); sincronizar com `git pull` quando ligar.

## 1. O QUE MUDA PARA QUEM USA (resumo das 4 fases)

| Área | Antes → Agora |
|---|---|
| Voz | 2 gramáticas → calha única ✔/▲/✖ com ASCII sob locale C e barra de fase |
| Falha | stack cru → assinatura de rede explicada + log preservado e nomeado |
| Memória | nada → manifesto `created`/`preexisting`/`pending` + `--profile last` + `last-run.log` |
| Remoção | prometida e morta → `--uninstall` que só remove o que PROVA ter criado |
| Diagnóstico | nada → `--doctor` em 5 seções com veredito |
| Atualização | nada → `--self-update` com recusa de downgrade |
| Docs | ESTADO/PLANO/INVENTARIO na raiz, ignorados → `docs/` versionados e LIMPOS, com cerca de segredo |

## 2. DECISÕES DESTA FRENTE (registro, não pergunta)

1. **VirtualBox nunca é removido automaticamente** pelo `--uninstall` — é
   extensão de sistema; `created` ganha a instrução do
   `VirtualBox_Uninstall.tool` da Oracle. Custo: o uninstall não desfaz 100%
   sozinho; ganho: nenhum risco de quebrar a máquina do usuário.
2. **`--self-update` com versões IGUAIS assume o publicado como canônico**
   (só a comparação de versão detecta downgrade). O bump 0.2.0 deste
   fechamento é o que faz o gate morder contra o main atrasado.
3. **Sem `rm -rf` no uninstall**: arquivo a arquivo com guarda de prefixo
   (o caminho vem do manifesto, que pode ter sido adulterado), diretório só
   por `rmdir`.
4. Originais de ESTADO/PLANO/INVENTARIO preservados em `.lixo-24-08/` (fora
   do git), na convenção da casa: mover, nunca apagar.

## 3. PLACAR DA BANCADA (rodada local, nesta máquina, hoje)

| # | Passo | Resultado |
|---|---|---|
| 1 | dry-run pelo cano, calha ✔/▲, exit 0 | ✅ |
| 2 | `NO_COLOR=1 \| cat`: zero escape ANSI | ✅ (cerca no portão) |
| 3 | `LC_ALL=C`: ASCII puro de ponta a ponta | ✅ (cerca, 0 bytes) |
| 4 | dry-run com `$HOME` sintético: diff vazio, nem log | ✅ (cerca) |
| 5 | execução real aborta em F1 (sem VBox); `last-run.log` nasce com rc e fase | ✅ (rc=4) |
| 6 | `--profile last` sem estado: erro nomeando o arquivo, exit 2 | ✅ |
| 7 | `--profile last` com estado: reproduz degrau/extras/vm/nome; id morto cai no default | ✅ |
| 8 | `--doctor`: 5 seções, veredito, nada escrito | ✅ |
| 9 | uninstall dry-run com `vbox preexisting`: PRESERVA nomeando o porquê | ✅ |
| 10 | uninstall real com `--confirm` certo: remove tudo que era `created`, placar 6-1 | ✅ |
| 11 | `--confirm` errado / manifesto perdido: **nada tocado** | ✅ |
| 12 | isca no cwd (nome certo, conteúdo errado): descartada, nada extraído | ✅ (cerca) |

**Pendente de device (Mac mini, depois do push):** F1 instalando o VirtualBox
de verdade (senha) · F3 com a imagem real · `--self-update` pós-push.

**Prompts prontos** — Funcionou: `Bancada no Mac mini OK nos passos <lista>.
Autorizo o push.` · Falhou: `Passo <N>: esperado <...>, observado <...>.
Saída literal: <colar>. Diagnostique antes de alterar.`

## 3b. LIÇÃO QUE CUSTOU DEFEITO NESTE FECHAMENTO

**A cerca de segredo varre o ÍNDICE do git — e eu rodei o portão antes do
`git add`.** A cópia do plano concluído entrou num commit local carregando a
senha da HGU citada nas pendências; a cerca só acusou na conferência seguinte.
Corrigido por amend (histórico ainda local — nada empurrado). Regra desde já:
**portão DEPOIS do `git add`, antes do commit** — é o índice que vai para o
mundo, não a árvore.

## 4. DÍVIDAS DECLARADAS

1. `listar()` com cabeçalhos pt hardcoded (fora da cerca de i18n).
2. `versao()` imprime `·` multibyte (fora do caminho da cerca de locale).
3. Contrato `0/100/1` ainda não é universal (só `garantir_virtualbox` e
   `fase_imagem`) — generaliza quando as fases F4+ nascerem.
4. Uninstall não remove o Extension Pack (ainda não é instalado por ninguém).
5. `HAOS_LANG=pt` sob locale C imprime acentos que o terminal não desenha.

## 5. O QUE FALTA (a frente seguinte)

- **F4 VM · F5 boot · F5b auto-start** — bloqueados até o VirtualBox existir
  no Mac mini (probe de `list ostypes`/`storagectl --help` no binário real).
- Push dos 7 commits (**só sob ordem**) e `git pull` no clone do Mac mini.
- **Logo e abertura: RATIFICADOS pelo dono em 24/08/2026** (após a correção
  das quinas — o "beiral" era leitura errada de anti-aliasing). Geometria
  refeita contra o vídeo oficial (beiral, ápice pontudo, base r2.2, traço
  1.75) + abertura em 4 atos (constelação → traço → sonar → respiração).
  Ver `docs/previews/2026-08-24-abertura/abertura.gif` e rodar
  `./tools/ui-demo.sh` no terminal. O escolhedor antigo foi para
  `.lixo-24-08/`.
- Pendências do dono: ratificar a abertura · `$TMPDIR/ha.tok` · troca da
  senha da HGU que passou pelo chat.
