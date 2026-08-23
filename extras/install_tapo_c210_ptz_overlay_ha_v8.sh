#!/usr/bin/env bash
set -Eeuo pipefail

# Home Assistant - TP-Link/Tapo C210 PTZ overlay installer
# Version 8
#
# Target validated in this workflow:
#   - Home Assistant OS 18.2
#   - Home Assistant Core 2026.8.2
#   - Home Assistant Frontend 20260729.6
#
# What it installs:
#   Compact Home/Area card:
#     - native live camera stream
#     - PTZ D-pad only: ▲ ◀ ● ▶ ▼
#     - compact-only proportional scale (default 0.72), bottom-right
#
#   Expanded camera view (more-info-camera):
#     - PTZ D-pad over the stream
#     - Pan step / Tilt step in degrees per D-pad press, NOT absolute position
#       (keyboard entry + arrows; commit on change/blur/Enter)
#     - Motion / Person / LED / Tamper
#
# Discovery is automatic per camera using device_id + TP-Link translation_key,
# so the same module handles multiple C210 cameras independently.
#
# Idempotence guarantees:
#   - Re-running with the same version/content does not rewrite the JS file.
#   - Exactly one /local/tapo-ptz-home.js entry is kept in extra_module_url.
#   - Existing frontend options/modules (for example themes/HACS iconset) are preserved.
#   - Backups are created only when a file will actually change.
#   - Core restarts only when something changed, unless --force-restart is used.
#   - If `ha core check` fails after a configuration change, configuration.yaml is restored.
#
# This script does NOT patch python-kasa/TLS. That workaround is runtime/version-specific
# and should only be applied when the installed python-kasa version actually needs it.

INSTALLER_VERSION="8"
JS_VERSION="8"
JS_FILE="/config/www/tapo-ptz-home.js"
YAML_FILE="/config/configuration.yaml"
MODULE_PATH="/local/tapo-ptz-home.js"
MODULE_URL="${MODULE_PATH}?v=${JS_VERSION}"
BACKUP_DIR="/config/backups/tapo-ptz-overlay"
NO_RESTART=0
FORCE_RESTART=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
Uso:
  bash install_tapo_c210_ptz_overlay_ha_v8.sh [opções]

Opções:
  --no-restart      Instala/valida, mas não reinicia o Core.
  --force-restart   Reinicia o Core mesmo se nada tiver mudado.
  --dry-run         Mostra o que mudaria sem alterar arquivos nem reiniciar.
  -h, --help        Mostra esta ajuda.

Comportamento idempotente:
  Se a v8 já estiver exatamente instalada, uma nova execução não regrava arquivos,
  não duplica extra_module_url, não cria backups inúteis e não reinicia o Core.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-restart) NO_RESTART=1; shift ;;
    --force-restart) FORCE_RESTART=1; shift ;;
    --dry-run) DRY_RUN=1; NO_RESTART=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERRO: opção desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done

fail() {
  echo "ERRO: $*" >&2
  exit 1
}

[[ -d /config ]] || fail "/config não existe. Execute no Home Assistant OS/Advanced SSH & Web Terminal."
[[ -f "$YAML_FILE" ]] || fail "$YAML_FILE não encontrado."
command -v python3 >/dev/null 2>&1 || fail "python3 não encontrado."
command -v ha >/dev/null 2>&1 || fail "comando 'ha' não encontrado."

mkdir -p /config/www "$BACKUP_DIR"

TMP_DIR="$(mktemp -d /tmp/tapo-ptz-v8.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
DESIRED_JS="$TMP_DIR/tapo-ptz-home.js"
DESIRED_YAML="$TMP_DIR/configuration.yaml"

cat > "$DESIRED_JS" <<'JS_EOF'
/*
 * Tapo C210 PTZ Overlay for Home Assistant
 * Version: 8
 * Validated target in this workflow: HA Core 2026.8.2 / Frontend 20260729.6
 *
 * Compact Home/Area card:
 *   - forces the native picture-entity card to camera_view=live
 *   - PTZ D-pad overlay only
 *   - proportional scale parameter applied only to the compact D-pad
 *
 * Expanded camera view (more-info-camera):
 *   - PTZ D-pad overlay on the native stream
 *   - Pan step / Tilt step with reliable keyboard input persistence
 *   - Motion / Person / LED / Tamper switches
 *
 * Entity discovery is automatic by device_id + TP-Link translation_key.
 */
