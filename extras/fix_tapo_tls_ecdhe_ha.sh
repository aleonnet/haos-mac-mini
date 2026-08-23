#!/usr/bin/env bash
set -Eeuo pipefail

# fix_tapo_tls_ecdhe_ha.sh
#
# Workaround idempotente para o erro:
#   SSLV3_ALERT_HANDSHAKE_FAILURE
# em câmeras Tapo recentes usadas pela integração oficial TP-Link/Tapo
# do Home Assistant quando o python-kasa/SslAesTransport não oferece
# cifras ECDHE-RSA aceitas pelo firmware.
#
# Referências:
# - https://github.com/python-kasa/python-kasa/issues/1724
# - https://github.com/home-assistant/core/issues/164045
#
# O script:
# - NÃO assume versão/caminho do Python;
# - descobre o sslaestransport.py dentro do container "homeassistant";
# - verifica se o upstream já contém as cifras ECDHE;
# - se já contém, NÃO altera nada;
# - se a estrutura upstream mudou, aborta sem tocar no arquivo;
# - cria backup persistente em /config antes de qualquer alteração;
# - valida sintaxe Python e as cifras com OpenSSL antes de gravar;
# - é idempotente;
# - reinicia o Core somente quando necessário.
#
# Uso:
#   chmod +x /config/fix_tapo_tls_ecdhe_ha.sh
#   /config/fix_tapo_tls_ecdhe_ha.sh
#
# Opções:
#   --dry-run        Apenas diagnostica; não altera nem reinicia.
#   --no-restart     Aplica o patch, mas não reinicia o Core.
#   --force-restart  Reinicia o Core mesmo se o patch já estiver presente.
#   -h, --help       Mostra esta ajuda.

SCRIPT_VERSION="1.0.0"
CONTAINER_NAME="homeassistant"

DRY_RUN=0
NO_RESTART=0
FORCE_RESTART=0

usage() {
  # O cabeçalho de comentário termina na linha 35; ir além imprime código.
  sed -n '4,35p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-restart)
      NO_RESTART=1
      ;;
    --force-restart)
      FORCE_RESTART=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERRO] Opção desconhecida: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

echo "============================================================"
echo " Tapo TLS/ECDHE workaround para Home Assistant"
echo " Script v${SCRIPT_VERSION}"
echo "============================================================"
echo

if ! command -v docker >/dev/null 2>&1; then
  cat >&2 <<'EOF'
[ERRO] O comando 'docker' não está disponível neste terminal.

No Home Assistant OS, se estiver usando o app
"Advanced SSH & Web Terminal":

  Settings -> Apps -> Advanced SSH & Web Terminal
  -> Protection mode: OFF
  -> Restart

Depois execute este script novamente.

Após concluir, você pode reativar o Protection mode.
EOF
  exit 3
fi

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  cat >&2 <<EOF
[ERRO] Não foi possível acessar o container '${CONTAINER_NAME}'.

Se a mensagem indicar "PROTECTION MODE ENABLED", desative
temporariamente o Protection mode do Advanced SSH & Web Terminal
e reinicie o app.
EOF
  exit 4
fi

echo "[1/4] Inspecionando python-kasa e SslAesTransport..."

set +e
PATCH_OUTPUT="$(
  docker exec -i \
    -e TAPO_TLS_DRY_RUN="$DRY_RUN" \
    "$CONTAINER_NAME" python3 - <<'PY'
import ast
import hashlib
import importlib.metadata
import os
import shutil
import ssl
import stat
import sys
import tempfile
from pathlib import Path

WANTED = [
    "ECDHE-RSA-AES256-GCM-SHA384",
    "ECDHE-RSA-AES128-GCM-SHA256",
]
BASELINE = "AES256-GCM-SHA384"
DRY_RUN = os.environ.get("TAPO_TLS_DRY_RUN") == "1"

def fail(msg, code=10):
    print(f"[ERRO] {msg}")
    print("TAPO_TLS_RESULT=error")
    raise SystemExit(code)

try:
    import kasa
except Exception as exc:
    fail(f"Não foi possível importar python-kasa: {exc}")

try:
    kasa_version = importlib.metadata.version("python-kasa")
except Exception:
    kasa_version = "desconhecida"

path = Path(kasa.__file__).resolve().parent / "transports" / "sslaestransport.py"

print(f"python-kasa: {kasa_version}")
print(f"arquivo:      {path}")

if not path.exists():
    fail("sslaestransport.py não foi encontrado; nada foi alterado.")

source = path.read_text(encoding="utf-8")
sha_before = hashlib.sha256(source.encode("utf-8")).hexdigest()

try:
    tree = ast.parse(source, filename=str(path))
except SyntaxError as exc:
    fail(f"O arquivo atual não pode ser parseado: {exc}")

