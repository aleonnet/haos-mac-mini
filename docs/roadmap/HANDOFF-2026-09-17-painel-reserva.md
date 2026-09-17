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

## 5. O que falta nesta frente

- **Fase dos protegidos**: o dono precisa acrescentar duas entradas da
  integração NUT (a máquina hospedeira e o roteador), que o servidor já publica.
  Feito isso, entra a seção com carga, autonomia e o botão de reiniciar o
  roteador, com confirmação. Comando de conferência: `--fase 2`.
- Discussão adiada pelo dono para quando as duas frentes fecharem: oferecer
  reinício para máquina genérica por SSH no serviço que publica os dados.

## 6. Onde está o que é desta casa

`inventario/reserva/` (fora do versionamento): prancha, painel, roteiros,
portão, implantador e curadoria. O handover para colegas agentes segue na raiz
do monorepo, também fora deste repositório.
