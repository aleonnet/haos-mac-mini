# HANDOFF — a noite das três mortes do /data, e o que as matou · 2026-08-25

> **LEIA-ME PRIMEIRO.** Porta de entrada da frente do instalador. Supersede
> `HANDOFF-2026-08-24-ha-no-ar.md`.

## 0. ESTADO — confira no git, não neste parágrafo

- main = origin/main, árvore limpa, portão limpo. Versão 0.3.0+unreleased.
- **A instância da casa está NO AR, restaurada por backup, com a conta e as
  28 integrações do dono** — nada manual foi refeito na recuperação final.

## 1. AS TRÊS MORTES (cronologia e causa de cada uma)

1. **Reboot do Mac** matou o VBoxHeadless a seco → `/data` zerado. Causa
   funda descoberta depois: **o VirtualBox por PADRÃO ignora flushes do
   guest** — o journal do ext4 é ficção sob esse default.
2. **Resume de savestate** quebrou o runtime de containers do guest
   (go2rtc em pânico → containerd sem exit event → Supervisor rebaixou o
   Core) → segunda perda.
3. **savestate+discardstate** na troca do vigia v2→v3 (teste controlado)
   → terceira perda. savestate está **BANIDO** do produto.

## 2. O QUE MATOU AS CAUSAS (tudo no produto, com cerca)

- **`IgnoreFlush=0`** no LUN da AHCI, gravado pela fase da VM na criação.
  Validação: **5 poweroffs secos** com marcadores sobrevivendo. Cerca F4
  exige a chamada.
- **vm-guard v3**: logout/shutdown → `ha host shutdown` via SSH (IP em
  `vm-guard.env`, escrito pela fase de boot) → fallback `poweroff` (75 s).
  Provado ao vivo: desligamento limpo em 30 s; boot frio de volta em ~50 s.
  Cerca F5 reprova `controlvm savestate`.
- **Backup FORA da VM**: `ha backups new` + exportação por cano de cat (o
  addon SSH não expõe SFTP) para `~/Documents/HAOS-backups` no Mac.
  **O ciclo completo foi provado em produção**: backup → desastre real →
  push do tar de volta → `ha backups restore` → instância inteira de volta
  (conta, 28 entries, 9 áreas, dashboards, overlay) sem um passo manual.

## 3. O QUE RODA NO MAC MINI HOJE (instância, fora do produto)

- `com.haos-mac-mini.HomeAssistant` → vm-guard v3 (igual ao do produto).
- `com.haos-mac-mini.backup` → `backup-pull.sh` às **04:10**: cria backup,
  traz para `~/Documents/HAOS-backups`, valida o tar, poda além de 7.
  ⚠️ com o IP da VM FIXO no script (reserva DHCP feita pelo dono) — a
  versão do produto deve ler o `vm-guard.env`; **productizar o puller é a próxima
  frente** (F11: fase de backup no instalador + uninstall preservando os
  tars).
- Cópia de segurança extra do dono: `~/Documents/HAOS-config` (o /config
  de 22:58 de 24/08, com .storage — foi ela que salvou a noite).

## 4. FATOS MEDIDOS NOVOS (não reaprender)

1. VirtualBox default = flush ignorado → dado zero-durável. SEMPRE
   `IgnoreFlush=0` em VM de servidor.
2. savestate/resume ≠ inofensivo: WebRTC/containerd do guest não
   sobrevivem; e discard de estado salvo = perda de páginas sujas.
3. `ha` CLI via SSH exige shell de LOGIN (`bash -lc`) para achar o token.
4. O addon SSH não fala SFTP (scp falha) — transporte por `ssh cat`.
5. Registros do HA gravam com atraso (~10 s) — teste de durabilidade
   marca, ESPERA 15 s, e então corta.
6. `launchctl bootout` seguido de `bootstrap` imediato dá EIO — retry ou
   `load -w`.

## 5. PRÓXIMAS FRENTES (ordem)

1. **F11 — backup no produto**: puller genérico (lê vm-guard.env),
   agente, primeira cópia pós-install, `--restore <tar>` no instalador
   (push do tar + `ha backups restore`), uninstall preserva os tars.
2. Enxugar mensagens/UX pendentes e re-medir bancada completa.
3. Extension Pack/USB e demais dívidas antigas do HANDOFF anterior.
