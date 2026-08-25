# haos-mac-mini

![CI](https://github.com/aleonnet/haos-mac-mini/actions/workflows/ci.yml/badge.svg)

> 🇧🇷 **Versão em português:** [README.md](README.md)

**Home Assistant OS** installer for a VirtualBox VM on **Apple Silicon Macs**, in a
single Bash script — idempotent, bilingual (pt-BR/en-US following your Mac's language)
and ready to run straight from `curl`. Home Assistant's own visual identity, with
verified degradation: in a log, in CI or in a terminal without UTF-8 the output becomes
clean, greppable text.

> **Status: working end to end (0.3.0).** One command takes an empty Mac to
> **Home Assistant up and running**: validates the machine, installs VirtualBox
> (Oracle's SHA-256), downloads and verifies the official HAOS image, creates
> the VM (arguments probed against the real ARM VBoxManage, with honest disk
> flushes from birth), boots it and waits on the VM's MAC address, creates your
> account (onboarding with analytics off), installs the add-ons you picked via
> the Supervisor WebSocket, configures the integrations that close without
> credentials, writes packages and dashboards into `/config` over SMB — and
> ends with the **real address** on screen and the browser open. Auto-start at
> login, **clean shutdown** on logout/reboot (vm-guard) and a **daily backup
> pulled out of the VM** (the vault, with `--backup`/`--restore`) included.
> The [CHANGELOG](CHANGELOG.md) says exactly what exists in each version.
>
> ⚠️ If you ALREADY have a Home Assistant on your network, `homeassistant.local`
> keeps pointing at it — the installer finds the VM by MAC and prints the real IP.

## Installation

### Remote (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash
```

In an interactive terminal, **with no flags at all**, it opens the menu with
[gum](https://github.com/charmbracelet/gum) (downloaded to temp with verified
SHA-256, never installed): pick a tier with the arrows, mark extras with
**space**, **fine-tune item by item with search** (type to filter, **TAB**
marks, enter confirms — inside the filter, space belongs to the search) and a
VM profile — then the plan and a confirmation, before anything is written.
Without a TTY or with `HAOS_USE_GUM=0` it degrades to the simple numbered
selector. Preflight also warns when a newer installer or HAOS release has been
published. Flags exist for headless/CI mode. Every real run saves your
selection (`--profile last` repeats it) and a report under
`~/.config/haos-mac-mini/`; a failure preserves the tools' log and prints its
path. Everything the installer creates is recorded in a manifest
(`created`/`preexisting`) — and `--uninstall` removes **only** what it can
prove it made: whatever already existed on the machine is preserved, with the
reason stated in the plan.

### Headless / no interaction

```bash
# ready-made profile, no questions
curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash -s -- --profile haos_casa --no-input --install-deps

# just see what would be done (writes nothing, not even a log)
curl -fsSL https://raw.githubusercontent.com/aleonnet/haos-mac-mini/main/haos-install.sh | bash -s -- --dry-run --profile haos_casa
```

## Profiles

Tiers **add up**; extras are marked separately, on any tier.

| Profile | What it covers |
|---|---|
| `haos_vanilla` | the floor — what HAOS installs by itself |
| `haos_conectado` | + connectivity infrastructure (MQTT, Matter, Thread, ESPHome, Cast) |
| `haos_casa` | + home hardware integrations (Hue, Tuya, Shelly, TP-Link, SmartThings…) |

Extras (`--with`): `ferramentas` (SSH, Studio Code Server, Samba) ·
`casa_abhome` (cost packages with Brazilian utility rules) · `extensoes`
(HACS — the installation only, and never in `--all`).

When System Monitor is in the selection, the installer also **enables a curated
list of sensors** (the integration ships with everything disabled — your own
choices are respected) and delivers the **Monitor dashboard** in the sidebar:
the VM's CPU, RAM, disk, swap, load and network; Core and Supervisor usage;
updates and the backup vault's state.

See the full catalog with `--list`.

## Options

| Flag | Effect |
|---|---|
| `--profile <id>` | `haos_vanilla` \| `haos_conectado` \| `haos_casa` \| `last` (repeats the last saved selection), no interaction |
| `--with a,b,c` | extras: `ferramentas`, `casa_abhome`, `extensoes` |
| `--all`, `-a` | `haos_casa` + extras (except what requires a named opt-in) |
| `--vm-profile <id>` | `vm_minimo` \| `vm_equilibrado` \| `vm_recomendado` (derived from the machine) |
| `--vm-name <name>` | VM name (default `HomeAssistant`) |
| `--dry-run`, `-n` | shows the plan and exits — writes nothing, not even a log |
| `--list` | lists the catalog and exits |
| `--image <file>` | uses this HAOS image `.zip` (verified by size and SHA-256 — a file that doesn't match is an error, not a fallback) |
| `--keep-image` | keeps the downloaded HAOS image `.zip` |
| `--install-deps` | installs missing prerequisites without asking (VirtualBox) |
| `--no-input` | asks nothing; fails if a required value is missing |
| `--force`, `-f` | redoes an artifact that is already present — does **not** skip the gate or hash checks |
| `--verbose`, `-v` | shows each tool's raw output |
| `--quiet`, `-q` | suppresses normal output |
| `--doctor` | read-only diagnostics: system, manifest, image, **VM storage** (controller + `IgnoreFlush` + the VirtualBox version the VM was validated under), local state (exit 1 on problems) |
| `--uninstall` | removes **only what this installer created** (plan + confirmation; `--dry-run` shows the plan; `--confirm=<vm-name>` confirms without a terminal) |
| `--self-update` | updates the script from the published one — validates syntax, refuses downgrades, leaves a `.bak` backup |
| `--backup` | creates a backup **now** and pulls it into the vault (`~/Documents/HAOS-backups`) — the manual twin of the daily 04:10 agent, with the result spoken on screen |
| `--restore <tar>` | restores a vault backup (`~/Documents/HAOS-backups`) into the VM — account, integrations and dashboards come back whole |
| `--no-open` | doesn't open the browser at the end |
| `--version` / `--help` | version and help |

Environment variables: `HAOS_LANG=pt|en` forces the language; `NO_COLOR`
disables color and animation; `HAOS_STATE_DIR` changes the state directory
(default `~/.config/haos-mac-mini`).

## Important behaviors

- **Idempotent**: an artifact that is present and intact reports "already
  there" and is not redone. Re-running after a failure continues from where it
  stopped.
- **Nothing unverified**: the VirtualBox `.dmg` is checked against Oracle's
  `SHA256SUMS` and the HAOS image against the hash published in the script's
  table — `--force` skips neither. A truncated download is discarded by size
  before costing a 380 MiB read.
- **One password, once**: `sudo` is who asks, in the terminal; the installer
  never sees, stores or forwards your password.
- **Failure explains itself**: a network error is recognized by its signature
  and said as such (with the hint to re-run), instead of dumping the tool's
  stack; the last lines of the log go on screen and the full file stays in
  `$TMPDIR`.
- **Degrades well**: without a TTY, without UTF-8 or with `NO_COLOR`, glyphs
  become ASCII and the animation goes away — the same run stays readable in a
  CI log.
- **The vault is the single backup authority**: it creates backups without a
  password (restore needs no key), keeps 7 on the Mac and only the latest 2
  inside the VM. An **encrypted** tar (UI automatic backups turned on in Home
  Assistant) is **refused with a warning** — the vault could not restore it
  without the Emergency Kit key. Recommendation: leave the UI automatic backup
  off and use `--backup`/the daily agent; if you choose the UI path, keep the
  kit — the key is yours, the installer never sees it.

## Requirements

- **Apple Silicon** Mac (the HAOS image is aarch64)
- macOS with `curl` (factory) · `python3` (via Command Line Tools:
  `xcode-select --install`)
- VirtualBox ≥ 7.1 — the installer offers to install it if missing

## Development

The repository is the script's source: `catalog/catalog.bash` is the catalog's
source of truth, `lib/` holds the visual layer and the host probe, and
`tools/embed.sh` embeds the copies into `haos-install.sh` (CI fails on drift).
Single quality gate, local and in CI:

```bash
./tools/gate.sh
```

Engineering documents (verified API contract, catalog curation, front handoffs)
live in [`docs/`](docs/). **MIT** license.

## The official guide and the holes this installer covers

The [official HAOS on macOS/VirtualBox guide](https://www.home-assistant.io/installation/macos/)
stops at "create the VM and boot it". In practice (all measured in the field,
Aug 24–25, 2026):

| The guide | Reality | Here |
|---|---|---|
| Silence about disk flushes | **VirtualBox ignores guest flushes by default** ([documented by Oracle](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/Troubleshooting.html); only IDE/SATA have the correction key) — the ext4 journal becomes fiction; on this bench, a dirty shutdown wiped HAOS's `/data` twice | `IgnoreFlush=0` written at VM creation (AHCI controller, exactly where Oracle documents the key); validated with 5 simulated power cuts without losing a byte (fenced in CI); `--doctor` checks controller and key on the real VM |
| Tells you to use VirtioSCSI on Apple Silicon | The ARM `VBoxManage` **refuses** VirtioSCSI ("Invalid controller type") — and Oracle marks it experimental, with no documented `IgnoreFlush` | SATA/AHCI probed against the real binary before creating |
| Nothing about safe shutdown | A Mac reboot/logout kills the VM cold | **vm-guard**: clean `ha host shutdown` at logout, honest `poweroff` fallback (fenced in both scenarios; `savestate` is banned as an engineering decision: it broke the guest's container runtime in the field, and Oracle records ARM saved states as incompatible across 7.1→7.2) |
| Nothing about backup | HA's native backup lives INSIDE the VM — it dies with it | **The vault**: a backup created at install time and pulled to `~/Documents/HAOS-backups` on the Mac, a daily 04:10 agent, `--backup` for an immediate on-demand backup, and `--restore <tar>` brings the whole instance back in one command (fences cover create/pull/prune/restore/refuse-tampered) |
| Onboarding, add-ons, integrations: "use the browser" | hours of clicking | phases 07–10 automate everything that doesn't require your credentials |
