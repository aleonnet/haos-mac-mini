---
status: aceito
---

# Fórmulas da fatura de energia — do consumo medido ao total a pagar

**Para quem revisa (pessoa ou LLM):** este é o único documento que você precisa
abrir. Cada fórmula abaixo tem número (F1…F13) e aponta para as quatro peças
que a carregam — se as quatro concordam, a fórmula está certa no produto:

| Peça | Arquivo | O que é |
|---|---|---|
| Dado | [`tarifas/energia_light_rj.json`](../tarifas/energia_light_rj.json) | cada parâmetro com valor, fonte, citação literal, data da conferência e grau de certeza |
| Regra | [`tarifas/fatura.py`](../tarifas/fatura.py) | a calculadora de referência, só biblioteca padrão; cada função traz o número da sua fórmula |
| Tela | [`packages/energia_br.yaml`](../packages/energia_br.yaml) | o package do Home Assistant: a mesma regra em template |
| Cerca | [`contract/pacotes.py`](../contract/pacotes.py) | sobe um Home Assistant e reprova se um sensor calculado do package diferir da calculadora |

A decisão de desenho está em
[2026-10-06-1600-fatura-como-funcao-do-medidor.md](2026-10-06-1600-fatura-como-funcao-do-medidor.md).

## Como conferir, em três comandos

```
python3 tarifas/fatura.py --confere     # as duas contas reais e os preços publicados, só com kWh e datas
./tools/embed.sh --check                # roda a de cima, e confere que o package carrega o mesmo dado do arquivo
./tools/pacotes-arnes.sh                # o Home Assistant dá o mesmo que a calculadora (precisa de Docker; roda no CI)
```

## O que entra

| Entrada | De onde vem | No package |
|---|---|---|
| Consumo do ciclo, por posto (kWh) | o medidor da casa | `sensor.fatura_energy_peak` · `_shoulder` · `_offpeak` |
| Data da leitura anterior e da leitura | a conta; depois do primeiro ciclo, o package avança sozinho | `input_datetime.fatura_ultima_leitura` · `fatura_proxima_leitura` |
| Média de consumo que define a faixa da iluminação pública (opcional) | a conta ou o histórico de consumo | `input_number.cosip_media_kwh` (0 = usa o consumo do ciclo) |
| Desde quando o medidor do ciclo em curso está contando | o próprio medidor guarda a hora em que foi criado ou zerado; um campo de ajuste vale no lugar dela quando o medidor foi recalibrado à mão | atributo `last_reset` de `sensor.fatura_energy_offpeak`; `input_text.ajuste_medido_desde` |
| Ajustes manuais (opcionais) | o dono, quando a conta trouxer número diferente | `input_text.ajuste_*` (vazio = vale o calculado) |

Nada mais. Tarifa, bandeira, ICMS, PIS, COFINS e iluminação pública são
calculados.

## As fórmulas

Grau de certeza, como no arquivo de dados: **lido na fonte** · **deduzido de
fatura** · **sem fonte**.

### F1 — os dias que a fatura conta

Do dia seguinte à leitura anterior até o dia da leitura, inclusive. Um ciclo de
03/09 a 06/10 conta 04/09 … 06/10: 27 dias de setembro e 6 de outubro.

- Dado: `bandeira.rateio.regra` · certeza: **deduzido de fatura** (a norma manda ratear por dias e não diz qual ponta entra; com 28 e 5 a conta de outubro não fecha)
- Regra: `dias_do_ciclo` · Tela: `Parâmetros do Ciclo` (laço `range(1, n + 1)`)

### F2 — bandeira do ciclo (R$/kWh)

```
bandeira = Σ adicional(mês de cada dia do ciclo) ÷ nº de dias ÷ 1000
```

- Dado: `bandeira.adicional` (R$/MWh por bandeira) e `bandeira.acionada` (bandeira de cada mês) · certeza: **lido na fonte**
- Fonte: base aberta da ANEEL, API em JSON sem chave (endereços em `bandeira.fonte`); adicionais pela REH 3.306/2024; rateio pela REN 1.000/2021, art. 307
- Mês que o arquivo não tem: vale o último mês conhecido antes dele, e o resultado sai marcado `estimado`
- Regra: `bandeira_do_ciclo` · Tela: `Parâmetros do Ciclo`, `sensor.bandeira_do_ciclo` · Ajuste: `input_text.ajuste_bandeira`

