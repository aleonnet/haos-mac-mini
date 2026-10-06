# Energia na fatura — o painel volta a fechar com a conta da Light

status: aceito

> Cópia do plano como foi aprovado em 2026-10-06, limpa de identificadores da
> casa. O que mudou na execução está no HANDOFF da frente e no diário.

## Context

O dono comparou o painel com a fatura de um ciclo de leitura: **354 kWh e R$ 542,46**
na conta; **348.013,79 kWh e R$ 336.453,33** no painel de Energia; **R$
50.609,13** no cartão de Custos. O medidor está certo — os contadores do próprio
Shelly somam 356,68 kWh no período (0,76 % da fatura). O que está errado é o
pacote de energia do **produto**, em quatro frentes medidas:

1. **A soma das fases trata "sem resposta" como zero.** Quando o Shelly some por
   segundos (queda de luz, ou perda de comunicação), o total cai fase a fase até
   zero e volta; isso é lido como medidor zerado e a vida inteira dele (~12,9 mil
   kWh) é somada de novo. Foram 29 ocorrências no período.
2. **Três referências a entidades que não existem**, escondidas por valor padrão:
   o fator de tributos nunca é aplicado, os encargos nunca são somados, e a água
   compara com zero. O identificador nasce do NOME do sensor, não da chave única.
3. **Todo campo que o dono preenche tem valor inicial fixo** e por isso volta ao
   valor de fábrica a cada reinício.
4. **O desenho não fecha com a fatura:** mês-calendário em vez de leitura a
   leitura; PIS, COFINS e bandeira congelados em agosto; e a tarifa atribuída a
   uma fonte que não a contém.

Decisões do dono em 2026-10-06, que este plano cumpre: **reparar o histórico** ·
**tudo numa frente só** · **os preços vêm da fatura** · **os impostos vêm da
fatura** · **a Light segue a lei** (a Tarifa Branca usa a tabela do ato vigente,
o mesmo que duas faturas já provam para o Convencional).

Resultado pretendido: com os números de uma conta digitados, o painel reproduz
essa conta ao centavo; uma queda de luz não soma mais nada; o que o dono digita
fica; e o ciclo da fatura passa a mostrar o que o Shelly mediu.

## Risk band

**critical** — reescreve somas de estatística no banco de uma instância de
produção e altera três pacotes do produto público. Por isso: diagnóstico de ponta
a ponta já medido; cerca nova que REPROVA antes do conserto e é refutada depois;
backup pelo cofre antes de tocar o banco, com cada ajuste registrado junto do
inverso; e bancada do dono no fim, comparando painel e fatura.

## Impact sweep (commands run now)

```
sudo cat /homeassistant/.storage/energy
sudo cat /homeassistant/packages/energia_br.yaml
SELECT id, statistic_id, unit_of_measurement, has_sum FROM statistics_meta
SELECT start_ts, state, sum FROM statistics WHERE metadata_id=48 AND start_ts>=? AND start_ts<? ORDER BY start_ts
WHERE m.entity_id IN (o total da casa e as três fases do medidor)
reg = {e['entity_id'] for e in json.load(open('/config/.storage/core.entity_registry'))['data']['entities']}
curl -fsS "$U/sensor.py" | awk '/def calculate_adjustment/,/def async_reading/'
curl -fsS "$U/const.py" | grep -nE "^CONF_|^SERVICE_|^ATTR_"
curl -fsS "$B/input_number/__init__.py" | awk '/async def async_added_to_hass/,/async def async_set_value/'
curl -fsS "$B/input_number/__init__.py" | grep -n "CONF_STEP
curl -fsS "$B/recorder/websocket_api.py" | grep -n -B3 -A28 '"recorder/adjust_sum_statistics"'
RIOS = (os dois sensores de estado dos no-breaks)
flt = {"NumCNPJDistribuidora": "60444437000146", "DscSubGrupo": "B1", "DscClasse": "Residencial"}
grep -n "EMBUTIDO >>>\|EMBUTIDO <<<" haos-install.sh
./tools/embed.sh --check
grep -rnI "1[.,]73992\|1739[.,]92\|0[.,]94793
cat .github/workflows/ci.yml
```

