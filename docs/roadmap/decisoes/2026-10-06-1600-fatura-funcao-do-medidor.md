# Diário — fatura como função do medidor · 2026-10-06

Carimbo desta entrada: 2026-10-06 16:22 -03 (tirado por comando).

## O pedido do dono

Depois de ver o painel fechar com a conta, mudou o rumo, por escrito: *"o input
deveria ser apenas a medição do Shelly, dado que alíquotas, iluminação pública
tem fontes e critérios"*; *"tudo ser função do Shelly, mas obviamente mantendo
o ajuste manual se necessário"*; *"janela de ciclo ser dia inteiro"*; *"confira
as fontes e deixe tudo documentado e fórmulas linkadas para ficar simples para
qualquer LLM revisar"*; *"isso no futuro tem potencial para virar um App"*.

Rejeitou a primeira versão do plano por duas coisas — fontes em PDF e o
complemento de 2,08 sem fonte — e mandou procurar coisa melhor no site da
distribuidora. Procurei no conteúdo público inteiro, pela interface de dados
que fica por trás das páginas: não há. O plano voltou com a tabela do que
existe e foi aprovado.

## O que as fontes dizem (cada número refeito por comando meu)

| Parcela | Regra | Fonte | Certeza |
|---|---|---|---|
| Tarifa | 0,94793; Branca 1,73992 · 1,20499 · 0,83447 | os dois PDFs de tarifa da distribuidora, edição de setembro/2026 | lido na fonte |
| Bandeira do ciclo | média, pelos dias do ciclo, do adicional do mês de cada dia | base aberta da agência reguladora (API em JSON) + norma do rateio | adicional e mês: lido na fonte; quais dias contam: deduzido da conta (0,01885 × 27/33 = 0,01542) |
| ICMS | pela faixa do consumo: até 50 kWh isento · 51–300 → 18 % · 301+ → 24 %, sobre tudo | colunas do PDF de tarifas + lei estadual | lido na fonte |
| PIS e COFINS | mudam todo mês; não são publicados separados | só a conta | deduzido de fatura |
| Iluminação pública | parcela fixa da faixa + arredonda(coeficiente × (tarifa de referência + bandeira do mês anterior ao da leitura)); teto | lei municipal + tabelas mensais da Fazenda | lido na fonte: 61 faixas × 4 meses refeitas, zero divergência |
| Complemento de 2,08 | sem regra em fonte nenhuma | — | sem fonte; fica como ajuste manual |

A base aberta da agência traz, para a tarifa de 2026, um valor diferente do que
a distribuidora cobra (0,88056 contra 0,94793): por isso a tarifa vem do PDF da
distribuidora e não da API.

## Decisões minhas, com a razão

1. **Três peças separadas: dado, regra, tela.** O arquivo de dados
   (`tarifas/energia_light_rj.json`) tem cada número com fonte, citação, data e
   grau de certeza; a calculadora (`tarifas/fatura.py`) é a regra em código
   comum; o package só consome. Um aplicativo futuro troca a tela e reaproveita
   as outras duas. Reversível.
2. **A calculadora nasceu antes do package e reproduz as duas contas só com kWh
   e datas.** Medido às 16:13 e de novo às 16:22: 304 kWh → 471,92 (conta
   471,92); 354 kWh → 542,47 (conta 542,46).
3. **A parcela fixa da iluminação entra como a tabela a publica.** O plano
   falava em "truncar" a parcela fixa; a tabela publicada já traz o valor
   pronto, então não há truncamento no código — a contraprova planejada
   ("arredondar em vez de truncar") vira "alterar em um centavo a parcela fixa
   de uma faixa". Por isso a tolerância da iluminação na conferência é de um
   décimo de centavo, não de um centavo.
4. **Um conjunto só de ajustes manuais, valendo para o ciclo em curso e para o
   fechado.** O que o dono corrige a partir da conta que chegou é também o
   último valor conhecido para o ciclo seguinte. Custo: um ajuste de bandeira
   ou de ICMS preenchido para um ciclo continua valendo no outro até ser
   apagado. Reversível.