### F3 — tarifa com bandeira (R$/kWh)

```
tarifa_com_bandeira = tarifa + bandeira
```

É a "tarifa unitária" sem tributos que a conta imprime.

- Dado: `tarifa.convencional` · certeza: **lido na fonte** (PDF de tarifas da distribuidora; confere com duas contas)
- A base aberta da ANEEL traz outro valor para a mesma vigência (a resolução homologada, não o que passou a valer por despacho): por isso a tarifa vem da distribuidora
- Ajuste: `input_text.ajuste_tarifa`

### F4 — ICMS (%)

Pela faixa do consumo do ciclo, em kWh inteiros; a alíquota da faixa vale sobre
o consumo todo.

| Consumo | Alíquota |
|---|---|
| até 50 kWh | isento |
| 51 a 300 kWh | 18 % |
| 301 kWh ou mais | 24 % (20 % + 4 % de fundo estadual) |

- Dado: `icms.faixas` · certeza: **lido na fonte** (cabeçalhos das colunas do PDF de tarifas; LC estadual RJ 210/2023)
- Não conferido: se a faixa usa o kWh faturado ou o normalizado para 30 dias
- **Arredondamento — regra do produto, não da fonte:** a conta fatura kWh inteiros; o consumo medido tem casas decimais e é arredondado ao inteiro mais próximo (metade exata vai ao par) antes de escolher a faixa. 300,4 kWh contam como 300; 300,6, como 301
- Enquanto o ciclo corre, a faixa é a do consumo **projetado** (F13); num ciclo fechado que só foi medido em parte, a do consumo na proporção dos dias (F13b)
- Regra: `icms_da_faixa` · Tela: `sensor.icms_do_ciclo` · Ajuste: `input_text.ajuste_icms`

### F5 — PIS e COFINS (%)

Os do mês da leitura. Mudam todo mês e a distribuidora não os publica
separados: só a conta os traz.

- Dado: `pis_cofins.por_mes` · certeza: **deduzido de fatura**
- Mês sem dado: o último conhecido antes dele, marcado `estimado`. Chegando a conta, ou se acrescenta o mês ao arquivo de dados, ou se preenche o ajuste
- Regra: `pis_cofins_do_mes` · Tela: `sensor.pis_do_ciclo`, `sensor.cofins_do_ciclo` · Ajuste: `input_text.ajuste_pis`, `ajuste_cofins`

### F6 — fator de tributos

Tributos "por dentro": o ICMS incide sobre o valor bruto; PIS e COFINS, sobre o
valor sem ICMS.

```
fator = 1 ÷ ((1 − ICMS) × (1 − PIS − COFINS))
```

- Regra: `fator_de_tributos` · Tela: `sensor.fator_de_tributos`

### F7 — preço do kWh com tributos

```
preço = tarifa_com_bandeira × fator
```

É o "preço unitário com tributos" que a conta imprime, e o preço que o painel
de Energia usa.

- Tela: `sensor.preco_convencional`; no ciclo fechado, `sensor.preco_do_ciclo_fechado`

### F8 — energia (R$)

```
energia = consumo × preço
```

### F9 — os três impostos em reais

```
ICMS   = energia × ICMS%
PIS    = (energia − ICMS) × PIS%
COFINS = (energia − ICMS) × COFINS%
```

- Tela: `sensor.fatura_icms`, `sensor.fatura_pis`, `sensor.fatura_cofins` (ciclo fechado)

### F10 — iluminação pública (R$)

```
iluminação = mínimo( parcela_fixa(faixa)
                     + arredonda( coeficiente(faixa) × (TEIP + adicional da bandeira), 2 casas ),
                     teto )
```

