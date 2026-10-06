# Mapa dos documentos

Primeiro arquivo a abrir ao retomar trabalho neste repositório.

**O estado vivo da frente** é o HANDOFF mais novo de [`roadmap/`](roadmap/) —
hoje [HANDOFF-2026-10-06-fatura-funcao-do-medidor.md](roadmap/HANDOFF-2026-10-06-fatura-funcao-do-medidor.md).
Handoff antigo traz no cabeçalho por qual foi superado.

## Convenções

- Documento novo: `aaaa-mm-dd-hhmm-descricao.md`. Sem `-vN`.
- Decisão traz no topo `status: proposto | rejeitado | aceito | obsoleto | superado por <arquivo>`.
- Revisar é criar arquivo novo e marcar o antigo como superado. O antigo fica.
- Links conferidos com `lychee --offline --root-dir . docs/`.
- O repositório é público: nada desta casa (endereço, nome de equipamento,
  identificador de entidade) entra em documento versionado. O que é da casa
  vive em `inventario/`, fora do versionamento.

## Decisões

| Documento | Status | O que decide |
|---|---|---|
| [2026-10-06-1600-fatura-como-funcao-do-medidor.md](2026-10-06-1600-fatura-como-funcao-do-medidor.md) | aceito | A fatura de energia é calculada do consumo medido e das datas de leitura; cada parâmetro tem fonte e ajuste manual |
| [2026-10-06-1200-fonte-da-tarifa-de-energia.md](2026-10-06-1200-fonte-da-tarifa-de-energia.md) | superado pela de cima | O preço e os impostos da energia vinham digitados da fatura |

## Referência

| Documento | O que é |
|---|---|
| [2026-10-06-1600-formulas-da-fatura-de-energia.md](2026-10-06-1600-formulas-da-fatura-de-energia.md) | As fórmulas da fatura de energia, numeradas, cada uma ligada ao dado, à calculadora, ao sensor e à cerca — o documento para revisar o cálculo |
| [API-REFERENCE_20260823_verificado.md](API-REFERENCE_20260823_verificado.md) | O contrato de API do instalador com o Home Assistant — vigente |
| [API-REFERENCE.md](API-REFERENCE.md) | A versão anterior do contrato — superada pela de cima |
| [ACHADOS-VERIFICADOS.md](ACHADOS-VERIFICADOS.md) | Fatos medidos que custam caro se esquecidos |
| [homeassistant_installer_tiers_curadoria_2026-08-23.md](homeassistant_installer_tiers_curadoria_2026-08-23.md) | As regras de camada do catálogo |
| [base_tarifaria_RJ_home_assistant.md](base_tarifaria_RJ_home_assistant.md) | Pesquisa das tarifas de energia, gás e água do RJ — com nota de revisão no topo |
| [INVENTARIO.md](INVENTARIO.md) | O inventário que serviu de cardápio para o catálogo — papel cumprido |
| [PLANO.md](PLANO.md) | O plano original do instalador, aprovado em 2026-08-23 |

## Frentes

| Pasta | O que guarda |
|---|---|
| [roadmap/](roadmap/) | Os HANDOFFs — a porta de entrada de cada frente |
| [roadmap/decisoes/](roadmap/decisoes/) | Os diários das frentes: decisões com a razão, provas e defeitos |
| [planos_concluidos/](planos_concluidos/README.md) | Os planos como foram aprovados, com índice |
| [previews/](previews/) | Pranchas de tela |
