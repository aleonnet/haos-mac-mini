# Fatura como função do medidor — só o Shelly entra; o resto é regra com fonte

status: aceito

> Cópia do plano como foi aprovado em 2026-10-06, limpa de identificadores da
> casa. O que mudou na execução está no HANDOFF da frente e no diário.

## Context

De manhã o dono decidiu que preço e impostos viriam digitados da fatura. Depois
de ver o painel funcionando, mudou o rumo (2026-10-06, por escrito): *"o input
deveria ser apenas a medição do Shelly, dado que alíquotas, iluminação pública
tem fontes e critérios"*; *"tudo ser função do Shelly, mas obviamente mantendo o
ajuste manual se necessário"*; *"janela de ciclo ser dia inteiro"*; *"confira as
fontes e deixe tudo documentado e fórmulas linkadas para ficar simples para
qualquer LLM revisar"*; e sobre onde registrar os critérios: *"isso no futuro
tem potencial para virar um App, consultando as fontes e calculando"*.

Conferi as fontes uma a uma (três pesquisas independentes, e os números-chave
refeitos por comando meu). Resultado: **dá**. Com os kWh do medidor e as duas
datas de leitura, as duas faturas reais saem ao centavo — sem digitar preço,
imposto nem iluminação pública:

| Parcela | Regra | Fonte conferida |
|---|---|---|
| Tarifa (0,94793; Branca 1,73992 · 1,20499 · 0,83447) | tabela da distribuidora | PDF de tarifas da própria Light, URL fixa — baixado hoje. **Fecha a pendência da Branca.** |
| Bandeira do ciclo | adicional do mês × dias de cada mês ÷ dias do ciclo; conta do dia seguinte à leitura anterior até o dia da leitura | Base aberta da ANEEL (setembro amarela 18,85 R$/MWh, outubro verde) e REN 1.000/2021 art. 307. Quais dias contam não está na norma: sai da fatura (0,01885 × 27/33 = 0,01542) |
| ICMS | por faixa de consumo do ciclo: até 50 kWh isento · 51–300 → 18 % · 301+ → 24 %, sobre o consumo inteiro | mesmo PDF da Light; LC estadual 210/2023 |
| PIS e COFINS | mudam todo mês; a Light **não publica** os dois separados | só a fatura. Entram os meses conhecidos; mês sem dado usa o último conhecido |
| Iluminação pública | parcela fixa da faixa (truncada) + coeficiente × (TEIP + bandeira do mês do consumo), arredondado; faixa pela média de 12 ciclos, congelada até o reajuste | Lei municipal 5.132/2009 com a 9.049/2025; tabelas mensais da Fazenda do Rio. 64,60 = 23,54 + 0,05839 × (684,41 + 18,85) |
| "Complemento Jan/26" (2,08) | **sem regra em fonte nenhuma** | fica como ajuste manual |

**Fonte melhor que PDF — procurada a pedido do dono, e não há.** Vasculhei o
conteúdo público inteiro do site da Light pela interface de dados em JSON que
fica por trás das páginas (60 listas, cerca de 1.300 itens de conteúdo, 500
arquivos nas duas bibliotecas de documentos):

| O quê | O que o site da Light tem | Melhor fonte que existe |
|---|---|---|
| Tarifa e Tarifa Branca | só os dois PDFs; nenhuma planilha, nenhum item de conteúdo com número | o PDF da Light (texto extraível por máquina, endereço fixo). A base aberta da ANEEL é JSON, mas traz o valor errado para 2026 |
| Bandeira | item de conteúdo em JSON ("Set 2026 - Amarela", "Out 2026 - Verde") | a API JSON da ANEEL — melhor que a da Light |
| ICMS | texto genérico; os números só nas colunas do PDF de tarifas | PDF da Light + lei estadual |
| PIS e COFINS | nenhum número em lugar nenhum; a Light remete à área logada ("Composição do Faturamento") | a fatura. A área logada pede CPF, senha e verificação anti-robô — não entrei |
| Iluminação pública | um PDF por município (o do Rio está em junho/2026) | as tabelas mensais da Fazenda do Rio (PDF, e dois meses em DOCX) |
| Complemento de 2,08 | nenhuma menção a "complemento", "retroativo" ou à Lei 9.049 | nenhuma |

Sobre o complemento, uma hipótese que os números sustentam mas não provam: em
janeiro/2026 a Prefeitura ainda publicou a tabela antiga (R$ 31,48 para a faixa
do consumo daquele mês), e pela lei nova, em vigor desde 01/01, o valor seria
entre R$ 81,84 e R$ 83,35. A diferença, cerca de R$ 50 a 52, dividida por 2,08,
dá 24 a 25 parcelas — coerente com o rótulo "Complemento COSIP RJ - Jan/26", mas
nenhuma das contas fecha exatamente em 2,08. O texto inteiro dessa linha na
conta de papel (cortado na foto) diria o número da parcela. Fica como ajuste
manual, com essa hipótese registrada.

