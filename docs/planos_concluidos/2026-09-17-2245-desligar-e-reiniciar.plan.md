<!-- Cópia higienizada do plano APROVADO. O repositório é público. -->

# Desligar e reiniciar, por ordem do dono

project: ~/Development/ABHOME-infra/ABHOME-haos-macmini
status: aceito

## Context

Eu tirei o botão de desligar do painel e, pior, **escrevi a minha decisão como
regra na tela do dono** ("Desligar não entra aqui, de propósito"). O painel é
dele. Ele leu, discordou e mandou incluir.

O que o servidor publica, **medido no ato às 22:38**: a máquina hospedeira
oferece **só desligar**; o roteador oferece **desligar e reiniciar**. Reiniciar a
máquina hospedeira **não existe** por este caminho — a ponte só oferece reinício
para a família do roteador. Então saem três botões, não quatro, e a ausência do
quarto é limite medido, não escolha minha.

Resultado pretendido: o painel oferece tudo o que o servidor publica, cada ordem
sob confirmação que diz a consequência em uma frase — e o texto na tela passa a
informar o que existe, em vez de justificar o que eu decidi.

## Risk band

**standard** para o que eu faço (escrever YAML e implantar pelo caminho já
provado). As ordens em si são perigosas por natureza — desligar a máquina
hospedeira apaga o próprio Home Assistant —, e por isso **nenhuma é disparada por
mim**: cada uma nasce atrás de confirmação, e a cerca reprova se um botão
perigoso perder a dela ou se algo automático chamar um roteiro.

## Impact sweep (commands run now)

```
for u,n in (("sshhost_8ccff25b","Mac mini"),("sshhost_d25b6f47","UDR7")):
grep -n "device_id" inventario/reserva/verifica-reserva.sh inventario/reserva/confere-entidades.py
if ta.get('action') == 'perform-action':
cat inventario/reserva/reserva.yaml
cat inventario/reserva/reserva-scripts.yaml
cat inventario/reserva/verifica-reserva.sh
cat inventario/reserva/confere-entidades.py
cat docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md
cat docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md
cat docs/planos_concluidos/README.md
```

| Medição | Achado |
|---|---|
| Ordens da máquina hospedeira | **`load.off` e mais nada** — desligar existe, reiniciar não |
| Ordens do roteador | `load.off` **e** `shutdown.reboot` — os dois |
| Cerca da confirmação, hoje | Conhece **um** roteiro pelo nome; um botão perigoso novo nasceria sem cobertura |
| Cerca da automação na instância, hoje | Percorre uma lista **fixa** de dois nomes de roteiro, escrita à mão |

## Changes, per file

- `inventario/reserva/reserva-scripts.yaml` — dois roteiros novos, ambos ação de
  dispositivo com a ordem de desligar: um para a máquina hospedeira, outro para o
  roteador. Modo único, descrição dizendo a consequência.
- `inventario/reserva/reserva.yaml` — três botões na seção dos protegidos
  (desligar a máquina hospedeira, desligar o roteador, reiniciar o roteador),
  cada um com **confirmação própria** dizendo o que acontece; e o texto da seção
  deixa de justificar decisão minha e passa a informar o limite medido: reiniciar
  só existe para o roteador.
- `inventario/reserva/confere-entidades.py` — a cerca da confirmação deixa de
  conhecer **um** roteiro pelo nome: passa a exigir confirmação em **todo** cartão
  que dispara roteiro desta frente, com uma lista curta e declarada do que é
  inofensivo (reler comandos). É o conserto da CLASSE: botão perigoso novo nasce
  coberto.
- `inventario/reserva/verifica-reserva.sh` — a busca por automação na instância
  deixa de usar lista fixa e passa a derivar os nomes **do próprio pacote**.
- `docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md` e
  `docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md` — o registro da
  correção de rumo: a decisão era do dono, não minha.
- `docs/planos_concluidos/2026-09-17-2245-desligar-e-reiniciar.plan.md` e
  `docs/planos_concluidos/README.md` — plano concluído e índice.

## Scope

```
inventario/reserva/reserva.yaml
inventario/reserva/reserva-scripts.yaml
inventario/reserva/confere-entidades.py
inventario/reserva/verifica-reserva.sh
docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md
docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md
docs/planos_concluidos/2026-09-17-2245-desligar-e-reiniciar.plan.md
docs/planos_concluidos/README.md
```

**Arquivos novos declarados:** `docs/planos_concluidos/2026-09-17-2245-desligar-e-reiniciar.plan.md`.

## Acceptance (EARS)

| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | qualquer cartão dispara um roteiro perigoso da frente | exigir confirmação naquele cartão, sem depender do nome do roteiro | `bash inventario/reserva/verifica-reserva.sh --fase 2` | imprime `SEM CONFIRMACAO` |
| 2 | os roteiros citam identificadores de aparelho | provar que todos existem no registro de aparelhos | `bash inventario/reserva/verifica-reserva.sh --fase 2` | imprime `APARELHO AUSENTE:` |
| 3 | a instância tem automações | provar que nenhuma chama **nenhum** roteiro do pacote, lista derivada do próprio pacote | `bash inventario/reserva/verifica-reserva.sh --fase 2` | imprime `CHAMADA AUTOMATICA NA INSTANCIA:` |
| 4 | o painel é conferido | continuar citando só entidades existentes e habilitadas | `bash inventario/reserva/verifica-reserva.sh --fase 2` | imprime `ENTIDADE AUSENTE:` ou `ENTIDADE DESABILITADA:` |
| 5 | os scripts da frente são medidos, depois do portão ter resolvido o verificador fixado | passar com a mesma régua de exclusões do repositório | `"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/reserva/verifica-reserva.sh inventario/reserva/implanta-reserva.sh` | qualquer achado impresso |
| 6 | o portão do produto roda depois da frente | continuar íntegro, cerca de segredo incluída | `./tools/gate.sh` | imprime `[ERRO]` ou `checagem(ns) falharam` |

## Verification (after the last commit)

```
./tools/gate.sh
"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/reserva/verifica-reserva.sh inventario/reserva/implanta-reserva.sh
bash inventario/reserva/verifica-reserva.sh --fase 2
```

Expected: portão do produto em `RESULTADO: portão limpo`; verificador fixado sem
nenhuma linha; `RESERVA OK` com a contagem de entidades, fase 2.

## Refutation

- Confirmação retirada do botão de desligar a máquina hospedeira (um botão que a
  cerca antiga **não conhecia**) → `SEM CONFIRMACAO`.
- Identificador de aparelho de um dos roteiros novos trocado por inexistente →
  `APARELHO AUSENTE:`.
- Automação plantada na instância chamando um dos roteiros **novos** (a lista
  fixa antiga não os cobria) → `CHAMADA AUTOMATICA NA INSTANCIA:`, com o arquivo
  restaurado e conferido por impressão digital.

## Out of scope

- Reiniciar a máquina hospedeira: **não existe** no servidor; o pedido vai ao
  agente da ponte, não ao YAML.
- Disparar qualquer uma das ordens: ato do dono.
- Qualquer alteração no produto público.

## Overnight policy

- Decidido de noite, com fonte: quais ordens existem (medido no servidor no ato).
- Reservado ao dono: **disparar** qualquer botão, `git push`.

## Open questions

- Nenhuma.