O que cada um mediu (2026-10-06, 10:04–11:40 -03):

| Medição | Achado |
|---|---|
| Painel de Energia da instância | Três conexões de rede: os medidores mensais por posto, com preço em `sensor.preco_convencional` — é o que `lib/ha-api.py:501` configura |
| Pacote da instância × produto | **Idênticos** (mesma impressão digital `4154075e…`): o defeito é do produto |
| Unidades | kWh em toda a cadeia — não há erro de unidade; a semelhança entre 348 mil e 354 era coincidência |
| Contadores do Shelly, no ciclo da fatura | **356,68 kWh** (três fases somadas) |
| Soma por estatística, mesmo período | medidores mensais **348.010,41 kWh**; total da casa com 23 horas de salto e 940.679,40 kWh só nos saltos |
| Um sumiço, estado a estado | o total cai fase a fase até zero e volta 14 s depois |
| Por que cada sumiço soma a vida inteira | código do medidor na versão em execução (2026.9.3): ajuste = novo − antigo, somado quando ≥ 0; com `periodically_resetting: false` usa o último valor válido |
| Causa dos sumiços | 4 de 7 são falta de luz (os no-breaks foram para a bateria no mesmo instante); 3 **não** são (horário fixo, 5–15 s, tensão normal) — causa destes ainda desconhecida |
| Referências inexistentes, varredura dos três pacotes e dos painéis | `sensor.fator_tributos` (`packages/energia_br.yaml:137`, 144, 151, 158) · `sensor.encargos_fixos_mes` (`packages/energia_br.yaml:201`, 210) · `sensor.agua_esgoto_simulado` (`packages/agua_br.yaml:130`, 134, 138, 156). Gás, painéis e demais pacotes: zero |
| Campo com valor inicial | no código da versão em execução, quem tem valor inicial não restaura o último estado; no banco, todos os campos datam do último início |
| Menor passo de um campo numérico | o código aceita até 0,000000001 — o cabeçalho do pacote dizia 0,001, e por isso as tarifas viraram números fixos |
| Ajuste de soma de estatística | existe comando administrativo próprio (`recorder/adjust_sum_statistics`), que corrige do instante informado em diante e mantém a continuidade |
| Base aberta da ANEEL (gerada no mesmo dia), Light B1 Residencial, vigência 15/03/2026–14/03/2027 | Convencional 0,88056 · Ponta 1,61431 · Intermediário 1,11884 · Fora ponta 0,77543. **Nenhuma vigência tem 0,94793** |
| De onde vêm os números do pacote | de `docs/base_tarifaria_RJ_home_assistant.md:233`, transcritos de um espelho de terceiros do Despacho 921/2026; o próprio documento põe espelho em último lugar na ordem de confiança |
| A fatura reproduz-se pelos próprios números | 354 × 1,34405 = 475,79 (475,78) · ICMS 24 % → 114,19 · PIS 1,01 % → 3,65 · COFINS 4,68 % → 16,92 · com 64,60 e 2,08 → 542,47 (542,46) |
| Como os pacotes viajam | cópias embutidas em `haos-install.sh`, regeneradas por `tools/embed.sh` e conferidas pelo portão; a escrita na instância é a de `haos-install.sh:2065` |
| Cerca de hoje sobre os pacotes | nenhuma semântica: o portão só confere que o arquivo foi escrito. O CI já sobe um Home Assistant de verdade para o arnês de contrato |

