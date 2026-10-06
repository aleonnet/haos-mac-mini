#!/usr/bin/env bash
# =============================================================================
# pacotes-arnes.sh — sobe um Home Assistant de verdade com os packages DO
#                    REPOSITÓRIO e roda contract/pacotes.py contra ele.
#
# O portão confere que o instalador ESCREVE os packages. Isto confere que eles
# FAZEM A CONTA: referências que existem, soma que não publica valor parcial,
# fatura reproduzida ao centavo, campo que sobrevive a reinício, ciclo que
# fecha na data da leitura. O mesmo comando no Mac e no CI.
#
#   ./tools/pacotes-arnes.sh                  versão fixada (HAOS_REF_CORE)
#   ./tools/pacotes-arnes.sh --ha stable      outra tag da imagem
#   ./tools/pacotes-arnes.sh --manter         não desmonta o contêiner no fim
#
# Exit: 0 PACOTES OK · 2 uso · 3 alguma garantia quebrou · 4 dependência
#       ausente · 10 o Core não subiu
# =============================================================================
set -Eeuo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
IMAGEM_BASE="ghcr.io/home-assistant/home-assistant"
PORTA="${PACOTES_PORTA:-18123}"
NOME="haos-pacotes-arnes-$$"
MANTER=0
VERSAO=""

while [ $# -gt 0 ]; do
    case "$1" in
        --ha) VERSAO="${2:-}"; shift 2 || { echo "[ERRO] --ha exige a tag" >&2; exit 2; } ;;
        --manter) MANTER=1; shift ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "[ERRO] opção desconhecida: $1" >&2; exit 2 ;;
    esac
done

# A versão fixada tem UMA fonte: a mesma constante que o instalador declara.
if [ -z "$VERSAO" ]; then
    VERSAO="$(sed -n 's/^HAOS_REF_CORE="\([^"]*\)".*/\1/p' "$RAIZ/haos-install.sh" | head -1)"
fi
[ -n "$VERSAO" ] || { echo "[ERRO] não achei HAOS_REF_CORE no instalador" >&2; exit 4; }

for dep in docker python3 curl; do
    command -v "$dep" >/dev/null 2>&1 || { echo "[ERRO] dependência ausente: $dep" >&2; exit 4; }
done
docker info >/dev/null 2>&1 || { echo "[ERRO] o Docker não está respondendo" >&2; exit 4; }
python3 -c 'import yaml' 2>/dev/null || { echo "[ERRO] PyYAML ausente: pip install pyyaml" >&2; exit 4; }

CFG="$(mktemp -d)"
limpa() {
    rm -rf "$CFG"
    if [ "$MANTER" = "1" ]; then
        echo "[OK]    contêiner mantido: $NOME (http://127.0.0.1:$PORTA) — remova com: docker rm -f $NOME"
    else
        docker rm -f "$NOME" >/dev/null 2>&1 || true
    fi
}
trap limpa EXIT

# O /config que o instalador deixa numa instância: a configuração padrão do
# Home Assistant mais a linha que carrega os packages.
mkdir -p "$CFG/packages"
cp "$RAIZ"/packages/*.yaml "$CFG/packages/"
cat > "$CFG/configuration.yaml" <<'YAML'
default_config:

homeassistant:
  packages: !include_dir_named packages
YAML

IMAGEM="$IMAGEM_BASE:$VERSAO"
echo "alvo: $IMAGEM"
docker pull --quiet "$IMAGEM" >/dev/null

# create + cp em vez de -v: montado, o Core (root) deixaria no hospedeiro
# arquivos que o usuário do CI não consegue apagar.
docker create --name "$NOME" -p "127.0.0.1:$PORTA:8123" "$IMAGEM" >/dev/null
docker cp "$CFG/." "$NOME:/config/"
docker start "$NOME" >/dev/null

de_pe=0
for _ in $(seq 1 180); do
    if curl -sf "http://127.0.0.1:$PORTA/manifest.json" >/dev/null 2>&1; then de_pe=1; break; fi
    sleep 1
done
if [ "$de_pe" != "1" ]; then
    echo "[ERRO] o Core não respondeu em 180s" >&2
    docker logs "$NOME" 2>&1 | tail -40 >&2
    exit 10
fi

rc=0
python3 "$RAIZ/contract/pacotes.py" --url "http://127.0.0.1:$PORTA" --bootstrap || rc=$?

if [ "$rc" != "0" ]; then
    echo
    echo "--- o que o Core registrou sobre os packages (últimas linhas) ---"
    docker logs "$NOME" 2>&1 | grep -iE "package|invalid config|template|utility_meter|input_" | tail -25 || true
fi
exit "$rc"
