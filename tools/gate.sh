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

# ── resultado ────────────────────────────────────────────────────────────────
printf '\n'
if [ "$FALHAS" = "0" ]; then
    printf 'RESULTADO: portão limpo\n'; exit 0
fi
printf 'RESULTADO: %s checagem(ns) falharam\n' "$FALHAS" >&2; exit 1
