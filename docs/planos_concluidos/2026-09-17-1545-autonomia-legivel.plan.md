<!-- Cópia higienizada do plano APROVADO. O repositório é público:
     identificadores de entidade desta casa foram substituídos por descrição.
     O original com os nomes reais vive fora do versionamento. -->

# Autonomia legível — o painel Reserva deixa de mostrar segundos crus

project: ~/Development/ABHOME-infra/ABHOME-haos-macmini
status: aceito

## Context

O painel Reserva entrou no ar em 2026-09-17 e tem **um defeito visível meu**: a
informação mais valiosa dele — quanto tempo a casa aguenta — aparece em segundos
crus (`148.140 s`) na etiqueta do topo, nos dois cartões de Autonomia e no
gráfico de 24 h. A prancha aprovada pelo dono mostrava `38 h 09 min`
(`mockup-2026-09-17-reserva.html:221`): o produto entregue **divergiu do desenho
aprovado**, e a divergência é minha, não do desenho.

A causa está medida: a integração NUT declara `battery.runtime` com unidade
nativa em **segundos** e sem precisão de exibição sugerida
(`sensor.py:189-196` da versão 2026.9.1), então o frontend mostra o número como
ele vem.

Resultado pretendido: nas abas de operação a autonomia é lida em horas e
minutos, como o dono aprovou; o número cru continua existindo, mas onde é
diagnóstico.

## Risk band

**standard** — escreve em `/config` da instância de produção pelo mesmo
implantador já provado nesta frente (backup carimbado, verificação e volta atrás
conferida por impressão digital); não toca o produto público; nenhum ato
destrutivo. Os dois acréscimos são template do próprio Home Assistant, sem
integração nova e sem credencial.

## Impact sweep (commands run now)

```
grep -n "runtime\|autonomia\|Autonomia" inventario/reserva/reserva.yaml
curl -fsS "$B/sensor.py" -o nut_sensor_2026_9_1.py
grep -n -A40 "^UNIT_CONVERTERS" sensor_const_2026_9_1.py
f"GET VAR {u} battery.runtime"
from homeassistant.util import slugify
import jinja2,yaml; print('mac jinja2'
sudo grep -nE \"^homeassistant:|packages|^template:
grep -n "h [0-9]\{1,2\} min\|min<\|Autonomia" inventario/reserva/mockup-2026-09-17-reserva.html
cat -n inventario/reserva/reserva.yaml
cat -n inventario/reserva/reserva-scripts.yaml
cat -n inventario/reserva/verifica-reserva.sh
cat -n inventario/reserva/confere-entidades.py
cat -n inventario/reserva/implanta-reserva.sh
cat -n docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md
cat -n docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md
cat -n docs/planos_concluidos/README.md
```

O que cada um mediu:

| Medição | Achado |
|---|---|
| Onde a autonomia aparece no painel | 5 citações: etiqueta do topo (linha 21), cartão do escritório (40), cartão da sala (82), gráfico de 24 h (147 e 149) — todas em segundos crus |
| Descrição do sensor na integração NUT 2026.9.1 | `native_unit_of_measurement=UnitOfTime.SECONDS`, `device_class=SensorDeviceClass.DURATION`, **sem** `suggested_display_precision` |
| Conversão de unidade por entidade | O Home Assistant **converte** duração (`SensorDeviceClass.DURATION: DurationConverter`) e aceita `DAYS, HOURS, MINUTES, SECONDS, MILLISECONDS, MICROSECONDS`. Converter para horas daria `41,15 h` — número, não `41 h 09 min`; e moraria no `.storage`, fora de qualquer arquivo versionado. **Recusado por isso** |
| Valores vivos no servidor, medidos no ato | um dos no-breaks `148140` s · o outro `285540` s — ou seja, `41 h 09 min` e `79 h 19 min` |
| Configuração da instância | `homeassistant: packages: !include_dir_named packages` — o pacote da frente já é carregado; **não existe** bloco `template:` na configuração, então o template nasce dentro do pacote |
| Identificador que o Home Assistant vai gerar | `slugify(<nome do sensor>)` = o identificador derivado, sem acento — medido no próprio contêiner, não suposto |
| Motor de template disponível | `jinja2` 3.1.6 dentro do Home Assistant (e 3.1.4 no Mac) — dá para rodar a fórmula no motor do próprio Home Assistant e comparar com a tabela esperada |
| A prancha aprovada | `38 h 09 min` / `82 h 49 min` — o formato `H h MM min` é o que o dono aprovou, não invenção minha |

## Changes, per file

- `inventario/reserva/reserva-scripts.yaml` — ganha um bloco `template:` com
  **quatro sensores derivados**, dois por no-break: o de texto
  (`Reserva autonomia escritório` / `… sala`), que rende `41 h 09 min` acima de
  uma hora e `9 min` abaixo dela; e o numérico em horas (`… em horas`), com
  classe de duração, unidade `h` e classe de estado `measurement`, que é o que o
  gráfico de 24 h sabe desenhar. Disponibilidade amarrada ao sensor de origem:
  origem indisponível, derivado indisponível — sem inventar texto de erro.
- `inventario/reserva/reserva.yaml` — as cinco citações trocadas: etiqueta do
  topo e os dois cartões passam ao sensor de texto (e a sala ganha etiqueta
  própria, que hoje não tem, para a leitura de um olhar valer para os dois); o
  gráfico de 24 h passa aos sensores em horas; o número cru **desce para a aba
  de Diagnóstico**, onde é diagnóstico e não decisão.