5. **Consumo projetado do ciclo em curso** (acréscimo necessário: o ICMS depende
   da faixa do consumo, e o preço do kWh aparece no painel de Energia desde a
   primeira hora do ciclo). Com ciclo anterior fechado: o já medido + a média
   diária do ciclo anterior × os dias que faltam. Sem ele: proporção dos dias.
   Sem isso as primeiras horas de cada ciclo seriam custeadas como isentas.
6. **Os dois sensores de parâmetros têm o mesmo texto por âncora do YAML**, em
   vez de serem gerados por ferramenta (desvio do plano, mesma garantia: um
   texto só). A ferramenta gera apenas o bloco de dados e confere os horários
   dos postos. A fórmula fica legível no próprio package.
7. **As datas de leitura das duas contas entram nos casos de conferência.** São
   necessárias ao rateio da bandeira e não identificam ninguém; nada mais da
   casa entra em arquivo versionado.

## Reprovação antes do conserto

Carimbo: 2026-10-06 16:27 -03. A cerca nova (`./tools/pacotes-arnes.sh`, Home
Assistant 2026.8.3) contra o package da manhã: **36 falhas em 6 tokens**, saída
com 3 — `ESTADO DE FABRICA`, `CAMPO NAO PERSISTE`, `FORMULA DIVERGE` (os nove
ciclos da grade e as duas projeções), `AJUSTE IGNORADO`, `CICLO NAO ZERA`
(gatilho ao meio-dia) e `MEDIDOR NAO ACOMPANHA` (horários dos postos diferentes
dos do arquivo de dados). As garantias que não mudaram continuaram íntegras
(referências, soma das fases, medidores, água, gás).

Com o package novo, às 16:35: `PACOTES OK — 13 garantias`.

## O que a cerca ganhou além do plano

- **O registro do Core entra na cerca** (`ERRO NO REGISTRO:`). A primeira
  rodada passou e eu não tinha como saber se o package novo registrava erro de
  template: o roteiro só mostrava o registro quando a rodada falhava. Agora
  erro e aviso de variável de template reprovam, antes e depois do reinício.
- **As faixas do ICMS ancoradas em fonte primária.** As duas contas reais são
  ambas de mais de 300 kWh: uma calculadora que cobrasse 24 % sempre as
  reproduziria. Entraram como casos de conferência os três preços com tributos
  que a distribuidora publica (um por faixa) e as quatro bordas.
- **Projeção do ciclo que ainda corre**, conferida com o relógio do próprio
  Home Assistant, com e sem ciclo anterior.

## Defeito antigo achado pela contraprova

`tools/embed.sh --check` saía com 1, e não com o 3 documentado, quando um bloco
embutido divergia: a linha que mostra a diferença (`diff | head`) falha por
desenho quando há diferença, e sob `pipefail` com `errexit` o roteiro morria
ali, sem conferir os blocos seguintes. Quem chama só olha "diferente de zero",
então o portão reprovava — mas pelo motivo errado e pela metade. Classe: comando
que sinaliza por código de saída, canalizado, sob `errexit`. Varri os outros
roteiros do portão: os que usam o mesmo desenho não têm `errexit`.

## A instância desta casa, antes do ajuste (só leitura, 16:44)

O portão da casa (`verifica-custos.sh`) com a regra nova **reprova**, como o
plano exigia: `HISTORICO DIVERGE` nos dois ciclos que o histórico alcança (o
custo das horas ainda no preço antigo), `PACOTE DIVERGE` (package e painel) e
`MEDIDOR DIVERGE` (o medidor do ciclo conta do meio-dia; a instância ainda não
guarda as datas do ciclo fechado).

O histórico começa no fim de agosto, no meio de um ciclo de leitura. A faixa do
ICMS desse ciclo parcial foi escolhida pela mesma regra de proporção de dias do
package (313 kWh projetados → 24 %), e o PIS/COFINS dele é o último conhecido:
é **estimativa**, e sai marcada assim no portão. A conta daquele ciclo
resolveria.

## Contraprovas (16:36–16:54)

Cada defeito plantado numa cópia do repositório; a cerca tem de sair com 3 e
imprimir o token com o trecho esperado. Oito fontes conferidas por impressão
digital antes e depois: intactas.

