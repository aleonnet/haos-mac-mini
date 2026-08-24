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
for f in contract/*.py; do
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
    CARD_SAIDA="$(cat haos-install.sh | HOME="$sb_card" TTY_DEV="$resp_card" \
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
