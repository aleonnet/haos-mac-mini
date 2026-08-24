#!/usr/bin/env bash
# shellcheck disable=SC2034
# SC2034: o padrão IFS='|' read descompacta todos os campos dos registros do
#         catálogo mesmo quando nem todos são usados numa dada função.
# =============================================================================
# haos-install.sh — instala Home Assistant OS numa VM VirtualBox em Mac Apple
#                   Silicon.
#
# Local:  bash haos-install.sh [opções]
# Remoto: curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash -s -- [opções]
#
# Sem opções e com terminal: sonda a máquina, oferece o seletor, mostra o plano
# e pede confirmação. Nada é escrito antes disso.
#
# Licença MIT. https://github.com/aleonnet/haos-mac-mini
# =============================================================================
set -Eeuo pipefail

HAOS_INSTALL_VERSION="0.3.0"
HAOS_REF_CORE="2026.8.3"      # versão do HA contra a qual o contrato foi verificado
HAOS_REF_OS="18.2"
HAOS_RAW_URL="https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh"

# ── imagem do HAOS ───────────────────────────────────────────────────────────
# versão|URL|SHA-256|bytes
#
# O hash vive AQUI porque o GitHub não publica um .sha256 ao lado do asset —
# medido em 23/08: o `<url>.sha256` responde 404. Sem hash de origem não há
# como separar download truncado de imagem adulterada, e um .vdi corrompido só
# se manifestaria no boot da VM, tarde demais e com erro incompreensível.
#
# O tamanho é conferido ANTES do hash: é comparação de metadado, não leitura de
# 380 MiB, e descarta o caso comum (arquivo pela metade) sem custo.
HAOS_IMAGE_DB=(
"18.2|https://github.com/home-assistant/operating-system/releases/download/18.2/haos_generic-aarch64-18.2.vdi.zip|cd2d6b2336b50e7a47d548862f6271db78c8563afb3fdd8bd4a6a59f02639787|397964849"
)

# Exit codes — convenção do projeto:
#   0 ok · 2 uso incorreto · 3 validação · 4 dependência ausente · 10 conexão
#   130 cancelado pelo usuário
E_USO=2; E_VALID=3; E_DEP=4; E_CONEXAO=10; E_CANCELADO=130

# =============================================================================
# F0 — PREÂMBULO
# =============================================================================

# ── limpeza ──────────────────────────────────────────────────────────────────
# Um único trap, do instalador. Bibliotecas não instalam trap: `trap` é global
# do shell e quem chama por último vence — um trap dentro de lib APAGARIA este,
# em silêncio, levando junto a limpeza de temporários e o desfazer de fase.
TMPFILES=()
FASE_ATUAL=""
VBOX_PONTO=""
limpar() {
    local rc=$?
    local f
    # SMB desmonta ANTES do rm dos temporários: o ponto de montagem mora num
    # mktempdir, e um rm -rf com o SMB ainda montado apagaria o /config da VM.
    # E sempre por AQUI, nunca por trap local (trap é global, o último vence).
    if [ -n "${SMB_PONTO:-}" ] && declare -F desmontar_smb >/dev/null 2>&1; then
        desmontar_smb
    fi
    for f in "${TMPFILES[@]:-}"; do
        if [ -n "$f" ]; then rm -rf "$f" 2>/dev/null || true; fi
    done
    # Imagem montada também é sujeira, e some do radar com facilidade.
    if [ -n "$VBOX_PONTO" ]; then desmontar "$VBOX_PONTO"; fi
    if declare -F ha_show_cursor >/dev/null 2>&1; then
        ha_show_cursor
    elif [ -t 1 ]; then
        tput cnorm 2>/dev/null || true
    fi
    # O espelho da execução sai AQUI, no trap: uma execução que morre no meio é
    # exatamente a que mais precisa de registro. Dry-run e os modos que só leem
    # nunca chegam a MAIN_INICIADO=1, então não escrevem nada.
    if [ "${MAIN_INICIADO:-0}" = "1" ] && [ "${OP_DRYRUN:-0}" != "1" ]; then
        escrever_last_run "$rc" || true
    fi
    if [ "$rc" != "0" ] && [ -n "$FASE_ATUAL" ] && [ "${MAIN_INICIADO:-0}" = "1" ]; then
        printf '\n%s\n' "$(msg interrompido "$FASE_ATUAL")" >&2
        printf '%s\n' "$(msg reexecutar_seguro)" >&2
        if [ -n "${LOG_FILE:-}" ] && [ -s "${LOG_FILE:-/nonexistent}" ]; then
            printf '%s\n' "$(msg log_em "$LOG_FILE")" >&2
        fi
    fi
    # Sucesso limpa o log; falha o preserva — ele acabou de ser nomeado acima.
    if [ "$rc" = "0" ] && [ -n "${LOG_FILE:-}" ]; then
        rm -f "$LOG_FILE" 2>/dev/null || true
    fi
    exit "$rc"
}
# O trap é REGISTRADO lá embaixo, depois da guarda de biblioteca: instalar um
# trap de EXIT aqui vazaria para quem faz `source` deste arquivo (a bancada).

mktempfile() { local f; f="$(mktemp)"; TMPFILES+=("$f"); printf '%s' "$f"; }
mktempdir()  { local d; d="$(mktemp -d)"; TMPFILES+=("$d"); printf '%s' "$d"; }

# ── idioma ───────────────────────────────────────────────────────────────────
# pt-BR quando o locale do Mac for português; en-US no resto. Uma chave sem par
# nas duas línguas é erro de CI, não string faltando em runtime.
IDIOMA="en"
case "${LANG:-}${LC_ALL:-}" in *pt_BR*|*pt_PT*|*pt*) IDIOMA="pt" ;; esac
[ "${HAOS_LANG:-}" = "pt" ] && IDIOMA="pt"
[ "${HAOS_LANG:-}" = "en" ] && IDIOMA="en"

msg() {
    local chave="$1"; shift
    local linha pt en
    for linha in "${MSG_DB[@]}"; do
        case "$linha" in "$chave|"*)
            linha="${linha#*|}"; pt="${linha%%|*}"; en="${linha#*|}"
            # `printf --` é obrigatório: mensagem que começa com "--" (ex.:
            # "--dry-run: nada foi escrito") seria lida como opção do printf.
            # shellcheck disable=SC2059
            [ "$IDIOMA" = "pt" ] && printf -- "$pt" "$@" || printf -- "$en" "$@"
            return 0 ;;
        esac
    done
    printf '%s' "$chave"   # chave desconhecida aparece crua, não some
}

MSG_DB=(
"cabecalho|Instalador de Home Assistant OS para Mac|Home Assistant OS installer for Mac"
"preflight|Pré-voo|Pre-flight"
"selecao|Seleção|Selection"
"plano|Plano|Plan"
"so_apple_silicon|Este instalador é só para Mac com Apple Silicon (a imagem do HAOS é aarch64). Detectado: %s|This installer is for Apple Silicon Macs only (the HAOS image is aarch64). Detected: %s"
"so_macos|Este instalador é só para macOS. Detectado: %s|This installer is for macOS only. Detected: %s"
"sem_vbox|VirtualBox não encontrado.|VirtualBox not found."
"vbox_versao|VirtualBox %s|VirtualBox %s"
"vbox_antigo|VirtualBox %s é anterior à 7.1, que trouxe host ARM e --platform-architecture. Atualize.|VirtualBox %s predates 7.1, which introduced ARM hosts and --platform-architecture. Please upgrade."
"sem_python|python3 não encontrado. É dependência real: instalar app no Home Assistant exige o comando WebSocket supervisor/api, e bash não fala WebSocket.|python3 not found. This is a hard dependency: installing add-ons requires the supervisor/api WebSocket command, and bash cannot speak WebSocket."
"sem_python_como|  Instale as Command Line Tools:  xcode-select --install|  Install the Command Line Tools:  xcode-select --install"
"disco_curto|Espaço livre insuficiente em %s: %s MiB. A imagem do HAOS precisa de pelo menos %s MiB.|Not enough free space on %s: %s MiB. The HAOS image needs at least %s MiB."
"sem_rede|Sem acesso à internet. O primeiro boot do HAOS baixa o Core, e os fluxos de nuvem falham sem rede — e falham de um jeito indistinguível de credencial errada.|No internet access. The first HAOS boot downloads Core, and cloud flows fail without network - in a way indistinguishable from a wrong credential."
"aviso_ram|Memória disponível agora: %s MiB. O perfil escolhido pede %s MiB. Pode faltar sob carga.|Memory available right now: %s MiB. The chosen profile asks for %s MiB. It may fall short under load."
"aviso_wifi|Só há interface Wi-Fi. A VM usa bridge, e sobre 802.11 o quadro com MAC de origem alheio costuma ser descartado: a VM pode não obter endereço. Se falhar, use um adaptador USB-Ethernet.|Only Wi-Fi interfaces found. The VM uses bridged networking, and over 802.11 a frame with a foreign source MAC is usually dropped: the VM may not get an address. If it fails, use a USB-Ethernet adapter."
"sem_interface|Nenhuma interface de rede utilizável.|No usable network interface."
"maquina|Máquina|Machine"
"memoria|Memória|Memory"
"disco|Disco|Disk"
"rede|Rede|Network"
"cabeada|cabeada|wired"
"sem_fio|sem fio|wireless"
"perfil_vm|Perfil da VM|VM profile"
"degrau|Degrau|Tier"
"ortogonais|Extras|Extras"
"itens|itens|items"
"nada_escrito|--dry-run: nada foi escrito.|--dry-run: nothing was written."
"sem_tty_titulo|Sem terminal interativo.|No interactive terminal."
"sem_tty_como|Passe um degrau, por exemplo:|Pass a tier, for example:"
"cancelado|Cancelado.|Cancelled."
"confirmar|Instalar agora? [s/N] |Install now? [y/N] "
"portoes_pendentes|%s pré-requisito(s) não atendido(s). O plano acima é o que aconteceria depois de resolvê-los.|%s prerequisite(s) not met. The plan above is what would happen once they are resolved."
"piso_sempre|Piso: %s componentes que a própria instalação cria — não são escolha.|Floor: %s components the installation creates by itself - not a choice."
"nada_alem_do_piso|(nada além do piso; os itens deste degrau são opt-in)|(nothing beyond the floor; this tier is opt-in)"
"sem_sudo|sudo não encontrado.|sudo not found."
"pede_senha|O próximo passo instala o VirtualBox e precisa da senha de administrador. Quem pergunta é o sudo; o instalador não guarda nem repassa a senha.|The next step installs VirtualBox and needs the administrator password. sudo is what asks; this installer never stores or forwards it."
"sudo_sem_tty|sudo precisa de senha e não há terminal interativo. Rode \x27sudo -v\x27 antes, ou use --install-deps num terminal.|sudo needs a password and there is no interactive terminal. Run \x27sudo -v\x27 first, or use --install-deps from a terminal."
"vbox_ausente|VirtualBox não encontrado.|VirtualBox not found."
"vbox_dmg_cache|Instalador do VirtualBox já em cache, hash conferido: %s|VirtualBox installer already cached, hash verified: %s"
"vbox_instalar|Baixar e instalar o VirtualBox %s da Oracle?|Download and install Oracle VirtualBox %s?"
"vbox_baixando|Baixando VirtualBox %s (~153 MB)...|Downloading VirtualBox %s (~153 MB)..."
"vbox_download_falhou|Falha ao baixar o VirtualBox.|Failed to download VirtualBox."
"vbox_sem_sha|Não consegui obter o SHA256SUMS da Oracle — sem ele não instalo.|Could not fetch Oracle SHA256SUMS - refusing to install without it."
"vbox_sha_diverge|O SHA-256 do arquivo baixado NÃO confere com o publicado pela Oracle.|The downloaded file SHA-256 does NOT match the one Oracle publishes."
"vbox_sha_ok|SHA-256 confere com o publicado pela Oracle|SHA-256 matches the one Oracle publishes"
"vbox_mount_falhou|Não consegui montar a imagem.|Could not mount the disk image."
"vbox_sem_pkg|A imagem não contém o pacote de instalação.|The image contains no installer package."
"vbox_instalando|Instalando (installer -pkg, sem interface gráfica)...|Installing (installer -pkg, no GUI)..."
"vbox_installer_falhou|O installer(8) falhou. Rode com --verbose para ver a saída.|installer(8) failed. Run with --verbose to see the output."
"vbox_ok|VirtualBox %s instalado|VirtualBox %s installed"
"vbox_bloqueado|VirtualBox instalado, mas o VBoxManage não responde. O macOS costuma BLOQUEAR a extensão de sistema da Oracle na primeira instalação: abra Ajustes do Sistema, Privacidade e Segurança, e Permitir o software da Oracle. Pode exigir reinício. Depois rode este instalador de novo.|VirtualBox installed, but VBoxManage does not respond. macOS usually BLOCKS the Oracle system extension on first install: open System Settings, Privacy & Security, and Allow the Oracle software. A restart may be required. Then run this installer again."
"vbox_nao_desmontou|Não consegui desmontar %s — algum processo ainda a segura. Desmonte com: hdiutil detach -force %s|Could not unmount %s - some process still holds it. Unmount with: hdiutil detach -force %s"
"subtitulo|numa VM VirtualBox no Mac|on a VirtualBox VM on Mac"
"nao_implementado|As fases de execução ainda não estão implementadas nesta versão (%s).|Execution phases are not implemented yet in this version (%s)."
"imagem|Imagem|Image"
"img_sem_tabela|Não há imagem catalogada para a versão %s do HAOS.|No image catalogued for HAOS version %s."
"img_ja|Imagem %s já está em %s — nada a baixar.|Image %s already at %s - nothing to download."
"img_local|Encontrei o arquivo local %s e o hash confere: não vou baixar de novo.|Found local file %s and the hash matches: not downloading again."
"img_local_descartado|O arquivo local %s não confere com a tabela e foi ignorado.|Local file %s does not match the table and was ignored."
"img_baixando|Baixando a imagem do HAOS %s — %s MiB.|Downloading the HAOS %s image - %s MiB."
"img_download_falhou|Falhou o download da imagem do HAOS.|HAOS image download failed."
"img_sem_baixador|Nem curl nem wget estão disponíveis para baixar a imagem.|Neither curl nor wget is available to download the image."
"img_sem_unzip|O comando unzip não está disponível, e a imagem vem compactada.|The unzip command is unavailable, and the image ships compressed."
"img_tamanho_diverge|A imagem baixada tem %s bytes; a tabela diz %s. Download incompleto.|The downloaded image has %s bytes; the table says %s. Incomplete download."
"img_sha_ok|SHA-256 da imagem confere.|Image SHA-256 matches."
"img_sha_diverge|O SHA-256 da imagem NÃO confere. Não vou descompactar.|The image SHA-256 does NOT match. Not extracting."
"img_descompactando|Descompactando a imagem.|Extracting the image."
"img_sem_vdi|O arquivo compactado não contém nenhum .vdi.|The archive contains no .vdi file."
"img_pronta|Imagem pronta: %s|Image ready: %s"
"interrompido|Interrompido na fase %s. Nada além dela foi alterado.|Interrupted during phase %s. Nothing beyond it was changed."
"reexecutar_seguro|Reexecutar é seguro: o instalador continua de onde parou.|Re-running is safe: the installer continues from where it stopped."
"log_em|Saída das ferramentas desta execução: %s|Tool output of this run: %s"
"log_ultimas|últimas linhas do log (%s):|last log lines (%s):"
"rede_titulo|Isto parece problema de REDE, não da sua máquina:|This looks like a NETWORK problem, not a problem with your machine:"
"rede_dica1|verifique a conexão — VPN, proxy e firewall são os suspeitos de sempre|check your connection - VPN, proxy or firewall are the usual suspects"
"rede_dica2|nada ficou pela metade: rodar o mesmo comando de novo continua de onde parou|nothing was left half-done: running the same command again continues from where it stopped"
"flag_sem_valor|%s exige um valor|%s requires a value"
"opcao_desconhecida|opção desconhecida: %s|unknown option: %s"
"python3_versao|python3 %s|python3 %s"
"fase_vm|VM|VM"
"relatorio_salvo|Relatório da execução: %s|Run report: %s"
"img_image_invalida|O arquivo passado em --image não confere com a tabela (tamanho ou SHA-256): %s|The file passed to --image does not match the table (size or SHA-256): %s"
"last_sem_estado|--profile last: nenhuma seleção salva em %s. Rode uma instalação primeiro.|--profile last: no saved selection at %s. Run an install first."
"last_repetindo|Repetindo a última seleção salva.|Repeating the last saved selection."
"doc_sistema|Sistema|System"
"doc_prereq|Pré-requisitos|Prerequisites"
"doc_manifesto|Manifesto — o que este instalador criou|Manifest - what this installer created"
"doc_imagem|Imagem|Image"
"doc_estado|Estado local|Local state"
"doc_maquina|%s (%s) - macOS %s|%s (%s) - macOS %s"
"doc_vbox_ok|VirtualBox %s|VirtualBox %s"
"doc_vbox_falta|VirtualBox ausente - o instalador o instala com sua confirmação|VirtualBox missing - the installer installs it with your confirmation"
"doc_py_ok|python3 %s|python3 %s"
"doc_py_falta|python3 ausente - só você resolve: xcode-select --install|python3 missing - only you can fix it: xcode-select --install"
"doc_sem_manifesto|nenhum manifesto - nada aqui foi criado por este instalador (ou já foi removido)|no manifest - nothing here was created by this installer (or it was already removed)"
"doc_vdi_ok|imagem pronta: %s|image ready: %s"
"doc_vdi_falta|imagem ainda não preparada para a VM %s|image not prepared yet for VM %s"
"doc_state_ok|seleção salva: %s|saved selection: %s"
"doc_state_falta|nenhuma seleção salva (--profile last ainda não funciona aqui)|no saved selection (--profile last will not work here yet)"
"doc_lastrun_ok|último relatório: %s|last report: %s"
"doc_veredito|%s ok - %s a observar - %s com problema|%s ok - %s to watch - %s broken"
"un_plano_titulo|Plano de remoção|Removal plan"
"un_remove|SERÁ REMOVIDO|WILL BE REMOVED"
"un_keep|SERÁ PRESERVADO|WILL BE PRESERVED"
"un_nada|nada a fazer - nenhum artefato deste instalador nesta máquina.|nothing to do - no artifact of this installer on this machine."
"un_vdi|imagem %s (criada por este instalador)|image %s (created by this installer)"
"un_zip|cache %s (baixado por este instalador)|cache %s (downloaded by this installer)"
"un_registro|registro do instalador (manifesto, seleção, relatório)|installer bookkeeping (manifest, selection, report)"
"un_dirvm|pasta %s - só sai se ficar vazia|folder %s - removed only if it ends up empty"
"un_vbox_created|VirtualBox foi instalado por este instalador, mas NÃO é removido automaticamente: é extensão de sistema. Use o VirtualBox_Uninstall.tool dentro do .dmg da Oracle.|VirtualBox was installed by this installer but is NOT removed automatically: it is a system extension. Use the VirtualBox_Uninstall.tool inside Oracle's .dmg."
"un_vbox_pre|VirtualBox já existia antes deste instalador - preservado|VirtualBox predates this installer - preserved"
"un_pendente|%s: instalação interrompida no meio, sem prova de que fomos nós - preservado|%s: install interrupted mid-way, no proof we created it - preserved"
"un_keep_image_msg|imagem preservada a seu pedido (--keep-image)|image kept at your request (--keep-image)"
"un_preexisting|%s: não foi este instalador que criou - preservado|%s: not created by this installer - preserved"
"un_confirmar|Executar o plano acima? [s/N] |Execute the plan above? [y/N] "
"un_sem_tty|Sem terminal: confirme com --confirm=<nome-da-vm> (o nome exato, não um sim).|No terminal: confirm with --confirm=<vm-name> (the exact name, not a yes)."
"un_confirm_errado|--confirm=%s não bate com o nome da VM (%s) - nada foi tocado.|--confirm=%s does not match the VM name (%s) - nothing was touched."
"un_removido|removido: %s|removed: %s"
"un_nao_removido|falhou ao remover: %s|failed to remove: %s"
"un_placar|%s removido(s) - %s preservado(s)|%s removed - %s preserved"
"su_pipe|Execução via pipe usa sempre a versão remota - nada a atualizar aqui.|Running via a pipe always uses the remote version - nothing to update here."
"su_baixa_falhou|Falha ao baixar a versão remota.|Failed to download the remote version."
"su_invalido|Download remoto inválido (bash -n reprovou) - abortado.|Remote download is invalid (bash -n failed) - aborted."
"su_downgrade|A versão remota (%s) é MAIS ANTIGA que a local (%s) - recusado: rebaixar apagaria o que você já tem. Publique a local primeiro.|Remote version (%s) is OLDER than local (%s) - refused: downgrading would erase what you already have. Publish the local one first."
"su_igual|Já está na versão publicada (%s).|Already at the published version (%s)."
"su_confirma|Atualizar %s para %s? [s/N] |Update %s to %s? [y/N] "
"su_ok|Atualizado para %s (backup em %s).|Updated to %s (backup at %s)."
"sel_degrau_titulo|Qual degrau instalar? (os degraus somam)|Which tier to install? (tiers stack)"
"sel_op_repetir|  0) Repetir a última: %s|  0) Repeat the last one: %s"
"sel_op_vanilla|  1) Vanilla    - só o piso, o que o HAOS cria sozinho|  1) Vanilla    - floor only, what HAOS creates by itself"
"sel_op_conectado|  2) Conectado  - + MQTT, Matter, Thread, ESPHome, Cast|  2) Conectado  - + MQTT, Matter, Thread, ESPHome, Cast"
"sel_op_casa|  3) Casa       - + Hue, Tuya, Shelly, TP-Link, SmartThings (recomendado)|  3) Casa       - + Hue, Tuya, Shelly, TP-Link, SmartThings (recommended)"
"sel_prompt_degrau|Degrau [3]: |Tier [3]: "
"sel_extras_titulo|Extras (entram em qualquer degrau; separe por vírgula):|Extras (added on any tier; comma-separated):"
"sel_op_ferramentas|  a) ferramentas - SSH e Web Terminal, File editor, Samba|  a) ferramentas - SSH and Web Terminal, File editor, Samba"
"sel_op_abhome|  b) casa_abhome - custos BR na fatura: energia, gás, água|  b) casa_abhome - BR utility costs: energy, gas, water"
"sel_op_hacs|  c) extensoes   - HACS (código de terceiros; sempre opt-in)|  c) extensoes   - HACS (third-party code; always opt-in)"
"sel_prompt_extras|Extras [nenhum]: |Extras [none]: "
"sel_vm_titulo|Perfil da VM:|VM profile:"
"sel_op_vm1|  1) Mínimo      - 2048 MiB - 2 vCPU (doc oficial)|  1) Minimal     - 2048 MiB - 2 vCPU (official doc)"
"sel_op_vm2|  2) Equilibrado - 4096 MiB - 2 vCPU (recomendado)|  2) Balanced    - 4096 MiB - 2 vCPU (recommended)"
"sel_op_vm3|  3) Desta máquina - %s MiB - %s vCPU (derivado da sonda)|  3) This machine - %s MiB - %s vCPU (derived from the probe)"
"sel_prompt_vm|VM [2]: |VM [2]: "
"sel_invalida|não entendi %s|did not understand %s"
"gum_ok|seletor rico carregado (gum %s, SHA-256 verificado, temporário)|rich selector loaded (gum %s, SHA-256 verified, temporary)"
"gum_fallback|seletor rico indisponível (%s) - usando o seletor simples|rich selector unavailable (%s) - using the simple one"
"sel_gum_degrau|Qual degrau instalar? (os degraus somam)|Which tier to install? (tiers stack)"
"sel_gum_op_repetir|Repetir a última: %s|Repeat the last one: %s"
"sel_gum_op_vanilla|Vanilla - só o piso, o que o HAOS cria sozinho|Vanilla - floor only, what HAOS creates by itself"
"sel_gum_op_conectado|Conectado - + MQTT, Matter, Thread, ESPHome, Cast|Conectado - + MQTT, Matter, Thread, ESPHome, Cast"
"sel_gum_op_casa|Casa - + Hue, Tuya, Shelly, TP-Link, SmartThings (recomendado)|Casa - + Hue, Tuya, Shelly, TP-Link, SmartThings (recommended)"
"sel_gum_op_perso|Personalizado - escolher componente a componente, com busca|Custom - pick component by component, with search"
"sel_gum_ex_a|ferramentas - SSH e Web Terminal, File editor, Samba|ferramentas - SSH and Web Terminal, File editor, Samba"
"sel_gum_ex_b|casa_abhome - custos BR na fatura: energia, gás, água|casa_abhome - BR utility costs: energy, gas, water"
"sel_gum_ex_c|extensoes - HACS (código de terceiros; sempre opt-in)|extensoes - HACS (third-party code; always opt-in)"
"sel_gum_vm1|vm_minimo - 2048 MiB - 2 vCPU (doc oficial)|vm_minimo - 2048 MiB - 2 vCPU (official doc)"
"sel_gum_vm2|vm_equilibrado - 4096 MiB - 2 vCPU (recomendado)|vm_equilibrado - 4096 MiB - 2 vCPU (recommended)"
"sel_gum_vm3|vm_recomendado - %s MiB - %s vCPU (desta máquina)|vm_recomendado - %s MiB - %s vCPU (this machine)"
"sel_gum_extras|Extras - ESPAÇO marca/desmarca, enter confirma|Extras - SPACE toggles, enter confirms"
"sel_gum_itens|Digite para buscar - TAB marca/desmarca - enter confirma|Type to search - TAB toggles - enter confirms"
"sel_gum_vm|Perfil da VM|VM profile"
"sel_gum_confirmar|Instalar agora?|Install now?"
"sel_gum_sim|Instalar|Install"
"sel_gum_nao|Cancelar|Cancel"
"novidade_script|Instalador %s publicado (este é %s) - atualize com --self-update|Installer %s published (this one is %s) - update with --self-update"
"rel_titulo|Feito até aqui|Done so far"
"rel_instalado|O que ficou instalado nesta máquina:|Installed on this machine:"
"rel_i_vbox|VirtualBox %s - /Applications/VirtualBox.app|VirtualBox %s - /Applications/VirtualBox.app"
"rel_i_vdi|o disco do HAOS, verificado por SHA-256: %s|the HAOS disk, SHA-256 verified: %s"
"rel_i_sel|sua seleção, salva - repita quando quiser com --profile last|your selection, saved - repeat anytime with --profile last"
"rel_i_vm|a VM %s, registrada no VirtualBox e apontando para o disco acima|the %s VM, registered in VirtualBox and pointing at the disk above"
"rel_falta|O que AINDA NÃO acontece: o Home Assistant rodando - nada responde em http://homeassistant.local:8123 ainda. Esta versão (%s) para na VM criada e verificada; o primeiro boot e o navegador são a PRÓXIMA release.|What does NOT happen yet: a running Home Assistant - nothing answers at http://homeassistant.local:8123 yet. This version (%s) stops at the created and verified VM; first boot and the browser are the NEXT release."
"fase_vm|Máquina virtual|Virtual machine"
"vm_ja|A VM %s já existe no VirtualBox - nada a criar.|The %s VM already exists in VirtualBox - nothing to create."
"vm_sem_vbm|VBoxManage não está no PATH nem em /Applications/VirtualBox.app - a fase do VirtualBox precisa vir antes.|VBoxManage is neither on PATH nor in /Applications/VirtualBox.app - the VirtualBox phase must come first."
"vm_sem_vdi|O disco %s não existe - a fase da imagem precisa vir antes.|Disk %s does not exist - the image phase must come first."
"vm_bridge|rede em ponte pela interface: %s|bridged network on interface: %s"
"vm_sem_bridge|Nenhuma interface de rede ativa para a ponte - a VM precisa aparecer na sua rede local para o homeassistant.local funcionar. Conecte o Mac à rede e reexecute.|No active network interface to bridge - the VM must appear on your LAN for homeassistant.local to work. Connect the Mac to the network and rerun."
"vm_criando|criando a VM %s - ARM 64-bit, EFI, %s MiB RAM, %s vCPU|creating the %s VM - ARM 64-bit, EFI, %s MiB RAM, %s vCPU"
"vm_falhou|O VBoxManage recusou um passo da criação - a VM parcial foi desfeita, o disco ficou intacto.|VBoxManage refused a creation step - the partial VM was rolled back, the disk is intact."
"vm_pronta|VM %s criada e verificada - disco SATA conectado, ponte de rede ativa.|%s VM created and verified - SATA disk attached, network bridge on."
"un_vm|a VM %s do VirtualBox (o registro e o arquivo .vbox)|the %s VM in VirtualBox (registration and .vbox file)"
"fase_boot|Boot|Boot"
"boot_sem_vm|A VM %s não está registrada - a fase anterior precisa vir antes.|The %s VM is not registered - the previous phase must come first."
"boot_ja_roda|A VM %s já está rodando.|The %s VM is already running."
"boot_ligando|ligando a VM %s - headless: sem janela, ela vive em segundo plano|starting the %s VM - headless: no window, it lives in the background"
"boot_esperando|esperando o HAOS aparecer na rede (MAC %s) - o primeiro boot leva alguns minutos|waiting for HAOS to show up on the network (MAC %s) - first boot takes a few minutes"
"boot_no_ar|HAOS no ar: %s responde.|HAOS is up: %s answers."
"boot_timeout|O HAOS não respondeu em %s s. A VM está ligada - confira a rede em ponte e o cabo, ou reexecute para esperar de novo.|HAOS did not answer within %s s. The VM is on - check the bridged network and cable, or rerun to wait again."
"boot_autostart_ok|auto-start no login instalado: a VM sobe sozinha quando você entrar no Mac|login auto-start installed: the VM comes up by itself when you log into the Mac"
"boot_autostart_ja|auto-start no login já instalado.|login auto-start already installed."
"un_agent|o auto-start do login (%s)|the login auto-start (%s)"
"vm_nome_invalido|--vm-name aceita só letras, números, ponto, hífen e sublinhado (até 64, sem ponto inicial) - o nome entra em caminhos e no launchd.|--vm-name accepts only letters, digits, dot, hyphen and underscore (max 64, no leading dot) - the name goes into paths and launchd."
"fase_conta|Conta|Account"
"conta_pede|Crie a conta administradora do SEU Home Assistant - ela vive só na VM.|Create the admin account of YOUR Home Assistant - it lives only in the VM."
"conta_usuario|usuário [%s]: |username [%s]: "
"conta_senha|senha (digitar não aparece): |password (typing is hidden): "
"conta_senha2|repita a senha: |repeat the password: "
"conta_senha_diferente|As senhas não conferem - de novo.|Passwords do not match - try again."
"conta_senha_vazia|Senha vazia não vale.|Empty password is not allowed."
"conta_sem_credencial|Sem terminal para perguntar: defina HAOS_HA_USER e HAOS_HA_PASSWORD no ambiente e reexecute.|No terminal to ask on: set HAOS_HA_USER and HAOS_HA_PASSWORD in the environment and rerun."
"conta_criada|conta %s criada, onboarding concluído - envio de analytics DESLIGADO.|account %s created, onboarding finished - analytics reporting OFF."
"conta_ja|onboarding já concluído - credencial validada.|onboarding already done - credential validated."
"conta_falhou|O onboarding falhou - veja o log.|Onboarding failed - see the log."
"fase_apps|Apps|Add-ons"
"apps_nada|nenhum app na seleção - nada a fazer.|no add-ons selected - nothing to do."
"apps_instalando|garantindo %s - instalar pode levar minutos|ensuring %s - install can take minutes"
"apps_ok|%s instalado e rodando.|%s installed and running."
"apps_ja|%s já instalado e rodando.|%s already installed and running."
"apps_falhou|%s falhou - veja o log.|%s failed - see the log."
"fase_int|Integrações|Integrations"
"int_ok|%s configurado - só padrões, nenhum dado seu.|%s configured - defaults only, no data from you."
"int_ja|%s já configurado.|%s already configured."
"int_espera|%s espera VOCÊ no painel (pede credencial ou escolha) - nada foi criado.|%s waits for YOU in the panel (needs credentials or a choice) - nothing was created."
"int_falhou|%s falhou - veja o log.|%s failed - see the log."
"int_flows|sua rede já acena: %s descoberta(s) esperando no painel (%s)|your network is waving: %s discovery(ies) waiting in the panel (%s)"
"fase_arq|Arquivos|Files"
"arq_nada|nenhum arquivo a colocar em /config - nada a fazer.|no files to put into /config - nothing to do."
"arq_montou|/config montado via Samba - escrevendo os arquivos.|/config mounted via Samba - writing the files."
"arq_mount_falhou|Não montei o /config por SMB - o app Samba está rodando? Veja o log.|Could not mount /config over SMB - is the Samba add-on running? See the log."
"arq_pkg_ok|package %s escrito.|package %s written."
"arq_pkg_ja|package %s já em dia.|package %s up to date."
"arq_conf_ok|configuration.yaml agora carrega packages/ - backup ao lado.|configuration.yaml now loads packages/ - backup next to it."
"arq_conf_ja|configuration.yaml já carrega packages/.|configuration.yaml already loads packages/."
"arq_conf_estranho|configuration.yaml tem um bloco homeassistant: que não reconheço - não vou adivinhar. Acrescente a ele:   packages: !include_dir_named packages|configuration.yaml has a homeassistant: block I do not recognize - not guessing. Add to it:   packages: !include_dir_named packages"
"arq_hacs_ok|HACS %s colocado em custom_components - termine no painel (fluxo do GitHub).|HACS %s placed into custom_components - finish in the panel (GitHub flow)."
"arq_hacs_ja|HACS já instalado.|HACS already installed."
"arq_hacs_falhou|O download do HACS não conferiu (SHA-256) - NÃO instalei.|The HACS download did not verify (SHA-256) - NOT installed."
"arq_check_falhou|O check de configuração reprovou - configuration.yaml restaurado do backup.|Config check failed - configuration.yaml restored from the backup."
"arq_restart|reiniciando o Core para carregar os arquivos novos|restarting Core to load the new files"
"arq_voltou|Core de volta no ar.|Core back up."
"arq_nao_voltou|O Core não voltou em %s s - abra o endereço e confira; os arquivos ficaram escritos.|Core did not come back within %s s - open the address and check; the files stayed written."
"rel_url|Seu Home Assistant está NO AR: %s|Your Home Assistant is UP: %s"
"rel_url_aviso|homeassistant.local pode apontar para OUTRO Home Assistant se você já tem um - confie no endereço acima.|homeassistant.local may point at ANOTHER Home Assistant if you already have one - trust the address above."
"rel_samba|arquivos da VM no Finder: smb://haos@%s/config - senha: %s|VM files in Finder: smb://haos@%s/config - password: %s"
"rel_ssh_chave|a chave ~/.ssh/haos-mac-mini dá acesso administrativo (SSH) à VM.|the ~/.ssh/haos-mac-mini key gives administrative (SSH) access to the VM."
"rel_flows|%s descoberta(s) da sua rede esperando você no painel.|%s discovery(ies) from your network waiting for you in the panel."
"rel_hacs_prox|HACS: termine no painel - Configurações > Dispositivos e serviços.|HACS: finish in the panel - Settings > Devices and services."
"rel_abrindo|abrindo no navegador...|opening in the browser..."
"rel_tempo|concluído em %s|done in %s"
"prox_relatorio|relatório desta execução: %s|this run's report: %s"
"novidade_haos|HAOS %s publicado; esta versão instala a %s fixada (a tabela atualiza em release futura)|HAOS %s published; this version installs the pinned %s (the table updates in a future release)"
)

