# Diário — painel dos no-breaks · 2026-09-17

Carimbo desta entrada: 2026-09-17 14:52 -03 (tirado por comando, não digitado).

## Decisões minhas, com a razão

1. **Painel próprio, não o painel de Energia nativo.** O nativo trabalha com
   energia acumulada e os aparelhos só entregam potência instantânea; e
   declarar um no-break como bateria da casa inventaria um fluxo inexistente,
   já que o consumo deles é medido pelo medidor geral. Fonte: documentação
   oficial do painel de Energia.
2. **Nada condicional no painel.** A versão futura do serviço que publica os
   dados não tem data; citar entidade que não existe quebraria o próprio
   critério de aceite. O destino vive só na prancha.
3. **Curadoria pelo utilitário do repositório**, não editando o registro a
   arquivo: ele respeita o que o dono desabilitou à mão. Trocado depois da
   primeira banca, que apontou o utilitário existente.
4. **Identificadores de integração literais** nos roteiros, medidos no ato, em
   vez de função de template — menos mágica, e o portão confere que existem.
5. **Desligar aparelho fica fora do painel.** Desligar a máquina hospedeira
   apagaria o próprio Home Assistant; desligar o roteador derrubaria a rede e
   ele não volta sozinho. Só reinício do roteador entra, com confirmação.

## Bancas

- Rodada 1: **reprovada**, nove bloqueadores — todos conferidos por mim no
  repositório antes de aceitar, e todos procedentes. Classe do que faltou ler:
  o portão e as cercas do próprio repositório.
- Rodada 2: **reprovada**, dois bloqueadores remanescentes (resíduo mecânico,
  aplicados sem nova rodada) e três avisos. Classe: o rito de fechamento do
  monorepo, que eu havia lido como documentação e não como contrato.

## Defeitos meus, pegos por mim ao rodar

- O portão imprimiu aprovação com o verificador quebrado: o documento embutido
  consumia a entrada padrão que traz o registro. Conserto da classe: análise em
  arquivo próprio e código de saída conferido.
- Nome de serviço acusado como entidade ausente. Conserto: lista de nomes de
  serviço descartada antes da conferência.
- Injeção de refutação mal feita (quebrava o YAML antes de exercitar a
  conferência de entidades). Conserto: injeção gerada por programa, mantendo o
  YAML válido.
