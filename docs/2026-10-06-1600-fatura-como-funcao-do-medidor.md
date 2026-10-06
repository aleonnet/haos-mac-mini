---
status: aceito
date: 2026-10-06
decisores: dono do repositório
---

# A fatura de energia como função do medidor

Supera [2026-10-06-1200-fonte-da-tarifa-de-energia.md](2026-10-06-1200-fonte-da-tarifa-de-energia.md).

## Contexto e problema

De manhã a decisão foi copiar da conta, a cada mês, o preço e os impostos. O
painel passou a fechar com a conta, mas com dez campos digitados por ciclo. Ao
ver o resultado, o dono mudou o rumo (2026-10-06, por escrito): *"o input
deveria ser apenas a medição do Shelly, dado que alíquotas, iluminação pública
tem fontes e critérios"*; *"tudo ser função do Shelly, mas obviamente mantendo
o ajuste manual se necessário"*; *"janela de ciclo ser dia inteiro"*.

A pergunta: **dá para calcular a fatura inteira só do consumo medido e das
datas de leitura?**

## O que foi medido

Cada parcela da conta foi conferida em fonte, e os números refeitos por
comando (detalhe e citações no arquivo de dados e no
[documento de fórmulas](2026-10-06-1600-formulas-da-fatura-de-energia.md)):

| Parcela | Tem regra pública? | Fonte |
|---|---|---|
| Tarifa, convencional e Branca | sim | PDF da distribuidora (a base aberta da ANEEL traz outro valor para a mesma vigência) |
| Bandeira do ciclo | sim | API aberta da ANEEL + norma do rateio por dias; quais dias contam sai da conta |
| ICMS | sim — pela faixa do consumo | colunas do PDF de tarifas; lei estadual |
| PIS e COFINS | **não** — mudam todo mês e não são publicados separados | só a conta |
| Iluminação pública | sim — parcela fixa da faixa + coeficiente × (tarifa de referência + bandeira) | lei municipal; tabelas mensais da Fazenda |
| "Complemento" de R$ 2,08 | **não** | nenhuma |

Com isso, as duas contas reais saem ao centavo só com consumo, datas, a faixa
da iluminação e as linhas sem regra: 304 kWh → 471,92 (conta: 471,92);
354 kWh → 542,47 (conta: 542,46).

O dono pediu fonte melhor que PDF. Foi procurada no conteúdo público inteiro do
site da distribuidora, pela interface de dados que fica por trás das páginas:
não existe. A área logada, que mostraria a composição do faturamento, pede
identificação e verificação anti-robô — não foi usada.

## Opções consideradas

1. **Manter os campos da fatura** (a decisão da manhã). Fecha sempre, ao custo
   de digitar dez números por mês; e o ciclo em curso fica com o preço do
   ciclo passado.
2. **Calcular tudo, sem ajuste.** Nada a digitar; erra em silêncio no mês em
   que PIS, COFINS ou a faixa mudarem.
3. **Calcular tudo, com valor padrão de fonte e ajuste manual por parâmetro.**

## Decisão

**Opção 3.** Só o consumo e as datas de leitura entram; cada parâmetro tem
valor calculado, com fonte, e um campo de ajuste — vazio vale o calculado,
preenchido vale o do dono.

Três peças separadas, para um aplicativo futuro trocar só a última:

- **Dado** — `tarifas/energia_light_rj.json`: cada número com fonte, citação
  literal, data da conferência e grau de certeza.
- **Regra** — `tarifas/fatura.py`: a calculadora de referência, e o documento
  de fórmulas numeradas.
- **Tela** — o package do Home Assistant, que consome o dado (bloco gerado por
  ferramenta) e implementa a mesma regra em template.

O ciclo passa a dia inteiro: fecha à 00:00 da data de leitura, guarda as duas
datas do ciclo fechado e assume a próxima leitura um mês depois, corrigível.
Medido na instância do dono: a janela de dia inteiro é a que melhor fecha com a
conta (2,90 kWh acima do faturado; a de meio-dia a meio-dia dava 4,33).

## Consequências

- Nenhum campo obrigatório. Instalação nova mostra preço desde o primeiro
  minuto.
- **O que continua dependendo de alguém:** bandeira, PIS, COFINS e tabela da
  iluminação valem pelo último valor conhecido até o arquivo de dados ser
  atualizado ou o ajuste ser preenchido. O resultado sai marcado como estimado
  quando isso acontece. Buscar as fontes automaticamente pela internet ficou
  fora desta frente; os endereços que uma máquina consegue ler estão no arquivo
  de dados.
- **O ICMS depende do consumo**, então o preço do kWh do ciclo em curso depende
  de quanto o ciclo vai fechar: o package projeta o consumo para escolher a
  faixa. Enquanto o ciclo corre, o preço pode mudar se a projeção atravessar
  300 kWh.
- **Os ajustes valem para o ciclo em curso e para o fechado**, até serem
  apagados.
- O arquivo de dados é de uma distribuidora e de um município. Outra
  distribuidora é outro arquivo, com a mesma forma.
- Os horários de ponta passam a ser os da distribuidora (17h30–20h30,
  intermediário até 22h30); o que já foi contado por posto com a janela antiga
  não é reescrito.
- Garantia: a calculadora tem de reproduzir as duas contas e os três preços com
  tributos que a distribuidora publica; o Home Assistant tem de dar o mesmo que
  a calculadora numa grade de ciclos; o package tem de carregar o mesmo dado do
  arquivo. As três conferências rodam no portão.