(() => {
  "use strict";

  const VERSION = "8";
  const LOG = "[Tapo PTZ]";

  /*
   * Direction mapping validated on the two C210 cameras in this installation:
   *   visual ◀/▶ needs the TP-Link pan entities reversed;
   *   visual ▲/▼ uses the nominal TP-Link tilt entities.
   */
  const INVERT_PAN = true;
  const INVERT_TILT = false;

  /*
   * Compact-only UI scale.
   *   1.00 = 34 px buttons (unscaled baseline)
   *   0.72 = current default, ~24 px buttons
   *
   * Only the compact Home/Area D-pad uses this scale. The expanded camera
   * view remains unchanged at 42 px for easier interaction. A 24 px minimum
   * click target is enforced so the compact control remains usable.
   */
  const COMPACT_SCALE = 0.72;
  const COMPACT_BASE_BUTTON_PX = 34;
  const COMPACT_MIN_BUTTON_PX = 24;
  const COMPACT_BASE_OFFSET_PX = 10;
  const COMPACT_BUTTON_PX = Math.max(
    COMPACT_MIN_BUTTON_PX,
    Math.round(COMPACT_BASE_BUTTON_PX * COMPACT_SCALE)
  );
  const COMPACT_OFFSET_PX = Math.max(
    4,
    Math.round(COMPACT_BASE_OFFSET_PX * COMPACT_SCALE)
  );

  const COMPACT_CLASS = "tapo-ptz-compact-v8";
  const STREAM_CLASS = "tapo-ptz-stream-v8";
  const PANEL_CLASS = "tapo-ptz-panel-v8";

  const getHass = () => document.querySelector("home-assistant")?.hass;

  const entriesForDevice = (hass, entityId) => {
    const entry = hass?.entities?.[entityId];
    if (!entry?.device_id) return [];
    return Object.values(hass.entities).filter(
      (candidate) =>
        candidate.device_id === entry.device_id &&
        candidate.platform === "tplink"
    );
  };

  const findEntityByKey = (entries, domain, translationKey) =>
    entries.find(
      (entry) =>
        entry.translation_key === translationKey &&
        entry.entity_id.startsWith(`${domain}.`)
    )?.entity_id;

  const discover = (hass, cameraEntityId) => {
    const entries = entriesForDevice(hass, cameraEntityId);
    if (!entries.length) return null;

    const features = {
      camera: cameraEntityId,
      panLeft: findEntityByKey(entries, "button", "pan_left"),
      panRight: findEntityByKey(entries, "button", "pan_right"),
      tiltUp: findEntityByKey(entries, "button", "tilt_up"),
      tiltDown: findEntityByKey(entries, "button", "tilt_down"),
      panStep: findEntityByKey(entries, "number", "pan_step"),
      tiltStep: findEntityByKey(entries, "number", "tilt_step"),
      motion: findEntityByKey(entries, "switch", "motion_detection"),
      person: findEntityByKey(entries, "switch", "person_detection"),
      led: findEntityByKey(entries, "switch", "led"),
      tamper: findEntityByKey(entries, "switch", "tamper_detection"),
    };

    return features.panLeft &&
      features.panRight &&
      features.tiltUp &&
      features.tiltDown
      ? features
      : null;
  };

  const service = async (hass, domain, serviceName, data, target) => {
    try {
      await hass.callService(domain, serviceName, data ?? {}, target ?? {});
    } catch (err) {
      console.error(`${LOG} Falha em ${domain}.${serviceName}`, err);
      throw err;
    }
  };

  const physicalPtzEntities = (features) => ({
    left: INVERT_PAN ? features.panRight : features.panLeft,
    right: INVERT_PAN ? features.panLeft : features.panRight,
    up: INVERT_TILT ? features.tiltDown : features.tiltUp,
    down: INVERT_TILT ? features.tiltUp : features.tiltDown,
  });

  const stopCardAction = (element) => {
    ["pointerdown", "mousedown", "touchstart"].forEach((name) => {
      element.addEventListener(name, (ev) => ev.stopPropagation());
    });
  };

  const styleDpadButton = (el, size) => {
    Object.assign(el.style, {
      width: `${size}px`,
      height: `${size}px`,
      border: "0",
      borderRadius: "50%",
      background: "rgba(0,0,0,0.58)",
      color: "white",
      fontSize: `${Math.round(size * 0.58)}px`,
      lineHeight: `${size}px`,
      textAlign: "center",
      padding: "0",
      margin: "0",
      cursor: "pointer",
      userSelect: "none",
      boxSizing: "border-box",
      fontFamily: "system-ui, sans-serif",
      backdropFilter: "blur(2px)",
      WebkitBackdropFilter: "blur(2px)",
    });
  };

  const makeDpadButton = (hass, entityId, symbol, title, col, row, size) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = symbol;
    button.title = title;
    button.setAttribute("aria-label", title);
    styleDpadButton(button, size);
    button.style.gridColumn = String(col);
    button.style.gridRow = String(row);
    stopCardAction(button);
    button.addEventListener("click", async (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      await service(hass, "button", "press", {}, { entity_id: entityId });
    });
    return button;
  };

  const createDpad = (hass, features, className, size = 36) => {
    const ptz = physicalPtzEntities(features);
    const gap = Math.max(3, Math.round(size * 0.08));
    const overlay = document.createElement("div");
    overlay.className = className;
    Object.assign(overlay.style, {
      display: "grid",
      gridTemplateColumns: `${size}px ${size}px ${size}px`,
      gridTemplateRows: `${size}px ${size}px ${size}px`,
      gap: `${gap}px`,
      zIndex: "100",
      pointerEvents: "auto",
    });

    overlay.appendChild(makeDpadButton(hass, ptz.up, "▲", "Cima", 2, 1, size));
    overlay.appendChild(makeDpadButton(hass, ptz.left, "◀", "Esquerda", 1, 2, size));

    const center = document.createElement("div");
    center.textContent = "●";
    center.setAttribute("aria-hidden", "true");
    styleDpadButton(center, size);
    center.style.gridColumn = "2";
    center.style.gridRow = "2";
    center.style.cursor = "default";
    center.style.background = "rgba(0,0,0,0.42)";
    center.style.pointerEvents = "none";
    overlay.appendChild(center);

    overlay.appendChild(makeDpadButton(hass, ptz.right, "▶", "Direita", 3, 2, size));
    overlay.appendChild(makeDpadButton(hass, ptz.down, "▼", "Baixo", 2, 3, size));
    return overlay;
  };

  const getNumberMeta = (hass, entityId) => {
    const state = entityId ? hass.states?.[entityId] : undefined;
    if (!state) return null;
    return {
      value: Number(state.state),
      min: Number(state.attributes.min ?? 1),
      max: Number(state.attributes.max ?? 360),
      step: Number(state.attributes.step ?? 1),
    };
  };

  const makeNumberControl = (hass, entityId, label) => {
    if (!entityId) return null;
    const meta = getNumberMeta(hass, entityId);
    if (!meta || !Number.isFinite(meta.value)) return null;

    const wrap = document.createElement("label");
    Object.assign(wrap.style, {
      display: "flex",
      alignItems: "center",
      gap: "8px",
      color: "var(--primary-text-color)",
      fontSize: "14px",
      whiteSpace: "nowrap",
    });

    const text = document.createElement("span");
    text.textContent = label;

    const input = document.createElement("input");
    input.type = "number";
    input.value = String(meta.value);
    input.min = String(meta.min);
    input.max = String(meta.max);
    input.step = String(meta.step);
    input.inputMode = "decimal";
    input.setAttribute("aria-label", `${label} em graus`);
    Object.assign(input.style, {
      width: "72px",
      boxSizing: "border-box",
      padding: "7px 8px",
      border: "1px solid var(--divider-color)",
      borderRadius: "8px",
      background: "var(--card-background-color)",
      color: "var(--primary-text-color)",
      font: "inherit",
    });

    const unit = document.createElement("span");
    unit.textContent = "°";
    unit.style.color = "var(--secondary-text-color)";

    // v8: document.activeElement does not reliably point at an input inside
    // nested Shadow DOM. In v7 the 1.5 s refresh could therefore overwrite a
    // value while it was being typed. Track edit/commit state on the input and
    // use :focus on the element itself instead.
    let dirty = false;
    let committing = false;
    let pendingUntil = 0;

    input.__tapoRefresh = () => {
      if (
        input.matches(":focus") ||
        dirty ||
        committing ||
        Date.now() < pendingUntil
      ) {
        return;
      }

      const currentHass = getHass() ?? hass;
      const state = currentHass.states?.[entityId];
      if (state && Number.isFinite(Number(state.state))) {
        input.value = String(Number(state.state));
      }
    };

    const commit = async () => {
      if (!dirty || committing) return;

      const value = Number(input.value);
      if (!Number.isFinite(value)) {
        dirty = false;
        input.__tapoRefresh();
        return;
      }

      const bounded = Math.min(meta.max, Math.max(meta.min, value));
      input.value = String(bounded);
      dirty = false;
      committing = true;

      try {
        await service(
          getHass() ?? hass,
          "number",
          "set_value",
          { value: bounded },
          { entity_id: entityId }
        );

        // Do not let the periodic refresh restore the old HA state during the
        // short interval between service completion and the state update.
        pendingUntil = Date.now() + 1500;
      } catch (err) {
        dirty = true;
        throw err;
      } finally {
        committing = false;
      }
    };

    input.addEventListener("input", () => {
      dirty = true;
    });

    // Native number steppers normally fire change while the control keeps
    // focus, so keep this path for immediate arrow-button commits.
    input.addEventListener("change", () => {
      void commit();
    });

    // Keyboard entry is committed when leaving the field.
    input.addEventListener("blur", () => {
      void commit();
    });

    // Enter commits immediately and then exits edit mode.
    input.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter") {
        ev.preventDefault();
        void commit().finally(() => input.blur());
      } else if (ev.key === "Escape") {
        ev.preventDefault();
        dirty = false;
        input.__tapoRefresh();
        input.blur();
      }
    });

    wrap.append(text, input, unit);
    return wrap;
  };

  const styleToggle = (button, isOn) => {
    Object.assign(button.style, {
      border: `1px solid ${isOn ? "var(--primary-color)" : "var(--divider-color)"}`,
      borderRadius: "999px",
      padding: "7px 12px",
      background: isOn ? "var(--primary-color)" : "var(--card-background-color)",
      color: isOn ? "var(--text-primary-color, white)" : "var(--primary-text-color)",
      cursor: "pointer",
      font: "inherit",
      fontSize: "14px",
      minWidth: "82px",
    });
  };

  const makeSwitchControl = (hass, entityId, label) => {
    if (!entityId || !hass.states?.[entityId]) return null;
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.entityId = entityId;
    button.dataset.label = label;

    const refresh = () => {
      const currentHass = getHass() ?? hass;
      const state = currentHass.states?.[entityId]?.state;
      const isOn = state === "on";
      button.textContent = `${label}  ${isOn ? "●" : "○"}`;
      button.setAttribute("aria-pressed", String(isOn));
      styleToggle(button, isOn);
    };

    refresh();
    button.__tapoRefresh = refresh;
    button.addEventListener("click", async () => {
      const currentHass = getHass() ?? hass;
      const isOn = currentHass.states?.[entityId]?.state === "on";
      await service(
        currentHass,
        "switch",
        isOn ? "turn_off" : "turn_on",
        {},
        { entity_id: entityId }
      );
      setTimeout(refresh, 250);
      setTimeout(refresh, 900);
    });
    return button;
  };

  const createExpandedPanel = (hass, features) => {
    const panel = document.createElement("div");
    panel.className = PANEL_CLASS;
    Object.assign(panel.style, {
      margin: "0 var(--ha-space-4, 16px) var(--ha-space-2, 8px)",
      padding: "12px 14px",
      border: "1px solid var(--divider-color)",
      borderRadius: "12px",
      background: "var(--card-background-color)",
      boxSizing: "border-box",
      display: "grid",
      gap: "12px",
    });

    const movement = document.createElement("div");
    Object.assign(movement.style, {
      display: "flex",
      flexWrap: "wrap",
      alignItems: "center",
      gap: "10px 18px",
    });

    const movementLabel = document.createElement("strong");
    movementLabel.textContent = "Movimento";
    movementLabel.style.fontSize = "14px";
    movementLabel.style.minWidth = "84px";
    movement.appendChild(movementLabel);

    const pan = makeNumberControl(hass, features.panStep, "Pan");
    const tilt = makeNumberControl(hass, features.tiltStep, "Tilt");
    if (pan) movement.appendChild(pan);
    if (tilt) movement.appendChild(tilt);

    const controls = document.createElement("div");
    Object.assign(controls.style, {
      display: "flex",
      flexWrap: "wrap",
      alignItems: "center",
      gap: "8px",
    });

    const controlsLabel = document.createElement("strong");
    controlsLabel.textContent = "Controles";
    controlsLabel.style.fontSize = "14px";
    controlsLabel.style.minWidth = "84px";
    controls.appendChild(controlsLabel);

    [
      [features.motion, "Motion"],
      [features.person, "Person"],
      [features.led, "LED"],
      [features.tamper, "Tamper"],
    ].forEach(([entityId, label]) => {
      const control = makeSwitchControl(hass, entityId, label);
      if (control) controls.appendChild(control);
    });

    panel.append(movement, controls);
    return panel;
  };

  const installCompact = (card) => {
    const hass = card.hass;
    const cameraEntityId = card._config?.entity;
    if (!hass || !cameraEntityId?.startsWith("camera.") || !card.shadowRoot) return;

    const features = discover(hass, cameraEntityId);
    if (!features) return;

    if (card._config?.camera_view !== "live" && !card.__tapoLiveForcedV8) {
      card.__tapoLiveForcedV8 = true;
      card.setConfig({ ...card._config, camera_view: "live" });
      return;
    }

    const haCard = card.shadowRoot.querySelector("ha-card");
    if (!haCard || haCard.querySelector(`.${COMPACT_CLASS}`)) return;

    const overlay = createDpad(
      hass,
      features,
      COMPACT_CLASS,
      COMPACT_BUTTON_PX
    );
    Object.assign(overlay.style, {
      position: "absolute",
      right: `${COMPACT_OFFSET_PX}px`,
      bottom: `${COMPACT_OFFSET_PX}px`,
    });
    haCard.appendChild(overlay);
    console.info(`${LOG} compacto instalado: ${cameraEntityId}`);
  };

  const refreshPanel = (component) => {
    const root = component.shadowRoot;
    if (!root) return;

    root.querySelectorAll(`.${PANEL_CLASS} button[data-entity-id]`).forEach((button) => {
      try {
        button.__tapoRefresh?.();
      } catch (_) {
        // Ignore transient state updates.
      }
    });

    root.querySelectorAll(`.${PANEL_CLASS} input[type="number"]`).forEach((input) => {
      try {
        input.__tapoRefresh?.();
      } catch (_) {
        // Ignore transient state updates.
      }
    });
  };

  const installExpanded = (component) => {
    const hass = getHass();
    const cameraEntityId = component.stateObj?.entity_id;
    if (!hass || !cameraEntityId?.startsWith("camera.") || !component.shadowRoot) return;

    const features = discover(hass, cameraEntityId);
    if (!features) return;

    const stream = component.shadowRoot.querySelector("ha-camera-stream");
    if (!stream) return;

    component.style.position = "relative";

    if (!component.shadowRoot.querySelector(`.${STREAM_CLASS}`)) {
      const dpad = createDpad(hass, features, STREAM_CLASS, 42);
      Object.assign(dpad.style, {
        position: "absolute",
        top: "12px",
        right: "12px",
      });
      component.shadowRoot.appendChild(dpad);
    }

    if (!component.shadowRoot.querySelector(`.${PANEL_CLASS}`)) {
      const panel = createExpandedPanel(hass, features);
      stream.after(panel);
    }

    if (!component.__tapoRefreshTimerV8) {
      component.__tapoRefreshTimerV8 = setInterval(() => {
        if (!component.isConnected) {
          clearInterval(component.__tapoRefreshTimerV8);
          component.__tapoRefreshTimerV8 = null;
          return;
        }
        refreshPanel(component);
      }, 1500);
    }

    if (!component.__tapoExpandedLoggedV8) {
      component.__tapoExpandedLoggedV8 = true;
      console.info(`${LOG} expandido instalado: ${cameraEntityId}`);
    }
  };

  const scan = (root) => {
    if (!root?.querySelectorAll) return;
    root.querySelectorAll("hui-picture-entity-card").forEach(installCompact);
    root.querySelectorAll("more-info-camera").forEach(installExpanded);
    root.querySelectorAll("*").forEach((el) => {
      if (el.shadowRoot) scan(el.shadowRoot);
    });
  };

  const patchComponent = async (tag, installer, marker) => {
    await customElements.whenDefined(tag);
    const Klass = customElements.get(tag);
    if (!Klass || Klass[marker]) return;
    const originalUpdated = Klass.prototype.updated;
    Klass.prototype.updated = function (...args) {
      const result = originalUpdated?.apply(this, args);
      queueMicrotask(() => installer(this));
      return result;
    };
    Klass[marker] = true;
  };

  patchComponent("hui-picture-entity-card", installCompact, "__tapoPtzV8");
  patchComponent("more-info-camera", installExpanded, "__tapoPtzV8");

  // Fallback for lazy-loaded/already-rendered shadow trees.
  setTimeout(() => scan(document), 500);
  setTimeout(() => scan(document), 1500);
  setTimeout(() => scan(document), 3500);

  console.info(`${LOG} v${VERSION} carregado; compact scale=${COMPACT_SCALE}`);
})();
JS_EOF