Achados que mudam o desenho: o ICMS depende do consumo (um ciclo de 288 kWh
paga 18 %, não 24 %); os horários de ponta da Light são 17h30–20h30 e o
intermediário só **depois** da ponta, 20h30–22h30 — o package trazia uma janela
de exemplo diferente; e a janela de dia inteiro que o dono propôs é a que
melhor fecha com a conta (356,90 kWh contra 354; meio-dia a meio-dia dava
358,33).

Resultado pretendido: nenhum campo obrigatório. A fatura inteira é calculada do
consumo; cada parâmetro tem valor padrão com fonte e pode ser corrigido à mão.
Regra, dado e tela ficam em três peças separadas, para um aplicativo futuro
trocar só a última.

## Risk band

**critical** — reescreve o cálculo de um package do produto público e mexe de
novo na instância de produção do dono (implantar, recalibrar o medidor do ciclo,
corrigir custo no histórico). Por isso: fontes conferidas antes; calculadora de
referência que tem de reproduzir as duas faturas; cerca que compara o Home
Assistant com a referência e é refutada; **ensaio em réplica local com os dados
reais antes de tocar a casa**; e a instância só é tocada no fim, de uma vez,
quando tudo já pode terminar (lição desta manhã).

## Impact sweep (commands run now)

```
curl -fsS --max-time 40 -G "https://dadosabertos.aneel.gov.br/api/3/action/package_search" --data-urlencode 'q=bandeira' --data-urlencode 'rows=8'
for rid in 0591b8f6-fe54-437b-b72b-1aa2efd46e42 5879ca80-b3bd-45b1-a135-d9b77c1d5b36; do echo "== $rid"; curl -fsS --max-time 40 -G "https://dadosabertos.aneel.gov.br/api/3/action/datastore_search" --data-urlencode "resource_id=$rid" --data-urlencode 'limit=400'
grep -n "400 até 450\|350 até 400\|450 até 500" "$f"
fixa = math.floor(22.66*1.039*100)/100; var = round(0.05839*(684.41+18.85), 2); print('outubro:', fixa, '+', var, '=', round(fixa+var, 2))
curl -fsS -o bt.pdf "https://www.light.com.br/Documentos%20Compartilhados/Entenda-Conta-Casa-Arquivos-Relacionados/Tarifas%20Baixa%20Tens%C3%A3o.pdf"
grep -n "Residencial" bt.txt | head -4
grep -n -i "2026\|ponta\|interm" branca.txt | head -14
("03/09 00:00 → 06/10 00:00", ts(3, 9, 0), ts(6, 10, 0)),
curl -sS --max-time 40 -H 'accept: application/json; odata=nometadata' "https://www.light.com.br/_api/Web/Lists?\$select=Title,ItemCount,BaseTemplate,Hidden,LastItemModifiedDate&\$filter=Hidden%20eq%20false" -o listas.json
for m in re.finditer(r"(?i)complemento|retroativ|lei\s*n?[ºo°.]*\s*9\.?049|5\.132|TEIP", t):
grep -n "550 até 600\|400 até 450" txt/0[3-5]-COSIP-para-site*.txt | cut -c1-170
grep -n "embed" tools/gate.sh verify.sh | head -12
sed -n '283,300p;344,362p' verify.sh
```

O que cada um mediu (2026-10-06, 15:02–15:15 -03):

| Medição | Achado |
|---|---|
| Base aberta da ANEEL, bandeiras | conjunto com API ativa, atualizado em 05/10: set/2026 Amarela 18,85 · out/2026 Verde; adicionais pela REH 3.306/2024 |
| Tabela de outubro da Fazenda do Rio | "Superior a 400 até 450 — R$ 64,60", bandeira amarela, TEIP 0,68441 |
| Conta da iluminação pública | 23,54 + 41,06 = 64,60; com a bandeira de outubro (verde) a próxima dá 63,50 |
| PDF de tarifas da Light, "Setembro/2026" | Residencial 1,00833 · 1,22967 · 1,32675, sem tributos 0,94793 — as três colunas são ICMS 0, 18 e 24 % |
| PDF da Tarifa Branca da Light | sem tributos: ponta 1,73992 · intermediária 1,20499 · fora ponta 0,83447 |
| Consumo do medidor por janela | 03/09 00:00 → 06/10 00:00: 356,903 kWh (medidores 356,870), +2,90 sobre a conta; meio-dia a meio-dia: +4,33 |
| Onde o portão confere cópias | `tools/gate.sh` e `verify.sh` delegam a `tools/embed.sh --check` — um só lugar; é ali que entra a conferência do arquivo de dados |

