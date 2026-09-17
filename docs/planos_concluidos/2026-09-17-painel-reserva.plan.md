# Painel Reserva — os no-breaks e os protegidos no Home Assistant

project: ~/Development/ABHOME-infra/ABHOME-haos-macmini
status: aceito
<!-- Higienizado ao entrar no versionamento: identificadores desta casa saíram;
     os literais vivem em inventario/reserva/, fora do git. -->

## Context

Dois EcoFlow River 3 Plus entraram no Home Assistant pela integração NUT, servidos pelo
River Bridge do Mac mini. Hoje rendem **36 entidades, todas sensores**, espalhadas no painel
padrão — e a informação mais valiosa de um no-break (**quanto tempo ele aguenta**) chega ao
Mac mini e morre antes da tela, porque a integração NUT nasce com esses sensores
desabilitados.

O dono pediu um painel próprio para eles, com controle, e perguntou se valia misturar com o
painel de Energia nativo. Não vale: o painel de Energia trabalha com energia acumulada
(kWh) e os Rivers só entregam watts; e declarar um no-break como "bateria da casa" inventa
um fluxo que não existe — o consumo deles já é medido pelo Shelly. Painel próprio, então,
com os cartões nativos do Home Assistant.

Duas descobertas da medição mudam o alcance para melhor:

1. O servidor do Mac mini **também publica o próprio Mac mini e o UDR7** como dispositivos
   protegidos, com carga, autonomia e comandos — e eles nem estão no Home Assistant.
2. O controle de tomadas **não depende desta frente**: o bridge declara as saídas como não
   comutáveis, e o acordo fechado com o agente daquele projeto prevê um conjunto novo de
   variáveis (limites, alarme, pacotes de bateria, contagem regressiva, trava do desligar)
   numa versão futura, **sem data**. Esta frente não cita nenhuma entidade que ainda não
   exista; quando a versão chegar, o painel ganha os cartões novos numa edição de YAML.

Resultado pretendido: um painel **Reserva** que mostre, de um olhar, quanto tempo a casa
aguenta sem energia, o que está protegido, e o que dá para comandar hoje.

## Risk band

**standard** — escreve em `/config` de uma instância de produção que tem cofre diário e
restauração já provada em campo; não toca o produto público; nenhum ato destrutivo. As duas
salvaguardas são executáveis: habilitar sensores usa o utilitário do próprio repositório
(`entity-enable`, que respeita o que o dono desabilitou à mão), e a escrita em `/config`
passa por backup carimbado, verificação e rollback **refutado** (injeção nº 4).

## Impact sweep (commands run now)

```
sudo cat /homeassistant/.storage/core.entity_registry
sudo cat /homeassistant/.storage/core.config_entries
ha core info --raw-json
LIST VAR river-3-plus-0046
LIST CMD river-3-plus-0046
for ups in (<os dois aparelhos protegidos>)
curl -fsS "$B/switch.py"
curl -fsS "$B/sensor.py"
https://raw.githubusercontent.com/networkupstools/nut/master/docs/nut-names.txt
grep -nE "outlet\.n\.(current_status|status|switchable|desc|name)" /tmp/nut-names.txt
sed -n '286,296p' /tmp/nut-names.txt
git check-ignore -v inventario/qualquer.txt
/bin/ls -la inventario/
grep -nE "\[FALHA\]|portão sujo" tools/gate.sh
sed -n '322,335p' verify.sh
grep -n -A14 "acha_shellcheck()" tools/gate.sh
command -v ha
/bin/ls -la docs/roadmap/decisoes/
```

O que cada um mediu:

| Medição | Achado |
|---|---|
| Registro de entidades da instância | 36 entidades NUT, **todas sensores**; zero interruptor. Desabilitadas por padrão: autonomia (nos dois Rivers), potência real, potência de entrada, tensão, temperaturas, frequência, limite de bateria baixa |
| Registro de integrações | As duas entradas NUT têm **usuário e senha** definidos — condição para o Home Assistant procurar comandos |
| Versão | Core **2026.9.1** |
| Servidor NUT, Rivers | `outlet.count=4`; `outlet.N.switchable="no"` nas quatro; `LIST CMD` só `load.off`; autonomia presente no servidor (137.340 s e 298.140 s) |
| Servidor NUT, protegidos | Mac mini (Apple, carga 98, `load.off`) e UDR7 (Ubiquiti, carga 100, `load.off` + `shutdown.reboot`) — **nenhum dos dois está no Home Assistant** |
| `switch.py` / `button.py` / `sensor.py` / `__init__.py` da integração NUT | Interruptor de tomada exige `switchable=="yes"` **e** os dois comandos; estado lê `outlet.N.status`; botão só para `load.cycle`; 92 nomes viram sensor, e por tomada só `current`, `current_status`, `desc`, `power`, `realpower`; `ups.status.display` é derivado pelo próprio HA; comandos são descobertos **no carregamento da entrada** |
| Norma do NUT (`nut-names.txt`) | `outlet.n.status` = "Outlet switch status (on/off)" (linha 874); `current_status` **ausente da norma**; `ups.id` = identificador do sistema (233); `ups.shutdown` = "Enable or disable UPS shutdown ability" (289) |
| `inventario/` | Existe, é ignorado pelo git (`.gitignore:8`) e já guarda artefatos desta casa |
| Textos de falha do portão | Ele **não** imprime `[FALHA]` nem "portão sujo": imprime `[ERRO]` (`tools/gate.sh:28`) e `RESULTADO: N checagem(ns) falharam` (`tools/gate.sh:1422`) |
| Cerca de segredo | Varre **só arquivos rastreados** e declara que `inventario/` fica fora dela (`verify.sh:327`) — por isso todo documento versionado desta frente nasce higienizado |
| Shellcheck do portão | Versão fixada `v0.10.0`, resolvida em `${TMPDIR}/shellcheck-v0.10.0/shellcheck`, e cobre apenas `haos-install.sh verify.sh tools/*.sh lib/*.sh extras/*.sh` — **não** cobre `inventario/` |
| `ha` no Mac | **Não existe** no PATH: todo `ha core check` desta frente roda por ssh **dentro** do HAOS |
| `docs/roadmap/decisoes/` | Existe e está vazio — é o lugar que o monorepo declara para o diário da frente |

## Changes, per file

Arquivos da casa em `inventario/reserva/` — dentro do repositório para organização, **fora do
versionamento** (`.gitignore:8`), porque citam entidades e equipamentos desta casa e o
repositório é público. Documentos da frente em `docs/`, **higienizados** (sem identificador de
entidade, sem endereço, sem nome de equipamento), como manda a cerca de segredo.

- `inventario/reserva/mockup-2026-09-17-reserva.html` — prancha navegável, HTML único, sem
  servidor e sem recurso externo, no padrão do mockup do River Bridge (barra de controle fora
  do produto; janela simulando o produto) e no **visual do HAOS**: tokens do sistema de design
  oficial, barra lateral e cabeçalho do Home Assistant, cartões desenhados como o frontend os
  desenha. Alternâncias: tema claro/escuro, estado (na tomada · na bateria · queda), moldura
  (computador · telefone) e **versão do bridge** (hoje · com as variáveis futuras) — esta
  última existe só no mockup, para o dono ver o destino.
- `inventario/reserva/reserva.yaml` — o painel em vista de seções: **Agora** (por River:
  bateria, autonomia, potência, as quatro saídas), **Protegidos** (Mac mini e UDR7 com carga,
  autonomia, estado; botão de reiniciar o UDR7 com confirmação), **Histórico** (24 h) e
  **Diagnóstico** (temperaturas, tensão, limites). **Cita exclusivamente entidades que
  existem no momento da escrita** — nada condicional, nada de entidade futura.
- `inventario/reserva/reserva-scripts.yaml` — o que vira `/config/packages/reserva.yaml`:
  roteiro que reinicia o UDR7 (ação de dispositivo da integração NUT) e roteiro que recarrega
  as entradas NUT (`homeassistant.reload_config_entry`, campo `entry_id`).
- `inventario/reserva/verifica-reserva.sh` — o portão da entrega, rodando **no Mac**: valida o
  YAML, extrai toda entidade citada e prova contra o registro da instância que existe e está
  habilitada; confere que o cartão do reinício tem confirmação e que nenhuma automação chama
  o roteiro; chama `ha core check` **por ssh dentro do HAOS**. Aceita `--fase 2` para incluir
  as entidades dos protegidos. Imprime `RESERVA OK` ou o token da falha.