# Build the desired configuration.yaml in a temporary file. This routine removes
# every old Tapo PTZ module entry and then ensures exactly one v8 entry exists.
python3 - "$YAML_FILE" "$DESIRED_YAML" "$MODULE_URL" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
dest = Path(sys.argv[2])
module_url = sys.argv[3]
text = source.read_text()
lines = text.splitlines(keepends=True)

module_re = re.compile(r"^\s*-\s*/local/tapo-ptz-home\.js(?:\?v=[^\s#]+)?\s*(?:#.*)?$")

# Remove all previous PTZ module entries, no matter the query-string version.
lines = [line for line in lines if not module_re.match(line.rstrip("\r\n"))]

# Locate a top-level `frontend:` block.
frontend_idx = None
for i, line in enumerate(lines):
    if line.strip() == "frontend:" and not line.startswith((" ", "\t")):
        frontend_idx = i
        break

if frontend_idx is None:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.extend([
        "frontend:\n",
        "  extra_module_url:\n",
        f"    - {module_url}\n",
    ])
else:
    # Determine the end of the top-level frontend block.
    end = len(lines)
    for i in range(frontend_idx + 1, len(lines)):
        raw = lines[i]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not raw.startswith((" ", "\t")):
            end = i
            break

    # Find extra_module_url inside frontend.
    extra_idx = None
    for i in range(frontend_idx + 1, end):
        if lines[i].strip() == "extra_module_url:":
            extra_idx = i
            break

    if extra_idx is None:
        # Insert immediately after frontend:, preserving all existing keys.
        lines.insert(frontend_idx + 1, "  extra_module_url:\n")
        lines.insert(frontend_idx + 2, f"    - {module_url}\n")
    else:
        # Reject uncommon scalar/inline forms instead of guessing and corrupting YAML.
        raw_extra = lines[extra_idx]
        if raw_extra.strip() != "extra_module_url:":
            raise SystemExit("ERRO: extra_module_url usa formato não suportado; nada foi alterado.")

        # Insert at the end of the sequence belonging to extra_module_url.
        insert_at = extra_idx + 1
        while insert_at < len(lines):
            raw = lines[insert_at]
            stripped = raw.strip()
            # Keep the module list compact: insert before the first blank line
            # or before the next sibling/top-level frontend key.
            if not stripped:
                break
            indent = len(raw) - len(raw.lstrip(" "))
            if indent <= 2:
                break
            insert_at += 1
        lines.insert(insert_at, f"    - {module_url}\n")

