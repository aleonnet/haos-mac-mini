---
status: superado por 2026-10-06-1600-fatura-como-funcao-do-medidor.md
date: 2026-10-06
decisores: dono do repositório
---

# De onde vem o preço da energia: a fatura, não a tabela

## Contexto e problema

O package de energia (`packages/energia_br.yaml`) calculava o preço do kWh a
partir de uma tabela escrita no próprio arquivo — tarifa por posto, bandeira e
alíquotas — e atribuía essa tabela aos dados abertos da ANEEL. Em 2026-10-06 o
dono comparou o painel com uma fatura real e os números não fechavam. A
investigação separou dois problemas: defeitos de cálculo (registrados no
`CHANGELOG.md`) e uma pergunta de desenho, que é o assunto deste documento:

**qual é a fonte do preço que o painel usa?**

Três fatos medidos responderam que a tabela não pode ser essa fonte.

**1. A base aberta da ANEEL não contém o valor que a distribuidora cobra.**
Consulta feita em 2026-10-06 11:36 -03, com o conjunto gerado no mesmo dia:

```
curl -G "https://dadosabertos.aneel.gov.br/api/3/action/datastore_search" \
  --data-urlencode 'resource_id=fcf2906c-7c32-4b9b-a637-054e7a5234f4' \
  --data-urlencode 'filters={"NumCNPJDistribuidora":"60444437000146","DscSubGrupo":"B1","DscClasse":"Residencial","DscBaseTarifaria":"Tarifa de Aplicação","DscDetalhe":"Não se aplica"}'
```

Para a vigência de 2026-03-15 a 2027-03-14 ela devolve, sob o ato
"RESOLUÇÃO HOMOLOGATÓRIA Nº 3.571, DE 10 DE MARÇO DE 2026" (campo `DscREH`,
literal), TUSD + TE em R$/MWh:

| Modalidade · posto | TUSD | TE | R$/kWh |
|---|---|---|---|
| Convencional | 578,56 | 302,00 | 0,88056 |
| Branca · ponta | 1172,93 | 441,38 | 1,61431 |
| Branca · intermediário | 829,51 | 289,33 | 1,11884 |
| Branca · fora ponta | 486,10 | 289,33 | 0,77543 |

Nenhuma das vigências publicadas traz 0,94793, que é o que o package usava.

**2. Duas faturas reais trazem 0,94793.** A tarifa unitária impressa na conta
já inclui a bandeira; descontada a bandeira, as contas de agosto e de outubro
de 2026 dão 0,94793 para o Convencional — 7,65 % acima da base aberta. A
diferença não é atraso de publicação: a base aberta publica a resolução
homologada, e o reajuste de 2026 dessa distribuidora foi alterado depois por
despacho (Despacho ANEEL 921/2026, com efeitos restaurados pelo Despacho
2129/2026).

**3. Os valores do package vieram de um espelho de terceiros.** Eles foram
transcritos de `base_tarifaria_RJ_home_assistant.md` (pesquisa de 2026-08-23),
que por sua vez os tirou de um espelho privado do despacho — a fonte que o
próprio documento põe em último lugar na ordem de confiança (§2.1). Em
2026-10-06 tentei abrir o ato em fonte primária e não consegui: o espelho
responde com verificação anti-robô, e o arquivo oficial
(`www2.aneel.gov.br/cedoc/`) respondeu 403 às duas grafias tentadas.

Além disso, mesmo uma tabela correta não reproduz a conta: PIS e COFINS mudam
todo mês (1,23 % e 5,67 % em agosto; 1,01 % e 4,68 % em outubro), e a bandeira
vem rateada pelos dias do ciclo.

## O que pesou

- O painel tem de fechar com a conta que o dono paga, ao centavo.
- Nenhum número pode ser publicado com uma fonte que não o contém.
- O que muda todo mês não pode estar escrito como constante no arquivo.
- O package é público: tem de servir a qualquer distribuidora, não só a esta.

## Opções consideradas

1. **Manter a tabela no arquivo e corrigir os números.**
2. **Buscar a tabela automaticamente nos dados abertos da ANEEL.**
3. **Digitar da fatura o que a fatura imprime**, e manter a tabela só para o
   que a fatura não tem — os postos da Tarifa Branca.

## Decisão