- `inventario/reserva/confere-entidades.py` — duas conferências novas:
  `AUTONOMIA ILEGIVEL:` quando uma aba que não seja a de diagnóstico citar um
  sensor `*_battery_runtime`, e a exigência de que as abas de operação citem os
  sensores derivados de autonomia.
- `inventario/reserva/verifica-reserva.sh` — seção nova que roda a fórmula no
  motor de template do próprio Home Assistant, com uma tabela de casos, e
  reprova com `FORMULA ILEGIVEL:` quando a saída difere do esperado. Limite
  declarado no código: o teste usa o `jinja2` do Home Assistant, não o ambiente
  completo dele — prova a aritmética e o formato, não os filtros próprios.
- `docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md` — o defeito e o conserto
  entram na porta de entrada da frente, com a prova.
- `docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md` — entrada nova no
  diário: o defeito, a classe dele e a decisão de não usar conversão de unidade.
- `docs/planos_concluidos/2026-09-17-1545-autonomia-legivel.plan.md` — este
  plano, no fechamento.
- `docs/planos_concluidos/README.md` — a linha deste plano no índice.

## Scope

```
inventario/reserva/reserva.yaml
inventario/reserva/reserva-scripts.yaml
inventario/reserva/verifica-reserva.sh
inventario/reserva/confere-entidades.py
docs/roadmap/HANDOFF-2026-09-17-painel-reserva.md
docs/roadmap/decisoes/2026-09-17-1100-painel-reserva.md
docs/planos_concluidos/2026-09-17-1545-autonomia-legivel.plan.md
docs/planos_concluidos/README.md
```

**Arquivos novos declarados:** `docs/planos_concluidos/2026-09-17-1545-autonomia-legivel.plan.md`.

## Acceptance (EARS)

| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | o painel é conferido | recusar autonomia em segundos crus em qualquer aba que não seja a de diagnóstico | `bash inventario/reserva/verifica-reserva.sh` | imprime `AUTONOMIA ILEGIVEL:` |
| 2 | a fórmula é renderizada pelo motor do Home Assistant | devolver `41 h 09 min` para 148140 s, `9 min` para 540 s e `0 min` para 0 s | `bash inventario/reserva/verifica-reserva.sh` | imprime `FORMULA ILEGIVEL:` |
| 3 | o painel implantado é conferido | encontrar os quatro sensores derivados existentes e habilitados no registro da instância | `bash inventario/reserva/verifica-reserva.sh` | imprime `ENTIDADE AUSENTE:` ou `ENTIDADE DESABILITADA:` |
| 4 | os scripts da frente são medidos, depois de `./tools/gate.sh` ter resolvido o verificador fixado | passar com a mesma régua de exclusões do repositório | `"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/reserva/verifica-reserva.sh inventario/reserva/implanta-reserva.sh` | qualquer achado impresso |
| 5 | o portão do produto roda depois da frente | continuar íntegro, cerca de segredo incluída | `./tools/gate.sh` | imprime `[ERRO]` ou `checagem(ns) falharam` |

## Verification (after the last commit)

```
./tools/gate.sh
"${TMPDIR:-/tmp}/shellcheck-v0.10.0/shellcheck" -e SC2034,SC1090,SC1091,SC2317,SC2329 inventario/reserva/verifica-reserva.sh inventario/reserva/implanta-reserva.sh
bash inventario/reserva/verifica-reserva.sh
```

Expected: o portão termina em `RESULTADO: portão limpo`; o verificador fixado
não imprime nada; `verifica-reserva.sh` imprime `RESERVA OK` com a contagem de
entidades conferidas. O portão roda primeiro porque é ele que resolve e guarda o
verificador fixado.

## Refutation

- A conferência de legibilidade falha quando o cartão volta ao sensor cru —
  injeção: trocar o sensor derivado de texto de volta por
  o sensor cru da integração no cartão Autonomia; texto esperado:
  `AUTONOMIA ILEGIVEL: <sensor cru>`.
- O teste da fórmula falha quando a aritmética erra — injeção: trocar `3600` por
  `600` no template do sensor de texto; texto esperado: `FORMULA ILEGIVEL:` com
  a saída divergente e o valor esperado ao lado.
- A conferência de citação falha quando a aba de operação deixa de citar os
  derivados — injeção: apagar as citações do sensor de texto do painel; texto
  esperado: `AUTONOMIA ILEGIVEL: a aba agora nao cita autonomia legivel`.

## Out of scope

- Conversão de unidade por entidade no registro (`.storage`): recusada com razão
  escrita — rende número decimal em horas, não `H h MM min`, e é estado que não
  cabe em arquivo nenhum desta frente.
- Fase dos protegidos (Mac mini e roteador): continua esperando o ato do dono.
- Interruptor de tomada: continua dependendo de versão futura do serviço, sem data.
- Qualquer alteração no produto público.

## Overnight policy

- Decidido de noite, com fonte: formato de exibição (a prancha aprovada), nomes
  e unidades de sensor (código da integração e do Home Assistant medidos).
- Reservado ao dono, e proibido de madrugada: implantar na instância, reiniciar
  o Core, `git push`.

## Open questions

- Nenhuma.