- `inventario/reserva/implanta-reserva.sh` — implantação: backup carimbado com impressão
  digital → escrita → verificação → **rollback** se reprovar (restaura e reconfere o SHA-256)
  → reinício do Core. Reusa a receita já usada nesta casa para o painel Casa.
- `docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md` — a porta de entrada da frente, no rito
  do monorepo, higienizada, apontando para `inventario/reserva/` o que é da casa.
- `docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md` — o diário, com os painéis de
  status de cada etapa.
- `docs/planos_concluidos/2026-09-17-painel-reserva.plan.md` — este plano, no fechamento.
- `docs/roadmap/HANDOFF-2026-08-25-a-algema-do-apfs.md` — ganha a marca **SUPERADO por**
  apontando o handoff novo, como os outros seis da pasta já fazem; é a cadeia de portas de
  entrada que o monorepo exige.
- `docs/planos_concluidos/README.md` — ganha a linha deste plano na tabela do índice, também
  exigida pelo checklist de fechamento do monorepo.

**Método dos sensores desabilitados, corrigido:** usar o utilitário do próprio repositório,
`entity-enable` (`lib/ha-api.py`, exposto por `helper_cred` em `haos-install.sh`), que habilita
pela API o que a **integração** desabilitou e **respeita** o que o dono desabilitou à mão. Não
se edita o registro de entidades a arquivo. O utilitário pede a credencial do Home Assistant.

**Duas fases, com pré-condição declarada.** Fase 1 (Rivers): mockup, curadoria de sensores,
painel e roteiros — verificada com `verifica-reserva.sh`. Fase 2 (Protegidos): só **depois**
de o dono adicionar as duas entradas NUT; a seção Protegidos e o roteiro do reinício entram
aqui, verificados com `verifica-reserva.sh --fase 2`.

**O que precisa da mão do dono, avisado antes:** (a) a credencial do Home Assistant, uma vez,
para a curadoria dos sensores; (b) adicionar as duas entradas NUT novas — Configurações →
Dispositivos e Serviços → Adicionar → Network UPS Tools, mesmo servidor, usuário e senha das
entradas existentes, mudando só o dispositivo.

## Scope

```
inventario/reserva/**
docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md
docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md
docs/planos_concluidos/2026-09-17-painel-reserva.plan.md
docs/roadmap/HANDOFF-2026-08-25-a-algema-do-apfs.md
docs/planos_concluidos/README.md
```

**Arquivos novos declarados:** `docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md`,
`docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md`,
`docs/planos_concluidos/2026-09-17-painel-reserva.plan.md`, e tudo sob
`inventario/reserva/`.

## Acceptance (EARS)

| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | o mockup está escrito | não buscar nenhum recurso externo (sem servidor, sem fonte remota) | `grep -nE "https?://\|src=\|@import\|fonts\." inventario/reserva/mockup-2026-09-17-reserva.html` | imprime qualquer linha |
| 2 | o painel da fase 1 é escrito | citar apenas entidades existentes e habilitadas | `bash inventario/reserva/verifica-reserva.sh` | imprime `ENTIDADE AUSENTE:` ou `ENTIDADE DESABILITADA:` |
| 3 | o YAML do painel é alterado | recusar YAML inválido antes de qualquer escrita remota | `bash inventario/reserva/verifica-reserva.sh` | imprime `YAML INVALIDO` |
| 4 | a configuração é gravada na instância | passar na verificação e, reprovando, restaurar o arquivo anterior com a mesma impressão digital | `bash inventario/reserva/implanta-reserva.sh` | imprime `CHECK-REPROVOU` sem em seguida `RESTAURADO sha256 confere` |
| 5 | a curadoria de sensores roda | a autonomia dos dois Rivers passar a existir habilitada e com valor numérico | `bash inventario/reserva/verifica-reserva.sh` | imprime `AUTONOMIA AUSENTE` |
| 6 | o dono adicionou as entradas dos protegidos | a seção Protegidos ser escrita e conferida na fase 2 | `bash inventario/reserva/verifica-reserva.sh --fase 2` | imprime `PROTEGIDO AUSENTE:` |
| 7 | o roteiro que reinicia o roteador existe | ter confirmação no cartão e não ser chamado por nada automático | `bash inventario/reserva/verifica-reserva.sh --fase 2` | imprime `SEM CONFIRMACAO` ou `CHAMADA AUTOMATICA` |
| 8 | os dois scripts novos são medidos, **depois** de `./tools/gate.sh` ter resolvido o verificador fixado | passar com a mesma régua de exclusões do repositório | `"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/reserva/verifica-reserva.sh inventario/reserva/implanta-reserva.sh` | qualquer achado impresso |
| 9 | o portão do produto roda depois da frente | continuar íntegro, cerca de segredo incluída | `./tools/gate.sh` | imprime `[ERRO]` ou `checagem(ns) falharam` |