**Opção 3.** Decidida pelo dono em 2026-10-06: *"Os preços corretos devem vir
da fatura de energia"*, *"E impostos também"*, e, para a Tarifa Branca, *"vamos
considerar que a light siga a lei"* — a simulação usa a tabela do ato vigente.

Na prática:

| O quê | Fonte | Onde mora |
|---|---|---|
| Preço do kWh com tributos, tarifa unitária, ICMS, PIS, COFINS, iluminação pública, complementos, bônus, total, data da próxima leitura | a fatura | campos digitados, sem valor de fábrica |
| Bandeira do ciclo | deduzida: tarifa unitária da conta − convencional da tabela | calculada |
| Tarifa por posto da Branca | o ato vigente (despacho), transcrito | tabela no package, com a proveniência escrita |
| Valor homologado | dados abertos da ANEEL | só referência, neste documento |

O que se paga no Convencional sai **direto do preço impresso**, sem recalcular.
A tabela só entra na simulação da Branca: (tarifa do posto + bandeira da conta)
× fator dos três impostos da conta.

### Consequências

- Bom: com os números de uma conta digitados, o painel a reproduz ao centavo —
  provado para as duas faturas (304 kWh → 471,92; 354 kWh → 542,47 contra
  542,46 impressos).
- Bom: um imposto digitado errado aparece: tarifa × fator tem de dar o preço
  com tributos, e a diferença é mostrada.
- Bom: o Convencional passa a servir a qualquer distribuidora sem editar YAML.
- Ruim: instalação nova mostra custo zero até a primeira conta ser digitada, e
  quem atualiza precisa digitar os campos novos uma vez.
- Ruim: a cada conta são dez campos. É o preço de fechar com ela.
- **Pendência aberta:** as três tarifas da Branca (ponta 1,73992 ·
  intermediária 1,20499 · fora de ponta 0,83447) **não foram conferidas em
  fonte primária**. A razão entre elas e a base aberta (1,0778 · 1,0770 ·
  1,0761) é coerente com a do Convencional (1,0765), que as faturas provam —
  mas coerência não é prova. O package diz isso no cabeçalho e no próprio
  sensor da tabela. Fecha quando alguém abrir o anexo do despacho.

### Confirmação

`./tools/pacotes-arnes.sh` sobe um Home Assistant de verdade com os packages do
repositório e reprova se: as duas faturas não saírem ao centavo
(`FATURA NAO REPRODUZ:`), um imposto errado não for acusado
(`CONFERENCIA CEGA:`), um campo digitado não sobreviver a um reinício
(`CAMPO NAO PERSISTE:`) ou uma instalação nova nascer com número diferente de
zero (`ESTADO DE FABRICA:`). Roda no CI na versão fixada e na estável.

## Prós e contras das opções

### 1. Manter a tabela e corrigir os números

- Bom: nada a digitar.
- Ruim: PIS, COFINS e bandeira mudam todo mês — a tabela estaria errada no mês
  seguinte ao da correção.
- Ruim: continua dependendo de uma transcrição que ninguém conferiu.

### 2. Buscar nos dados abertos

- Bom: automático, fonte oficial.
- Ruim: para esta distribuidora, em 2026, devolveria um valor 7,65 % abaixo do
  cobrado. Publicaria número errado com selo oficial.
- Ruim: não traz tributos nem o rateio da bandeira.

### 3. Digitar da fatura

- Bom: é o documento que define o que se paga; fecha por construção.
- Bom: a redundância entre os campos (tarifa, alíquotas, preço) vira conferência.
- Ruim: trabalho manual mensal; custo zero até a primeira digitação.

## Mais informação

- Os defeitos de cálculo corrigidos na mesma frente estão no `CHANGELOG.md`.
- A pesquisa original das tarifas, com a nota de revisão no topo:
  [base_tarifaria_RJ_home_assistant.md](base_tarifaria_RJ_home_assistant.md).
- Postos tarifários e regra da Tarifa Branca (ANEEL):
  <https://www.gov.br/aneel/pt-br/assuntos/tarifas/entenda-a-tarifa/postos-tarifarios>
- Dados abertos — tarifas das distribuidoras (ANEEL):
  <https://dadosabertos.aneel.gov.br/dataset/tarifas-distribuidoras-energia-eletrica>
