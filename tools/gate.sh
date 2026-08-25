#!/usr/bin/env bash
# =============================================================================
# gate.sh — o portão de qualidade. UM só, rodado igual localmente e no CI.
#
# Existe porque gate local e gate de CI que divergem não são gate: são duas
# opiniões. Aconteceu em 23/08 — shellcheck 0.11 local passava e 0.10 do CI
# reprovava o mesmo arquivo, três vezes seguidas. A versão agora é fixada aqui,
# e o CI chama este script em vez de repetir os comandos.
#
#   ./tools/gate.sh            tudo
#   ./tools/gate.sh --rapido   pula o que baixa da rede
#
# Exit: 0 tudo passou · 1 alguma checagem falhou
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$RAIZ" || exit 1

SHELLCHECK_VERSION="v0.10.0"
RAPIDO=0
[ "${1:-}" = "--rapido" ] && RAPIDO=1

FALHAS=0
titulo() { printf '\n\033[1m── %s\033[0m\n' "$1"; }
ok()     { printf '  [OK]    %s\n' "$1"; }
falha()  { printf '  [ERRO]  %s\n' "$1" >&2; FALHAS=$((FALHAS+1)); }

# ── shellcheck, na versão fixada ─────────────────────────────────────────────
# SC2034        IFS='|' read descompacta campos que nem sempre se usam
# SC1090/SC1091 source de caminho computado
# SC2317/SC2329 corpo de trap e funções de fase ainda não chamadas — o código
#               do aviso mudou entre versões do shellcheck
EXCLUI="SC2034,SC1090,SC1091,SC2317,SC2329"

acha_shellcheck() {
    local cache="${TMPDIR:-/tmp}/shellcheck-$SHELLCHECK_VERSION"
    if [ -x "$cache/shellcheck" ]; then printf '%s' "$cache/shellcheck"; return 0; fi
    local os arch
    case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) return 1 ;; esac
    case "$(uname -m)" in arm64|aarch64) arch=aarch64 ;; *) arch=x86_64 ;; esac
    mkdir -p "$cache" || return 1
    curl -fsSL --proto '=https' --tlsv1.2 \
        "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.${os}.${arch}.tar.xz" \
        | tar -xJf - --strip-components=1 -C "$cache" "shellcheck-${SHELLCHECK_VERSION}/shellcheck" 2>/dev/null || return 1
    chmod +x "$cache/shellcheck" 2>/dev/null || return 1
    printf '%s' "$cache/shellcheck"
}

titulo "shellcheck $SHELLCHECK_VERSION"
if [ "$RAPIDO" = "1" ] && ! [ -x "${TMPDIR:-/tmp}/shellcheck-$SHELLCHECK_VERSION/shellcheck" ]; then
    ok "pulado (--rapido, e não está em cache)"
elif SC="$(acha_shellcheck)"; then
    if "$SC" -e "$EXCLUI" haos-install.sh verify.sh tools/*.sh lib/*.sh extras/*.sh; then
        ok "sem achados"
    else
        falha "shellcheck reprovou"
    fi
else
    falha "não consegui obter o shellcheck $SHELLCHECK_VERSION"
fi

# ── sintaxe ──────────────────────────────────────────────────────────────────
titulo "sintaxe"
erros=0
for f in haos-install.sh verify.sh tools/*.sh lib/*.sh extras/*.sh catalog/*.bash; do
    bash -n "$f" || { falha "bash -n: $f"; erros=1; }
done
[ "$erros" = "0" ] && ok "bash -n em todos os shell"
for f in contract/*.py lib/*.py tools/*.py; do
    [ -f "$f" ] || continue
    python3 -m py_compile "$f" 2>/dev/null || falha "py_compile: $f"
done
ok "py_compile nos python"

# ── catálogo ─────────────────────────────────────────────────────────────────
titulo "catálogo"
if ./verify.sh --quiet; then ok "verify.sh"; else falha "verify.sh"; fi
if ./tools/embed.sh --check >/dev/null 2>&1; then ok "cópia embutida não derivou"
else falha "cópia embutida diverge — rode ./tools/embed.sh"; fi

# ── bash 3.2, que é o do macOS ───────────────────────────────────────────────
titulo "bash 3.2 e distribuição"
if [ -x /bin/bash ] && /bin/bash --version | head -1 | grep -q 'version 3'; then
    if /bin/bash -c 'source catalog/catalog.bash; [ ${#ITEM_DB[@]} -gt 0 ]'; then
        ok "catálogo carrega em $(/bin/bash --version | head -1 | sed 's/.*version //;s/ .*//')"
    else
        falha "catálogo não carrega em bash 3.2"
    fi
else
    ok "bash 3.2 não disponível aqui (o CI cobre no runner macOS)"
fi

# O produto é distribuído por `curl | bash`. Vindo de stdin o array BASH_SOURCE
# é VAZIO; com set -u, qualquer ${BASH_SOURCE[0]} sem default aborta na linha 2.
# bash -n e shellcheck NÃO pegam isso.
# shellcheck disable=SC2002
# O `cat |` é o ponto: reproduz literalmente o `curl | bash`. Trocar por
# redirecionamento testaria outra coisa.
if cat haos-install.sh | "${BASH:-/bin/bash}" -s -- --version >/dev/null 2>&1; then
    ok "roda por stdin (o caminho do curl | bash)"
else
    falha "NÃO roda por stdin — é o modo de distribuição"
fi