Leitura dos arquivos do escopo: os três pacotes, o painel de Custos, o fluxo do
CI e o documento de pesquisa das tarifas foram lidos por inteiro. O instalador
(6.121 linhas) foi lido em janelas — 1 a 2.706 e 5.190 a 6.121; o miolo são as
cópias embutidas, conferidas idênticas às fontes por `./tools/embed.sh --check`.
Do registro de mudanças li o topo por inteiro e a estrutura do restante: a
mudança ali é acréscimo na seção de não publicados.

## Changes, per file

**Produto — a cerca vem primeiro**

- `contract/pacotes.py` (novo) — arnês dos pacotes contra um Home Assistant de
  verdade, reusando as funções de `contract/check.py`. Prova: toda entidade
  citada nos pacotes e painéis existe na instância que os carregou (o
  identificador é o que o próprio Home Assistant gerou); a fatura de agosto e a
  de outubro saem ao centavo dos números digitados; a soma não é publicada com
  uma fase sem valor; campo digitado sobrevive a um reinício; o medidor da fatura
  zera na data informada; água e gás reproduzem os exemplos.
- `tools/pacotes-arnes.sh` (novo) — sobe o contêiner com os pacotes do
  repositório, roda o arnês e desmonta. O mesmo comando no Mac e no CI.
- `.github/workflows/ci.yml` — trabalho novo que chama esse comando na versão
  fixada e na estável, como o arnês de contrato já faz.

**Produto — o conserto**

- `packages/energia_br.yaml`
  - Total da casa: só existe com **todas** as fases numéricas; sem isso fica
    indisponível em vez de publicar soma parcial.
  - Medidores: passam a usar o último valor válido e a ficar visíveis durante a
    indisponibilidade; entra o **medidor da fatura**, sem ciclo de calendário,
    zerado ao meio-dia da data de leitura informada.
  - **Da fatura, digitados e guardados:** preço unitário com tributos, tarifa
    unitária, ICMS, PIS, COFINS, iluminação pública, complementos, bônus, total
    da conta e data da próxima leitura. Nenhum com valor inicial.
  - Preço convencional = o preço com tributos impresso na conta. Conferência:
    tarifa × fator dos três impostos tem de bater com ele.
  - Tarifa Branca = (tarifa do posto na tabela + bandeira implícita na conta) ×
    fator dos impostos da conta.
  - Decomposição dos impostos em reais, fatura do ciclo, desvio da conferência.
  - Nomes corrigidos nas seis linhas; cabeçalho reescrito com as fontes certas.
- `packages/agua_br.yaml` — nome corrigido nas quatro linhas; campos do dono sem
  valor inicial.
- `packages/gas_br.yaml` — campos do dono sem valor inicial; o fator de correção
  passa a aceitar as cinco casas da fatura; comentário do passo mínimo corrigido.
- `dashboards/custos_br.yaml` — bloco "da fatura" com os campos, o ciclo e as
  conferências. Só campo e valor: nenhum texto de explicação na tela.
- `haos-install.sh` — apenas as cópias embutidas, regeneradas pela ferramenta.

**Documentação e fontes**

- `docs/2026-10-06-1200-fonte-da-tarifa-de-energia.md` (novo, decisão no formato
  da casa, status aceito) — o problema, as três tabelas lado a lado com a data e
  o comando de cada medição, as fontes com citação literal e data de acesso, a
  decisão (a fatura é a fonte do que se paga; o ato vigente é a fonte da Branca;
  a base aberta fica como referência do valor homologado), as consequências e a
  seção de confirmação apontando o arnês.
- `docs/base_tarifaria_RJ_home_assistant.md` — nota no topo: a seção da Light e a
  linha dela no resumo foram revistas pela decisão acima, e a afirmação sobre o
  passo mínimo do campo numérico está errada. O resto do documento fica intacto.
- `docs/README.md` (novo) — o mapa da árvore de documentos, que a norma da casa
  exige e este repositório não tinha.
- `CHANGELOG.md` — seção de não publicados: os quatro defeitos e a mudança de
  desenho. Sem subir versão: isso é só sob ordem.