Arquivos do escopo lidos por inteiro: o package de energia, o painel Custos, a
ferramenta de embutir. O instalador entra só pelas cópias embutidas,
regeneradas pela ferramenta.

## Changes, per file

**Dado — a fonte da verdade (o que um aplicativo leria)**

- `tarifas/energia_light_rj.json` (novo) — todo parâmetro com valor, unidade,
  vigência, endereço da fonte, citação literal, data da conferência e grau de
  certeza (lido na fonte · deduzido de fatura · sem fonte): tarifa convencional
  e Branca; horários dos postos; adicional de cada bandeira e bandeira acionada
  por mês; faixas do ICMS; PIS e COFINS dos meses conhecidos; as 60 faixas da
  iluminação pública com parcela fixa, coeficiente, TEIP e teto; a regra de
  contagem de dias. E os **casos de conferência**: as duas faturas, só com os
  números (sem identificação).
- `tarifas/fatura.py` (novo, só biblioteca padrão) — a calculadora de
  referência: recebe kWh por posto, as duas datas de leitura e os ajustes, e
  devolve a fatura decomposta. `--confere` refaz os casos de conferência e
  reprova se algum sair mais de um centavo fora, ou se algum parâmetro estiver
  sem fonte.

**Regra — o documento que qualquer LLM abre**

- `docs/2026-10-06-1600-formulas-da-fatura-de-energia.md` (novo) — cada fórmula
  numerada, com: a regra em uma linha, as chaves do arquivo de dados que usa, a
  fonte, a função da calculadora e o sensor do package que a implementam, e as
  duas faturas refeitas passo a passo. Uma tabela final liga fórmula → dado →
  código → cerca.
- `docs/2026-10-06-1600-fatura-como-funcao-do-medidor.md` (novo, decisão,
  status aceito) e `docs/2026-10-06-1200-fonte-da-tarifa-de-energia.md` marcado
  como superado por ela — a de manhã fica, como manda a norma.

**Tela — o package só consome**

- `tools/tarifas-bloco.py` (novo) — gera, do arquivo de dados, o bloco de dados
  e os dois sensores de parâmetros do package (ciclo em curso e ciclo fechado,
  o mesmo texto com entradas diferentes); `--check` reprova divergência.
- `tools/embed.sh` — o `--check` passa a chamar também essa conferência. É o
  ponto único que `tools/gate.sh` e `verify.sh` já usam.
- `packages/energia_br.yaml`
  - Saem os campos digitados da fatura (preço, tarifa, alíquotas, encargos).
  - Entram os parâmetros calculados: bandeira do ciclo, ICMS pela faixa do
    consumo, PIS e COFINS do mês, fator, preço, iluminação pública — para o
    ciclo em curso e para o fechado.
  - **Ajustes manuais** em campos de texto: vazio = usa o padrão; preenchido =
    vale o seu. Tarifa, bandeira, ICMS, PIS, COFINS, iluminação pública, outros
    débitos, créditos. Mais a média de consumo que define a faixa da iluminação
    (zero = usa o consumo do ciclo, que é a regra da lei para quem não tem
    histórico) e o total da conta para comparar.
  - **Ciclo em dia inteiro:** fecha à 00:00 da data de leitura; guarda as duas
    datas do ciclo fechado; a próxima leitura passa a ser assumida um mês
    depois, e continua corrigível.
  - Consumo projetado do ciclo, para escolher a faixa do ICMS enquanto o ciclo
    corre; o ciclo fechado usa o consumo real.
  - Horários dos postos corrigidos para os da Light.
- `dashboards/custos_br.yaml` — a parte de energia vira: ciclo em curso (consumo,
  projeção, fatura estimada) · ciclo fechado × conta · parâmetros em vigor ·
  ajustes manuais. Linhas simples, sem texto de explicação.
- `haos-install.sh` — as cópias embutidas, pela ferramenta, e a frase que o
  instalador diz ao configurar o painel de Energia (hoje manda digitar a conta;
  passa a dizer que o preço sai do consumo e pode ser ajustado no painel Custos).

**Cerca**