# ── contaminação de biblioteca ───────────────────────────────────────────────
# trap é global do shell: um trap no topo de uma lib apaga o cleanup do
# chamador, em silêncio, levando junto o desfazer de fase.
titulo "contaminação de biblioteca"
if /bin/bash -c '
    cleanup() { :; }; trap cleanup EXIT
    a="$(trap -p EXIT)"
    for l in lib/*.sh; do source "$l" >/dev/null 2>&1 || true; done
    [ "$a" = "$(trap -p EXIT)" ]'; then
    ok "nenhuma lib mexeu no trap EXIT"
else
    falha "uma lib trocou o trap EXIT"
fi

# Mesma disciplina para as OPÇÕES do shell. `set -uo pipefail` numa lib só liga
# o que o instalador já tem, então hoje não contamina — mas um `set +e` futuro
# desligaria o errexit do chamador em silêncio, e ninguém veria.
if /bin/bash -c '
    set -Eeuo pipefail
    a="$-|$(set -o | awk "/errtrace|pipefail/{printf \"%s=%s \",\$1,\$2}")"
    for l in lib/*.sh; do source "$l" >/dev/null 2>&1 || true; done
    b="$-|$(set -o | awk "/errtrace|pipefail/{printf \"%s=%s \",\$1,\$2}")"
    [ "$a" = "$b" ]'; then
    ok "nenhuma lib mexeu nas opções do shell"
else
    falha "uma lib mudou as opções do shell do chamador"
fi

# A camada visual tem de degradar sob locale C, não cuspir UTF-8 partido.
# Medido em 23/08: por SSH num Mac mini, LC_CTYPE=C fazia o bash contar BYTES e
# a mesma linha de arte medir 118 em vez de 42.
# A cerca exercita as FUNÇÕES DE FASE, não só o banner — achado B-3 da banca:
# a primeira versão só olhava ha_banner, e ha_ok/ha_warn/ha_err passariam
# verdes emitindo ✔▲✖ crus na máquina que o produto mais visita por SSH.
titulo "locale"
saida_c="$(LC_ALL=C LANG=C /bin/bash -c '
    source lib/haos-ui.sh >/dev/null 2>&1
    ha_banner "T" "S" 2>/dev/null
    ha_phase "Fase de teste"
    ha_ok "linha ok"; ha_info "linha info"; ha_warn "linha warn"
    ha_err "linha err" 2>&1; ha_skip "linha skip"
    ha_bar 3 3 "barra"
    ( sleep 0.1 ) & ha_spin "girando" $!
    ha_wrap "  - " "    " 4 "um caminho comprido /Users/alguem/VirtualBox VMs/HomeAssistant/haos.vdi para quebrar"
    ' | LC_ALL=C tr -d '[:print:][:space:]' | wc -c | tr -d ' ')"
if [ "${saida_c:-1}" = "0" ]; then
    ok "sob LC_ALL=C banner, fases, barra, spinner e wrap são ASCII puro"
else
    falha "sob LC_ALL=C a camada visual emitiu $saida_c byte(s) não imprimível(is)"
fi

# E o INSTALADOR inteiro, pelo cano, sob locale C: as mensagens en (as que o
# locale C seleciona) têm de ser ASCII puro — separador de UI inclusive.
# shellcheck disable=SC2002
saida_c="$(cat haos-install.sh | LC_ALL=C LANG=C "${BASH:-/bin/bash}" -s -- \
    --dry-run --profile haos_casa --no-input 2>&1 \
    | LC_ALL=C tr -d '\0-\177' | wc -c | tr -d ' ')"
if [ "${saida_c:-1}" = "0" ]; then
    ok "dry-run sob LC_ALL=C é ASCII puro de ponta a ponta"
else
    falha "dry-run sob LC_ALL=C emitiu $saida_c byte(s) não-ASCII"
fi

# ── help honesto ─────────────────────────────────────────────────────────────
# Cada flag PUBLICADA no --help é EXECUTADA (forma do call-site, não grep de
# texto): a que responder "não implementado" ou "opção desconhecida" reprova.
# É a cerca que teria pego o help prometendo --doctor/--uninstall/--resume
# enquanto todos caíam em morrer() — achado B-4 da banca.
titulo "help honesto"
# shellcheck disable=SC2002  # o `cat |` reproduz o curl | bash de propósito
flags_help="$(cat haos-install.sh | "${BASH:-/bin/bash}" -s -- --help 2>/dev/null \
    | grep -oE '^\s+(-[a-zA-Z], )?--[a-z-]+' | grep -oE '\-\-[a-z-]+' | sort -u)"
mentira=""
for f in $flags_help; do
    case "$f" in
        --help)    args="--help" ;;
        --version) args="--version" ;;
        --list)    args="--list" ;;
        --profile)    args="--profile haos_casa --dry-run --no-input" ;;
        --with)       args="--with ferramentas --profile haos_casa --dry-run --no-input" ;;
        --vm-profile) args="--vm-profile vm_minimo --profile haos_casa --dry-run --no-input" ;;
        --vm-name)    args="--vm-name Teste --profile haos_casa --dry-run --no-input" ;;
        --image)      args="--image /dev/null --profile haos_casa --dry-run --no-input" ;;
        --doctor)     args="--doctor" ;;
        --uninstall)  args="--uninstall --dry-run" ;;
        --confirm)    args="--uninstall --dry-run --confirm=HomeAssistant" ;;
        --self-update) args="--self-update" ;;
        *)            args="$f --profile haos_casa --dry-run --no-input" ;;
    esac
    # shellcheck disable=SC2086,SC2002
    saida="$(cat haos-install.sh | "${BASH:-/bin/bash}" -s -- $args 2>&1)" || true
    if printf '%s' "$saida" | grep -qE 'não estão implementadas|not implemented yet|opção desconhecida|unknown option'; then
        mentira="$mentira $f"
    fi
done
if [ -z "$mentira" ]; then
    ok "toda flag do --help executa de verdade ($(printf '%s\n' "$flags_help" | wc -l | tr -d ' ') flags)"
else
    falha "flags publicadas no help que não funcionam:$mentira"
fi

# ── enumerados do help ───────────────────────────────────────────────────────
# Cada valor enumerado nas linhas --profile/--vm-profile/--with do --help é
# executado contra o parser real. Foi assim que `last` ficou dois commits
# prometido e morto ("perfil desconhecido") sem ninguém ver — achado 5.
titulo "enumerados do help"
sb_enum="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-en.XXXXXX")"
mkdir -p "$sb_enum/.config/haos-mac-mini"
printf 'degrau=haos_casa\nextras=\nvm=vm_equilibrado\nvm_nome=HomeAssistant\n' \
    > "$sb_enum/.config/haos-mac-mini/state"
# shellcheck disable=SC2002  # o `cat |` reproduz o curl | bash de propósito
ajuda="$(cat haos-install.sh | "${BASH:-/bin/bash}" -s -- --help 2>/dev/null)"
tokens_profile="$(printf '%s\n' "$ajuda" | grep -A1 -- '--profile <id>' | grep -oE 'haos_[a-z]+|last' | sort -u)"
tokens_vm="$(printf '%s\n' "$ajuda" | grep -- '--vm-profile' | grep -oE 'vm_[a-z]+' | sort -u)"
tokens_with="$(printf '%s\n' "$ajuda" | grep -- '--with ' | grep -oE 'ferramentas|casa_abhome|extensoes' | sort -u)"
enum_ruim=""
for t in $tokens_profile; do
    # shellcheck disable=SC2002
    out="$(cat haos-install.sh | HOME="$sb_enum" "${BASH:-/bin/bash}" -s -- --dry-run --no-input --profile "$t" 2>&1)" || true
    printf '%s' "$out" | grep -qE 'desconhecido|unknown' && enum_ruim="$enum_ruim --profile=$t"
done
for t in $tokens_vm; do
    # shellcheck disable=SC2002
    out="$(cat haos-install.sh | HOME="$sb_enum" "${BASH:-/bin/bash}" -s -- --dry-run --no-input --profile haos_casa --vm-profile "$t" 2>&1)" || true
    printf '%s' "$out" | grep -qE 'desconhecido|unknown' && enum_ruim="$enum_ruim --vm-profile=$t"
done
for t in $tokens_with; do
    # shellcheck disable=SC2002
    out="$(cat haos-install.sh | HOME="$sb_enum" "${BASH:-/bin/bash}" -s -- --dry-run --no-input --profile haos_casa --with "$t" 2>&1)" || true
    printf '%s' "$out" | grep -qE 'desconhecido|unknown' && enum_ruim="$enum_ruim --with=$t"
done
rm -rf "$sb_enum"
n_enum="$(printf '%s %s %s\n' "$tokens_profile" "$tokens_vm" "$tokens_with" | wc -w | tr -d ' ')"
if [ -z "$enum_ruim" ]; then
    ok "todo valor enumerado no --help é aceito pelo parser real ($n_enum valores)"
else
    falha "enumerados do help recusados pelo parser:$enum_ruim"
fi

# ── isca no diretório corrente ───────────────────────────────────────────────
# O zip local do usuário é candidato LEGÍTIMO (decisão da banca: --image soma,
# não substitui). O que a cerca prova é o outro lado: arquivo com o NOME certo
# e conteúdo errado é DESCARTADO — nunca descompactado — e a fase falha limpa
# quando também não há rede (URL inválida), sem escrever .vdi nenhum.
titulo "isca no cwd"
sb_isca="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-isca.XXXXXX")"
printf 'lixo' > "$sb_isca/haos_generic-aarch64-18.2.vdi.zip"
# shellcheck disable=SC2016  # a interpolação de $RAIZ é feita AQUI, de propósito
saida_isca="$(cd "$sb_isca" && HOME="$sb_isca" HAOS_INSTALL_LIB=1 "${BASH:-/bin/bash}" -c '
    source "'"$RAIZ"'/haos-install.sh"
    HAOS_IMAGE_DB=("18.2|https://invalido.invalido/haos.zip|0000000000000000000000000000000000000000000000000000000000000000|397964849")
    OP_DRYRUN=0
    rc=0; fase_imagem >/dev/null 2>&1 || rc=$?
    printf "rc=%s vdi=%s" "$rc" "$(find "$HOME/VirtualBox VMs" -name "*.vdi" 2>/dev/null | wc -l | tr -d " ")"')"
rm -rf "$sb_isca"
if [ "$saida_isca" = "rc=1 vdi=0" ]; then
    ok "isca com nome certo e conteúdo errado: descartada, nada extraído (rc=1)"
else
    falha "isca no cwd: esperado 'rc=1 vdi=0', obtido '$saida_isca'"
fi

# ── F1 executa de ponta a ponta ──────────────────────────────────────────────
# A lição mais cara do primeiro teste em campo: a cauda da F1 (montar o DMG,
# achar o .pkg, instalar, desmontar) nunca tinha RODADO — e caiu no primeiro
# usuário real porque `hdiutil attach -quiet` suprime a listagem que o parse
# lia. Esta cerca roda a F1 INTEIRA com um DMG sintético e hdiutil DE VERDADE;
# só rede (curl), sudo e VBoxManage são dublados por função.
titulo "F1 de ponta a ponta (hdiutil real)"
sb_f1="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-f1.XXXXXX")"
mkdir -p "$sb_f1/vol" "$sb_f1/bin"
touch "$sb_f1/vol/VirtualBox.pkg"
if hdiutil create -quiet -srcfolder "$sb_f1/vol" -volname HAOSGateVBox "$sb_f1/fake.dmg" >/dev/null 2>&1; then
    # shellcheck disable=SC2016  # o script filho expande $SB sozinho, de propósito
    saida_f1="$(HAOS_INSTALL_LIB=1 SB="$sb_f1" "${BASH:-/bin/bash}" -c '
        source haos-install.sh
        HOME="$SB"; PATH="$SB/bin:$PATH"
        OP_INSTALL_DEPS=1; OP_VERBOSE=0
        sha="$(shasum -a 256 "$SB/fake.dmg" | awk "{print \$1}")"
        printf "%s *%s\n" "$sha" "$VBOX_DMG" > "$SB/SHA256SUMS"
        curl() { # dublê: entrega SHA256SUMS e o DMG sintético
            local a out="" prev=""
            for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
            case "$a" in
                *SHA256SUMS) cp "$SB/SHA256SUMS" "$out" ;;
                *.dmg)       cp "$SB/fake.dmg" "$out" ;;
                *) return 22 ;;
            esac
        }
        sudo() { # dublê: -n/-v ok; "installer" cria o VBoxManage no PATH
            case "$1" in
                -n|-v) return 0 ;;
                installer)
                    printf "#!/bin/sh\necho 7.2.16\n" > "$SB/bin/VBoxManage"
                    chmod +x "$SB/bin/VBoxManage"
                    return 0 ;;
                *) return 0 ;;
            esac
        }
        rc=0; garantir_virtualbox >/dev/null 2>&1 || rc=$?
        vbox_st="$(manifest_get "$(host_manifest)" vbox)"
        montado=0; [ -d /Volumes/HAOSGateVBox ] && montado=1
        cacheado=0; [ -f "$SB/Library/Caches/haos-mac-mini/$VBOX_DMG" ] && cacheado=1
        printf "rc=%s vbox=%s montado=%s cache=%s" "$rc" "$vbox_st" "$montado" "$cacheado"')"
    if [ "$saida_f1" = "rc=0 vbox=created montado=0 cache=1" ]; then
        ok "F1 inteira: SHA, cache, mount por -plist, .pkg, installer, detach, re-sonda"
    else
        falha "F1 de ponta a ponta: esperado 'rc=0 vbox=created montado=0 cache=1', obtido '$saida_f1'"
    fi
    hdiutil detach -quiet /Volumes/HAOSGateVBox 2>/dev/null || true
else
    ok "hdiutil indisponível aqui — a F1 de ponta a ponta fica com o runner macOS"
fi
rm -rf "$sb_f1"

# ── F4 de ponta a ponta (VBoxManage dublado) ─────────────────────────────────
# A criação da VM roda inteira contra um dublê que GRAVA cada chamada. As
# asserções vêm da sonda de 24/08 no binário ARM real: --platform-architecture
# arm, ostype Linux_arm64, SATA/IntelAhci (VirtIO SCSI é recusado no ARM),
# ponte SONDADA (nunca nome fixo), medium = o .vdi da fase anterior. E a
# segunda execução tem de convergir em 100 sem recriar nada.
titulo "F4 de ponta a ponta (VBoxManage dublado)"
sb_f4="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-f4.XXXXXX")"
touch "$sb_f4/haos.vdi"
# shellcheck disable=SC2016  # o script filho expande $SB sozinho, de propósito
saida_f4="$(HAOS_INSTALL_LIB=1 SB="$sb_f4" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"
    OP_VM_NOME=HomeAssistant; HAOS_VDI="$SB/haos.vdi"
    VM_RAM_MIB=4096; VM_CPU_N=2
    VBoxManage() { # dublê: grava a chamada e simula o 7.2.16 ARM
        printf "%s\n" "$*" >> "$SB/calls.txt"
        case "$1" in
            showvminfo)
                [ -f "$SB/created" ] || return 1
                printf "firmware=\"EFI\"\nnic1=\"bridged\"\n\"SATA-0-0\"=\"%s\"\n" \
                    "$(cat "$SB/medium" 2>/dev/null)"
                return 0 ;;
            createvm) touch "$SB/created"; return 0 ;;
            storageattach)
                local a prev=""
                for a in "$@"; do
                    [ "$prev" = "--medium" ] && printf "%s" "$a" > "$SB/medium"
                    prev="$a"
                done
                return 0 ;;
            list)
                printf "Name:            en7: Cabo Fake\nIPAddress:       10.9.9.9\nStatus:          Up\n"
                return 0 ;;
            *) return 0 ;;
        esac
    }
    route() { return 1; } # sem rota default: força o caminho da varredura
    rc1=0; fase_vm >/dev/null 2>&1 || rc1=$?
    rc2=0; fase_vm >/dev/null 2>&1 || rc2=$?
    st="$(manifest_get "$(vm_manifest)" vm_registrada)"
    seq=1
    grep -q "^createvm .*--platform-architecture arm" "$SB/calls.txt" || seq=0
    grep -q "^createvm .*--ostype Linux_arm64" "$SB/calls.txt" || seq=0
    grep -q "^storagectl .*--add sata .*--controller IntelAhci" "$SB/calls.txt" || seq=0
    grep -q "^setextradata .*IgnoreFlush 0" "$SB/calls.txt" || seq=0
    grep -q "^modifyvm .*--bridge-adapter1 en7: Cabo Fake" "$SB/calls.txt" || seq=0
    if grep -qi "virtio-scsi" "$SB/calls.txt"; then seq=0; fi
    [ "$(cat "$SB/medium" 2>/dev/null)" = "$SB/haos.vdi" ] || seq=0
    n_create="$(grep -c "^createvm" "$SB/calls.txt")"
    printf "rc1=%s rc2=%s st=%s seq=%s criacoes=%s" "$rc1" "$rc2" "$st" "$seq" "$n_create"')"
if [ "$saida_f4" = "rc1=0 rc2=100 st=created seq=1 criacoes=1" ]; then
    ok "F4 inteira: args da sonda ARM, ponte sondada, medium certo, convergência em 100"
else
    falha "F4 de ponta a ponta: esperado 'rc1=0 rc2=100 st=created seq=1 criacoes=1', obtido '$saida_f4'"
fi
rm -rf "$sb_f4"

# ── Doctor: cerca da seção de storage (§8.3 — controller + IgnoreFlush + T5) ─
# AHCI+flush aprova; flush ausente REPROVA (getextradata rc=0 mesmo sem valor,
# medido no 7.2.16 — o veredito tem de sair do texto); controller estranho só
# avisa (IgnoreFlush não é documentado para ele); versão do VBox divergente da
# registrada na criação avisa, igual aprova.
titulo "Doctor: storage — flush, controller e versão do hypervisor"
sb_ds="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-ds.XXXXXX")"
# shellcheck disable=SC2016  # o script filho expande $SB sozinho, de propósito
saida_ds="$(HAOS_INSTALL_LIB=1 SB="$sb_ds" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"; OP_VM_NOME=HomeAssistant
    p_get() { case "$1" in vbox.present) echo 1 ;; vbox.version) echo 7.2.16r174877 ;; esac; }
    manifest_get() { cat "$SB/vbox_reg"; }
    caso() { # <ctrl> <saida-do-getextradata> <versao-registrada>
        CTRL="$1"; FLUSH="$2"; printf "%s" "$3" > "$SB/vbox_reg"
        VBoxManage() {
            case "$1" in
                showvminfo)   printf "storagecontrollertype0=\"%s\"\n" "$CTRL" ;;
                getextradata) printf "%s\n" "$FLUSH" ;;
            esac
            return 0
        }
        DOC_OK=0; DOC_WARN=0; DOC_FAIL=0
        doctor_storage >/dev/null 2>&1 || true
        printf "%s/%s/%s " "$DOC_OK" "$DOC_WARN" "$DOC_FAIL"
    }
    caso IntelAhci  "Value: 0"      7.2.16r174877
    caso IntelAhci  "No value set!" 7.2.16r174877
    caso VirtioSCSI "Value: 0"      ""
    caso IntelAhci  "Value: 0"      7.2.14r000000')"
if [ "$saida_ds" = "2/0/0 1/0/1 0/1/0 1/1/0 " ]; then
    ok "doctor_storage: 4 cenários com o veredito certo (ok/warn/fail contados)"
else
    falha "doctor_storage: esperado '2/0/0 1/0/1 0/1/0 1/1/0 ', obtido '$saida_ds'"
fi
rm -rf "$sb_ds"

# ── fase_imagem: o disco VIVO nunca se substitui ─────────────────────────────
# O cenário exato da 4ª morte do /data: disco dinâmico CRESCEU depois do
# boot, o rerun reprovava o "já está" pelo tamanho e movia a fábrica por
# cima do disco da VM registrada. A cerca exige: (a) disco crescido + origem
# com ver|sha certos → 100 SEM tocar na rede; (b) origem divergente + VM
# registrada → recusa (rc=1), nada baixado, disco intacto; (c) sem VM
# registrada, o fluxo de aquisição segue vivo (chega ao download).
titulo "fase_imagem: disco crescido converge; disco de VM viva é intocável"
sb_im="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-im.XXXXXX")"
# shellcheck disable=SC2016  # o script filho expande $SB sozinho, de propósito
saida_im="$(HAOS_INSTALL_LIB=1 SB="$sb_im" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"; OP_VM_NOME=HomeAssistant
    mkdir -p "$SB/bin"; PATH="$SB/bin:$PATH"
    printf "#!/bin/sh\necho REDE >> \"%s/rede.txt\"\nexit 1\n" "$SB" > "$SB/bin/curl"
    cp "$SB/bin/curl" "$SB/bin/wget"; chmod +x "$SB/bin/curl" "$SB/bin/wget"
    VBoxManage() { case "$1" in showvminfo) return 0 ;; *) return 0 ;; esac; }
    ver="$HAOS_REF_OS"; sha=""
    for r in "${HAOS_IMAGE_DB[@]}"; do IFS="|" read -r rv u s b <<< "$r"
        [ "$rv" = "$ver" ] && sha="$s"; done
    D="$SB/VirtualBox VMs/HomeAssistant"; mkdir -p "$D"
    V="$D/haos_generic-aarch64-$ver.vdi"; O="$D/.haos_generic-aarch64-$ver.vdi.origem"
    # (a) disco CRESCIDO (tamanho no origem difere do arquivo) + ver|sha ok
    printf "cresci-muito-depois-do-boot" > "$V"
    printf "%s|%s|11\n" "$ver" "$sha" > "$O"
    rcA=0; fase_imagem >/dev/null 2>&1 || rcA=$?
    conteudoA="$(cat "$V")"
    # (b) origem com sha DIVERGENTE + VM registrada: recusa sem tocar
    printf "%s|deadbeef|11\n" "$ver" > "$O"
    rcB=0; fase_imagem >/dev/null 2>&1 || rcB=$?
    conteudoB="$(cat "$V")"
    redeAB=0; [ -f "$SB/rede.txt" ] && redeAB=1
    # (c) sem VM registrada, aquisição segue viva (bate na rede e falha nela)
    VBoxManage() { return 1; }
    rm -f "$V" "$O"
    rcC=0; fase_imagem >/dev/null 2>&1 || rcC=$?
    redeC=0; [ -f "$SB/rede.txt" ] && redeC=1
    printf "A=%s/%s B=%s/%s redeAB=%s C=%s/rede%s" \
        "$rcA" "$conteudoA" "$rcB" "$conteudoB" "$redeAB" "$rcC" "$redeC"')"
esp_im="A=100/cresci-muito-depois-do-boot B=1/cresci-muito-depois-do-boot redeAB=0 C=1/rede1"
if [ "$saida_im" = "$esp_im" ]; then
    ok "fase_imagem: crescido=100, VM viva intocável (zero rede), aquisição segue sem VM"
else
    falha "fase_imagem: esperado '$esp_im', obtido '$saida_im'"
fi
rm -rf "$sb_im"

# ── apfs-pin: cerca dos artefatos + do doctor ────────────────────────────────
# O vigia é a defesa contra o fsync fraco do VirtualBox no macOS (RTFileFlush
# sem F_FULLFSYNC, provado no fonte; APFS reverteu o disco ao estado de
# fábrica num corte real). A cerca exige: script com F_FULLFSYNC, plist sem
# `sh -c` (mesma cerca de injeção do vm-guard) apontando o VDI por argv,
# convergência silenciosa na 2ª chamada, e doctor com os 3 vereditos.
titulo "apfs-pin: artefatos escritos, sem sh -c, convergentes; doctor 3 vereditos"
sb_pn="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-pn.XXXXXX")"
# shellcheck disable=SC2016  # o script filho expande $SB sozinho, de propósito
saida_pn="$(HAOS_INSTALL_LIB=1 SB="$sb_pn" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"
    launchctl() { printf "%s\n" "$*" >> "$SB/lc.txt"; return 0; }
    mkdir -p "$SB/vm"; printf x > "$SB/vm/disco.vdi"
    vm_set vdi_path "$SB/vm/disco.vdi"
    escrever_pin_artefatos >/dev/null 2>&1
    S="$SB/Library/Application Support/haos-mac-mini/apfs-pin.py"
    P="$SB/Library/LaunchAgents/com.haos-mac-mini.apfs-pin.plist"
    a=0
    # a CHAMADA (fcntl.F_FULLFSYNC), não o comentário; e -c em tag própria
    [ -x "$S" ] && grep -qF "fcntl.F_FULLFSYNC" "$S" \
        && grep -qF "$SB/vm/disco.vdi" "$P" \
        && ! grep -qE "<string>-c</string>|sh -c|bash -c" "$P" \
        && [ "$(manifest_get "$(vm_manifest)" pin_agente)" = "created" ] && a=1
    sum1="$(cksum "$P")"
    escrever_pin_artefatos >/dev/null 2>&1
    conv=0; [ "$(cksum "$P")" = "$sum1" ] && conv=1
    # doctor_pin: ausente → warn · rodando → ok · parado → fail
    p_get() { echo 1; }
    d() { DOC_OK=0; DOC_WARN=0; DOC_FAIL=0; doctor_pin >/dev/null 2>&1; printf "%s%s%s" "$DOC_OK" "$DOC_WARN" "$DOC_FAIL"; }
    mv "$P" "$P.fora"; da="$(d)"; mv "$P.fora" "$P"
    launchctl() { printf "state = running\n"; return 0; }
    db="$(d)"
    launchctl() { return 1; }
    dc="$(d)"
    printf "arte=%s conv=%s d=%s/%s/%s" "$a" "$conv" "$da" "$db" "$dc"')"
if [ "$saida_pn" = "arte=1 conv=1 d=010/100/001" ]; then
    ok "apfs-pin: artefatos certos, injeção barrada, convergência e doctor nos 3 vereditos"
else
    falha "apfs-pin: esperado 'arte=1 conv=1 d=010/100/001', obtido '$saida_pn'"
fi
rm -rf "$sb_pn"

# ── --backup: cerca da voz e do veredito ─────────────────────────────────────
# O agente das 04:10 é mudo por design; a flag manual NÃO pode ser: tar novo
# diz onde ficou (A), nada novo diz que o cofre já está atual (D), falha do
# puxador vira rc=1 com explicação (B), cofre inexistente vira uso rc=2 (C).
titulo "--backup: tar novo, cofre atual, falha do puxador, sem cofre"
sb_bk="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-bk.XXXXXX")"
# shellcheck disable=SC2016  # o script filho expande $SB sozinho, de propósito
saida_bk="$(HAOS_INSTALL_LIB=1 SB="$sb_bk" HAOS_LANG=pt "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"
    sdir="$SB/Library/Application Support/haos-mac-mini"
    dest="$SB/Documents/HAOS-backups"
    mkdir -p "$sdir" "$dest"
    printf x > "$dest/velho.tar"
    touch -t 202601010000 "$dest/velho.tar"
    # esta cerca testa o VEREDITO do rodar_backup com puxadores de mentira;
    # a convergência do artefato real tem cerca própria (tar protegido/poda)
    escrever_cofre_artefatos() { :; }
    roda() { RC=0; OUT="$(rodar_backup 2>&1)" || RC=$?; }
    # A: o puxador traz um tar novo
    printf "#!/bin/sh\nprintf y > \"%s/novo.tar\"\nexit 0\n" "$dest" > "$sdir/backup-pull.sh"
    chmod +x "$sdir/backup-pull.sh"
    roda; a="$RC"; case "$OUT" in *novo.tar*) a="$a/novo" ;; esac
    rm -f "$dest/novo.tar"
    # D: o puxador não traz nada e sai 0 (cofre já atual)
    printf "#!/bin/sh\nexit 0\n" > "$sdir/backup-pull.sh"
    roda; d="$RC"; case "$OUT" in *"já tem"*) d="$d/atual" ;; esac
    # B: o puxador falha (VM fora do ar)
    printf "#!/bin/sh\nexit 3\n" > "$sdir/backup-pull.sh"
    roda; b="$RC"
    # C: cofre nunca instalado
    rm -f "$sdir/backup-pull.sh"
    roda; c="$RC"
    printf "A=%s D=%s B=%s C=%s" "$a" "$d" "$b" "$c"')"
if [ "$saida_bk" = "A=0/novo D=0/atual B=1 C=2" ]; then
    ok "--backup: 4 cenários com a voz e o rc certos"
else
    falha "--backup: esperado 'A=0/novo D=0/atual B=1 C=2', obtido '$saida_bk'"
fi
rm -rf "$sb_bk"

# ── cofre: o puxador ESCRITO recusa tar protegido e poda dentro da VM ────────
# O cofre restaura sem chave: um tar criptografado (backup automático ligado
# na UI do HA) entraria mudo e falharia só na hora do desastre. E sem poda
# interna o /backup da VM cresce ~18 MB/dia até encher o disco. A cerca roda
# o backup-pull.sh que escrever_cofre_artefatos gerou, não uma cópia.
titulo "cofre: protegido recusado, poda só do auto-*, backup do dono intocável"
sb_pp="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-pp.XXXXXX")"
# shellcheck disable=SC2016  # o script filho expande $SB sozinho, de propósito
saida_pp="$(HAOS_INSTALL_LIB=1 SB="$sb_pp" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"; PATH="$SB/bin:$PATH"
    mkdir -p "$SB/bin" "$SB/Documents/HAOS-backups" "$SB/fbk" \
        "$SB/Library/Application Support/haos-mac-mini"
    printf "VMIP=127.0.0.2\n" > "$SB/Library/Application Support/haos-mac-mini/vm-guard.env"
    launchctl() { return 0; }
    cat > "$SB/bin/ssh" <<FIMSSH
#!/bin/sh
caso="\$*"
case "\$caso" in
    *"sudo rm -f /backup/"*) echo poda >> "$SB/poda-vm.txt"; exit 0 ;;
    *"ha backups new"*) exit 0 ;;
    *"ls -t /backup"*)  echo "/backup/t1.tar"; exit 0 ;;
    *"sudo cat /backup/t1.tar"*) cat "$SB/serv.tar"; exit 0 ;;
    *) exit 0 ;;
esac
FIMSSH
    chmod +x "$SB/bin/ssh"
    escrever_cofre_artefatos >/dev/null 2>&1
    P="$SB/Library/Application Support/haos-mac-mini/backup-pull.sh"
    [ -x "$P" ] || { printf "sem-artefato"; exit 0; }
    dest="$SB/Documents/HAOS-backups"
    # protegido: recusa com rc=4, nada aterrissa, nem .parcial sobra
    printf "{\"protected\": true, \"slug\": \"t1\"}" > "$SB/fbk/backup.json"
    tar -cf "$SB/serv.tar" -C "$SB/fbk" ./backup.json
    rcP=0; "$P" >/dev/null 2>&1 || rcP=$?
    nP="$(command ls "$dest" 2>/dev/null | wc -l | tr -d " ")"
    # cofre cheio: 7 autos velhos + 1 tar do DONO, o mais antigo de todos —
    # a lição de 26/08: a poda por contagem cega levou o transplante real
    for n in 1 2 3 4 5 6 7; do
        printf x > "$dest/auto-velho-$n.tar"
        touch -t 2601020$n"00" "$dest/auto-velho-$n.tar"
    done
    printf x > "$dest/transplante-dono.tar"
    touch -t 2512310000 "$dest/transplante-dono.tar"
    # aberto: aceita; poda SÓ auto-* (o do dono fica); poda interna emitida
    printf "{\"protected\": false, \"slug\": \"t1\"}" > "$SB/fbk/backup.json"
    tar -cf "$SB/serv.tar" -C "$SB/fbk" ./backup.json
    rcA=0; "$P" >/dev/null 2>&1 || rcA=$?
    nA="$(command ls "$dest"/*.tar 2>/dev/null | wc -l | tr -d " ")"
    podavm=0; [ -f "$SB/poda-vm.txt" ] && podavm=1
    trans=0; [ -f "$dest/transplante-dono.tar" ] && trans=1
    printf "P=%s/%s A=%s/%s/poda%s/trans%s" "$rcP" "$nP" "$rcA" "$nA" "$podavm" "$trans"')"
if [ "$saida_pp" = "P=4/0 A=0/8/poda1/trans1" ]; then
    ok "puxador real: protegido fora, 7 autos + o tar do dono intacto, poda interna emitida"
else
    falha "puxador real: esperado 'P=4/0 A=0/8/poda1/trans1', obtido '$saida_pp'"
fi
rm -rf "$sb_pp"

# ── F5 de ponta a ponta (boot dublado) ───────────────────────────────────────
# A espera do boot é por MAC→ARP, nunca por mDNS (falso positivo medido em
# campo com outro HA vivo na rede). Os stubs FALHAM nas primeiras iterações
# (arp vazio, depois curl mudo) para exercitar o laço de verdade; depois o
# caminho de timeout com HAOS_BOOT_TIMEOUT mínimo; e o launchctl é dublado.
titulo "F5 de ponta a ponta (boot dublado)"
sb_f5="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-f5.XXXXXX")"
# shellcheck disable=SC2016
saida_f5="$(HAOS_INSTALL_LIB=1 SB="$sb_f5" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"
    OP_VM_NOME=HomeAssistant
    HAOS_BOOT_PASSO=1; HAOS_BOOT_TIMEOUT=8
    VBoxManage() {
        printf "%s\n" "$*" >> "$SB/calls.txt"
        case "$1" in
            showvminfo) printf "macaddress1=\"0800270C0FFB\"\nVMState=\"poweroff\"\n"; return 0 ;;
            list)       return 0 ;;   # nada rodando
            startvm)    touch "$SB/ligada"; return 0 ;;
            *) return 0 ;;
        esac
    }
    vbm() { VBoxManage "$@"; }
    # contadores em ARQUIVO: os stubs rodam dentro de $( ) — subshell, variável
    # de contagem morreria a cada chamada (lição desta própria cerca)
    arp() { # vazio 2x, depois entrega o IP no formato do macOS
        local n; n="$(cat "$SB/n_arp" 2>/dev/null || printf 0)"; n=$((n+1))
        printf "%s" "$n" > "$SB/n_arp"
        [ "$n" -le 2 ] && return 0
        printf "? (10.9.9.9) at 8:0:27:c:f:fb on en7 ifscope [ethernet]\n"
    }
    curl() {
        local m; m="$(cat "$SB/n_curl" 2>/dev/null || printf 0)"; m=$((m+1))
        printf "%s" "$m" > "$SB/n_curl"
        [ "$m" -le 1 ] && { printf "000"; return 0; }; printf "307"
    }
    ping() { touch "$SB/pingou"; return 0; }
    route() { printf "   interface: en7\n"; }
    ifconfig() { printf "	inet 10.9.9.1 netmask 0xffffff00 broadcast 10.9.9.255\n"; }
    launchctl() { printf "%s\n" "$*" >> "$SB/launchctl.txt"; return 0; }
    sleep() { :; }
    rc1=0; fase_boot >/dev/null 2>&1 || rc1=$?
    ip="$(manifest_get "$(vm_manifest)" vm_ip)"
    mac="$(manifest_get "$(vm_manifest)" vm_mac)"
    ag="$(manifest_get "$(vm_manifest)" autostart)"
    plist_ok=0
    p="$SB/Library/LaunchAgents/com.haos-mac-mini.HomeAssistant.plist"
    g="$SB/Library/Application Support/haos-mac-mini/vm-guard.sh"
    [ -f "$p" ] && ! grep -q -- "-c</string>" "$p" \
        && grep -q "vm-guard.sh</string>" "$p" \
        && grep -q "<string>HomeAssistant</string>" "$p" \
        && [ -x "$g" ] && grep -q "ha host shutdown" "$g" \
        && grep -q "poweroff" "$g" \
        && ! grep -qE "controlvm.*savestate" "$g" \
        && [ -f "$SB/Library/Application Support/haos-mac-mini/vm-guard.env" ] \
        && plist_ok=1
    boot_ok=0; [ -f "$SB/ligada" ] && [ -f "$SB/pingou" ] && boot_ok=1
    # convergência: agora a VM "roda" e responde de primeira
    VBoxManage() { case "$1" in showvminfo) printf "macaddress1=\"0800270C0FFB\"\nVMState=\"running\"\n";; list) printf "\"HomeAssistant\" {u}\n";; esac; return 0; }
    arp() { printf "? (10.9.9.9) at 8:0:27:c:f:fb on en7 [ethernet]\n"; }
    curl() { printf "200"; }
    rc2=0; fase_boot >/dev/null 2>&1 || rc2=$?
    # timeout: arp nunca acha
    arp() { return 0; }
    VBoxManage() { case "$1" in showvminfo) printf "macaddress1=\"0800270C0FFB\"\nVMState=\"poweroff\"\n";; *) :;; esac; return 0; }
    rc3=0; fase_boot >/dev/null 2>&1 || rc3=$?
    printf "rc1=%s rc2=%s rc3=%s ip=%s mac=%s ag=%s plist=%s boot=%s" \
        "$rc1" "$rc2" "$rc3" "$ip" "$mac" "$ag" "$plist_ok" "$boot_ok"')"
esp_f5="rc1=0 rc2=100 rc3=1 ip=10.9.9.9 mac=8:0:27:c:f:fb ag=created plist=1 boot=1"
if [ "$saida_f5" = "$esp_f5" ]; then
    ok "F5 inteira: laço com ARP tardio, convergência 100, timeout limpo, agente sem sh -c"
else
    falha "F5 de ponta a ponta: esperado '$esp_f5', obtido '$saida_f5'"
fi
rm -rf "$sb_f5"

# ── vm-guard: os DOIS cenários de desligamento, com o script de verdade ──────
# Limpo: TERM → ssh `ha host shutdown` responde e a VM some → SEM poweroff.
# Fallback: ssh falha e a VM não morre → poweroff após GUARD_TIMEOUT.
titulo "vm-guard: desligamento limpo e fallback"
sb_g="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-guard.XXXXXX")"
# shellcheck disable=SC2016
saida_g="$(HAOS_INSTALL_LIB=1 SB="$sb_g" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"
    OP_VM_NOME=HomeAssistant
    launchctl() { return 0; }
    autostart_launchagent >/dev/null 2>&1
    mkdir -p "$SB/Library/Application Support/haos-mac-mini" "$SB/bin" "$SB/c1" "$SB/c2"
    printf "VMIP=127.0.0.2\n" > "$SB/Library/Application Support/haos-mac-mini/vm-guard.env"
    mkdir -p "$SB/.ssh"; printf "chave-cerca\n" > "$SB/.ssh/haos-mac-mini"
    g="$SB/Library/Application Support/haos-mac-mini/vm-guard.sh"
    [ -x "$g" ] || { printf "sem-guard"; exit 0; }
    # shims de PATH: o guard é processo separado — função de shell não o alcança
    cat > "$SB/bin/VBoxManage" <<FIMV
#!/bin/sh
echo "\$*" >> "\$CENARIO/calls.txt"
case "\$*" in
    "list runningvms")
        n=\$(cat "\$CENARIO/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "\$CENARIO/n"
        if [ -f "\$CENARIO/imortal" ] || [ \$n -le 2 ]; then echo "\"HomeAssistant\" {u}"; fi ;;
esac
exit 0
FIMV
    chmod +x "$SB/bin/VBoxManage"
    cat > "$SB/bin/ssh" <<FIMS
#!/bin/sh
echo "ssh \$*" >> "\$CENARIO/calls.txt"
[ -f "\$CENARIO/ssh-falha" ] && exit 1
exit 0
FIMS
    chmod +x "$SB/bin/ssh"
    roda_cenario() { # <dir>
        CENARIO="$1" PATH="$SB/bin:$PATH" VBM_BIN="$SB/bin/VBoxManage" \
            GUARD_TIMEOUT=6 /bin/sh "$g" HomeAssistant &
        gp=$!
        sleep 1
        kill -TERM $gp 2>/dev/null
        wait $gp 2>/dev/null
    }
    roda_cenario "$SB/c1"
    limpo_ssh=0; grep -q "ssh .*ha host shutdown" "$SB/c1/calls.txt" && limpo_ssh=1
    limpo_pw=0;  grep -q "controlvm HomeAssistant poweroff" "$SB/c1/calls.txt" && limpo_pw=1
    touch "$SB/c2/imortal" "$SB/c2/ssh-falha"
    roda_cenario "$SB/c2"
    fb_pw=0; grep -q "controlvm HomeAssistant poweroff" "$SB/c2/calls.txt" && fb_pw=1
    printf "limpo_ssh=%s limpo_pw=%s fb_pw=%s" "$limpo_ssh" "$limpo_pw" "$fb_pw"')"
if [ "$saida_g" = "limpo_ssh=1 limpo_pw=0 fb_pw=1" ]; then
    ok "vigia: limpo desliga via ha host shutdown SEM poweroff; fallback faz poweroff no prazo"
else
    falha "vm-guard: esperado 'limpo_ssh=1 limpo_pw=0 fb_pw=1', obtido '$saida_g'"
fi
rm -rf "$sb_g"

# ── --restore de ponta a ponta (dublado) ─────────────────────────────────────
# O caminho de volta: tar do cofre → push → reload → restore → espera voltar.
# E a recusa: tar corrompido nem sai do lugar.
titulo "--restore (dublado)"
sb_r="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-rest.XXXXXX")"
python3 - "$sb_r" <<'PYTAR'
import io, json, sys, tarfile
sb = sys.argv[1]
with tarfile.open(f"{sb}/bom.tar", "w") as t:
    dado = json.dumps({"slug": "feed1234", "name": "cerca"}).encode()
    info = tarfile.TarInfo("./backup.json"); info.size = len(dado)
    t.addfile(info, io.BytesIO(dado))
open(f"{sb}/ruim.tar", "wb").write(b"nao sou um tar")
PYTAR
# shellcheck disable=SC2016
saida_r="$(HAOS_INSTALL_LIB=1 SB="$sb_r" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"
    OP_VM_NOME=HomeAssistant
    HAOS_HA_USER=u; HAOS_HA_PASSWORD=p; OP_NOINPUT=1
    HAOS_BOOT_PASSO=1; HAOS_BOOT_TIMEOUT=8
    fase_boot() { VM_IP=10.9.9.9; VM_URL="http://10.9.9.9"; return 100; }
    helper() { case "$1" in
        conta) return 0 ;;
        repo-ensure) printf "a1b2c3d4_ssh\n" ;;
        addon-ensure) return 0 ;;
    esac; }
    garantir_chave_ssh() { CHAVE_SSH_PUB="ssh-ed25519 CERCA"; }
    ssh-keygen() { return 0; }
    vmssh() {
        printf "%s\n" "$*" >> "$SB/calls.txt"
        case "$*" in *"sudo tee /backup/feed1234.tar"*) cat > "$SB/pushed.tar" ;; esac
        return 0
    }
    curl() { printf "404: Not Found"; }
    garantir_log
    OP_RESTORE="$SB/bom.tar"
    rc1=0; rodar_restore >/dev/null 2>&1 || rc1=$?
    seq_ok=1
    grep -q "ha backups reload" "$SB/calls.txt" || seq_ok=0
    grep -q "ha backups restore feed1234" "$SB/calls.txt" || seq_ok=0
    igual=0; cmp -s "$SB/pushed.tar" "$SB/bom.tar" && igual=1
    OP_RESTORE="$SB/ruim.tar"
    rc2=0; rodar_restore >/dev/null 2>&1 || rc2=$?
    printf "rc1=%s seq=%s igual=%s rc2=%s" "$rc1" "$seq_ok" "$igual" "$rc2"')"
if [ "$saida_r" = "rc1=0 seq=1 igual=1 rc2=2" ]; then
    ok "--restore: push íntegro + reload + restore pelo slug + espera; tar corrompido recusado"
else
    falha "--restore: esperado 'rc1=0 seq=1 igual=1 rc2=2', obtido '$saida_r'"
fi
rm -rf "$sb_r"

# ── caminho seguro do uninstall: cerca NEGATIVA da classe agent ──────────────
titulo "un_caminho_seguro (classe agent)"
# shellcheck disable=SC2016
saida_ag="$(HAOS_INSTALL_LIB=1 "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    ok=1
    un_caminho_seguro "$HOME/Library/LaunchAgents/com.haos-mac-mini.X.plist" agent || ok=0
    un_caminho_seguro "$HOME/Library/LaunchAgents/com.apple.dock.plist" agent && ok=0
    un_caminho_seguro "$HOME/Library/LaunchAgents/com.haos-mac-mini../../../etc.plist" agent && ok=0
    printf "%s" "$ok"')"
if [ "$saida_ag" = "1" ]; then
    ok "classe agent: aceita só com.haos-mac-mini.*.plist dentro de LaunchAgents"
else
    falha "cerca negativa da classe agent furada"
fi

# ── F6–F9 contra um Home Assistant DUBLADO (REST + WebSocket reais) ─────────
# Um servidor python (stdlib) fala as duas superfícies que o helper usa:
# onboarding/login_flow/token/config_entries por HTTP e supervisor/api por
# WebSocket — com um frame >64 KiB para forçar o comprimento de 8 bytes no
# cliente (banca cer#6). A senha é uma SENTINELA: no fim, grep prova que ela
# não vazou para LOG_FILE, last-run, manifesto nem state dir (banca cer#2).
titulo "F6–F9 contra HA dublado"
sb_ha="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-ha.XXXXXX")"
cat > "$sb_ha/fake_ha.py" <<'FIM_FAKE_HA'
import base64, hashlib, json, os, signal, socket, struct, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORTFILE, REQLOG = sys.argv[1], sys.argv[2]
signal.alarm(120)  # watchdog: o portão nunca fica pendurado nesta cerca
estado = {"onboarded": False, "addons": {}, "repos": ["core"], "entries": []}
tranca = threading.Lock()

def log(evento):
    with tranca, open(REQLOG, "a") as f:
        f.write(json.dumps(evento) + "\n")

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, corpo, code=200):
        dado = json.dumps(corpo).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(dado)))
        self.end_headers()
        self.wfile.write(dado)

    def _corpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        bruto = self.rfile.read(n).decode() if n else ""
        try:
            return json.loads(bruto)
        except Exception:
            from urllib.parse import parse_qs
            return {k: v[0] for k, v in parse_qs(bruto).items()}

    def do_GET(self):
        if self.path == "/api/websocket":
            return self._ws()
        if self.path == "/api/onboarding":
            if estado["onboarded"]:
                return self._json({"error": "gone"}, 404)
            return self._json([{"step": s, "done": False} for s in
                               ("user", "core_config", "analytics", "integration")])
        if self.path == "/api/config/config_entries/entry":
            return self._json(estado["entries"])
        self._json({}, 404)

    def do_POST(self):
        c = self._corpo()
        log({"m": "POST", "p": self.path, "c": c})
        p = self.path
        if p == "/api/onboarding/users":
            if not (c.get("username") and c.get("password")):
                return self._json({}, 400)
            estado["cred"] = (c["username"], c["password"])
            return self._json({"auth_code": "code-onboarding"})
        if p == "/auth/login_flow":
            return self._json({"flow_id": "lf1", "step_id": "init"})
        if p == "/auth/login_flow/lf1":
            if (c.get("username"), c.get("password")) == estado.get("cred"):
                return self._json({"type": "create_entry", "result": "code-login"})
            return self._json({"type": "form", "errors": {"base": "invalid_auth"}})
        if p == "/auth/token":
            return self._json({"access_token": "tok", "refresh_token": "ref",
                               "token_type": "Bearer"})
        if p in ("/api/onboarding/core_config", "/api/onboarding/analytics",
                 "/api/onboarding/integration"):
            if p.endswith("integration"):
                estado["onboarded"] = True
            return self._json({})
        if p == "/api/config/config_entries/flow":
            h = c.get("handler")
            if h == "systemmonitor":
                estado["entries"].append({"domain": h, "entry_id": "e1",
                                          "source": "user"})
                return self._json({"type": "create_entry", "flow_id": "f1"})
            if h == "fora_do_conjunto":
                estado["entries"].append({"domain": h, "entry_id": "e2",
                                          "source": "zeroconf"})
                return self._json({"type": "create_entry", "flow_id": "f2"})
            return self._json({"type": "form", "flow_id": "f3", "step_id": "user",
                               "data_schema": [{"name": "host", "required": True}]})
        if p == "/api/config/core/check_config":
            return self._json({"result": "valid"})
        if p == "/api/services/homeassistant/restart":
            return self._json({})
        self._json({}, 404)

    def do_DELETE(self):
        log({"m": "DELETE", "p": self.path})
        if self.path.startswith("/api/config/config_entries/entry/"):
            eid = self.path.rsplit("/", 1)[1]
            estado["entries"] = [e for e in estado["entries"]
                                 if e["entry_id"] != eid]
        self._json({})

    # ── WebSocket lado servidor ──────────────────────────────────────────────
    def _ws(self):
        chave = self.headers.get("Sec-WebSocket-Key", "")
        aceite = base64.b64encode(hashlib.sha1(
            (chave + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
        ).decode()
        self.wfile.write((
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Accept: " + aceite + "\r\n\r\n"
        ).encode())
        s = self.connection
        s.settimeout(30)

        def manda(obj):
            d = json.dumps(obj).encode()
            if len(d) < 126:
                cab = struct.pack("!BB", 0x81, len(d))
            elif len(d) < 65536:
                cab = struct.pack("!BBH", 0x81, 126, len(d))
            else:
                cab = struct.pack("!BBQ", 0x81, 127, len(d))
            s.sendall(cab + d)

        def le():
            def exato(n):
                b = b""
                while len(b) < n:
                    p = s.recv(n - len(b))
                    if not p:
                        raise EOFError
                    b += p
                return b
            b1, b2 = struct.unpack("!BB", exato(2))
            tam = b2 & 0x7F
            if tam == 126:
                (tam,) = struct.unpack("!H", exato(2))
            elif tam == 127:
                (tam,) = struct.unpack("!Q", exato(8))
            masc = exato(4) if b2 & 0x80 else b""
            dado = exato(tam)
            if masc:
                dado = bytes(x ^ masc[i % 4] for i, x in enumerate(dado))
            if b1 & 0x0F == 0x8:
                raise EOFError
            return json.loads(dado.decode())

        manda({"type": "auth_required"})
        m = le()
        if m.get("access_token") != "tok":
            manda({"type": "auth_invalid"})
            return
        manda({"type": "auth_ok"})
        try:
            while True:
                m = le()
                log({"m": "WS", "c": m})
                mid = m.get("id")
                if m.get("type") == "config_entries/flow/progress":
                    manda({"id": mid, "type": "result", "success": True,
                           "result": [{"handler": "hue"}, {"handler": "shelly"}]})
                    continue
                if m.get("type") == "energy/get_prefs":
                    if "energia" in estado:
                        manda({"id": mid, "type": "result", "success": True,
                               "result": {"energy_sources": estado["energia"]}})
                    else:
                        manda({"id": mid, "type": "result", "success": False,
                               "error": {"code": "not_found", "message": "No prefs"}})
                    continue
                if m.get("type") == "energy/save_prefs":
                    estado["energia"] = m.get("energy_sources") or []
                    manda({"id": mid, "type": "result", "success": True, "result": {}})
                    continue
                if m.get("type") == "config/entity_registry/list":
                    # o dublado cobre os 4 destinos do entity-enable:
                    # desabilitada-pela-integracao (vira update), ja ativa
                    # (ja), desligada PELO DONO (mantido - nunca update) e
                    # interface lo (o glob _e* nao pode casar)
                    manda({"id": mid, "type": "result", "success": True,
                           "result": [
                        {"entity_id": "sensor.system_monitor_processor_use",
                         "disabled_by": "integration"},
                        {"entity_id": "sensor.system_monitor_memory_usage",
                         "disabled_by": None},
                        {"entity_id": "sensor.system_monitor_swap_usage",
                         "disabled_by": "user"},
                        {"entity_id": "sensor.system_monitor_network_throughput_in_enp0s9",
                         "disabled_by": "integration"},
                        {"entity_id": "sensor.system_monitor_network_throughput_in_lo",
                         "disabled_by": "integration"},
                    ]})
                    continue
                if m.get("type") == "config/entity_registry/update":
                    manda({"id": mid, "type": "result", "success": True,
                           "result": {}})
                    continue
                ep = m.get("endpoint", "")
                metodo = m.get("method", "get")
                if ep == "/store":
                    manda({"id": mid, "type": "result", "success": True,
                           "result": {"repositories":
                                      [{"source": s2, "slug": ("a1b2c3d4" if "hassio-addons" in s2 else s2)}
                                       for s2 in estado["repos"]],
                                      "addons": [{"slug": "a1b2c3d4_ssh"}, {"slug": "a1b2c3d4_vscode"}] if any("hassio-addons" in r for r in estado["repos"]) else [],
                                      "enchimento": "x" * 70000}})
                elif ep == "/store/repositories" and metodo == "post":
                    estado["repos"].append(m["data"]["repository"])
                    manda({"id": mid, "type": "result", "success": True, "result": {}})
                elif ep == "/addons":
                    manda({"id": mid, "type": "result", "success": True,
                           "result": {"addons": [{"slug": k} for k in estado["addons"]]}})
                elif ep.startswith("/store/addons/") and ep.endswith("/install"):
                    slug = ep.split("/")[3]
                    estado["addons"][slug] = {"version": "1.0", "state": "stopped",
                                              "options": {}}
                    manda({"id": mid, "type": "result", "success": True, "result": {}})
                elif ep.endswith("/options") and metodo == "post":
                    slug = ep.split("/")[2]
                    estado["addons"][slug]["options"] = m["data"]["options"]
                    manda({"id": mid, "type": "result", "success": True, "result": {}})
                elif ep.endswith("/start") and metodo == "post":
                    slug = ep.split("/")[2]
                    estado["addons"][slug]["state"] = "started"
                    manda({"id": mid, "type": "result", "success": True, "result": {}})
                elif ep.endswith("/restart") and metodo == "post":
                    slug = ep.split("/")[2]
                    estado["addons"][slug]["state"] = "started"
                    manda({"id": mid, "type": "result", "success": True, "result": {}})
                elif ep.endswith("/info"):
                    slug = ep.split("/")[2]
                    a = estado["addons"].get(slug)
                    if a is None:
                        manda({"id": mid, "type": "result", "success": False,
                               "error": {"code": "not_found", "message": ""}})
                    else:
                        manda({"id": mid, "type": "result", "success": True,
                               "result": dict(a)})
                else:
                    manda({"id": mid, "type": "result", "success": False,
                           "error": {"code": "?", "message": ep}})
        except (EOFError, socket.timeout, OSError):
            return

srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(PORTFILE, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
FIM_FAKE_HA
python3 "$sb_ha/fake_ha.py" "$sb_ha/porta" "$sb_ha/req.log" &
pid_fake=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$sb_ha/porta" ] && break; sleep 0.3; done
if [ -s "$sb_ha/porta" ]; then
    porta_ha="$(cat "$sb_ha/porta")"
    # shellcheck disable=SC2016
    saida_ha="$(HAOS_INSTALL_LIB=1 SB="$sb_ha" PORTA="$porta_ha" "${BASH:-/bin/bash}" -c '
        source haos-install.sh
        HOME="$SB"; PATH="$SB/bin:$PATH"
        mkdir -p "$SB/bin"
        # mount_smbfs dublado: pede senha (o expect REAL a responde — o cano
        # inteiro é exercitado) e povoa o "share" com um configuration.yaml
        printf "#!/bin/sh\nprintf \"Password for fake: \"\nread -r _s\nprintf \"default_config:\\\\n\" > \"\$2/configuration.yaml\"\nexit 0\n" > "$SB/bin/mount_smbfs"
        chmod +x "$SB/bin/mount_smbfs"
        VM_URL="http://127.0.0.1:$PORTA"; VM_IP="127.0.0.2"
        HAOS_BOOT_TIMEOUT=2; HAOS_BOOT_PASSO=1
        HAOS_HA_USER="usuario-cerca"; HAOS_HA_PASSWORD="SENTINELA-9f3a7c"
        OP_NOINPUT=1
        garantir_log
        rc_c1=0; fase_conta  >/dev/null 2>&1 || rc_c1=$?
        rc_c2=0; fase_conta  >/dev/null 2>&1 || rc_c2=$?   # 2a: login_flow
        HA_SENHA_ERRADA=0
        SEL_ITENS="samba advanced_ssh studio_code_server"
        rc_a1=0; fase_apps   >/dev/null 2>&1 || rc_a1=$?
        rc_a2=0; fase_apps   >/dev/null 2>&1 || rc_a2=$?   # convergência
        SEL_ITENS="systemmonitor tuya"
        rc_i=0;  fase_integracoes >/dev/null 2>&1 || rc_i=$?
        n_flows="$(printf "%s" "$FLOWS_PENDENTES" | grep -c .)"
        # cerca de conjunto: o dublado grava source=zeroconf; permitido só user
        rc_cj=0
        printf "%s\n%s\n" "$HAOS_HA_USER" "$HAOS_HA_PASSWORD" \
            | helper entry-ensure fora_do_conjunto user >/dev/null 2>&1 || rc_cj=$?
        SEL_ITENS="energia_br systemmonitor"
        # gravar o ponto antes de a fase o zerar — nada está montado de verdade
        desmontar_smb() { PONTO_GRAVADO="$SMB_PONTO"; SMB_PONTO=""; }
        rc_f9=0; fase_arquivos >/dev/null 2>&1 || rc_f9=$?
        # ── cofre: primeiro backup + agente + poda, com ssh/launchctl dublados
        launchctl() { printf "%s\n" "$*" >> "$SB/launchctl.txt"; return 0; }
        mkdir -p "$SB/fbk"
        printf "{\"protected\": false, \"slug\": \"feed1234\"}" > "$SB/fbk/backup.json"
        tar -cf "$SB/fake-backup.tar" -C "$SB/fbk" ./backup.json >/dev/null 2>&1
        cat > "$SB/bin/ssh" <<FIMSSH
#!/bin/sh
caso="\$*"
case "\$caso" in
    *"sudo rm -f /backup/"*) echo poda >> "$SB/poda-vm.txt"; exit 0 ;;
    *"ha backups new"*) exit 0 ;;
    *"ls -t /backup"*)  echo "/backup/feed1234.tar"; exit 0 ;;
    *"sudo cat /backup/feed1234.tar"*) cat "$SB/fake-backup.tar"; exit 0 ;;
    *) exit 0 ;;
esac
FIMSSH
        chmod +x "$SB/bin/ssh"
        cat > "$SB/bin/ssh-keygen" <<FIMKG
#!/bin/sh
exit 0
FIMKG
        chmod +x "$SB/bin/ssh-keygen"
        garantir_chave_ssh() { CHAVE_SSH_PUB="ssh-ed25519 CERCA"; }
        mkdir -p "$SB/Library/Application Support/haos-mac-mini"
        printf "VMIP=127.0.0.2\n" > "$SB/Library/Application Support/haos-mac-mini/vm-guard.env"
        mkdir -p "$SB/Documents/HAOS-backups"
        for n in 1 2 3 4 5 6 7 8; do
            printf x > "$SB/Documents/HAOS-backups/auto-velho-$n.tar"
            touch -t 2601010$n"00" "$SB/Documents/HAOS-backups/auto-velho-$n.tar"
        done
        rc_cf=0; fase_cofre >"$SB/cofre.log" 2>&1 || rc_cf=$?
        n_tars="$(command ls "$SB/Documents/HAOS-backups"/*.tar 2>/dev/null | wc -l | tr -d " ")"
        tem_novo=0
        command ls "$SB/Documents/HAOS-backups"/auto-*feed1234.tar >/dev/null 2>&1 && tem_novo=1
        cofre_arte=0
        [ -x "$SB/Library/Application Support/haos-mac-mini/backup-pull.sh" ] \
            && [ -f "$SB/Library/LaunchAgents/com.haos-mac-mini.backup.plist" ] && cofre_arte=1
        podavm=0; [ -f "$SB/poda-vm.txt" ] && podavm=1
        pkg_ok=0
        if [ -f "${PONTO_GRAVADO:-/nada}/packages/energia_br.yaml" ]; then pkg_ok=1; fi
        dash_ok=0
        if [ -f "${PONTO_GRAVADO:-/nada}/dashboards/custos_br.yaml" ] \
            && grep -q "custos-br:" "${PONTO_GRAVADO:-/nada}/configuration.yaml"; then dash_ok=1; fi
        # Monitor: dashboard escrito, registrado SOB o bloco lovelace que o
        # Custos abriu (caminho insere), e a NIC do dublado substituída no yaml
        mon_ok=0
        if [ -f "${PONTO_GRAVADO:-/nada}/dashboards/monitor_haos.yaml" ] \
            && grep -q "monitor-haos:" "${PONTO_GRAVADO:-/nada}/configuration.yaml" \
            && grep -q "in_enp0s9" "${PONTO_GRAVADO:-/nada}/dashboards/monitor_haos.yaml"; then mon_ok=1; fi
        # exatamente 2 updates: integration-disabled vira ativo; ja-ativa não
        # repete; desligada PELO DONO nunca é tocada; lo não casa o glob _e*
        n_upd="$(grep -c "entity_registry/update" "$SB/req.log")"
        # sem credencial e sem terminal: erro claro
        HA_USER=""; HA_SENHA=""; HAOS_HA_USER=""; HAOS_HA_PASSWORD=""
        rc_sem=0; obter_credencial >/dev/null 2>&1 || rc_sem=$?
        # a sentinela NÃO pode existir em nada que o instalador persiste
        vaz=0
        for alvo in "$LOG_FILE" "$(haos_state_dir)"; do
            [ -e "$alvo" ] || continue
            if grep -r "SENTINELA-9f3a7c" "$alvo" >/dev/null 2>&1; then vaz=1; fi
        done
        printf "c1=%s c2=%s a1=%s a2=%s i=%s fl=%s cj=%s f9=%s pkg=%s dash=%s mon=%s upd=%s cf=%s tars=%s novo=%s arte=%s podavm=%s sem=%s vaz=%s" \
            "$rc_c1" "$rc_c2" "$rc_a1" "$rc_a2" "$rc_i" "$n_flows" "$rc_cj" "$rc_f9" "$pkg_ok" "$dash_ok" "$mon_ok" "$n_upd" "$rc_cf" "$n_tars" "$tem_novo" "$cofre_arte" "$podavm" "$rc_sem" "$vaz"')"
    esp_ha="c1=0 c2=100 a1=0 a2=100 i=0 fl=2 cj=1 f9=0 pkg=1 dash=1 mon=1 upd=2 cf=0 tars=7 novo=1 arte=1 podavm=1 sem=1 vaz=0"
    if [ "$saida_ha" = "$esp_ha" ]; then
        ok "F6–F9 no dublado: conta 0→100, apps 0→100 (repo hash descoberto), conjunto reprova, F9 escreve, sentinela ausente"
    else
        falha "F6–F9 no dublado: esperado '$esp_ha', obtido '$saida_ha'"
    fi
    if grep -q '"p": "/api/onboarding/analytics"' "$sb_ha/req.log"; then
        ok "onboarding: passo analytics concluído SEM ligar envio (corpo vazio no dublado)"
    else
        falha "onboarding: passo analytics não exercitado"
    fi
    if grep -q 'a1b2c3d4_ssh' "$sb_ha/req.log"; then
        ok "prefixo de repositório de terceiro DESCOBERTO (a1b2c3d4), nunca fixado"
    else
        falha "slug community não passou pela descoberta"
    fi
    n_grid="$(grep -c 'stat_energy_from' "$sb_ha/req.log" || true)"
    if grep -q 'energy/save_prefs' "$sb_ha/req.log" && [ "${n_grid:-0}" -ge 1 ]; then
        ok "painel de Energia provisionado via energy/save_prefs (3 postos + preço)"
    else
        falha "energy/save_prefs não exercitado na F9 dublada"
    fi
else
    falha "HA dublado não subiu"
fi
kill "$pid_fake" 2>/dev/null || true
wait "$pid_fake" 2>/dev/null || true
rm -rf "$sb_ha"

# ── F9: conf_estado nunca adivinha ───────────────────────────────────────────
titulo "conf_estado (configuration.yaml)"
# shellcheck disable=SC2016
saida_conf="$(HAOS_INSTALL_LIB=1 "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    d="$(mktemp -d)"
    printf "default_config:\n" > "$d/a.yaml"
    printf "default_config:\nhomeassistant:\n  packages: !include_dir_named packages\n" > "$d/b.yaml"
    printf "homeassistant:\n  name: Casa\n" > "$d/c.yaml"
    printf "lovelace:\n  dashboards:\n    x:\n      filename: dashboards/custos_br.yaml\n" > "$d/d.yaml"
    printf "lovelace:\n  mode: yaml\n" > "$d/e.yaml"
    printf "%s %s %s %s %s %s" \
        "$(conf_estado "$d/a.yaml")" "$(conf_estado "$d/b.yaml")" "$(conf_estado "$d/c.yaml")" \
        "$(conf_lovelace_estado "$d/a.yaml")" "$(conf_lovelace_estado "$d/d.yaml")" "$(conf_lovelace_estado "$d/e.yaml")"
    rm -rf "$d"')"
if [ "$saida_conf" = "append ja estranho append ja estranho" ]; then
    ok "conf_estado e conf_lovelace_estado: append no virgem, 100 no já-feito, nunca adivinham"
else
    falha "conf_estado/lovelace: esperado 'append ja estranho append ja estranho', obtido '$saida_conf'"
fi

# ── componente-zip adulterado é RECUSADO (supply chain) ──────────────────────
# Cobre o instala_componente_zip nas DUAS formas: zip-raiz (HACS) e zip com
# subdiretório de tag (SmartIR) — SHA errado com o tamanho publicado certo.
titulo "componente-zip recusa download adulterado"
sb_hc="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-hc.XXXXXX")"
# shellcheck disable=SC2016
saida_hc="$(HAOS_INSTALL_LIB=1 SB="$sb_hc" "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    HOME="$SB"
    curl() { # dublê: entrega um zip ADULTERADO com o tamanho publicado
        local a out="" prev=""
        for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
        [ -n "$out" ] && dd if=/dev/zero of="$out" bs=1 count=0 seek="$TAM_ALVO" 2>/dev/null
    }
    helper() { return 0; }  # nada de rede real nesta cerca
    garantir_smb_senha() { SMB_SENHA=x; }
    montar_smb() { SMB_PONTO="$SB/mnt"; mkdir -p "$SMB_PONTO"; }
    obter_credencial() { HA_USER=u; HA_SENHA=p; }
    garantir_log
    TAM_ALVO="$HAOS_HACS_BYTES"
    SEL_ITENS="hacs"
    rc1=0; fase_arquivos >/dev/null 2>&1 || rc1=$?
    tem1=0; [ -n "$(command ls "$SB/mnt/custom_components/hacs" 2>/dev/null)" ] && tem1=1
    TAM_ALVO="$HAOS_SMARTIR_BYTES"
    SEL_ITENS="smartir"
    rc2=0; fase_arquivos >/dev/null 2>&1 || rc2=$?
    tem2=0; [ -n "$(command ls "$SB/mnt/custom_components/smartir" 2>/dev/null)" ] && tem2=1
    printf "hacs=%s/%s smartir=%s/%s" "$rc1" "$tem1" "$rc2" "$tem2"')"
if [ "$saida_hc" = "hacs=1/0 smartir=1/0" ]; then
    ok "adulterado recusado nas duas formas (zip-raiz e zip-subdiretório), nada instalado"
else
    falha "componente adulterado: esperado 'hacs=1/0 smartir=1/0', obtido '$saida_hc'"
fi
rm -rf "$sb_hc"

# self-update por ARQUIVO: versão maior atualiza com backup; menor é recusada.
titulo "self-update"
sb_su="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-su.XXXXXX")"
cp haos-install.sh "$sb_su/eu.sh"
# shellcheck disable=SC2016  # idem: expansão no shell filho
saida_su="$(HAOS_INSTALL_LIB=1 SB="$sb_su" "${BASH:-/bin/bash}" -c '
    cd "$SB"
    source ./eu.sh
    sed "s/^HAOS_INSTALL_VERSION=.*/HAOS_INSTALL_VERSION=\"9.9.9\"/" eu.sh > novo.sh
    sed "s/^HAOS_INSTALL_VERSION=.*/HAOS_INSTALL_VERSION=\"0.0.1\"/" eu.sh > velho.sh
    curl() { local a out="" prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done; cp "$SB/$REMOTO" "$out"; }
    BASH_SOURCE=("$SB/eu.sh")
    OP_NOINPUT=1
    REMOTO=novo.sh;  rc1=0; rodar_self_update >/dev/null 2>&1 || rc1=$?
    v_apos="$(grep -m1 "^HAOS_INSTALL_VERSION=" "$SB/eu.sh" | cut -d\" -f2)"
    tem_bak=0; [ -f "$SB/eu.sh.bak" ] && tem_bak=1
    REMOTO=velho.sh; rc2=0; rodar_self_update >/dev/null 2>&1 || rc2=$?
    printf "rc1=%s v=%s bak=%s rc2=%s" "$rc1" "$v_apos" "$tem_bak" "$rc2"')"
