# HANDOFF — a fatura como função do medidor · 2026-10-06

> **LEIA-ME PRIMEIRO.** Porta de entrada da frente do instalador. Supersede
> `HANDOFF-2026-10-06-energia-na-fatura.md`.

## 0. ESTADO — confira no git, não neste parágrafo

- Versão do produto **inalterada** (`HAOS_INSTALL_VERSION`): as mudanças estão
  em `## [Unreleased]` do `CHANGELOG.md`. Subir versão, publicar e empurrar
  para o remoto: **só sob ordem**.
- Esta frente **tocou o produto público**: o package de energia (reescrito), o
  painel Custos, as cópias embutidas e uma frase do instalador, a cerca dos
  packages, o roteiro das cópias embutidas, o CI; e criou `tarifas/` (dado e
  calculadora) e `tools/tarifas-bloco.py`.
- A parte da instância desta casa vive em `inventario/custos/`, fora do
  versionamento. Estado dela: seção 6.

## 1. O que a frente entregou

De manhã o preço e os impostos passaram a vir digitados da conta. À tarde o
dono mudou o rumo: só o medidor entra; o resto é regra com fonte, com ajuste
manual. Decisão em
[2026-10-06-1600-fatura-como-funcao-do-medidor.md](../2026-10-06-1600-fatura-como-funcao-do-medidor.md).

| Peça | Onde | O que faz |
|---|---|---|
| Dado | `tarifas/energia_light_rj.json` | cada parâmetro com valor, fonte, citação literal, data da conferência e grau de certeza |
| Regra | `tarifas/fatura.py` e [as fórmulas numeradas](../2026-10-06-1600-formulas-da-fatura-de-energia.md) | a calculadora de referência: consumo e datas entram, a fatura decomposta sai |
| Tela | `packages/energia_br.yaml`, `dashboards/custos_br.yaml` | a mesma regra em template; dois blocos gerados do arquivo de dados |
| Cerca | `contract/pacotes.py`, `tools/embed.sh --check`, `tarifas/fatura.py --confere` | o Home Assistant tem de dar o mesmo que a calculadora; o package tem de carregar o dado do arquivo; a calculadora tem de reproduzir as contas |

O que mudou para quem usa: nenhum campo obrigatório; cada parâmetro tem ajuste
manual (vazio vale o calculado); o ciclo fecha à 00:00 da data de leitura,
guarda as duas datas e assume a próxima um mês depois (nunca no passado); o
preço do ciclo em curso escolhe a faixa do ICMS pelo consumo projetado,
contando só os dias de fato medidos; os horários dos postos são os da
distribuidora.

## 2. As provas (comandos rodados no ato, 2026-10-06)

| Portão | Resultado |
|---|---|
| `./tools/pacotes-arnes.sh` contra o package **da manhã** (cerca nova) | reprovou: 36 falhas em 6 tokens |
| `python3 tarifas/fatura.py --confere` | `FATURAS OK`: duas contas reais (471,92 e 542,47 contra 471,92 e 542,46), os três preços com tributos publicados, as quatro bordas das faixas do ICMS e quatro casos de arredondamento |
| `./tools/pacotes-arnes.sh`, versão fixada (2026.8.3) e estável (2026.9.4) | `PACOTES OK — 14 garantias` nas duas |
| Leitura fria adversarial sobre o diff, duas rodadas (o teto) | 1ª rodada **reprovou**: 4 bloqueadores e 8 avisos — buracos da cerca e dois defeitos de produto. 2ª rodada **reprovou**: os 12 da primeira caíram; 1 bloqueador novo no conserto (os dias medidos contavam da meia-noite do dia da instalação) e 5 avisos — todos consertados e contraprovados depois dela, sem terceira rodada (diário) |
| Defeitos plantados, um por vez, em cópia do repositório | ver a contagem no diário; fontes com a mesma impressão digital antes e depois |
| `./tools/embed.sh --check` | a calculadora, os dois blocos gerados e os oito embutidos |
| `./tools/gate.sh` | `RESULTADO: portão limpo` |
| Ensaio geral em réplica local, com as estatísticas reais, duas vezes (a segunda com o package final) | as seis etapas do ajuste da casa, e o portão da casa em `CUSTOS OK` contra a réplica |

