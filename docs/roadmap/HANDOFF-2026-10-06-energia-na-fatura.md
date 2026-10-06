# HANDOFF — a energia volta a fechar com a conta · 2026-10-06

> **SUPERADO por `HANDOFF-2026-10-06-fatura-funcao-do-medidor.md`** (2026-10-06,
> tarde): o preço e os impostos deixaram de ser digitados da conta e passaram a
> ser calculados do consumo. O que está abaixo é o registro da manhã.
>
> Supersede `HANDOFF-2026-09-17-painel-reserva.md`.

## 0. ESTADO — confira no git, não neste parágrafo

- Versão do produto **inalterada** (`HAOS_INSTALL_VERSION`): as mudanças estão
  em `## [Unreleased]` do `CHANGELOG.md`. Subir versão, publicar e empurrar
  para o remoto: **só sob ordem**.
- Esta frente **tocou o produto público**: os três packages de custo, o painel
  Custos, as cópias embutidas no instalador, uma mensagem do instalador, o CI e
  uma cerca nova.
- A parte da instância desta casa (implantação e reparo do histórico) vive em
  `inventario/custos/`, fora do versionamento. **Está concluída**: packages e
  painel implantados, histórico reparado, medidores recalibrados, ciclo da
  fatura fechado, portão da casa em `CUSTOS OK` (diário, terceira entrada).

## 1. O que a frente entregou

O dono comparou o painel com uma fatura real e os números estavam fora por três
ordens de grandeza. O medidor estava certo; o package de energia, não.

| Defeito | Conserto |
|---|---|
| O total da casa somava fase sem resposta como zero; cada sumiço do medidor somava a vida inteira dele de novo | O total só existe com todas as fases respondendo, e as fases são procuradas no registro de entidades (a lista de entidades vivas perde as fases uma a uma numa recarga da integração); os medidores contam a partir do último valor válido |
| Três templates liam entidades inexistentes, com valor padrão escondendo | Nomes corrigidos; cerca que confere toda referência contra uma instância de verdade |
| Todo campo digitado voltava ao valor de fábrica a cada reinício | Nenhum campo do usuário tem valor inicial |
| Mês-calendário, impostos e bandeira congelados, tarifa de fonte errada | Preço e impostos vêm da fatura; medidor próprio do ciclo de leitura; ciclo fechado comparado com a conta |

A decisão de desenho e as fontes estão em
[2026-10-06-1200-fonte-da-tarifa-de-energia.md](../2026-10-06-1200-fonte-da-tarifa-de-energia.md).

## 2. As provas (comandos rodados no ato)

| Portão | Resultado |
|---|---|
| `./tools/pacotes-arnes.sh` contra os packages **antes** do conserto (1ª versão da cerca) | reprovou: 35 falhas em 8 tokens |
| Duas leituras frias adversariais sobre o diff e sobre o reparo, duas rodadas | 1ª rodada **reprovou** (3 bloqueadores no produto, 5 no reparo); 2ª rodada **aprovou o produto** e apontou dois buracos de cerca, fechados em seguida (diário) |
| `./tools/pacotes-arnes.sh`, versão fixada (2026.8.3) e estável (2026.9.4), cerca reescrita | `PACOTES OK — 12 garantias` nas duas |
| 24 defeitos plantados, um por vez, em cópia do repositório | 24/24 dispararam o token e o texto esperados; fontes com a mesma impressão digital antes e depois |
| `./tools/embed.sh --check` | os oito blocos embutidos idênticos às fontes |
| `./tools/gate.sh` | `RESULTADO: portão limpo` |

O detalhe, com hora, está em
[decisoes/2026-10-06-1200-energia-na-fatura.md](decisoes/2026-10-06-1200-energia-na-fatura.md).

## 3. Decisões que eu tomei

| Decisão | Custo | Reversível |
|---|---|---|
| Disponibilidade estrita do total, em vez de sensor com memória | nenhum | sim |
| Ciclo fechado (o período anterior que o medidor guarda ao zerar) como o que se compara com a conta — acréscimo ao plano | três sensores a mais | sim |
| O ciclo fecha por horário e por início do Home Assistant, nunca ao digitar a data | fecha até um dia depois se o HA estiver parado ao meio-dia | sim |
| Sem valor de reserva quando o preço não foi digitado: mostra zero | instalação nova vê custo zero até digitar a conta | sim |
| Uma cerca além do plano (medidor com a fonte indo e voltando) | ~5 s por rodada | sim |
| O reparo do histórico foi escrito por lotes de comandos do Home Assistant, executados numa sessão do painel já aberta, em vez de pedir senha — desvio do plano | nenhuma credencial lida ou guardada; depende de haver sessão aberta | a volta é o backup completo |
| Ensaio geral em réplica local com os dados reais antes de escrever na instância | ~1 h | — |
| Uma frase do instalador alterada fora das cópias embutidas | desvio declarado do plano | sim |
| Fases procuradas iterando os sensores e consultando o registro, em vez da lista da integração | o template é reavaliado a cada mudança de sensor (no máximo uma vez por segundo) | sim |
| "Complementos" deixa de aceitar valor negativo | quem tinha crédito ali passa a usar o campo de bônus | sim |
| Ciclo fechado indisponível até o primeiro fechamento | o cartão mostra "indisponível" numa instalação nova | sim |

