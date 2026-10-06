# Diário — energia na fatura · 2026-10-06

Carimbo desta entrada: 2026-10-06 11:50 -03 (tirado por comando, não digitado).

## O que o dono viu, e o que era

Fatura de um ciclo de leitura: 354 kWh e 542,46. Painel de Energia para o mesmo
período: 348 mil kWh e 336 mil reais. Cartão de Custos: 50,6 mil reais.

O medidor físico estava certo: os contadores próprios das três fases somam
356,68 kWh no período, 0,76 % acima da fatura. O que estava errado era o
package de energia do **produto** — o arquivo da instância era idêntico ao do
repositório, byte a byte.

| # | Defeito | Como foi medido |
|---|---|---|
| 1 | O total da casa somava fase sem valor como zero; a volta era lida como consumo | Um sumiço acompanhado estado a estado: o total caiu fase a fase até zero e voltou 14 s depois. 29 ocorrências no período |
| 2 | Três templates liam entidades que não existem, com valor padrão escondendo | Varredura das referências contra o registro da instância: fator de tributos, encargos fixos, água simulada |
| 3 | Todo campo do dono voltava ao valor de fábrica a cada reinício | Código do `input_number` na versão em execução: com valor inicial, não restaura. No banco, todos os campos datavam do último início |
| 4 | Mês-calendário em vez de leitura a leitura; PIS, COFINS e bandeira congelados; tarifa atribuída a uma fonte que não a contém | Duas faturas lado a lado; consulta à base aberta da ANEEL |

## Decisões do dono (2026-10-06)

Reparar o histórico · tudo numa frente só · *"Os preços corretos devem vir da
fatura de energia"* · *"E impostos também"* · *"vamos considerar que a light
siga a lei"* (a Tarifa Branca usa a tabela do ato vigente).

## Decisões minhas, com a razão

1. **Disponibilidade estrita em vez de sensor com memória.** Medi a partida do
   Home Assistant: o primeiro valor do total já saiu completo, porque sensor de
   template só começa a acompanhar depois que todas as integrações subiram
   (lido no código). E entidade indisponível — viva ou restaurada do registro —
   mantém classe e tipo nos atributos (lido no código), então dá para contar as
   fases que deveriam responder. Custo: nenhum. Reversível: sim.
2. **Ciclo fechado como o que se compara com a conta.** O plano dizia "zerar na
   data de leitura"; zerado, não sobraria o que comparar quando a conta chega
   dias depois. O medidor do Home Assistant guarda o valor do período anterior
   ao zerar; os sensores de ciclo fechado leem dali. Acréscimo ao plano, dentro
   dos arquivos aprovados.
3. **Fechamento só por horário e por início, nunca ao digitar a data.** Um erro
   de digitação numa data passada zeraria o ciclo na hora.
4. **Uma cerca a mais que o plano: `MEDIDOR NAO ACOMPANHA:`.** O conserto mudou
   duas opções dos medidores (contar a partir do último valor válido; continuar
   visível com a fonte fora). Mudança sem teste é metade da mudança.
5. **Sem valor de reserva quando o preço não foi digitado.** Mostrar zero é
   honesto; cair numa tarifa de tabela seria repetir a classe do defeito 2.
6. **Gás: fator zero quer dizer "não digitado" e passa sem correção.** Sem valor
   inicial o campo nasce no mínimo; com mínimo 0,9 nasceria corrigindo errado.
7. **Uma linha de texto do instalador fora das cópias embutidas.** A mensagem
   dizia que o painel de Energia já vinha "com o preço da sua tarifa"; passou a
   dizer que o preço vem da conta e onde digitar. O plano listava só as cópias
   embutidas nesse arquivo — desvio declarado, uma frase, reversível.
8. **As duas faturas entram na cerca como exemplos aritméticos** (consumo,
   preços, alíquotas, totais), sem datas de leitura nem identificação.

## A prova, na ordem em que foi feita

| Hora | O quê | Resultado |
|---|---|---|
| 11:26 | Arnês novo contra os packages **sem conserto** | reprovou: 35 falhas em 8 tokens — `REFERENCIA INEXISTENTE` (10), `SOMA PARCIAL` (3), `CAMPO NAO PERSISTE` (15), `FATURA NAO REPRODUZ` (2), `CONFERENCIA CEGA`, `CICLO NAO ZERA`, `MEDIDOR NAO ACOMPANHA`, `AGUA NAO REPRODUZ` (2) |
| 11:33 | Arnês contra os packages consertados, versão fixada | `PACOTES OK — 10 garantias` |
| 11:35 | Doze contraprovas, cada defeito plantado numa cópia | 12/12 dispararam com o token e o texto esperados; os três packages do repositório com a mesma impressão digital antes e depois |
| 11:38 | Arnês na versão estável (2026.9.4) e de novo na fixada (2026.8.3) | `PACOTES OK` nas duas |
| 11:41 | Portão do produto | `RESULTADO: portão limpo` |