if [ "$saida_su" = "rc1=0 v=9.9.9 bak=1 rc2=1" ]; then
    ok "self-update: atualiza com backup e RECUSA downgrade"
else
    falha "self-update: esperado 'rc1=0 v=9.9.9 bak=1 rc2=1', obtido '$saida_su'"
fi
rm -rf "$sb_su"

# diagnóstico de rede: a assinatura reconhece o erro do curl e explica.
titulo "diagnóstico de rede"
# shellcheck disable=SC2016  # idem
saida_dr="$(HAOS_INSTALL_LIB=1 "${BASH:-/bin/bash}" -c '
    source haos-install.sh
    garantir_log
    printf "curl: (6) Could not resolve host: exemplo.invalido\n" >> "$LOG_FILE"
    diagnostico_log 2>&1')"
if printf '%s' "$saida_dr" | grep -qE 'problema de REDE|NETWORK problem'; then
    ok "falha de rede é reconhecida pela assinatura e explicada"
else
    falha "diagnóstico de rede não reconheceu a assinatura do curl"
fi

# ── as teclas do seletor rico ────────────────────────────────────────────────
# Medido em 24/08 depois de o cabeçalho MENTIR a tecla para o dono: no gum
# choose --no-limit quem marca é ESPAÇO; no gum filter (o que tem busca) quem
# marca é TAB — o espaço pertence à caixa de busca. A cerca dirige o gum num
# pty de verdade (expect, timeout 8 s) e confere que a TELA ensina cada tecla.
titulo "teclas do seletor rico"
gum_cerca="${TMPDIR:-/tmp}/gum-0.17.0/gum"
if command -v expect >/dev/null 2>&1 && [ -x "$gum_cerca" ]; then
    GUMBIN="$gum_cerca" expect <<'FIM' >/dev/null 2>&1