## Verification (after the last commit)

```
./tools/gate.sh
"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/reserva/verifica-reserva.sh inventario/reserva/implanta-reserva.sh
bash inventario/reserva/verifica-reserva.sh
```

Expected: o portão termina em `RESULTADO: portão limpo`; o verificador fixado não imprime
nada; `verifica-reserva.sh` imprime `RESERVA OK` com a contagem de entidades conferidas. O
portão roda primeiro porque é ele que resolve e guarda o verificador fixado.

**A fase 2 não fecha esta frente, e por isso não está no bloco acima.** Ela depende de um ato
do dono (adicionar as duas entradas dos protegidos), e condicionar o fechamento a um ato de
terceiro seria pendurar o rito em quem não é o executor. O gate da fase 2 é o aceite 6 e o 7,
rodados com `bash inventario/reserva/verifica-reserva.sh --fase 2` **depois** do ato do dono;
o resultado entra no diário da frente.

## Refutation

- `verifica-reserva.sh` falha quando o painel cita entidade inexistente — injeção:
  acrescentar `sensor.reserva_inexistente_teste` ao YAML; texto esperado:
  `ENTIDADE AUSENTE: sensor.reserva_inexistente_teste`.
- `verifica-reserva.sh` falha quando o YAML quebra — injeção: remover um espaço de indentação
  de um item de lista; texto esperado: `YAML INVALIDO`.
- `verifica-reserva.sh` falha quando a entidade existe mas está desabilitada — injeção: citar
  um sensor de frequência de entrada, que a curadoria deixa desabilitado
  de propósito; texto esperado: `ENTIDADE DESABILITADA: <identificador>` (o literal vive em `inventario/reserva/`,
  fora do versionamento).
- `implanta-reserva.sh` restaura quando a verificação reprova — injeção: mandar implantar um
  `configuration.yaml` com bloco inválido; textos esperados, em sequência: `CHECK-REPROVOU` e
  `RESTAURADO sha256 confere`, com o arquivo remoto voltando à impressão digital medida antes.

## Out of scope

- Interruptor de tomada: depende de versão futura do River Bridge, **sem data**; nada dele
  entra no YAML agora.
- Painel de Energia nativo: nenhum sensor derivado (kWh) nesta frente.
- Qualquer alteração no produto público (`haos-install.sh`, catálogo, `tools/gate.sh`,
  `README`): esta frente não o toca.
- Botão de desligar o Mac mini ou o UDR7: fora do painel. Desligar o mini apagaria o próprio
  Home Assistant; desligar o roteador derrubaria a rede. Só **reiniciar** o UDR7 entra.
- Adicionar as entradas NUT dos protegidos e fornecer a credencial: atos do dono.

## Overnight policy

- Decidido de noite, com fonte: nomes de variável e comportamento da integração (norma do NUT
  e código do Home Assistant), forma dos cartões (documentação oficial de painéis), paleta
  (sistema de design do frontend) — registrado no diário e marcado "ratificar de manhã".
- Reservado ao dono, e **proibido de madrugada** (o monorepo proíbe tocar rede e hardware da
  casa à noite): executar `implanta-reserva.sh`, rodar a curadoria de sensores, chamar o
  roteiro que reinicia o roteador, reiniciar o Core, adicionar entradas NUT, `git push`, e
  aprovar o mockup. De noite andam apenas mockup, YAML, scripts e documentos — nada que toque
  a instância.

## Open questions

- Nenhuma. A versão do River Bridge que publicará as variáveis novas **não tem data**, e o
  plano está escrito para não depender dela.

## Review

```
plan: linear-frolicking-wren.md
round: 1
sections-round1: Context | Risk band | Impact sweep (commands run now) | Changes, per file | Scope | Acceptance (EARS) | Verification (after the last commit) | Refutation | Out of scope | Overnight policy | Open questions
VERDICT: REJECTED
```

