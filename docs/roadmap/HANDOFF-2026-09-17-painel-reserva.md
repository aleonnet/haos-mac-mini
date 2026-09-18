# HANDOFF — o painel dos no-breaks, e a caçada que veio junto · 2026-09-17

> **LEIA-ME PRIMEIRO.** Porta de entrada da frente do instalador. Supersede
> `HANDOFF-2026-08-25-a-algema-do-apfs.md`.

## 0. ESTADO — confira no git, não neste parágrafo

- Versão do produto **inalterada**: esta frente **não tocou o produto público**
  (instalador, catálogo, portão, README). O que ela entrega vive fora do
  versionamento, em `inventario/reserva/` (ignorado pelo git), porque cita
  equipamentos e identificadores desta casa.
- Instância no ar, com um painel novo de no-breaks entregue e verificado.

## 1. O que a frente entregou

Um painel de reserva de energia para os dois no-breaks lidos por NUT, com o que
cada um está aguentando, quanto tempo resta, o consumo por saída, histórico de
24 h e uma aba de diagnóstico. Fora dele: nada de interruptor de tomada, que
depende de versão futura do serviço que publica os dados — **sem data**.

Método, na ordem: prancha navegável aprovada pelo dono → curadoria de sensores
pelo utilitário do próprio repositório (`entity-enable`, que respeita o que o
dono desabilitou à mão) → painel e roteiros escritos → portão próprio →
implantação com volta atrás.

## 2. As provas (comandos rodados no ato)

| Portão | Resultado |
|---|---|
| Painel conferido contra o registro da instância | `RESERVA OK — 27 entidades conferidas` |
| Entidade inexistente plantada | `ENTIDADE AUSENTE:` — pegou |
| YAML quebrado plantado | `YAML INVALIDO` — pegou |
| Entidade desabilitada plantada | `ENTIDADE DESABILITADA:` — pegou |
| Implantação com defeito proposital | `CHECK-REPROVOU` seguido de `RESTAURADO sha256 confere` — o arquivo voltou com a mesma impressão digital |
| Implantação real | `core check: passou` · `IMPLANTADO` |
| **Correção da autonomia** (16:17) — conferência nova, escrita ANTES do conserto | reprovou 6× `AUTONOMIA ILEGIVEL:` e `FORMULA ILEGIVEL:`; depois do conserto, `RESERVA OK — 31 entidade(s) conferida(s)` |

Antes da curadoria o portão reprovava com 10 falhas nominais; depois, verde.
É o mesmo comando nos dois momentos.

## 3. A caçada que apareceu no meio (e valeu mais que o painel)

O dono reiniciou o Mac mini e nada subiu. Três achados, todos medidos:

1. **A máquina hospedeira não fazia início de sessão automático.** Máquina
   virtual, rede privada e cofre nasciam **no login** — 27 minutos depois do
   boot, no caso. Corrigido pelo dono: FileVault desligado e sessão automática.
2. **O vigia do disco estava morto havia semanas**, falhando em laço (61
   tentativas, saída 69) porque uma atualização do sistema reapresentou o termo
   de licença das ferramentas de desenvolvedor e o interpretador que ele usa
   passou a recusar execução. Corrigido pelo dono aceitando o termo; o vigia
   voltou e está algemando o disco vivo (inode do descritor = inode do arquivo).
3. **A rede privada da casa não sobe antes do login** nessa variante — é
   limitação documentada pelo fabricante, e a variante de linha de comando é a
   única que roda sem sessão.

## 4. Dívidas que isso criou no PRODUTO (não entram nesta frente)

1. 🔴 **O diagnóstico do instalador diz que o vigia está bem quando ele está
   morto**: confere se o serviço está *carregado*, e ele estava — carregado e
   falhando. Precisa olhar o último código de saída e a contagem de reinícios,
   com cerca que reprove essa condição.
2. 🟡 O vigia depende do interpretador do sistema, que pode ser bloqueado por
   termo de licença após atualização. Avaliar dependência mais robusta.