ssl_class = None
for node in tree.body:
    if isinstance(node, ast.ClassDef) and node.name == "SslAesTransport":
        ssl_class = node
        break

if ssl_class is None:
    fail("A classe SslAesTransport não existe mais neste arquivo; upstream mudou.")

cipher_list = None
for node in ssl_class.body:
    target_name = None
    value = None

    if isinstance(node, ast.Assign):
        if len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            target_name = node.targets[0].id
            value = node.value
    elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
        target_name = node.target.id
        value = node.value

    if target_name != "CIPHERS" or value is None:
        continue

    # Esperado: CIPHERS = ":".join([ ... ])
    if (
        isinstance(value, ast.Call)
        and isinstance(value.func, ast.Attribute)
        and value.func.attr == "join"
        and len(value.args) == 1
        and isinstance(value.args[0], (ast.List, ast.Tuple))
    ):
        cipher_list = value.args[0]
        break

if cipher_list is None:
    fail(
        "A definição SslAesTransport.CIPHERS mudou e não corresponde ao formato "
        "esperado. Nada foi alterado."
    )

current = []
for elt in cipher_list.elts:
    if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
        current.append(elt.value)
    else:
        fail(
            "SslAesTransport.CIPHERS contém expressão dinâmica; "
            "o patch automático foi recusado por segurança."
        )

print("CIPHERS atuais:")
for cipher in current:
    print(f"  - {cipher}")

missing = [cipher for cipher in WANTED if cipher not in current]

if not missing:
    print()
    print("[OK] As duas cifras ECDHE já estão presentes.")
    print("     Nenhuma alteração é necessária.")
    print(f"SHA-256 atual: {sha_before}")
    print("TAPO_TLS_RESULT=already_patched")
    raise SystemExit(0)

if BASELINE not in current:
    fail(
        f"A cifra-base '{BASELINE}' não existe mais em CIPHERS. "
        "A implementação upstream mudou; patch automático abortado."
    )

if not cipher_list.elts:
    fail("A lista CIPHERS está vazia; patch automático abortado.")

# Determina o ponto de inserção pela AST, não por caminho/linha hardcoded.
first_elt = cipher_list.elts[0]
insert_line_index = first_elt.lineno - 1
lines = source.splitlines(keepends=True)

if insert_line_index < 0 or insert_line_index >= len(lines):
    fail("Não foi possível determinar com segurança o ponto de inserção.")

first_line = lines[insert_line_index]
indent = first_line[: len(first_line) - len(first_line.lstrip())]
newline = "\r\n" if first_line.endswith("\r\n") else "\n"

insert_text = "".join(
    f'{indent}"{cipher}",{newline}'
    for cipher in missing
)

new_lines = lines[:insert_line_index] + [insert_text] + lines[insert_line_index:]
new_source = "".join(new_lines)

# Valida sintaxe ANTES de tocar no arquivo.
try:
    compile(new_source, str(path), "exec")
except SyntaxError as exc:
    fail(f"O conteúdo proposto falhou na validação de sintaxe: {exc}")

# Reparse e confirma que o conteúdo resultante inclui as cifras desejadas.
try:
    new_tree = ast.parse(new_source, filename=str(path))
except SyntaxError as exc:
    fail(f"O conteúdo proposto não pôde ser parseado: {exc}")

new_ciphers = None
for node in new_tree.body:
    if isinstance(node, ast.ClassDef) and node.name == "SslAesTransport":
        for child in node.body:
            value = None
            name = None
            if isinstance(child, ast.Assign):
                if len(child.targets) == 1 and isinstance(child.targets[0], ast.Name):
                    name = child.targets[0].id
                    value = child.value
            elif isinstance(child, ast.AnnAssign) and isinstance(child.target, ast.Name):
                name = child.target.id
                value = child.value

            if (
                name == "CIPHERS"
                and isinstance(value, ast.Call)
                and len(value.args) == 1
                and isinstance(value.args[0], (ast.List, ast.Tuple))
            ):
                vals = []
                for elt in value.args[0].elts:
                    if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                        vals.append(elt.value)
                new_ciphers = vals
                break

if new_ciphers is None or not all(cipher in new_ciphers for cipher in WANTED):
    fail("Validação interna falhou: as cifras ECDHE não ficaram presentes.")

# Confirma que o OpenSSL deste container aceita a lista resultante.
try:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.set_ciphers(":".join(new_ciphers))
except Exception as exc:
    fail(f"OpenSSL recusou a lista de cifras proposta: {exc}")

sha_after = hashlib.sha256(new_source.encode("utf-8")).hexdigest()

print()
print("Cifras a adicionar:")
for cipher in missing:
    print(f"  + {cipher}")

