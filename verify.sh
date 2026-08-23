#!/bin/bash
# =============================================================================
# verify.sh — cerca do catálogo.
#
# Confere SCHEMA e CONTEÚDO. Conferir só conteúdo deixa passar troca de ordem de
# campo, que é bug silencioso: a linha continua com o mesmo número de campos e
# o significado muda.
#
# Quando o haos-install.sh existir, também compara a cópia embutida nele contra
# o catalog/catalog.bash — deriva entre os dois é erro, não aviso.
#
#   ./verify.sh            confere tudo
#   ./verify.sh --quiet    só o resultado e as falhas
#
# Exit: 0 tudo certo · 3 falha de validação · 4 dependência ausente
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CATALOGO="$RAIZ/catalog/catalog.bash"
INSTALADOR="$RAIZ/haos-install.sh"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

FALHAS=0
CHECAGENS=0

ok()    { CHECAGENS=$((CHECAGENS+1)); [ "$QUIET" = "1" ] || printf '[OK]    %s\n' "$1"; }
falha() { CHECAGENS=$((CHECAGENS+1)); FALHAS=$((FALHAS+1)); printf '[ERRO]  %s\n' "$1" >&2; }
info()  { [ "$QUIET" = "1" ] || printf '[*]     %s\n' "$1"; }

[ -f "$CATALOGO" ] || { printf '[ERRO]  catálogo não encontrado: %s\n' "$CATALOGO" >&2; exit 4; }

# bash -n antes de source: catálogo com erro de sintaxe derruba o verificador
bash -n "$CATALOGO" || { printf '[ERRO]  catalog.bash não passa em bash -n\n' >&2; exit 3; }
# shellcheck source=catalog/catalog.bash
source "$CATALOGO"

# ── util ─────────────────────────────────────────────────────────────────────
# n_campos <linha> — conta campos separados por "|"
n_campos() { local s="$1"; local n=1; local resto="$s"; while [ "${resto#*|}" != "$resto" ]; do resto="${resto#*|}"; n=$((n+1)); done; echo "$n"; }
# tem <agulha> <palheiro-separado-por-espaço>
tem() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

# ── 1. SCHEMA: número de campos por tabela ───────────────────────────────────
info "schema das tabelas"
verifica_schema() {
    local nome="$1" esperado="$2"; shift 2
    local linha n erros=0 i=0
    for linha in "$@"; do
        i=$((i+1))
        n="$(n_campos "$linha")"
        if [ "$n" != "$esperado" ]; then
            falha "$nome linha $i: $n campos, esperado $esperado — \"${linha%%|*}...\""
            erros=$((erros+1))
        fi
    done
    [ "$erros" = "0" ] && ok "$nome — $# linhas, todas com $esperado campos"
}
verifica_schema CATEGORY_DB    3 "${CATEGORY_DB[@]}"
verifica_schema ITEM_DB       12 "${ITEM_DB[@]}"
verifica_schema ITEM_META_DB   3 "${ITEM_META_DB[@]}"
verifica_schema VM_PROFILE_DB  5 "${VM_PROFILE_DB[@]}"
verifica_schema HAOS_PROFILE_DB 3 "${HAOS_PROFILE_DB[@]}"
verifica_schema NAO_APLICA_DB  2 "${NAO_APLICA_DB[@]}"
verifica_schema HAOS_INTRINSIC_DB 2 "${HAOS_INTRINSIC_DB[@]}"
verifica_schema ONBOARDING_DB  2 "${ONBOARDING_DB[@]}"

# ── 2. catálogo de categorias ────────────────────────────────────────────────
info "coerência de categorias"
CATS=""
for r in "${CATEGORY_DB[@]}"; do CATS="$CATS ${r%%|*}"; done

itens_sem_cat=0
for r in "${ITEM_DB[@]}"; do
    IFS='|' read -r id cat _ <<< "$r"
    tem "$cat" "$CATS" || { falha "item '$id': categoria '$cat' não existe no CATEGORY_DB"; itens_sem_cat=$((itens_sem_cat+1)); }
done
[ "$itens_sem_cat" = "0" ] && ok "todas as categorias dos itens existem"