O detalhe, com hora, está em
[decisoes/2026-10-06-1600-fatura-funcao-do-medidor.md](decisoes/2026-10-06-1600-fatura-funcao-do-medidor.md).

## 3. Decisões que eu tomei

| Decisão | Custo | Reversível |
|---|---|---|
| Um conjunto só de ajustes manuais, valendo para o ciclo em curso e para o fechado | um ajuste de bandeira ou de ICMS feito para um ciclo continua valendo no outro até ser apagado | sim |
| Consumo projetado do ciclo (o já medido + a taxa diária nos dias que a medição não cobriu) para escolher as faixas | o preço do ciclo em curso pode mudar se a projeção atravessar 300 kWh | sim |
| A projeção conta os dias de fato medidos: desde a hora em que o medidor do ciclo foi criado ou zerado (ele mesmo a guarda), e, no ciclo fechado, os dias que a automação grava ao fechar — acréscimo ao plano, vindo da leitura fria | um campo gravado pela automação e um campo de ajuste a mais; quem instala no meio do ciclo deixa de cair na faixa errada | sim |
| Consumo com casas decimais é arredondado ao inteiro mais próximo antes de escolher a faixa do ICMS — regra do produto, a fonte só fala em kWh inteiros | perto de 50 e de 300 kWh a faixa depende de décimos | sim |
| A próxima leitura assumida nunca fica no passado | parado mais de um mês, o consumo de dois ciclos fica num só | sim |
| `./tools/embed.sh --check` passou a rodar também a calculadora contra as contas — acréscimo ao plano | o portão local fica alguns décimos de segundo mais lento | sim |
| Os dois sensores de parâmetros compartilham um texto por âncora do YAML, em vez de serem gerados por ferramenta — desvio do plano | o sensor descobre qual é pelo próprio identificador | sim |
| A ferramenta gera também a automação dos postos, a partir dos horários do arquivo de dados — acréscimo ao plano | mais um bloco gerado | sim |
| O registro do Core entra na cerca (erro de template reprova) — acréscimo ao plano | uma garantia e um token a mais (`ERRO NO REGISTRO:`) | sim |
| Os três preços publicados pela distribuidora entram como casos de conferência — acréscimo ao plano | sete casos a mais na calculadora | sim |
| Os campos de ajuste só aceitam número (ponto ou vírgula) | texto qualquer é recusado pelo próprio Home Assistant | sim |
| As datas de leitura das duas contas entram nos casos de conferência | são necessárias ao rateio da bandeira; não identificam ninguém | sim |
| Conserto de `tools/embed.sh --check` (saía com 1 em vez de 3 ao achar divergência) | nenhum | sim |

## 4. Dívidas declaradas

- **Bandeira, PIS, COFINS e tabela da iluminação não se atualizam sozinhos.**
  Valem pelo último valor conhecido até alguém editar o arquivo de dados (e
  regenerar) ou preencher o ajuste. O ciclo fechado avisa quando usou
  estimativa. Buscar as fontes pela internet ficou fora desta frente.
- **PIS e COFINS do ciclo em curso são sempre estimativa**: só a conta os traz.
- **O arquivo de dados é de uma distribuidora e de um município.** O produto
  ainda não tem como escolher outro arquivo na instalação.
- **O "complemento" de R$ 2,08 não tem fonte**; entra como ajuste manual.
- **Não conferido:** se a faixa do ICMS usa o kWh faturado ou o normalizado
  para 30 dias; se a resolução de 2026 repete os horários de ponta da de 2022;
  quais dias contam no rateio da bandeira além da conta que serviu de prova.
- **A projeção é estimativa do produto, não regra da distribuidora.** Sem ciclo
  anterior ela usa a taxa do próprio ciclo, com o primeiro dia contado inteiro:
  nas primeiras horas de uma instalação nova a faixa é a do pouco que se mediu.
  E sem as datas de leitura informadas não há projeção: vale o consumo
  acumulado.