- A **faixa** é a da média de consumo dos 12 ciclos anteriores ao reajuste anual, congelada até o reajuste seguinte; sem histórico, a do consumo do próprio ciclo. Até 120 kWh: isento
- A **bandeira** aqui é a do mês **anterior** ao da leitura (o mês do consumo), inteira, sem rateio
- A **TEIP** é a tarifa de referência da iluminação, em R$/MWh, fixa até o reajuste
- Dado: `iluminacao_publica.faixas` (61 faixas: limite, parcela fixa, coeficiente), `.teip_brl_mwh`, `.teto` · certeza: **lido na fonte**
- Fonte: Lei municipal RJ 5.132/2009 com a redação da Lei 9.049/2025; Decreto Rio 57.472/2025; tabelas mensais da Fazenda municipal. As 61 faixas reproduzem as tabelas de maio, agosto, setembro e outubro de 2026, linha a linha. A parcela fixa entra como a tabela a publica; o arredondamento é empírico
- Regra: `iluminacao_publica` · Tela: `sensor.iluminacao_publica_do_ciclo` · Ajuste: `input_text.ajuste_iluminacao`; faixa: `input_number.cosip_media_kwh`

### F11 — total a pagar

```
total = energia + iluminação + outros débitos − créditos
```

- Outros débitos e créditos não têm regra: são o que a conta trouxer (`input_text.ajuste_outros_debitos`, `ajuste_creditos`)
- Tela: `sensor.fatura_mensal_convencional` (ciclo em curso, com o consumo até agora), `sensor.fatura_projetada_do_ciclo`, `sensor.fatura_do_ciclo_fechado`

### F12 — a mesma fatura na Tarifa Branca

Troca só a tarifa de cada posto; bandeira, tributos e encargos são os mesmos.

```
energia_branca = ( kWh_ponta × (tarifa_ponta + bandeira)
                 + kWh_intermediário × (tarifa_intermediária + bandeira)
                 + kWh_fora_ponta × (tarifa_fora_ponta + bandeira) ) × fator
```

- Dado: `tarifa.branca`, `postos` · certeza: **lido na fonte** (PDF da Tarifa Branca da distribuidora; horários pela REH 3.014/2022, art. 11 — não conferido se a resolução de 2026 os repete)
- Ponta e intermediário só em dia útil; o intermediário é depois da ponta
- Tela: `sensor.fatura_mensal_branca`; a automação dos postos é gerada do arquivo de dados

### F13 — consumo projetado do ciclo em curso

Serve só para escolher as **faixas** (F4 e F10) antes de o ciclo terminar — sem
isso as primeiras horas de cada ciclo teriam o preço de quem é isento.

```
projetado = consumo até agora + taxa diária × dias do ciclo que a medição não cobriu

dias cobertos  = de quando o medidor do ciclo foi criado ou zerado (ou do início do ciclo, o que for mais tarde) até agora
taxa diária    = consumo do ciclo anterior ÷ dias MEDIDOS dele, se ele cobriu ao menos um dia;
                 senão, consumo até agora ÷ dias cobertos (o primeiro dia conta inteiro)
ciclo encerrado ou sem datas: projetado = consumo
```

Quem instala no meio de um ciclo mediu só parte dele: por isso a conta usa os
dias **cobertos pela medição**, não os dias do calendário. Medido desde o
início, com ciclo anterior completo, a fórmula é "o já medido + a média diária
do ciclo anterior × os dias que faltam".

- Não vem de fonte: é estimativa do produto, substituída pelo consumo real quando o ciclo fecha
- Regra: `consumo_projetado` · Tela: `sensor.consumo_projetado_do_ciclo`; entradas: a hora que o medidor guarda (ou `input_text.ajuste_medido_desde`) e `input_number.fatura_fechado_dias_medidos`
- Limite: o medidor é criado quando o package sobe; se a fonte de consumo só for ligada dias depois, esses dias contam como medidos

### F13b — consumo de faixa de um ciclo fechado medido em parte

```
dias medidos ≥ 1 e menores que os dias do ciclo:  consumo de faixa = consumo medido × dias do ciclo ÷ dias medidos
senão:                                            consumo de faixa = consumo medido
```