set timeout 8
log_user 0
spawn sh -c "$env(GUMBIN) choose --no-limit alfa beta gama > /tmp/haos-gate-gc.txt"
sleep 0.4; send " "; sleep 0.2; send "\r"
expect eof
FIM
    GUMBIN="$gum_cerca" expect <<'FIM' >/dev/null 2>&1
set timeout 8
log_user 0
spawn sh -c "$env(GUMBIN) filter --no-limit alfa beta gama > /tmp/haos-gate-gf.txt"
sleep 0.4; send "\t"; sleep 0.2; send "\r"
expect eof
FIM
    t_choose="$(cat /tmp/haos-gate-gc.txt 2>/dev/null)"
    t_filter="$(cat /tmp/haos-gate-gf.txt 2>/dev/null)"
    rm -f /tmp/haos-gate-gc.txt /tmp/haos-gate-gf.txt
    tecla_ruim=""
    [ "$t_choose" = "alfa" ] || tecla_ruim="$tecla_ruim choose-espaço"
    [ "$t_filter" = "alfa" ] || tecla_ruim="$tecla_ruim filter-tab"
    grep -q 'sel_gum_itens|.*TAB' haos-install.sh || tecla_ruim="$tecla_ruim texto-filter"
    grep -q 'sel_gum_extras|.*ESPAÇO' haos-install.sh || tecla_ruim="$tecla_ruim texto-choose"
    if [ -z "$tecla_ruim" ]; then
        ok "espaço marca no choose, TAB marca no filter — e a tela ensina cada um"
    else
        falha "teclas do seletor:$tecla_ruim"
    fi