- **No arranque do Home Assistant**, por instantes, o consumo do ciclo pode
  valer zero antes de os medidores restaurarem; com ciclo anterior a projeção
  não sente, sem ele o preço pode sair na faixa de isento por esse instante.
  Não medi.
- **A conta traz um centavo a menos na energia de outubro** (475,78; a
  calculadora dá 475,79) e não sei explicar. A tolerância é de um centavo.
- **Quem atualiza de uma versão com os campos antigos** fica com as entidades
  antigas órfãs no registro (o Home Assistant as mostra como indisponíveis). O
  instalador não as remove.
- **O medidor do ciclo é criado quando o package sobe.** Se a fonte de consumo
  só for ligada dias depois, esses dias contam como medidos e a projeção fica
  baixa até o ciclo seguinte; o campo "medido desde" corrige à mão.
- **O gatilho da meia-noite só é conferido no arquivo**, não disparado; o
  fechamento é exercitado pelo disparo da automação e pelo início do Home
  Assistant.
- **A troca de posto por horário não é exercitada pela cerca** — depende do
  relógio. Confere-se que os horários da automação são os do arquivo de dados.
- As dívidas da frente anterior que não mudaram continuam valendo (cerca sem um
  medidor de verdade; consumo com o Home Assistant parado; entidade órfã que
  prende o total; laço de template numa rajada).

## 5. Achados não tratados

| Achado | Severidade | Conserto |
|---|---|---|
| A descrição do item de energia no catálogo fala em "reproduz a fatura na vírgula" | baixa — continua verdadeira | uma linha em `catalog/catalog.bash`, fora do escopo aprovado |
| A nota de revisão de `docs/base_tarifaria_RJ_home_assistant.md` aponta para a decisão da manhã, hoje superada | baixa — a decisão superada aponta para a nova | uma linha, fora do escopo aprovado |
| O instalador não avisa quem ATUALIZA de que as entidades antigas ficam órfãs | média | o `CHANGELOG.md` avisa; um aviso na própria execução seria melhor |
| Três sumiços do medidor em horário fixo, sem falta de luz | média — não soma mais nada, mas a causa é desconhecida | medir na próxima ocorrência; não depende do instalador |

## 6. A instância desta casa

(preenchido ao fim da frente)

## 7. O que falta

- A cada conta nova: conferir PIS e COFINS (ajuste, ou acrescentar o mês ao
  arquivo de dados) e a data da próxima leitura.
- Todo mês: a bandeira do mês no arquivo de dados.
- Empurrar para o remoto, subir versão, publicar: **só sob ordem**.

## 8. Lições que custaram defeito

- **Duas provas do mesmo lado da faixa não provam a faixa.** As duas contas
  reais são de mais de 300 kWh; uma calculadora que cobrasse sempre a alíquota
  maior passaria. A âncora foi buscar o que a fonte publica para as outras
  faixas.
- **Cerca que passa de primeira não disse o que deixou de olhar.** A primeira
  rodada verde não lia o registro do Core: erro de template passaria.
- **Comando que sinaliza por código de saída, canalizado, sob `errexit`,
  encerra o roteiro no lugar errado.** O conferidor de cópias saía com 1 antes
  de conferir os blocos seguintes.
- **Segui o dado até o total da fatura e parei.** A cerca comparava os totais e
  não lia os sensores que a tela mostra — entre eles o preço que o painel de
  Energia usa. A leitura fria achou; agora a grade lê todos.
- **Grade escolhida à mão tem os números que eu acho naturais**: kWh inteiros,
  a data de hoje, vírgula em dois campos. O que cercou de verdade foi avaliar o
  texto do package no motor do Home Assistant para centenas de casos
  sorteados, com comparação exata.
- **Pensei só na instalação que já tem um ciclo inteiro medido — a desta
  casa.** Quem instala no meio do ciclo caía na faixa errada por um ciclo e
  meio.
- **O que a tela mostra logo depois de implantar é o estado de fábrica dos
  campos novos sobre os medidores antigos** — e não é o que o dono deve ver. O
  ensaio em réplica mostrou os números errados desse intervalo; a implantação
  encadeia as etapas sem pausa.
