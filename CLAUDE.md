# Dotfiles v2

Hyprland + Quickshell on Arch. Catppuccin Mocha base. Single source of truth for colors with live reload across kitty, hyprland, oh-my-posh, GTK, and the bar.

## Keeping docs current

Each component has its own CLAUDE.md. Update the relevant file in the same change.

- `.config/quickshell/CLAUDE.md` — QML shell, bar, popouts, games, invariants
- `.config/hypr/CLAUDE.md` — Hyprland config, uwsm, special workspaces, session cleanup
- `sddm-theme/CLAUDE.md` — SDDM greeter
- `scripts/CLAUDE.md` — scripts overview

Root CLAUDE.md covers: color system, live reload, animation system, style conventions, file layout.

## Color system

**Source of truth:** `.config/colors.json` — base palette (`ansi`, `ui`, `opacity`, `theme.{gtk,cursor,icon,gtk2_fallback}`).

**Runtime override:** `~/.cache/quickshell/colors-override.json` — gitignored, written by the settings UI. Final = base shallow-merged with override (top-level sections merge per-key).

**Override fields** written by `scripts/apply_palette.py` on every accent/flavor change:
- `theme.{gtk,cursor}`, `ui.{bg,mantle,fg,primary,accent,url,muted,border}`, `opacity.bg`, `anim.speed`, `ansi.*`

### Generated files (gitignored)

All written by `render_configs.sh` from `colors.json` + override:

| Path | Notes |
|---|---|
| `.config/colors.conf` | kitty include; also sets `background_opacity` |
| `.config/bashrc/colors` | `export PRIMARY=...` |
| `.config/gtk-{3,4}.0/{gtk.css,settings.ini}` | |
| `.config/ohmyposh/theme.omp.json` | palette injected into `templates/ohmyposh.omp.json` |
| `.config/hypr/conf/colors.conf` | `$ACCENT`, `$PRIMARY`, etc.; sourced from `visuals.conf` |
| `home/.gtkrc-2.0` | |
| `sddm-theme/dotfiles/theme.conf` | read by greeter as `config.<key>` |

Hand-edited: `kitty.conf`, `hypr/conf/*`, `bashrc/{aliases,ohmyposh,env}`, `templates/*`, `quickshell/*`.

## Live reload pipeline

Order: `render_configs.sh` → `apply_gsettings.sh` → `reload_all.sh`. Quickshell's `applyChain` Process runs all three.

- **kitty** — `kitty @ set-colors` + `kitty @ set-background-opacity` per PID. Requires `allow_remote_control yes` + `listen_on unix:@mykitty`. Kitty appends `-{PID}` to socket names — iterate every PID.
- **hyprland** — `hyprctl reload`.
- **bash / oh-my-posh** — `bashrc/ohmyposh` traps `SIGUSR1` to re-run `oh-my-posh init`. `reload_all.sh` sends `pkill -USR1 -x bash`.
- **GTK** — no live reload; restart the app.

## Animation system

All durations defined in `.config/quickshell/Anims.qml` (singleton). Multiply all tiers by `Anims.multiplier` (default 1.0, persisted in override as `anim.speed`).

| Tier | Base | Curve | Used for |
|---|---|---|---|
| `Anims.panel` | 280 ms | OutCubic | Panel reveal/morph/close, content cross-fade |
| `Anims.pill` | 240 ms | OutCubic | Workspace pill width |
| `Anims.accent` | 140 ms | OutQuad | Accent circle scale/border |
| `Anims.micro` | 120 ms | ColorAnimation | Hover tints, button transitions |
| `Anims.pulse` | 800 ms | InOutSine | NeedsAttention slow-pulse |

The multiplier slider in ThemeSwitcherContent (range 0.1–5.0, step 0.1) writes `anim.speed` to the override and sets `Anims.multiplier` live.

## Accent picker