dest.write_text("".join(lines))
PY

JS_CHANGED=0
YAML_CHANGED=0

if [[ ! -f "$JS_FILE" ]] || ! cmp -s "$DESIRED_JS" "$JS_FILE"; then
  JS_CHANGED=1
fi

if ! cmp -s "$DESIRED_YAML" "$YAML_FILE"; then
  YAML_CHANGED=1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Tapo C210 PTZ Overlay installer v${INSTALLER_VERSION} — DRY RUN"
  echo
  [[ "$JS_CHANGED" -eq 1 ]] && echo "- ALTERARIA: $JS_FILE" || echo "- OK/SEM MUDANÇA: $JS_FILE"
  [[ "$YAML_CHANGED" -eq 1 ]] && echo "- ALTERARIA: $YAML_FILE" || echo "- OK/SEM MUDANÇA: $YAML_FILE"
  echo
  echo "Entrada desejada: $MODULE_URL"
  exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
YAML_BACKUP=""
JS_BACKUP=""

if [[ "$JS_CHANGED" -eq 1 ]]; then
  if [[ -f "$JS_FILE" ]]; then
    JS_BACKUP="$BACKUP_DIR/tapo-ptz-home.js.${STAMP}.bak"
    cp -p "$JS_FILE" "$JS_BACKUP"
  fi
  install -m 0644 "$DESIRED_JS" "$JS_FILE"
  echo "[ALTERADO] $JS_FILE -> v${JS_VERSION}"