if DRY_RUN:
    print()
    print("[DRY-RUN] O arquivo seria alterado, mas nada foi gravado.")
    print(f"SHA antes: {sha_before}")
    print(f"SHA depois: {sha_after}")
    print("TAPO_TLS_RESULT=would_patch")
    raise SystemExit(0)

# Backup persistente e deduplicado por versão + hash de origem.
backup_dir = Path("/config/backups/tapo-tls-ecdhe")
backup_dir.mkdir(parents=True, exist_ok=True)

safe_version = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in kasa_version)
backup = backup_dir / (
    f"sslaestransport.py.kasa-{safe_version}.sha256-{sha_before[:16]}.bak"
)

if not backup.exists():
    shutil.copy2(path, backup)
    print(f"Backup criado: {backup}")
else:
    print(f"Backup já existente: {backup}")

# Grava atomicamente preservando as permissões.
original_mode = stat.S_IMODE(path.stat().st_mode)
fd, tmp_name = tempfile.mkstemp(
    prefix=".sslaestransport.",
    suffix=".tmp",
    dir=str(path.parent),
    text=True,
)
tmp = Path(tmp_name)

try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(new_source)
        handle.flush()
        os.fsync(handle.fileno())

    os.chmod(tmp, original_mode)
    os.replace(tmp, path)
finally:
    if tmp.exists():
        tmp.unlink(missing_ok=True)

# Validação pós-gravação.
written = path.read_text(encoding="utf-8")
if hashlib.sha256(written.encode("utf-8")).hexdigest() != sha_after:
    shutil.copy2(backup, path)
    fail(
        "SHA pós-gravação não corresponde ao esperado. "
        "Backup restaurado automaticamente."
    )

try:
    compile(written, str(path), "exec")
except SyntaxError as exc:
    shutil.copy2(backup, path)
    fail(
        f"Validação pós-gravação falhou ({exc}). "
        "Backup restaurado automaticamente."
    )

print()
print("[OK] Workaround ECDHE aplicado com segurança.")
print(f"SHA antes:  {sha_before}")
print(f"SHA depois: {sha_after}")
print("TAPO_TLS_RESULT=patched")
PY
)"
PATCH_RC=$?
set -e

printf '%s\n' "$PATCH_OUTPUT"

if (( PATCH_RC != 0 )); then
  echo
  echo "[ERRO] O diagnóstico/patch falhou. Core NÃO foi reiniciado." >&2
  exit "$PATCH_RC"
fi

RESULT="$(
  printf '%s\n' "$PATCH_OUTPUT" |
    sed -n 's/^TAPO_TLS_RESULT=//p' |
    tail -n 1
)"

if [[ -z "$RESULT" ]]; then
  echo "[ERRO] Não foi possível determinar o resultado do patch." >&2
  exit 20
fi

echo
echo "[2/4] Resultado: ${RESULT}"

case "$RESULT" in
  patched)
    CHANGED=1
    ;;
  already_patched|would_patch)
    CHANGED=0
    ;;
  *)
    echo "[ERRO] Resultado inesperado: ${RESULT}" >&2
    exit 21
    ;;
esac

if (( DRY_RUN )); then
  echo
  echo "[3/4] Dry-run: validação concluída."
  echo "[4/4] Core não reiniciado."
  exit 0
fi

echo
echo "[3/4] Verificando o arquivo efetivamente carregável em um novo processo..."

docker exec "$CONTAINER_NAME" python3 - <<'PY'
from kasa.transports.sslaestransport import SslAesTransport

required = {
    "ECDHE-RSA-AES256-GCM-SHA384",
    "ECDHE-RSA-AES128-GCM-SHA256",
}
actual = set(SslAesTransport.CIPHERS.split(":"))
missing = sorted(required - actual)

if missing:
    raise SystemExit(
        "ERRO: novo processo python-kasa ainda não enxerga: " + ", ".join(missing)
    )

print("[OK] Novo processo python-kasa enxerga as duas cifras ECDHE.")
PY

echo
echo "[4/4] Reinício do Home Assistant Core..."

if (( NO_RESTART )); then
  echo "[OK] --no-restart usado. Patch aplicado, Core não reiniciado."
  echo "     Execute depois: ha core restart"
  exit 0
fi

if (( CHANGED )) || (( FORCE_RESTART )); then
  echo "Reiniciando o Core para carregar o workaround..."
  ha core restart
  echo
  echo "[OK] Comando de restart enviado."
  echo "     Aguarde o Core voltar e teste novamente a câmera Tapo."
else
  echo "[OK] Nenhuma alteração foi necessária; Core não reiniciado."
fi

echo
echo "Observação:"
echo "  O patch fica no writable layer do container do Core."
echo "  Uma atualização/recriação do Core pode removê-lo."
echo "  Nesse caso, execute este mesmo script novamente."