# ── saída ────────────────────────────────────────────────────────────────────
# UMA gramática visual: a calha da camada embutida (ha_ok · ha_info · ha_warn ·
# ha_err · ha_skip), a mesma dos dois instaladores irmãos. Os glifos degradam
# para ASCII sob locale não-UTF-8 e a cor some sem TTY/NO_COLOR — nenhuma
# informação vive só na cor. A voz antiga, de prefixos textuais em funções
# próprias, era uma segunda gramática no mesmo produto, e o verify.sh agora
# reprova a volta dela. As definições vivem na camada visual embutida, mais
# abaixo; bash resolve função em runtime, então a ordem no arquivo não importa.

# ha_fase <título> — cabeçalho de fase que também alimenta o estado global:
# FASE_ATUAL é o que a mensagem de interrupção do limpar() imprime, e a barra
# de fase da calha anda junto. A camada visual não conhece esse estado — é o
# instalador que o mantém (achado da banca: mover fase() para a lib perderia
# FASE_ATUAL em silêncio).
ha_fase() {
    FASE_ATUAL="$1"
    HA_BAR_N=$(( ${HA_BAR_N:-0} + 1 ))
    ha_phase "$1"
}

morrer() { local code="$1"; shift; ha_err "$*"; exit "$code"; }

# Em --dry-run, portão duro não aborta: reporta e segue, para o operador
# conseguir VER o plano numa máquina que ainda não tem tudo. Achado R5 da banca:
# o único modo que existe para inspecionar a ferramenta não pode exigir que a
# máquina já esteja pronta.
PORTOES_ABERTOS=0
portao() {
    local code="$1"; shift
    if [ "$OP_DRYRUN" = "1" ]; then
        ha_warn "$*"
        PORTOES_ABERTOS=$(( PORTOES_ABERTOS + 1 ))
        return 0
    fi
    ha_err "$*"; exit "$code"
}

# ── terminal interativo ──────────────────────────────────────────────────────
# Testa /dev/tty, NUNCA stdin: em `curl | bash` stdin é o cano, e testar stdin
# faria o instalador se declarar não-interativo justamente no modo em que é
# distribuído. -r/-w não bastam — sessão detached falha no open.
tem_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ] || return 1
    ( : </dev/tty ) 2>/dev/null || return 1
    return 0
}
perguntar() {
    local prompt="$1" resp=""
    tem_tty || return 1
    # Prompt no STDOUT (a mesma tela onde a calha vive) e leitura do terminal
    # real; a barra fica suspensa enquanto a pergunta existe — prompt e barra
    # disputando a última linha foi o defeito medido no primeiro teste real.
    ha_bar_suspende
    ha_ask "$prompt"
    IFS= read -r resp < "$TTY_DEV" || true
    ha_bar_retoma
    [[ "${resp:-N}" =~ ^[sSyY]$ ]]
}

# ── sudo ─────────────────────────────────────────────────────────────────────
# A credencial é PRIMADA antes, uma vez só, lendo o terminal de verdade. Sem
# isso um prompt de senha cairia dentro de um passo com spinner e travaria — e
# em `curl | bash` stdin é o cano, então tem de vir de $TTY_DEV.
# O instalador NUNCA guarda, ecoa ou passa a senha adiante: quem pergunta é o
# sudo, e o cache é do sistema.
TTY_DEV="${TTY_DEV:-/dev/tty}"

garantir_sudo() {
    [ "$(id -u)" = "0" ] && return 0
    command -v sudo >/dev/null 2>&1 || { ha_err "$(msg sem_sudo)"; return 1; }
    if sudo -n true 2>/dev/null; then return 0; fi
    if [ -r "$TTY_DEV" ]; then
        ha_bar_suspende
        ha_info "$(msg pede_senha)"
        # shellcheck disable=SC2024
        # O aviso é sobre redirecionar SAÍDA com sudo. Aqui o redirecionamento é
        # de ENTRADA, e é o ponto: o sudo tem de ler a senha do terminal real,
        # porque em `curl | bash` o stdin do script é o cano.
        sudo -v < "$TTY_DEV" || { ha_bar_retoma; return 1; }
        ha_bar_retoma
        return 0
    fi
    ha_err "$(msg sudo_sem_tty)"
    return 1
}

# confirmar "pergunta" — 0 = sim. Lê o terminal real, seguro sob `curl | bash`.
# Sem TTY: só --install-deps ou --no-input decidem; o padrão é não.
confirmar_dep() {
    local q="$1" r=""
    [ "$OP_INSTALL_DEPS" = "1" ] && return 0
    [ -r "$TTY_DEV" ] || return 1
    [ "$OP_NOINPUT" = "1" ] && return 1
    ha_bar_suspende
    ha_ask "$q [s/N] "
    IFS= read -r r < "$TTY_DEV" || true
    ha_bar_retoma
    case "${r:-N}" in s|S|y|Y) return 0 ;; *) return 1 ;; esac
}

# ── VirtualBox ───────────────────────────────────────────────────────────────
# Contrato de retorno: 0 instalou agora · 100 já estava · 1 falhou.
#
# Por que o .dmg da Oracle e não o Homebrew: o cask apenas embrulha ESTE mesmo
# .dmg e roda o mesmo .pkg. Passar pelo brew obrigaria a instalar um gerenciador
# de pacotes inteiro que o usuário pode não querer, e pediria a senha DUAS vezes
# — uma para criar /opt/homebrew, outra para o pkg. Medido em 23/08 no Mac mini
# alvo: não havia Homebrew.
#
# Sem interface gráfica em momento nenhum: `installer(8)` é a mesma ferramenta
# que o Installer.app usa por baixo.
# `hdiutil detach` falha com "Resource busy" enquanto qualquer processo segurar
# o volume — medido em 23/08: o Installer.app segurava o .pkg. Sem -force o
# volume ficava montado para sempre, e um `|| true` esconderia isso.
desmontar() {
    local ponto="$1" i=0
    [ -n "$ponto" ] || return 0
    [ -d "$ponto" ] || { VBOX_PONTO=""; return 0; }
    while [ "$i" -lt 3 ]; do
        if hdiutil detach -quiet "$ponto" 2>/dev/null; then VBOX_PONTO=""; return 0; fi
        i=$(( i + 1 )); sleep 1
    done
    if hdiutil detach -force -quiet "$ponto" 2>/dev/null; then VBOX_PONTO=""; return 0; fi
    ha_warn "$(msg vbox_nao_desmontou "$ponto")"
    VBOX_PONTO=""
    return 1
}

VBOX_VERSAO="7.2.16"
VBOX_BUILD="174877"
VBOX_DMG="VirtualBox-${VBOX_VERSAO}-${VBOX_BUILD}-macOSArm64.dmg"
VBOX_BASE="https://download.virtualbox.org/virtualbox/${VBOX_VERSAO}"

garantir_virtualbox() {
    if command -v VBoxManage >/dev/null 2>&1; then
        host_set vbox preexisting
        return 100
    fi

    ha_warn "$(msg vbox_ausente)"
    confirmar_dep "$(msg vbox_instalar "$VBOX_VERSAO")" || return 1
    garantir_sudo || return 1

    # `pending` ANTES de tentar: morrer entre o installer e o registro deixa a
    # prova de que ESTE instalador mexeu aqui (regra 1 do manifesto).
    host_set vbox pending
    garantir_log

    # O DMG mora no CACHE, não em tempdir: o desfecho mais provável da 1ª vez
    # é o macOS bloquear a extensão da Oracle e o usuário reexecutar depois de
    # permitir — medido no primeiro teste real. Reexecução não recompra 153 MB.
    local dir sha_arq esperado obtido ponto pkg
    local cache="$HOME/Library/Caches/haos-mac-mini" dmg
    dmg="$cache/$VBOX_DMG"
    dir="$(mktempdir)"

    # O SHA da Oracle vem primeiro: é ele que valida tanto o cache quanto o
    # download novo.
    sha_arq="$dir/SHA256SUMS"
    curl -fsSL --proto '=https' -o "$sha_arq" "$VBOX_BASE/SHA256SUMS" 2>>"$LOG_FILE" \
        || { ha_err "$(msg vbox_sem_sha)"; diagnostico_log; return 1; }
    esperado="$(awk -v f="$VBOX_DMG" '$0 ~ f {print $1; exit}' "$sha_arq")"
    [ -n "$esperado" ] || { ha_err "$(msg vbox_sem_sha)"; return 1; }

    if [ -f "$dmg" ] && [ "$(shasum -a 256 "$dmg" | awk '{print $1}')" = "$esperado" ]; then
        ha_ok "$(msg vbox_dmg_cache "$dmg")"
    else
        mkdir -p "$cache" || return 1
        rm -f "$dmg.parcial"
        ha_run_step "$(msg vbox_baixando "$VBOX_VERSAO")" \
            curl -fL -sS --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
            -o "$dmg.parcial" "$VBOX_BASE/$VBOX_DMG" \
            || { rm -f "$dmg.parcial"; ha_err "$(msg vbox_download_falhou)"; return 1; }
        obtido="$(shasum -a 256 "$dmg.parcial" | awk '{print $1}')"
        if [ "$esperado" != "$obtido" ]; then
            rm -f "$dmg.parcial"
            ha_err "$(msg vbox_sha_diverge)"
            printf '    esperado: %s\n    obtido  : %s\n' "$esperado" "$obtido" >&2
            return 1
        fi
        mv "$dmg.parcial" "$dmg"
        host_set dmg_cache created
        host_set dmg_path "$dmg"
        ha_ok "$(msg vbox_sha_ok)"
    fi

    # O parse do ponto de montagem vem do -plist: `hdiutil attach -quiet`
    # SUPRIME a listagem, o parse recebia vazio e a instalação morria com
    # "Could not mount" sobre um DMG perfeitamente montável — medido no
    # primeiro teste real, no Mac mini. </dev/null porque em curl|bash o
    # stdin é o cano do script.
    ponto="$(hdiutil attach -nobrowse -readonly -plist "$dmg" </dev/null 2>>"$LOG_FILE" \
        | sed -n 's:.*<string>\(/Volumes/[^<]*\)</string>.*:\1:p' | head -1)"
    [ -n "$ponto" ] || { ha_err "$(msg vbox_mount_falhou)"; diagnostico_log; return 1; }
    # desmonta aconteça o que acontecer, inclusive em erro no meio
    VBOX_PONTO="$ponto"

    pkg="$(find "$ponto" -maxdepth 1 -name '*.pkg' | head -1)"
    if [ -z "$pkg" ]; then
        desmontar "$ponto"
        ha_err "$(msg vbox_sem_pkg)"; return 1
    fi

    # sudo já foi primado no topo desta função — o installer roda com -n
    # implícito no cache; nenhum prompt pode cair dentro do spinner.
    local rc_inst=0
    ha_run_step "$(msg vbox_instalando)" sudo installer -pkg "$pkg" -target / || rc_inst=$?
    desmontar "$ponto"
    if [ "$rc_inst" != "0" ]; then ha_err "$(msg vbox_installer_falhou)"; return 1; fi

    # Re-sonda: instalado não é o mesmo que utilizável. Se o macOS bloqueou a
    # extensão de sistema, o binário existe e não funciona — e dizer isso aqui
    # é melhor que falhar na criação da VM com erro incompreensível.
    if command -v VBoxManage >/dev/null 2>&1 && VBoxManage --version >/dev/null 2>&1; then
        ha_ok "$(msg vbox_ok "$(VBoxManage --version 2>/dev/null | tr -d '\r')")"
        host_set vbox created
        return 0
    fi
    ha_err "$(msg vbox_bloqueado)"
    return 1
}

# ── download ─────────────────────────────────────────────────────────────────
baixador() {
    if command -v curl >/dev/null 2>&1; then printf 'curl'; return 0; fi
    if command -v wget >/dev/null 2>&1; then printf 'wget'; return 0; fi
    return 1
}

# ── log da execução ──────────────────────────────────────────────────────────
# Um arquivo por execução, criado SÓ quando o primeiro passo real roda — assim
# o --dry-run continua não escrevendo nada, nem em /tmp. Fica FORA de TMPFILES
# de propósito: o limpar() apagaria exatamente o arquivo que a mensagem de erro
# acabou de nomear. Sucesso limpa; falha preserva e imprime o caminho.
LOG_FILE=""
garantir_log() {
    [ -n "$LOG_FILE" ] && return 0
    LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/haos-install-XXXXXX" 2>/dev/null)" \
        || LOG_FILE="${TMPDIR:-/tmp}/haos-install-$$.log"
    return 0
}

# Assina uma falha de REDE a partir do que a ferramenta escreveu no log. As
# frases são as que curl/wget realmente emitem — não um palpite.
falha_de_rede() {
    [ -n "$LOG_FILE" ] && [ -s "$LOG_FILE" ] || return 1
    LC_ALL=C tail -40 "$LOG_FILE" | LC_ALL=C grep -qiE \
        'could not resolve host|failed to connect|connection refused|connection timed out|network is unreachable|no route to host|ssl|tls|operation timed out|temporary failure in name resolution'
}

# Depois de um passo falhar: diz se parece rede (em vez de despejar stack de
# ferramenta como se fosse culpa da máquina) e mostra as últimas linhas do log.
# NÃO sai do script — o chamador mantém o próprio código de erro (contrato
# 0/100/1 das funções de fase; achado B-6 da banca).
diagnostico_log() {
    if falha_de_rede; then
        ha_warn "$(msg rede_titulo)"
        ha_info "$(msg rede_dica1)"
        ha_info "$(msg rede_dica2)"
    fi
    if [ -n "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        printf '   %s\n' "$(msg log_ultimas "$LOG_FILE")" >&2
        tail -12 "$LOG_FILE" | sed 's/^/    | /' >&2
    fi
    return 0
}

# ── ha_run_step: um passo com spinner, tempo e log ──────────────────────────
# REGRA DA BANCA (B-6): só embrulha COMANDO EXTERNO FOLHA (curl, unzip, shasum,
# installer, VBoxManage) — nunca função de fase. O comando roda em background, e
# num subshell qualquer variável global gravada se perde: foi assim que o .dmg
# ficaria montado para sempre. Prompt nenhum pode acontecer aqui dentro: sudo e
# confirmações são primados ANTES, pelos chamadores.
# HA_STEP_OK lista os códigos aceitos (padrão "0"); volta ao padrão a cada uso.
RUN_STEPS=""
HA_STEP_OK="0"
ha_run_step() { # <rótulo já traduzido> <cmd...>
    local rotulo="$1"; shift
    garantir_log
    local t0="$SECONDS" rc=0 aceitos="$HA_STEP_OK"
    HA_STEP_OK="0"
    if [ "$OP_VERBOSE" = "1" ]; then
        # Verbose = ver a ferramenta crua, na tela. É o modo de diagnóstico;
        # essas linhas não vão para o log (tee num pipeline sob pipefail
        # esconderia o rc do comando — bash 3.2 não dá as duas coisas).
        ha_info "$rotulo"
        "$@" || rc=$?
    else
        "$@" >>"$LOG_FILE" 2>&1 &
        ha_spin "$rotulo" "$!" || rc=$?
    fi
    RUN_STEPS="${RUN_STEPS}${rotulo}|$(( SECONDS - t0 ))
"
    if tem_na_lista "$rc" "$aceitos"; then return "$rc"; fi
    diagnostico_log
    return "$rc"
}

# ── estado local: ~/.config/haos-mac-mini ────────────────────────────────────
# Derivado de $HOME NO MOMENTO DA CHAMADA, nunca congelado no topo: é o que
# permite à bancada apontar um $HOME sintético (achado B-7). HAOS_STATE_DIR é a
# costura de teste documentada.
haos_state_dir() { printf '%s' "${HAOS_STATE_DIR:-$HOME/.config/haos-mac-mini}"; }

# ── manifesto: o que ESTE instalador criou NESTA máquina ─────────────────────
# Dois escopos, dois arquivos, porque são mesmo diferentes (desenho do
# AtlasFile): há UM VirtualBox por máquina (host-prereqs) e pode haver N VMs
# (vms/<nome>.manifest). Valores: created | preexisting | pending.
# As três regras que tornam o mecanismo seguro para o --uninstall:
#   1. `pending` é gravado ANTES de tentar instalar — morrer entre o comando e
#      o registro deixa a prova; sem isso a execução seguinte veria o artefato
#      presente e gravaria a mentira `preexisting`.
#   2. `created` NUNCA é rebaixado numa reexecução.
#   3. Chave ausente lê como `preexisting` — a resposta conservadora: o
#      uninstall só poderá remover o que provar que fez.
# Escrituração é best-effort: nunca derruba uma instalação por causa de registro.
manifest_get() { # <arquivo> <chave>
    [ -f "$1" ] || return 0
    awk -F'\t' -v k="$2" '$1==k{print $2; exit}' "$1" 2>/dev/null || true
}
manifest_set() { # <arquivo> <chave> <valor>
    local arq="$1" chave="$2" valor="$3" atual tmp
    atual="$(manifest_get "$arq" "$chave")"
    [ "$atual" = "created" ] && return 0
    [ "$atual" = "$valor" ] && return 0
    mkdir -p "$(dirname "$arq")" 2>/dev/null || return 0
    if [ ! -f "$arq" ]; then
        printf '# haos-mac-mini — chave<TAB>valor. Consumido pelo --uninstall.\nschema\t1\n' \
            > "$arq" 2>/dev/null || return 0
    fi
    tmp="$arq.tmp.$$"
    { awk -F'\t' -v k="$chave" '$1!=k' "$arq" 2>/dev/null
      printf '%s\t%s\n' "$chave" "$valor"; } > "$tmp" 2>/dev/null && mv "$tmp" "$arq" 2>/dev/null
    rm -f "$tmp" 2>/dev/null || true
    return 0
}
host_manifest() { printf '%s' "$(haos_state_dir)/host-prereqs"; }
vm_manifest()   { printf '%s' "$(haos_state_dir)/vms/${OP_VM_NOME}.manifest"; }
host_set() { manifest_set "$(host_manifest)" "$1" "$2"; }
vm_set()   { manifest_set "$(vm_manifest)" "$1" "$2"; }

# ── memória de seleção: --profile last ───────────────────────────────────────
# Grava a seleção resolvida DEPOIS da confirmação (nunca em dry-run) e a relê
# filtrando o que saiu do catálogo — id morto numa seleção antiga não pode
# derrubar a reexecução (desenho do mac-env-setup).
salvar_selecao() {
    local d; d="$(haos_state_dir)"
    mkdir -p "$d" 2>/dev/null || return 0
    {
        printf '# última seleção — haos-install.sh (%s)\n' "$(date '+%Y-%m-%d %H:%M')"
        printf 'degrau=%s\n'  "$SEL_DEGRAU"
        printf 'extras=%s\n'  "$SEL_EXTRAS"
        printf 'vm=%s\n'      "$SEL_VM"
        printf 'vm_nome=%s\n' "$OP_VM_NOME"
        # Personalizado é uma LISTA, não um degrau — sem ela o --profile last
        # regride aos padrões e derruba itens como hacs (pego em campo)
        if [ "${SEL_PERSO:-0}" = "1" ]; then
            printf 'perso=1\n'
            printf 'itens=%s\n' "$SEL_ITENS"
        fi
    } > "$d/state" 2>/dev/null || true
    return 0
}
LAST_DEGRAU=""; LAST_EXTRAS=""; LAST_VM=""; LAST_VM_NOME=""; LAST_PERSO=0; LAST_ITENS=""
carregar_selecao() {
    local f linha e filtrado=""
    f="$(haos_state_dir)/state"
    [ -f "$f" ] || return 1
    while IFS= read -r linha; do
        case "$linha" in
            degrau=*)  LAST_DEGRAU="${linha#*=}" ;;
            extras=*)  LAST_EXTRAS="${linha#*=}" ;;
            vm=*)      LAST_VM="${linha#*=}" ;;
            vm_nome=*) LAST_VM_NOME="${linha#*=}" ;;
            perso=1)   LAST_PERSO=1 ;;
            itens=*)   LAST_ITENS="${linha#*=}" ;;
        esac
    done < "$f"
    perfil_valido "$LAST_DEGRAU" || return 1
    for e in $LAST_EXTRAS; do
        tem_na_lista "$e" "${ORTOGONAL_DB[*]}" && filtrado="$filtrado $e"
    done
    LAST_EXTRAS="${filtrado# }"
    # ids mortos caem fora (catálogo pode ter mudado entre execuções)
    filtrado=""
    for e in $LAST_ITENS; do
        item_campo "$e" 1 >/dev/null 2>&1 && filtrado="$filtrado $e"
    done
    LAST_ITENS="${filtrado# }"
    local r achou=0
    for r in "${VM_PROFILE_DB[@]}"; do [ "${r%%|*}" = "$LAST_VM" ] && achou=1; done
    [ "$achou" = "1" ] || LAST_VM=""
    return 0
}

# Espelho da execução, no espírito do last-run.log dos irmãos: o log guarda a
# saída das ferramentas; ISTO guarda o que o instalador fez. Best-effort —
# escrituração nunca derruba uma instalação.
escrever_last_run() { # <rc>
    local rc="$1" d linha
    d="$(haos_state_dir)"
    mkdir -p "$d" 2>/dev/null || return 0
    {
        printf 'haos-install.sh %s — %s\n' "$HAOS_INSTALL_VERSION" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'rc=%s' "$rc"
        [ -n "${FASE_ATUAL:-}" ] && printf ' · fase=%s' "$FASE_ATUAL"
        [ -n "${SEL_DEGRAU:-}" ] && printf ' · degrau=%s' "$SEL_DEGRAU"
        [ -n "${SEL_EXTRAS:-}" ] && printf ' · extras=%s' "$SEL_EXTRAS"
        printf '\n\n'
        printf '%s' "$RUN_STEPS" | while IFS='|' read -r linha segs; do
            [ -n "$linha" ] && printf '  %-52s %ss\n' "$linha" "$segs"
        done
        [ -n "${LOG_FILE:-}" ] && [ -s "${LOG_FILE:-/nonexistent}" ] \
            && printf '\nlog das ferramentas: %s\n' "$LOG_FILE"
    } > "$d/last-run.log" 2>/dev/null || true
    return 0
}


# ── F3: a imagem do HAOS ─────────────────────────────────────────────────────
# Contrato de retorno, o mesmo do garantir_virtualbox: 0 fez agora · 100 já
# estava · 1 falhou.
#
# Idempotência sem hash do .vdi: hashear o disco descompactado a cada execução
# custaria minutos, então ao lado dele fica um arquivo .origem com a versão, o
# hash do .zip de onde saiu e o tamanho gravado. Bate os três, não refaz nada.
# É proveniência conferível, não fé no nome do arquivo.
HAOS_VDI=""
VM_RAM_MIB=""; VM_CPU_N=""

fase_imagem() {
    ha_fase "$(msg imagem)"

    local ver="$HAOS_REF_OS" r rv url sha bytes achou=0
    for r in "${HAOS_IMAGE_DB[@]}"; do
        IFS='|' read -r rv url sha bytes <<< "$r"
        [ "$rv" = "$ver" ] && { achou=1; break; }
    done
    if [ "$achou" != "1" ]; then ha_err "$(msg img_sem_tabela "$ver")"; return 1; fi

    local destdir vdi origem nome
    destdir="$HOME/VirtualBox VMs/$OP_VM_NOME"
    nome="haos_generic-aarch64-${ver}.vdi"
    vdi="$destdir/$nome"
    origem="$destdir/.${nome}.origem"
    HAOS_VDI="$vdi"

    # ── já está? ────────────────────────────────────────────────────────────
    if [ "$OP_FORCE" != "1" ] && [ -f "$vdi" ] && [ -f "$origem" ]; then
        local ov osha otam tam_atual
        IFS='|' read -r ov osha otam < "$origem"
        tam_atual="$(wc -c < "$vdi" 2>/dev/null | tr -d ' ')"
        if [ "$ov" = "$ver" ] && [ "$osha" = "$sha" ] && [ "$otam" = "$tam_atual" ]; then
            ha_ok "$(msg img_ja "$ver" "$vdi")"
            # O .origem é prova NOSSA (só este script o escreve): o vdi pode
            # ser marcado created mesmo vindo de uma execução anterior.
            vm_set vdi created
            vm_set vdi_path "$vdi"
            return 100
        fi
    fi

    mkdir -p "$destdir" || return 1

    # ── já existe um .zip que sirva? ────────────────────────────────────────
    # Tamanho primeiro: é metadado, e descarta o arquivo pela metade sem ler
    # 380 MiB. Só o que passa no tamanho paga o hash.
    local cache zipnome zip="" cand tam baixamos=0
    cache="$HOME/Library/Caches/haos-mac-mini"
    zipnome="$(basename "$url")"
    # --image aponta um arquivo EXPLÍCITO e por isso falha alto se ele não
    # conferir — descartar em silêncio e baixar 380 MiB por cima seria ignorar
    # uma ordem direta. Os candidatos implícitos (cache, diretório corrente)
    # mantêm o descarte tolerante.
    if [ -n "$OP_IMAGEM" ]; then
        [ -f "$OP_IMAGEM" ] || { ha_err "$(msg img_image_invalida "$OP_IMAGEM")"; return 1; }
        tam="$(wc -c < "$OP_IMAGEM" 2>/dev/null | tr -d ' ')"
        if [ "$tam" != "$bytes" ] ||            [ "$(shasum -a 256 "$OP_IMAGEM" | awk '{print $1}')" != "$sha" ]; then
            ha_err "$(msg img_image_invalida "$OP_IMAGEM")"
            return 1
        fi
        ha_ok "$(msg img_local "$OP_IMAGEM")"
        zip="$OP_IMAGEM"
    fi
    [ -n "$zip" ] || for cand in "$cache/$zipnome" "./$zipnome"; do
        [ -f "$cand" ] || continue
        tam="$(wc -c < "$cand" 2>/dev/null | tr -d ' ')"
        [ "$tam" = "$bytes" ] || { ha_warn "$(msg img_local_descartado "$cand")"; continue; }
        if [ "$(shasum -a 256 "$cand" | awk '{print $1}')" = "$sha" ]; then
            ha_ok "$(msg img_local "$cand")"; zip="$cand"; break
        fi
        ha_warn "$(msg img_local_descartado "$cand")"
    done

    # ── baixar ──────────────────────────────────────────────────────────────
    if [ -z "$zip" ]; then
        baixamos=1
        local dl
        dl="$(baixador)" || { ha_err "$(msg img_sem_baixador)"; return 1; }
        mkdir -p "$cache" || return 1
        zip="$cache/$zipnome"
        ha_info "$(msg img_baixando "$ver" "$(( bytes / 1048576 ))")"
        # O parcial vai para um nome à parte: interrompido no meio, um arquivo
        # com o nome final e o tamanho errado seria "encontrado" na próxima
        # execução e reprovado no hash — ruído em vez de retomada.
        local parcial="$zip.parcial"
        rm -f "$parcial"
        # Barra de progresso só quando há terminal. Em log, CI ou pipe, o curl
        # escreve dezenas de linhas de estatística em stderr e afoga a saída
        # útil — medido: 87 s de download viraram uma linha ilegível de 8 KB.
        # Com TTY o download fica FORA do ha_run_step de propósito: para
        # 380 MiB a barra nativa do curl informa mais que um spinner. Sem TTY,
        # o stderr vai para o log e uma falha ganha o diagnóstico de rede.
        local rc_dl=0
        if [ -t 2 ] && [ "$dl" = "curl" ]; then
            # a barra é a NOSSA (bytes gravados contra o total da tabela) — a
            # do curl é um jogo-da-velha fora da identidade, apontado pelo dono
            garantir_log
            curl -fL -sS --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
                -o "$parcial" "$url" 2>>"$LOG_FILE" &
            local pid_dl=$! tam_dl
            while kill -0 "$pid_dl" 2>/dev/null; do
                tam_dl="$(stat -f%z "$parcial" 2>/dev/null || echo 0)"
                ha_bar $(( tam_dl / 1048576 )) $(( bytes / 1048576 )) "MiB"
                sleep 0.3
            done
            wait "$pid_dl" || rc_dl=$?
            if [ "$rc_dl" = "0" ]; then
                ha_bar $(( bytes / 1048576 )) $(( bytes / 1048576 )) "MiB"
            else
                printf '\r\033[2K'
            fi
        elif [ -t 2 ]; then
            wget -q --https-only -O "$parcial" "$url" || rc_dl=$?
        else
            garantir_log
            case "$dl" in
                curl) curl -fL -sS --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
                           -o "$parcial" "$url" >>"$LOG_FILE" 2>&1 || rc_dl=$? ;;
                wget) wget -q --https-only -O "$parcial" "$url" >>"$LOG_FILE" 2>&1 || rc_dl=$? ;;
            esac
        fi
        if [ "$rc_dl" != "0" ]; then
            rm -f "$parcial"
            ha_err "$(msg img_download_falhou)"
            diagnostico_log
            return 1
        fi
        tam="$(wc -c < "$parcial" 2>/dev/null | tr -d ' ')"
        if [ "$tam" != "$bytes" ]; then
            ha_err "$(msg img_tamanho_diverge "$tam" "$bytes")"; rm -f "$parcial"; return 1
        fi
        mv "$parcial" "$zip"
    fi

    # ── hash SEMPRE, inclusive no arquivo local e sob --force ───────────────
    # Descompactar sem conferir é executar conteúdo de origem não confirmada.
    local obtido
    obtido="$(shasum -a 256 "$zip" | awk '{print $1}')"
    if [ "$obtido" != "$sha" ]; then
        ha_err "$(msg img_sha_diverge)"
        printf '    esperado: %s\n    obtido  : %s\n' "$sha" "$obtido" >&2
        return 1
    fi
    ha_ok "$(msg img_sha_ok)"

    # ── descompactar ────────────────────────────────────────────────────────
    command -v unzip >/dev/null 2>&1 || { ha_err "$(msg img_sem_unzip)"; return 1; }

    # Descompacta DENTRO do destino, num diretório temporário irmão: o mv final
    # fica no mesmo sistema de arquivos e é atômico. Extrair em /var/folders e
    # mover para $HOME atravessaria sistemas de arquivos, e aí `mv` vira cópia
    # — que interrompida deixa um .vdi truncado com o nome definitivo.
    local tmpx="$destdir/.haos-extraindo.$$"
    rm -rf "$tmpx"; mkdir -p "$tmpx" || return 1
    if ! ha_run_step "$(msg img_descompactando)" unzip -o -q "$zip" -d "$tmpx"; then
        rm -rf "$tmpx"; return 1
    fi
    local extraido
    extraido="$(find "$tmpx" -maxdepth 2 -name '*.vdi' | head -1)"
    if [ -z "$extraido" ]; then rm -rf "$tmpx"; ha_err "$(msg img_sem_vdi)"; return 1; fi

    mv -f "$extraido" "$vdi" || { rm -rf "$tmpx"; return 1; }
    rm -rf "$tmpx"
    printf '%s|%s|%s\n' "$ver" "$sha" "$(wc -c < "$vdi" | tr -d ' ')" > "$origem"

    # Só apaga o que ESTE script baixou. O .zip que o usuário já tinha no
    # diretório é dele: encontrá-lo e apagá-lo em seguida seria cobrar 380 MiB
    # de download pelo favor de ter reaproveitado o arquivo.
    if [ "$baixamos" = "1" ] && [ "$OP_KEEP_IMAGE" != "1" ]; then rm -f "$zip"
    elif [ "$baixamos" = "1" ]; then vm_set zip_cache created; vm_set zip_path "$zip"; fi
    vm_set vdi created
    vm_set vdi_path "$vdi"
    ha_ok "$(msg img_pronta "$vdi")"
    return 0
}


# ── F4: a máquina virtual ────────────────────────────────────────────────────
# Cada argumento aqui foi SONDADO no VBoxManage 7.2.16 real de um Mac ARM em
# 24/08/2026 — nada veio de documentação: `createvm` exige
# `--platform-architecture arm`; o ostype é `Linux_arm64` ("Other Linux, ARM
# 64-bit"); `storagectl --add scsi --controller VirtIO` é RECUSADO na
# plataforma ARM ("Invalid controller type 11") e o aceito é SATA/IntelAhci;
# o controlador gráfico é qemuramfb; a NIC virtio em ponte funciona.
# Contrato 0/100/1, como as demais fases.
vbm() { # VBoxManage com saída no log — o stderr dele é diagnóstico, não UI
    garantir_log
    VBoxManage "$@" >>"$LOG_FILE" 2>&1
}

vm_bridge_iface() { # imprime o nome COMPLETO exigido pelo --bridge-adapter1
    # O nome que o VBoxManage espera é o DELE ("en0: Ethernet"), e qual placa
    # está ativa varia por máquina: sondar sempre, nunca fixar. Preferência:
    # a interface da rota default; sem ela, a primeira Up com endereço real.
    local ifc lista nome
    lista="$(VBoxManage list bridgedifs 2>/dev/null | sed -n 's/^Name:[[:space:]]*//p')"
    [ -n "$lista" ] || return 1
    ifc="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
    if [ -n "$ifc" ]; then
        nome="$(printf '%s\n' "$lista" | grep -m1 "^${ifc}[: ]" || true)"
        [ -n "$nome" ] && { printf '%s' "$nome"; return 0; }
    fi
    nome="$(VBoxManage list bridgedifs 2>/dev/null | awk '
        /^Name:/      { sub(/^Name:[[:space:]]*/, ""); n=$0 }
        /^IPAddress:/ { ip=$2 }
        /^Status:/    { if ($2=="Up" && ip!="0.0.0.0" && n!="") { print n; exit } }')"
    [ -n "$nome" ] && { printf '%s' "$nome"; return 0; }
    return 1
}