Só escolhe as faixas (F4 e F10) do ciclo fechado; a fatura dele continua sendo
o consumo medido × o preço. Os dias medidos são gravados pela automação ao
fechar.

- Regra: `consumo_de_faixa_do_fechado` · Tela: `sensor.consumo_de_faixa_do_ciclo_fechado`

## As duas contas, passo a passo

Números tirados de `python3 tarifas/fatura.py --confere` e da própria
calculadora em 2026-10-06. Entram só as datas, o consumo, a média da faixa da
iluminação (425 kWh) e as linhas sem regra.

| Passo | Conta de agosto/2026 | Conta de outubro/2026 |
|---|---|---|
| Leituras | 03/07 → 05/08 | 03/09 → 06/10 |
| Consumo | 304 kWh | 354 kWh |
| F1 dias | 33 (28 de julho, 5 de agosto) | 33 (27 de setembro, 6 de outubro) |
| F2 bandeira | amarela nos dois meses: 0,018850 | amarela em setembro, verde em outubro: 18,85 × 27 ÷ 33 ÷ 1000 = 0,015423 |
| F3 tarifa com bandeira | 0,94793 + 0,01885 = 0,96678 (conta: 0,96678) | 0,94793 + 0,015423 = 0,963353 (conta: 0,96335) |
| F4 ICMS | 304 kWh → 24 % | 354 kWh → 24 % |
| F5 PIS · COFINS | 1,23 % · 5,67 % | 1,01 % · 4,68 % |
| F6 fator | 1,413308 | 1,395175 |
| F7 preço | 1,366358 (conta: 1,36636) | 1,344046 (conta: 1,34405) |
| F8 energia | 415,37 (conta: 415,37) | 475,79 (conta: 475,78) |
| F9 ICMS · PIS · COFINS | 99,69 · 3,88 · 17,90 (conta: iguais) | 114,19 · 3,65 · 16,92 (conta: iguais) |
| F10 iluminação | faixa de 400 a 450 kWh, bandeira de julho amarela: 23,54 + arredonda(0,05839 × (684,41 + 18,85)) = 23,54 + 41,06 = 64,60 (conta: 64,60) | bandeira de setembro amarela: 64,60 (conta: 64,60) |
| Linhas sem regra | + 2,08 de complemento, − 10,13 de crédito | + 2,08 de complemento |
| F11 total | **471,92** (conta: 471,92) | **542,47** (conta: 542,46) |

Em outubro a conta traz 475,78 de energia e a calculadora, 475,79
(354 × 1,344046 = 475,792; com o preço impresso, 354 × 1,34405 = 475,794).
**Não sei explicar esse centavo** — a conta provavelmente soma parcelas
arredondadas em separado, que ela não mostra. Por isso a conferência aceita um
centavo de diferença nos valores em reais, e nenhuma na iluminação pública.

## O que não tem fonte, e o que não foi conferido

| Item | Situação | Como o produto trata |
|---|---|---|
| "Complemento" da iluminação pública de R$ 2,08 nas duas contas | **sem fonte.** Hipótese em `sem_fonte` no arquivo de dados: diferença entre a tabela antiga, ainda cobrada em janeiro/2026, e a lei nova, parcelada. Os números são coerentes e nenhuma conta fecha exatamente em 2,08 | ajuste manual (outros débitos) |
| PIS e COFINS do mês | não publicados | último mês conhecido, marcado `estimado`; ajuste manual |
| Quais dias contam no rateio da bandeira | deduzido de uma conta | ajuste manual da bandeira, se outra conta divergir |
| Faixa do ICMS pelo kWh faturado ou normalizado para 30 dias | não conferido | ajuste manual do ICMS |
| Horários de ponta depois da resolução de 2026 | fonte de 2022 | trocar `postos` no arquivo de dados e regenerar |
| Média de consumo que define a faixa da iluminação | não está em conta nenhuma que eu tenha visto; a faixa de 400 a 450 kWh é a que as duas contas cobram | campo da média; zero usa o consumo do ciclo |