else
  echo "[OK] $JS_FILE já está exatamente na v${JS_VERSION}."
fi

if [[ "$YAML_CHANGED" -eq 1 ]]; then
  YAML_BACKUP="$BACKUP_DIR/configuration.yaml.${STAMP}.bak"
  cp -p "$YAML_FILE" "$YAML_BACKUP"
  install -m 0644 "$DESIRED_YAML" "$YAML_FILE"
  echo "[ALTERADO] $YAML_FILE"
else
  echo "[OK] $YAML_FILE já contém exatamente uma referência PTZ v${JS_VERSION}."
fi

echo
echo "Validação do Home Assistant..."
if ! ha core check; then
  echo "ERRO: 'ha core check' falhou." >&2

  if [[ -n "$YAML_BACKUP" && -f "$YAML_BACKUP" ]]; then
    cp -p "$YAML_BACKUP" "$YAML_FILE"
    echo "configuration.yaml restaurado de: $YAML_BACKUP" >&2
  fi

  if [[ "$JS_CHANGED" -eq 1 ]]; then
    if [[ -n "$JS_BACKUP" && -f "$JS_BACKUP" ]]; then
      cp -p "$JS_BACKUP" "$JS_FILE"
      echo "JS restaurado de: $JS_BACKUP" >&2
    else
      rm -f "$JS_FILE"
      echo "JS novo removido durante rollback." >&2
    fi
  fi

  exit 1