| Cerca | Defeitos plantados | Resultado |
|---|---|---|
| `python3 tarifas/fatura.py --confere` | rateio com 28 dias de setembro em vez de 27 · ICMS de 24 % sempre · borda de 300 kWh do lado errado · parcela fixa da iluminação um centavo acima · iluminação com a bandeira do mês da leitura · PIS e COFINS somados ao ICMS no fator · fonte sem citação · fonte sem endereço | 8/8 (`CONTA NAO REPRODUZ:`, `DADO SEM FONTE:`) |
| `./tools/embed.sh --check` | número alterado no bloco do package · arquivo de dados alterado sem regenerar · horário de posto alterado no package | 3/3 (`DIVERGE`) — na primeira tentativa 1/3 saía com o código errado: o defeito antigo do roteiro, registrado acima |
| `./tools/pacotes-arnes.sh` | 30: bandeira do mês da leitura para o ciclo todo · dias contados da leitura anterior · ICMS fixo · borda do ICMS · iluminação com a bandeira errada, sem teto e sem a média · PIS do mês errado · estimativa não avisada · faixa pelo consumo em vez do projetado · projeção sem o ciclo anterior · ciclo fechado lendo as datas do ciclo em curso · Branca com a tarifa errada · diferença para a conta com o sinal trocado · imposto em reais sobre o valor bruto · ajuste ignorado · vírgula não aceita · contagem de ajustes · fechamento ao meio-dia, só no dia seguinte, antes da data, sem zerar, sem guardar as datas, sem avançar a próxima leitura, e fechando sozinho numa instalação nova · campo com valor inicial (dois casos) · horário de posto · referência a entidade inexistente · erro de template | 30/30 |

## Outras versões e portões (16:53–17:01)

- `./tools/pacotes-arnes.sh --ha stable` (2026.9.4): `PACOTES OK — 13 garantias`.
- `./tools/gate.sh`: `RESULTADO: portão limpo`.

## Ensaio geral em réplica local (16:44–17:01)

Contêiner na versão da instância, package novo, medidores no estado em que a
casa está, estatísticas horárias reais importadas. O que o ensaio mostrou:

1. **Logo depois de o package subir, a tela fica errada** até as etapas
   rodarem: o ciclo fechado aparece sem as datas dele (bandeira zero, preço
   menor), e o ciclo em curso, que ainda conta do meio-dia, projeta 73 kWh e
   cai na faixa de 18 %. Na casa as etapas são encadeadas logo depois do
   reinício.
2. Etapas, na ordem, cada uma repetida em seguida para provar "nada a fazer":
   campos (10 comandos) · medidores de calendário (nada) · refazer o
   fechamento pela automação do package (6) · ciclo em curso (2) · custo pelo
   preço de cada ciclo (273 ajustes) · depois de a hora virar, o rastro da
   calibração (3).
3. Depois delas a réplica mostra o que a calculadora dá: ciclo fechado
   356,87 kWh × 1,344046 = 479,65; fatura 546,33; diferença para a conta
   +3,87. Ciclo em curso: preço 1,322528 (bandeira verde, ICMS de 24 % pela
   projeção de 334,6 kWh), iluminação 63,50.
4. O portão da casa contra a réplica: `CUSTOS OK`.
5. O painel Custos conferido por captura de tela na réplica: linhas da mesma
   altura, ajustes vazios em branco.

## A regra do package comparada bit a bit com a calculadora (17:05–17:12)

Antes de chamar o leitor frio, fiz por minha conta a pergunta que a grade de
nove ciclos não responde: a regra do package dá o MESMO número que a
calculadora fora dos casos que eu escolhi? O texto da regra foi avaliado no
motor de templates do Home Assistant para 600 ciclos sorteados (bordas de
todas as faixas, virada de ano, meses que a tabela não tem, datas iguais e
invertidas), com comparação exata.

- Resultado da primeira rodada: bandeira, ICMS, PIS, COFINS, fator, preço e
  iluminação **idênticos nos 600**; uma diferença, só informativa — com as
  datas invertidas o package publicava "dias: −3" e a calculadora, 0.
  Corrigido no package.
