#!/usr/bin/env bash
# =============================================================================
# embed.sh — copia catalog/catalog.bash para dentro do haos-install.sh.
#
# O instalador é autocontido: distribuído por `curl | bash`, não pode depender
# de arquivo ao lado. Mas a fonte de verdade tem de continuar sendo UMA, senão
# as duas divergem em silêncio.
#
# A solução é mecânica: esta ferramenta copia, o verify.sh compara, e o CI
# reprova a divergência. Editar o bloco embutido à mão é o erro que isto existe
# para tornar detectável.
#
#   ./tools/embed.sh           embute
#   ./tools/embed.sh --check   só confere, não escreve (exit 3 se divergir)
# =============================================================================
set -Eeuo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
CATALOGO="$RAIZ/catalog/catalog.bash"
INSTALADOR="$RAIZ/haos-install.sh"
ABRE="# >>> CATALOGO EMBUTIDO >>>"
FECHA="# <<< CATALOGO EMBUTIDO <<<"

[ -f "$CATALOGO" ]   || { echo "[ERRO] catálogo ausente: $CATALOGO" >&2; exit 4; }
[ -f "$INSTALADOR" ] || { echo "[ERRO] instalador ausente: $INSTALADOR" >&2; exit 4; }

grep -qF "$ABRE"  "$INSTALADOR" || { echo "[ERRO] instalador sem marcador de abertura" >&2; exit 3; }
grep -qF "$FECHA" "$INSTALADOR" || { echo "[ERRO] instalador sem marcador de fechamento" >&2; exit 3; }

atual="$(mktemp)"; novo="$(mktemp)"
trap 'rm -f "$atual" "$novo"' EXIT

awk -v a="$ABRE" -v f="$FECHA" '$0==a{p=1;next} $0==f{p=0} p' "$INSTALADOR" > "$atual"

if [ "${1:-}" = "--check" ]; then
    if diff -q "$atual" "$CATALOGO" >/dev/null 2>&1; then
        echo "[OK] cópia embutida idêntica ao catalog.bash"
        exit 0
    fi
    echo "[ERRO] cópia embutida DIVERGE — rode ./tools/embed.sh" >&2
    diff "$CATALOGO" "$atual" | head -20 >&2
    exit 3
fi

awk -v a="$ABRE" -v f="$FECHA" -v cat="$CATALOGO" '
    $0==a { print; while ((getline l < cat) > 0) print l; close(cat); skip=1; next }
    $0==f { skip=0 }
    !skip { print }
' "$INSTALADOR" > "$novo"

# nunca escrever direto: gera, valida a sintaxe, só então troca
bash -n "$novo" || { echo "[ERRO] resultado não passa em bash -n — nada foi escrito" >&2; exit 3; }
cat "$novo" > "$INSTALADOR"
n="$(wc -l < "$CATALOGO" | tr -d ' ')"
echo "[OK] catálogo embutido ($n linhas)"
