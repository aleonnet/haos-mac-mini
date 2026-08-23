# Base tarifária residencial do Estado do Rio de Janeiro (RJ)
## Energia elétrica, gás canalizado, água e esgoto — fontes oficiais, modelo de dados e atualização automática

**Versão da pesquisa:** 2026-08-23  
**Objetivo:** construir uma base tarifária rastreável e machine-readable para ser consumida por um LLM e, posteriormente, gerar/configurar YAML do Home Assistant.  
**Princípio:** nenhum valor deve ser publicado sem fonte, vigência e contexto tarifário explícitos.

---

## Sumário

1. [Conclusões executivas](#1-conclusões-executivas)
2. [Critérios de confiabilidade](#2-critérios-de-confiabilidade)
3. [Energia elétrica](#3-energia-elétrica)
4. [Gás canalizado](#4-gás-canalizado)
5. [Água e esgoto](#5-água-e-esgoto)
6. [Mapa de prestadores e problema de cobertura geográfica](#6-mapa-de-prestadores-e-problema-de-cobertura-geográfica)
7. [Modelo de dados canônico](#7-modelo-de-dados-canônico)
8. [Arquitetura recomendada para atualização automática](#8-arquitetura-recomendada-para-atualização-automática)
9. [Algoritmo de atualização por vigência](#9-algoritmo-de-atualização-por-vigência)
10. [Tratamento de PDFs, CSVs e alterações regulatórias](#10-tratamento-de-pdfs-csvs-e-alterações-regulatórias)
11. [Integração segura com Home Assistant](#11-integração-segura-com-home-assistant)
12. [Validações obrigatórias](#12-validações-obrigatórias)
13. [Estrutura sugerida do repositório](#13-estrutura-sugerida-do-repositório)
14. [Fontes e links](#14-fontes-e-links)
15. [Pendências para uma base de água 100% estadual](#15-pendências-para-uma-base-de-água-100-estadual)

---

# 1. Conclusões executivas

## 1.1 Estado atual das fontes

| Serviço | Existe fonte única nacional? | Fonte principal para RJ | Situação para automação |
|---|---|---|---|
| Energia elétrica | **Sim** | ANEEL Dados Abertos | **Excelente**: CSV estruturado, histórico e vigência |
| Bandeira tarifária | **Sim** | ANEEL | **Boa**: deve ser camada separada da tarifa-base |
| Gás canalizado | Não | Naturgy + AGENERSA | **Boa**: PDFs oficiais, mas frequentemente sem `valid_until` |
| Água/esgoto | Não | AGENERSA + prestadores municipais + SINISA | **Fragmentada**: exige vários parsers e mapa de cobertura |

### Regra essencial

A base **não deve** ser apenas:

```yaml
electricity_price: 0.95
gas_price: 9.72
water_price: 6.50
```

Isso produziria cálculos incorretos.

O modelo precisa preservar:

- distribuidora/concessionária;
- município e, quando necessário, área de concessão;
- classe/subclasse residencial;
- modalidade tarifária;
- posto horário;
- faixas progressivas;
- água e esgoto separados;
- tarifa social separada;
- TE e TUSD separadas;
- bandeira tarifária separada;
- início e fim de vigência;
- ato regulatório;
- URL da fonte;
- hash do arquivo obtido;
- data da verificação;
- status de validação.

---

# 2. Critérios de confiabilidade

## 2.1 Ordem de preferência das fontes

1. **Regulador oficial em formato estruturado**
   - ANEEL Dados Abertos.
2. **Regulador oficial em PDF/ato**
   - ANEEL, AGENERSA.
3. **Concessionária/prestador oficial**
   - Naturgy, Energisa, prestadores de saneamento.
4. **SINISA**
   - útil principalmente para identificar prestadores e cobertura;
   - não deve ser tratado como base tarifária corrente.
5. **Espelhos jurídicos ou notícias**
   - apenas para descoberta/validação cruzada;
   - não devem ser fonte canônica quando o ato oficial estiver disponível.

## 2.2 Regra de publicação

Um registro só pode receber:

```yaml
status: verified
```

se contiver no mínimo:

```yaml
source:
  authority: ...
  document: ...
  url: ...
  retrieved_at: ...
  sha256: ...

validity:
  from: ...
  to: ...

verification:
  status: verified
```

Se a fonte não fornecer data final de vigência, **não inventar uma**:

```yaml
validity:
  from: "2026-08-01"
  to: null

refresh_policy:
  type: source_change_watch
```

---

# 3. Energia elétrica

# 3.1 Fonte canônica nacional

A ANEEL mantém o conjunto oficial:

**Tarifas das distribuidoras de energia elétrica**

Página do dataset:

https://dadosabertos.aneel.gov.br/pt_BR/dataset/tarifas-distribuidoras-energia-eletrica

Download direto do CSV:

https://dadosabertos.aneel.gov.br/dataset/5a583f3e-1646-4f67-bf0f-69db4203e89e/resource/fcf2906c-7c32-4b9b-a637-054e7a5234f4/download/tarifas-homologadas-distribuidoras-energia-eletrica.csv

Dicionário de dados:

https://dadosabertos.aneel.gov.br/pt_BR/dataset/tarifas-distribuidoras-energia-eletrica/resource/2d3478e0-8aa0-4cd4-81a7-5f8967cd8804

Características verificadas da base em 23/08/2026:

- contém **TE** e **TUSD**;
- contém vigência;
- contém distribuidora;
- contém subgrupo;
- contém modalidade;
- contém classe e subclasse;
- contém posto tarifário;
- cobertura histórica desde 2010;
- frequência de atualização declarada: **semanal**.

Também existe a base oficial de componentes tarifários:

https://dadosabertos.aneel.gov.br/dataset/componentes-tarifarias

Recurso 2026:

https://dadosabertos.aneel.gov.br/dataset/componentes-tarifarias/resource/e8717aa8-2521-453f-bf16-fbb9a16eea39

Ela é útil para auditoria e decomposição dos componentes, mas para o preço residencial aplicado o dataset de tarifas homologadas deve ser a primeira fonte.

---

## 3.2 Filtro residencial recomendado

Para evitar misturar tarifa residencial normal com SCEE, geração distribuída, rural, baixa renda etc.:

```text
DscBaseTarifaria = "Tarifa de Aplicação"
DscSubGrupo      = "B1"
DscClasse        = "Residencial"
DscSubClasse     = "Residencial"
DscDetalhe       = "Não se aplica"        # quando aplicável ao schema

modalidade:
  - "Convencional Monômia"
  - "Branca"

posto:
  - "Não se aplica"
  - "Ponta"
  - "Intermediário"
  - "Fora ponta"
```

Os campos TE e TUSD são normalmente apresentados em **R$/MWh** no dataset regulatório.

Conversão:

```text
TUSD_R$/kWh = VlrTUSD / 1000
TE_R$/kWh   = VlrTE   / 1000

tarifa_base_R$/kWh = (VlrTUSD + VlrTE) / 1000
```

Nunca descartar TE/TUSD originais.

---

## 3.3 Distribuidoras residenciais identificadas no RJ

Na pesquisa foram identificados os seguintes agentes com B1 residencial aplicável no RJ:

- CERAL Araruama;
- CERCI;
- CERES;
- Energisa Minas Rio — EMR;
- Enel Distribuição Rio;
- Light Serviços de Eletricidade — Light SESA.

### Snapshot de tarifas residenciais 2026

Valores abaixo em **R$/kWh**, antes de bandeira, tributos e outros itens de faturamento.

| Distribuidora | Convencional | Branca fora ponta | Branca intermediária | Branca ponta | Vigência/referência |
|---|---:|---:|---:|---:|---|
| CERAL Araruama | 1,20634 | 0,90366* | 1,97984* | 3,05600* | revisão 2026 |
| CERCI | 1,50089 | 1,18982 | 2,29587 | 3,40191 | 29/04/2026–28/04/2027 |
| CERES | 1,56923 | 1,23132 | 2,43276 | 3,63420 | 29/04/2026–28/04/2027 |
| Energisa Minas Rio | 0,91899 | 0,75090 | 1,14921 | 1,76178 | desde 22/06/2026 |
| Enel RJ | 1,06110 | 0,89343 | 1,43658 | 2,15856 | 15/03/2026–14/03/2027 |
| Light SESA | **0,94793** | **0,83447** | **1,20499** | **1,73992** | 15/03/2026–14/03/2027, com override regulatório |

\* Os valores da Tarifa Branca da CERAL foram obtidos no levantamento sobre o snapshot da ANEEL e devem ser **regenerados diretamente do CSV pelo pipeline antes de publicação em produção**. Não devem ser copiados manualmente como fonte definitiva.

---

## 3.4 Energisa Minas Rio — validação oficial

Quadro tarifário oficial da distribuidora:

https://www.energisa.com.br/sites/energisa/files/media/documents/2026-06/Quadro_de_Tarifas_EMR.pdf

Resolução ANEEL nº 3.591/2026.

Residencial B1:

```yaml
conventional:
  tusd_brl_per_kwh: 0.55810
  te_brl_per_kwh: 0.36089
  total_brl_per_kwh: 0.91899

white:
  peak:
    tusd_brl_per_kwh: 1.20448
    te_brl_per_kwh: 0.55730
    total_brl_per_kwh: 1.76178

  shoulder:
    tusd_brl_per_kwh: 0.80617
    te_brl_per_kwh: 0.34304
    total_brl_per_kwh: 1.14921

  offpeak:
    tusd_brl_per_kwh: 0.40786
    te_brl_per_kwh: 0.34304
    total_brl_per_kwh: 0.75090
```

Vigência informada no quadro: **22/06/2026**.

---

## 3.5 Enel RJ — tarifa 2026

Documento oficial da Enel/ANEEL:

https://www.enel.com.br/content/dam/enel-br/Tarifas/SEI_48500.030702_2025_70%20REH%203570-2026.pdf

Residencial B1:

```yaml
conventional:
  tusd_brl_per_kwh: 0.73172
  te_brl_per_kwh: 0.32938
  total_brl_per_kwh: 1.06110

white:
  peak:
    tusd_brl_per_kwh: 1.66526
    te_brl_per_kwh: 0.49330
    total_brl_per_kwh: 2.15856

  shoulder:
    tusd_brl_per_kwh: 1.12211
    te_brl_per_kwh: 0.31447
    total_brl_per_kwh: 1.43658

  offpeak:
    tusd_brl_per_kwh: 0.57896
    te_brl_per_kwh: 0.31447
    total_brl_per_kwh: 0.89343
```

Vigência: **15/03/2026–14/03/2027**.

---

## 3.6 Light — caso que exige camada de override regulatório

Este é o caso mais importante para a arquitetura da automação.

A tarifa originalmente homologada para 2026 sofreu alteração posterior por ato regulatório. Houve ainda suspensão temporária e posterior restauração dos efeitos da alteração.

Espelho jurídico usado durante a verificação do ato de alteração:

https://atosoficiais.com.br/aneel/despacho-n-921-2026-decide-i-altera-se-o-resultado-do-reajuste-tarifario-anual-de-2026-da-light-servicos-de-eletricidade-s-a-light-objeto-da-2026-03-17-versao-original?origin=instituicao

Despacho que restaurou os efeitos do ato anterior:

https://atosoficiais.com.br/aneel/despacho-n-2129-2026-decide-i-suspender-os-efeitos-do-despacho-str-aneel-no-1-063-de-25-de-marco-de-2026-ii-retornar-a-vigencia-dos-efeitos?origin=instituicao

### Valor efetivo considerado após o override

```yaml
light_sesa:
  validity:
    from: "2026-03-15"
    to: "2027-03-14"

  regulatory_override:
    altered_by: "Despacho ANEEL 921/2026"
    restored_by: "Despacho ANEEL 2129/2026"

  residential_b1:
    conventional:
      tusd_brl_per_kwh: 0.62265
      te_brl_per_kwh: 0.32528
      total_brl_per_kwh: 0.94793

    white:
      peak:
        tusd_brl_per_kwh: 1.26393
        te_brl_per_kwh: 0.47599
        total_brl_per_kwh: 1.73992

      shoulder:
        tusd_brl_per_kwh: 0.89341
        te_brl_per_kwh: 0.31158
        total_brl_per_kwh: 1.20499

      offpeak:
        tusd_brl_per_kwh: 0.52289
        te_brl_per_kwh: 0.31158
        total_brl_per_kwh: 0.83447
```

### Consequência arquitetural

A automação não pode fazer apenas:

```text
baixar CSV -> selecionar linha -> publicar
```

Precisa fazer:

```text
CSV ANEEL
   ↓
candidate
   ↓
verificar atos posteriores / overrides vigentes
   ↓
aplicar precedência regulatória
   ↓
validar
   ↓
publicar
```

Uma base oficial estruturada pode ficar temporariamente defasada em relação a um ato posterior. O sistema precisa ser capaz de registrar essa exceção sem alterar o dado bruto original.

---

## 3.7 Bandeiras tarifárias

Fonte oficial:

https://www.gov.br/aneel/pt-br/assuntos/tarifas/bandeiras-tarifarias

Fonte específica de agosto de 2026:

https://www.gov.br/aneel/pt-br/assuntos/noticias/2026-defeso-eleitoral/bandeira-tarifaria-continua-amarela-em-agosto

Em agosto de 2026:

```yaml
tariff_flag:
  name: yellow
  additional_brl_per_kwh: 0.01885
```

Referências atuais dos adicionais publicadas pela ANEEL:

```yaml
green:  0.00000
yellow: 0.01885
red_1:  0.04463
red_2:  0.07877
```

**Não incorporar a bandeira dentro da TE/TUSD.**

Ela deve ser uma camada independente:

```text
custo_base
+ bandeira
+ tributos aplicáveis
+ CIP/COSIP quando aplicável
+ demais componentes da fatura
```

---

## 3.8 Horários da Tarifa Branca

Os horários **não devem ser globalmente hardcodedados para todas as distribuidoras**.

Eles devem ser tratados como atributo da distribuidora:

```yaml
white_tariff_schedule:
  provider: light_sesa
  source: ...
  weekdays: ...
  weekends: offpeak
  national_holidays: offpeak
```

O seu YAML atual utiliza:

```text
17:30 -> peak
20:30 -> shoulder
22:30 -> offpeak
```

Esse tipo de configuração deve ser gerado **depois de identificar a distribuidora correta e validar o posto horário vigente**.

---

# 4. Gás canalizado

## 4.1 Fontes oficiais

AGENERSA — tarifas vigentes:

https://www.rj.gov.br/agenersa/tarifas-em-vigor

Naturgy — tarifa CEG, vigente desde 01/08/2026:

https://www.naturgy.com.br/wp-content/uploads/2026/07/PB85USD_Tarifa-CEG-01.08.26.pdf

Naturgy — tarifa CEG Rio, vigente desde 01/08/2026:

https://www.naturgy.com.br/wp-content/uploads/2026/07/PB85USD_Tarifa-CRIO-01.08.26.pdf

---

## 4.2 Regra de cobrança

As tarifas residenciais de gás são aplicadas **em cascata**.

Logo:

```text
custo = consumo × tarifa_da_última_faixa
```

é incorreto.

O cálculo precisa aplicar cada parcela do consumo à sua respectiva faixa.

---

## 4.3 CEG — residencial

Vigência:

```yaml
from: "2026-08-01"
to: null
```

Tabela residencial normal:

| Faixa de consumo | Tarifa |
|---|---:|
| 0–7 m³ | R$ 9,7235/m³ |
| 8–23 m³ | R$ 12,6756/m³ |
| 24–83 m³ | R$ 15,3462/m³ |
| acima de 83 m³ | R$ 16,1928/m³ |

Tarifa social:

| Faixa | Tarifa |
|---|---:|
| 0–7 m³ | R$ 6,0441/m³ |
| 8–23 m³ | R$ 6,3148/m³ |
| 24–83 m³ | R$ 15,3462/m³ |
| acima de 83 m³ | R$ 16,1928/m³ |

Modelo:

```yaml
gas:
  ceg:
    validity:
      from: "2026-08-01"
      to: null

    billing_method: progressive_cascade
    reference_pcs_kcal_m3: 9400

    residential:
      minimum_volume_m3: 7

      tiers:
        - from_m3: 0
          to_m3: 7
          rate_brl_per_m3: 9.7235

        - from_m3: 7
          to_m3: 23
          rate_brl_per_m3: 12.6756

        - from_m3: 23
          to_m3: 83
          rate_brl_per_m3: 15.3462

        - from_m3: 83
          to_m3: null
          rate_brl_per_m3: 16.1928
```

A conta mínima resulta da primeira faixa. Se armazenada na base, deve ser marcada como **valor derivado**, e não como número lido literalmente da tabela:

```yaml
derived:
  minimum_charge_brl: 68.06
```

---

## 4.4 CEG Rio — residencial

Vigência:

```yaml
from: "2026-08-01"
to: null
```

Tabela residencial:

| Faixa | Tarifa |
|---|---:|
| 0–7 m³ | R$ 7,3891/m³ |
| 8–23 m³ | R$ 9,3637/m³ |
| 24–83 m³ | R$ 11,1714/m³ |
| acima de 83 m³ | R$ 12,4456/m³ |

Tarifa social:

| Faixa | Tarifa |
|---|---:|
| 0–7 m³ | R$ 5,6059/m³ |
| 8–23 m³ | R$ 5,8439/m³ |
| 24–83 m³ | R$ 11,1714/m³ |
| acima de 83 m³ | R$ 12,4456/m³ |

---

## 4.5 Implicação para atualização automática

Os PDFs de gás trazem `valid_from`, mas podem não trazer `valid_until`.

Portanto o updater deve usar:

```yaml
refresh_policy:
  type: source_change_watch
  scan_interval_days: 1
  strategy:
    - check_landing_page_links
    - compare_etag
    - compare_last_modified
    - compare_sha256
```

Não criar artificialmente:

```yaml
to: "2027-07-31"
```

sem fonte oficial dizendo isso.

---

# 5. Água e esgoto

## 5.1 Situação estrutural do RJ

Não existe uma única planilha estadual oficial com todas as tarifas residenciais dos 92 municípios.

A AGENERSA publica as tarifas vigentes das concessões sob sua regulação:

https://www.rj.gov.br/agenersa/tarifas-em-vigor

Na pesquisa atual a página lista:

- Águas de Juturnaíba;
- Prolagos;
- Águas da Condessa;
- Águas de Paraty;
- Águas de Pádua;
- CEDAE;
- CEDAE — Preço da Água;
- Águas do Rio 1;
- Águas do Rio 4;
- Rio+ Saneamento;
- Águas da Imperatriz;
- Iguá.

**Atenção:** “CEDAE — Preço da Água” é preço de fornecimento no atacado e não deve ser confundido com tarifa residencial.

---

## 5.2 Downloads oficiais — AGENERSA

### Águas de Juturnaíba

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUASDEJUTURNAIBA_0.pdf

### Prolagos

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/PROLAGOS_2.pdf

### Águas da Condessa

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS%20DA%20CONDESSA_0.pdf

### Águas de Paraty

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS%20DE%20PARATY_0.pdf

### Águas de Pádua

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS-DE-PADUA.pdf

### CEDAE

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/CEDAE_4.pdf

### Águas do Rio — Bloco 1

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUASDORIOBL%201.pdf

### Águas do Rio — Bloco 4

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUASDORIOBL%204.pdf

### Rio+ Saneamento

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/RIO%2BSANEAMENTO.pdf

### Águas da Imperatriz

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS%20DA%20IMPERATRIZ_0.pdf

### Iguá

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/IGUA_0.pdf

---

## 5.3 Valores residenciais verificados — exemplos e estruturas

> Os exemplos abaixo são extrações verificadas dos documentos vigentes encontrados. O pipeline final deve preservar todas as categorias, tarifa social, regiões, economias e regras específicas existentes no PDF.

### CEDAE — Área B

Documento vigente consultado em 2026, com efeito indicado a partir de 22/01/2026.

| Faixa | Água — R$/m³ |
|---|---:|
| 0–15 | 5,628681 |
| 16–30 | 12,383098 |
| 31–45 | 16,886043 |
| 46–60 | 33,772086 |
| >60 | 45,029448 |

Valor de conta mínima/Tarifa 1 indicado na estrutura:

```yaml
minimum_tariff_brl_per_m3_or_structure_value: 4.913304
```

A semântica da tarifa mínima deve ser preservada exatamente conforme o documento; não inferir mecanicamente que todas as linhas são cobradas da mesma forma.

---

### Águas do Rio 1

Data de referência do reajuste consultado: 01/12/2025.

Faixas:

```text
0–15
16–30
31–45
46–60
>60 m³
```

Área A:

```yaml
[7.436291, 16.359841, 22.308872, 44.617747, 59.490329]
```

Área B:

```yaml
[6.523050, 14.350710, 19.569152, 39.138304, 52.184405]
```

A estrutura consultada indica cobrança de esgoto equivalente à água para a regra apresentada no documento.

---

### Águas do Rio 4

Data de referência: 01/12/2025.

Área A:

```yaml
[7.650527, 16.831159, 22.951580, 45.903161, 61.204215]
```

Área B:

```yaml
[6.710976, 14.764146, 20.132930, 40.265858, 53.687811]
```

---

### Rio+ Saneamento

Data de referência: 01/12/2025.

Área A:

```yaml
[7.360963, 16.194117, 22.082889, 44.165776, 58.887704]
```

Área B:

```yaml
[6.456973, 14.205340, 19.370920, 38.741839, 51.655786]
```

---

### Iguá

Data de referência: 01/12/2025.

Área A:

```yaml
[7.414307, 16.311476, 22.242921, 44.485842, 59.314457]
```

Área B:

```yaml
[6.503766, 14.308285, 19.511299, 39.022598, 52.030131]
```

---

### Águas de Paraty

Deliberação AGENERSA nº 4.997/2026.

| Faixa | Água — R$/m³ |
|---|---:|
| 0–10 | 4,6631 |
| 11–15 | 6,0620 |
| 16–20 | 10,0257 |
| 21–30 | 10,7252 |
| 31–45 | 13,9894 |
| >45 | 20,9840 |

---

### Águas da Condessa

Estrutura consultada em 2026.

| Faixa domiciliar | Água | Esgoto |
|---|---:|---:|
| 0–15 | 6,2447 | 3,1223 |
| 16–30 | 13,7383 | 6,8691 |
| 31–45 | 18,7340 | 9,3670 |
| 46–60 | 37,4680 | 18,7340 |
| >60 | 49,9574 | 24,9787 |

A tabela contém ainda tarifa social e regra de conta mínima, que devem permanecer como registros separados no schema.

---

### Águas de Pádua

Valores encontrados na tabela vigente apontada pela AGENERSA:

| Faixa | Água | Esgoto |
|---|---:|---:|
| 0–15 | 3,110 | 3,110 |
| 16–30 | 7,043 | 7,043 |
| 31–45 | 9,758 | 9,758 |
| 46–60 | 19,367 | 19,367 |
| >60 | 26,130 | 26,130 |

Tarifa social publicada:

```yaml
water: 2.497
sewer: 2.497
```

---

### Águas da Imperatriz

Tabela 2026:

| Faixa domiciliar | Água | Esgoto |
|---|---:|---:|
| 0–15 | 5,2836 | 4,7551 |
| 16–30 | 11,6238 | 10,4614 |
| 31–45 | 15,8506 | 14,2655 |
| 46–60 | 31,7012 | 28,5310 |
| >60 | 42,2682 | 38,0414 |

---

## 5.4 Por que água exige um schema mais rico

Não assumir que toda tarifa de água usa a mesma fórmula.

O registro precisa dizer explicitamente:

```yaml
billing_method:
  type: ...
```

Exemplos possíveis:

```text
progressive_cascade
block_tariff
minimum_consumption_plus_tiers
fixed_plus_variable
per_economy
area_specific
```

E esgoto deve ser representado separadamente:

```yaml
sewer:
  method: explicit_table
```

ou, somente quando a fonte determinar:

```yaml
sewer:
  method: percentage_of_water
  percentage: 100
```

**Nunca aplicar um percentual padrão estadual de esgoto.**

---

# 6. Mapa de prestadores e problema de cobertura geográfica

## 6.1 SINISA

Portal oficial:

https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/area-do-prestador

Prestadores locais:

https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/area-do-prestador/prestadores-locais-2013-abastecimento-de-agua

Prestadores regionais:

https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/area-do-prestador/prestadores-regionais-de-abastecimento-de-agua-e-ou-de-esgotamento-sanitario

O SINISA deve ser usado para:

- descobrir prestadores;
- conferir cobertura;
- montar o mapa município → prestador;
- auditar lacunas.

Não deve substituir a tabela tarifária corrente do regulador/prestador.

---

## 6.2 Mapeamento operacional identificado

Exemplos de prestadores identificados na pesquisa:

```text
Rio de Janeiro       -> Águas do Rio 1 / Águas do Rio 4 / Iguá / Rio+
Niterói              -> Águas de Niterói
Nova Friburgo        -> Águas de Nova Friburgo
Petrópolis           -> Águas do Imperador
Campos               -> Águas do Paraíba
Resende              -> Águas das Agulhas Negras
Angra dos Reis       -> SAAE Angra
Barra Mansa          -> SAAE Barra Mansa
Volta Redonda        -> SAAE Volta Redonda
Três Rios            -> SAAETRI
Araruama             -> Águas de Juturnaíba
Silva Jardim         -> Águas de Juturnaíba
Cabo Frio            -> Prolagos
Armação dos Búzios   -> Prolagos
Arraial do Cabo      -> Prolagos
Iguaba Grande        -> Prolagos
Paraíba do Sul       -> Águas da Condessa
Teresópolis          -> Águas da Imperatriz
Miguel Pereira       -> Iguá
Paty do Alferes      -> Iguá
```

Esse mapa é um **índice operacional** e precisa ser cruzado com a cobertura contratual atual antes de publicação automática.

### Municípios com múltiplas áreas/prestadores

Foram identificados casos em que município sozinho não é chave suficiente, incluindo:

- Rio de Janeiro;
- Duque de Caxias;
- Nova Iguaçu;
- São Gonçalo;
- Saquarema;
- Seropédica;
- Paracambi.

Portanto, isto é insuficiente:

```yaml
location:
  uf: RJ
  municipality: Rio de Janeiro
```

O modelo precisa permitir:

```yaml
location:
  uf: RJ
  municipality: Rio de Janeiro
  concession_area: AP4
  neighborhood: Barra da Tijuca
  postal_code_prefix: ...
```

ou outro identificador territorial oficial disponível.

---

# 7. Modelo de dados canônico

A recomendação é **não fazer do `configuration.yaml` do Home Assistant a base mestre**.

A base mestre deve ser independente:

```text
tarifas_RJ.yaml
        ↓
validator
        ↓
tarifas_RJ.json
        ↓
gerador Home Assistant
        ↓
package/sensors/templates
```

## 7.1 Exemplo de schema

```yaml
schema_version: 1
country: BR
state: RJ

dataset:
  verified_at: "2026-08-23T14:50:00-03:00"
  complete:
    electricity: true
    gas_regulated_network: true
    water_statewide: false

providers:

  light_sesa:
    service: electricity

    geographic_scope:
      state: RJ
      municipalities: []
      concession_area: null

    source:
      authority: ANEEL
      document: "Tarifa B1 + override regulatório 2026"
      url: "..."
      retrieved_at: "2026-08-23T14:50:00-03:00"
      sha256: "..."

    validity:
      from: "2026-03-15"
      to: "2027-03-14"

    status: verified

    residential:
      conventional:
        components:
          tusd_brl_per_kwh: 0.62265
          te_brl_per_kwh: 0.32528
        total_brl_per_kwh: 0.94793

      white:
        peak:
          tusd_brl_per_kwh: 1.26393
          te_brl_per_kwh: 0.47599
          total_brl_per_kwh: 1.73992

        shoulder:
          tusd_brl_per_kwh: 0.89341
          te_brl_per_kwh: 0.31158
          total_brl_per_kwh: 1.20499

        offpeak:
          tusd_brl_per_kwh: 0.52289
          te_brl_per_kwh: 0.31158
          total_brl_per_kwh: 0.83447
```

---

## 7.2 Estados possíveis do registro

```yaml
status:
  - verified
  - needs_review
  - expired_pending_source
  - superseded
  - source_unavailable
  - regulatory_override
```

Nunca deixar um valor vencido parecer vigente.

---

# 8. Arquitetura recomendada para atualização automática

## 8.1 Princípio

O Home Assistant **não deve ser o scraper dos reguladores**.

A arquitetura mais segura é:

```text
                   ┌────────────────────────┐
                   │ Fontes oficiais        │
                   │ ANEEL / AGENERSA       │
                   │ Naturgy / prestadores  │
                   └────────────┬───────────┘
                                │
                                ▼
                   ┌────────────────────────┐
                   │ Tariff Updater         │
                   │ Python                 │
                   └────────────┬───────────┘
                                │
          ┌─────────────────────┼─────────────────────┐
          ▼                     ▼                     ▼
   download bruto          parser normalizado    metadados
   + SHA256                + validação           + vigência
          └─────────────────────┼─────────────────────┘
                                ▼
                   ┌────────────────────────┐
                   │ Candidate dataset      │
                   └────────────┬───────────┘
                                │
                                ▼
                   ┌────────────────────────┐
                   │ Regulatory overrides   │
                   │ + validation gates     │
                   └────────────┬───────────┘
                                │
                                ▼
                   ┌────────────────────────┐
                   │ tariffs_RJ.yaml/json   │
                   │ VERSIONADO             │
                   └────────────┬───────────┘
                                │
                                ▼
                   ┌────────────────────────┐
                   │ Home Assistant         │
                   │ somente consome        │
                   └────────────────────────┘
```

---

## 8.2 Onde executar

Três opções adequadas:

### Opção A — GitHub Actions

Vantagens:

- histórico Git;
- diff automático;
- execução agendada;
- possibilidade de abrir Pull Request;
- rollback simples;
- logs centralizados.

### Opção B — container Docker

Executar um container Python agendado por cron/systemd/orquestrador.

Vantagens:

- controle local;
- fácil integração com Home Assistant;
- não depende de tornar a base pública.

### Opção C — CI + container local

O CI busca/valida e publica o dataset; a rede local apenas consome a versão assinada/validada.

**Recomendação:** separar atualização da base da configuração do Home Assistant.

---

# 9. Algoritmo de atualização por vigência

## 9.1 Não esperar a tarifa expirar

A rotina deve antecipar a expiração.

Sugestão:

```text
> 30 dias para vencer -> checagem semanal
30 dias              -> começar checagem diária
7 dias               -> checagem diária + alerta se sucessora não apareceu
1 dia                -> alerta crítico se sucessora não apareceu
0 dias               -> NÃO inventar renovação
vencida               -> status = expired_pending_source
```

---

## 9.2 Fluxo

```python
for tariff in database:

    if tariff.validity.to is not None:

        days = tariff.validity.to - today

        if days > 30:
            check_source_if_due()

        elif days <= 30:
            check_source_daily()

        if days <= 7 and no_successor_found:
            alert()

        if days < 0 and no_successor_found:
            tariff.status = "expired_pending_source"
            do_not_replace_with_guessed_value()

    else:
        monitor_source_change()
```

---

## 9.3 Fontes sem data final

Para gás e diversas tabelas de água:

```python
new_file = download(source.url)

if sha256(new_file) != source.sha256:
    parse_candidate()
    validate()
    diff()
    publish_or_review()
```

Também verificar:

```text
ETag
Last-Modified
URL/href da página índice
SHA-256 do conteúdo
número do ato
data de vigência encontrada no documento
```

Uma concessionária pode publicar um **novo PDF com uma nova URL**, então observar apenas o hash da URL antiga não é suficiente.

O monitor deve primeiro verificar a página índice.

Exemplo AGENERSA:

```text
https://www.rj.gov.br/agenersa/tarifas-em-vigor
```

Se o `href` associado ao prestador mudar, baixar o novo documento.

---

# 10. Tratamento de PDFs, CSVs e alterações regulatórias

## 10.1 ANEEL

Pipeline:

```text
download CSV
→ validar schema
→ filtrar B1 Residencial
→ preservar TE e TUSD
→ calcular total
→ selecionar vigência ativa
→ verificar override
→ publicar
```

### Guardar o arquivo bruto

Exemplo:

```text
raw/
  aneel/
    2026-08-23/
      tarifas-homologadas.csv
      tarifas-homologadas.csv.sha256
```

---

## 10.2 Naturgy/AGENERSA

PDFs devem ser arquivados antes da extração:

```text
raw/
  naturgy/
  agenersa/
```

O parser deve retornar, além dos valores:

```yaml
evidence:
  source_file: ...
  page: 1
  table: "Residencial"
```

---

## 10.3 Uso de LLM

Um LLM pode ser muito útil para:

- identificar tabelas em PDFs novos;
- mapear títulos diferentes para campos canônicos;
- interpretar pequenas mudanças de layout;
- gerar um `candidate.yaml`.

Mas ele **não deve decidir sozinho que uma tarifa está vigente**.

Fluxo seguro:

```text
PDF oficial
   ↓
parser determinístico
   │
   ├── conseguiu → validator
   │
   └── falhou → LLM extraction
                    ↓
              candidate only
                    ↓
                 validator
                    ↓
              revisão se necessário
```

O LLM nunca deve:

- inventar uma data final;
- calcular um reajuste porque encontrou apenas o percentual;
- substituir uma tabela oficial que não foi encontrada;
- assumir que a estrutura de um prestador é igual à de outro;
- inferir percentual de esgoto;
- inferir área de concessão somente pelo município.

---

## 10.4 Overrides regulatórios

Criar arquivo separado:

```yaml
overrides:

  light_2026:
    provider: light_sesa
    precedence: 100

    reason: regulatory_act

    effective_from: "2026-03-15"
    effective_to: "2027-03-14"

    altered_by:
      type: despacho
      number: "921/2026"

    restored_by:
      type: despacho
      number: "2129/2026"

    values:
      conventional:
        total_brl_per_kwh: 0.94793
```

O arquivo bruto ANEEL continua intacto.

A camada efetiva é:

```text
effective_tariff =
    highest_precedence_valid_override
    OR
    current_ANEEL_record
```

---

# 11. Integração segura com Home Assistant

## 11.1 Documentação oficial consultada

Utility Meter:

https://www.home-assistant.io/integrations/utility_meter/

Input Number:

https://www.home-assistant.io/integrations/input_number/

Reload de Input Number:

https://www.home-assistant.io/actions/input_number.reload/

RESTful Sensor:

https://www.home-assistant.io/integrations/sensor.rest/

REST:

https://www.home-assistant.io/integrations/rest/

---

## 11.2 Utility Meter

O `utility_meter` suporta tarifas e cria a entidade `select` usada para alternar entre elas.

O padrão usado no seu YAML é conceitualmente adequado:

```yaml
utility_meter:
  monthly_energy:
    source: sensor.energy_total
    cycle: monthly
    tariffs:
      - peak
      - shoulder
      - offpeak
```

E a troca:

```yaml
action:
  - action: select.select_option
    target:
      entity_id: select.monthly_energy
    data:
      option: "{{ tariff }}"
```

---

## 11.3 Não usar `input_number` como banco mestre

A documentação atual do Home Assistant informa resolução mínima de `step` que pode não ser adequada para manter diretamente cinco casas decimais de tarifa.

Exemplo de tarifa real:

```text
0.94793
```

Portanto, o valor canônico deve ficar fora do helper visual.

Alternativas:

1. sensor REST/JSON;
2. template sensor alimentado pelo dataset;
3. valor inteiro escalado, se necessário:

```text
94793 = 0.94793 × 100000
```

O `input_number` pode continuar existindo como:

- override manual;
- interface de teste;
- fallback.

Não deve ser a fonte de verdade.

---

## 11.4 Modelo recomendado

Dataset servido localmente:

```json
{
  "provider": "light_sesa",
  "valid_from": "2026-03-15",
  "valid_to": "2027-03-14",
  "conventional": 0.94793,
  "peak": 1.73992,
  "shoulder": 1.20499,
  "offpeak": 0.83447
}
```

Home Assistant apenas consome.

Assim:

```text
regulador mudou
→ updater detecta
→ valida
→ dataset é atualizado atomicamente
→ HA lê a nova versão
```

Não é necessário editar manualmente `configuration.yaml` a cada reajuste.

---

## 11.5 Cálculo da Tarifa Branca

```text
custo =
    kWh_peak      × tarifa_peak
  + kWh_shoulder  × tarifa_shoulder
  + kWh_offpeak   × tarifa_offpeak
```

Bandeira:

```text
+ consumo_total_kWh × adicional_da_bandeira
```

Tributos/CIP devem ser componentes separados se o objetivo for aproximar a fatura final.

---

## 11.6 Gás — função em cascata

Exemplo conceitual:

```python
def cascade_cost(consumption, tiers):
    total = 0
    previous_limit = 0

    for tier in tiers:
        upper = tier["to"]
        rate = tier["rate"]

        if upper is None:
            used = max(0, consumption - previous_limit)
        else:
            used = max(
                0,
                min(consumption, upper) - previous_limit
            )

        total += used * rate

        if upper is None or consumption <= upper:
            break

        previous_limit = upper

    return total
```

A implementação real deve reproduzir exatamente a convenção de limites do documento oficial.

---

## 11.7 Água/esgoto

Não reutilizar automaticamente a função de gás.

O motor deve despachar conforme:

```yaml
billing_method: ...
```

Por exemplo:

```python
match tariff.billing_method:
    case "progressive_cascade":
        ...
    case "minimum_consumption_plus_tiers":
        ...
    case "per_economy":
        ...
    case "fixed_plus_variable":
        ...
```

---

# 12. Validações obrigatórias

Antes de uma nova tarifa substituir a atual:

## 12.1 Estrutura

- schema conhecido;
- provider conhecido;
- unidade válida;
- classe residencial;
- modalidade esperada.

## 12.2 Faixas

- limites crescentes;
- nenhuma sobreposição;
- nenhuma lacuna não explicada;
- valor não negativo.

## 12.3 Datas

```text
valid_from <= hoje ou data futura conhecida
valid_to > valid_from, quando existir
```

## 12.4 Sanidade de variação

Se:

```text
abs(nova - antiga) / antiga > 25%
```

não rejeitar automaticamente, mas:

```yaml
status: needs_review
reason: unusually_large_change
```

Um reajuste grande pode ser legítimo.

---

## 12.5 Fonte

Aceitar publicação automática apenas de uma allowlist, por exemplo:

```yaml
allowed_domains:
  - dadosabertos.aneel.gov.br
  - www.aneel.gov.br
  - www2.aneel.gov.br
  - www.gov.br
  - www.rj.gov.br
  - www.naturgy.com.br
  - www.energisa.com.br
  - www.enel.com.br
```

Domínios municipais/prestadores adicionais devem entrar explicitamente depois de validados.

---

## 12.6 Hash e rastreabilidade

Cada arquivo:

```yaml
source:
  retrieved_at: "2026-08-23T14:50:00-03:00"
  sha256: "..."
```

Cada atualização deve produzir um diff:

```text
Light conventional:
OLD 0.94793
NEW 0.98214

source:
OLD ...
NEW ...

validity:
OLD 2026-03-15 → 2027-03-14
NEW 2027-03-15 → 2028-03-14
```

---

# 13. Estrutura sugerida do repositório

```text
tariff-db/
├── README.md
├── schema/
│   └── tariff.schema.json
│
├── data/
│   └── BR/
│       └── RJ/
│           ├── electricity.yaml
│           ├── tariff_flags.yaml
│           ├── gas.yaml
│           ├── water.yaml
│           ├── provider_map.yaml
│           └── overrides.yaml
│
├── sources/
│   └── RJ/
│       └── sources.yaml
│
├── raw/
│   ├── aneel/
│   ├── agenersa/
│   ├── naturgy/
│   └── municipal/
│
├── updater/
│   ├── main.py
│   ├── fetch.py
│   ├── validators.py
│   ├── diff.py
│   │
│   └── parsers/
│       ├── aneel.py
│       ├── naturgy.py
│       ├── agenersa.py
│       └── municipal.py
│
├── generated/
│   └── homeassistant/
│       ├── tariffs_RJ.json
│       └── tariffs_RJ_package.yaml
│
└── tests/
    ├── fixtures/
    ├── test_aneel.py
    ├── test_gas.py
    └── test_water.py
```

---

## 13.1 Agendamento sugerido

Pseudo-cron:

```cron
# Base ANEEL: dataset oficial tem frequência declarada semanal.
0 5 * * 1 tariff-updater --source aneel

# Fontes regulatórias com PDFs/links mutáveis:
30 5 * * * tariff-updater --source agenersa
45 5 * * * tariff-updater --source naturgy

# Bandeira: checagem diária é barata e evita depender do dia exato da publicação.
0 6 * * * tariff-updater --source aneel-flags
```

Além disso, qualquer tarifa com <=30 dias para o fim da vigência entra automaticamente na fila diária.

---

## 13.2 Exemplo de GitHub Actions

```yaml
name: Atualizar base tarifária

on:
  schedule:
    - cron: "15 8 * * *"  # UTC; ajustar conforme necessidade
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - run: pip install -r requirements.txt

      - name: Buscar e validar tarifas
        run: python -m updater.main

      - name: Rodar testes
        run: pytest -q

      - name: Verificar mudanças
        run: git diff --exit-code || echo "TARIFF_CHANGED=true" >> "$GITHUB_ENV"

      # Em produção, a preferência é abrir PR com o diff.
      # Auto-publicação pode ser permitida apenas para fontes
      # estruturadas e validações de alta confiança.
```

### Política recomendada

| Origem | Auto-publicar? |
|---|---|
| ANEEL CSV, schema conhecido, sem override | Sim, após validação |
| Bandeira ANEEL identificada inequivocamente | Sim |
| Novo PDF Naturgy com parser validado | Sim ou PR, conforme confiança |
| Novo PDF AGENERSA com layout conhecido | Preferencialmente PR |
| PDF com layout alterado | Não; `needs_review` |
| Fonte municipal sem parser confiável | Não |
| LLM usado para extração | Não diretamente; gerar candidato |

---

# 14. Fontes e links

## 14.1 Energia — ANEEL

**Dataset principal**

https://dadosabertos.aneel.gov.br/pt_BR/dataset/tarifas-distribuidoras-energia-eletrica

**CSV direto**

https://dadosabertos.aneel.gov.br/dataset/5a583f3e-1646-4f67-bf0f-69db4203e89e/resource/fcf2906c-7c32-4b9b-a637-054e7a5234f4/download/tarifas-homologadas-distribuidoras-energia-eletrica.csv

**Dicionário**

https://dadosabertos.aneel.gov.br/pt_BR/dataset/tarifas-distribuidoras-energia-eletrica/resource/2d3478e0-8aa0-4cd4-81a7-5f8967cd8804

**Componentes tarifários**

https://dadosabertos.aneel.gov.br/dataset/componentes-tarifarias

**Bandeiras**

https://www.gov.br/aneel/pt-br/assuntos/tarifas/bandeiras-tarifarias

**Bandeira de agosto/2026**

https://www.gov.br/aneel/pt-br/assuntos/noticias/2026-defeso-eleitoral/bandeira-tarifaria-continua-amarela-em-agosto

**Energisa Minas Rio 2026**

https://www.energisa.com.br/sites/energisa/files/media/documents/2026-06/Quadro_de_Tarifas_EMR.pdf

**Enel RJ 2026**

https://www.enel.com.br/content/dam/enel-br/Tarifas/SEI_48500.030702_2025_70%20REH%203570-2026.pdf

### Espelhos jurídicos usados para conferir o caso Light

Esses links são úteis como apoio de pesquisa, mas a automação deve priorizar ANEEL/DOU como autoridade sempre que o ato oficial puder ser obtido.

Despacho 921/2026:

https://atosoficiais.com.br/aneel/despacho-n-921-2026-decide-i-altera-se-o-resultado-do-reajuste-tarifario-anual-de-2026-da-light-servicos-de-eletricidade-s-a-light-objeto-da-2026-03-17-versao-original?origin=instituicao

Despacho 2129/2026:

https://atosoficiais.com.br/aneel/despacho-n-2129-2026-decide-i-suspender-os-efeitos-do-despacho-str-aneel-no-1-063-de-25-de-marco-de-2026-ii-retornar-a-vigencia-dos-efeitos?origin=instituicao

---

## 14.2 Gás

**AGENERSA — Tarifas em vigor**

https://www.rj.gov.br/agenersa/tarifas-em-vigor

**CEG — 01/08/2026**

https://www.naturgy.com.br/wp-content/uploads/2026/07/PB85USD_Tarifa-CEG-01.08.26.pdf

**CEG Rio — 01/08/2026**

https://www.naturgy.com.br/wp-content/uploads/2026/07/PB85USD_Tarifa-CRIO-01.08.26.pdf

---

## 14.3 Água/esgoto

**AGENERSA — índice oficial de tarifas**

https://www.rj.gov.br/agenersa/tarifas-em-vigor

**Águas de Juturnaíba**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUASDEJUTURNAIBA_0.pdf

**Prolagos**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/PROLAGOS_2.pdf

**Águas da Condessa**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS%20DA%20CONDESSA_0.pdf

**Águas de Paraty**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS%20DE%20PARATY_0.pdf

**Águas de Pádua**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS-DE-PADUA.pdf

**CEDAE**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/CEDAE_4.pdf

**Águas do Rio — Bloco 1**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUASDORIOBL%201.pdf

**Águas do Rio — Bloco 4**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUASDORIOBL%204.pdf

**Rio+**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/RIO%2BSANEAMENTO.pdf

**Águas da Imperatriz**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUAS%20DA%20IMPERATRIZ_0.pdf

**Iguá**

https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/IGUA_0.pdf

---

## 14.4 SINISA

**Área do prestador**

https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/area-do-prestador

**Prestadores locais**

https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/area-do-prestador/prestadores-locais-2013-abastecimento-de-agua

**Prestadores regionais**

https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/area-do-prestador/prestadores-regionais-de-abastecimento-de-agua-e-ou-de-esgotamento-sanitario

---

## 14.5 Home Assistant

**Utility Meter**

https://www.home-assistant.io/integrations/utility_meter/

**Input Number**

https://www.home-assistant.io/integrations/input_number/

**Reload Input Number**

https://www.home-assistant.io/actions/input_number.reload/

**RESTful Sensor**

https://www.home-assistant.io/integrations/sensor.rest/

**REST**

https://www.home-assistant.io/integrations/rest/

---

# 15. Pendências para uma base de água 100% estadual

A pesquisa não encontrou ainda uma tabela tarifária residencial corrente, inequívoca e primária para **todos** os prestadores fora da AGENERSA.

Não é correto marcar a água do RJ como 100% completa neste estágio.

Prestadores/municípios que ainda precisam de fechamento documental individual incluem, entre outros:

- Areal;
- Barra do Piraí — componente municipal;
- Casimiro de Abreu / SAAE;
- Comendador Levy Gasparian;
- Conceição de Macabu;
- Itatiaia;
- Mendes;
- Porto Real;
- Quatis;
- Rio das Flores;
- São José do Vale do Rio Preto / Águas do Rio Preto;
- Três Rios / SAAETRI;
- Volta Redonda / SAAE;
- Guapimirim / Fontes da Serra.

Também devem ser fechadas/recertificadas as tabelas atuais das concessões municipais como:

- Águas de Niterói;
- Águas de Nova Friburgo;
- Águas do Imperador — Petrópolis;
- Águas do Paraíba — Campos;
- Águas das Agulhas Negras — Resende;
- SAAE Angra;
- SAAE Barra Mansa.

### Barra Mansa — cuidado específico

Foram encontrados indícios/documentos de mais de um reajuste em 2026.

Regra para o pipeline:

```text
NÃO aplicar o percentual mais recente sobre a tabela anterior
e publicar o resultado calculado como se fosse tarifa oficial.
```

Somente publicar quando houver:

- tabela final emitida pelo prestador/regulador; ou
- ato que defina de forma inequívoca tanto a base quanto a fórmula necessária.

---

# 16. Política final recomendada

## O LLM pode

- ler a base verificada;
- escolher o provider correto a partir do endereço/área;
- gerar YAML do Home Assistant;
- gerar templates de custo;
- explicar diferenças de tarifa;
- produzir candidato de parsing de novos documentos.

## O LLM não pode

- descobrir sozinho uma tarifa ausente;
- preencher `valid_until` por suposição;
- escolher concessionária em município com múltiplas áreas sem informação suficiente;
- calcular reajuste e chamar o resultado de tarifa oficial;
- transformar tarifa em cascata em taxa única;
- aplicar regra de esgoto de um prestador a outro;
- sobrescrever uma tarifa verificada sem evidência da nova fonte.

---

# 17. Critério de “base completa”

A base só deve declarar:

```yaml
complete: true
```

quando:

1. todos os prestadores residenciais aplicáveis estiverem catalogados;
2. toda área territorial estiver mapeada;
3. cada tarifa vigente tiver fonte oficial;
4. todas as categorias residenciais necessárias estiverem representadas;
5. a fórmula de cobrança estiver identificada;
6. tarifa social estiver separada;
7. água/esgoto estiverem separados quando necessário;
8. todas as vigências e exceções estiverem registradas;
9. nenhum registro estiver `expired_pending_source`;
10. o pipeline reproduzir a base a partir das fontes sem edição manual silenciosa.

Até lá, usar:

```yaml
complete:
  electricity: true
  gas_regulated_network: true
  water_statewide: false
```

---

# 18. Próxima etapa técnica

A sequência recomendada para transformar este levantamento em algo operacional é:

```text
1. Definir tariff.schema.json
2. Criar sources_RJ.yaml
3. Implementar parser ANEEL
4. Gerar electricity_RJ.yaml automaticamente
5. Implementar Naturgy CEG/CEG Rio
6. Implementar índice AGENERSA + parsers das tabelas
7. Montar provider_map_RJ.yaml
8. Resolver prestadores municipais restantes
9. Implementar overrides regulatórios
10. Criar validators + testes
11. Gerar tariffs_RJ.json
12. Integrar Home Assistant como consumidor
13. Agendar atualização automática
14. Alertar quando uma tarifa estiver próxima do vencimento ou sem sucessora
```

Essa separação permite evoluir posteriormente de RJ para todo o Brasil sem refazer a arquitetura.