else
    ok "expect ou gum em cache indisponíveis — cerca de teclas pulada (roda quando houver)"
fi

# ── o cardápio responde ──────────────────────────────────────────────────────
# O seletor interativo é exercitado pela costura TTY_DEV (arquivo de respostas
# lido em fd único, como um terminal entrega). Quatro cenários: escolha
# explícita, padrões por vazio, inválido repete, e a opção 0 repetindo a
# última seleção salva.
titulo "cardápio"
sb_card="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-card.XXXXXX")"
resp_card="$sb_card/respostas.txt"
# A saída é CAPTURADA antes de qualquer grep: sob o pipefail deste portão,
# `| grep -q` fecha o cano no primeiro match, o bash leva SIGPIPE (141) e o
# cenário registraria falha APESAR do acerto — aconteceu na primeira rodada.
card_roda() { # <respostas printf> -> stdout do dry-run em $CARD_SAIDA
    printf '%b' "$1" > "$resp_card"
    # shellcheck disable=SC2002
    CARD_SAIDA="$(cat haos-install.sh | HOME="$sb_card" TTY_DEV="$resp_card" HAOS_USE_GUM=0 \
        "${BASH:-/bin/bash}" -s -- --dry-run 2>&1)" || true
}
card_ruim=""
card_roda '2\na,b\n1\n'
printf '%s' "$CARD_SAIDA" | grep -q 'Conectado' || card_ruim="$card_ruim escolha-explicita"
card_roda '\n\n\n'
printf '%s' "$CARD_SAIDA" | grep -qE 'Casa|haos_casa' || card_ruim="$card_ruim padroes-por-vazio"
card_roda '9\n1\n\n\n'
[ "$(printf '%s' "$CARD_SAIDA" | grep -cE 'não entendi|did not understand')" = "1" ] || card_ruim="$card_ruim invalido-repete"
mkdir -p "$sb_card/.config/haos-mac-mini"
printf 'degrau=haos_conectado\nextras=ferramentas\nvm=vm_minimo\nvm_nome=HomeAssistant\n' > "$sb_card/.config/haos-mac-mini/state"
card_roda '0\n'
printf '%s' "$CARD_SAIDA" | grep -q 'vm_minimo' || card_ruim="$card_ruim opcao-0-ultima"
rm -rf "$sb_card"
if [ -z "$card_ruim" ]; then
    ok "cardápio: escolha, padrões, inválido e repetição da última — 4 cenários"