Nove bloqueadores e três avisos, **todos conferidos por mim no repositório antes de aceitar**
— e todos procedentes. Classe do que faltou ler no meu levantamento, para o diário: eu não
abri `tools/gate.sh` nem `verify.sh` para saber **o que o portão cobre e o que ele imprime**,
e não varri o repositório atrás de utilitário já existente para a tarefa (`entity-enable`)
antes de propor um método a arquivo.

| # | Bloqueador | Correção aplicada |
|---|---|---|
| B1 | Aceite usava textos que o portão nunca imprime | Aceite 9 usa `[ERRO]` e `checagem(ns) falharam`, medidos em `tools/gate.sh:28` e `:1422` |
| B2 | Os scripts novos nasciam sem lint (o portão não cobre `inventario/`) | Aceite 8 e linha própria na Verification com o shellcheck fixado `v0.10.0` |
| B3 | Cartões condicionais citariam entidades inexistentes, contradizendo o aceite | Cartões condicionais **removidos** do YAML; o futuro vive só no mockup |
| B4 | Verificação rodaria antes das entradas dos protegidos existirem | Fases 1 e 2 declaradas, com `--fase 2` e aceite próprio |
| B5 | Editar o registro a arquivo tendo `entity-enable` no repositório | Método trocado pelo utilitário da casa; alegação sem lastro sobre "três vezes em 25/08" removida |
| B6 | Frente sem rastro versionado e fora do rito do monorepo | Escopo ganha HANDOFF, diário em `docs/roadmap/decisoes/` e plano concluído, higienizados |
| B7 | Rollback e "sem recurso externo" sem prova | Injeção nº 4 (rollback com impressão digital) e aceite 1 (varredura no HTML) |
| B8 | `ha core check` não existe no Mac | Declarado: o verificador roda no Mac e chama a verificação **por ssh dentro do HAOS** |
| B9 | Roteiro do reinício sem aceite, refutação nem trava | Aceite 7 (confirmação e nenhuma chamada automática) e proibição explícita na política de madrugada |

Avisos: refutação que se auto-invalidava trocada por entidade que a curadoria deixa
desabilitada de propósito; gramática de falha unificada em tokens únicos; "sem data" escrito
onde havia silêncio.

```
plan: linear-frolicking-wren.md
round: 2
VERDICT: REJECTED
```

Dois bloqueadores remanescentes, três avisos e uma alegação que o revisor não podia verificar.
A contagem caiu de **9 para 2**, e os dois restantes são resíduo mecânico — aplicados nesta
mesma volta, sem rodada nova, como manda a regra da casa:

| Achado da rodada 2 | O que fiz |
|---|---|
| A fase 2 no bloco de verificação penduraria o fechamento da frente num ato do dono | Bloco passa a rodar a fase 1; a fase 2 tem gate próprio (aceites 6 e 7), declarado logo abaixo do bloco, com a razão escrita |
| Faltavam no escopo o handoff a marcar como superado e o índice de planos concluídos | Ambos acrescentados ao escopo e a "Changes, per file" — e **lidos por inteiro nesta sessão**, como o pré-voo exige |
| Régua do verificador diferente da do repositório | Exclusões alinhadas com `tools/gate.sh:34` (`SC2034,SC1090,SC1091,SC2317,SC2329`), medidas no ato |
| Aceite do verificador não dizia que depende do portão ter rodado antes | A condição está escrita na própria linha do aceite |
| Tokens de falha repetidos entre aceites | Aceite da autonomia passa a `AUTONOMIA AUSENTE`; aceite dos protegidos passa a `PROTEGIDO AUSENTE:` — cada linha com token único |
| "Dois esquemas de nome incompatíveis; no máximo um casa com o registro" | **Medido agora no registro da instância: os dois existem literalmente.** A divergência é real e é do próprio Home Assistant, que gerou nomes por caminhos diferentes. Nenhuma correção necessária, e a dúvida sai do plano com evidência |

Classe do que faltou ler, para o diário: na primeira volta, o portão e as cercas do próprio
repositório; na segunda, o **rito de fechamento do monorepo** (cadeia de handoffs e índice de
planos), que eu havia lido como "documentação" e não como contrato com arquivos a tocar.