3. 🟡 Registrar no produto que a máquina hospedeira precisa de sessão
   automática para que tudo suba sem gente.

## 4b. A correção da autonomia (mesmo dia, depois da entrega)

O painel entregou a informação mais valiosa dele — quanto tempo a casa aguenta —
em **segundos crus**, contra a prancha aprovada, que mostrava horas e minutos.
Defeito meu, de apresentação, visível na primeira tela.

- **Causa medida:** a integração declara a autonomia em segundos, com classe de
  duração e sem precisão de exibição sugerida; o frontend mostra o que recebe.
- **Conserto:** quatro sensores derivados no pacote da frente — dois de texto
  (`41 h 09 min`), que vão nos cartões e na etiqueta do topo, e dois numéricos
  em horas, que é o que o gráfico de 24 h sabe desenhar. O número cru desceu
  para a aba de Diagnóstico.
- **Recusado, com razão escrita:** converter a unidade da entidade no registro.
  Renderia número decimal em horas, não leitura, e moraria no armazenamento
  interno da instância, fora de qualquer arquivo que viaje com o repositório.
- **Cercas novas, ambas refutadas antes de existir conserto:** a conferência
  reprova segundo cru em qualquer aba que não seja a de diagnóstico, e o teste
  da fórmula roda no motor de template **do próprio Home Assistant**, seis casos
  por sensor.

Dois fatos do mesmo dia, medidos e alheios à frente: a máquina hospedeira
reiniciou às 15:57 (desligamento ordenado, com relatório de travamento no
desligamento) e o Core se atualizou sozinho para 2026.9.2. E um erro meu de
diagnóstico, registrado no diário: tratei a instância como fora do ar porque
supus a porta 8123 — ela serve na porta 80, e nunca caiu.

## 4c. A fase dos protegidos, entregue no mesmo dia

As duas entradas da integração foram criadas: uma por mim, pelo navegador com a
sessão do dono, e a outra por ele — **criar entrada de integração é ato do
aplicativo, não do disco**, e a credencial é dele, sempre.

O que o painel ganhou: por aparelho protegido, a carga do no-break que o segura
e **quanto tempo ele aguenta, em horas e minutos**; e um botão que reinicia o
roteador, **com confirmação**. Desligar não entra — desligar a máquina
hospedeira apagaria o próprio Home Assistant e desligar o roteador derrubaria a
rede sem volta automática; o aviso está escrito na tela, não só aqui.

Curadoria: a autonomia dos dois protegidos nasce **desabilitada pela
integração** e foi habilitada pela interface; os limiares continuam desligados
de propósito.

| Prova | Resultado |
|---|---|
| Portão da fase 2 | `RESERVA OK — 41 entidade(s) conferida(s), fase 2` |
| Aparelho inexistente plantado | `ENTIDADE AUSENTE:` — pegou |
| Confirmação removida do botão | `SEM CONFIRMACAO` — pegou |
| Automação plantada no pacote | `CHAMADA AUTOMATICA` — pegou |
| Um dos quatro sensores de texto apagado | `FORMULA ILEGIVEL: … esperado 4` — pegou |
| Restauro das injeções | as duas impressões digitais conferem |

Defeito meu, pego pelo portão antes de qualquer outra coisa: **o identificador
de uma entidade de template nasce do NOME, não da chave única** — o espaço do
nome vira sublinhado. Eu supus em vez de medir, o portão reprovou com
`ENTIDADE AUSENTE`, e a armadilha ficou escrita num comentário ao lado do
sensor.

## 5. O que falta nesta frente

- Discussão adiada pelo dono para quando as duas frentes fecharem: oferecer
  reinício para máquina genérica por SSH no serviço que publica os dados.
- Ligar e desligar tomada dos no-breaks: o serviço que publica os dados declarou
  isso **fora** da versão atual, por escrito. Sem data.

## 6. Onde está o que é desta casa

`inventario/reserva/` (fora do versionamento): prancha, painel, roteiros,
portão, implantador e curadoria. O handover para colegas agentes segue na raiz
do monorepo, também fora deste repositório.