# toda categoria é alcançável: ou está num degrau, ou é ortogonal
degrau_cats=""
for r in "${HAOS_PROFILE_DB[@]}"; do IFS='|' read -r _ _ cs <<< "$r"; degrau_cats="$degrau_cats $cs"; done
orfas=0
for c in $CATS; do
    tem "$c" "$degrau_cats" && continue
    tem "$c" "${ORTOGONAL_DB[*]}" && continue
    falha "categoria '$c' não está em nenhum degrau nem em ORTOGONAL_DB — inalcançável"
    orfas=$((orfas+1))
done
[ "$orfas" = "0" ] && ok "toda categoria é alcançável por degrau ou ortogonal"

# degrau e ortogonal não podem se sobrepor
sobrepostas=0
for c in "${ORTOGONAL_DB[@]}"; do
    tem "$c" "$degrau_cats" && { falha "categoria '$c' é ortogonal E está num degrau — a escada arrastaria"; sobrepostas=$((sobrepostas+1)); }
done
[ "$sobrepostas" = "0" ] && ok "nenhuma categoria é degrau e ortogonal ao mesmo tempo"

# ── 3. ids únicos ────────────────────────────────────────────────────────────
info "unicidade de ids"
dups="$(for r in "${ITEM_DB[@]}"; do echo "${r%%|*}"; done | sort | uniq -d)"
if [ -n "$dups" ]; then falha "ids duplicados no ITEM_DB: $(echo $dups)"; else ok "ids do ITEM_DB são únicos"; fi

IDS=""
for r in "${ITEM_DB[@]}"; do IDS="$IDS ${r%%|*}"; done

# ── 4. slug obrigatório para app ─────────────────────────────────────────────
info "slug de app"
sem_slug=0
for r in "${ITEM_DB[@]}"; do
    IFS='|' read -r id cat rot origem slug resto <<< "$r"
    case "$origem" in
        oficial|community)
            [ "$slug" = "-" ] && { falha "item '$id' tem origem '$origem' mas slug '-' — a F7 não saberia o que instalar"; sem_slug=$((sem_slug+1)); }
            case "$slug" in
                *_*) : ;;
                -)   : ;;
                *)   falha "item '$id': slug '$slug' não tem a forma <repo>_<app>" ; sem_slug=$((sem_slug+1)) ;;
            esac
            ;;
        *)
            [ "$slug" != "-" ] && { falha "item '$id' não é app (origem '$origem') mas declara slug '$slug'"; sem_slug=$((sem_slug+1)); }
            ;;
    esac
done
[ "$sem_slug" = "0" ] && ok "todo app tem slug <repo>_<app>, e só apps têm slug"

# ── 5. preferred pertence a setup ────────────────────────────────────────────
info "preferred ⊂ setup"
pref_ruim=0
for r in "${ITEM_DB[@]}"; do
    IFS='|' read -r id cat rot origem slug padrao disc setup pref resto <<< "$r"
    [ "$pref" = "-" ] && continue
    tem "$pref" "$setup" || { falha "item '$id': preferred '$pref' não está em setup ('$setup')"; pref_ruim=$((pref_ruim+1)); }
done
[ "$pref_ruim" = "0" ] && ok "todo preferred pertence ao conjunto setup"

# ── 6. requires aponta para algo real ────────────────────────────────────────
info "requires resolvível"
# alvos aceitos além de ids do ITEM_DB: apps gerenciados pelo HA e deps do core
EXTERNOS="mosquitto matter_server openthread_border_router application_credentials"
req_ruim=0
for r in "${ITEM_DB[@]}"; do
    IFS='|' read -r id c1 c2 c3 c4 c5 c6 c7 c8 requires resto <<< "$r"
    [ "$requires" = "-" ] && continue
    for dep in $requires; do
        alvo="${dep%%:*}"
        tem "$alvo" "$IDS" && continue
        tem "$alvo" "$EXTERNOS" && continue
        falha "item '$id': requires '$alvo' não é id do catálogo nem dependência externa conhecida"
        req_ruim=$((req_ruim+1))
    done
done
[ "$req_ruim" = "0" ] && ok "todo requires resolve para id do catálogo ou dependência conhecida"