- A comparação entrou na cerca (`PACOTES OK — 14 garantias`, 17:08).
- Contraprovas: quatro defeitos que só ela pega (dias negativos; faixa do ICMS
  truncando em vez de arredondar; borda da faixa da iluminação; mês anterior
  ao primeiro da tabela) — 4/4. Duas mutações que eu tinha plantado **não**
  dispararam e foram descartadas por serem equivalentes: arredondar uma vez em
  vez de duas quando a parcela fixa já tem duas casas, e escrever
  1 − PIS − COFINS em vez de 1 − (PIS + COFINS) dão o mesmo número para estes
  dados.
- "Um mês depois", na automação: o texto dela avaliado para 791 datas seguidas
  (dois anos, um bissexto, e a virada) contra a função de referência — zero
  divergência.

## Leitura fria do diff, rodada 1: REPROVADO (17:05–17:17)

Quatro bloqueadores e oito avisos. Achado do leitor é defeito da MINHA
verificação; a classe do que faltou:

| # | O que ele achou | Classe do que eu não fiz | Conserto |
|---|---|---|---|
| 1 | "dias" negativo com as datas invertidas | — (eu já tinha achado e corrigido pela comparação bit a bit, antes de o leitor terminar) | corrigido; a comparação exata inclui "dias" |
| 2 | A cerca não lia 16 sensores calculados — entre eles o preço que o painel de Energia usa. Trocar o preço pela tarifa sem tributos passava | **Conferi o caminho do dado até o total da fatura e parei; não segui até cada sensor que a tela mostra.** E escrevi "cada número" em três textos sem contar | todos os sensores calculados entram na grade, em curso e fechado; os textos dizem o que a cerca faz |
| 3 | A grade só tinha kWh inteiros; o arredondamento não estava cercado, nem no package nem na calculadora | **Grade escolhida por mim, com números redondos** — a mesma classe das duas contas do mesmo lado da faixa | consumo com casas na grade (300,4 e 300,6), na comparação sorteada e nos casos da calculadora |
| 4 | "Um mês depois" só era conferido para o dia em que a cerca roda | **Conta que depende da data testada só com a data de hoje** | o texto da automação avaliado para 1.200 datas |
| 5 | Vírgula provada em 2 dos 8 campos | amostra em vez do conjunto | todos os campos com vírgula |
| 6 | A composição do aviso de estimativa não era exercitada | um caminho só (PIS) | ciclo anterior à tabela, cinco combinações de ajuste |
| 7 | A guarda contra alíquota de 100 % não era exercitada | guarda escrita sem teste | ajuste de ICMS = 100 na cerca |
| 8 | **Defeito de produto:** parado mais de um mês, o ciclo fecharia duas vezes e o fechado de verdade seria sobrescrito | não perguntei "e se a data que eu gravo também já passou?" | a próxima leitura vai ao primeiro mês que ainda não chegou; cenário na cerca |
| 9 | **Defeito de produto:** instalado no meio do ciclo, a projeção dividia o consumo medido pelos dias do calendário e caía na faixa errada por um ciclo e meio | **só pensei na instalação que já tem um ciclo inteiro medido — a desta casa** | o package passa a saber desde quando mede; projeção e faixa do ciclo fechado contam os dias medidos; 400 projeções sorteadas e três cenários na cerca |
| 10 | A explicação do centavo de outubro não fechava (354 × 1,34405 dá 475,79, não 475,78) | **afirmei uma causa sem fazer a conta** | o documento diz que não sei explicar; "ao centavo" virou "no máximo um centavo" |
| 11 | "As três conferências rodam no portão": só uma rodava | afirmação não conferida contra o roteiro do portão | a calculadora entrou no portão local; o documento diz onde cada uma roda |
| 12 | O que `DADO SEM FONTE` deixava passar (certeza livre, data que não é data, bloco novo sem fonte) | lista fixa de blocos | certeza de vocabulário fechado, data validada, todo bloco de parâmetro |

Fora dos itens: a citação dos horários só trazia a ponta. Baixei de novo a
resolução (17:19) e a citação agora inclui o parágrafo do posto intermediário
("duas horas imediatamente posterior ao posto (horário) ponta").

Escalado pelo leitor ao dono, e é do dono: as duas contas reais (datas, kWh,
totais) num repositório público. O plano aprovado as previa "só com os
números, sem identificação"; nada foi empurrado para o remoto.

Depois dos consertos (17:28): `PACOTES OK — 14 garantias`, com a grade em onze
ciclos e todos os sensores.
