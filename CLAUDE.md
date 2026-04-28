# Dotfiles v2

Hyprland + Quickshell on Arch. Catppuccin Mocha base. Single source of truth for colors with live reload across kitty, hyprland, oh-my-posh, GTK, and the bar.

## Source of truth

- **`.config/colors.json`** — base palette (`ansi`, `ui`, `opacity`, `theme.{gtk,cursor,icon,gtk2_fallback}`).
- **`~/.cache/quickshell/colors-override.json`** — runtime override, gitignored, outside the repo. Settings UI / accent picker writes here, not to `colors.json`.
- Final colors = base shallow-merged with override (top-level sections like `ui`, `theme` merge per-key).

Repo stays clean during interactive theme tweaking. To make an override permanent, copy values from override into `colors.json`.

## Generated files (gitignored, do not edit by hand)

| Path | Generator |
|---|---|
| `.config/colors.conf` | render_configs.sh (kitty include) |
| `.config/bashrc/colors` | render_configs.sh (`export PRIMARY=...`) |
| `.config/gtk-{3,4}.0/{gtk.css,settings.ini}` | render_configs.sh |
| `.config/ohmyposh/theme.omp.json` | render_configs.sh (palette injected into `templates/ohmyposh.omp.json`) |
| `home/.gtkrc-2.0` | render_configs.sh |

Hand-edited: `kitty.conf`, `hypr/conf/*`, `bashrc/{aliases,ohmyposh,env}`, `templates/*`, `quickshell/shell.qml`.

## Live reload pipeline

After any colors change, run in order:

```
render_configs.sh   # write generated files (merged base + override)
apply_gsettings.sh  # gsettings + hyprctl setcursor (also reads merged)
reload_all.sh       # IPC pushes to running apps
```

The Quickshell `applyChain` Process runs all three. What each app needs:

- **kitty** — `kitty @ --to=unix:@mykitty-{PID} set-colors --all --configured ~/.config/colors.conf`. Requires `allow_remote_control yes` + `listen_on unix:@mykitty` in kitty.conf. **Kitty appends `-{PID}` to abstract socket names** — iterate every kitty PID.
- **hyprland** — `hyprctl reload`.
- **bash / oh-my-posh** — bash embeds the prompt at init. `bashrc/ohmyposh` installs a `SIGUSR1` trap that re-runs `oh-my-posh init`. `reload_all.sh` does `pkill -USR1 -x bash`.
- **GTK apps** — **no live reload exists**. Apps cache theme at startup. gsettings notifications reach libadwaita apps but not custom CSS. Restart the app.

## Quickshell (`.config/quickshell/`)

Multi-file structure. Each PanelWindow lives in its own file; `shell.qml` only holds shared state and instantiates them via `Variants`.

```
.config/quickshell/
├── shell.qml          # entry point: state (colors, theme, system polling, IPC) + Variants
├── Bar.qml            # top bar PanelWindow (workspaces, clock, title, modules, corners)
├── ThemeSwitcher.qml  # bottom hover-reveal panel (accent grid, dark/light, reset)
├── Notifications.qml  # unified toast + center: pops on new notif, hover expands to all tracked
├── AppLauncher.qml    # centered drop-down launcher (search + DesktopEntries), opened via IPC
├── PowerMenu.qml      # left-anchored drop-down with lock/suspend/logout/reboot/shutdown
└── TintedIcon.qml     # reusable: IconImage from active icon theme + MultiEffect tint
```

**State stays in `shell.qml`** — colors loading (FileView × 2), `cBg`/`cFg`/`cPrimary`/etc., theme state (`currentAccent`, `currentFlavor`), action functions (`setAccent`, `toggleFlavor`, `clearOverride`), system polling (`volumeText`, `batteryText`, `btConnected`). Children declare `required property` for what they need; `shell.qml` passes them via the Variants delegate.

**Action callbacks** are passed as arrow-wrapped function properties:

```qml
ThemeSwitcher {
    setAccent: (name, hex) => shellRoot.setAccent(name, hex)
}
```

The arrow wrapping captures `shellRoot` so `this` doesn't get lost.

**Adding a new modal** (notifications, launcher, lock): write `Foo.qml`, add a third `Variants { Foo { ... } }` block in `shell.qml`. No edits to existing files.