## 4. Dívidas declaradas

- **As três tarifas da Branca não foram conferidas em fonte primária.** O
  espelho exige verificação anti-robô e o arquivo oficial respondeu 403. Está
  escrito no package, no sensor da tabela e na decisão.
- **Consumo com o Home Assistant parado não entra nos medidores por posto**
  (o medidor descarta a referência anterior ao iniciar). Segundos num reinício;
  o intervalo inteiro numa parada longa.
- **O caso "hoje, antes ou depois do meio-dia" do fechamento do ciclo não é
  exercitado pela cerca** — depende do relógio. Data passada, data futura, a
  mesma data duas vezes e o fechamento no início do Home Assistant são.
- **A cerca não tem um Shelly.** As fases de teste são sensores registrados da
  integração `template`, e o domínio procurado é trocado antes de o texto ir ao
  motor. Prova-se a descoberta pelo registro, a regra e a soma; não a sequência
  real de uma recarga da integração.
- **Fase desabilitada pelo usuário sai da soma** — some do estado, e o total
  passa a ser o das que sobraram.
- **O gatilho do meio-dia só é conferido no arquivo**, não disparado.
- **Entidade de energia órfã no registro prende o total.** Uma entidade que a
  integração deixou de fornecer mas continua registrada aparece sem valor para
  sempre e segura o total indisponível. Falha fechada; o conserto é remover a
  entidade órfã.
- **O Home Assistant pode registrar "laço de template" no total da casa** numa
  rajada de mudanças (o total é um sensor e passa a acompanhar o próprio
  domínio). Medido numa rajada artificial: duas ocorrências, número final
  certo. Numa instância real com o medidor, 16 minutos de registro: nenhuma.

## 5. Achados não tratados

| Achado | Severidade | Conserto |
|---|---|---|
| A descrição do item de energia no catálogo ainda fala em "reproduz a fatura na vírgula" | baixa — continua verdadeira | uma linha em `catalog/catalog.bash`, fora do escopo aprovado desta frente |
| Três sumiços do medidor em horário fixo, sem falta de luz | média — não soma mais nada, mas a causa é desconhecida | medir na próxima ocorrência; não depende do instalador |
| O instalador não avisa quem ATUALIZA que precisa digitar os campos da fatura | média | o `CHANGELOG.md` avisa; um aviso na própria execução seria melhor |
| O package de gás mostra a tarifa mínima (7 m³) quando nada foi digitado | baixa — é como a tarifa funciona, mas numa instalação nova parece número inventado | decidir se zero digitado deve mostrar zero |

## 6. O que falta

- Bancada do dono: comparar o painel Custos e o painel de Energia com a conta.
  O que ele deve ver: ciclo fechado de 358,3 kWh e 548,24 pelo medidor da casa,
  contra 354 kWh e 542,46 da conta (o medidor da casa marca 1,2 % a mais).
- A cada conta nova: digitar os dez campos e a data da próxima leitura.
- Empurrar para o remoto, subir versão, publicar: **só sob ordem**.

## 7. Lições que custaram defeito

- **Valor padrão em template esconde referência quebrada.** `float(1)` atrás de
  um nome errado não dá erro: dá número errado, para sempre. A cerca tem de
  conferir a referência, não o resultado.
- **O identificador de um sensor de template nasce do nome, não da chave única.**
- **"Sem resposta" não é zero.** Somar indisponível como zero num contador
  acumulado transforma cada falha de comunicação em consumo.
- **Campo com valor inicial não guarda o que o usuário digita.**
- **Fonte citada tem de conter o número.** O cabeçalho atribuía a tabela aos
  dados abertos; eles nunca a contiveram.
- **Um portão que só confere que o arquivo foi escrito não diz nada sobre o que
  o arquivo faz.**
- **"Entidades da integração" quer dizer as VIVAS.** A função de template que
  lista por domínio não consulta o registro: descarregada a integração, a lista
  encolhe. Quem precisa das que *deveriam* existir pergunta ao registro.
- **Campo sem valor inicial nasce no mínimo.** Mínimo negativo é número
  inventado numa instalação nova.
- **Provar que a cerca dispara no defeito óbvio não é perguntar o que ela deixa
  passar.** Segunda frente seguida em que a leitura fria achou isso.