fi

echo "Validação concluída com sucesso."

CHANGED=0
if [[ "$JS_CHANGED" -eq 1 || "$YAML_CHANGED" -eq 1 ]]; then
  CHANGED=1
fi

echo
if [[ "$CHANGED" -eq 0 ]]; then
  echo "RESULTADO: nenhuma alteração necessária — instalação já estava convergida para a v${JS_VERSION}."
else
  echo "RESULTADO: instalação convergida para a v${JS_VERSION}."
  [[ -n "$JS_BACKUP" ]] && echo "Backup JS:   $JS_BACKUP"
  [[ -n "$YAML_BACKUP" ]] && echo "Backup YAML: $YAML_BACKUP"
fi

if [[ "$NO_RESTART" -eq 1 ]]; then
  echo "Core não reiniciado (--no-restart/--dry-run)."
elif [[ "$CHANGED" -eq 1 || "$FORCE_RESTART" -eq 1 ]]; then
  echo "Reiniciando Home Assistant Core..."
  ha core restart
  echo "Após o Core voltar: faça Cmd+Shift+R no Firefox."
else
  echo "Core não reiniciado: nada mudou. Use --force-restart se quiser reiniciar mesmo assim."
fi

echo
echo "Diagnóstico no Console do navegador: filtre por '[Tapo PTZ]'."
echo "Esperado: '[Tapo PTZ] v8 carregado' e mensagens de compacto/expandido por câmera."