Clicking a Catppuccin Mocha accent writes 9 fields to the override via inline Python:
- `theme.gtk` → `catppuccin-mocha-<name>-standard+default`
- `theme.cursor` → `catppuccin-mocha-<name>-cursors`
- `ui.primary`, `ui.accent`, `ui.url` → accent hex
- `ui.bg` → accent × 0.13; `ui.mantle` × 0.10; `ui.muted` × 0.40; `ui.border` × 0.28
- `opacity.bg`, `anim.speed` — preserved from current override

Untouched: `ansi.*`, `ui.fg`.

## Style + consistency

### Colors

No literal `#xxxxxx` in configs/templates. All colors resolve through `colors.json`.

| Tool | Mechanism |
|---|---|
| Quickshell QML | `cBg`, `cFg`, `cPrimary`, `cAccent`, `cMuted`, `cRed`. Semi-transparent overlays via `Qt.rgba(cFg.r, cFg.g, cFg.b, alpha)` |
| oh-my-posh | `p:primary`, `p:accent`, `p:bg`, `p:mantle`, `p:fg`, `p:url`, `p:muted`, `p:border` (UI) + `p:black/red/...` (ANSI) |
| kitty | named directives (`background`, `color0..15`, `url_color`) |
| GTK | `@define-color window_bg_color`, etc. |
| bash | `$BG`, `$FG`, `$PRIMARY`, etc. |
| Hyprland | `$ACCENT`, `$PRIMARY`, `$BG`, `$FG`, `$MUTED`, `$BORDER` |

**Known exception:** the 14-element `mochaAccents` array in `shell.qml` is hardcoded hex — represents available options, not the active theme.

### Buttons

`CardButton.qml` is the single source of truth. Radius 12 (override to `height/2` for round). Default fill `Qt.rgba(cFg…, 0.06)`; highlighted 0.18. Border 1 px, transitions `Anims.micro`. Use `implicitWidth/Height` not `Layout.preferred*`. **Don't hand-roll buttons** — only intentional opt-out: AppLauncher list delegate.

### Icons

`TintedIcon.qml` for all symbolic icons. Theme-resolved via `Quickshell.iconPath(name)` (Colloid-Dark → Adwaita → hicolor). No ASCII/Unicode glyphs. **Exceptions:** tray icons (SNI full-color pixmaps, not theme-resolvable) and bar launcher logo (Nerd Font glyph).

### Hover hit-boxes

Bar icons use `MouseArea` with negative `anchors.{top,bottom}Margin` to fill bar height. Right-side icon spacing: 16 px between groups (tray→volume→bell); hover margins are sized to leave zero gap between adjacent zones.

### Bar icon behavior

Every bar icon with a popout opens on **hover**. Click is for in-place stateful toggles only (bell → mute, volume icon → audio mute).

## File layout

```
dotfiles/
├── install_x86_64.sh        # orchestrator (ARM: install_arm.sh)
├── packages/{pacman,aur}    # `- pkgname` per line
├── scripts/                 # see scripts/CLAUDE.md
├── templates/               # hand-edited bases for generators
├── sddm-theme/dotfiles/     # see sddm-theme/CLAUDE.md
├── .config/
│   ├── quickshell/          # see .config/quickshell/CLAUDE.md
│   ├── hypr/                # see .config/hypr/CLAUDE.md
│   ├── colors.json          # color source of truth
│   └── ...
└── home/                    # → $HOME
```

## Conventions

- Generated files are gitignored; source + scripts are tracked.
- Script naming: `verb_object`. Each does one thing, runnable on its own.
- Override-first edits: settings UI writes override, never base.
- Live reload first, restart fallback. Document where impossible (GTK).
- No backwards-compat shims — obsolete code gets deleted, not deprecated.

## Misc

- **oh-my-posh git** uses `branch_icon` property (not template prefix) — oh-my-posh auto-prepends to `.HEAD`. Setting both causes a duplicate.
- **Catppuccin GTK4 `headerbar` workaround** — Catppuccin's CSS only paints `headerbar` inside `box.vertical`. Plain `headerbar` (Electron menu bars) falls through to default light. `gtk.css` includes both selectors with the same transparent override.