else
    falha "cardápio falhou em:$card_ruim"
fi

# ── dry-run não escreve NADA ─────────────────────────────────────────────────
# Nem log, nem estado: a promessa "--dry-run: nada foi escrito" é conferida por
# snapshot de um $HOME sintético (a costura HAOS_STATE_DIR/HOME é a do B-7).
titulo "dry-run é read-only"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/haos-gate-sb.XXXXXX")"
# shellcheck disable=SC2002
cat haos-install.sh | HOME="$sandbox" "${BASH:-/bin/bash}" -s -- \
    --dry-run --profile haos_casa --no-input >/dev/null 2>&1 || true
escritos="$(find "$sandbox" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "$sandbox"
if [ "${escritos:-1}" = "0" ]; then
    ok "dry-run não escreveu nada num \$HOME sintético"
else
    falha "dry-run escreveu $escritos arquivo(s) no \$HOME"
fi

# EXECUTAR a camada visual, não só analisá-la. `bash -n` não acusa função que
# não existe, e o shellcheck também não quando ela é chamada de outra função.
# Achado em 23/08: uma reescrita apagou _hide/_show/ha_show_cursor e todo o
# portão passou verde enquanto a demo cuspia "command not found" em cada linha.
titulo "a camada visual executa"
saida_err="$(HAOS_NO_ANIM=1 /bin/bash tools/ui-demo.sh --no-anim 2>&1 >/dev/null)"
if [ -z "$saida_err" ]; then
    ok "ui-demo.sh roda sem nada em stderr"
else
    falha "ui-demo.sh escreveu em stderr:"
    printf '%s\n' "$saida_err" | head -6 | sed 's/^/          /' >&2
fi

# Toda função chamada pela lib tem de existir depois de sourceá-la.
faltando="$(/bin/bash -c '
    source lib/haos-ui.sh >/dev/null 2>&1
    for f in $(grep -oE "\b(_hide|_show|ha_[a-z_]+)\b" lib/haos-ui.sh | sort -u); do
        declare -F "$f" >/dev/null 2>&1 || printf "%s " "$f"
    done')"
if [ -z "$faltando" ]; then
    ok "toda função que a lib chama está definida"
else
    falha "funções chamadas e não definidas: $faltando"
fi

# ── resultado ────────────────────────────────────────────────────────────────
printf '\n'
if [ "$FALHAS" = "0" ]; then
    printf 'RESULTADO: portão limpo\n'; exit 0
fi
printf 'RESULTADO: %s checagem(ns) falharam\n' "$FALHAS" >&2; exit 1