- `docs/roadmap/HANDOFF-2026-10-06-energia-na-fatura.md` (novo), com o anterior
  `docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md` marcado como superado;
  `docs/roadmap/decisoes/2026-10-06-1200-energia-na-fatura.md` (novo, diário);
  `docs/planos_concluidos/2026-10-06-1200-energia-na-fatura.plan.md` (novo) e a
  linha em `docs/planos_concluidos/README.md`.

**Instância desta casa** — `inventario/custos/`, fora do versionamento

- `implanta-pacotes.sh` — backup pelo cofre do próprio instalador, escrita dos
  três pacotes e do painel a partir das fontes do repositório, verificação de
  configuração, volta atrás conferida por impressão digital, reinício.
- `repara-historico.py` — pede a senha do dono por entrada padrão (nunca em
  argumento); modo de plano que só imprime; aplica: os campos da fatura de
  outubro, a calibração dos nove medidores e os ajustes de soma hora a hora nas
  dez estatísticas, tendo os contadores do Shelly como verdade; grava um registro
  com o inverso de cada ajuste.
- `verifica-custos.sh` — o portão da casa: lê o banco e reprova se o período de
  ciclo da fatura não fechar com o Shelly, se sobrar hora com salto, ou se algum
  medidor divergir do consumo real desde o último zeramento.

**Fora do repositório, por serem regras e estado da casa:** a emenda do dono à
regra de formato de resposta (tabela e fecho só quando fizer sentido), no arquivo
do protocolo; e a seção nova no documento de passagem para os outros agentes.

## Scope

```
packages/energia_br.yaml
packages/agua_br.yaml
packages/gas_br.yaml
dashboards/custos_br.yaml
haos-install.sh
contract/pacotes.py
tools/pacotes-arnes.sh
.github/workflows/ci.yml
CHANGELOG.md
docs/2026-10-06-1200-fonte-da-tarifa-de-energia.md
docs/base_tarifaria_RJ_home_assistant.md
docs/README.md
docs/roadmap/HANDOFF-2026-10-06-energia-na-fatura.md
docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md
docs/roadmap/decisoes/2026-10-06-1200-energia-na-fatura.md
docs/planos_concluidos/2026-10-06-1200-energia-na-fatura.plan.md
docs/planos_concluidos/README.md
inventario/custos/**
```

**Arquivos novos declarados:** `contract/pacotes.py`, `tools/pacotes-arnes.sh`,
`docs/2026-10-06-1200-fonte-da-tarifa-de-energia.md`, `docs/README.md`,
`docs/roadmap/HANDOFF-2026-10-06-energia-na-fatura.md`,
`docs/roadmap/decisoes/2026-10-06-1200-energia-na-fatura.md`,
`docs/planos_concluidos/2026-10-06-1200-energia-na-fatura.plan.md`.

## Acceptance (EARS)

| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | um pacote ou painel cita uma entidade | encontrá-la na instância que carregou os pacotes | `./tools/pacotes-arnes.sh` | imprime `REFERENCIA INEXISTENTE:` |
| 2 | uma das fases fica sem valor | deixar o total indisponível, sem publicar soma menor | `./tools/pacotes-arnes.sh` | imprime `SOMA PARCIAL:` |
| 3 | os números da conta de agosto (304 kWh) e da de outubro (354 kWh) são digitados | devolver 471,92 e 542,46, com no máximo um centavo de diferença | `./tools/pacotes-arnes.sh` | imprime `FATURA NAO REPRODUZ:` |
| 4 | um imposto é digitado errado | acusar na conferência do preço | `./tools/pacotes-arnes.sh` | imprime `CONFERENCIA CEGA:` |
| 5 | um campo é digitado e o Home Assistant reinicia | manter o valor digitado | `./tools/pacotes-arnes.sh` | imprime `CAMPO NAO PERSISTE:` |
| 6 | chega o meio-dia da data de leitura informada | zerar o medidor da fatura, e só ele | `./tools/pacotes-arnes.sh` | imprime `CICLO NAO ZERA:` |
| 7 | os exemplos de água e gás são carregados | devolver os valores já validados | `./tools/pacotes-arnes.sh` | imprime `AGUA NAO REPRODUZ:` ou `GAS NAO REPRODUZ:` |
| 8 | um pacote é alterado | manter a cópia embutida idêntica à fonte | `./tools/embed.sh --check` | imprime `DIVERGE` |
| 9 | o portão do produto roda depois da frente | continuar íntegro, cerca de segredo incluída | `./tools/gate.sh` | imprime `[ERRO]` ou `checagem(ns) falharam` |
| 10 | o histórico é reparado | fazer o ciclo da fatura somar o que o Shelly mediu, sem hora com salto | `bash inventario/custos/verifica-custos.sh` | imprime `HISTORICO DIVERGE:` ou `SALTO REMANESCENTE:` |
| 11 | os medidores são recalibrados | mostrar o consumo real desde o último zeramento de cada um | `bash inventario/custos/verifica-custos.sh` | imprime `MEDIDOR DIVERGE:` |
| 12 | a documentação é escrita | não ter link interno quebrado | `lychee --offline --root-dir . docs/` | qualquer erro listado |

## Verification (after the last commit)

```
./tools/gate.sh
./tools/embed.sh --check
./tools/pacotes-arnes.sh
"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/custos/implanta-pacotes.sh inventario/custos/verifica-custos.sh
bash inventario/custos/verifica-custos.sh
lychee --offline --root-dir . docs/
```

Expected: portão em `RESULTADO: portão limpo`; os oito blocos embutidos
idênticos; `PACOTES OK`; verificador de shell sem nenhuma linha; `CUSTOS OK`;
zero erros de link. O portão roda primeiro porque é ele que resolve o verificador
de shell fixado.

## Refutation

Cada cerca nova é escrita **antes** do conserto e tem de reprovar o pacote de
hoje; depois do conserto, cada uma é refutada com o defeito plantado e o arquivo
restaurado conferido por impressão digital.

- `REFERENCIA INEXISTENTE:` — devolver um dos três nomes errados.
- `SOMA PARCIAL:` — devolver a disponibilidade antiga do total.
- `FATURA NAO REPRODUZ:` — trocar o preço da conta pelo produto tarifa × 1.
- `CONFERENCIA CEGA:` — remover a comparação entre o preço digitado e tarifa × fator.
- `CAMPO NAO PERSISTE:` — devolver o valor inicial a um campo do dono.
- `CICLO NAO ZERA:` — devolver o ciclo de calendário ao medidor da fatura.
- `HISTORICO DIVERGE:` e `SALTO REMANESCENTE:` — rodar o portão da casa antes do
  reparo: tem de reprovar com os 348 mil.

## Out of scope

- A causa dos três sumiços em horário fixo: será medida à parte; o conserto da
  soma não depende dela.
- Buscar a tabela da Branca de forma automática: a tabela fica como número do ato
  vigente, com a proveniência escrita. Na execução tento abrir o anexo do ato
  pelo navegador do dono; conferindo, a citação literal entra na decisão; não
  conseguindo, a pendência fica escrita no pacote e na decisão.
- Subir a versão do produto, publicar ou empurrar para o remoto: só sob ordem.
- Os pacotes de clima, mídia e reserva; o catálogo; o arnês de contrato existente.

## Overnight policy

- Decidido de noite, com fonte: forma dos sensores e dos campos (código da versão
  em execução, já medido), textos de documentação.
- Reservado ao dono, e proibido de madrugada: implantar na instância, mexer no
  banco, reiniciar o Core, digitar valores de fatura, empurrar para o remoto.

## Open questions

- Nenhuma. Premissa registrada: a leitura do medidor acontece em algum momento do
  dia; o medidor da fatura zera ao meio-dia da data impressa na conta.
