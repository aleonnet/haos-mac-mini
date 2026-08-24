# HANDOFF — F5–F10 fechadas: o instalador entrega o HA NO AR · 2026-08-24

> **LEIA-ME PRIMEIRO.** Porta de entrada da frente do instalador. Supersede
> `HANDOFF-2026-08-24-pos-teste-campo.md`.

## 0. ESTADO — confira no git, não neste parágrafo

- main = origin/main, árvore limpa. Versão **0.3.0** (bump de fechamento).
- Portão limpo com as cercas novas: F5 dublada, **HA dublado** (REST +
  WebSocket com frame >64 KiB), sentinela de segredo, conf_estado, HACS
  adulterado, classe agent negativa; verify com en-ASCII estático.
- Plano da frente (com a banca 3×REPROVA incorporada):
  `docs/planos_concluidos/2026-08-24-f5-f10-ha-no-ar.plan.md`.

## 1. O QUE O PRODUTO FAZ AGORA (fases 01–10)

Pré-voo → seleção (gum/cardápio, Personalizado persistido no `--profile
last`) → plano → imagem → VM → **boot com espera pelo MAC** + auto-start →
**conta** (onboarding, analytics OFF) → **apps** (WS supervisor/api) →
**integrações** (só sem credencial; resto "espera você") → **arquivos**
(packages BR + HACS por SMB) → relatório com o **endereço real** + navegador.

Fim-a-fim REAL no Mac mini: 3 execuções — instala tudo → converge →
**idempotente em 18 s** (tudo "já"). SSH à VM com a chave gerada: provado.

## 2. FATOS MEDIDOS QUE O CÓDIGO AGORA CARREGA (não reaprender)

1. **HAOS 18.2 serve o HA na PORTA 80** — pré-onboarding a 8123 dá 307 para
   a 80; pós-onboarding a 8123 FECHA. O console da VM anuncia `:80`.
   `vm_url_de()` sonda as duas; helper segue 3xx preservando método.
2. **Snapshot LIVE do VirtualBox ARM mata a NIC virtio** — a VM ficou surda
   e nem reset recuperou (poweroff frio + start recria os devices; a
   primeira VM foi perdida assim e recriada pelo próprio instalador).
   Snapshot SÓ com a VM desligada. E **ACPI não desliga o HAOS** — o
   uninstall usa `controlvm poweroff` com espera, correto.
3. **Options de app podem ser ANINHADAS** (`advanced_ssh` → `ssh.*`): merge
   e diff recursivos; lista compara por contenção (o app normaliza); option
   nova em app rodando exige RESTART do app.
4. **Flow que aborta (tuya sem nuvem) ou não fecha só com defaults é do
   USUÁRIO** — desfazer o flow aberto e reportar, nunca falhar a fase.
5. **Listar flows em progresso é WS `config_entries/flow/progress`** — a
   rota REST devolve 405.
6. **Keychain não abre em sessão SSH** — o mount SMB usa expect respondendo
   o prompt com a senha em env do expect (nunca argv).
7. O Mac mini **dormia** e congelava a VM — `caffeinate` do dono segurou;
   o LaunchAgent religa a VM no login, mas energia é assunto do dono.

## 3. DECISÕES (registro, não pergunta)

1. Credencial do HA: pedida no terminal (oculta, 2×) ou
   `HAOS_HA_USER/HAOS_HA_PASSWORD`; vive só na memória da execução — a
   reexecução pede de novo. Token nunca persiste.
2. Senha do samba: gerada uma vez, relida do Supervisor a cada execução
   (desired-state) e impressa no relatório para o Finder.
3. HACS fixado (2.0.5 + SHA-256 + tamanho); bump manual em release nova.
4. `--profile last` guarda a LISTA do Personalizado (ids mortos caem fora).

## 4. DÍVIDAS DECLARADAS

1. Extension Pack/USB passthrough — fora; entra se algum item precisar.
2. `--upgrade/--upgrade-only` — a reexecução idempotente cobre "instalar o
   que falta"; upgrade de versão de app/HACS não existe.
3. O arnês de contrato do CI não exercita as ESCRITAS (POST core_config,
   flows) — mitigado por exercício empírico único em campo + HA dublado no
   portão (banca cer#4).
4. `mqtt` selecionado não configura o broker sozinho (flow é menu, regra
   `:ha` do catálogo) — fica "espera você no painel".
5. Flake antigo da cerca do cardápio (1 em 3 rodadas, 24/08) — não
   reapareceu; instrução de captura no HANDOFF anterior.
6. **`utility_meter.source` é nome-contrato (`sensor.energy_total`)** que o
   dono aponta via auxiliar template de UI — editar o yaml não sobrevive ao
   desired-state. Falta uma costura melhor (ex.: input de configuração) para
   fonte por casa.
7. `rel_falta`/`prox_*`: mensagens do relatório pré-0.3.0 que sobraram no
   MSG_DB só para o caminho sem VM_URL — revisar quando F5 for obrigatória.

## 5. BANCADA DO DONO — o teste fim-a-fim

A VM foi restaurada ao snapshot `pre-onboarding` (virgem, rodando) e o
estado de teste removido. O comando é o de sempre, no Terminal do mini:

```
curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash
```

| Passo | Ação | RESULTADO ESPERADO |
|---|---|---|
| 1 | one-liner acima | abertura, cardápio gum; escolher **Personalizado** e marcar (TAB) o que quiser |
| 2 | confirmar o plano | fases 04–06 convergem (imagem e VM já existem); boot "já rodando" |
| 3 | fase 07 pede usuário e senha (2×, oculta) | conta criada; "analytics DESLIGADO" |
| 4 | fases 08–10 correm sozinhas | apps instalados; integrações "esperam você"; packages escritos |
| 5 | relatório final | endereço real na tela + **navegador abre no seu HA** |
| 6 | rodar o one-liner DE NOVO com `--profile last` | tudo "já", ~20 s, mesma tela final |

Prompts prontos — Funcionou: `Fim-a-fim OK. Feche a frente (push já feito) e
proponha a próxima.` · Falhou: `Passo <N>: esperado <...>, observado <...>.
Saída literal: <colar>. Diagnostique antes de alterar.`

## 6. O QUE FALTA (frentes futuras)

- **core_config preenchido a partir do host** (hoje vai vazio e o dono viu a
  tela Region em inglês): fuso do macOS (`systemsetup`/`readlink
  /etc/localtime`), país/moeda do locale, `language` = idioma escolhido no
  cardápio (não o do terminal), unidade métrica quando país ≠ EUA. A tela
  Region confirmou que o HA deduz quase tudo — falta só o idioma do servidor
  e do primeiro usuário baterem com a escolha do dono.
- F7 para mosquitto/matter quando algum tier os trouxer por padrão.
- Release público (tag + raw estável) — **só sob ordem**.
- Tapo overlay/extras: seguem à parte, dentro do HAOS (contrato antigo).