fase_vm() {
    ha_fase "$(msg fase_vm)"
    command -v VBoxManage >/dev/null 2>&1 \
        || PATH="$PATH:/Applications/VirtualBox.app/Contents/MacOS"
    command -v VBoxManage >/dev/null 2>&1 || { ha_err "$(msg vm_sem_vbm)"; return 1; }

    # Convergência: registrada com este nome = pronta. Quem criou por fora
    # sabe o que fez — reconfigurar uma VM alheia seria destruir trabalho.
    if VBoxManage showvminfo "$OP_VM_NOME" >/dev/null 2>&1; then
        vm_set vm_registrada preexisting
        ha_ok "$(msg vm_ja "$OP_VM_NOME")"
        return 100
    fi
    [ -f "${HAOS_VDI:-/nonexistent}" ] || { ha_err "$(msg vm_sem_vdi "${HAOS_VDI:-?}")"; return 1; }

    local ponte ram="${VM_RAM_MIB:-4096}" cpu="${VM_CPU_N:-2}"
    ponte="$(vm_bridge_iface)" || { ha_err "$(msg vm_sem_bridge)"; return 1; }
    ha_info "$(msg vm_bridge "$ponte")"

    vm_set vm_registrada pending
    ha_info "$(msg vm_criando "$OP_VM_NOME" "$ram" "$cpu")"
    if ! { vbm createvm --name "$OP_VM_NOME" --platform-architecture arm \
               --ostype Linux_arm64 --basefolder "$HOME/VirtualBox VMs" --register \
        && vbm modifyvm "$OP_VM_NOME" --memory "$ram" --cpus "$cpu" \
               --firmware efi --graphicscontroller qemuramfb \
               --rtc-use-utc on --audio-driver none \
        && vbm modifyvm "$OP_VM_NOME" --nic1 bridged \
               --bridge-adapter1 "$ponte" --nic-type1 virtio \
        && vbm storagectl "$OP_VM_NOME" --name SATA --add sata \
               --controller IntelAhci --bootable on \
        && vbm storageattach "$OP_VM_NOME" --storagectl SATA --port 0 --device 0 \
               --type hdd --medium "$HAOS_VDI" --nonrotational on --discard on; }; then
        # Rollback do parcial SEM tocar no disco: soltar o medium ANTES de
        # desregistrar — um `unregistervm --delete` levaria o .vdi junto.
        vbm storageattach "$OP_VM_NOME" --storagectl SATA --port 0 --device 0 --medium none || true
        vbm closemedium disk "$HAOS_VDI" || true
        vbm unregistervm "$OP_VM_NOME" || true
        rm -f "$HOME/VirtualBox VMs/$OP_VM_NOME/$OP_VM_NOME.vbox" 2>/dev/null || true
        ha_err "$(msg vm_falhou)"
        diagnostico_log
        return 1
    fi

    # Verificação: o que o VirtualBox REGISTROU, não o que pedimos.
    local info
    info="$(VBoxManage showvminfo "$OP_VM_NOME" --machinereadable 2>/dev/null)"
    if ! { printf '%s' "$info" | grep -q '^firmware="EFI"' \
        && printf '%s' "$info" | grep -qF "\"SATA-0-0\"=\"$HAOS_VDI\"" \
        && printf '%s' "$info" | grep -q '^nic1="bridged"'; }; then
        ha_err "$(msg vm_falhou)"; diagnostico_log; return 1
    fi
    vm_set vm_registrada created
    ha_ok "$(msg vm_pronta "$OP_VM_NOME")"
    return 0
}


# ── F5: boot e espera — pelo MAC, nunca pelo nome ────────────────────────────
# Medido em 24/08: com outro Home Assistant vivo na rede, homeassistant.local
# resolve para ELE e um teste por nome dá falso positivo. O único fato que
# identifica ESTA VM é o MAC que o VirtualBox registrou. E o critério de vivo
# é "qualquer resposta HTTP" nas duas portas candidatas — ver vm_url_de().
VM_IP=""
VM_URL=""

mac_para_arp() { # 0800270C0FFB -> 8:0:27:c:f:fb (formato do arp do macOS)
    printf '%s' "$1" | awk '{ s=tolower($0); o=""
        for (i = 1; i <= length(s); i += 2) { oct = substr(s, i, 2)
            sub(/^0/, "", oct); if (oct == "") oct = "0"
            o = o (i > 1 ? ":" : "") oct }
        print o }'
}

vm_ip_pelo_mac() { # <mac-arp> — imprime o IP ou falha
    local ip
    ip="$(arp -an 2>/dev/null | grep -iF " at $1 " \
        | sed -n 's/.*(\([0-9.][0-9.]*\)).*/\1/p' | head -1)"
    [ -n "$ip" ] && { printf '%s' "$ip"; return 0; }
    return 1
}

vm_url_de() { # <ip> — imprime a base que responde. No HAOS 18.2 a URL
    # canônica é a PORTA 80 (o console da VM a anuncia); a 8123 redireciona
    # antes do onboarding e FECHA depois — medido em 24/08, e mordeu no fresh
    # do dono: descoberta pré-onboarding fixava :8123 e a fase de apps falava
    # com porta morta. A 80 vem PRIMEIRO por ser estável nos dois estados.
    local b code
    for b in "http://$1" "http://$1:8123"; do
        code="$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$b/" 2>/dev/null || true)"
        [ -n "$code" ] && [ "$code" != "000" ] && { printf '%s' "$b"; return 0; }
    done
    return 1
}

fase_boot() {
    ha_fase "$(msg fase_boot)"
    command -v VBoxManage >/dev/null 2>&1 \
        || PATH="$PATH:/Applications/VirtualBox.app/Contents/MacOS"
    command -v VBoxManage >/dev/null 2>&1 || { ha_err "$(msg vm_sem_vbm)"; return 1; }

    local mac mac_arp ja=0
    mac="$(VBoxManage showvminfo "$OP_VM_NOME" --machinereadable 2>/dev/null \
        | sed -n 's/^macaddress1="\(.*\)"/\1/p')"
    [ -n "$mac" ] || { ha_err "$(msg boot_sem_vm "$OP_VM_NOME")"; return 1; }
    mac_arp="$(mac_para_arp "$mac")"

    # Três ramos, não dois (banca): rodando (com ou sem resposta ainda) só
    # espera; pausada retoma; qualquer outro estado (off, saved, aborted)
    # passa pelo startvm — que em `saved` resume do ponto salvo.
    local estado
    estado="$(VBoxManage showvminfo "$OP_VM_NOME" --machinereadable 2>/dev/null \
        | sed -n 's/^VMState="\(.*\)"/\1/p')"
    case "$estado" in
        running)
            ja=1
            ha_ok "$(msg boot_ja_roda "$OP_VM_NOME")" ;;
        paused)
            vbm controlvm "$OP_VM_NOME" resume \
                || { ha_err "$(msg vm_falhou)"; diagnostico_log; return 1; } ;;
        *)
            ha_info "$(msg boot_ligando "$OP_VM_NOME")"
            if ! vbm startvm "$OP_VM_NOME" --type headless; then
                ha_err "$(msg vm_falhou)"; diagnostico_log; return 1
            fi ;;
    esac

    # A espera: ARP popula quando a VM fala; um ping no broadcast da interface
    # da rota default acorda a tabela quando ela demora.
    local t=0 passo="${HAOS_BOOT_PASSO:-5}" limite="${HAOS_BOOT_TIMEOUT:-900}"
    local ifc bcast achou=0
    ifc="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
    bcast="$(ifconfig "${ifc:-en0}" 2>/dev/null | awk '/broadcast/{print $NF; exit}')"
    ha_info "$(msg boot_esperando "$mac_arp")"
    while [ "$t" -lt "$limite" ]; do
        VM_IP="$(vm_ip_pelo_mac "$mac_arp" || true)"
        if [ -n "$VM_IP" ]; then
            VM_URL="$(vm_url_de "$VM_IP" || true)"
            [ -n "$VM_URL" ] && { achou=1; break; }
        else
            [ -z "$bcast" ] || ping -c1 -t1 "$bcast" >/dev/null 2>&1 || true
        fi
        sleep "$passo"; t=$(( t + passo ))
        ha_bar "$t" "$limite" "s"
    done
    # achou ou não, a barra de tempo sai da tela — "900/900 s" no sucesso
    # leria como se a espera tivesse consumido o limite inteiro
    printf '\r\033[2K'
    if [ "$achou" != "1" ]; then
        ha_err "$(msg boot_timeout "$limite")"
        return 1
    fi
    vm_set vm_mac "$mac_arp"
    vm_set vm_ip "$VM_IP"
    vm_set vm_url "$VM_URL"
    ha_ok "$(msg boot_no_ar "$VM_URL")"

    autostart_launchagent

    [ "$ja" = "1" ] && return 100
    return 0
}

# ── F5b: auto-start no login ─────────────────────────────────────────────────
# LaunchAgent desired-state. Caminho COMPLETO do bundle no comando: launchd
# não tem /usr/local/bin no PATH (mesma lição da sonda). SEM `sh -c` — a banca
# reprovou a interpolação de nome dentro de shell (injeção persistente a cada
# login); argv direto não interpreta nada, e `startvm` numa VM já rodando só
# devolve um erro inócuo. O nome da VM é validado no parser ([A-Za-z0-9._-]).
autostart_launchagent() {
    local rotulo plist tmp vbm_bin dir uid_atual
    dir="$HOME/Library/LaunchAgents"
    rotulo="com.haos-mac-mini.$OP_VM_NOME"
    plist="$dir/$rotulo.plist"
    vbm_bin="/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"
    tmp="$(mktempfile)"
    cat > "$tmp" <<FIM
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$rotulo</string>
    <key>ProgramArguments</key>
    <array>
        <string>$vbm_bin</string>
        <string>startvm</string>
        <string>$OP_VM_NOME</string>
        <string>--type</string>
        <string>headless</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
FIM
    uid_atual="$(id -u)"
    if [ -f "$plist" ] && cmp -s "$tmp" "$plist"; then
        # arquivo igual não prova job carregado (banca) — conferir e sanar
        launchctl print "gui/$uid_atual/$rotulo" >/dev/null 2>&1 \
            || launchctl bootstrap "gui/$uid_atual" "$plist" >/dev/null 2>&1 \
            || launchctl load -w "$plist" >/dev/null 2>&1 || true
        ha_ok "$(msg boot_autostart_ja)"
        return 0
    fi
    mkdir -p "$dir" || return 0
    vm_set autostart pending
    install -m 0644 "$tmp" "$plist" || return 0
    launchctl bootout "gui/$uid_atual/$rotulo" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$uid_atual" "$plist" >/dev/null 2>&1 \
        || launchctl load -w "$plist" >/dev/null 2>&1 || true
    vm_set autostart created
    vm_set autostart_path "$plist"
    ha_ok "$(msg boot_autostart_ok)"
    return 0
}


# =============================================================================
# F6–F9 — dentro do Home Assistant, pelo helper Python embutido.
# CONTRATO DE SEGREDO (banca): credencial só por STDIN do helper; nunca argv,
# nunca export, nunca em rótulo de passo; o stderr do helper é só
# "ERRO <status> <rota>". Cerca de sentinela no portão prova a ausência.
# =============================================================================
HA_USER=""
HA_SENHA=""
SMB_SENHA=""
SMB_PONTO=""
CHAVE_SSH_PUB=""
FLOWS_PENDENTES=""

helper() { # <args...> — stdin preparado pelo chamador; HAOS_BASE já com a URL
    HAOS_BASE="${HAOS_BASE_URL:-$VM_URL}" HAOS_HELPER_LANG="$IDIOMA" \
        python3 -c "$HAOS_HELPER_PY" "$@"
}
helper_cred() { # <args...> — credencial no stdin
    printf '%s\n%s\n' "$HA_USER" "$HA_SENHA" | helper "$@"
}

obter_credencial() {
    [ -n "$HA_SENHA" ] && return 0
    if [ -n "${HAOS_HA_USER:-}" ] && [ -n "${HAOS_HA_PASSWORD:-}" ]; then
        HA_USER="$HAOS_HA_USER"; HA_SENHA="$HAOS_HA_PASSWORD"
        return 0
    fi
    if [ "$OP_NOINPUT" = "1" ] || ! tem_tty; then
        ha_err "$(msg conta_sem_credencial)"
        return 1
    fi
    ha_bar_suspende
    ha_info "$(msg conta_pede)"
    local padrao="${USER:-admin}" s1 s2 tent=0
    ha_ask "$(msg conta_usuario "$padrao")"
    IFS= read -r HA_USER < "$TTY_DEV" || HA_USER=""
    [ -n "$HA_USER" ] || HA_USER="$padrao"
    while [ "$tent" -lt 3 ]; do
        ha_ask "$(msg conta_senha)"
        IFS= read -rs s1 < "$TTY_DEV" || s1=""
        printf '\n'
        if [ -z "$s1" ]; then ha_warn "$(msg conta_senha_vazia)"; tent=$((tent+1)); continue; fi
        ha_ask "$(msg conta_senha2)"
        IFS= read -rs s2 < "$TTY_DEV" || s2=""
        printf '\n'
        [ "$s1" = "$s2" ] && { HA_SENHA="$s1"; break; }
        ha_warn "$(msg conta_senha_diferente)"; tent=$((tent+1))
    done
    ha_bar_retoma
    [ -n "$HA_SENHA" ] || { ha_err "$(msg conta_falhou)"; return 1; }
    return 0
}

fase_conta() {
    ha_fase "$(msg fase_conta)"
    obter_credencial || return 1
    garantir_log
    local rc=0
    helper_cred conta >/dev/null 2>>"$LOG_FILE" || rc=$?
    case "$rc" in
        0)
            # o onboarding pode MOVER a porta do HA (8123 fecha) — redescobrir
            # a URL antes de qualquer fase falar com ele de novo
            local nova
            nova="$(vm_url_de "$VM_IP" || true)"
            if [ -n "$nova" ] && [ "$nova" != "$VM_URL" ]; then
                VM_URL="$nova"
                vm_set vm_url "$VM_URL"
            fi
            ha_ok "$(msg conta_criada "$HA_USER")"; return 0 ;;
        100) ha_ok "$(msg conta_ja)"; return 100 ;;
        *)   ha_err "$(msg conta_falhou)"; diagnostico_log; return 1 ;;
    esac
}

# ── F7: apps via WebSocket supervisor/api ────────────────────────────────────
garantir_smb_senha() {
    [ -n "$SMB_SENHA" ] && return 0
    # desired-state (banca): quem detém a verdade é o Supervisor — a senha
    # de uma execução anterior é lida DE VOLTA, nunca regenerada por cima.
    SMB_SENHA="$(helper_cred addon-option core_samba password 2>/dev/null || true)"
    [ -n "$SMB_SENHA" ] && return 0
    SMB_SENHA="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
    [ -n "$SMB_SENHA" ]
}

garantir_chave_ssh() {
    local f="$HOME/.ssh/haos-mac-mini"
    if [ ! -f "$f.pub" ]; then
        mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
        ssh-keygen -q -t ed25519 -N "" -C "haos-mac-mini" -f "$f" || return 1
    fi
    CHAVE_SSH_PUB="$(awk '{print $1" "$2}' "$f.pub")"
    [ -n "$CHAVE_SSH_PUB" ]
}

fase_apps() {
    ha_fase "$(msg fase_apps)"
    local it origem slug lista=""
    for it in $SEL_ITENS; do
        origem="$(item_campo "$it" 4)"
        case "$origem" in oficial|community) lista="$lista $it" ;; esac
    done
    if [ -z "$lista" ]; then ha_ok "$(msg apps_nada)"; return 100; fi
    obter_credencial || return 1
    garantir_log
    local rc opts todos_ja=1
    for it in $lista; do
        origem="$(item_campo "$it" 4)"; slug="$(item_campo "$it" 5)"
        if [ "$origem" = "community" ]; then
            # prefixo de repositório de terceiro é HASH da URL — descobrir,
            # nunca fixar (contrato do catálogo)
            case "$slug" in
                DESCOBRIR_ssh)
                    slug="$(helper_cred repo-ensure \
                        "https://github.com/hassio-addons/repository" ssh \
                        2>>"$LOG_FILE")" \
                        || { ha_err "$(msg apps_falhou "$it")"; diagnostico_log; return 1; } ;;
                *) ha_err "$(msg apps_falhou "$it")"; return 1 ;;
            esac
        fi
        opts=""
        case "$slug" in
            core_samba)
                garantir_smb_senha || return 1
                opts="{\"username\":\"haos\",\"password\":\"$SMB_SENHA\"}" ;;
            *_ssh)
                # as options deste app são aninhadas em ssh.* (medido)
                garantir_chave_ssh || return 1
                opts="{\"ssh\":{\"authorized_keys\":[\"$CHAVE_SSH_PUB\"]}}" ;;
        esac
        ha_info "$(msg apps_instalando "$it")"
        rc=0
        if [ -n "$opts" ]; then
            printf '%s\n%s\n%s\n' "$HA_USER" "$HA_SENHA" "$opts" \
                | helper addon-ensure "$slug" --options-stdin \
                    >/dev/null 2>>"$LOG_FILE" || rc=$?
        else
            helper_cred addon-ensure "$slug" >/dev/null 2>>"$LOG_FILE" || rc=$?
        fi
        case "$rc" in
            0)   ha_ok "$(msg apps_ok "$it")"; todos_ja=0 ;;
            100) ha_ok "$(msg apps_ja "$it")" ;;
            *)   ha_err "$(msg apps_falhou "$it")"; diagnostico_log; return 1 ;;
        esac
    done
    [ "$todos_ja" = "1" ] && return 100
    return 0
}

# ── F8: integrações — só flow que fecha SEM dado do usuário ─────────────────
fase_integracoes() {
    ha_fase "$(msg fase_int)"
    obter_credencial || return 1
    garantir_log
    local it setup rc teve_acao=0
    for it in $SEL_ITENS; do
        [ "$(item_campo "$it" 4)" = "core" ] || continue
        setup="$(item_campo "$it" 8)"
        rc=0
        helper_cred entry-ensure "$it" "$(printf '%s' "$setup" | tr ' ' ',')" \
            >/dev/null 2>>"$LOG_FILE" || rc=$?
        case "$rc" in
            0)   ha_ok "$(msg int_ok "$it")"; teve_acao=1 ;;
            100) ha_ok "$(msg int_ja "$it")" ;;
            3)   ha_info "$(msg int_espera "$it")" ;;
            *)   ha_err "$(msg int_falhou "$it")"; diagnostico_log; return 1 ;;
        esac
    done
    # o que a rede JÁ descobriu sozinha — informação para o relatório
    FLOWS_PENDENTES="$(helper_cred flows-pendentes 2>>"$LOG_FILE" || true)"
    local n
    n="$(printf '%s' "$FLOWS_PENDENTES" | grep -c . || true)"
    if [ "${n:-0}" -gt 0 ]; then
        ha_info "$(msg int_flows "$n" "$(printf '%s\n' "$FLOWS_PENDENTES" | awk '{print $1}' | tr '\n' ' ')")"
    fi
    [ "$teve_acao" = "1" ] && return 0
    return 100
}

# ── F9: arquivos em /config, por montagem SMB ────────────────────────────────
HAOS_HACS_VERSION="2.0.5"
HAOS_HACS_SHA="97be6b824a4f38e683728cc6dd72367f6b8bad0a43428b1b3b987a3087adf413"
HAOS_HACS_BYTES="19021117"

desmontar_smb() {
    [ -n "$SMB_PONTO" ] || return 0
    umount "$SMB_PONTO" >/dev/null 2>&1 \
        || diskutil unmount "$SMB_PONTO" >/dev/null 2>&1 || true
    SMB_PONTO=""
}

montar_smb() { # senha via ENV do expect (nunca argv — banca); ponto em temp
    local ponto
    ponto="$(mktempdir)/config"
    mkdir -p "$ponto" || return 1
    garantir_log
    if ! SENHA_SMB="$SMB_SENHA" /usr/bin/expect -f - "$VM_IP" "$ponto" \
        >>"$LOG_FILE" 2>&1 <<'FIM_EXPECT'
log_user 0
set timeout 45
spawn mount_smbfs //haos@[lindex $argv 0]/config [lindex $argv 1]
expect {
    "assword" { send -- "$env(SENHA_SMB)\r"; exp_continue }
    eof {}
    timeout { exit 10 }
}
catch wait resultado
exit [lindex $resultado 3]
FIM_EXPECT
    then return 1; fi
    SMB_PONTO="$ponto"
    return 0
}

conf_estado() { # <arquivo> → ja | append | estranho (nunca adivinhar)
    if grep -q 'include_dir_named packages' "$1" 2>/dev/null; then printf 'ja'
    elif grep -qE '^homeassistant:' "$1" 2>/dev/null; then printf 'estranho'
    else printf 'append'; fi
}

fase_arquivos() {
    ha_fase "$(msg fase_arq)"
    local it pkgs="" quer_hacs=0
    for it in $SEL_ITENS; do
        case "$it" in
            energia_br|gas_br|agua_br) pkgs="$pkgs $it" ;;
            hacs) quer_hacs=1 ;;
        esac
    done
    if [ -z "$pkgs" ] && [ "$quer_hacs" = "0" ]; then
        ha_ok "$(msg arq_nada)"; return 100
    fi
    obter_credencial || return 1
    garantir_log

    # o samba é o CAMINHO destes arquivos — garantir mesmo fora da seleção
    garantir_smb_senha || return 1
    local rc=0
    printf '%s\n%s\n%s\n' "$HA_USER" "$HA_SENHA" \
        "{\"username\":\"haos\",\"password\":\"$SMB_SENHA\"}" \
        | helper addon-ensure core_samba --options-stdin \
            >/dev/null 2>>"$LOG_FILE" || rc=$?
    [ "$rc" = "0" ] || [ "$rc" = "100" ] || { ha_err "$(msg arq_mount_falhou)"; diagnostico_log; return 1; }

    montar_smb || { ha_err "$(msg arq_mount_falhou)"; diagnostico_log; return 1; }
    ha_info "$(msg arq_montou)"

    local mudou=0 conteudo alvo tmpf carimbo backup_conf=""
    carimbo="$(date +%Y%m%d%H%M%S)"
    if [ -n "$pkgs" ]; then
        mkdir -p "$SMB_PONTO/packages" || { desmontar_smb; return 1; }
        for it in $pkgs; do
            case "$it" in
                energia_br) conteudo="$HAOS_PKG_ENERGIA" ;;
                gas_br)     conteudo="$HAOS_PKG_GAS" ;;
                agua_br)    conteudo="$HAOS_PKG_AGUA" ;;
            esac
            alvo="$SMB_PONTO/packages/$it.yaml"
            tmpf="$(mktempfile)"
            printf '%s\n' "$conteudo" > "$tmpf"
            if [ -f "$alvo" ] && cmp -s "$tmpf" "$alvo"; then
                ha_ok "$(msg arq_pkg_ja "$it")"
            else
                [ -f "$alvo" ] && cp "$alvo" "$alvo.antes-$carimbo"
                cp "$tmpf" "$alvo" || { desmontar_smb; return 1; }
                ha_ok "$(msg arq_pkg_ok "$it")"
                mudou=1
            fi
        done
        alvo="$SMB_PONTO/configuration.yaml"
        case "$(conf_estado "$alvo")" in
            ja) ha_ok "$(msg arq_conf_ja)" ;;
            append)
                backup_conf="$alvo.antes-$carimbo"
                cp "$alvo" "$backup_conf" || { desmontar_smb; return 1; }
                printf '\nhomeassistant:\n  packages: !include_dir_named packages\n' >> "$alvo"
                ha_ok "$(msg arq_conf_ok)"
                mudou=1 ;;
            estranho)
                ha_err "$(msg arq_conf_estranho)"; desmontar_smb; return 1 ;;
        esac
    fi

    if [ "$quer_hacs" = "1" ]; then
        if [ -d "$SMB_PONTO/custom_components/hacs" ]; then
            ha_ok "$(msg arq_hacs_ja)"
        else
            local zip_hacs cache tam obtido
            cache="$HOME/Library/Caches/haos-mac-mini"
            zip_hacs="$cache/hacs-$HAOS_HACS_VERSION.zip"
            if [ ! -f "$zip_hacs" ]; then
                mkdir -p "$cache"
                curl -fsSL --proto '=https' --tlsv1.2 --retry 2 -o "$zip_hacs" \
                    "https://github.com/hacs/integration/releases/download/$HAOS_HACS_VERSION/hacs.zip" \
                    2>>"$LOG_FILE" || { rm -f "$zip_hacs"; ha_err "$(msg arq_hacs_falhou)"; desmontar_smb; return 1; }
            fi
            tam="$(wc -c < "$zip_hacs" | tr -d ' ')"
            obtido="$(shasum -a 256 "$zip_hacs" | awk '{print $1}')"
            if [ "$tam" != "$HAOS_HACS_BYTES" ] || [ "$obtido" != "$HAOS_HACS_SHA" ]; then
                rm -f "$zip_hacs"
                ha_err "$(msg arq_hacs_falhou)"; desmontar_smb; return 1
            fi
            mkdir -p "$SMB_PONTO/custom_components/hacs"
            unzip -o -q "$zip_hacs" -d "$SMB_PONTO/custom_components/hacs" \
                || { desmontar_smb; return 1; }
            ha_ok "$(msg arq_hacs_ok "$HAOS_HACS_VERSION")"
            mudou=1
        fi
    fi

    if [ "$mudou" = "0" ]; then
        desmontar_smb
        return 100
    fi

    # check ANTES de reiniciar; reprovou → desfazer o configuration.yaml
    rc=0
    helper_cred core-check >/dev/null 2>>"$LOG_FILE" || rc=$?
    if [ "$rc" != "0" ]; then
        [ -n "$backup_conf" ] && cp "$backup_conf" "$SMB_PONTO/configuration.yaml"
        ha_err "$(msg arq_check_falhou)"; diagnostico_log
        desmontar_smb
        return 1
    fi
    desmontar_smb

    ha_info "$(msg arq_restart)"
    helper_cred core-restart >/dev/null 2>>"$LOG_FILE" || true
    # esperar CAIR primeiro — um curl imediato acerta o Core velho (banca)
    local t=0
    while [ "$t" -lt 60 ]; do
        vm_url_de "$VM_IP" >/dev/null 2>&1 || break
        sleep 2; t=$(( t + 2 ))
    done
    t=0
    local limite="${HAOS_BOOT_TIMEOUT:-300}" nova=""
    while [ "$t" -lt "$limite" ]; do
        nova="$(vm_url_de "$VM_IP" || true)"
        [ -n "$nova" ] && break
        sleep "${HAOS_BOOT_PASSO:-5}"; t=$(( t + ${HAOS_BOOT_PASSO:-5} ))
    done
    if [ -z "$nova" ]; then
        ha_warn "$(msg arq_nao_voltou "$limite")"
    else
        VM_URL="$nova"
        vm_set vm_url "$VM_URL"
        ha_ok "$(msg arq_voltou)"
    fi
    return 0
}


# =============================================================================
# --doctor · --uninstall · --self-update
# =============================================================================

# ── --doctor: diagnóstico read-only ──────────────────────────────────────────
# Instala nada, muda nada — só mede e conta. Separa o que o INSTALADOR resolve
# (aviso) do que só o usuário resolve (falha), como o doctor do AtlasFile.
DOC_OK=0; DOC_WARN=0; DOC_FAIL=0
doc_ok()   { DOC_OK=$((DOC_OK+1));     ha_ok "$1"; }
doc_warn() { DOC_WARN=$((DOC_WARN+1)); ha_warn "$1"; }
doc_fail() { DOC_FAIL=$((DOC_FAIL+1)); ha_err "$1"; }

rodar_doctor() {
    sonda
    ha_fase "$(msg doc_sistema)"
    doc_ok "$(msg doc_maquina "$(p_get host.model)" "$(p_get host.arch)" "$(p_get host.macos)")"

    ha_fase "$(msg doc_prereq)"
    if [ "$(p_get vbox.present)" = "1" ]; then
        doc_ok "$(msg doc_vbox_ok "$(p_get vbox.version)")"
    else
        doc_warn "$(msg doc_vbox_falta)"
    fi
    if [ "$(p_get python3.present)" = "1" ]; then
        doc_ok "$(msg doc_py_ok "$(python3 -V 2>&1 | awk '{print $2}')")"
    else
        doc_fail "$(msg doc_py_falta)"
    fi

    ha_fase "$(msg doc_manifesto)"
    local mf tem=0 chave valor
    for mf in "$(host_manifest)" "$(vm_manifest)"; do
        [ -f "$mf" ] || continue
        tem=1
        doc_ok "$mf"
        while IFS=$'\t' read -r chave valor; do
            case "$chave" in \#*|schema|'') continue ;; esac
            ha_linha "$(printf '    %-14s %s' "$chave" "$valor")"
        done < "$mf"
    done
    [ "$tem" = "1" ] || doc_warn "$(msg doc_sem_manifesto)"

    ha_fase "$(msg doc_imagem)"
    local vdi_path
    vdi_path="$(manifest_get "$(vm_manifest)" vdi_path)"
    if [ -n "$vdi_path" ] && [ -f "$vdi_path" ]; then
        doc_ok "$(msg doc_vdi_ok "$vdi_path")"
    else
        doc_warn "$(msg doc_vdi_falta "$OP_VM_NOME")"
    fi

    ha_fase "$(msg doc_estado)"
    local d; d="$(haos_state_dir)"
    if [ -f "$d/state" ]; then doc_ok "$(msg doc_state_ok "$d/state")"
    else doc_warn "$(msg doc_state_falta)"; fi
    [ -f "$d/last-run.log" ] && doc_ok "$(msg doc_lastrun_ok "$d/last-run.log")"

    printf '\n'
    ha_rule
    printf ' %s\n' "$(msg doc_veredito "$DOC_OK" "$DOC_WARN" "$DOC_FAIL")"
    [ "$DOC_FAIL" = "0" ]
}

# ── --uninstall: fatos → plano → UMA confirmação → execução prestando contas ─
# Remove SÓ o que o manifesto prova que este instalador criou; preexisting,
# pending e chave ausente preservam, cada um com a própria frase no plano.
# Nunca rm -rf: arquivos um a um, com guarda de prefixo, e diretório só por
# rmdir — se sobrar qualquer coisa de outra origem, a pasta fica.
UN_REMOVE=""; UN_KEEP=""; UN_ACOES=""; UN_N_OK=0; UN_N_KEEP=0
un_add_remove() { UN_REMOVE="${UN_REMOVE}${HA_GUT}  - $1\n"; }
un_add_keep()   { UN_KEEP="${UN_KEEP}${HA_GUT}  - $1\n"; UN_N_KEEP=$((UN_N_KEEP+1)); }
un_act()        { UN_ACOES="${UN_ACOES}$1\n"; }