- `contract/pacotes.py`, `tools/pacotes-arnes.sh` — a cerca deixa de digitar
  preço: informa datas e consumo e compara cada número do Home Assistant com a
  calculadora de referência, numa grade de cenários (40, 288, 300, 301, 354, 460
  e 1.200 kWh; ciclo dentro de um mês e atravessando bandeira diferente; mês sem
  PIS conhecido; com e sem ajuste manual). As garantias de hoje ficam (soma das
  fases, medidores, persistência, estado de fábrica, água, gás).
- `.github/workflows/ci.yml` — o trabalho dos packages roda também a
  conferência da calculadora.

**Registro**

- `CHANGELOG.md`, `docs/README.md`, handoff novo (o da manhã marcado como
  superado), diário, plano concluído e índice.

**Instância desta casa** — `inventario/custos/`, fora do versionamento, e só
depois do ensaio em réplica

- Implantar package e painel; informar a faixa da iluminação (a das contas:
  400–450) e o ajuste do complemento (2,08).
- Refazer o ciclo fechado na janela de dia inteiro (03/09 00:00 → 06/10 00:00,
  356,87 kWh) e o ciclo em curso desde 06/10 00:00.
- Corrigir o custo no histórico pelo preço do ciclo a que cada hora pertence
  (hoje as primeiras 12 horas de 03/09 e os dias antes dela estão no preço
  antigo).
- Escrita pelo mesmo caminho de hoje: lotes de comandos do Home Assistant
  executados na sessão do painel que o dono deixa aberta, sem senha —
  **aprovando este plano o dono aprova esse caminho**.

## Scope

```
tarifas/**
tools/tarifas-bloco.py
tools/embed.sh
tools/pacotes-arnes.sh
packages/energia_br.yaml
dashboards/custos_br.yaml
haos-install.sh
contract/pacotes.py
.github/workflows/ci.yml
CHANGELOG.md
docs/README.md
docs/2026-10-06-1600-formulas-da-fatura-de-energia.md
docs/2026-10-06-1600-fatura-como-funcao-do-medidor.md
docs/2026-10-06-1200-fonte-da-tarifa-de-energia.md
docs/roadmap/HANDOFF-2026-10-06-fatura-funcao-do-medidor.md
docs/roadmap/HANDOFF-2026-10-06-energia-na-fatura.md
docs/roadmap/decisoes/2026-10-06-1600-fatura-funcao-do-medidor.md
docs/planos_concluidos/2026-10-06-1600-fatura-funcao-do-medidor.plan.md
docs/planos_concluidos/README.md
inventario/custos/**
```

**Arquivos novos declarados:** `tools/tarifas-bloco.py`,
`docs/2026-10-06-1600-formulas-da-fatura-de-energia.md`,
`docs/2026-10-06-1600-fatura-como-funcao-do-medidor.md`,
`docs/roadmap/HANDOFF-2026-10-06-fatura-funcao-do-medidor.md`,
`docs/roadmap/decisoes/2026-10-06-1600-fatura-funcao-do-medidor.md`,
`docs/planos_concluidos/2026-10-06-1600-fatura-funcao-do-medidor.plan.md`, e
tudo sob `tarifas/`.

## Acceptance (EARS)

| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | o arquivo de dados é lido | ter fonte, citação e data de conferência em todo parâmetro | `python3 tarifas/fatura.py --confere` | imprime `DADO SEM FONTE:` |
| 2 | a calculadora recebe só kWh e datas das duas faturas | devolver 471,92 e 542,46, com no máximo um centavo de diferença, e cada parcela impressa na conta | `python3 tarifas/fatura.py --confere` | imprime `CONTA NAO REPRODUZ:` |
| 3 | o arquivo de dados muda | manter o bloco do package idêntico ao gerado | `./tools/embed.sh --check` | imprime `DIVERGE` |
| 4 | datas e consumo são informados ao Home Assistant | dar, em cada cenário da grade, o mesmo que a calculadora — bandeira, ICMS, PIS, COFINS, preço, iluminação e total | `./tools/pacotes-arnes.sh` | imprime `FORMULA DIVERGE:` |
| 5 | um ajuste manual é preenchido, e depois apagado | usar o valor do dono, e voltar ao padrão | `./tools/pacotes-arnes.sh` | imprime `AJUSTE IGNORADO:` |
| 6 | chega a 00:00 da data de leitura | fechar o ciclo uma vez, guardar as duas datas e assumir a próxima leitura um mês depois | `./tools/pacotes-arnes.sh` | imprime `CICLO NAO ZERA:` |
| 7 | a instalação é nova | não mostrar número inventado e nascer sem ajuste nenhum | `./tools/pacotes-arnes.sh` | imprime `ESTADO DE FABRICA:` |
| 8 | as garantias de antes são reexecutadas | continuar valendo (soma das fases, medidores, persistência, referências, água, gás) | `./tools/pacotes-arnes.sh` | imprime `SOMA PARCIAL:`, `MEDIDOR NAO ACOMPANHA:`, `CAMPO NAO PERSISTE:`, `REFERENCIA INEXISTENTE:`, `AGUA NAO REPRODUZ:` ou `GAS NAO REPRODUZ:` |
| 9 | o portão do produto roda depois da frente | continuar íntegro | `./tools/gate.sh` | imprime `[ERRO]` ou `checagem(ns) falharam` |
| 10 | a instância é ajustada | ter os arquivos do repositório, o ciclo fechado igual ao medidor na janela de dia inteiro e o custo de cada hora pelo preço do ciclo dela | `bash inventario/custos/verifica-custos.sh` | imprime `PACOTE DIVERGE:`, `HISTORICO DIVERGE:`, `SALTO REMANESCENTE:` ou `MEDIDOR DIVERGE:` |
| 11 | a documentação é escrita | não ter link interno quebrado | `lychee --offline --root-dir . docs/` | qualquer erro listado |