## Como atualizar os dados

1. Editar `tarifas/energia_light_rj.json`: o valor, a `citacao` literal da fonte
   e `conferido_em`. Parâmetro sem fonte reprova (`DADO SEM FONTE:`).
2. `./tools/embed.sh` — regenera os dois blocos do package e as cópias do
   instalador.
3. `python3 tarifas/fatura.py --confere` e `./tools/pacotes-arnes.sh`.

| O que muda | Quando | Onde buscar |
|---|---|---|
| Bandeira do mês | todo mês | API da ANEEL (`bandeira.fonte.url`) |
| PIS e COFINS | todo mês | a conta |
| Tabela da iluminação pública | todo mês (muda com a bandeira); a faixa e a parcela fixa, uma vez por ano | Fazenda municipal (`iluminacao_publica.fonte.url`) |
| Tarifa | no reajuste anual (`tarifa.vigencia_fim`) | PDF da distribuidora (`tarifa.fonte.url`) |

## Fórmula → dado → regra → tela → cerca

| # | Dado (chave) | Regra (função) | Tela (sensor) | Cerca |
|---|---|---|---|---|
| F1 | `bandeira.rateio` | `dias_do_ciclo` | `parametros_do_ciclo` | `FORMULA DIVERGE:` (bandeira) · `CONTA NAO REPRODUZ:` |
| F2 | `bandeira.adicional`, `.acionada` | `bandeira_do_ciclo` | `bandeira_do_ciclo` | `FORMULA DIVERGE:` |
| F3 | `tarifa.convencional` | `calcula` | `parametros_do_ciclo` | `CONTA NAO REPRODUZ:` |
| F4 | `icms.faixas`, `casos_de_preco` | `icms_da_faixa` | `icms_do_ciclo` | `FORMULA DIVERGE:` (bordas de 300 e 301 kWh; 300,4 e 300,6) · `CONTA NAO REPRODUZ:` (os preços publicados por faixa) |
| F5 | `pis_cofins.por_mes` | `pis_cofins_do_mes` | `pis_do_ciclo`, `cofins_do_ciclo` | `FORMULA DIVERGE:` (mês sem dado) |
| F6 | — | `fator_de_tributos` | `fator_de_tributos` | `FORMULA DIVERGE:` (preço) |
| F7 | — | `calcula` | `preco_convencional` | `FORMULA DIVERGE:` |
| F8, F11 | — | `calcula` | `fatura_mensal_convencional`, `fatura_do_ciclo_fechado` | `FORMULA DIVERGE:` |
| F9 | — | `calcula` | `fatura_icms`, `fatura_pis`, `fatura_cofins` | `FORMULA DIVERGE:` |
| F10 | `iluminacao_publica.*` | `iluminacao_publica` | `iluminacao_publica_do_ciclo` | `FORMULA DIVERGE:` (isenção, faixa pelo consumo, teto) |
| F12 | `tarifa.branca`, `postos` | `calcula` | `fatura_mensal_branca` | `FORMULA DIVERGE:` · `MEDIDOR NAO ACOMPANHA:` (horários) |
| F13 | — | `consumo_projetado` | `consumo_projetado_do_ciclo` | `FORMULA DIVERGE:` (400 projeções sorteadas, e cinco cenários com o relógio do Home Assistant) |
| F13b | — | `consumo_de_faixa_do_fechado` | `consumo_de_faixa_do_ciclo_fechado` | `FORMULA DIVERGE:` |
| F2–F7, F10 | o arquivo inteiro | `calcula` | o texto da regra em `parametros_do_ciclo` | `FORMULA DIVERGE:` (600 ciclos sorteados, comparação exata) |
| próxima leitura | — | `proxima_depois_de` (no arnês) | automação de fechamento | `CICLO NAO ZERA:` (1.200 datas) |
| ajustes | — | `calcula(ajustes=…)` | `input_text.ajuste_*` | `AJUSTE IGNORADO:` |
| dado → tela | o arquivo inteiro | — | bloco `DADOS DA FATURA` | `DIVERGE` (`./tools/embed.sh --check`) |