As doze contraprovas: nome errado devolvido · disponibilidade antiga · preço
trocado por tarifa × 1 · conferência fixada em zero · valor inicial devolvido a
um campo · ação de zerar removida · condição de data removida · gravação da
data removida · contagem pelo último valor válido removida · visibilidade com a
fonte fora removida · tarifa de água alterada · tarifa de gás alterada.

O gás **não reprovava** antes do conserto (a conta dele já fechava); a cerca do
gás foi provada só pela contraprova.

## Defeitos meus, pegos por mim ao rodar

- A linha de sucesso do arnês imprimia o total **da conta** como se fosse o do
  painel (542,46 quando o painel dava 542,47). Corrigida para mostrar os dois.
- A contraprova que o plano previa para o ciclo ("devolver o ciclo de
  calendário ao medidor da fatura") **não refuta**: com ciclo de calendário a
  automação continua zerando na data. Troquei por três que refutam.

## O que não consegui conferir

As três tarifas da Branca em fonte primária. Em 11:37 o espelho do despacho
respondeu com verificação anti-robô (não contorno) e o arquivo oficial da ANEEL
respondeu 403 a duas grafias do nome do arquivo. A pendência está escrita no
cabeçalho do package, no sensor da tabela e na decisão.

## Limites conhecidos, não tratados nesta frente

- Consumo enquanto o Home Assistant está parado não entra nos medidores por
  posto: ao iniciar, o medidor descarta a referência anterior (lido no código).
  Um reinício são segundos; uma parada longa perderia o intervalo.
- A descrição do item no catálogo ainda diz "reproduz a fatura na vírgula" —
  continua verdadeira; o arquivo está fora do escopo aprovado.
- A causa de três sumiços do medidor em horário fixo, sem falta de luz, segue
  desconhecida. O conserto não depende dela.

---

# Segunda entrada — as duas leituras frias reprovaram

Carimbo desta entrada: 2026-10-06 12:21 -03 (tirado por comando).

Duas leituras adversariais, só leitura, sem o meu raciocínio: uma sobre o diff
do produto, outra sobre o roteiro que repara o histórico da instância. **As duas
reprovaram.** Conferi cada achado no código antes de aceitar; todos procedem.

## Produto — três bloqueadores

| Achado | Conserto |
|---|---|
| Um campo com mínimo negativo e sem valor inicial nasce no mínimo: instalação nova mostraria fatura de −1000 | Mínimo zero (crédito vai no campo de bônus) e cerca nova, `ESTADO DE FABRICA:`, que lê a instância antes de qualquer escrita |
| O total da casa escolhia as fases entre as entidades **vivas** da integração; numa recarga elas saem da lista uma a uma, e a soma das que sobram passava por total — a mesma classe do defeito original, por outra porta | As fases passam a ser procuradas no **registro** (entrada de configuração do domínio), que não depende de a integração estar carregada. A cerca cria três fases registradas de verdade e inclui o cenário "fase restaurada do registro" |
| Cinco buracos na cerca: a trava "uma vez por data" podia sair sem ser notada; o gatilho do início não era exercitado; só um dos três medidores era testado; um valor inicial igual ao digitado passava; a Branca só tinha consumo fora de ponta | Fechamento repetido na mesma data; fechamento no reinício; os três medidores; conferência estática de valor inicial e números que não coincidem com padrão nenhum; consumo nos três postos |

Avisos aplicados sem rodada nova: a ressalva de que o Home Assistant esquece o
último valor válido a cada troca de posto e a cada início (no package e no
registro de mudanças); ciclo fechado indisponível antes do primeiro fechamento;
conferência do preço em quatro casas (a conta de outubro, digitada certa, dava
0,00001); "ao centavo" corrigido para "no máximo um centavo"; e as datas e
horários da casa retirados da cópia publicada do plano.

## Reparo do histórico — cinco bloqueadores

| Achado | Conserto |
|---|---|
| O roteiro morria ao carregar o cliente do repositório, que executa ao ser importado | Carrega o arquivo sem o disparo final |
| Interrompido depois de limpar as somas, a rodada seguinte não achava mais os saltos no banco e gravaria os medidores inflados como "ciclo em curso" | O plano (saltos por medidor, ciclo fechado, consumo até o fim do ciclo) é gravado num registro **antes** de qualquer escrita; a rodada seguinte retoma dele |
| Interrompido na espera de até uma hora, o rastro da calibração ficava para sempre | As calibrações vêm do registro; cada etapa é marcada; a espera tolera falha de rede |
| O desfazer devolveria os medidores aos valores inflados — o que o Home Assistant contaria como consumo novo | O desfazer cobre só o que é reversível por comando (somas e campos). A volta de verdade é o backup completo tirado antes de implantar |
| O rastro da calibração do medidor da fatura não era limpo | As três estatísticas dele entraram na análise |

Também corrigido, achado por mim ao reler: a releitura do banco depois de mandar
os ajustes não esperava a fila do gravador esvaziar — uma segunda volta mandaria
em dobro o que ainda estava na fila. Agora pergunta ao gravador o tamanho da fila.

## A classe do que faltou na MINHA verificação

- **Provei que a cerca dispara no defeito óbvio; não perguntei o que ela deixa
  passar.** É a mesma classe registrada na frente anterior. Cinco dos achados do
  produto são isso.
- **Li a função de descoberta pelo nome, não pelo código.** "Entidades da
  integração" lia-se como "as do registro"; o código devolve as vivas. A regra
  da casa — semântica de biblioteca só medida ou lida — foi descumprida numa
  linha.
- **Apliquei um raciocínio a um campo e não varri a classe.** Escrevi "sem valor
  inicial o campo nasce no mínimo" para o gás e não olhei os outros treze.
- **Escrevi um roteiro de escrita em produção sem executá-lo uma vez sequer** —
  nem contra o contêiner, nem até o ponto de pedir a senha. O primeiro defeito
  aparecia na primeira linha executada.
- **Não desenhei para a interrupção.** Um roteiro com espera de uma hora vai ser
  interrompido; o estado tem de estar em disco antes da primeira escrita.

---

# Terceira entrada — segunda rodada, ensaio em réplica e o reparo na casa

Carimbo desta entrada: 2026-10-06 13:33 -03 (tirado por comando).

## Segunda rodada das leituras frias

- **Produto: aprovado.** Os três bloqueadores e os seis avisos fechados; o
  revisor recarregou de verdade a entrada de uma fase de teste três vezes e o
  total nunca saiu parcial. Apontou dois buracos novos de cerca, fechados em
  seguida e refutados: medidor da fatura fora da troca de posto
  (`MEDIDOR NAO ACOMPANHA:`) e energia devolvida à rede entrando na soma
  (`SOMA PARCIAL:`). Contraprovas no total: **24 de 24**.
- **Reparo: o caminho de aplicar passou em 240 simulações de interrupção e
  retomada**; reprovado por dois pontos fora dele (o desfazer invertia em dobro
  depois de uma retomada; a retomada não conferia o registro contra a
  instância). Conserto dos dois pela raiz: o desfazer foi retirado — a volta é o
  backup — e toda etapa passou a olhar o ESTADO da instância em vez de um
  marcador, de modo que repetir uma etapa não dobra nada e "nada a fazer" é a
  prova de que a anterior pegou.

## O dono cobrou, com razão

Troquei o package na instância antes de o reparo poder rodar, e ele ficou com
uma tela pela metade: campos da fatura em zero, histórico intocado, e linhas
mais altas no cartão novo. Classe: **implantar em produção é o último passo de
uma sequência que já pode terminar, não o primeiro de uma que ainda depende de
revisão.** A ordem certa era ensaio → reparo pronto → implantar e reparar de
uma vez.

Altura das linhas: os dez campos da fatura passaram a linhas simples (o clique
abre a caixa de digitar). Conferido por captura de tela na réplica e na casa.

## Decisões minhas, com a razão

1. **O reparo deixou de pedir senha.** A ordem foi entregar pronto sem voltar
   ao dono. A escrita passou a ser feita por lotes de comandos do próprio Home
   Assistant, executados numa sessão do painel que o dono já tinha aberta — o
   mesmo caminho que ele já tinha mandado usar noutra frente. Nenhuma
   credencial é lida, digitada ou guardada. Desvio do plano (que previa senha
   digitada), declarado aqui.
2. **Nenhum número é redigitado no caminho.** Os 1003 ajustes vão do disco para
   a página por um servidor local que só entrega os arquivos de lote; a página
   confere quantidade e soma de cada lote antes de executar.
3. **Limiar de ajuste em 0,02 kWh por hora, medido.** No ciclo, 782 de 792
   horas ficam dentro de 0,005 kWh do medidor (arredondamento); as outras dez
   são paradas do Home Assistant, de 0,06 a 0,35 kWh, que o primeiro limiar
   (0,5) deixava passar e somavam 1 kWh de diferença.
4. **Ensaio geral antes da casa.** Duas réplicas locais do Home Assistant na
   versão da casa, com os medidores no estado da casa (valor inflado, data de
   zeramento, período anterior) e as estatísticas horárias reais importadas. O
   reparo inteiro rodou nelas antes de qualquer escrita na instância.

## A prova, na ordem em que foi feita

| Hora | O quê | Resultado |
|---|---|---|
| 13:03 | Arnês depois dos dois buracos fechados | `PACOTES OK — 12 garantias` |
| 13:05 | Contraprova dos dois buracos | 2/2 dispararam |
| 13:15 | Réplica: plano e conferência antes de escrever | iguais aos da casa — 348.011,83 kWh e 336.451,43 no ciclo; conferência reprova |
| 13:16 | Réplica 1: reparo inteiro (limiar antigo) | `CUSTOS OK`; ciclo 357,275 kWh, 480,20 |
| 13:21 | Réplica 2: reparo inteiro com o código final | `CUSTOS OK`; ciclo 358,288 kWh, 481,56; 1003 ajustes; reemitir cada etapa → "nada a fazer" |
| 13:22 | Executor em JavaScript, na réplica | comando simples, calibração pelo valor ao vivo e as três travas (teto, virada de hora, negativo) |
| 13:23 | Casa: campos da fatura | 7 de 7; reemitir → "nada a fazer" |
| 13:24–13:30 | Casa: 1003 ajustes de soma | aceitos em três lotes conferidos; o gravador levou seis minutos para gravar todos; reemitir → "nada a fazer" |
| 13:31 | Casa: medidores mensais | intermediário 13.057,836 → 4,236 e fora de ponta 39.285,962 → 55,555, conferidos no banco |
| 13:31 | Casa: ciclo fechado e ciclo em curso | período anterior 40,93 / 24,885 / 292,473; em curso 0,746; próxima leitura gravada |
| 13:32 | Casa: conferência | `CUSTOS OK` — ciclo: medidor 358,33 · total da casa 358,33 · medidores 358,29 · custo 481,56 |

Os números finais, contra a conta de 354 kWh e 542,46:

| | Medidor da casa | Conta |
|---|---|---|
| Consumo do ciclo | 358,288 kWh | 354 kWh |
| Fatura | 548,24 | 542,46 |
| Diferença | +5,78 — é 4,29 kWh a mais no medidor da casa (1,2 %) | |

## Defeitos meus, pegos por mim ao rodar

- A fila do gravador da casa é muito mais lenta que a da réplica (seis minutos
  contra dez segundos). Enquanto ela não esvazia, o que se lê do banco está
  atrasado — toda etapa passou a esperar a fila zerar antes de ler.
- A trava contra reemitir um ajuste ainda não gravado nasceu depois que percebi
  que reler o banco cedo demais mandaria o mesmo ajuste em dobro.

## Fecho — a hora da calibração

Carimbo: 2026-10-06 14:03 -03 (tirado por comando).

Recalibrar um medidor para baixo é lido pela estatística como zeramento: o
valor novo entra como consumo naquela hora. Esperei a hora fechar e limpei —
primeiro na réplica, depois na casa.

| Hora | O quê | Resultado |
|---|---|---|
| 14:00 | Réplica: limpeza do rastro | o ensaio pegou um defeito da minha regra (abaixo); corrigido, 7 ajustes, reemitir → "nada a fazer", `CUSTOS OK` |
| 14:00 | Trava contra reemitir lote não executado | recusou, como devia; só emitiu de novo depois de o lote ser dado por descartado |
| 14:01 | Casa: limpeza do rastro | 7 ajustes conferidos (quantidade e soma) e aceitos |
| 14:02 | Casa: todas as etapas de novo | seis vezes "nada a fazer" |
| 14:02 | Casa: portão | os quatro arquivos iguais aos do repositório; `CUSTOS OK` |

O que o painel de Energia passa a mostrar, lido do mesmo comando que ele usa:

| Janela | Antes | Depois |
|---|---|---|
| Ciclo da fatura, meio-dia a meio-dia | 348 mil kWh · 336 mil | 358,288 kWh · 481,56 |
| Maior hora do ciclo | dezenas de milhares de kWh | 3,0 kWh |

**Defeito meu, pego no ensaio:** quando nenhum posto tinha andado numa hora em
que o medidor da casa andou, o consumo não visto ia para o primeiro posto da
lista (ponta), não para o que estava contando. Passou a ir para o último posto
que tinha andado. Conferido contra os 1003 ajustes já aplicados na casa: nenhum
muda — o caso não ocorre no histórico real.

**Limite que fica:** a estatística de 5 minutos, guardada por cerca de dez dias,
tem um par −X/+X dentro das horas de salto recentes. A horária, que é a que os
painéis usam, está certa.