## Verification (after the last commit)

```
./tools/gate.sh
./tools/embed.sh --check
python3 tarifas/fatura.py --confere
./tools/pacotes-arnes.sh
"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/custos/implanta-pacotes.sh inventario/custos/verifica-custos.sh
bash inventario/custos/verifica-custos.sh
lychee --offline --root-dir . docs/
```

Expected: portão em `RESULTADO: portão limpo`; todos os blocos idênticos;
`FATURAS OK`; `PACOTES OK`; verificador de shell sem nenhuma linha;
`CUSTOS OK`; zero erros de link.

## Refutation

A calculadora e a cerca nova são escritas antes do package novo; a cerca tem de
reprovar o package de hoje. Depois, cada uma é refutada com o defeito plantado
numa cópia, e as fontes conferidas por impressão digital antes e depois.

- `CONTA NAO REPRODUZ:` — trocar o divisor do rateio da bandeira (28 dias em vez
  de 27); cobrar 24 % de ICMS num ciclo de 288 kWh; arredondar em vez de truncar
  a parcela fixa da iluminação.
- `DADO SEM FONTE:` — apagar a fonte de um parâmetro.
- `DIVERGE` — alterar um número no bloco do package sem passar pelo arquivo de dados.
- `FORMULA DIVERGE:` — no package: usar a bandeira do mês da leitura para o
  ciclo inteiro; ignorar a faixa do ICMS; usar na iluminação a bandeira do mês
  da fatura em vez da do mês do consumo.
- `AJUSTE IGNORADO:` — fazer um sensor ler o padrão mesmo com ajuste preenchido.
- `CICLO NAO ZERA:` — devolver o fechamento ao meio-dia; não gravar as datas do
  ciclo fechado; não avançar a próxima leitura.
- `HISTORICO DIVERGE:` — rodar o portão da casa antes do ajuste: tem de reprovar
  pelo custo das horas no preço antigo.

## Out of scope

- **Buscar as fontes automaticamente pela internet.** Os endereços que uma
  máquina consegue ler ficam registrados no arquivo de dados (a bandeira tem API
  oficial em JSON; tarifa e iluminação são PDF) — é o ponto de partida do
  aplicativo, não desta frente. Consequência aceita pelo dono: bandeira, PIS,
  COFINS e iluminação valem pelo último valor conhecido até alguém atualizar o
  arquivo de dados ou preencher o ajuste.
- Reescrever no histórico a divisão por posto das horas contadas com a janela de
  horários antiga: a correção vale daqui para a frente.
- O "Complemento Jan/26": sem fonte; fica como ajuste manual.
- Subir a versão do produto, publicar ou empurrar para o remoto: só sob ordem.
- Água, gás, e a causa dos sumiços do medidor em horário fixo.

## Overnight policy

- Decidido de noite, com fonte: forma dos sensores, textos de documentação,
  valores que já têm fonte conferida.
- Reservado ao dono, e proibido de madrugada: implantar na instância, recalibrar
  medidor, ajustar histórico, reiniciar o Core, empurrar para o remoto.

## Open questions

- Nenhuma. Premissas registradas, todas corrigíveis por ajuste manual: (a) a
  contagem de dias da bandeira é a que a fatura de outubro mostra; (b) PIS e
  COFINS seguem o mês da leitura; (c) a faixa do ICMS é pelo consumo do ciclo
  como medido, sem normalizar para 30 dias; (d) a faixa da iluminação pública
  desta casa é a de 400–450 kWh, a que as duas contas cobram — a média exata de
  mai/25 a abr/26 não está em nenhuma conta que eu tenha visto.
