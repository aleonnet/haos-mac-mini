# HANDOFF — teste de campo no Mac mini: F1–F4 REAIS concluídas, VM BOOTA · 2026-08-24

> **SUPERADO por `HANDOFF-2026-08-24-ha-no-ar.md`.** Mantido como registro
> do fechamento da F4.
>
> Supersede `HANDOFF-2026-08-24-reforma-fechada.md`.

## 0b. F4 FECHADA NO MESMO DIA — a VM existe, boota e o HA responde

Sequência executada em 24/08, tudo medido:

1. **Sonda no VBoxManage 7.2.16 ARM real** (VM descartável `haos-probe-f4`,
   criada e removida): `createvm` exige `--platform-architecture arm`; ostype
   `Linux_arm64`; **`VirtIO` SCSI é RECUSADO no ARM** ("Invalid controller
   type 11") — o aceito é **SATA/IntelAhci**; gráfico `qemuramfb`; firmware
   EFI; NIC `virtio` em ponte OK. `unregistervm --delete` apagaria o .vdi —
   o inverso solta o medium ANTES de desregistrar.
2. **`fase_vm` implementada** com esses args, ponte SONDADA (rota default →
   varredura de `list bridgedifs`), contrato 0/100/1, rollback sem tocar no
   disco, inverso no `--uninstall`, chave `vm_registrada`, cerca de ponta a
   ponta no portão (VBoxManage dublado que grava chamadas).
3. **Campo no mini**: 1ª execução por SSH morreu em "VirtualBox not found" —
   shell não-interativo não tem `/usr/local/bin` no PATH; a sonda ganhou
   fallback para o app bundle. Depois: VM criada (8192 MiB, 4 vCPU, ponte
   `en0: Ethernet`), reexecução converge em 100, manifesto `created`.
4. **BOOT VALIDADO**: `startvm --type headless` → HAOS 18.2 boota de
   SATA+EFI e o Core responde **HTTP 200 na porta 8123 do IP que o DHCP
   entregou à VM** (página de onboarding), poucos minutos após o start.
   **A VM ficou LIGADA.**

**Achados que a F5 NÃO pode ignorar:**
- **`homeassistant.local` pode pertencer a OUTRO Home Assistant já vivo na
  rede** (medido nesta casa: o nome resolve para a instância antiga, não
  para a VM) — um teste de :8123 por esse nome dá falso positivo. A espera
  do boot na F5 deve achar a VM **pelo MAC** (showvminfo `macaddress1` →
  `arp -an`), como o teste fez. O sufixo `-2.local` não respondeu.
- Qualquer usuário com um HA já na rede tem a mesma ambiguidade — o
  relatório da F5 deve imprimir o IP REAL da VM, não só o nome .local.

## 0. ESTADO — confira no git, não neste parágrafo

- main local = origin/main, árvore limpa. Últimos commits: relatório
  honesto + barra nossa + teclas medidas; antes dele, a rodada de campo
  (mount por -plist, calha nos prompts, seletor gum, Personalizado no menu).
- Versão **0.2.0** · `[Unreleased]` do CHANGELOG acumula a rodada de campo.
- Portão `./tools/gate.sh` **limpo em ~55 s** — agora com a cerca de teclas
  (expect dirige o gum num pty; a 1ª versão da cerca TRAVOU o portão e foi
  reescrita no formato heredoc com `set timeout 8`).

## 1. O TESTE DE CAMPO — o que o Mac mini TEM hoje

O dono rodou o one-liner de verdade, várias vezes, até o fim. Estado real da
máquina alvo:

| Artefato | Estado |
|---|---|
| VirtualBox **7.2.16r174877** | instalado em `/Applications/VirtualBox.app` (F1 real, com senha e aprovação da extensão) |
| Disco HAOS | `~/VirtualBox VMs/HomeAssistant/haos_generic-aarch64-18.2.vdi`, SHA-256 verificado (F3 real) |
| Seleção | salva — Personalizado, 16 itens (inclui hacs/extensoes); `--profile last` reproduz |
| Manifesto | `host-prereqs` + `vms/HomeAssistant.manifest` gravados |
| Relatório final | fecha em placar + "o que ficou instalado" + aviso do que ainda não existe |

**F4 está DESBLOQUEADA**: existe VBoxManage real para sondar.

## 2. O QUE A RODADA DE CAMPO CONSERTOU (cada item nasceu de um tiro do dono)

1. `hdiutil attach -quiet` suprime a listagem → parse do `-plist` +
   `</dev/null` + diagnóstico de log. DMG em cache com SHA.
2. Prompt colado na barra de fase → `ha_bar_suspende/retoma`; prompts no
   stdout, ícone `?`, calha em toda etapa.
3. Seletor numerado "horrível" → gum 0.17.0 (SHA conferido, tema HA, cache
   por versão), busca, Personalizado como opção do MENU, opções via `msg()`.
4. Cabeçalho ensinava tecla errada → medido com expect: ESPAÇO no choose,
   TAB no filter. Cerca no portão.
5. "Jogo da velha" do curl → barra NOSSA (poll de `stat -f%z` contra o total).
6. "Não entendi o que foi instalado e onde" → `relatorio_final()` responde as
   duas perguntas e avisa que **nada responde em :8123 ainda**.

## 3. DECISÕES (registro, não pergunta)

1. **A versão 0.2.x PARA na preparação verificada** — e o relatório final diz
   isso com todas as letras (`rel_falta`). Criar a VM, boot e navegador são a
   PRÓXIMA release. Custo: o usuário termina sem HA rodando; ganho: nenhuma
   promessa falsa na tela.
2. Barra de download por poll de 300 ms do arquivo parcial, curl em
   background — não parser do stderr do curl. Reversível trocando o laço.
3. Cerca de teclas roda só quando `expect` + gum em cache existem; fora
   disso, pula com aviso (CI sem TTY não tem pty do gum garantido).

## 4. A FRENTE SEGUINTE — F4 em diante (ordem)

1. **Sondar o VBoxManage REAL do Mac mini** (por SSH, máquina ligada):
   `VBoxManage list ostypes | grep -i linux`, `VBoxManage storagectl --help`
   (o `--add virtio-scsi` é DOC-GAP), `VBoxManage list bridgedifs`. Nunca
   fixar argumento sem sondar — regra do CLAUDE.md.
2. **F4** criar a VM (createvm/modifyvm/storagectl/storageattach com o .vdi
   já no lugar) — com inverso no `--uninstall` e chave no manifesto.
3. **F5** boot + espera do lease/mDNS; **F5b** LaunchAgent de auto-start.
4. Depois: F6 onboarding · F7 add-ons via WebSocket `supervisor/api` (helper
   Python; slugs `<repo>_<app>`; hash do repo community NUNCA fixo) · F8
   integrações · F9 pacotes casa (embutidos via `embed.sh`) · F10 relatório
   com `http://homeassistant.local:8123` + navegador aberto.

## 5. DÍVIDAS DECLARADAS (inalteradas + novas)

1. `listar()` cabeçalhos pt hardcoded · 2. `versao()` com `·` multibyte ·
3. `0/100/1` não universal · 4. Extension Pack fora do uninstall ·
5. `HAOS_LANG=pt` sob locale C · 6. `--upgrade/--upgrade-only` e remoção por
item esperam F7–F9. · 7. **Flake observado na cerca do cardápio**
(24/08): `padroes-por-vazio` reprovou 1 vez em 3 rodadas do portão; o cenário
passa isolado (3 ocorrências de Casa) e o portão limpou na reexecução. Causa
não diagnosticada — se repetir, capturar `$CARD_SAIDA` da rodada que falhou
antes de mexer.

## 6. REGRAS QUE CUSTARAM CARO (não reaprender)

- **Teste pelo cano, NUNCA pelo clone** — o one-liner é o produto; instrução
  com `cd ~/haos-mac-mini` está errada por definição.
- **`embed.sh` imediatamente após QUALQUER edição na lib**, antes de testar.
- **Portão CONDICIONA o commit no mesmo comando** (`gate.sh && git commit`),
  depois do `git add` (a cerca de segredo varre o índice).
- **Edição por python sem assert (ou sem fechar parêntese) falha em
  silêncio** — usar o Edit; se python, assert em tudo. Custou duas vezes:
  função velha convivendo com call-sites novos, e o CHANGELOG que ficou fora
  do commit e191e77.
- **Tecla de UI se prova com expect num pty**, não de memória.

## 7. Pendências do dono

- Trocar a senha da HGU que passou pelo chat (depois eu atualizo
  `PROCEDIMENTO.md` e `01-coleta-hg8141xr.sh` do cutover).

## 8. PROMPT DE RETOMADA (colar após /clear)

```
Retome a frente do instalador haos-mac-mini. Leia PRIMEIRO
docs/roadmap/HANDOFF-2026-08-24-pos-teste-campo.md e as memórias do projeto.
Estado: F1–F3 reais concluídas no Mac mini (VirtualBox 7.2.16 instalado,
.vdi verificado no lugar, seleção salva). Próximo passo: F4 — antes de
escrever qualquer linha, sondar o VBoxManage real do Mac mini por SSH
(list ostypes, storagectl --help, list bridgedifs) e só então desenhar a
criação da VM, com inverso no --uninstall e chave no manifesto. Portão antes
de todo commit, na mesma cadeia. Push só sob ordem.
```
