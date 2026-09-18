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

---

# Segunda entrada — a autonomia legível · 2026-09-17

Carimbo desta entrada: 2026-09-17 16:18 -03 (tirado por comando, não digitado).

## O defeito, e de quem era

O painel entregou a informação mais valiosa dele em **segundos crus**
(`148140 s`) na etiqueta do topo, nos dois cartões e no gráfico de 24 h. A
prancha aprovada pelo dono mostrava `38 h 09 min`: o entregue divergiu do
desenho aprovado, e a divergência foi minha. Causa medida: a integração declara
a autonomia em segundos, com classe de duração e sem precisão de exibição
sugerida — o frontend mostra o número como ele vem.

## Decisões minhas, com a razão

6. **Sensores derivados de template, não conversão de unidade no registro.**
   O Home Assistant converte duração e aceita horas — mas isso renderia
   `41,15 h`, número e não leitura, e moraria no `.storage`, fora de qualquer
   arquivo que viaje com o repositório. Os derivados vivem no pacote da frente.
7. **Dois derivados por no-break, não um.** O de texto rende `41 h 09 min` e
   serve aos cartões; o numérico em horas é o que o gráfico de 24 h sabe
   desenhar. Um só não cobriria os dois usos.
8. **O número cru desceu para a aba de Diagnóstico** em vez de sumir: em
   segundos ele é diagnóstico, e diagnóstico tem lugar próprio.

## A prova, na ordem em que foi feita

1. Conferência de legibilidade escrita **antes** do conserto → reprovou com
   6 falhas `AUTONOMIA ILEGIVEL:`, uma por citação em segundos crus.
2. Teste da fórmula escrito em seguida → reprovou com
   `FORMULA ILEGIVEL: nenhum sensor de autonomia legivel no pacote`.
3. Sensores derivados escritos → o teste da fórmula passou, rodando no motor de
   template **do próprio Home Assistant**, com seis casos por sensor.
4. Painel religado aos derivados → implantação com `core check: passou` e
   `IMPLANTADO`.
5. Portão completo depois da implantação: `RESERVA OK — 31 entidade(s)
   conferida(s), fase 1` (eram 27 antes desta correção).

## Um susto que era meu, não da casa

Entre 15:50 e 16:16 achei que a instância estivesse fora do ar, porque a porta
8123 não respondia. **A instância nunca caiu**: ela serve na porta 80 — a porta 80 devolveu
`HTTP 200` na instância de produção e também na reserva fria.
Classe do erro: eu supus a porta em vez de medir; a URL que o dono usa não tem
porta nenhuma, e isso estava à vista.

No meio disso, dois fatos reais e medidos, nenhum deles meu:

- O **Mac mini reiniciou às 15:57** (`last reboot`), com relatório de
  `shutdownStall` no mesmo minuto — desligamento ordenado, não pane. Subiu
  sozinho e a VM voltou com ele.
- O **Core se atualizou para 2026.9.2** (o supervisor registra "Successfully
  started Home Assistant 2026.9.2" e a limpeza da imagem 2026.9.1).
- A **reserva fria está LIGADA**: o log da produção traz "Discovered another
  Home Assistant instance with the same instance ID" apontando para o endereço
  da reserva. Duas instâncias com o mesmo identificador no ar ao mesmo tempo é
  exatamente o que a reserva fria existe para não fazer.


---

# Terceira entrada — os protegidos · 2026-09-17

Carimbo desta entrada: 2026-09-17 22:12 -03 (tirado por comando, não digitado).

## Decisões minhas, com a razão

9. **Só reiniciar o roteador entra no painel.** O servidor publica duas ordens
   para ele e uma para a máquina hospedeira; desligar qualquer um dos dois é
   irreversível na prática — um apaga o próprio Home Assistant, o outro derruba
   a rede e não volta sozinho. A razão está escrita **na tela**, não só aqui.
10. **A autonomia dos protegidos nasce no mesmo formato dos no-breaks.** O
    defeito dos segundos crus é de CLASSE, não de instância: dois sensores de
    texto novos, mesma fórmula já provada, e a contagem esperada da cerca subiu
    de dois para quatro no mesmo ato — senão ela aprovaria com um faltando.
11. **O roteiro do reinício é escrito, nunca chamado por mim.** Quem dispara é o
    dono, por botão com confirmação; o portão reprova se uma automação aparecer
    no pacote.

## Defeitos meus, pegos por mim ao rodar

- **Identificador de entidade suposto em vez de medido.** O identificador nasce
  do NOME do sensor, não da chave única: "mac mini" virou `mac_mini`. O portão
  reprovou com `ENTIDADE AUSENTE` antes de qualquer outra coisa. Conserto da
  classe: comentário ao lado do sensor dizendo de onde vem o identificador, e a
  regra de medir no registro depois de implantar.
- **Escopo do plano nomeando o arquivo errado.** A contagem de sensores
  esperados mora no verificador, não no conferidor de entidades. Em vez de
  editar fora do que foi aprovado, reabri a frente com a razão escrita no plano.