# Guarda: o caminho gravado no manifesto pode ter sido adulterado — só
# removemos arquivo que esteja onde ESTE instalador escreve.
un_caminho_seguro() { # <caminho> <classe: vdi|zip|estado>
    case "$2" in
        vdi)    case "$1" in "$HOME/VirtualBox VMs/"*.vdi|"$HOME/VirtualBox VMs/"*.vdi.origem) return 0 ;; esac ;;
        agent)  case "$1" in "$HOME/Library/LaunchAgents/com.haos-mac-mini."*.plist)
                    # `*` de case casa `/` também — barrar travessia na cauda
                    case "${1#"$HOME/Library/LaunchAgents/"}" in */*) ;; *) return 0 ;; esac ;;
                esac ;;
        zip)    case "$1" in "$HOME/Library/Caches/haos-mac-mini/"*.zip|"$HOME/Library/Caches/haos-mac-mini/"*.dmg) return 0 ;; esac ;;
        estado) case "$1" in "$(haos_state_dir)/"*) return 0 ;; esac ;;
    esac
    return 1
}

un_montar_plano() {
    UN_REMOVE=""; UN_KEEP=""; UN_ACOES=""; UN_N_KEEP=0
    local vbox_st vdi_st vdi_path zip_st zip_path d
    vbox_st="$(manifest_get "$(host_manifest)" vbox)"
    vdi_st="$(manifest_get "$(vm_manifest)" vdi)"
    vdi_path="$(manifest_get "$(vm_manifest)" vdi_path)"
    zip_st="$(manifest_get "$(vm_manifest)" zip_cache)"
    zip_path="$(manifest_get "$(vm_manifest)" zip_path)"
    d="$(haos_state_dir)"

    # VirtualBox: extensão de sistema — created ganha a instrução do vendedor,
    # nunca uma remoção automática. Decisão registrada no CHANGELOG.
    case "$vbox_st" in
        created)     un_add_keep "$(msg un_vbox_created)" ;;
        pending)     un_add_keep "$(msg un_pendente VirtualBox)" ;;
        preexisting) un_add_keep "$(msg un_vbox_pre)" ;;
        *)           command -v VBoxManage >/dev/null 2>&1 && un_add_keep "$(msg un_vbox_pre)" ;;
    esac

    # O agente de auto-start sai PRIMEIRO — enquanto ele existir, um login
    # pode religar a VM no meio da remoção (achado da banca).
    local ag_st ag_path
    ag_st="$(manifest_get "$(vm_manifest)" autostart)"
    ag_path="$(manifest_get "$(vm_manifest)" autostart_path)"
    if [ "$ag_st" = "created" ] && [ -n "$ag_path" ] && [ -f "$ag_path" ]; then
        un_add_remove "$(msg un_agent "$ag_path")"
        un_act "rm-agent"
    fi

    # A VM sai ANTES do disco: desregistrar solta o medium que o rm vai apagar.
    local vmreg_st
    vmreg_st="$(manifest_get "$(vm_manifest)" vm_registrada)"
    case "$vmreg_st" in
        created)
            un_add_remove "$(msg un_vm "$OP_VM_NOME")"
            un_act "rm-vm" ;;
        pending)     un_add_keep "$(msg un_pendente VM)" ;;
        preexisting) un_add_keep "$(msg un_preexisting "VM $OP_VM_NOME")" ;;
    esac

    if [ "$vdi_st" = "created" ] && [ -n "$vdi_path" ] && [ -f "$vdi_path" ]; then
        if [ "$OP_KEEP_IMAGE" = "1" ]; then
            un_add_keep "$(msg un_keep_image_msg)"
        elif un_caminho_seguro "$vdi_path" vdi; then
            un_add_remove "$(msg un_vdi "$vdi_path")"
            un_act "rm-vdi"
            un_add_remove "$(msg un_dirvm "$(dirname "$vdi_path")")"
            un_act "rmdir-vm"
        fi
    elif [ "$vdi_st" = "pending" ]; then
        un_add_keep "$(msg un_pendente ".vdi")"
    elif [ -n "$vdi_path" ] && [ -f "$vdi_path" ]; then
        un_add_keep "$(msg un_preexisting "$vdi_path")"
    fi

    if [ "$zip_st" = "created" ] && [ -n "$zip_path" ] && [ -f "$zip_path" ] \
        && [ "$OP_KEEP_IMAGE" != "1" ] && un_caminho_seguro "$zip_path" zip; then
        un_add_remove "$(msg un_zip "$zip_path")"
        un_act "rm-zip"
    fi
    local dmg_st dmg_path
    dmg_st="$(manifest_get "$(host_manifest)" dmg_cache)"
    dmg_path="$(manifest_get "$(host_manifest)" dmg_path)"
    if [ "$dmg_st" = "created" ] && [ -n "$dmg_path" ] && [ -f "$dmg_path" ] \
        && un_caminho_seguro "$dmg_path" zip; then
        un_add_remove "$(msg un_zip "$dmg_path")"
        un_act "rm-dmg"
    fi

    if [ -f "$d/state" ] || [ -f "$d/last-run.log" ] || [ -f "$(host_manifest)" ] || [ -f "$(vm_manifest)" ]; then
        un_add_remove "$(msg un_registro)"
        un_act "rm-registro"
    fi
    return 0
}

un_rm() { # <caminho> <classe>
    if un_caminho_seguro "$1" "$2" && rm -f "$1" 2>/dev/null; then
        ha_ok "$(msg un_removido "$1")"
        UN_N_OK=$((UN_N_OK+1))
    else
        ha_err "$(msg un_nao_removido "$1")"
    fi
}

un_executar() {
    local acao vdi_path zip_path d ag_path esp
    vdi_path="$(manifest_get "$(vm_manifest)" vdi_path)"
    zip_path="$(manifest_get "$(vm_manifest)" zip_path)"
    ag_path="$(manifest_get "$(vm_manifest)" autostart_path)"
    d="$(haos_state_dir)"
    while IFS= read -r acao; do
        [ -n "$acao" ] || continue
        case "$acao" in
            rm-agent)
                launchctl bootout "gui/$(id -u)/$(basename "${ag_path%.plist}")" >/dev/null 2>&1 || true
                un_rm "$ag_path" agent ;;
            rm-vm)
                command -v VBoxManage >/dev/null 2>&1 \
                    || PATH="$PATH:/Applications/VirtualBox.app/Contents/MacOS"
                # desligar antes de desregistrar (unregister falha em VM viva)
                # e soltar o medium primeiro — `unregistervm --delete` apagaria
                # o .vdi, inclusive sob --keep-image
                if command -v VBoxManage >/dev/null 2>&1 \
                    && { if VBoxManage list runningvms 2>/dev/null | grep -qF "\"$OP_VM_NOME\""; then
                             VBoxManage controlvm "$OP_VM_NOME" poweroff >/dev/null 2>&1 || true
                             esp=0
                             while [ "$esp" -lt 30 ] && VBoxManage list runningvms 2>/dev/null \
                                 | grep -qF "\"$OP_VM_NOME\""; do sleep 1; esp=$((esp+1)); done
                         fi
                         VBoxManage storageattach "$OP_VM_NOME" --storagectl SATA \
                             --port 0 --device 0 --medium none >/dev/null 2>&1 || true
                         [ -z "$vdi_path" ] \
                             || VBoxManage closemedium disk "$vdi_path" >/dev/null 2>&1 || true
                         VBoxManage unregistervm "$OP_VM_NOME" >/dev/null 2>&1; }; then
                    rm -f "$HOME/VirtualBox VMs/$OP_VM_NOME/$OP_VM_NOME.vbox" 2>/dev/null || true
                    ha_ok "$(msg un_removido "VM $OP_VM_NOME")"
                    UN_N_OK=$((UN_N_OK+1))
                else
                    ha_err "$(msg un_nao_removido "VM $OP_VM_NOME")"
                fi ;;
            rm-vdi)
                un_rm "$vdi_path" vdi
                un_rm "$(dirname "$vdi_path")/.$(basename "$vdi_path").origem" vdi ;;
            rmdir-vm)
                rmdir "$(dirname "$vdi_path")" 2>/dev/null || true ;;
            rm-zip)
                un_rm "$zip_path" zip
                rmdir "$HOME/Library/Caches/haos-mac-mini" 2>/dev/null || true ;;
            rm-dmg)
                un_rm "$(manifest_get "$(host_manifest)" dmg_path)" zip
                rmdir "$HOME/Library/Caches/haos-mac-mini" 2>/dev/null || true ;;
            rm-registro)
                # o registro sai POR ÚLTIMO: falhar no meio deixa artefato
                # órfão, mas nunca artefato órfão SEM memória dele.
                un_rm "$(vm_manifest)" estado
                un_rm "$(host_manifest)" estado
                un_rm "$d/state" estado
                un_rm "$d/last-run.log" estado
                rmdir "$d/vms" 2>/dev/null || true
                rmdir "$d" 2>/dev/null || true ;;
        esac
    done <<EOF
$(printf '%b' "$UN_ACOES")
EOF
    return 0
}

rodar_uninstall() {
    un_montar_plano
    ha_fase "$(msg un_plano_titulo)"
    if [ -z "$UN_ACOES" ] && [ -z "$UN_KEEP" ]; then
        ha_info "$(msg un_nada)"
        return 0
    fi
    if [ -n "$UN_REMOVE" ]; then
        ha_linha "$(msg un_remove)"
        printf '%b' "$UN_REMOVE"
    fi
    if [ -n "$UN_KEEP" ]; then
        ha_linha "$(msg un_keep)"
        printf '%b' "$UN_KEEP"
    fi
    if [ -z "$UN_ACOES" ]; then
        ha_info "$(msg un_nada)"
        return 0
    fi
    if [ "$OP_DRYRUN" = "1" ]; then
        ha_info "$(msg nada_escrito)"
        return 0
    fi
    if tem_tty && [ "$OP_NOINPUT" != "1" ] && [ -z "$OP_CONFIRM" ]; then
        perguntar "$(msg un_confirmar)" || { ha_info "$(msg cancelado)"; return "$E_CANCELADO"; }
    else
        # Sem terminal a confirmação é o NOME da VM — um yes genérico num
        # script não pode desinstalar a VM errada.
        if [ "$OP_CONFIRM" != "$OP_VM_NOME" ]; then
            [ -z "$OP_CONFIRM" ] && { ha_err "$(msg un_sem_tty)"; return "$E_USO"; }
            ha_err "$(msg un_confirm_errado "$OP_CONFIRM" "$OP_VM_NOME")"
            return "$E_USO"
        fi
    fi
    un_executar
    printf '\n'
    ha_ok "$(msg un_placar "$UN_N_OK" "$UN_N_KEEP")"
    return 0
}

# ── --self-update ────────────────────────────────────────────────────────────
# bash -n + comparação de versão + hash antes de trocar; downgrade é RECUSADO
# (achado B-1 da banca: com o main atrasado, atualizar rebaixaria o script).
ver_menor() { # <a> <b> — 0 quando a < b (compara X.Y.Z, sufixo -dev fora)
    local a="${1%%-*}" b="${2%%-*}" a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<EOF
$a
EOF
    IFS=. read -r b1 b2 b3 <<EOF
$b
EOF
    [ "${a1:-0}" != "${b1:-0}" ] && { [ "${a1:-0}" -lt "${b1:-0}" ]; return; }
    [ "${a2:-0}" != "${b2:-0}" ] && { [ "${a2:-0}" -lt "${b2:-0}" ]; return; }
    [ "${a3:-0}" -lt "${b3:-0}" ]
}

rodar_self_update() {
    local eu="${BASH_SOURCE[0]:-}"
    if [ -z "$eu" ] || [ ! -f "$eu" ]; then
        ha_info "$(msg su_pipe)"
        return 0
    fi
    local tmp ver_remota
    tmp="$(mktempfile)"
    garantir_log
    if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp" "$HAOS_RAW_URL" 2>>"$LOG_FILE"; then
        ha_err "$(msg su_baixa_falhou)"; diagnostico_log; return 1
    fi
    bash -n "$tmp" 2>/dev/null || { ha_err "$(msg su_invalido)"; return 1; }
    ver_remota="$(grep -m1 '^HAOS_INSTALL_VERSION=' "$tmp" | cut -d'"' -f2)"
    [ -n "$ver_remota" ] || { ha_err "$(msg su_invalido)"; return 1; }
    if ver_menor "$ver_remota" "$HAOS_INSTALL_VERSION"; then
        ha_err "$(msg su_downgrade "$ver_remota" "$HAOS_INSTALL_VERSION")"
        return 1
    fi
    if [ "$(shasum -a 256 "$eu" | awk '{print $1}')" = "$(shasum -a 256 "$tmp" | awk '{print $1}')" ]; then
        ha_ok "$(msg su_igual "$HAOS_INSTALL_VERSION")"
        return 0
    fi
    if tem_tty && [ "$OP_NOINPUT" != "1" ]; then
        perguntar "$(msg su_confirma "$HAOS_INSTALL_VERSION" "$ver_remota")" \
            || { ha_info "$(msg cancelado)"; return "$E_CANCELADO"; }
    fi
    cp "$eu" "$eu.bak"
    cat "$tmp" > "$eu"
    chmod +x "$eu" 2>/dev/null || true
    ha_ok "$(msg su_ok "$ver_remota" "$eu.bak")"
    return 0
}

# =============================================================================
# CAMADA VISUAL — cópia embutida de lib/haos-ui.sh. NÃO editar aqui.
# O shebang e o `set` da origem são removidos na cópia: valendo aqui, mudariam
# as opções do instalador em silêncio.
# =============================================================================
# >>> UI EMBUTIDO >>>
# haos-ui.sh — camada visual do instalador do HAOS, identidade Home Assistant.
# Source it as a library, or run it directly for the demo:  ./lib/haos-ui.sh --demo
#
# Design notes:
#   - Palette is Home Assistant's own: #03A9F4 primary, #00E5FF cyan, #FFC107 amber.
#   - Truecolor when available, 256-color fallback, plain text when neither.
#   - Every animation degrades to a single static frame when stdout is not a TTY,
#     when NO_COLOR is set, or when --no-anim is passed. A piped log stays readable.

# ── capability detection ────────────────────────────────────────────────────
HAOS_UI_ANIM=1
[[ -t 1 ]] || HAOS_UI_ANIM=0
[[ -n "${NO_COLOR:-}" ]] && HAOS_UI_ANIM=0
[[ "${HAOS_NO_ANIM:-0}" == "1" ]] && HAOS_UI_ANIM=0

# ── UTF-8 ────────────────────────────────────────────────────────────────────
# A arte é toda de caracteres multibyte. Sob locale C o bash conta e fatia
# BYTES: `${linha:col:1}` devolveria um terço de caractere, e a tela receberia
# UTF-8 inválido. Medido em 23/08 num Mac mini por SSH, onde LC_CTYPE=C: a
# mesma linha media 42 aqui e 118 lá.
#
# E se o locale não é UTF-8, o terminal provavelmente não desenha os glifos de
# qualquer forma. Então a resposta certa não é forçar o locale do usuário — é
# degradar para texto simples.
HAOS_UI_UTF8=0
if [ "$(LC_ALL="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" /bin/bash -c 's=▟▙; printf %s "${#s}"')" = "2" ]; then
  HAOS_UI_UTF8=1
fi
[[ "$HAOS_UI_UTF8" == 0 ]] && HAOS_UI_ANIM=0

case "${COLORTERM:-}" in
  truecolor|24bit) HAOS_UI_DEPTH=24 ;;
  *) [[ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]] && HAOS_UI_DEPTH=8 || HAOS_UI_DEPTH=0 ;;
esac
[[ -t 1 ]] || HAOS_UI_DEPTH=0
[[ -n "${NO_COLOR:-}" ]] && HAOS_UI_DEPTH=0

# ── Home Assistant palette ──────────────────────────────────────────────────
# Compatível com bash 3.2 (o que o macOS traz): sem namerefs, sem array indirection.
HA_BLUE_R=3;    HA_BLUE_G=169; HA_BLUE_B=244    # #03A9F4  primary
HA_CYAN_R=0;    HA_CYAN_G=229; HA_CYAN_B=255    # #00E5FF  accent
HA_DEEP_R=1;    HA_DEEP_G=87;  HA_DEEP_B=155    # #01579B  deep
if [[ "$HAOS_UI_DEPTH" == 0 ]]; then NC=''; BOLD=''; DIM=''
else NC=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; fi

# ── glifos, com fallback ASCII ───────────────────────────────────────────────
# UMA fonte para todo caractere multibyte das linhas de status. Sob locale
# não-UTF-8 o terminal recebe os bytes crus de "✔" — medido num Mac mini por
# SSH com LC_CTYPE=C. A cerca do portão exercita ESTAS funções sob LC_ALL=C,
# não só o banner (achado B-3 da banca).
if [[ "$HAOS_UI_UTF8" == 1 ]]; then
  HA_G_OK='✔'; HA_G_INFO='•'; HA_G_WARN='▲'; HA_G_ERR='✖'; HA_G_SKIP='◦'
  HA_G_DOTS='…'; HA_G_REGUA='─'; HA_G_MARCA='▎'
  HA_G_SEP='·'; HA_G_DASH='—'
  HA_G_GUT='│'; HA_G_ASK='?'; HA_G_RAMO='├──'
  HA_G_CHEIO='━'; HA_G_VAZIO='╌'; HA_G_BON='▰'; HA_G_BOFF='▱'
  HA_SPIN_F='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; HA_SPIN_N=10
else
  HA_G_OK='[OK]'; HA_G_INFO='[i]'; HA_G_WARN='[!]'; HA_G_ERR='[X]'; HA_G_SKIP='[-]'
  HA_G_DOTS='...'; HA_G_REGUA='-'; HA_G_MARCA='>'
  HA_G_SEP='-'; HA_G_DASH='--'
  HA_G_GUT='|'; HA_G_ASK='?'; HA_G_RAMO='+--'
  HA_G_CHEIO='#'; HA_G_VAZIO='-'; HA_G_BON='#'; HA_G_BOFF='-'
  HA_SPIN_F='-\|/'; HA_SPIN_N=4
fi

rgb() { # rgb R G B -> escape
  case "$HAOS_UI_DEPTH" in
    24) printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3" ;;
    8)  printf '\033[38;5;%dm' "$(( 16 + 36*($1*5/255) + 6*($2*5/255) + ($3*5/255) ))" ;;
    *)  printf '' ;;
  esac
}
# Escapes pré-computados uma vez: mais rápido que um subshell por chamada.
C_BLUE="$(rgb 3 169 244)";   C_CYAN="$(rgb 0 229 255)"
C_AMBER="$(rgb 255 193 7)";  C_GREEN="$(rgb 76 175 80)"
C_RED="$(rgb 244 67 54)";    C_MUTED="$(rgb 96 125 139)"

# ── a calha vertical ─────────────────────────────────────────────────────────
# Toda mensagem pendura numa trilha contínua — a gramática do mac-env-setup
# que o AtlasFile adotou dizendo o porquê: linhas soltas leem como lista, a
# calha lê como FLUXO. Pedido do dono no segundo teste real.
HA_GUT="${C_MUTED}${HA_G_GUT}${NC} "

# ── gradient across a string, HA_DEEP -> HA_BLUE -> HA_CYAN ─────────────────
ha_gradient() {
  local s="$1" n=${#1} i out='' t r g b
  (( n == 0 )) && return
  # Sob locale não-UTF-8, ${s:i:1} fatia BYTES: inserir escape de cor entre os
  # bytes de um caractere multibyte quebra a sequência na tela. Texto plano.
  if [[ "$HAOS_UI_DEPTH" == 0 || "$HAOS_UI_UTF8" == 0 ]]; then printf '%s' "$s"; return; fi
  for (( i=0; i<n; i++ )); do
    t=$(( i * 200 / (n>1 ? n-1 : 1) ))
    if (( t <= 100 )); then
      r=$(( HA_DEEP_R + (HA_BLUE_R-HA_DEEP_R)*t/100 ))
      g=$(( HA_DEEP_G + (HA_BLUE_G-HA_DEEP_G)*t/100 ))
      b=$(( HA_DEEP_B + (HA_BLUE_B-HA_DEEP_B)*t/100 ))
    else
      local u=$(( t-100 ))
      r=$(( HA_BLUE_R + (HA_CYAN_R-HA_BLUE_R)*u/100 ))
      g=$(( HA_BLUE_G + (HA_CYAN_G-HA_BLUE_G)*u/100 ))
      b=$(( HA_BLUE_B + (HA_CYAN_B-HA_BLUE_B)*u/100 ))
    fi
    out+="$(rgb "$r" "$g" "$b")${s:i:1}"
  done
  printf '%s%s' "$out" "$NC"
}

# ── cursor ───────────────────────────────────────────────────────────────────
# A biblioteca NÃO instala trap: `trap` é global do shell e quem chama por
# último vence — um trap aqui apagaria o cleanup do instalador. Quem usa chama
# ha_show_cursor no próprio cleanup.
_hide() { if [[ "$HAOS_UI_ANIM" == 1 ]]; then tput civis 2>/dev/null || true; fi; }
_show() { if [[ "$HAOS_UI_ANIM" == 1 ]]; then tput cnorm 2>/dev/null || true; fi; }
ha_show_cursor() { _show; }

# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────
# Geometria conferida contra o vídeo oficial: beiral, ápice pontudo,
# base com raio moderado. Máscara por pixel: . fora · # casa · o circuito.
# HA_TX/HA_TY/HA_TT: faixa do traço ordenada pela posição no caminho —
# cabeça e cauda animam por posição de ARCO, não por índice de pixel.
# HA_PX/HA_PY/HA_PD: pixels dos 3 discos (1 topo · 2 direita · 3 esquerda).
HA_W=34
HA_H=34
HA_CAMINHO=342
HA_MASK=(
'..................................'
'..................................'
'..................................'
'..................................'
'..................................'
'...............####...............'
'..............######..............'
'.............########.............'
'............##########............'
'...........############...........'
'..........######oo######..........'
'........#######oooo#######........'
'.......#######oooooo#######.......'
'......#########oooo#########......'
'.....##########oooo##########.....'
'....############oo############....'
'....############oo###ooo######....'
'....############oo##ooooo#####....'
'....############oo##ooooo#####....'
'....############oo##ooooo#####....'
'....######ooo###oo#oooooo#####....'
'....#####ooooo##ooooo#########....'
'....#####ooooo##oooo##########....'
'....#####ooooo##ooo###########....'
'....######ooooo#oo############....'
'....#########ooooo############....'
'....##########oooo############....'
'....###########ooo############....'
'....############oo############....'
'.....########################.....'
'..................................'
'..................................'
'..................................'
'..................................'
)
HA_TX=(16 16 15 15 14 14 13 13 12 12 11 11 10 10 9 9 8 8 7 7 6 6 5 5 5 4 4 3 3 4 3 2 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 2 3 3 4 4 4 5 5 5 6 6 6 7 7 7 8 8 8 9 9 9 10 10 10 11 11 12 12 12 13 13 13 14 14 14 15 15 15 16 16 17 17 18 18 18 19 19 20 19 20 20 21 21 22 21 23 22 23 24 23 24 25 24 25 26 25 26 26 27 27 28 27 28 29 28 29 30 29 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 31 30 29 30 29 30 29 28 28 28 27 27 26 26 25 25 24 24 23 23 22 22 21 21 20 20 19 19 18 18 17 17)
HA_TY=(30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 31 30 29 30 29 30 29 28 28 28 27 27 26 26 25 25 24 24 23 23 22 22 21 21 20 20 19 19 18 18 17 17 16 16 15 15 14 15 14 13 14 13 12 13 12 11 12 11 10 11 10 9 10 9 8 9 8 7 8 7 8 7 6 7 6 5 6 5 4 5 4 3 4 3 3 4 3 4 5 4 5 5 6 6 7 6 7 7 8 7 8 8 8 9 9 9 10 10 10 11 11 12 11 12 12 13 13 13 14 14 14 15 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 28 29 29 30 30 29 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31 30 31)
HA_TT=(2 2 6 6 10 10 14 14 18 18 22 22 26 26 30 30 34 34 38 38 42 42 44 45 46 47 49 49 51 52 53 54 56 56 60 60 64 64 68 68 72 72 76 76 80 80 84 84 88 88 92 92 96 96 100 100 103 104 105 105 108 110 110 113 116 116 119 121 122 124 127 127 130 133 133 135 138 138 141 144 144 147 147 150 152 153 155 158 158 161 163 164 166 168 169 170 172 173 174 176 178 179 181 184 184 187 189 190 192 195 195 198 198 201 204 204 207 209 209 212 215 215 218 220 221 223 226 226 229 232 232 234 237 237 238 239 242 242 246 246 250 250 254 254 258 258 262 262 266 266 270 270 274 274 278 278 282 282 286 286 288 289 290 291 293 293 295 296 297 298 300 300 304 304 308 308 312 312 316 316 320 320 324 324 328 328 332 332 336 336 340 340)
HA_PX=(16 17 15 16 17 18 14 15 16 17 18 19 15 16 17 18 15 16 17 18 21 22 23 20 21 22 23 24 20 21 22 23 24 20 21 22 23 24 10 11 12 21 22 23 24 9 10 11 12 13 9 10 11 12 13 9 10 11 12 13 10 11 12)
HA_PY=(10 10 11 11 11 11 12 12 12 12 12 12 13 13 13 13 14 14 14 14 16 16 16 17 17 17 17 17 18 18 18 18 18 19 19 19 19 19 20 20 20 20 20 20 20 21 21 21 21 21 22 22 22 22 22 23 23 23 23 23 24 24 24)
HA_PD=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 3 3 3 2 2 2 2 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3)
# Partículas do assemble: destino (AX,AY), origem (AOX,AOY), atraso (ADL).
HA_AX=(15 16 17 18 14 15 16 17 18 19 13 14 15 16 17 18 19 20 12 13 14 15 16 17 18 19 20 21 11 12 13 14 15 16 17 18 19 20 21 22 10 11 12 13 14 15 16 17 18 19 20 21 22 23 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28)
HA_AY=(5 5 5 5 6 6 6 6 6 6 7 7 7 7 7 7 7 7 8 8 8 8 8 8 8 8 8 8 9 9 9 9 9 9 9 9 9 9 9 9 10 10 10 10 10 10 10 10 10 10 10 10 10 10 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29)
HA_AOX=(33 36 39 41 32 35 39 42 45 41 27 30 34 37 41 44 47 50 23 26 30 33 37 41 45 48 51 45 19 22 25 29 34 38 43 47 43 45 47 49 13 16 20 24 29 30 35 39 43 47 50 52 54 55 8 9 11 14 17 21 26 32 39 38 42 46 49 50 52 53 54 55 4 5 6 8 10 13 18 24 31 33 39 44 48 50 52 53 54 55 46 47 0 0 0 1 3 5 8 14 19 26 34 42 48 52 54 55 47 47 48 49 49 50 -5 -5 -5 0 0 1 2 4 8 13 22 35 40 46 49 50 50 51 51 51 52 44 45 45 -5 -6 -6 -7 -7 -7 -1 -1 0 1 5 13 30 49 55 47 47 47 47 47 48 48 49 49 42 43 -7 -7 -8 -9 -9 -10 -10 -4 -4 -4 -4 -1 13 53 51 50 42 43 43 44 44 45 46 46 47 41 -7 -8 -9 -10 -11 -12 -13 -14 -8 -9 -11 -14 -17 20 36 40 42 38 39 40 41 42 43 43 44 45 -8 -9 -10 -11 -12 -14 -15 -17 -18 -12 -14 -15 -11 4 20 28 33 37 34 36 37 38 39 40 41 42 -16 -10 -11 -12 -13 -15 -16 -18 -19 -21 -13 -12 -8 0 11 20 26 30 33 31 33 35 36 37 38 39 -17 -18 -11 -12 -14 -15 -16 -18 -19 -20 -20 -10 -6 0 7 14 20 24 28 31 29 31 33 34 35 37 -17 -18 -19 -12 -13 -15 -16 -17 -18 -18 -18 -15 -5 0 5 10 15 20 23 26 29 28 30 31 33 34 -17 -18 -19 -21 -13 -14 -15 -16 -16 -16 -16 -13 -10 0 3 8 12 16 20 23 25 28 27 29 30 31 -16 -18 -19 -20 -21 -13 -14 -15 -15 -15 -14 -12 -9 -5 3 6 10 13 17 20 22 25 27 26 28 29 -16 -17 -18 -19 -20 -21 -13 -13 -13 -13 -12 -10 -8 -5 -1 5 8 11 14 17 20 22 24 26 25 27 -15 -16 -17 -18 -19 -20 -20 -12 -12 -11 -10 -9 -7 -4 -1 1 7 10 12 15 17 20 22 24 26 25 -14 -15 -16 -17 -18 -18 -19 -19 -10 -10 -9 -8 -6 -4 -1 0 3 9 11 13 15 18 20 22 23 25 -13 -14 -15 -16 -16 -17 -17 -17 -17 -9 -8 -7 -5 -3 -1 0 3 5 10 12 14 16 18 20 21 23 -21 -13 -14 -15 -15 -16 -16 -16 -16 -15 -7 -6 -5 -3 -1 0 2 4 7 11 13 14 16 18 20 21 -20 -21 -12 -13 -13 -14 -14 -13 -13 -12 -11 -3 -2 0 0 2 4 6 8 10 13 15 17 18)
HA_AOY=(-8 -8 -7 -5 -13 -13 -12 -10 -8 -1 -12 -12 -11 -10 -9 -7 -4 -2 -12 -13 -12 -12 -10 -8 -6 -3 0 5 -14 -15 -15 -15 -14 -12 -10 -7 0 3 6 9 -17 -18 -19 -19 -19 -10 -8 -6 -3 0 3 7 10 13 -12 -13 -15 -16 -17 -18 -18 -17 -14 -4 -1 2 6 10 13 16 19 21 -10 -12 -13 -15 -16 -18 -19 -19 -18 -8 -4 0 4 9 13 17 20 23 23 24 -10 -12 -13 -15 -17 -18 -20 -13 -14 -14 -11 -6 0 7 13 18 21 23 25 27 28 30 -11 -13 -14 -8 -9 -11 -13 -15 -17 -19 -20 -16 -2 6 14 19 23 26 28 30 32 30 31 32 -7 -8 -9 -10 -11 -13 -7 -8 -10 -12 -15 -18 -17 -2 13 21 26 28 31 32 34 35 36 37 33 34 -4 -5 -6 -7 -8 -9 -10 -4 -5 -7 -9 -12 -18 13 30 35 33 34 35 36 37 38 39 39 40 35 -2 -2 -3 -3 -4 -4 -4 -5 0 0 1 4 20 52 48 46 45 39 39 39 40 40 41 41 42 42 0 0 0 0 0 0 0 1 2 8 12 19 34 49 52 51 50 49 42 42 42 42 43 43 43 44 -1 2 2 3 3 4 5 7 9 13 19 27 37 46 51 52 52 52 51 43 43 44 44 44 45 45 1 1 5 6 7 8 9 12 15 20 26 30 38 44 49 51 52 52 52 52 44 44 45 45 45 46 4 4 5 9 10 11 13 16 20 24 30 37 38 43 47 49 51 52 52 53 53 45 45 46 46 46 7 7 8 10 13 14 17 19 23 27 32 38 44 42 45 48 50 51 52 53 53 53 45 46 46 47 9 10 11 13 15 17 19 22 25 29 34 39 43 48 44 46 48 50 51 52 53 53 54 46 46 47 11 12 14 15 17 20 21 24 27 31 35 39 43 47 50 45 47 49 50 51 52 53 53 54 46 46 13 14 16 18 20 22 25 25 28 32 35 39 42 46 49 52 46 47 49 50 51 52 53 53 54 46 15 16 18 20 22 24 27 30 29 32 35 39 42 45 48 51 53 46 48 49 50 51 52 53 53 54 17 18 19 21 23 25 28 31 34 33 35 38 41 44 47 49 51 53 46 48 49 50 51 52 53 54 18 19 21 22 24 27 29 32 35 38 35 38 41 43 46 48 50 52 54 47 48 49 50 51 52 53 21 23 23 25 27 29 32 34 37 40 43 39 41 44 46 48 50 52 53 55 47 48 49 50)
HA_ADL=(9 10 11 9 10 11 9 10 11 9 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1)
# Centros dos discos (sonar), em pixel inteiro: topo, direita, esquerda.
HA_SCX=(17 22 11)
HA_SCY=(12 18 22)

# ── a abertura: constelação → traço → sonar → respiração ─────────────────────
# Quatro atos, ~3 s. O que cada um é, e por quê:
#   1. CONSTELAÇÃO — cada pixel da casa é uma partícula que voa de fora da
#      tela em trajetória radial (com um giro de 40°) e ASSENTA no lugar,
#      construindo a casa de baixo para cima. Trajetórias pré-computadas pelo
#      gerador; o runtime só interpola inteiros.
#   2. O TRAÇO OFICIAL — a caneta branca desenha o contorno INTEIRO e se
#      retrai, por posição de arco (conferido contra o vídeo do logo).
#   3. SONAR — cada disco do circuito emite dois anéis ciano que varrem o
#      corpo azul: os dispositivos entrando na rede, visível.
#   4. RESPIRAÇÃO — o azul pulsa uma vez mais claro e assenta.
# O corpo azul tem GRADIENTE VERTICAL (mais claro no topo): volume, não sprite.
# Sem animação: um quadro final parado. Sem UTF-8 ou sem cor: só o título.

HA_MIN_COLS=36
HA_ATRASO=0.03
HA_A_DUR=8           # quadros de voo de cada partícula
HA_Q_MONTA=22        # constelação (delay máx + voo)
HA_Q_TRACO=34        # metade desenha, metade retrai
HA_Q_SONAR=15        # 3 discos x 5 raios
HA_Q_GLOW=5
HA_QUADROS=$(( HA_Q_MONTA + HA_Q_TRACO + HA_Q_SONAR + HA_Q_GLOW ))
HA_LINHAS=$(( HA_H / 2 ))

ha_logo_init() {
  [ -n "${HA_LOGO_PRONTO:-}" ] && return 0
  local y r g b t
  # Azul HA com gradiente vertical: do #35b6f8 (topo) ao #0277BD (base).
  # Um escape de frente e um de fundo POR LINHA, pré-computados uma vez.
  HA_FGA=(); HA_BGA=()
  for (( y = 0; y < HA_H; y++ )); do
    t=$(( y * 100 / (HA_H - 1) ))
    r=$(( 53 - (53 - 2) * t / 100 ))
    g=$(( 182 - (182 - 119) * t / 100 ))
    b=$(( 248 - (248 - 189) * t / 100 ))
    if [[ "$HAOS_UI_DEPTH" == 24 ]]; then
      HA_FGA[y]=$'\033[38;2;'"$r;$g;$b"m
      HA_BGA[y]=$'\033[48;2;'"$r;$g;$b"m
    else
      HA_FGA[y]=$'\033[38;5;39m'; HA_BGA[y]=$'\033[48;5;39m'
    fi
  done
  if [[ "$HAOS_UI_DEPTH" == 24 ]]; then
    HA_FG_BRANCO=$'\033[38;2;236;242;248m'; HA_BG_BRANCO=$'\033[48;2;236;242;248m'
    HA_FG_TRACO=$'\033[38;2;255;255;255m';  HA_BG_TRACO=$'\033[48;2;255;255;255m'
    HA_FG_PULSO=$'\033[38;2;0;229;255m';    HA_BG_PULSO=$'\033[48;2;0;229;255m'
    HA_FG_FAGULHA=$'\033[38;2;120;220;255m'
    HA_FG_GLOW=$'\033[38;2;120;214;255m';   HA_BG_GLOW=$'\033[48;2;120;214;255m'
  else
    HA_FG_BRANCO=$'\033[38;5;255m'; HA_BG_BRANCO=$'\033[48;5;255m'
    HA_FG_TRACO=$'\033[38;5;231m';  HA_BG_TRACO=$'\033[48;5;231m'
    HA_FG_PULSO=$'\033[38;5;51m';   HA_BG_PULSO=$'\033[48;5;51m'
    HA_FG_FAGULHA=$'\033[38;5;117m'
    HA_FG_GLOW=$'\033[38;5;117m';   HA_BG_GLOW=$'\033[48;5;117m'
  fi
  HA_LOGO_PRONTO=1
}

# O quadro é montado num buffer de MÁSCARA mutável (QM), linha a linha, e um
# render único pinta as classes: . fora · # azul · o branco · t traço ·
# p pulso ciano · a partícula em voo · g glow. Substituição posicional de
# string é O(1) por pixel — é o que deixa 470 partículas por quadro baratas.
ha_qm_reset_vazio() { local y; QM=(); for (( y = 0; y < HA_H; y++ )); do QM[y]="$HA_QM_VAZIA"; done; }
ha_qm_reset_mask()  { local y; QM=(); for (( y = 0; y < HA_H; y++ )); do QM[y]="${HA_MASK[y]}"; done; }
ha_qm_poe() { # <x> <y> <classe>
  [ "$2" -ge 0 ] && [ "$2" -lt "$HA_H" ] && [ "$1" -ge 0 ] && [ "$1" -lt "$HA_W" ] || return 0
  QM[$2]="${QM[$2]:0:$1}$3${QM[$2]:$(( $1 + 1 ))}"
}

ha_render_qm() {
  local y1 y2 x c1 c2 saida
  for (( y1 = 0; y1 < HA_H; y1 += 2 )); do
    y2=$(( y1 + 1 ))
    saida=''
    local fa1="${HA_FGA[y1]}" fa2bg="${HA_BGA[y2]}" fa2="${HA_FGA[y2]}"
    for (( x = 0; x < HA_W; x++ )); do
      c1="${QM[$y1]:$x:1}"; c2="${QM[$y2]:$x:1}"
      case "$c1$c2" in
        '..') saida+="${NC} " ;;
        '.#') saida+="${NC}${fa2}▄" ;;
        '#.') saida+="${NC}${fa1}▀" ;;
        '##') saida+="${fa1}${fa2bg}▀" ;;
        '.o') saida+="${NC}${HA_FG_BRANCO}▄" ;;
        'o.') saida+="${NC}${HA_FG_BRANCO}▀" ;;
        'oo') saida+="${HA_FG_BRANCO}${HA_BG_BRANCO}▀" ;;
        '#o') saida+="${fa1}${HA_BG_BRANCO}▀" ;;
        'o#') saida+="${HA_FG_BRANCO}${fa2bg}▀" ;;
        '.t') saida+="${NC}${HA_FG_TRACO}▄" ;;
        't.') saida+="${NC}${HA_FG_TRACO}▀" ;;
        'tt') saida+="${HA_FG_TRACO}${HA_BG_TRACO}▀" ;;
        '#t') saida+="${fa1}${HA_BG_TRACO}▀" ;;
        't#') saida+="${HA_FG_TRACO}${fa2bg}▀" ;;
        'ot') saida+="${HA_FG_BRANCO}${HA_BG_TRACO}▀" ;;
        'to') saida+="${HA_FG_TRACO}${HA_BG_BRANCO}▀" ;;
        '.p') saida+="${NC}${HA_FG_PULSO}▄" ;;
        'p.') saida+="${NC}${HA_FG_PULSO}▀" ;;
        'pp') saida+="${HA_FG_PULSO}${HA_BG_PULSO}▀" ;;
        '#p') saida+="${fa1}${HA_BG_PULSO}▀" ;;
        'p#') saida+="${HA_FG_PULSO}${fa2bg}▀" ;;
        'op') saida+="${HA_FG_BRANCO}${HA_BG_PULSO}▀" ;;
        'po') saida+="${HA_FG_PULSO}${HA_BG_BRANCO}▀" ;;
        '.a') saida+="${NC}${HA_FG_FAGULHA}▄" ;;
        'a.') saida+="${NC}${HA_FG_FAGULHA}▀" ;;
        'aa') saida+="${HA_FG_FAGULHA}${HA_BG_PULSO}▀" ;;
        'a#') saida+="${HA_FG_FAGULHA}${fa2bg}▀" ;;
        '#a') saida+="${fa1}${HA_BG_PULSO}▀" ;;
        'ao') saida+="${HA_FG_FAGULHA}${HA_BG_BRANCO}▀" ;;
        'oa') saida+="${HA_FG_BRANCO}${HA_BG_PULSO}▀" ;;
        '.g') saida+="${NC}${HA_FG_GLOW}▄" ;;
        'g.') saida+="${NC}${HA_FG_GLOW}▀" ;;
        'gg') saida+="${HA_FG_GLOW}${HA_BG_GLOW}▀" ;;
        'go') saida+="${HA_FG_GLOW}${HA_BG_BRANCO}▀" ;;
        'og') saida+="${HA_FG_BRANCO}${HA_BG_GLOW}▀" ;;
        *)    saida+="${NC} " ;;
      esac
    done
    printf '%s%s\n' "$saida" "$NC"
  done
}

# ha_logo_quadro <n> — compõe o quadro n. n < 0: quadro final parado.
ha_logo_quadro() {
  local n="$1"
  ha_logo_init
  [ -n "${HA_QM_VAZIA:-}" ] || printf -v HA_QM_VAZIA '%*s' "$HA_W" ''; HA_QM_VAZIA="${HA_QM_VAZIA// /.}"
  local -a QM

  if [ "$n" -lt 0 ]; then
    ha_qm_reset_mask; ha_render_qm; return 0
  fi

  if [ "$n" -lt "$HA_Q_MONTA" ]; then
    # ── ato 1: constelação ──────────────────────────────────────────────────
    ha_qm_reset_vazio
    local total=${#HA_AX[@]} i d t x y
    for (( i = 0; i < total; i++ )); do
      d=${HA_ADL[i]}
      if [ "$n" -ge $(( d + HA_A_DUR )) ]; then
        ha_qm_poe "${HA_AX[i]}" "${HA_AY[i]}" "${HA_MASK[${HA_AY[i]}]:${HA_AX[i]}:1}"
      elif [ "$n" -ge "$d" ]; then
        t=$(( (n - d) * 100 / HA_A_DUR ))
        x=$(( HA_AOX[i] + (HA_AX[i] - HA_AOX[i]) * t / 100 ))
        y=$(( HA_AOY[i] + (HA_AY[i] - HA_AOY[i]) * t / 100 ))
        ha_qm_poe "$x" "$y" a
      fi
    done
    ha_render_qm; return 0
  fi

  if [ "$n" -lt $(( HA_Q_MONTA + HA_Q_TRACO )) ]; then
    # ── ato 2: o traço desenha e retrai, por posição de ARCO ────────────────
    ha_qm_reset_mask
    local k=$(( n - HA_Q_MONTA )) meio=$(( HA_Q_TRACO / 2 )) cabeca cauda i tt
    if [ "$k" -lt "$meio" ]; then
      cabeca=$(( k * HA_CAMINHO / meio )); cauda=0
    else
      cabeca=$HA_CAMINHO; cauda=$(( (k - meio) * HA_CAMINHO / meio ))
    fi
    local total=${#HA_TX[@]}
    for (( i = 0; i < total; i++ )); do
      tt=${HA_TT[i]}
      [ "$tt" -lt "$cauda" ] && continue
      [ "$tt" -ge "$cabeca" ] && break
      ha_qm_poe "${HA_TX[i]}" "${HA_TY[i]}" t
    done
    ha_render_qm; return 0
  fi

  if [ "$n" -lt $(( HA_Q_MONTA + HA_Q_TRACO + HA_Q_SONAR )) ]; then
    # ── ato 3: sonar — anéis ciano saindo de cada disco ─────────────────────
    ha_qm_reset_mask
    local k=$(( n - HA_Q_MONTA - HA_Q_TRACO ))
    local disco=$(( k / 5 )) passo=$(( k % 5 ))
    local cx=${HA_SCX[disco]} cy=${HA_SCY[disco]}
    local r=$(( (passo + 1) * 3 )) r2min r2max x y dx dy d2
    r2min=$(( (r - 2) * (r - 2) )); r2max=$(( r * r ))
    for (( y = 0; y < HA_H; y++ )); do
      for (( x = 0; x < HA_W; x++ )); do
        [ "${HA_MASK[$y]:$x:1}" = '#' ] || continue
        dx=$(( x - cx )); dy=$(( y - cy ))
        d2=$(( dx * dx + dy * dy ))
        if [ "$d2" -ge "$r2min" ] && [ "$d2" -le "$r2max" ]; then
          ha_qm_poe "$x" "$y" p
        fi
      done
    done
    ha_render_qm; return 0
  fi

  # ── ato 4: respiração — o azul pulsa e assenta ────────────────────────────
  local k=$(( n - HA_Q_MONTA - HA_Q_TRACO - HA_Q_SONAR )) y
  ha_qm_reset_mask
  if [ "$k" = "1" ] || [ "$k" = "2" ]; then
    for (( y = 0; y < HA_H; y++ )); do QM[y]="${QM[y]//#/g}"; done
  fi
  ha_render_qm
}

# ha_banner [título] [subtítulo]
ha_banner() {
  local title="${1:-Home Assistant OS}" sub="${2:-}" n cols
  cols="$(tput cols 2>/dev/null || echo 0)"
  case "$cols" in ''|*[!0-9]*) cols=0 ;; esac

  # Sem UTF-8 os glifos sairiam partidos; sem cor o logo vira mancha.
  if [[ "$HAOS_UI_UTF8" == 0 ]] || [[ "$HAOS_UI_DEPTH" == 0 ]]; then
    printf '  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi

  # Terminal estreito ou sem animação: UM quadro, tudo assentado. Nunca meia
  # animação, e nada que o movimento mostre existe só nele.
  if [[ "$HAOS_UI_ANIM" == 0 ]] || [ "$cols" -lt "$HA_MIN_COLS" ]; then
    ha_logo_quadro -1
    printf '\n  %s\n' "$title"
    [ -n "$sub" ] && printf '  %s\n' "$sub"
    printf '\n'
    return 0
  fi

  _hide
  for (( n = 0; n < HA_QUADROS; n++ )); do
    (( n > 0 )) && { tput cuu "$HA_LINHAS" 2>/dev/null || break; }
    ha_logo_quadro "$n"
    sleep "$HA_ATRASO"
  done
  tput cuu "$HA_LINHAS" 2>/dev/null && ha_logo_quadro -1   # assenta
  _show
  printf '\n'
  ha_shimmer "  ${title}"
  [ -n "$sub" ] && printf '  %s%s%s\n' "${C_MUTED}" "$sub" "$NC"
  printf '\n'
}

# ── shimmer: a highlight travels once across the text ───────────────────────
ha_shimmer() {
  local s="$1" n=${#1} p i out
  if [[ "$HAOS_UI_ANIM" == 0 || "$HAOS_UI_DEPTH" == 0 ]]; then printf '%s%s%s\n' "$BOLD" "$s" "$NC"; return
  fi
  _hide
  for (( p=-6; p<=n+6; p+=2 )); do
    out=''
    for (( i=0; i<n; i++ )); do
      local d=$(( i>p ? i-p : p-i ))
      if (( d <= 3 )); then out+="${BOLD}$(rgb 255 255 255)${s:i:1}"
      elif (( d <= 6 )); then out+="${C_CYAN}${s:i:1}"
      else out+="${C_BLUE}${s:i:1}"; fi
    done
    printf '\r%s%s' "$out" "$NC"; sleep 0.012
  done
  printf '\r%s%s%s%s\n' "$BOLD" "$(ha_gradient "$s")" "$NC" ""
  _show
}

# ── gradient rule across the terminal ───────────────────────────────────────
ha_rule() {
  local w; w=$(tput cols 2>/dev/null || echo 72); (( w > 78 )) && w=78
  local line=''; printf -v line '%*s' "$w" ''; line=${line// /$HA_G_REGUA}
  printf '%s\n' "$(ha_gradient "$line")"
}

# ── barra de fase, viva na última linha ─────────────────────────────────────
# Conta FASES, não itens (o desenho do AtlasFile): o que existe de discreto e
# conhecido aqui são as fases, e um total de passos inventado é pior que barra
# nenhuma. Só aparece depois da 1ª fase, e só com animação — em log seria lixo.
# Apagar ANTES de qualquer mensagem é o que impede a barra de virar sujeira no
# meio do texto; `\033[2K` apaga a linha inteira sem depender de TERM.
HA_BAR_TOTAL=0; HA_BAR_N=0; HA_BAR_VISIVEL=0; HA_BAR_SUSPENSA=0
ha_bar_limpa() {
  if [[ "$HA_BAR_VISIVEL" == 1 ]]; then printf '\r\033[2K'; HA_BAR_VISIVEL=0; fi
  return 0
}
# Durante uma PERGUNTA a barra não existe: prompt e barra disputando a última
# linha foi medido em campo (o "[s/N]" colado em "fase 1/4"). É a disciplina
# do ask() do AtlasFile: quem pergunta suspende, quem termina retoma.
ha_bar_suspende() { ha_bar_limpa; HA_BAR_SUSPENSA=1; }
ha_bar_retoma()   { HA_BAR_SUSPENSA=0; ha_bar_mostra; }
ha_bar_mostra() {
  [[ "${HA_BAR_SUSPENSA:-0}" == 0 ]] || return 0
  [[ "$HAOS_UI_ANIM" == 1 && "$HA_BAR_TOTAL" -gt 0 && "$HA_BAR_N" -gt 0 ]] || return 0
  local w=20 f i out=''
  f=$(( HA_BAR_N * w / HA_BAR_TOTAL ))
  for (( i = 0; i < w; i++ )); do
    if (( i < f )); then out+="${C_CYAN}${HA_G_BON}"; else out+="${C_MUTED}${HA_G_BOFF}"; fi
  done
  printf '%s%s%s %sfase %d/%d%s' "$HA_GUT" "$out" "$NC" "${C_MUTED}" "$HA_BAR_N" "$HA_BAR_TOTAL" "$NC"
  HA_BAR_VISIVEL=1
  return 0
}

# ── phase header ────────────────────────────────────────────────────────────
HA_PHASE_N=0
ha_phase() {
  ha_bar_limpa
  HA_PHASE_N=$(( HA_PHASE_N + 1 ))
  local w cab pad n
  w=$(tput cols 2>/dev/null || echo 72); case "$w" in ''|*[!0-9]*) w=72 ;; esac
  (( w > 78 )) && w=78
  printf '%s\n' "$HA_GUT"
  cab="$(printf '%02d %s ' "$HA_PHASE_N" "$1")"
  n=$(( w - ${#cab} - 4 )); [ "$n" -lt 4 ] && n=4
  printf -v pad '%*s' "$n" ''; pad=${pad// /$HA_G_REGUA}
  printf '%s%s%s %s%s\n' "${C_BLUE}" "$HA_G_RAMO" "$NC" "$(ha_gradient "$cab")" "$(ha_gradient "$pad")"
  ha_bar_mostra
}

# ── status lines ────────────────────────────────────────────────────────────
ha_ok()    { ha_bar_limpa; printf '%s%s%s%s %s\n'  "$HA_GUT" "${C_GREEN}" "$HA_G_OK" "$NC" "$1"; ha_bar_mostra; }
ha_info()  { ha_bar_limpa; printf '%s%s%s%s %s%s%s\n' "$HA_GUT" "${C_BLUE}" "$HA_G_INFO" "$NC" "${C_MUTED}" "$1" "$NC"; ha_bar_mostra; }
ha_warn()  { ha_bar_limpa; printf '%s%s%s%s %s\n'  "$HA_GUT" "${C_AMBER}" "$HA_G_WARN" "$NC" "$1"; ha_bar_mostra; }
ha_err()   { ha_bar_limpa; printf '%s%s%s%s %s\n'  "$HA_GUT" "${C_RED}"  "$HA_G_ERR" "$NC" "$1" >&2; }
ha_skip()  { ha_bar_limpa; printf '%s%s%s%s %s%s%s\n' "$HA_GUT" "${C_MUTED}" "$HA_G_SKIP" "$NC" "$DIM" "$1" "$NC"; ha_bar_mostra; }
# pergunta: glifo próprio, SEM newline — quem lê a resposta é o chamador.
# A barra fica suspensa por conta do chamador (ha_bar_suspende/retoma).
ha_ask()   { printf '%s%s%s%s %s' "$HA_GUT" "${C_AMBER}" "$HA_G_ASK" "$NC" "$1"; }
# linha de conteúdo pendurada na calha, sem glifo (menus, tabelas do plano)
ha_linha() { ha_bar_limpa; printf '%s%s\n' "$HA_GUT" "$1"; ha_bar_mostra; }

# ── quebra de linha na largura do terminal ──────────────────────────────────
# Existe porque o produto imprime CAMINHOS (`~/VirtualBox VMs/...`), e caminho
# que o terminal quebra sozinho sai sem recuo e não pode ser copiado inteiro.
# Palavra maior que a largura transborda em vez de ser partida — caminho
# quebrado no meio não cola. Largura por bytes menos bytes de continuação
# UTF-8: dá caracteres nos dois locales (a armadilha do ${#s} sob LC_ALL=C).
ha_strwidth() { # <texto>
  local b c
  b=$(printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' ')
  c=$(printf '%s' "$1" | LC_ALL=C tr -dc '\200-\277' | LC_ALL=C wc -c | tr -d ' ')
  printf '%s' $(( b - c ))
}
ha_wrap() { # <prefixo_1a_linha> <prefixo_continuacao> <colunas_do_prefixo> <texto>
  local p1="$1" p2="$2" pw="$3" texto="$4" linha='' palavra util w glob_ligado=1
  w=$(tput cols 2>/dev/null || echo 72); case "$w" in ''|*[!0-9]*) w=72 ;; esac
  (( w > 92 )) && w=92
  util=$(( w - pw )); [ "$util" -lt 20 ] && util=20
  # Texto pode conter glob (`*.vdi`); sem `set -f` a divisão em palavras
  # expandiria contra o diretório corrente.
  case "$-" in *f*) glob_ligado=0 ;; esac
  set -f
  for palavra in $texto; do
    if [ -z "$linha" ]; then linha="$palavra"
    elif [ "$(ha_strwidth "${linha} ${palavra}")" -le "$util" ]; then linha="${linha} ${palavra}"
    else printf '%s%s\n' "$p1" "$linha"; p1="$p2"; linha="$palavra"; fi
  done
  [ "$glob_ligado" = "1" ] && set +f
  printf '%s%s\n' "$p1" "$linha"
}

# ── orbit spinner around a label ────────────────────────────────────────────
ha_spin() { # ha_spin "label" <pid>
  local label="$1" pid="$2" i=0 rc=0
  # `wait` com código != 0 sob `set -e` abortaria o chamador antes do return —
  # por isso todo wait aqui é `|| rc=$?`, nunca solto.
  if [[ "$HAOS_UI_ANIM" == 0 ]]; then
    printf '%s%s %s\n' "$HA_GUT" "$HA_G_DOTS" "$label"
    wait "$pid" || rc=$?
    return "$rc"
  fi
  ha_bar_limpa
  _hide
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s%s %s' "$HA_GUT" "${C_CYAN}" "${HA_SPIN_F:$(( i % HA_SPIN_N )):1}" "$NC" "$label"; i=$(( i + 1 ))
    sleep 0.07
  done
  wait "$pid" || rc=$?
  printf '\r\033[2K'; _show
  if (( rc == 0 )); then ha_ok "$label"; else ha_err "$label  (exit $rc)"; fi
  return "$rc"
}

# ── progress bar, HA rounded style ──────────────────────────────────────────
ha_bar() { # ha_bar <done> <total> "label"
  local d="$1" t="$2" label="${3:-}" w=32 f i out=''
  # Em log (nao-TTY) uma barra por frame vira lixo: so a linha final importa.
  if [[ "$HAOS_UI_ANIM" == 0 ]]; then (( d >= t )) && printf ' %d/%d %s\n' "$d" "$t" "$label"; return; fi
  ha_bar_limpa
  (( t == 0 )) && t=1
  f=$(( d * w / t ))
  if [[ "$HAOS_UI_DEPTH" == 0 || "$HAOS_UI_UTF8" == 0 ]]; then
    printf '\r [%-*s] %d/%d %s' "$w" "$(printf '%*s' "$f" '' | tr ' ' '#')" "$d" "$t" "$label"
  else
    for (( i=0; i<w; i++ )); do
      if (( i < f )); then
        local u=$(( w>1 ? i*200/(w-1) : 0 )) r g b
        if (( u <= 100 )); then r=$(( HA_DEEP_R+(HA_BLUE_R-HA_DEEP_R)*u/100 )); g=$(( HA_DEEP_G+(HA_BLUE_G-HA_DEEP_G)*u/100 )); b=$(( HA_DEEP_B+(HA_BLUE_B-HA_DEEP_B)*u/100 ))
        else local v=$(( u-100 )); r=$(( HA_BLUE_R+(HA_CYAN_R-HA_BLUE_R)*v/100 )); g=$(( HA_BLUE_G+(HA_CYAN_G-HA_BLUE_G)*v/100 )); b=$(( HA_BLUE_B+(HA_CYAN_B-HA_BLUE_B)*v/100 )); fi
        out+="$(rgb "$r" "$g" "$b")━"
      else out+="${C_MUTED}╌"; fi
    done
    printf '\r %s%s %s%d/%d%s %s' "$out" "$NC" "${C_MUTED}" "$d" "$t" "$NC" "$label"
  fi
  (( d >= t )) && printf '\n'
}

# A demonstração vive em tools/ui-demo.sh. Biblioteca é biblioteca:
# ela não desenha sozinha, não instala trap e não afirma fatos.
# <<< UI EMBUTIDO <<<

# =============================================================================
# CATÁLOGO — cópia embutida. NÃO editar aqui: a fonte é catalog/catalog.bash,
# ./tools/embed.sh copia, e ./verify.sh reprova a divergência.
# =============================================================================
# >>> CATALOGO EMBUTIDO >>>
# =============================================================================
# catalog.bash — FONTE DE VERDADE do catálogo do instalador HAOS.
#
# O haos-install.sh é autocontido: distribuído por `curl | bash`, ele embute
# uma cópia destas tabelas. Este arquivo existe para que a cópia possa ser
# CONFERIDA — o CI compara o que está no script com o que está aqui, e deriva
# vira erro detectável em vez de bug silencioso.
#
# Sintaxe: fragmento bash, compatível com bash 3.2 (o que o macOS traz).
# Sem parser, sem formato inventado: `source` este arquivo e as tabelas estão
# na mão. Sem arrays associativos, sem namerefs.
#
# -----------------------------------------------------------------------------
# Verificado em 2026-08-23 contra:
#   Home Assistant Core 2026.8.3 (source na tag) · HAOS 18.2 · VirtualBox 7.2.16
#   doc oficial de default_config · analytics.home-assistant.io
#   manifest.json e config_flow.py de cada domínio, lidos na tag 2026.8.3
#   store do Supervisor de uma instância real (80 apps, 5 repositórios)
# =============================================================================

# -----------------------------------------------------------------------------
# CATEGORY_DB — id|rótulo|descrição
# -----------------------------------------------------------------------------
CATEGORY_DB=(
    "vanilla|Vanilla|piso do produto — o que o HAOS instala sozinho; remover é opção, não escolha"
    "conectado|Conectado|infraestrutura e protocolos de conectividade com adoção relevante"
    "casa|Casa|integrações de hardware ou serviço presente na casa"
    "ferramentas|Ferramentas|apps de manutenção e observabilidade do HAOS"
    "casa_abhome|Casa ABHOME|packages de custo com regras brasileiras — específicos desta casa"
    "extensoes|Extensões de terceiros|HACS — só a instalação, nada de dentro dele"
)

# =============================================================================
# O PISO — três partes, com procedência. O instalador precisa conhecê-lo para
# NÃO DUPLICAR o que a própria instalação já cria.
# =============================================================================

# 24 itens. Fonte: doc oficial de default_config.
DEFAULT_CONFIG_DB=(
    assist_pipeline backup bluetooth cloud config conversation dhcp
    energy file go2rtc history homeassistant_alerts image_upload
    logbook media_source mobile_app my ssdp stream sun
    usage_prediction usb webhook zeroconf
)

# Intrínsecos do HAOS. Medidos com source=system numa instância real.
# `analytics`: o COMPONENTE é piso; o ENVIO de telemetria é consentimento,
# perguntado no onboarding. Nunca assumir habilitado.
HAOS_INTRINSIC_DB=(
    "hassio|integração com o Supervisor"
    "analytics|componente presente; envio = consentimento do usuário"
)

# Criados pelo onboarding. Fonte: components/onboarding/views.py @ 2026.8.3 —
# POST /api/onboarding/core_config inicia os flows destes quatro.
ONBOARDING_DB=(
    "google_translate|texto para voz"
    "met|previsão do tempo"
    "radio_browser|catálogo de rádios"
    "shopping_list|lista de compras"
)

# =============================================================================
# ITEM_DB — 20 itens
#
# id|cat|rotulo|origem|slug|padrao|discovery|setup|preferred|requires|flags|desc
#
#  origem    core     = homeassistant/components/
#            oficial  = repositório home-assistant/addons
#            community= repositório de terceiro (exige adicionar o repositório)
#            proprio  = deste projeto
#            custom   = fora dos anteriores
#
#  slug      identificador do app no Supervisor. É `<repositório>_<app>`, NUNCA
#            o nome curto. `-` quando não é app.
#            ⚠️ O prefixo de repositório de terceiro é HASH DA URL (ex.: a0d7b954)
#            — descobrir depois de adicionar o repositório, jamais fixar.
#
#  padrao    1 pré-marcado · 0 só por escolha explícita · cond avaliado em runtime
#
#  discovery os matchers declarados no manifest. `-` = o manifest não declara
#            nenhum. NÃO é o mesmo que setup.
#
#  setup     como uma entry pode NASCER. É CERCA DE CONJUNTO: cria, lê de volta,
#            e confere se o source lido PERTENCE a esta lista. NUNCA igualdade —
#            um domínio guarda legitimamente entries com sources diferentes.
#
#  requires  dependências. Sufixo `:ha` = o próprio config flow do HA instala e
#            gerencia; o instalador NÃO deve instalar por fora, duplicaria.
#
#  flags     single_entry  o manifest declara single_config_entry: true — não
#                          tentar criar a segunda
#            schema_flow   usa SchemaConfigFlowHandler: os passos são DADOS
#                          (`CONFIG_FLOW = {"user": ...}`), não métodos
#                          `async def`. Procurar só por método dá falso negativo
#            repo_terceiro exige adicionar repositório antes de instalar
# =============================================================================
ITEM_DB=(
    # ── conectado ────────────────────────────────────────────────────────────
    "cast|conectado|Google Cast|core|-|0|zeroconf|zeroconf user|zeroconf|-|single_entry|Chromecast e telas — 50,9% de adoção"
    "mqtt|conectado|MQTT|core|-|0|-|user hassio|user|mosquitto:ha|single_entry|broker para Zigbee2MQTT, ESPHome e sensores DIY — 48,6%"
    "matter|conectado|Matter|core|-|0|zeroconf|zeroconf user|zeroconf|matter_server:ha|-|padrão aberto — 39,8%; comissionamento costuma exigir rádio"
    "thread|conectado|Thread|core|-|0|zeroconf|zeroconf user|zeroconf|openthread_border_router|single_entry|37,1%; exige border router, que NÃO é gerenciado pelo flow"
    "esphome|conectado|ESPHome|core|-|0|zeroconf dhcp mqtt|zeroconf user|zeroconf|-|-|firmware para ESP32/ESP8266 — 27,0%"

    # ── casa ─────────────────────────────────────────────────────────────────
    "hue|casa|Philips Hue|core|-|1|zeroconf homekit|user zeroconf homekit|user|-|-|iluminação — o passo 'link' pede o botão da bridge"
    "tuya|casa|Tuya|core|-|1|dhcp|user dhcp|user|-|-|SmartLife — credencial de nuvem; o flow tem passo de QR"
    "broadlink|casa|Broadlink|core|-|1|dhcp|user dhcp|dhcp|-|-|infravermelho — passos auth e unlock; exige modo de pareamento"
    "shelly|casa|Shelly|core|-|1|zeroconf bluetooth|user zeroconf bluetooth|zeroconf|-|-|medição de energia — base dos packages de custo"
    "tplink|casa|TP-Link Smart Home|core|-|1|dhcp|user dhcp integration_discovery|dhcp|-|-|câmeras Tapo — exige Camera Account criada no app do celular"
    "smartthings|casa|SmartThings|core|-|1|dhcp|user dhcp|user|application_credentials|-|aparelhos Samsung — OAuth, não token pessoal"

    # ── ferramentas ──────────────────────────────────────────────────────────
    "advanced_ssh|ferramentas|SSH & Web Terminal|community|DESCOBRIR_ssh|1|-|-|-|-|repo_terceiro|terminal com Docker API; 33,7% — repositório hassio-addons"
    "file_editor|ferramentas|File editor|oficial|core_configurator|1|-|-|-|-|-|editor ciente das entidades da instância — 63,6%"
    "samba|ferramentas|Samba share|oficial|core_samba|1|-|-|-|-|-|/config montável no Finder por smb:// — 26,8%"
    "systemmonitor|ferramentas|System Monitor|core|-|0|-|user|user|-|single_entry schema_flow|CPU, memória e disco do host; schema VAZIO — cria com {}"

    # ── casa_abhome ──────────────────────────────────────────────────────────
    "workday|casa_abhome|Workday|core|-|1|-|user|user|-|schema_flow|feriados nacionais e estaduais — o energia_br NÃO funciona sem isto"
    "energia_br|casa_abhome|Custo de energia (BR)|proprio|-|1|-|-|-|shelly workday samba|-|reproduz a fatura na vírgula; simula Convencional x Branca"
    "gas_br|casa_abhome|Custo de gás canalizado (BR)|proprio|-|1|-|-|-|samba|-|cascata por faixa, volume corrigido por P,T,Z e PCS"
    "agua_br|casa_abhome|Custo de água e esgoto (BR)|proprio|-|1|-|-|-|samba|-|simula a concessionária e compara com o rateio do condomínio"

    # ── extensoes ────────────────────────────────────────────────────────────
    "hacs|extensoes|HACS|custom|-|0|-|user|user|samba|repo_terceiro|só a instalação; nunca por perfil, nunca em --all"
)

# -----------------------------------------------------------------------------
# ITEM_META_DB — id|quality_scale|analytics_pct
# Informativo. Fica FORA do ITEM_DB de propósito: nada no caminho quente consome
# isto hoje, e inchar a tabela operacional é como se erra a ordem de um campo.
# quality_scale do manifest; adoção da telemetria oficial.
# -----------------------------------------------------------------------------
ITEM_META_DB=(
    "mqtt|platinum|48.6"
    "esphome|platinum|27.0"
    "shelly|platinum|25.0"
    "smartthings|bronze|-"
    "cast|-|50.9"
    "matter|-|39.8"
    "thread|-|37.1"
    "tuya|-|29.5"
    "file_editor|-|63.6"
    "samba|-|26.8"
    "advanced_ssh|-|33.7"
)

# -----------------------------------------------------------------------------
# VM_PROFILE_DB — id|rótulo|RAM MiB|vCPU|origem do número
#
# "derivado" é calculado pela sonda no momento da execução, e NUNCA pode ficar
# abaixo do vm_equilibrado — senão o perfil chamado "Recomendado" fica menor que
# o "Equilibrado" e o rótulo mente.
# Se a sonda falhar, o perfil NÃO é ofertado — nunca cai num valor inventado.
#
# Disco não é dimensão: o .vdi do HAOS traz 32 GiB de capacidade virtual.
# -----------------------------------------------------------------------------
VM_PROFILE_DB=(
    "vm_minimo|Mínimo|2048|2|documentação oficial do HA"
    "vm_equilibrado|Equilibrado|4096|2|medido — cobre os 2,5 GB de uma instância real"
    "vm_recomendado|Recomendado|derivado|derivado|calculado da sonda, com piso no equilibrado"
)

# -----------------------------------------------------------------------------
# HAOS_PROFILE_DB — id|rótulo|categorias.  A ESCADA SOMA. Só isto é escada.
# As demais categorias são ORTOGONAIS: marcam-se à parte, em qualquer degrau.
# -----------------------------------------------------------------------------
HAOS_PROFILE_DB=(
    "haos_vanilla|Vanilla|vanilla"
    "haos_conectado|Conectado|vanilla conectado"
    "haos_casa|Casa|vanilla conectado casa"
)

ORTOGONAL_DB=(ferramentas casa_abhome extensoes)

# -----------------------------------------------------------------------------
# NAO_APLICA_DB — id|motivo
#
# REGRA: preferir o oficial QUANDO O OFICIAL COBRE A NECESSIDADE.
# Não é "sem repositório de terceiro" — essa formulação não se sustentava, e era
# ela que criava a contradição com o advanced_ssh.
#
# Serve para o gerador de proposta não sugerir para sempre o que já foi
# decidido, e para registrar o MOTIVO — senão uma sessão futura "conserta" a
# ausência. Fica fora do ITEM_DB para não poluir o seletor.
# -----------------------------------------------------------------------------
NAO_APLICA_DB=(
    "raspberry_pi|não existe hardware Raspberry Pi numa VM em Mac"
    "rpi_power|mede a fonte do Raspberry Pi"
    "smartir|é pacote de dentro do HACS — a regra é não instalar nada de lá"
    "studio_code_server|file_editor e samba, ambos oficiais, cobrem edição"
    "core_ssh|oficial, mas NÃO cobre: o config.yaml não declara docker_api, e Protection mode só libera o que o app declara"
)
# <<< CATALOGO EMBUTIDO <<<

# ── cópias embutidas: helper Python e packages (fonte: lib/ e packages/) ─────
# Preenchidas por tools/embed.sh; o portão e o CI reprovam deriva (--check).
# >>> HELPER EMBUTIDO >>>
HAOS_HELPER_PY=$(cat <<'FIM_EMB_HELPER'
# =============================================================================
# ha-api.py — o braço do instalador DENTRO do Home Assistant.
#
# bash não fala WebSocket e não deve falar JSON na unha — este helper fala os
# dois, só com a stdlib (a máquina do usuário não tem pip garantido).
# Embutido no haos-install.sh via tools/embed.sh (bloco HELPER); a fonte de
# verdade é este arquivo.
#
# CONTRATO DE SEGREDO (banca 24/08):
#   - credenciais entram por STDIN: linha 1 = usuário, linha 2 = senha,
#     linhas seguintes = payload JSON quando o comando pedir. NUNCA argv/env.
#   - erro imprime SÓ "ERRO <status> <rota>" no stderr — nunca corpo de
#     request/response (o stderr pode ir para o LOG_FILE preservado).
#   - tokens vivem só na memória deste processo.
#
# Superfícies (docs/API-REFERENCE_20260823_verificado.md):
#   /auth/token é Authentication API pública; onboarding, config_entries e o
#   comando WS supervisor/api são SOURCE-PINNED no Core 2026.8.3 — daí toda
#   escrita conferir a PÓS-CONDIÇÃO, nunca só o status HTTP.
#
# Saída (contrato com o instalador): exit 0 = fez agora · 100 = já estava ·
# 1 = erro. Comandos que devolvem dados imprimem UMA linha por dado no stdout.
# =============================================================================
import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("HAOS_BASE", "").rstrip("/")
LANG = os.environ.get("HAOS_HELPER_LANG", "pt")
JA = 100


def erro(rota, status):
    print(f"ERRO {status} {rota}", file=sys.stderr)
    sys.exit(1)


class _SemRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):  # noqa: D102
        return None


_opener = urllib.request.build_opener(_SemRedirect)


def http(caminho, metodo="GET", dados=None, token=None, form=False, timeout=30):
    """(status, corpo). Segue 3xx PRESERVANDO método e corpo — medido em
    24/08: antes do onboarding a API mora na porta 80 e a 8123 devolve 307."""
    url = BASE + caminho
    corpo = None
    cab = {}
    if dados is not None:
        if form:
            corpo = urllib.parse.urlencode(dados).encode()
            cab["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            corpo = json.dumps(dados).encode()
            cab["Content-Type"] = "application/json"
    if token:
        cab["Authorization"] = f"Bearer {token}"
    for _ in range(4):
        req = urllib.request.Request(url, data=corpo, headers=cab, method=metodo)
        try:
            with _opener.open(req, timeout=timeout) as r:
                texto = r.read().decode("utf-8", "replace")
                try:
                    return r.status, json.loads(texto)
                except json.JSONDecodeError:
                    return r.status, texto
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 307, 308) and e.headers.get("Location"):
                url = urllib.parse.urljoin(url, e.headers["Location"])
                continue
            texto = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(texto)
            except json.JSONDecodeError:
                return e.code, texto
        except (urllib.error.URLError, OSError):
            return 0, ""
    return 0, ""


def _cid():
    return BASE.rstrip("/") + "/"


def _troca_code(code, rota):
    st, r = http("/auth/token", "POST", {
        "grant_type": "authorization_code", "code": code, "client_id": _cid(),
    }, form=True)
    if st != 200 or not isinstance(r, dict) or "access_token" not in r:
        erro(rota, st)
    return r["access_token"], r.get("refresh_token", "")


def onboarding_estado():
    """(status, lista-de-passos). 404 = onboarding já terminou."""
    return http("/api/onboarding")


def login(usuario, senha):
    """login_flow → token. Para instância JÁ onboardada."""
    st, r = http("/auth/login_flow", "POST", {
        "client_id": _cid(), "handler": ["homeassistant", None],
        "redirect_uri": _cid(),
    })
    if st != 200 or not isinstance(r, dict) or "flow_id" not in r:
        erro("/auth/login_flow", st)
    st, r = http(f"/auth/login_flow/{r['flow_id']}", "POST", {
        "username": usuario, "password": senha, "client_id": _cid(),
    })
    if st != 200 or not isinstance(r, dict) or r.get("type") != "create_entry":
        erro("/auth/login_flow (credencial)", st)
    return _troca_code(r["result"], "/auth/token")


def autenticar(usuario, senha):
    """Fresca ou onboardada, devolve (access, refresh)."""
    st, passos = onboarding_estado()
    if st == 200 and isinstance(passos, list) \
            and not all(p.get("done") for p in passos):
        pend = {p["step"] for p in passos if not p.get("done")}
        if "user" in pend:
            st, r = http("/api/onboarding/users", "POST", {
                "name": usuario, "username": usuario, "password": senha,
                "client_id": _cid(), "language": LANG,
            })
            if st != 200 or not isinstance(r, dict) or "auth_code" not in r:
                erro("/api/onboarding/users", st)
            return _troca_code(r["auth_code"], "/auth/token")
    return login(usuario, senha)


def _le_credencial():
    usuario = sys.stdin.readline().strip()
    senha = sys.stdin.readline().rstrip("\n")
    if not usuario or not senha:
        erro("credencial ausente no stdin", 0)
    return usuario, senha


# ── onboarding (F6) ──────────────────────────────────────────────────────────
def cmd_conta():
    usuario, senha = _le_credencial()
    st, passos = onboarding_estado()
    if st == 404 or (st == 200 and isinstance(passos, list)
                     and all(p.get("done") for p in passos)):
        login(usuario, senha)  # valida a credencial agora, não na F7
        sys.exit(JA)
    if st != 200 or not isinstance(passos, list):
        erro("/api/onboarding", st)
    token, _ = autenticar(usuario, senha)
    pend = {p["step"] for p in passos if not p.get("done")}
    if "core_config" in pend:
        st, _r = http("/api/onboarding/core_config", "POST", {}, token=token)
        if st != 200:
            erro("/api/onboarding/core_config", st)
    if "analytics" in pend:
        # consentimento NUNCA assumido: o passo é concluído sem ligar envio
        st, _r = http("/api/onboarding/analytics", "POST", {}, token=token)
        if st != 200:
            erro("/api/onboarding/analytics", st)
    if "integration" in pend:
        st, _r = http("/api/onboarding/integration", "POST", {
            "client_id": _cid(), "redirect_uri": _cid(),
        }, token=token)
        if st != 200:
            erro("/api/onboarding/integration", st)
    # pós-condição: acabou de verdade?
    st, passos = onboarding_estado()
    if st == 200 and isinstance(passos, list) \
            and not all(p.get("done") for p in passos):
        erro("/api/onboarding (pós-condição)", st)
    sys.exit(0)


# ── WebSocket RFC 6455, só stdlib (F7) ──────────────────────────────────────
class WS:
    """Cliente mínimo: máscara obrigatória no cliente, comprimentos 126/127,
    PING→PONG, fragmentação, timeout de socket dos dois lados."""

    def __init__(self, timeout=60):
        u = urllib.parse.urlparse(BASE)
        self.sock = socket.create_connection(
            (u.hostname, u.port or 80), timeout=timeout)
        chave = base64.b64encode(secrets.token_bytes(16)).decode()
        pedido = (
            f"GET /api/websocket HTTP/1.1\r\n"
            f"Host: {u.hostname}:{u.port or 80}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {chave}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(pedido.encode())
        resposta = b""
        while b"\r\n\r\n" not in resposta:
            peda = self.sock.recv(4096)
            if not peda:
                erro("/api/websocket (handshake)", 0)
            resposta += peda
        cabeca, _, resto = resposta.partition(b"\r\n\r\n")
        if b" 101 " not in cabeca.split(b"\r\n", 1)[0]:
            erro("/api/websocket (upgrade)", 0)
        esperado = base64.b64encode(hashlib.sha1(
            (chave + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
        ).digest())
        if esperado not in cabeca:
            erro("/api/websocket (accept)", 0)
        self.buf = resto
        self.n = 0

    def _le(self, quanto):
        while len(self.buf) < quanto:
            peda = self.sock.recv(65536)
            if not peda:
                erro("/api/websocket (conexão caiu)", 0)
            self.buf += peda
        dado, self.buf = self.buf[:quanto], self.buf[quanto:]
        return dado

    def envia_texto(self, texto):
        dado = texto.encode()
        mascara = secrets.token_bytes(4)
        corpo = bytes(b ^ mascara[i % 4] for i, b in enumerate(dado))
        tam = len(dado)
        if tam < 126:
            cab = struct.pack("!BB", 0x81, 0x80 | tam)
        elif tam < 65536:
            cab = struct.pack("!BBH", 0x81, 0x80 | 126, tam)
        else:
            cab = struct.pack("!BBQ", 0x81, 0x80 | 127, tam)
        self.sock.sendall(cab + mascara + corpo)

    def _quadro(self):
        b1, b2 = struct.unpack("!BB", self._le(2))
        fim, opcode = b1 & 0x80, b1 & 0x0F
        tam = b2 & 0x7F
        if tam == 126:
            (tam,) = struct.unpack("!H", self._le(2))
        elif tam == 127:
            (tam,) = struct.unpack("!Q", self._le(8))
        if b2 & 0x80:  # servidor não mascara; tolerar se mascarar
            mascara = self._le(4)
            dado = bytes(b ^ mascara[i % 4] for i, b in enumerate(self._le(tam)))
        else:
            dado = self._le(tam)
        return fim, opcode, dado

    def recebe(self):
        partes = b""
        while True:
            fim, opcode, dado = self._quadro()
            if opcode == 0x9:   # PING → PONG com o mesmo payload
                mascara = secrets.token_bytes(4)
                corpo = bytes(b ^ mascara[i % 4] for i, b in enumerate(dado))
                self.sock.sendall(
                    struct.pack("!BB", 0x8A, 0x80 | len(dado)) + mascara + corpo)
                continue
            if opcode == 0x8:
                erro("/api/websocket (close do servidor)", 0)
            if opcode in (0x1, 0x2, 0x0):
                partes += dado
                if fim:
                    return json.loads(partes.decode("utf-8", "replace"))

    def auth(self, token):
        m = self.recebe()
        if m.get("type") != "auth_required":
            erro("/api/websocket (auth_required)", 0)
        self.envia_texto(json.dumps({"type": "auth", "access_token": token}))
        m = self.recebe()
        if m.get("type") != "auth_ok":
            erro("/api/websocket (auth)", 0)

    def chama(self, corpo):
        self.n += 1
        corpo = dict(corpo, id=self.n)
        self.envia_texto(json.dumps(corpo))
        while True:
            m = self.recebe()
            if m.get("id") == self.n and m.get("type") == "result":
                return m


def sup(ws, endpoint, metodo="get", dados=None, timeout=None):
    """supervisor/api — a ÚNICA rota que funciona com token de usuário para
    falar com o Supervisor (o proxy REST /api/hassio/* devolve 401, medido)."""
    corpo = {"type": "supervisor/api", "endpoint": endpoint, "method": metodo}
    if dados is not None:
        corpo["data"] = dados
    if timeout is not None:
        corpo["timeout"] = timeout
    m = ws.chama(corpo)
    if not m.get("success"):
        erro(f"supervisor/api {endpoint}", 0)
    return m.get("result")


def _ws_autenticado():
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    ws = WS(timeout=300)
    ws.auth(token)
    return ws, token


# ── apps (F7) ────────────────────────────────────────────────────────────────
def cmd_repo_ensure(url, sufixo):
    """Garante o repositório e imprime o slug real `<hash>_<sufixo>` —
    o prefixo é hash da URL: descobrir SEMPRE, nunca fixar."""
    ws, _tok = _ws_autenticado()
    loja = sup(ws, "/store")
    repos = {r.get("source"): r.get("slug") for r in loja.get("repositories", [])}
    if url not in repos:
        sup(ws, "/store/repositories", "post", {"repository": url}, timeout=120)
        loja = sup(ws, "/store")
        repos = {r.get("source"): r.get("slug")
                 for r in loja.get("repositories", [])}
    prefixo = repos.get(url)
    if not prefixo:
        erro("/store/repositories (pós-condição)", 0)
    for a in loja.get("addons", []):
        if a.get("slug") == f"{prefixo}_{sufixo}":
            print(a["slug"])
            return
    erro(f"/store (sem app _{sufixo} no repositório)", 0)


def _opt_mescla(atu, nov):
    m = dict(atu)
    for k, v in nov.items():
        if isinstance(v, dict):
            m[k] = _opt_mescla(atu.get(k) or {}, v)
        else:
            m[k] = v
    return m


def _opt_difere(atu, nov):
    for k, v in nov.items():
        if isinstance(v, dict):
            if _opt_difere(atu.get(k) or {}, v):
                return True
        elif isinstance(v, list):
            tem = atu.get(k) or []
            if not all(x in tem for x in v):
                return True
        elif atu.get(k) != v:
            return True
    return False


def cmd_addon_ensure(slug, com_options):
    """Instala (se preciso), aplica options (stdin, se pedido) e inicia.
    Pós-condição: info.state == started. exit 100 quando nada mudou.
    Ordem do stdin importa: credencial primeiro, payload depois."""
    ws, _tok = _ws_autenticado()
    opcoes = None
    if com_options:
        bruto = sys.stdin.read()
        opcoes = json.loads(bruto) if bruto.strip() else None
    st_info = sup(ws, f"/addons/{slug}/info") if _addon_existe(ws, slug) else None
    mudou = False
    if st_info is None or not st_info.get("version"):
        sup(ws, f"/store/addons/{slug}/install", "post", timeout=1800)
        st_info = sup(ws, f"/addons/{slug}/info")
        if not st_info.get("version"):
            erro(f"/store/addons/{slug}/install (pós-condição)", 0)
        mudou = True
    if opcoes:
        atuais = st_info.get("options") or {}
        # options podem ser ANINHADAS (advanced_ssh guarda em ssh.*, medido
        # em campo: o merge raso deixava a chave fora e o diff nunca zerava).
        # Lista: em dia quando tudo que pedimos está lá (o app normaliza).
        if _opt_difere(atuais, opcoes):
            sup(ws, f"/addons/{slug}/options", "post",
                {"options": _opt_mescla(atuais, opcoes)})
            mudou = True
            aplicou_opts = True
        else:
            aplicou_opts = False
    else:
        aplicou_opts = False
    if st_info.get("state") != "started":
        sup(ws, f"/addons/{slug}/start", "post", timeout=300)
        mudou = True
    elif aplicou_opts:
        # option nova num app RODANDO só vale depois de reiniciá-lo
        sup(ws, f"/addons/{slug}/restart", "post", timeout=300)
    st_info = sup(ws, f"/addons/{slug}/info")
    if st_info.get("state") != "started":
        erro(f"/addons/{slug}/start (pós-condição)", 0)
    sys.exit(0 if mudou else JA)


def _addon_existe(ws, slug):
    lista = sup(ws, "/addons")
    return any(a.get("slug") == slug for a in lista.get("addons", []))


def cmd_addon_option(slug, chave):
    """Imprime UMA option do app (ex.: a senha do samba na reexecução —
    desired-state: quem detém a verdade é o Supervisor)."""
    ws, _tok = _ws_autenticado()
    if not _addon_existe(ws, slug):
        erro(f"/addons/{slug} (ausente)", 0)
    info = sup(ws, f"/addons/{slug}/info")
    valor = (info.get("options") or {}).get(chave)
    if valor is None:
        erro(f"/addons/{slug}/info (sem option {chave})", 0)
    print(valor)


# ── integrações (F8) ─────────────────────────────────────────────────────────
def _entries(token, dominio):
    st, r = http("/api/config/config_entries/entry", token=token)
    if st != 200 or not isinstance(r, list):
        erro("/api/config/config_entries/entry", st)
    return [e for e in r if e.get("domain") == dominio]


PRECISA_USUARIO = 3


def cmd_entry_ensure(dominio, fontes):
    """Cria a entry SÓ quando o flow fecha sem dado do usuário (regra da
    curadoria: credencial NUNCA). Flow que pede dado ou escolha → exit 3,
    depois de DESFAZER o flow aberto (não deixar lixo no painel).
    CERCA DE CONJUNTO: lê a entry de volta e confere source ∈ fontes;
    fora do conjunto → REMOVE a entry e falha."""
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    if _entries(token, dominio):
        sys.exit(JA)
    st, r = http("/api/config/config_entries/flow", "POST",
                 {"handler": dominio}, token=token)
    if st != 200 or not isinstance(r, dict):
        erro("/api/config/config_entries/flow", st)

    def _desiste():
        fid = r.get("flow_id")
        if fid:
            http(f"/api/config/config_entries/flow/{fid}", "DELETE",
                 token=token)
        sys.exit(PRECISA_USUARIO)

    for _ in range(4):  # nunca postar formulário sem ler o schema (contrato)
        if r.get("type") in ("create_entry", "abort"):
            break
        if r.get("type") != "form":
            _desiste()  # menu, progress, credencial externa — é do usuário
        schema = r.get("data_schema") or []
        if any(c.get("required") and c.get("default") is None for c in schema):
            _desiste()
        corpo = {c["name"]: c["default"] for c in schema
                 if c.get("default") is not None}
        st, r = http(f"/api/config/config_entries/flow/{r['flow_id']}",
                     "POST", corpo, token=token)
        if st != 200 or not isinstance(r, dict):
            erro(f"/api/config/config_entries/flow/{dominio}", st)
    criadas = _entries(token, dominio)
    if not criadas:
        # abort (ex.: tuya sem credencial de nuvem — medido em campo) ou um
        # flow que nunca fecha só com defaults: é do USUÁRIO, não erro nosso
        _desiste()
    permitidas = fontes.split(",")
    for e in criadas:
        if e.get("source") not in permitidas:
            http(f"/api/config/config_entries/entry/{e['entry_id']}",
                 "DELETE", token=token)
            erro(f"flow {dominio} (source {e.get('source')} fora do conjunto)", 0)
    sys.exit(0)


def cmd_flows_pendentes():
    """Imprime 'dominio contagem' dos discovery flows esperando o usuário.
    Listar flows em progresso não tem rota REST (405, medido em 24/08) —
    é o comando WS config_entries/flow/progress."""
    ws, _tok = _ws_autenticado()
    m = ws.chama({"type": "config_entries/flow/progress"})
    if not m.get("success"):
        erro("config_entries/flow/progress", 0)
    contagem = {}
    for f in m.get("result") or []:
        d = f.get("handler", "?")
        contagem[d] = contagem.get(d, 0) + 1
    for d in sorted(contagem):
        print(d, contagem[d])


# ── configuração do Core (F9) ────────────────────────────────────────────────
def cmd_core_check():
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    st, r = http("/api/config/core/check_config", "POST", {}, token=token)
    if st != 200 or not isinstance(r, dict) or r.get("result") != "valid":
        erro("/api/config/core/check_config", st)


def cmd_core_restart():
    usuario, senha = _le_credencial()
    token, _ = login(usuario, senha)
    st, _r = http("/api/services/homeassistant/restart", "POST", {},
                  token=token, timeout=10)
    # o restart derruba a conexão no meio — status 0 aqui não é erro
    if st not in (0, 200):
        erro("/api/services/homeassistant/restart", st)


def main():
    if not BASE:
        erro("HAOS_BASE ausente", 0)
    args = sys.argv[1:]
    if not args:
        erro("comando ausente", 0)
    cmd, resto = args[0], args[1:]
    if cmd == "conta":
        cmd_conta()
    elif cmd == "repo-ensure":
        cmd_repo_ensure(resto[0], resto[1])
    elif cmd == "addon-ensure":
        cmd_addon_ensure(resto[0], len(resto) > 1 and resto[1] == "--options-stdin")
    elif cmd == "addon-option":
        cmd_addon_option(resto[0], resto[1])
    elif cmd == "entry-ensure":
        cmd_entry_ensure(resto[0], resto[1])
    elif cmd == "flows-pendentes":
        cmd_flows_pendentes()
    elif cmd == "core-check":
        cmd_core_check()
    elif cmd == "core-restart":
        cmd_core_restart()
    else:
        erro(f"comando desconhecido {cmd}", 0)


main()
FIM_EMB_HELPER
)
# <<< HELPER EMBUTIDO <<<
# >>> PKG_ENERGIA EMBUTIDO >>>
HAOS_PKG_ENERGIA=$(cat <<'FIM_EMB_PKG_ENERGIA'
# =============================================================================
# energia_br.yaml — custo de energia elétrica no Brasil
#                   Reproduz a fatura NA VÍRGULA e simula Convencional × Branca
#
# Instalação: copie para /config/packages/ e no configuration.yaml:
#               homeassistant:
#                 packages: !include_dir_named packages
#
# -----------------------------------------------------------------------------
# COMO A FATURA SE COMPÕE — validado contra fatura Light AGO/2026, 304 kWh
# -----------------------------------------------------------------------------
#   Tributos são "por dentro": ICMS sobre o BRUTO, PIS/COFINS sobre o LÍQUIDO DE ICMS.
#     fator = 1 / (1 − icms − (pis + cofins) × (1 − icms))
#     ICMS 24,00% · PIS 1,23% · COFINS 5,67% → 1,413308
#     fatura mediu 1,36636 ÷ 0,96678 = 1,413310   (bate na 6ª casa)
#
#   Reprodução linha a linha:
#     (0,94793 + 0,01885) × 1,413308 × 304 kWh = 415,37  ✓ (fatura: 415,37)
#     ICMS   24,00% de 415,37 =  99,69  ✓        PIS  1,23% de 315,68 =  3,88  ✓
#     COFINS  5,67% de 315,68 =  17,90  ✓
#     415,37 − 10,13 + 2,08 + 64,60 = 471,92  ✓ (TOTAL A PAGAR: 471,92)
#
#   ⚠️ A BANDEIRA está DENTRO da linha de energia. "Bandeira Amarela 8,10" é
#      descrição do que ela contribuiu aos 415,37, não item somado à parte.
#   ⚠️ A COSIP (64,60) é MUNICIPAL e NÃO escala com kWh. São 13,7% da conta.
#      Modelo que só multiplica consumo × tarifa erra a fatura em R$ 56,55/mês.
#
# -----------------------------------------------------------------------------
# ONDE MORA CADA COISA — e por quê
# -----------------------------------------------------------------------------
#   Tarifas por kWh  → sensor `Tabela Tarifária`, como ATRIBUTOS literais.
#     Motivo: a doc do HA fixa o step mínimo do input_number em 0,001
#     ("step: Smallest value 0.001"). Guardar 0,947927 ali vira 0,948, e a
#     conta deixa de bater na vírgula. Literal no YAML não tem esse limite.
#
#   Alíquotas e encargos → input_number. Aqui 0,01 é resolução de sobra
#     (ICMS 24,00% · COSIP 64,60) e o ajuste pela interface é desejável.
#
# -----------------------------------------------------------------------------
# FONTES (lidas 2026-08-23)
# -----------------------------------------------------------------------------
#   ANEEL — dados abertos, tarifas homologadas (atualização semanal declarada)
#     https://dadosabertos.aneel.gov.br/dataset/tarifas-distribuidoras-energia-eletrica
#     resource_id fcf2906c-7c32-4b9b-a637-054e7a5234f4 · 324.629 registros
#     filtros: NumCNPJDistribuidora + DscSubGrupo=B1 + DscClasse=Residencial
#              + DscBaseTarifaria="Tarifa de Aplicação" + DscDetalhe="Não se aplica"
#     tarifa = (VlrTUSD + VlrTE) ÷ 1000   (o CSV publica em R$/MWh, sem tributos)
#
#   ANEEL — regra da Tarifa Branca e postos tarifários
#     gov.br/aneel/pt-br/assuntos/tarifas/entenda-a-tarifa/postos-tarifarios
#     · Ponta: "período diário de 3h consecutivas, com exceção feita aos
#       sábados, domingos e feriados nacionais"
#     · Intermediário: "1h a 1h30 ANTES E DEPOIS do horário de ponta"
#     · "Nos fins de semana e feriados nacionais, todas as horas são fora de ponta"
#     · Janelas definidas POR DISTRIBUIDORA na revisão tarifária periódica
#
#   Requer a integração `workday` (core, config flow) com país BR e a subdivisão
#   do estado — é ela que conhece feriados nacionais e estaduais.
# =============================================================================

template:
  # ═══════════════════════════════════════════════════════════════════════════
  # TABELA TARIFÁRIA — valores canônicos em R$/kWh LÍQUIDOS (sem tributos)
  #
  # ⚠️  ESTES VALORES REFLETEM OVERRIDE REGULATÓRIO, não o CSV bruto da ANEEL.
  #       REH 3.571/2026 (base) → Despacho ANEEL 921/2026 alterou o reajuste
  #       anual de 2026 → Despacho 2129/2026 restaurou os efeitos.
  #     O CSV de dados abertos ainda publica 0,88056 para o convencional.
  #     A diferença de 0,067367 R$/kWh foi confirmada contra fatura real.
  #
  #     → CONSEQUÊNCIA PARA O ATUALIZADOR AUTOMÁTICO: baixar o CSV e publicar
  #       direto produz tarifa ERRADA. É obrigatória uma camada de override
  #       que consulte atos posteriores antes de sobrescrever este bloco.
  # ═══════════════════════════════════════════════════════════════════════════
  - sensor:
      - name: "Tabela Tarifária"
        unique_id: tabela_tarifaria
        icon: mdi:table-large
        state: "LIGHT SESA"
        attributes:
          cnpj: "60444437000146"
          subgrupo: "B1 Residencial"
          vigencia_inicio: "2026-03-15"
          vigencia_fim: "2027-03-14"
          ato: "REH 3.571/2026 + Despacho 921/2026, restaurado por 2129/2026"
          convencional: 0.94793
          ponta: 1.73992
          intermediaria: 1.20499
          fora_ponta: 0.83447
          bandeira: 0.01885
          bandeira_nome: "Amarela"

      # ── Fator de tributos, DERIVADO das alíquotas
      - name: "Fator de Tributos"
        unique_id: fator_tributos
        icon: mdi:calculator-variant
        state: >
          {% set i = states('input_number.aliquota_icms')|float(0) / 100 %}
          {% set p = states('input_number.aliquota_pis')|float(0) / 100 %}
          {% set c = states('input_number.aliquota_cofins')|float(0) / 100 %}
          {% set d = 1 - i - (p + c) * (1 - i) %}
          {{ (1 / d) | round(6) if d > 0 else 0 }}

      # ── Preço final por posto = (tarifa líquida + bandeira) × fator
      - name: "Preço Convencional"
        unique_id: preco_convencional
        unit_of_measurement: "BRL/kWh"
        state: >
          {% set t = states.sensor.tabela_tarifaria.attributes %}
          {{ ((t.convencional|float(0) + t.bandeira|float(0)) * states('sensor.fator_tributos')|float(1)) | round(6) }}

      - name: "Preço Ponta"
        unique_id: preco_ponta
        unit_of_measurement: "BRL/kWh"
        state: >
          {% set t = states.sensor.tabela_tarifaria.attributes %}
          {{ ((t.ponta|float(0) + t.bandeira|float(0)) * states('sensor.fator_tributos')|float(1)) | round(6) }}

      - name: "Preço Intermediário"
        unique_id: preco_intermediario
        unit_of_measurement: "BRL/kWh"
        state: >
          {% set t = states.sensor.tabela_tarifaria.attributes %}
          {{ ((t.intermediaria|float(0) + t.bandeira|float(0)) * states('sensor.fator_tributos')|float(1)) | round(6) }}

      - name: "Preço Fora Ponta"
        unique_id: preco_fora_ponta
        unit_of_measurement: "BRL/kWh"
        state: >
          {% set t = states.sensor.tabela_tarifaria.attributes %}
          {{ ((t.fora_ponta|float(0) + t.bandeira|float(0)) * states('sensor.fator_tributos')|float(1)) | round(6) }}

      # ── Encargos fixos do mês (independem do consumo)
      - name: "Encargos Fixos do Mês"
        unique_id: encargos_fixos_mes
        unit_of_measurement: BRL
        device_class: monetary
        state: >
          {{ (states('input_number.encargo_cosip')|float(0)
            + states('input_number.encargo_complementos')|float(0)
            - states('input_number.encargo_bonus')|float(0)) | round(2) }}

      # ── Energia do mês em cada modalidade
      - name: "Energia Mensal Convencional"
        unique_id: energia_mensal_convencional
        unit_of_measurement: BRL
        device_class: monetary
        state: >
          {% set p = states('sensor.monthly_energy_peak')|float(0) %}
          {% set s = states('sensor.monthly_energy_shoulder')|float(0) %}
          {% set o = states('sensor.monthly_energy_offpeak')|float(0) %}
          {{ ((p + s + o) * states('sensor.preco_convencional')|float(0)) | round(2) }}

      - name: "Energia Mensal Branca"
        unique_id: energia_mensal_branca
        unit_of_measurement: BRL
        device_class: monetary
        state: >
          {% set p = states('sensor.monthly_energy_peak')|float(0) %}
          {% set s = states('sensor.monthly_energy_shoulder')|float(0) %}
          {% set o = states('sensor.monthly_energy_offpeak')|float(0) %}
          {{ (p * states('sensor.preco_ponta')|float(0)
            + s * states('sensor.preco_intermediario')|float(0)
            + o * states('sensor.preco_fora_ponta')|float(0)) | round(2) }}

      # ── FATURA COMPLETA — é o que se paga
      - name: "Fatura Mensal Convencional"
        unique_id: fatura_mensal_convencional
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:file-document-outline
        state: >
          {{ (states('sensor.energia_mensal_convencional')|float(0)
            + states('sensor.encargos_fixos_mes')|float(0)) | round(2) }}

      - name: "Fatura Mensal Branca"
        unique_id: fatura_mensal_branca
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:file-document-outline
        state: >
          {{ (states('sensor.energia_mensal_branca')|float(0)
            + states('sensor.encargos_fixos_mes')|float(0)) | round(2) }}

      # ── Veredito da simulação
      - name: "Economia com Tarifa Branca"
        unique_id: economia_tarifa_branca
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:swap-horizontal
        state: >
          {{ (states('sensor.fatura_mensal_convencional')|float(0)
            - states('sensor.fatura_mensal_branca')|float(0)) | round(2) }}
        attributes:
          melhor_modalidade: >
            {{ 'Tarifa Branca' if states('sensor.fatura_mensal_convencional')|float(0)
                                > states('sensor.fatura_mensal_branca')|float(0)
               else 'Convencional' }}

      # ── Cerca do package: digite o total da fatura, isto deve ficar em zero
      - name: "Desvio da Conferência"
        unique_id: desvio_conferencia
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:scale-balance
        state: >
          {{ (states('sensor.fatura_mensal_convencional')|float(0)
            - states('input_number.fatura_conferencia')|float(0)) | round(2) }}

      # ── Alerta de fim de vigência (a virada é conhecida, não é surpresa)
      - name: "Dias até Reajuste Tarifário"
        unique_id: dias_ate_reajuste
        unit_of_measurement: d
        icon: mdi:calendar-clock
        state: >
          {% set fim = states.sensor.tabela_tarifaria.attributes.vigencia_fim %}
          {{ ((fim | as_datetime).date() - now().date()).days }}

      - name: "Posto Tarifário Atual"
        unique_id: posto_tarifario_atual
        icon: mdi:clock-outline
        state: >
          {% set m = states('select.monthly_energy') %}
          {{ {'peak':'Ponta','shoulder':'Intermediário','offpeak':'Fora Ponta'}.get(m, m) }}

input_number:
  # ── Alíquotas — copie do quadro "Tributo" da sua fatura
  aliquota_icms:
    name: "Alíquota ICMS"
    initial: 24.0
    min: 0
    max: 40
    step: 0.01
    unit_of_measurement: "%"
    icon: mdi:percent
    mode: box
  aliquota_pis:
    name: "Alíquota PIS/PASEP"
    initial: 1.23
    min: 0
    max: 10
    step: 0.01
    unit_of_measurement: "%"
    icon: mdi:percent
    mode: box
  aliquota_cofins:
    name: "Alíquota COFINS"
    initial: 5.67
    min: 0
    max: 20
    step: 0.01
    unit_of_measurement: "%"
    icon: mdi:percent
    mode: box

  # ── Encargos fixos do mês (R$) — NÃO escalam com consumo
  encargo_cosip:
    name: "Contrib. Custeio Iluminação Pública"
    initial: 0
    min: 0
    max: 1000
    step: 0.01
    unit_of_measurement: "BRL"
    icon: mdi:lightbulb-on-outline
    mode: box
  encargo_complementos:
    name: "Complementos e outros débitos"
    initial: 0
    min: -1000
    max: 1000
    step: 0.01
    unit_of_measurement: "BRL"
    icon: mdi:plus-box-outline
    mode: box
  encargo_bonus:
    name: "Bônus e créditos (positivo, será subtraído)"
    initial: 0
    min: 0
    max: 1000
    step: 0.01
    unit_of_measurement: "BRL"
    icon: mdi:minus-box-outline
    mode: box

  # ── Conferência — total da última fatura, para validar o modelo
  fatura_conferencia:
    name: "Total da última fatura (conferência)"
    initial: 0
    min: 0
    max: 100000
    step: 0.01
    unit_of_measurement: "BRL"
    icon: mdi:file-document-check-outline
    mode: box

utility_meter:
  # Roda mesmo no Convencional: sem a quebra por posto não existe simulação.
  daily_energy:
    source: sensor.energy_total          # ← troque pela sua fonte de kWh acumulado
    cycle: daily
    tariffs: [peak, shoulder, offpeak]
  monthly_energy:
    source: sensor.energy_total          # ← troque pela sua fonte de kWh acumulado
    cycle: monthly
    tariffs: [peak, shoulder, offpeak]

automation:
  # ⚠️ AS JANELAS SÃO POR DISTRIBUIDORA, não universais.
  #    A ANEEL fixa a ESTRUTURA (ponta 3h; intermediário 1h–1h30 antes E depois);
  #    as janelas saem da revisão tarifária de cada distribuidora. Os horários
  #    abaixo são exemplo coerente com a regra — confirme na sua antes de usar.
  - id: energia_br_posto_tarifario
    alias: "Energia BR — seleciona o posto tarifário"
    description: >
      Chaveia o utility_meter entre os postos. Em dia não útil força fora ponta
      o dia inteiro, conforme regra da ANEEL. Recalcula no start do HA e quando
      o workday muda, para não ficar preso no posto errado após reinício.
    mode: single
    trigger:
      - platform: time
        at: "16:30:00"
        variables: {posto: shoulder}
      - platform: time
        at: "17:30:00"
        variables: {posto: peak}
      - platform: time
        at: "20:30:00"
        variables: {posto: shoulder}
      - platform: time
        at: "21:30:00"
        variables: {posto: offpeak}
      - platform: state
        entity_id: binary_sensor.workday_sensor
        variables: {posto: recalcular}
      - platform: homeassistant
        event: start
        variables: {posto: recalcular}
    action:
      - variables:
          util: "{{ is_state('binary_sensor.workday_sensor','on') }}"
          agora: "{{ now().strftime('%H:%M') }}"
          alvo: >
            {% if not util %}offpeak
            {% elif posto != 'recalcular' %}{{ posto }}
            {% elif '17:30' <= agora < '20:30' %}peak
            {% elif '16:30' <= agora < '17:30' or '20:30' <= agora < '21:30' %}shoulder
            {% else %}offpeak
            {% endif %}
      - service: select.select_option
        target:
          entity_id:
            - select.daily_energy
            - select.monthly_energy
        data:
          option: "{{ alvo | trim }}"
FIM_EMB_PKG_ENERGIA
)
# <<< PKG_ENERGIA EMBUTIDO <<<
# >>> PKG_GAS EMBUTIDO >>>
HAOS_PKG_GAS=$(cat <<'FIM_EMB_PKG_GAS'
# =============================================================================
# gas_br.yaml — custo de gás canalizado no Brasil (modelo RJ / Naturgy)
#               Reproduz a fatura NA VÍRGULA
#
# Instalação: copie para /config/packages/ e no configuration.yaml:
#               homeassistant:
#                 packages: !include_dir_named packages
#
# -----------------------------------------------------------------------------
# QUATRO CAMADAS — validadas contra fatura Naturgy CEG, JUL/2026, cliente residencial
# -----------------------------------------------------------------------------
#
# 1) VOLUME CORRIGIDO — gás NÃO é faturado no volume medido
#      medido × fator P,T,Z × fator PCS, arredondado ao m³ inteiro
#      Fatura: 19 m³ × 1,02146 × 1,012 = 19,64 → cobra 20 m³  (+5,3%)
#      P,T,Z = pressão, temperatura e compressibilidade · PCS = poder calorífico
#      Um modelo que use o volume do medidor erra sistematicamente PARA BAIXO.
#
# 2) CASCATA POR FAIXA — cada parcela do consumo na sua faixa
#      Fatura imprime o cálculo:
#        0–7  :  7,00 m³ × 9,5319  =  66,72
#        8–23 : 13,00 m³ × 12,4840 = 162,29
#        total                     = 229,01  ✓
#      ⚠️ A fatura ARREDONDA CADA LINHA antes de somar. Somar e arredondar
#         no fim dá 229,02 — um centavo de diferença.
#      ⚠️ Consumo na primeira faixa cobra TAXA MÍNIMA (o volume cheio da faixa).
#
# 3) TARIFA JÁ VEM COM TRIBUTOS
#      "Impostos incluídos no total do faturamento" — a cascata produz o valor
#      final. Diferente da energia, onde a tarifa é líquida e se aplica fator.
#
# 4) TRIBUTOS — estrutura própria, NÃO é a da energia
#      ICMS: BASE REDUZIDA a 60% do total (Decreto RJ 25.941/1999), alíquota 20%
#            → efetivo 12% do total, não 20%
#            Fatura: base 137,41 de 229,01 = exatamente 60,00%
#                    137,41 × 20% = 27,48  ✓
#      PIS+COFINS: 9,25% (1,65 + 7,60) sobre o valor LÍQUIDO DE ICMS
#            Fatura: (229,01 − 27,48) × 9,25% = 18,64  (fatura: 18,65)
#      Total dos tributos: 46,13  ✓
#
# -----------------------------------------------------------------------------
# FONTES (lidas 2026-08-23)
# -----------------------------------------------------------------------------
#   AGENERSA — tarifas em vigor .... https://www.rj.gov.br/agenersa/tarifas-em-vigor
#   Naturgy CEG ..... https://www.naturgy.com.br/wp-content/uploads/2026/07/PB85USD_Tarifa-CEG-01.08.26.pdf
#   Naturgy CEG Rio . https://www.naturgy.com.br/wp-content/uploads/2026/07/PB85USD_Tarifa-CRIO-01.08.26.pdf
#
#   ⚠️ CEG e CEG Rio são distribuidoras DIFERENTES com tabelas DIFERENTES.
#      Identifique pelo CNPJ na sua fatura:
#        CEG      33.938.119/0002-40
#      Os PDFs trazem `valid_from` mas frequentemente NÃO trazem `valid_until`.
#      Não invente data de fim: monitore a mudança do arquivo na página índice.
# =============================================================================

template:
  # ═══════════════════════════════════════════════════════════════════════════
  # TABELA TARIFÁRIA — R$/m³ JÁ COM TRIBUTOS
  # Literais no YAML e não input_number: o step mínimo do input_number é 0,001
  # e a tarifa tem 4 casas decimais.
  #
  # Valores desta fatura (JUL/2026). O PDF vigente a partir de 01/08/2026 traz
  # 9,7235 e 12,6756 — a virada de tarifa está capturada aqui.
  # ═══════════════════════════════════════════════════════════════════════════
  - sensor:
      - name: "Tabela Gás"
        unique_id: tabela_gas
        icon: mdi:table-large
        state: "CEG"
        attributes:
          distribuidora: "Naturgy CEG"
          cnpj: "33938119000240"
          classe: "Residencial"
          vigencia_inicio: "2026-07-01"
          vigencia_fim: ""            # PDF não publica fim — monitorar a fonte
                                      # (attribute é template: null é inválido)
          # faixas: [limite_superior_m3, tarifa_R$/m3_com_tributos]
          # a última faixa usa limite null = sem teto
          faixa_1_ate: 7
          faixa_1_tarifa: 9.5319
          faixa_2_ate: 23
          faixa_2_tarifa: 12.4840
          faixa_3_ate: 83
          faixa_3_tarifa: 15.3462
          faixa_4_ate: null
          faixa_4_tarifa: 16.1928
          volume_minimo_m3: 7         # consumo na 1ª faixa cobra a faixa cheia
          icms_reducao_base: 0.60     # Decreto RJ 25.941/1999
          icms_aliquota: 0.20
          pis_cofins_aliquota: 0.0925 # 1,65 + 7,60, sobre líquido de ICMS

      # ── Volume corrigido: medido × fator, arredondado ao m³ inteiro
      - name: "Gás Volume Corrigido"
        unique_id: gas_volume_corrigido
        unit_of_measurement: "m³"
        icon: mdi:gas-cylinder
        state: >
          {% set m = states('sensor.gas_consumo_medido')|float(0) %}
          {% set f = states('input_number.gas_fator_correcao')|float(1) %}
          {{ (m * f) | round(0) | int }}
        attributes:
          medido: "{{ states('sensor.gas_consumo_medido') }}"
          fator: "{{ states('input_number.gas_fator_correcao') }}"

      # ── Cascata, arredondando CADA faixa como a fatura faz
      - name: "Gás Custo Fornecimento"
        unique_id: gas_custo_fornecimento
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:fire
        state: >
          {% set t = states.sensor.tabela_gas.attributes %}
          {% set v = states('sensor.gas_volume_corrigido')|float(0) %}
          {% set vmin = t.volume_minimo_m3 | float(0) %}
          {% set c = [v, vmin] | max %}
          {% set l1 = t.faixa_1_ate | float(0) %}
          {% set l2 = t.faixa_2_ate | float(0) %}
          {% set l3 = t.faixa_3_ate | float(0) %}
          {% set u1 = [c, l1] | min %}
          {% set u2 = [[c, l2] | min - l1, 0] | max %}
          {% set u3 = [[c, l3] | min - l2, 0] | max %}
          {% set u4 = [c - l3, 0] | max %}
          {{ ( (u1 * t.faixa_1_tarifa|float(0)) | round(2)
             + (u2 * t.faixa_2_tarifa|float(0)) | round(2)
             + (u3 * t.faixa_3_tarifa|float(0)) | round(2)
             + (u4 * t.faixa_4_tarifa|float(0)) | round(2) ) | round(2) }}
        attributes:
          faixa_1_m3: >
            {% set t = states.sensor.tabela_gas.attributes %}
            {% set c = [states('sensor.gas_volume_corrigido')|float(0), t.volume_minimo_m3|float(0)] | max %}
            {{ [c, t.faixa_1_ate|float(0)] | min }}
          faixa_2_m3: >
            {% set t = states.sensor.tabela_gas.attributes %}
            {% set c = [states('sensor.gas_volume_corrigido')|float(0), t.volume_minimo_m3|float(0)] | max %}
            {{ [[c, t.faixa_2_ate|float(0)] | min - t.faixa_1_ate|float(0), 0] | max }}

      # ── Decomposição dos tributos (informativa; já estão no valor acima)
      - name: "Gás ICMS"
        unique_id: gas_icms
        unit_of_measurement: BRL
        device_class: monetary
        state: >
          {% set t = states.sensor.tabela_gas.attributes %}
          {% set v = states('sensor.gas_custo_fornecimento')|float(0) %}
          {{ (v * t.icms_reducao_base|float(0) * t.icms_aliquota|float(0)) | round(2) }}
        attributes:
          base_reduzida: >
            {% set t = states.sensor.tabela_gas.attributes %}
            {{ (states('sensor.gas_custo_fornecimento')|float(0) * t.icms_reducao_base|float(0)) | round(2) }}
          fundamento: "Decreto RJ 25.941/1999 — base de cálculo reduzida"

      - name: "Gás PIS COFINS"
        unique_id: gas_pis_cofins
        unit_of_measurement: BRL
        device_class: monetary
        state: >
          {% set t = states.sensor.tabela_gas.attributes %}
          {% set v = states('sensor.gas_custo_fornecimento')|float(0) %}
          {% set icms = states('sensor.gas_icms')|float(0) %}
          {{ ((v - icms) * t.pis_cofins_aliquota|float(0)) | round(2) }}

      - name: "Gás Tributos Total"
        unique_id: gas_tributos_total
        unit_of_measurement: BRL
        device_class: monetary
        state: >
          {{ (states('sensor.gas_icms')|float(0)
            + states('sensor.gas_pis_cofins')|float(0)) | round(2) }}

      # ── Cerca do package: digite o total da fatura, isto deve ficar em zero
      - name: "Gás Desvio da Conferência"
        unique_id: gas_desvio_conferencia
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:scale-balance
        state: >
          {{ (states('sensor.gas_custo_fornecimento')|float(0)
            - states('input_number.gas_fatura_conferencia')|float(0)) | round(2) }}

input_number:
  # ── Fator de correção COMBINADO = P,T,Z × PCS, lido da sua fatura
  #    Fatura JUL/2026: 1,02146 × 1,012 = 1,03372
  #    ⚠️ step mínimo do input_number é 0,001, então guarda 1,034.
  #       Verificado: 19 × 1,03372 = 19,6407 e 19 × 1,034 = 19,646 — os dois
  #       arredondam para 20. A perda só importaria a ~0,05% de uma fronteira
  #       de arredondamento. Se a sua fatura divergir, ajuste este valor.
  gas_fator_correcao:
    name: "Gás — fator de correção (P,T,Z × PCS)"
    initial: 1.034
    min: 0.9
    max: 1.2
    step: 0.001
    icon: mdi:tune-variant
    mode: box

  # ── Conferência: total de fornecimento da última fatura
  gas_fatura_conferencia:
    name: "Gás — total da última fatura (conferência)"
    initial: 229.01
    min: 0
    max: 100000
    step: 0.01
    unit_of_measurement: "BRL"
    icon: mdi:file-document-check-outline
    mode: box

# -----------------------------------------------------------------------------
# FONTE DE CONSUMO
#
# `sensor.gas_consumo_medido` é o volume do MEDIDOR no ciclo, em m³.
# Sem medidor conectado ao HA, crie um input_number e digite a diferença de
# leituras da fatura (ex.: 4218 − 4199 = 19).
#
# Com medidor, use utility_meter sobre o sensor de volume acumulado:
#
#   utility_meter:
#     gas_mensal:
#       source: sensor.gas_volume_total
#       cycle: monthly
#
# e aponte `sensor.gas_consumo_medido` para ele com um template sensor.
#
# O painel de Energia do HA tem aba própria de Gás (Settings → Dashboards →
# Energy → Gas consumption) — aponte para o sensor de volume acumulado, não
# para o corrigido, para não contar a correção duas vezes.
# -----------------------------------------------------------------------------
FIM_EMB_PKG_GAS
)
# <<< PKG_GAS EMBUTIDO <<<
# >>> PKG_AGUA EMBUTIDO >>>
HAOS_PKG_AGUA=$(cat <<'FIM_EMB_PKG_AGUA'
# =============================================================================
# agua_br.yaml — água e esgoto: simula o que você pagaria como cliente DIRETO
#                da concessionária e compara com o rateio do condomínio
#
# Instalação: copie para /config/packages/ e no configuration.yaml:
#               homeassistant:
#                 packages: !include_dir_named packages
#
# -----------------------------------------------------------------------------
# POR QUE ESTE PACKAGE É DIFERENTE DOS DE ENERGIA E GÁS
# -----------------------------------------------------------------------------
#   Nos outros dois a fatura vem da concessionária e o modelo reproduz a conta.
#   Aqui a fatura vem do CONDOMÍNIO, que faz rateio próprio. Então o package
#   NÃO tenta reproduzir o rateio — ele calcula o que a REGRA DA CONCESSIONÁRIA
#   cobraria de um cliente direto e mostra a DIFERENÇA.
#
#   Essa diferença é o dado útil: revela se o rateio do prédio favorece ou
#   penaliza a sua unidade.
#
#   ⚠️ ESPERE DIVERGÊNCIA, e ela não é defeito do modelo.
#      Prédio é faturado como uma ligação com N "economias". Nas tarifas
#      brasileiras de água os LIMITES das faixas escalam com o número de
#      economias — então o prédio inteiro entra numa curva diferente da de uma
#      residência isolada. O rateio interno depois divide isso por critério
#      próprio (medição individual, fração ideal, etc).
#
# -----------------------------------------------------------------------------
# CONCESSIONÁRIA
# -----------------------------------------------------------------------------
#   Exemplo preenchido: a ÁGUAS DO RIO — BLOCO 1, que atende parte da capital.
#   A própria concessionária publica a lista de distritos do Bloco 1:
#     https://aguasdorio.com.br/quem-somos/
#   Troque `bairro` e a tabela pela sua concessionária — a estrutura é a mesma.
#
#   ⚠️ ÁREA A ou ÁREA B: **confirme a sua**.
#      A referência encontrada diz que a Área B reúne bairros da AP5/zona oeste
#      e da zona norte — o que por EXCLUSÃO colocaria a Zona Sul na Área A.
#      Isso é INFERÊNCIA, não fonte. Por isso a área é selecionável e o padrão
#      vem marcado como não confirmado. Confirme na sua conta ou na AGENERSA:
#        https://www.rj.gov.br/agenersa/tarifas-em-vigor
#
#   ⚠️ VALORES COM DATA DE REFERÊNCIA 01/12/2025.
#      Podem estar desatualizados. Confirme antes de usar como verdade:
#        https://www.rj.gov.br/agenersa/sites/default/files/arquivos_paginas_basicas/AGUASDORIOBL%201.pdf
#
#   Estrutura: cascata progressiva por faixas de 0–15, 16–30, 31–45, 46–60, >60 m³.
#   Esgoto: a estrutura consultada indica cobrança EQUIVALENTE à água (100%).
#   ⚠️ NUNCA aplicar percentual de esgoto de um prestador a outro.
# =============================================================================

template:
  - sensor:
      # ═══════════════════════════════════════════════════════════════════════
      # TABELA — R$/m³ de ÁGUA. Literais no YAML: input_number não guarda 6 casas.
      # ═══════════════════════════════════════════════════════════════════════
      - name: "Tabela Água"
        unique_id: tabela_agua
        icon: mdi:table-large
        state: "Águas do Rio 1"
        attributes:
          concessionaria: "Águas do Rio — Bloco 1"
          municipio: "Rio de Janeiro"
          bairro: ""            # preencha com o seu
          area_confirmada: false
          data_referencia: "2025-12-01"
          esgoto_percentual: 1.00
          # attributes são TEMPLATES (doc do template integration): lista
          # literal YAML é inválida — embrulhada em Jinja rende lista nativa
          limites: "{{ [15, 30, 45, 60] }}"
          area_a: "{{ [7.436291, 16.359841, 22.308872, 44.617747, 59.490329] }}"
          area_b: "{{ [6.523050, 14.350710, 19.569152, 39.138304, 52.184405] }}"

      # ── Cascata da água, pela área escolhida
      - name: "Água Custo Simulado"
        unique_id: agua_custo_simulado
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:water
        state: >
          {% set t = states.sensor.tabela_agua.attributes %}
          {% set tar = t.area_a if is_state('input_select.agua_area','Área A') else t.area_b %}
          {% set lim = t.limites %}
          {% set c = states('input_number.agua_consumo_m3')|float(0) %}
          {% set u1 = [c, lim[0]] | min %}
          {% set u2 = [[c, lim[1]] | min - lim[0], 0] | max %}
          {% set u3 = [[c, lim[2]] | min - lim[1], 0] | max %}
          {% set u4 = [[c, lim[3]] | min - lim[2], 0] | max %}
          {% set u5 = [c - lim[3], 0] | max %}
          {{ ( u1*tar[0] + u2*tar[1] + u3*tar[2] + u4*tar[3] + u5*tar[4] ) | round(2) }}
        attributes:
          area: "{{ states('input_select.agua_area') }}"
          detalhe_faixas: >
            {% set t = states.sensor.tabela_agua.attributes %}
            {% set tar = t.area_a if is_state('input_select.agua_area','Área A') else t.area_b %}
            {% set lim = t.limites %}
            {% set c = states('input_number.agua_consumo_m3')|float(0) %}
            {% set u1 = [c, lim[0]] | min %}
            {% set u2 = [[c, lim[1]] | min - lim[0], 0] | max %}
            {{ '%.0f m³ × %.6f = %.2f | %.0f m³ × %.6f = %.2f'
               | format(u1, tar[0], u1*tar[0], u2, tar[1], u2*tar[1]) }}

      - name: "Esgoto Custo Simulado"
        unique_id: esgoto_custo_simulado
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:pipe-disconnected
        state: >
          {% set t = states.sensor.tabela_agua.attributes %}
          {{ (states('sensor.agua_custo_simulado')|float(0) * t.esgoto_percentual|float(1)) | round(2) }}

      - name: "Água e Esgoto Simulado"
        unique_id: agua_esgoto_simulado
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:calculator
        state: >
          {{ (states('sensor.agua_custo_simulado')|float(0)
            + states('sensor.esgoto_custo_simulado')|float(0)) | round(2) }}

      # ═══════════════════════════════════════════════════════════════════════
      # O DADO ÚTIL: quanto o rateio do condomínio diverge da regra
      # ═══════════════════════════════════════════════════════════════════════
      - name: "Água Diferença vs Condomínio"
        unique_id: agua_diferenca_condominio
        unit_of_measurement: BRL
        device_class: monetary
        icon: mdi:scale-balance
        state: >
          {{ (states('input_number.agua_valor_condominio')|float(0)
            - states('sensor.agua_esgoto_simulado')|float(0)) | round(2) }}
        attributes:
          leitura: >
            {% set d = states('input_number.agua_valor_condominio')|float(0)
                     - states('sensor.agua_esgoto_simulado')|float(0) %}
            {{ 'condomínio cobra A MAIS que a regra da concessionária' if d > 0
               else ('condomínio cobra A MENOS' if d < 0 else 'idêntico') }}
          percentual: >
            {% set s = states('sensor.agua_esgoto_simulado')|float(0) %}
            {% set c = states('input_number.agua_valor_condominio')|float(0) %}
            {{ ((c/s - 1) * 100) | round(1) if s > 0 else 0 }}

      - name: "Água Preço Efetivo Condomínio"
        unique_id: agua_preco_efetivo_condominio
        unit_of_measurement: "BRL/m³"
        icon: mdi:currency-usd
        state: >
          {% set c = states('input_number.agua_consumo_m3')|float(0) %}
          {{ (states('input_number.agua_valor_condominio')|float(0) / c) | round(4) if c > 0 else 0 }}

      - name: "Água Preço Efetivo Concessionária"
        unique_id: agua_preco_efetivo_concessionaria
        unit_of_measurement: "BRL/m³"
        icon: mdi:currency-usd
        state: >
          {% set c = states('input_number.agua_consumo_m3')|float(0) %}
          {{ (states('sensor.agua_esgoto_simulado')|float(0) / c) | round(4) if c > 0 else 0 }}

input_select:
  agua_area:
    name: "Água — área tarifária"
    options:
      - "Área A"
      - "Área B"
    initial: "Área A"
    icon: mdi:map-marker-radius

input_number:
  # ── Consumo do ciclo, em m³. Da linha da fatura do condomínio:
  #    "Água - Esgoto - Individual M³: 4 219,0000(Jul) − 4 198,0000(Jun) = 21,0000"
  agua_consumo_m3:
    name: "Água — consumo do ciclo"
    initial: 21
    min: 0
    max: 500
    step: 0.001
    unit_of_measurement: "m³"
    icon: mdi:water-outline
    mode: box

  # ── O que o condomínio repassou, para a comparação
  agua_valor_condominio:
    name: "Água — valor repassado pelo condomínio"
    initial: 356.39
    min: 0
    max: 100000
    step: 0.01
    unit_of_measurement: "BRL"
    icon: mdi:home-city-outline
    mode: box

# -----------------------------------------------------------------------------
# COMO LER O RESULTADO
#
#   `Água e Esgoto Simulado`          o que a regra da concessionária cobraria
#   `Água Diferença vs Condomínio`    positivo = o prédio cobra a mais
#   os dois `Preço Efetivo`           R$/m³ de cada lado, para comparação direta
#
#   Divergência de alguns por cento é ESPERADA — o prédio é faturado como uma
#   ligação com N economias, numa curva de faixas diferente. Divergência grande
#   e persistente é que merece pergunta ao síndico.
#
#   ⚠️ Este package NÃO reproduz a conta do condomínio e não deve ser usado
#      para contestar cobrança sem antes obter a fatura completa do prédio,
#      com prestador, área de concessão e número de economias.
# -----------------------------------------------------------------------------
FIM_EMB_PKG_AGUA
)
# <<< PKG_AGUA EMBUTIDO <<<

# ── acessores do catálogo ────────────────────────────────────────────────────
cat_rotulo() {
    local r id rot desc
    for r in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id rot desc <<< "$r"
        [ "$id" = "$1" ] && { printf '%s' "$rot"; return 0; }
    done
    printf '%s' "$1"
}
item_campo() {   # item_campo <id> <n>  — n é 1-based na ordem do schema
    local r campos
    for r in "${ITEM_DB[@]}"; do
        [ "${r%%|*}" = "$1" ] || continue
        IFS='|' read -r -a campos <<< "$r"
        printf '%s' "${campos[$(( $2 - 1 ))]}"
        return 0
    done
    return 1
}
tem_na_lista() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

# =============================================================================
# ARGUMENTOS
# =============================================================================
OP_PERFIL=""; OP_WITH=""; OP_VM_PERFIL=""; OP_VM_NOME="HomeAssistant"; OP_IMAGEM=""
OP_DRYRUN=0; OP_LIST=0; OP_NOINPUT=0; OP_FORCE=0
OP_QUIET=0; OP_VERBOSE=0; OP_ALL=0
OP_KEEP_IMAGE=0; OP_INSTALL_DEPS=0; OP_NO_OPEN=0
OP_MODO=""; OP_CONFIRM=""

modo_unico() {
    [ -z "$OP_MODO" ] || morrer "$E_USO" "--$1 / --$OP_MODO"
    OP_MODO="$1"
}

# O help só promete o que EXISTE. As flags das fases futuras (--doctor,
# --uninstall, --self-update, --resume, --upgrade, --bridge, --json, `last`)
# entram AQUI no mesmo commit em que a implementação entra — o gate executa
# cada flag publicada e reprova a que responder "não implementado" (B-4).
uso() {
    cat <<'USO'
haos-install.sh — Home Assistant OS numa VM VirtualBox em Mac Apple Silicon

  bash haos-install.sh [opções]
  curl -fsSL <raw-url> | bash -s -- [opções]

SELEÇÃO
  --profile <id>     haos_vanilla | haos_conectado | haos_casa | last
                     (last repete a última seleção salva)
  --with a,b,c       extras: ferramentas, casa_abhome, extensoes
  -a, --all          haos_casa + todos os extras (exceto o que exige opt-in)

VM
  --vm-profile <id>  vm_minimo | vm_equilibrado | vm_recomendado
  --vm-name <nome>   padrão: HomeAssistant

NÃO INSTALAM NADA
  -n, --dry-run      imprime o plano e sai (com --uninstall: só o plano de remoção)
  --list             lista o catálogo e sai
  --doctor           diagnóstico read-only: sistema, manifesto, imagem, estado
  --version          versão do instalador e a referência de compatibilidade
  -h, --help         esta ajuda

MANUTENÇÃO
  --uninstall        remove o que ESTE instalador criou (plano + confirmação)
  --confirm=<nome>   confirma o --uninstall sem terminal (o nome exato da VM)
  --self-update      atualiza este script pelo publicado (recusa downgrade)

OUTRAS
  --image <arquivo>  usa este .zip da imagem do HAOS (verificado por SHA-256)
  --keep-image       preserva o .zip baixado da imagem do HAOS
  -v, --verbose      mostra a saída crua de cada ferramenta
  -q, --quiet        suprime a saída normal
  --no-input         não pergunta nada; falha se faltar dado obrigatório
  --no-open          não abre o navegador no fim
  -f, --force        refaz artefato já presente. NÃO pula portão nem hash.
  --install-deps     instala pré-requisitos ausentes sem perguntar (VirtualBox)

Ambiente: HAOS_LANG=pt|en · NO_COLOR · HAOS_HA_USER/HAOS_HA_PASSWORD (conta
do HA sem terminal, ex.: CI)
USO
}

versao() {
    printf 'haos-install.sh %s\n' "$HAOS_INSTALL_VERSION"
    printf 'contrato verificado contra Home Assistant Core %s · HAOS %s\n' "$HAOS_REF_CORE" "$HAOS_REF_OS"
    printf 'https://github.com/aleonnet/haos-mac-mini · MIT\n'
}

# Flag de valor valida o shape NA HORA: sem isto, `--profile --help` engole a
# flag seguinte e o erro aparece longe da causa (achado 7 do gap analysis; o
# AtlasFile faz o mesmo no parser dele).
exige_valor() { # <flag> <valor?>
    case "${2:-}" in ''|-*) morrer "$E_USO" "$(msg flag_sem_valor "$1")" ;; esac
}

# O nome da VM entra em CAMINHO (manifesto, VirtualBox VMs/), em PLIST do
# launchd e em argv de VBoxManage — a banca reprovou aceitá-lo livre (um nome
# com `../` ou aspas vira travessia de diretório ou código persistente).
valida_vm_nome() {
    case "$OP_VM_NOME" in
        *[!A-Za-z0-9._-]*|''|.*)
            morrer "$E_USO" "$(msg vm_nome_invalido)" ;;
    esac
    [ "${#OP_VM_NOME}" -le 64 ] || morrer "$E_USO" "$(msg vm_nome_invalido)"
}

ler_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)      exige_valor --profile "${2:-}";    OP_PERFIL="$2"; shift ;;
            --profile=*)    exige_valor --profile "${1#*=}";   OP_PERFIL="${1#*=}" ;;
            --with)         exige_valor --with "${2:-}";       OP_WITH="$2"; shift ;;
            --with=*)       exige_valor --with "${1#*=}";      OP_WITH="${1#*=}" ;;
            --vm-profile)   exige_valor --vm-profile "${2:-}"; OP_VM_PERFIL="$2"; shift ;;
            --vm-profile=*) exige_valor --vm-profile "${1#*=}"; OP_VM_PERFIL="${1#*=}" ;;
            --vm-name)      exige_valor --vm-name "${2:-}";    OP_VM_NOME="$2"; shift
                            valida_vm_nome ;;
            --vm-name=*)    exige_valor --vm-name "${1#*=}";   OP_VM_NOME="${1#*=}"
                            valida_vm_nome ;;
            --image)        exige_valor --image "${2:-}";      OP_IMAGEM="$2"; shift ;;
            --image=*)      exige_valor --image "${1#*=}";     OP_IMAGEM="${1#*=}" ;;
            --doctor)       modo_unico doctor ;;
            --uninstall)    modo_unico uninstall ;;
            --self-update)  modo_unico self-update ;;
            --confirm=*)    OP_CONFIRM="${1#*=}" ;;
            -a|--all)       OP_ALL=1 ;;
            -n|--dry-run)   OP_DRYRUN=1 ;;
            --list)         OP_LIST=1 ;;
            --no-input)     OP_NOINPUT=1 ;;
            --no-open)      OP_NO_OPEN=1 ;;
            -f|--force)     OP_FORCE=1 ;;
            -q|--quiet)     OP_QUIET=1 ;;
            -v|--verbose)   OP_VERBOSE=1 ;;
            --keep-image)   OP_KEEP_IMAGE=1 ;;
            --install-deps) OP_INSTALL_DEPS=1 ;;
            --version)      versao; exit 0 ;;
            -h|--help)      uso; exit 0 ;;
            *)              ha_err "$(msg opcao_desconhecida "$1")"; printf '\n'; uso >&2; exit "$E_USO" ;;
        esac
        shift
    done
}

# =============================================================================
# --list
# =============================================================================
listar() {
    printf '%s\n\n' "$(msg cabecalho)"
    printf 'PISO — o que a instalação já cria sozinha (%s)\n' \
        "$(( ${#DEFAULT_CONFIG_DB[@]} + ${#HAOS_INTRINSIC_DB[@]} + ${#ONBOARDING_DB[@]} ))"
    printf '  default_config (%s): %s\n' "${#DEFAULT_CONFIG_DB[@]}" "${DEFAULT_CONFIG_DB[*]}" | fold -s -w 78 | sed '2,$s/^/    /'
    local r id d
    printf '  intrínsecos:'; for r in "${HAOS_INTRINSIC_DB[@]}"; do printf ' %s' "${r%%|*}"; done; printf '\n'
    printf '  onboarding: ';  for r in "${ONBOARDING_DB[@]}";     do printf ' %s' "${r%%|*}"; done; printf '\n'

    local c cid crot cdesc
    for c in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r cid crot cdesc <<< "$c"
        [ "$cid" = "vanilla" ] && continue
        printf '\n%s — %s\n' "$crot" "$cdesc"
        local it iid icat irot iorigem islug ipadrao
        for it in "${ITEM_DB[@]}"; do
            IFS='|' read -r iid icat irot iorigem islug ipadrao _ <<< "$it"
            [ "$icat" = "$cid" ] || continue
            local marca="  "; [ "$ipadrao" = "1" ] && marca="* "
            printf '  %s%-26s %s\n' "$marca" "$iid" "$irot"
        done
    done
    printf '\nDegraus (somam): '; for r in "${HAOS_PROFILE_DB[@]}"; do printf '%s ' "${r%%|*}"; done
    printf '\nExtras (à parte): %s\n' "${ORTOGONAL_DB[*]}"
    printf '\n* = pré-marcado quando a categoria é escolhida\n'
}

# =============================================================================
# F1 — PRÉ-VOO. Só lê. Nada é escrito nesta fase.
# =============================================================================
PROBE=""
# Num shell sem /usr/local/bin no PATH (SSH não-interativo, launchd, cron) o
# symlink do VBoxManage some e um VirtualBox instalado vira "not found" —
# aconteceu no teste de campo por SSH. O app bundle é o fato; o PATH, detalhe.
sonda() {
    command -v VBoxManage >/dev/null 2>&1 \
        || [ ! -x /Applications/VirtualBox.app/Contents/MacOS/VBoxManage ] \
        || PATH="$PATH:/Applications/VirtualBox.app/Contents/MacOS"
    PROBE="$(probe_all 2>/dev/null || true)"
}
p_get() { printf '%s\n' "$PROBE" | awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); print; exit}'; }

# Sonda embutida — mesma lógica de lib/probe-host.sh, só dados.
probe_all() {
    local total pagesize vs free active inactive spec wired comp purge used avail
    printf 'host.model=%s\n' "$(sysctl -n hw.model 2>/dev/null || true)"
    printf 'host.cpu=%s\n'   "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    printf 'host.arch=%s\n'  "$(uname -m)"
    printf 'host.os=%s\n'    "$(uname -s)"
    printf 'host.macos=%s\n' "$(sw_vers -productVersion 2>/dev/null || true)"

    total="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    pagesize="$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
    printf 'mem.total_mib=%s\n' $(( total / 1048576 ))
    vs="$(vm_stat 2>/dev/null || true)"
    if [ -n "$vs" ]; then
        _pg() { printf '%s\n' "$vs" | awk -v pat="$1" '$0 ~ pat {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.?$/){gsub(/\./,"",$i); print $i; exit}}'; }
        free="$(_pg 'Pages free')";        free="${free:-0}"
        inactive="$(_pg 'Pages inactive')"; inactive="${inactive:-0}"
        spec="$(_pg 'Pages speculative')";  spec="${spec:-0}"
        purge="$(_pg 'Pages purgeable')";   purge="${purge:-0}"
        avail=$(( (free + inactive + spec + purge) * pagesize ))
        printf 'mem.available_mib=%s\n' $(( avail / 1048576 ))
    fi

    printf 'cpu.performance=%s\n' "$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 0)"

    local vmdir; vmdir="$HOME/VirtualBox VMs"; [ -d "$vmdir" ] || vmdir="$HOME"
    printf 'disk.path=%s\n' "$vmdir"
    printf 'disk.available_mib=%s\n' "$(( $(df -k "$vmdir" 2>/dev/null | awk 'NR==2{print $4}' || echo 0) / 1024 ))"

    if command -v VBoxManage >/dev/null 2>&1; then
        printf 'vbox.present=1\n'
        printf 'vbox.version=%s\n' "$(VBoxManage --version 2>/dev/null | tr -d '\r')"
    else
        printf 'vbox.present=0\n'
    fi

    command -v python3 >/dev/null 2>&1 && printf 'python3.present=1\n' || printf 'python3.present=0\n'

    local n=0 port dev ip status media wired_f
    while IFS= read -r line; do
        case "$line" in
            "Hardware Port: "*) port="${line#Hardware Port: }" ;;
            "Device: "*)
                dev="${line#Device: }"
                ip="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
                status="$(ifconfig "$dev" 2>/dev/null | awk '/status:/{print $2}')"
                media="$(ifconfig "$dev" 2>/dev/null | awk '/media:/{print; exit}')"
                wired_f=0
                case "$media" in *baseT*|*10Gbase*) wired_f=1 ;; esac
                [ "$port" = "Wi-Fi" ] && wired_f=0
                if [ -n "$ip" ] || [ "${status:-}" = "active" ]; then
                    n=$(( n + 1 ))
                    printf 'net.%s.device=%s\n' "$n" "$dev"
                    printf 'net.%s.port=%s\n'   "$n" "$port"
                    printf 'net.%s.ip=%s\n'     "$n" "${ip:-}"
                    printf 'net.%s.wired=%s\n'  "$n" "$wired_f"
                fi ;;
        esac
    done <<EOF
$(networksetup -listallhardwareports 2>/dev/null || true)
EOF
    printf 'net.count=%s\n' "$n"
}

# ── novidades: melhor-esforço, 3 s de teto, silêncio na falha ────────────────
# O que o mac-env faz com o brew outdated, aqui vale para as DUAS fontes que
# envelhecem: o próprio instalador (raw publicado) e a release do HAOS (a
# imagem é fixada por tabela; release nova é AVISO, nunca troca automática).
checar_novidades() {
    local remoto tag
    remoto="$(curl -fsSL --max-time 3 "$HAOS_RAW_URL" 2>/dev/null         | grep -m1 '^HAOS_INSTALL_VERSION=' | cut -d'"' -f2)" || true
    if [ -n "$remoto" ] && ver_menor "$HAOS_INSTALL_VERSION" "$remoto"; then
        ha_info "$(msg novidade_script "$remoto" "$HAOS_INSTALL_VERSION")"
    fi
    tag="$(curl -fsSL --max-time 3         "https://api.github.com/repos/home-assistant/operating-system/releases/latest" 2>/dev/null         | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" || true
    case "$tag" in
        ''|*[!0-9.]*) : ;;   # shape estranho: silêncio — a fonte é externa
        *) [ "$tag" != "$HAOS_REF_OS" ] && ver_menor "$HAOS_REF_OS" "$tag"             && ha_info "$(msg novidade_haos "$tag" "$HAOS_REF_OS")" ;;
    esac
    return 0
}

TEM_CABEADA=0
pre_voo() {
    ha_fase "$(msg preflight)"
    sonda

    # ── portões duros: impossibilidade de plataforma ──────────────────────────
    local os arch
    os="$(p_get host.os)"; arch="$(p_get host.arch)"
    [ "$os" = "Darwin" ]  || portao "$E_VALID" "$(msg so_macos "$os")"
    [ "$arch" = "arm64" ] || portao "$E_VALID" "$(msg so_apple_silicon "$arch")"
    ha_ok "$(msg maquina): $(p_get host.model) ${HA_G_SEP} $(p_get host.cpu) ${HA_G_SEP} macOS $(p_get host.macos)"

    if [ "$(p_get vbox.present)" != "1" ]; then
        # Conduz, não delega: baixa da Oracle, confere o hash e instala por
        # installer(8). Uma senha, no terminal, pedida pelo sudo.
        if [ "$OP_DRYRUN" = "1" ]; then
            portao "$E_DEP" "$(msg sem_vbox)"
        else
            local rc_vb=0
            ha_bar_suspende
            garantir_virtualbox || rc_vb=$?
            ha_bar_retoma
            if [ "$rc_vb" != "0" ] && [ "$rc_vb" != "100" ]; then
                exit "$E_DEP"
            fi
            sonda   # re-sonda: a máquina mudou
        fi
    fi
    if [ "$(p_get vbox.present)" = "1" ]; then
        local vv maj min
        vv="$(p_get vbox.version)"; maj="${vv%%.*}"; min="${vv#*.}"; min="${min%%.*}"
        if [ "${maj:-0}" -lt 7 ] || { [ "${maj:-0}" = "7" ] && [ "${min:-0}" -lt 1 ]; }; then
            portao "$E_DEP" "$(msg vbox_antigo "$vv")"
        else
            ha_ok "$(msg vbox_versao "$vv")"
        fi
    fi

    # python3: dependência REAL. Instalar app exige o comando WebSocket
    # supervisor/api, e bash não fala WebSocket. Descobrir isso na fase de apps,
    # depois da VM criada, seria descobrir tarde.
    if [ "$(p_get python3.present)" != "1" ]; then
        portao "$E_DEP" "$(msg sem_python) $(msg sem_python_como)"
    else
        ha_ok "$(msg python3_versao "$(python3 -V 2>&1 | awk '{print $2}')")"
    fi

    local livre; livre="$(p_get disk.available_mib)"
    local minimo=12000
    if [ "${livre:-0}" -ge "$minimo" ]; then ha_ok "$(msg disco): ${livre} MiB"
    else portao "$E_VALID" "$(msg disco_curto "$(p_get disk.path)" "$livre" "$minimo")"; fi

    # ── portões suaves: avisam, não abortam ──────────────────────────────────
    local n i
    n="$(p_get net.count)"; [ "${n:-0}" -ge 1 ] || portao "$E_VALID" "$(msg sem_interface)"
    i=1
    while [ "$i" -le "${n:-0}" ]; do
        [ "$(p_get "net.$i.wired")" = "1" ] && TEM_CABEADA=1
        i=$(( i + 1 ))
    done
    if [ "$TEM_CABEADA" = "1" ]; then
        ha_ok "$(msg rede): $(p_get net.1.port) ($(msg cabeada))"
    else
        # Aviso, NÃO portão. A doc oficial do HA aceita escolher o adaptador
        # Wi-Fi, e nenhum MacBook tem porta Ethernet desde 2016: abortar aqui
        # recusaria a maior parte dos Macs. A prova é empírica, na F5.
        ha_warn "$(msg aviso_wifi)"
    fi
    checar_novidades
}

# =============================================================================
# F2 — SELEÇÃO
# =============================================================================
SEL_DEGRAU=""; SEL_EXTRAS=""; SEL_VM=""; SEL_ITENS=""

perfil_valido() {
    local r
    for r in "${HAOS_PROFILE_DB[@]}"; do [ "${r%%|*}" = "$1" ] && return 0; done
    return 1
}
degrau_categorias() {
    local r id rot cats
    for r in "${HAOS_PROFILE_DB[@]}"; do
        IFS='|' read -r id rot cats <<< "$r"
        [ "$id" = "$1" ] && { printf '%s' "$cats"; return 0; }
    done
    return 1
}

# vm_recomendado deriva do TOTAL, não do disponível: o disponível varia entre
# execuções na mesma máquina, e derivar dele faria o perfil "Recomendado" ficar
# menor que o "Equilibrado" — o rótulo mentiria. Piso no equilibrado.
vm_derivado_ram() {
    local total metade=4096
    total="$(p_get mem.total_mib)"
    [ "${total:-0}" -gt 0 ] && metade=$(( total / 2 ))
    [ "$metade" -gt 8192 ] && metade=8192
    [ "$metade" -lt 4096 ] && metade=4096
    printf '%s' "$metade"
}
vm_derivado_cpu() {
    local p; p="$(p_get cpu.performance)"
    [ "${p:-0}" -lt 2 ] && p=2
    [ "${p:-2}" -gt 4 ] && p=4
    printf '%s' "$p"
}

# ── gum: o seletor rico, carregado em TEMP com SHA-256 verificado ────────────
# Porta do mac-env-setup: baixa o binário oficial do charmbracelet para um
# diretório temporário (some no limpar()), confere contra o checksums.txt da
# release e NUNCA instala nada permanente. Sem TTY, sem rede ou com
# HAOS_USE_GUM=0, o cardápio simples numerado assume — mesma degradação de lá.
HAOS_GUM_VERSION="${HAOS_GUM_VERSION:-0.17.0}"
GUM=""
GUM_MOTIVO=""

gum_tem_tty() {
    [ -z "${NO_COLOR:-}" ] || return 1
    [ "${TERM:-dumb}" != "dumb" ] || return 1
    tem_tty
}

gum_bootstrap() {
    GUM=""; GUM_MOTIVO=""
    case "${HAOS_USE_GUM:-auto}" in 0|off|no) GUM_MOTIVO="HAOS_USE_GUM=0"; return 1 ;; esac
    gum_tem_tty || { GUM_MOTIVO="sem TTY"; return 1; }
    if command -v gum >/dev/null 2>&1; then GUM="gum"; return 0; fi
    command -v tar >/dev/null 2>&1 || { GUM_MOTIVO="sem tar"; return 1; }
    local os arch base asset d
    case "$(uname -s)" in Darwin) os=Darwin ;; *) GUM_MOTIVO="so macOS"; return 1 ;; esac
    case "$(uname -m)" in arm64) arch=arm64 ;; x86_64) arch=x86_64 ;; *) GUM_MOTIVO="arch"; return 1 ;; esac
    asset="gum_${HAOS_GUM_VERSION}_${os}_${arch}.tar.gz"
    base="https://github.com/charmbracelet/gum/releases/download/v${HAOS_GUM_VERSION}"
    local cache_gum="$HOME/Library/Caches/haos-mac-mini/gum-${HAOS_GUM_VERSION}"
    if [ -x "$cache_gum/gum" ]; then GUM="$cache_gum/gum"; return 0; fi
    d="$(mktempdir)"
    garantir_log
    curl -fsSL --proto '=https' --tlsv1.2 --retry 2 -o "$d/$asset" "$base/$asset" 2>>"$LOG_FILE"         || { GUM_MOTIVO="download"; return 1; }
    curl -fsSL --proto '=https' --tlsv1.2 -o "$d/checksums.txt" "$base/checksums.txt" 2>>"$LOG_FILE"         || { GUM_MOTIVO="checksum indisponível"; return 1; }
    ( cd "$d" && shasum -a 256 --ignore-missing -c checksums.txt ) >>"$LOG_FILE" 2>&1         || { GUM_MOTIVO="checksum divergiu"; return 1; }
    tar -xzf "$d/$asset" -C "$d" 2>>"$LOG_FILE" || { GUM_MOTIVO="extração"; return 1; }
    GUM="$(find "$d" -type f -name gum 2>/dev/null | head -1)"
    if [ -z "$GUM" ] || [ ! -x "$GUM" ]; then GUM=""; GUM_MOTIVO="binário ausente"; return 1; fi
    # verificado uma vez, guardado por versão — reexecução não repaga o download
    if mkdir -p "$cache_gum" 2>/dev/null && cp "$GUM" "$cache_gum/gum" 2>/dev/null; then
        chmod +x "$cache_gum/gum" 2>/dev/null || true
        GUM="$cache_gum/gum"
    fi
    return 0
}

# Tema na paleta do Home Assistant — o mac-env usa o âmbar dele; aqui é o azul.
gum_tema() {
    [ -n "$GUM" ] || return 0
    export GUM_CHOOSE_CURSOR="❯ "
    export GUM_CHOOSE_CURSOR_FOREGROUND="#03A9F4"
    export GUM_CHOOSE_HEADER_FOREGROUND="#8892b0"
    export GUM_CHOOSE_SELECTED_FOREGROUND="#00E5FF"
    export GUM_CHOOSE_SELECTED_PREFIX="◆ "
    export GUM_CHOOSE_UNSELECTED_PREFIX="◇ "
    export GUM_CHOOSE_CURSOR_PREFIX="◇ "
    export GUM_CONFIRM_PROMPT_FOREGROUND="#03A9F4"
    export GUM_CONFIRM_SELECTED_BACKGROUND="#03A9F4"
    export GUM_CONFIRM_SELECTED_FOREGROUND="#0b0f14"
    export GUM_FILTER_INDICATOR="❯"
    export GUM_FILTER_INDICATOR_FOREGROUND="#03A9F4"
    export GUM_FILTER_MATCH_FOREGROUND="#00E5FF"
    export GUM_FILTER_SELECTED_PREFIX=" ◆ "
    export GUM_FILTER_SELECTED_PREFIX_FOREGROUND="#00E5FF"
    export GUM_FILTER_UNSELECTED_PREFIX=" ◇ "
    export GUM_FILTER_PLACEHOLDER_FOREGROUND="#5a6480"
    export GUM_FILTER_HEADER_FOREGROUND="#8892b0"
    export GUM_FILTER_PROMPT="/ "
    export GUM_FILTER_PROMPT_FOREGROUND="#03A9F4"
    return 0
}
gum_choose()  { "$GUM" choose  "$@" </dev/tty; }
gum_filter()  { "$GUM" filter  "$@" </dev/tty; }
gum_confirm() { "$GUM" confirm "$@" </dev/tty; }

# ── seletor rico: choose/filter, com busca e marcação por espaço ─────────────
# Personalizado é opção do MENU, no início — o desenho do mac-env: todos os
# componentes do catálogo num filtro com busca (digite filtra, espaço marca,
# enter confirma), com os padrões do Casa+ferramentas+casa_abhome
# pré-marcados. HACS nunca vem pré-marcado: opt-in é opt-in.
SEL_PERSO=0
seletor_personalizado() {
    local it iid icat irot iorigem islug ipadrao resto ops=() presel='' op sel linha novo='' extras=''
    for it in "${ITEM_DB[@]}"; do
        IFS='|' read -r iid icat irot iorigem islug ipadrao resto <<< "$it"
        op="$iid — $irot ($icat)"
        ops+=("$op")
        if [ "$ipadrao" = "1" ] && [ "$icat" != "extensoes" ]; then
            if [ -n "$presel" ]; then presel="$presel,$op"; else presel="$op"; fi
        fi
    done
    sel="$(gum_filter --no-limit --height 16 --header "$(msg sel_gum_itens)" \
        --placeholder "..." --selected "$presel" "${ops[@]}")" \
        || { ha_info "$(msg cancelado)"; exit "$E_CANCELADO"; }
    [ -n "$sel" ] || { ha_info "$(msg cancelado)"; exit "$E_CANCELADO"; }
    while IFS= read -r linha; do
        [ -n "$linha" ] || continue
        iid="${linha%% *}"
        novo="$novo $iid"
        icat="$(item_campo "$iid" 2)"
        if tem_na_lista "$icat" "${ORTOGONAL_DB[*]}" && ! tem_na_lista "$icat" "$extras"; then
            extras="$extras $icat"
        fi
    done <<EOF
$sel
EOF
    SEL_DEGRAU="haos_casa"
    SEL_EXTRAS="${extras# }"
    SEL_ITENS="${novo# }"
    SEL_PERSO=1
    return 0
}

seletor_gum() {
    local sel linha tem_ultima=0 resumo=''
    if carregar_selecao; then
        tem_ultima=1
        resumo="$LAST_DEGRAU"; [ -n "$LAST_EXTRAS" ] && resumo="$resumo + $LAST_EXTRAS"
    fi

    local op_r='' op_v op_c op_h op_p ops=()
    op_v="$(msg sel_gum_op_vanilla)"; op_c="$(msg sel_gum_op_conectado)"
    op_h="$(msg sel_gum_op_casa)";    op_p="$(msg sel_gum_op_perso)"
    if [ "$tem_ultima" = "1" ]; then
        op_r="$(msg sel_gum_op_repetir "$resumo")"
        ops+=("$op_r")
    fi
    ops+=("$op_h" "$op_c" "$op_v" "$op_p")
    sel="$(gum_choose --header "$(msg sel_gum_degrau)" "${ops[@]}")" \
        || { ha_info "$(msg cancelado)"; exit "$E_CANCELADO"; }
    case "$sel" in
        "$op_p") seletor_personalizado ;;
        "$op_v") SEL_DEGRAU="haos_vanilla" ;;
        "$op_c") SEL_DEGRAU="haos_conectado" ;;
        "$op_h") SEL_DEGRAU="haos_casa" ;;
        *)  SEL_DEGRAU="$LAST_DEGRAU"
            [ -n "$LAST_EXTRAS" ] && SEL_EXTRAS="$LAST_EXTRAS"
            [ -n "$LAST_VM" ] && OP_VM_PERFIL="${OP_VM_PERFIL:-$LAST_VM}"
            SEL_PERSO=2 ;;
    esac

    # Preset é preset: extras só são perguntados fora do Personalizado e fora
    # da repetição — o Personalizado já os derivou dos itens escolhidos.
    if [ "$SEL_PERSO" = "0" ]; then
        sel="$(gum_choose --no-limit --header "$(msg sel_gum_extras)" \
            "$(msg sel_gum_ex_a)" "$(msg sel_gum_ex_b)" "$(msg sel_gum_ex_c)")" || sel=""
        SEL_EXTRAS=""
        while IFS= read -r linha; do
            [ -n "$linha" ] && SEL_EXTRAS="$SEL_EXTRAS ${linha%% *}"
        done <<EOF
$sel
EOF
        SEL_EXTRAS="${SEL_EXTRAS# }"
    fi

    if [ -z "$OP_VM_PERFIL" ]; then
        sel="$(gum_choose --header "$(msg sel_gum_vm)" \
            "$(msg sel_gum_vm1)" "$(msg sel_gum_vm2)" \
            "$(msg sel_gum_vm3 "$(vm_derivado_ram)" "$(vm_derivado_cpu)")")" \
            || { ha_info "$(msg cancelado)"; exit "$E_CANCELADO"; }
        OP_VM_PERFIL="${sel%% *}"
    fi
    return 0
}



# ── o cardápio ───────────────────────────────────────────────────────────────
# Sem flags e com terminal, o instalador PERGUNTA — o norte de UX: o leigo
# responde no máximo degrau + senha. O desenho é o dos irmãos (AtlasFile
# af_read_line / mac-env flow_node→flow_done): o MENU e o prompt vão para a
# TELA, na calha; só a LEITURA vem de $TTY_DEV — nunca do stdin, que em
# curl | bash é o cano. $TTY_DEV é também a costura da bancada: apontado para
# um arquivo de respostas, o seletor roda de ponta a ponta sem terminal.
# Entrada inválida repete a pergunta; vazio assume o padrão entre colchetes.
# O fd 4 abre UMA vez no início do seletor: reabrir o TTY_DEV a cada pergunta
# faria um arquivo de respostas (a bancada) devolver sempre a primeira linha —
# um terminal entrega as linhas em sequência, e a bancada imita o terminal.
# A resposta sai em $RESP, NUNCA em stdout — a lição escrita no af_read_line
# do AtlasFile: chamada dentro de "$( )", o prompt impresso seria capturado
# junto com a resposta e a comparação nunca bateria (reproduzido aqui como
# laço infinito na bancada, 24/08).
RESP=''
ler_opcao() { # <prompt já traduzido> -> resposta em $RESP
    RESP=''
    ha_ask "$1"
    IFS= read -r -u 4 RESP || true
    printf '\n'
}

seletor_interativo() {
    exec 4< "$TTY_DEV" || return 1
    ha_bar_suspende
    local r tem_ultima=0 resumo=''
    if carregar_selecao; then
        tem_ultima=1
        resumo="$LAST_DEGRAU"
        [ -n "$LAST_EXTRAS" ] && resumo="$resumo + $LAST_EXTRAS"
    fi
    ha_info "$(msg sel_degrau_titulo)"
    [ "$tem_ultima" = "1" ] && ha_linha "$(msg sel_op_repetir "$resumo")"
    ha_linha "$(msg sel_op_vanilla)"
    ha_linha "$(msg sel_op_conectado)"
    ha_linha "$(msg sel_op_casa)"
    while :; do
        ler_opcao "$(msg sel_prompt_degrau)"; r="$RESP"
        case "${r:-3}" in
            0) [ "$tem_ultima" = "1" ] || { ha_warn "$(msg sel_invalida "$r")"; continue; }
               SEL_DEGRAU="$LAST_DEGRAU"
               [ -n "$LAST_EXTRAS" ] && SEL_EXTRAS="$LAST_EXTRAS"
               [ -n "$LAST_VM" ] && OP_VM_PERFIL="${OP_VM_PERFIL:-$LAST_VM}"
               exec 4<&-
               ha_bar_retoma
               return 0 ;;
            1) SEL_DEGRAU="haos_vanilla"; break ;;
            2) SEL_DEGRAU="haos_conectado"; break ;;
            3) SEL_DEGRAU="haos_casa"; break ;;
            *) ha_warn "$(msg sel_invalida "$r")" ;;
        esac
    done

    ha_info "$(msg sel_extras_titulo)"
    ha_linha "$(msg sel_op_ferramentas)"
    ha_linha "$(msg sel_op_abhome)"
    ha_linha "$(msg sel_op_hacs)"
    while :; do
        ler_opcao "$(msg sel_prompt_extras)"; r="$RESP"
        [ -z "$r" ] && break
        local tok ruim=0 escolhidos=''
        for tok in $(printf '%s' "$r" | tr ',;' '  '); do
            case "$tok" in
                a|ferramentas) escolhidos="$escolhidos ferramentas" ;;
                b|casa_abhome) escolhidos="$escolhidos casa_abhome" ;;
                c|extensoes)   escolhidos="$escolhidos extensoes" ;;
                *) ha_warn "$(msg sel_invalida "$tok")"; ruim=1; break ;;
            esac
        done
        [ "$ruim" = "1" ] && continue
        SEL_EXTRAS="${escolhidos# }"
        break
    done

    if [ -z "$OP_VM_PERFIL" ]; then
        ha_info "$(msg sel_vm_titulo)"
        ha_linha "$(msg sel_op_vm1)"
        ha_linha "$(msg sel_op_vm2)"
        ha_linha "$(msg sel_op_vm3 "$(vm_derivado_ram)" "$(vm_derivado_cpu)")"
        while :; do
            ler_opcao "$(msg sel_prompt_vm)"; r="$RESP"
            case "${r:-2}" in
                1) OP_VM_PERFIL="vm_minimo"; break ;;
                2) OP_VM_PERFIL="vm_equilibrado"; break ;;
                3) OP_VM_PERFIL="vm_recomendado"; break ;;
                *) ha_warn "$(msg sel_invalida "$r")" ;;
            esac
        done
    fi
    exec 4<&-
    ha_bar_retoma
    return 0
}

resolver_selecao() {
    ha_fase "$(msg selecao)"

    if [ "$OP_ALL" = "1" ]; then
        SEL_DEGRAU="haos_casa"; SEL_EXTRAS="ferramentas casa_abhome"
        # `extensoes` (HACS) fica FORA do --all de propósito: é código de fora
        # do canal oficial, e opt-in nominal é o certo para isso.
    elif [ "$OP_PERFIL" = "last" ]; then
        carregar_selecao || morrer "$E_USO" "$(msg last_sem_estado "$(haos_state_dir)/state")"
        ha_info "$(msg last_repetindo)"
        SEL_DEGRAU="$LAST_DEGRAU"
        [ -z "$OP_WITH" ] && [ -n "$LAST_EXTRAS" ] && SEL_EXTRAS="$LAST_EXTRAS"
        [ -z "$OP_VM_PERFIL" ] && [ -n "$LAST_VM" ] && OP_VM_PERFIL="$LAST_VM"
        [ "$OP_VM_NOME" = "HomeAssistant" ] && [ -n "$LAST_VM_NOME" ] && OP_VM_NOME="$LAST_VM_NOME"
        if [ "$LAST_PERSO" = "1" ] && [ -n "$LAST_ITENS" ]; then
            SEL_PERSO=1
            SEL_ITENS="$LAST_ITENS"
        fi
    elif [ -n "$OP_PERFIL" ]; then
        perfil_valido "$OP_PERFIL" || morrer "$E_USO" "perfil desconhecido: $OP_PERFIL"
        SEL_DEGRAU="$OP_PERFIL"
    elif { tem_tty || [ "$TTY_DEV" != "/dev/tty" ]; } && [ "$OP_NOINPUT" != "1" ]; then
        if [ "$TTY_DEV" = "/dev/tty" ] && gum_bootstrap; then
            gum_tema
            ha_info "$(msg gum_ok "$HAOS_GUM_VERSION")"
            seletor_gum
        else
            [ -n "$GUM_MOTIVO" ] && ha_info "$(msg gum_fallback "$GUM_MOTIVO")"
            seletor_interativo
        fi
    else
        ha_err "$(msg sem_tty_titulo)"
        printf '%s\n' "$(msg sem_tty_como)" >&2
        printf '  curl -fsSL %s | bash -s -- --profile haos_casa\n' "$HAOS_RAW_URL" >&2
        exit "$E_USO"
    fi

    [ -n "$OP_WITH" ] && SEL_EXTRAS="$(printf '%s' "$OP_WITH" | tr ',' ' ')"
    local e
    for e in $SEL_EXTRAS; do
        tem_na_lista "$e" "${ORTOGONAL_DB[*]}" || morrer "$E_USO" "extra desconhecido: $e"
    done

    SEL_VM="${OP_VM_PERFIL:-vm_equilibrado}"
    local r vid
    local achou=0
    for r in "${VM_PROFILE_DB[@]}"; do [ "${r%%|*}" = "$SEL_VM" ] && achou=1; done
    [ "$achou" = "1" ] || morrer "$E_USO" "perfil de VM desconhecido: $SEL_VM"

    # itens: os de padrao=1 das categorias escolhidas — a menos que o modo
    # Personalizado já os tenha escolhido um a um, com busca.
    [ "${SEL_PERSO:-0}" = "1" ] && { ha_ok "$(msg degrau): Personalizado ${HA_G_SEP} $(msg itens): $(printf '%s' "$SEL_ITENS" | wc -w | tr -d ' ')"; return 0; }
    local cats; cats="$(degrau_categorias "$SEL_DEGRAU") $SEL_EXTRAS"
    local it iid icat irot iorigem islug ipadrao
    for it in "${ITEM_DB[@]}"; do
        IFS='|' read -r iid icat irot iorigem islug ipadrao _ <<< "$it"
        tem_na_lista "$icat" "$cats" || continue
        [ "$ipadrao" = "1" ] && SEL_ITENS="$SEL_ITENS $iid"
    done
    ha_ok "$(msg degrau): $(cat_rotulo "${SEL_DEGRAU#haos_}") ${HA_G_SEP} $(msg ortogonais): ${SEL_EXTRAS:--}"
}

plano() {
    ha_fase "$(msg plano)"
    local ram cpu r id rot rm cp orig
    for r in "${VM_PROFILE_DB[@]}"; do
        IFS='|' read -r id rot rm cp orig <<< "$r"
        [ "$id" = "$SEL_VM" ] || continue
        if [ "$rm" = "derivado" ]; then ram="$(vm_derivado_ram)"; cpu="$(vm_derivado_cpu)"
        else ram="$rm"; cpu="$cp"; fi
    done
    # a fase da VM consome os números resolvidos aqui — o plano é o contrato
    VM_RAM_MIB="$ram"; VM_CPU_N="$cpu"

    ha_linha "$(printf '%-14s %s' "$(msg perfil_vm):" "$SEL_VM ${HA_G_DASH} ${ram} MiB RAM ${HA_G_SEP} ${cpu} vCPU")"
    ha_linha "$(printf '%-14s %s' "VM:" "$OP_VM_NOME")"
    ha_linha "$(printf '%-14s %s' "$(msg degrau):" "$SEL_DEGRAU")"
    [ -n "$SEL_EXTRAS" ] && ha_linha "$(printf '%-14s %s' "$(msg ortogonais):" "$SEL_EXTRAS")"

    local disp; disp="$(p_get mem.available_mib)"
    if [ "${disp:-0}" -lt "${ram:-0}" ]; then ha_warn "$(msg aviso_ram "$disp" "$ram")"; fi

    # O piso vem de qualquer jeito — dizer só "0 itens" seria enganoso.
    ha_linha ""
    ha_linha "$(msg piso_sempre "$(( ${#DEFAULT_CONFIG_DB[@]} + ${#HAOS_INTRINSIC_DB[@]} + ${#ONBOARDING_DB[@]} ))")"

    local n=0 it
    ha_linha ""
    for it in $SEL_ITENS; do
        n=$(( n + 1 ))
        ha_linha "$(printf '  %-26s %s' "$it" "$(item_campo "$it" 3)")"
    done
    if [ "$n" = "0" ]; then
        ha_linha "  $(msg nada_alem_do_piso)"
    else
        ha_linha ""
        ha_linha "$n $(msg itens)"
    fi
}

# ── relatório final ──────────────────────────────────────────────────────────
# O fechamento do mac-env: o que aconteceu, em números e artefatos, e SÓ os
# próximos passos que se aplicam. A execução que instalou VirtualBox e imagem
# termina em placar — não num "não implementado" com cara de erro.
fmt_seg() { local t="$1"; if [ "$t" -ge 60 ]; then printf '%dm%02ds' $((t/60)) $((t%60)); else printf '%ds' "$t"; fi; }

relatorio_final() {
    local total=$(( SECONDS - ${MAIN_T0:-0} ))
    ha_bar_limpa
    printf '%s\n' "$HA_GUT"
    if [[ "${HAOS_UI_UTF8:-0}" == 1 ]]; then printf '%s' '╰'; else printf '%s' '+'; fi
    printf '%s\n' "$(ha_gradient "$(printf '%*s' 76 '' | tr ' ' "$HA_G_REGUA")")"
    printf '\n'
    ha_shimmer "  $(msg rel_titulo) ${HA_G_SEP} $(msg rel_tempo "$(fmt_seg "$total")")"

    local corpo
    corpo="$(msg rel_instalado)
"
    command -v VBoxManage >/dev/null 2>&1 \
        && corpo="${corpo}  $HA_G_OK $(msg rel_i_vbox "$(VBoxManage --version 2>/dev/null | tr -d '\r')")
"
    [ -n "${HAOS_VDI:-}" ] && [ -f "${HAOS_VDI:-/nonexistent}" ] \
        && corpo="${corpo}  $HA_G_OK $(msg rel_i_vdi "$HAOS_VDI")
"
    case "$(manifest_get "$(vm_manifest)" vm_registrada)" in
        created|preexisting) corpo="${corpo}  $HA_G_OK $(msg rel_i_vm "$OP_VM_NOME")
" ;;
    esac
    corpo="${corpo}  $HA_G_OK $(msg rel_i_sel)"
    if [ -n "${GUM:-}" ]; then
        "$GUM" style --border rounded --border-foreground "#03A9F4" --padding "0 2" \
            "$corpo" 2>/dev/null || printf '%s\n' "$corpo"
    else
        printf '%s\n' "$corpo"
    fi
    printf '\n'
    if [ -n "${VM_URL:-}" ]; then
        # O NORTE: o endereço REAL na tela — e o navegador aberto.
        ha_shimmer "  $(msg rel_url "$VM_URL")"
        ha_wrap "  $HA_G_INFO " "    " 4 "$(msg rel_url_aviso)"
        if [ -n "${SMB_SENHA:-}" ] && [ -n "${VM_IP:-}" ]; then
            printf '  %s %s\n' "$HA_G_INFO" "$(msg rel_samba "$VM_IP" "$SMB_SENHA")"
        fi
        [ -n "${CHAVE_SSH_PUB:-}" ] && printf '  %s %s\n' "$HA_G_INFO" "$(msg rel_ssh_chave)"
        local n_flows
        n_flows="$(printf '%s' "${FLOWS_PENDENTES:-}" | grep -c . || true)"
        [ "${n_flows:-0}" -gt 0 ] && printf '  %s %s\n' "$HA_G_INFO" "$(msg rel_flows "$n_flows")"
        case " ${SEL_ITENS:-} " in *" hacs "*) printf '  %s %s\n' "$HA_G_INFO" "$(msg rel_hacs_prox)" ;; esac
        if [ "$OP_NO_OPEN" != "1" ] && tem_tty && command -v open >/dev/null 2>&1; then
            printf '  %s %s\n' "$HA_G_INFO" "$(msg rel_abrindo)"
            open "$VM_URL" 2>/dev/null || true
        fi
    else
        ha_wrap "  $HA_G_WARN " "    " 4 "$(msg rel_falta "$HAOS_INSTALL_VERSION")"
    fi
    printf '\n  %s %s\n' "$HA_G_INFO" "$(msg prox_relatorio "$(haos_state_dir)/last-run.log")"
    printf '\n'
    return 0
}


# =============================================================================
# MAIN
# =============================================================================
main() {
    ler_args "$@"

    # `--list | head` fecha o cano; SIGPIPE com pipefail viraria erro do script
    [ "$OP_LIST" = "1" ] && { trap - PIPE; listar 2>/dev/null || true; exit 0; }

    # Modos de manutenção: read-only ou com a própria prestação de contas —
    # nenhum passa pelo caminho de instalação nem grava last-run.
    case "$OP_MODO" in
        doctor)      rodar_doctor;      exit $? ;;
        uninstall)   rodar_uninstall;   exit $? ;;
        self-update) rodar_self_update; exit $? ;;
    esac

    # A partir daqui a execução conta como execução: o limpar() espelha o
    # last-run mesmo numa morte no meio — exceto em dry-run, que não escreve
    # NADA (cerca de snapshot no portão).
    MAIN_INICIADO=1
    MAIN_T0=$SECONDS
    if [ "$OP_DRYRUN" = "1" ]; then HA_BAR_TOTAL=3; else HA_BAR_TOTAL=10; fi

    # O logo só aparece quando há terminal e o usuário não pediu silêncio.
    # Em log, CI ou --quiet, um cabeçalho de uma linha. A animação nunca é
    # informação: tudo que ela mostra também está no texto.
    if [ "$OP_QUIET" != "1" ]; then
        if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
            ha_banner "Home Assistant OS" "$(msg subtitulo) ${HA_G_SEP} v${HAOS_INSTALL_VERSION}"
        else
            printf '\n%s v%s\n' "$(msg cabecalho)" "$HAOS_INSTALL_VERSION"
        fi
    fi

    pre_voo
    resolver_selecao
    plano

    if [ "$OP_DRYRUN" = "1" ]; then
        printf '\n'
        if [ "$PORTOES_ABERTOS" -gt 0 ]; then
            ha_warn "$(msg portoes_pendentes "$PORTOES_ABERTOS")"
        fi
        ha_info "$(msg nada_escrito)"
        exit 0
    fi

    if [ "$OP_NOINPUT" != "1" ]; then
        if [ -n "$GUM" ]; then
            gum_confirm "$(msg sel_gum_confirmar)"                 --affirmative "$(msg sel_gum_sim)" --negative "$(msg sel_gum_nao)"                 || { ha_info "$(msg cancelado)"; exit "$E_CANCELADO"; }
        else
            perguntar "$(msg confirmar)" || { ha_info "$(msg cancelado)"; exit "$E_CANCELADO"; }
        fi
    fi
    salvar_selecao

    local rc_img=0
    fase_imagem || rc_img=$?
    [ "$rc_img" = "0" ] || [ "$rc_img" = "100" ] || exit "$E_VALID"

    local rc_vm=0
    fase_vm || rc_vm=$?
    [ "$rc_vm" = "0" ] || [ "$rc_vm" = "100" ] || exit "$E_VALID"

    local rc_boot=0
    fase_boot || rc_boot=$?
    [ "$rc_boot" = "0" ] || [ "$rc_boot" = "100" ] || exit "$E_VALID"

    local rc_conta=0
    fase_conta || rc_conta=$?
    [ "$rc_conta" = "0" ] || [ "$rc_conta" = "100" ] || exit "$E_VALID"

    local rc_apps=0
    fase_apps || rc_apps=$?
    [ "$rc_apps" = "0" ] || [ "$rc_apps" = "100" ] || exit "$E_VALID"

    local rc_int=0
    fase_integracoes || rc_int=$?
    [ "$rc_int" = "0" ] || [ "$rc_int" = "100" ] || exit "$E_VALID"

    local rc_arq=0
    fase_arquivos || rc_arq=$?
    [ "$rc_arq" = "0" ] || [ "$rc_arq" = "100" ] || exit "$E_VALID"

    relatorio_final
}

# ── guarda de biblioteca ─────────────────────────────────────────────────────
# `HAOS_INSTALL_LIB=1 source haos-install.sh` para AQUI: a bancada de teste
# alcança as funções sem executar nada. O `exit` de fallback existe porque sob
# `curl | bash` não há função de onde retornar. O trap vem DEPOIS da guarda —
# um trap de EXIT instalado no source vazaria para o shell da bancada (B-7).
MAIN_INICIADO=0
if [ -n "${HAOS_INSTALL_LIB:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

trap limpar EXIT INT TERM
main "$@"