### Critical gotcha: `FileView.text` is a method, not a property

Accessing `colorsFile.text` returns the function reference. Capture via signal:

```qml
FileView {
    onLoaded: baseContents = text()
}
property string baseContents: ""
```

Bindings on `baseContents` re-evaluate on change. Bindings on `colorsFile.text` do not.

### Bar (top)

- `barHeight: 48`, `cornerSize: 16` (= `gaps_out` 8 + window rounding 8).
- `implicitHeight: barHeight + cornerSize`, `exclusiveZone: barHeight` — corners overhang into workspace without reserving extra space.
- Layout sections anchor `verticalCenter: barBg.verticalCenter` (not parent's), so they sit in the bar text area, not the corner overhang.
- Inverse corners (Caelestia style) drawn with `Shape` + `PathArc`. Same color as bar.
- System modules (volume/bluetooth/battery) poll via `Process` + `StdioCollector` every 2s. No native Quickshell services used (more reliable across QS versions).

### App launcher (centered, drop-down)

- Hangs from the bar with symmetric inverse top-LEFT/top-RIGHT corners (mirrors the bar's bottom corners) and rounded bottom-LEFT/bottom-RIGHT.
- Triggered via IPC: `qs ipc call launcher toggle | show | hide` (Hyprland keybinds wired in `keybinds.conf`).
- IpcHandler lives in `shell.qml` (one global instance); `launcherOpen` state drives the panel via Variants per screen.
- Search input + ListView of `DesktopEntries.applications.values` (filtered by name/genericName/comment, sorted by name). Up/Down to navigate, Enter to launch, Esc to close.
- Icons resolved via `Quickshell.iconPath(name)` + `IconImage` (uses current icon theme).
- `WlrLayershell.keyboardFocus: OnDemand` while open so the search input receives input.

### Theme switcher (bottom, hover-reveal)

- `PanelWindow` anchored bottom-left-right (full width); a centered `Item` holds the visible panel.
- `exclusiveZone: 0` (overlay, no space reservation).
- `Behavior on implicitHeight` animates between `collapsedHeight: 8` (peek strip) and `expandedHeight: 260` (full panel).
- `MouseArea` on the centered `Item` triggers `open = true/false`.
- Body Shape uses `safeTopRadius = min(topRadius, height/2)` so the collapsed peek is a small pill, not a broken arc.
- Inverse corners at bottom fade in only when expanded (`opacity: panel.height > invRadius*2 ? 1 : 0`) — hidden when only the trigger strip shows.

## No hardcoded colors

**Any color value used anywhere in dotfiles must resolve to `colors.json` (or a palette file derived from it).** Never paste a literal `#xxxxxx` into a config or template.

How each tool references colors:

| Tool | Mechanism |
|---|---|
| Quickshell QML | `cBg`, `cFg`, `cPrimary`, etc. properties bound to `colors.ui.*`; ANSI accessed via `colors.ansi.*` |
| oh-my-posh | palette refs `p:primary`, `p:accent`, `p:yellow`, etc. (palette is generated from `colors.json.ui` + `colors.json.ansi`) |
| kitty | named directives (`background`, `foreground`, `color0..15`, `url_color`) written by render script |
| GTK | `@define-color window_bg_color`/etc. for libadwaita; class selectors use generated rgba values |
| bash | `$BG`, `$FG`, `$PRIMARY`, etc. exports (generated `bashrc/colors`) |
| Hyprland | `$BG = ...`, `$PRIMARY = ...` could be similarly generated if needed (currently uses static rounding/gap values, no colors) |

The oh-my-posh palette is composed from BOTH `colors.json.ui` and `colors.json.ansi`, exposed as:

- `p:bg`, `p:mantle`, `p:fg`, `p:primary`, `p:accent`, `p:url`, `p:muted`, `p:border` — semantic UI colors (live-updating with override)
- `p:black`, `p:red`, `p:green`, `p:yellow`, `p:blue`, `p:magenta`, `p:cyan`, `p:white` (+ `bright_*` variants) — ANSI palette (stable; "always this hue regardless of accent")

ANSI refs are perfect for "I want a fixed hue" (git uses `p:yellow` so it contrasts with any accent).

### Known exception: `mochaAccents` array in `shell.qml`

The 14 Catppuccin Mocha accent options listed in `shell.qml` are hardcoded hex values. They represent *available* theme options, not the active theme. If we later add a `palettes/` directory of theme options, move them there.

## Branch icon

The `git` segment uses `branch_icon` property (not template prefix) — oh-my-posh auto-prepends it to `.HEAD`. Setting both causes a duplicate. Current value: ` ` (Devicons git branch glyph).

## Accent picker writes 9 fields

Clicking a Catppuccin Mocha accent writes via inline Python to override:

- `theme.gtk` → `catppuccin-mocha-<name>-standard+default`
- `theme.cursor` → `catppuccin-mocha-<name>-cursors`
- `ui.primary`, `ui.accent`, `ui.url` → accent hex (all three unified)
- `ui.bg` → accent × 0.13 (tinted dark)
- `ui.mantle` → accent × 0.10 (slightly darker)
- `ui.muted` → accent × 0.40
- `ui.border` → accent × 0.28

Untouched: `ansi.*` (terminal apps assume "red is red"), `ui.fg` (readability).

## File layout

```
dotfiles/
├── new_install.sh              # orchestrator (runs scripts/* in order)
├── CLAUDE.md                   # this file
├── packages/{pacman,aur}       # `- pkgname` per line
├── scripts/                    # one concern each, independently runnable
│   ├── install_pacman_packages.sh
│   ├── install_yay.sh
│   ├── install_aur_packages.sh
│   ├── install_gpu_drivers.sh   # interactive picker
│   ├── install_colloid_icons.sh # git clone + ./install.sh -b
│   ├── enable_services.sh       # sddm, NM, bluetooth, hyprpolkitagent (user)
│   ├── render_configs.sh        # colors.json + override → generated configs
│   ├── symlink_dotfiles.sh      # .config/* → ~/.config/, home/* → ~/
│   ├── apply_gsettings.sh       # gsettings + hyprctl setcursor
│   ├── reload_all.sh            # IPC live-reload
│   └── hook_bashrc.sh           # ~/.bashrc sources bashrc/ fragments
├── templates/                  # hand-edited bases for generators
│   └── ohmyposh.omp.json        # prompt structure (no palette)
├── .config/                    # → ~/.config/
└── home/                       # → $HOME (.gtkrc-2.0 is generated)
```

## Conventions

- **Generated files are gitignored.** Source-of-truth + scripts are tracked. Templates for hybrid files (oh-my-posh) live in `templates/`.
- **Script naming**: verb_object (`install_pacman_packages.sh`, `render_configs.sh`). Each script does one thing and is runnable on its own.
- **Override-first edits**: settings UI writes override file, never base. User commits override → base only when explicitly desired.
- **Live reload first, restart fallback**: prefer IPC. Document where it's impossible (GTK).
- **No backwards-compatibility shims**: the user is iterating actively; obsolete code gets deleted, not deprecated.
- **Don't pivot architecture from referenced material**: `origin/v1-(glass)` is for context, not a directive to mimic.

## Hyprland config (`.config/hypr/`)

- Layout: **dwindle with `smart_split = true`** — cursor-position determines split direction. Avoids aspect-ratio surprises on near-square monitors.
- `general.gaps_out = 8`, `decoration.rounding = 8` — paired with bar's `cornerSize = 16`.
- Autostart: `nm-applet --indicator`, `livepaper --restore`, `qs` (Quickshell).
- Session: **uwsm**. System services need explicit enable; user services start via session.

## Catppuccin GTK theme: `box.vertical headerbar` workaround

Catppuccin's GTK4 CSS only paints `headerbar` background inside `box.vertical`. Plain `headerbar` (e.g., Electron menu bars) falls through to default light. Our `gtk.css` includes both `headerbar` and `box.vertical headerbar` selectors with the same transparent override.

## VM-specific notes (current dev environment)

- Resolution `1914×999` is near-square. Without `smart_split = true`, dwindle splits 3rd window side-by-side (workspace half is ~949×945, marginally landscape).
- Software rendering (no GPU passthrough). Hover events drop occasionally; not a bug in our code.

## Memory file references

User has memory entries that this project context complements. Don't restate user-level preferences here; they live in `~/.claude/projects/-home-sun-dotfiles/memory/`.
