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
INSTALADOR="$RAIZ/haos-install.sh"

# Cada bloco: <marcador>|<arquivo de origem>[|var:<NOME_DA_VAR>].
# Sem sufixo o conteúdo entra como BASH (shebang e `set` removidos — numa cópia
# embutida passariam a valer para o instalador). Com `var:` o conteúdo entra
# VERBATIM dentro de um heredoc quoted atribuído à variável — é assim que
# python e yaml viajam dentro de um script bash sem virar código dele.
BLOCOS="CATALOGO|catalog/catalog.bash UI|lib/haos-ui.sh HELPER|lib/ha-api.py|var:HAOS_HELPER_PY PKG_ENERGIA|packages/energia_br.yaml|var:HAOS_PKG_ENERGIA PKG_GAS|packages/gas_br.yaml|var:HAOS_PKG_GAS PKG_AGUA|packages/agua_br.yaml|var:HAOS_PKG_AGUA DASH_CUSTOS|dashboards/custos_br.yaml|var:HAOS_DASH_CUSTOS"

[ -f "$INSTALADOR" ] || { echo "[ERRO] instalador ausente: $INSTALADOR" >&2; exit 4; }

# Completude: um packages/*.yaml novo SEM bloco viajaria fora do instalador em
# silêncio — cerca da banca.
for p in "$RAIZ"/packages/*.yaml; do
    case " $BLOCOS " in
        *"|packages/$(basename "$p")|"*) ;;
        *) echo "[ERRO] packages/$(basename "$p") sem bloco em BLOCOS — o instalador não o carregaria" >&2; exit 3 ;;
    esac
done

tmp_a="$(mktemp)"; tmp_b="$(mktemp)"; tmp_c="$(mktemp)"
trap 'rm -f "$tmp_a" "$tmp_b" "$tmp_c"' EXIT

# prepara <origem> <modo> <nome> -> stdout
prepara() {
    if [ "${2%%:*}" = "var" ]; then
        # shellcheck disable=SC2016  # o $( ) é para o INSTALADOR expandir, não aqui
        printf '%s=$(cat <<'\''FIM_EMB_%s'\''\n' "${2#var:}" "$3"
        cat "$1"
        printf 'FIM_EMB_%s\n)\n' "$3"
    else
        grep -vE '^#!/|^set ' "$1"
    fi
}

falhou=0
for bloco in $BLOCOS; do
    nome="${bloco%%|*}"; resto="${bloco#*|}"
    rel="${resto%%|*}"
    modo="bash"; case "$resto" in *"|"*) modo="${resto#*|}" ;; esac
    origem="$RAIZ/$rel"
    abre="# >>> $nome EMBUTIDO >>>"
    fecha="# <<< $nome EMBUTIDO <<<"

    [ -f "$origem" ] || { echo "[ERRO] origem ausente: $origem" >&2; exit 4; }
    grep -qF "$abre"  "$INSTALADOR" || { echo "[ERRO] sem marcador de abertura de $nome" >&2; exit 3; }
    grep -qF "$fecha" "$INSTALADOR" || { echo "[ERRO] sem marcador de fechamento de $nome" >&2; exit 3; }

    awk -v a="$abre" -v f="$fecha" '$0==a{p=1;next} $0==f{p=0} p' "$INSTALADOR" > "$tmp_a"
    prepara "$origem" "$modo" "$nome" > "$tmp_b"

    if [ "${1:-}" = "--check" ]; then
        if diff -q "$tmp_a" "$tmp_b" >/dev/null 2>&1; then
            echo "[OK] $nome embutido idêntico a $rel"
        else
            echo "[ERRO] $nome embutido DIVERGE de $rel — rode ./tools/embed.sh" >&2
            diff "$tmp_b" "$tmp_a" | head -12 >&2
            falhou=1
        fi
        continue
    fi

    awk -v a="$abre" -v f="$fecha" -v src="$tmp_b" '
        $0==a { print; while ((getline l < src) > 0) print l; close(src); skip=1; next }
        $0==f { skip=0 }
        !skip { print }
    ' "$INSTALADOR" > "$tmp_c"
    bash -n "$tmp_c" || { echo "[ERRO] resultado não passa em bash -n — nada foi escrito" >&2; exit 3; }
    cat "$tmp_c" > "$INSTALADOR"
    echo "[OK] $nome embutido ($(wc -l < "$tmp_b" | tr -d ' ') linhas de $rel)"
done
[ "$falhou" = "0" ] || exit 3