# ── 7. quem escreve em /config precisa de veículo ────────────────────────────
# Achado da banca (R7): os packages e o HACS escrevem em /config e estavam com
# requires vazio, escondendo o tamanho real do bloqueio da F7.
info "quem escreve em /config declara veículo"
ESCREVEM_CONFIG="energia_br gas_br agua_br hacs"
sem_veiculo=0
for id in $ESCREVEM_CONFIG; do
    tem "$id" "$IDS" || continue
    for r in "${ITEM_DB[@]}"; do
        [ "${r%%|*}" = "$id" ] || continue
        IFS='|' read -r _ _ _ _ _ _ _ _ _ requires flags _ <<< "$r"
        # veículo = requires com app de acesso a arquivo, OU flag declarando
        # veículo de escrita: samba (monta /config) ou o terminal community
        veiculo=0
        for dep in $requires; do
            case "${dep%%:*}" in samba|advanced_ssh|file_editor) veiculo=1 ;; esac
        done
        if [ "$veiculo" = "0" ]; then
            falha "item '$id' escreve em /config e não declara veículo (samba, advanced_ssh ou file_editor em requires)"
            sem_veiculo=$((sem_veiculo+1))
        fi
    done
done
[ "$sem_veiculo" = "0" ] && ok "itens que escrevem em /config declaram como chegam lá"

# ── 8. ITEM_META_DB aponta para itens reais ──────────────────────────────────
info "ITEM_META_DB"
meta_ruim=0
for r in "${ITEM_META_DB[@]}"; do
    mid="${r%%|*}"
    tem "$mid" "$IDS" || { falha "ITEM_META_DB: '$mid' não existe no ITEM_DB"; meta_ruim=$((meta_ruim+1)); }
done
[ "$meta_ruim" = "0" ] && ok "todo id do ITEM_META_DB existe no ITEM_DB"

# ── 9. NAO_APLICA não colide com ITEM_DB ─────────────────────────────────────
info "NAO_APLICA_DB"
colisao=0
for r in "${NAO_APLICA_DB[@]}"; do
    nid="${r%%|*}"
    tem "$nid" "$IDS" && { falha "'$nid' está em NAO_APLICA_DB E no ITEM_DB"; colisao=$((colisao+1)); }
done
[ "$colisao" = "0" ] && ok "nada está simultaneamente ofertado e bloqueado"

# ── 10. piso não se repete no ITEM_DB ────────────────────────────────────────
# O piso é o que a instalação já cria. Ofertar de novo é duplicar.
info "piso × ITEM_DB"
PISO="${DEFAULT_CONFIG_DB[*]}"
for r in "${HAOS_INTRINSIC_DB[@]}" "${ONBOARDING_DB[@]}"; do PISO="$PISO ${r%%|*}"; done
dup_piso=0
for id in $IDS; do
    tem "$id" "$PISO" && { falha "item '$id' está no ITEM_DB E no piso — o instalador duplicaria"; dup_piso=$((dup_piso+1)); }
done
[ "$dup_piso" = "0" ] && ok "nenhum item do ITEM_DB repete o piso"

# ── 11. cópia embutida no instalador ─────────────────────────────────────────
info "cópia embutida"
if [ ! -f "$INSTALADOR" ]; then
    ok "haos-install.sh ainda não existe — comparação pulada (esperado nesta fase)"
else
    tmp="$(mktemp)"
    # extrai o bloco entre os marcadores do instalador
    awk '/^# >>> CATALOGO EMBUTIDO >>>$/{f=1;next} /^# <<< CATALOGO EMBUTIDO <<<$/{f=0} f' "$INSTALADOR" > "$tmp"
    if [ ! -s "$tmp" ]; then
        falha "instalador existe mas não tem o bloco CATALOGO EMBUTIDO"
    elif diff -q "$tmp" "$CATALOGO" >/dev/null 2>&1; then
        ok "cópia embutida idêntica ao catalog.bash"
    else
        falha "cópia embutida DIVERGE do catalog.bash:"
        diff "$CATALOGO" "$tmp" | head -20 >&2
    fi
    rm -f "$tmp"
fi

# ── resultado ────────────────────────────────────────────────────────────────
echo ""
if [ "$FALHAS" = "0" ]; then
    printf 'RESULTADO: %s checagens, 0 falhas\n' "$CHECAGENS"
    exit 0
fi
printf 'RESULTADO: %s checagens, %s FALHA(S)\n' "$CHECAGENS" "$FALHAS" >&2
exit 3
