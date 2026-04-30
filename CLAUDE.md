# Dotfiles v2

Hyprland + Quickshell on Arch. Catppuccin Mocha base. Single source of truth for colors with live reload across kitty, hyprland, oh-my-posh, GTK, and the bar.

## Keeping this file current

This file is a contract. When you make a non-trivial change (new component, new invariant, new generated file, new IPC, new keybind, new animation tier, discovered Wayland gotcha), update CLAUDE.md in the same change.

- Brief declarative entries, not narrative.
- Document non-obvious invariants AND a one-line "why" so the next agent doesn't undo them.
- Remove deleted code's mention. Keep file trees, generated-file tables, and animation tiers in sync with reality.

## Source of truth

- `.config/colors.json` — base palette (`ansi`, `ui`, `opacity`, `theme.{gtk,cursor,icon,gtk2_fallback}`).
- `~/.cache/quickshell/colors-override.json` — runtime override, gitignored, outside the repo. Settings UI / accent picker writes here.
- Final = base shallow-merged with override (top-level sections like `ui`, `theme` merge per-key).

## Generated files (gitignored)

All written by `render_configs.sh` from `colors.json` + override:

| Path | Notes |
|---|---|
| `.config/colors.conf` | kitty include |
| `.config/bashrc/colors` | `export PRIMARY=...` |
| `.config/gtk-{3,4}.0/{gtk.css,settings.ini}` | |
| `.config/ohmyposh/theme.omp.json` | palette injected into `templates/ohmyposh.omp.json` |
| `.config/hypr/conf/colors.conf` | `$ACCENT`, `$PRIMARY`, etc.; sourced from `visuals.conf` |
| `home/.gtkrc-2.0` | |
| `sddm-theme/dotfiles/theme.conf` | read by greeter as `config.<key>` |

Hand-edited: `kitty.conf`, `hypr/conf/*`, `bashrc/{aliases,ohmyposh,env}`, `templates/*`, `quickshell/*`.

## Live reload pipeline

Order: `render_configs.sh` → `apply_gsettings.sh` → `reload_all.sh`. The Quickshell `applyChain` Process runs all three.

- **kitty** — `kitty @ --to=unix:@mykitty-{PID} set-colors --all --configured ~/.config/colors.conf`. Requires `allow_remote_control yes` + `listen_on unix:@mykitty`. Kitty appends `-{PID}` to abstract socket names — iterate every kitty PID.
- **hyprland** — `hyprctl reload`.
- **bash / oh-my-posh** — `bashrc/ohmyposh` traps `SIGUSR1` to re-run `oh-my-posh init`. `reload_all.sh` does `pkill -USR1 -x bash`.
- **GTK** — no live reload exists; restart the app. gsettings notifications reach libadwaita but not custom CSS.

## Quickshell (`.config/quickshell/`)

`shell.qml` holds shared state; per-screen panels are instantiated via `Variants`. **All bar drop-down popouts (volume, notifications, calendar, power, tray, workspaces) share one Popouts wrapper window per side per screen** that morphs between contents (animated `panel.x`/`width`/`height`, fading content). AppLauncher and ThemeSwitcher are standalone `Modal` instances.

```
shell.qml                # state (colors, theme, popout, system) + Variants
Bar.qml                  # top bar; exposes anchor X for each popout trigger
Modal.qml                # base PanelWindow for standalone modals
Popouts.qml              # wrapper hosting all bar popouts; SVG path adapts to edge state
{Volume,Notifications,Calendar,PowerMenu,Tray,Workspaces}Content.qml
AppLauncher.qml          # centered top-anchored Modal (closeOnOutsideClick)
ThemeSwitcher.qml        # bottom centered Modal — accent grid, dark/light, reset
EdgeBumper.qml           # invisible hover trigger anchored to a screen edge
Lock.qml                 # WlSessionLock screen with PamContext auth
CardButton.qml           # reusable button surface
TintedIcon.qml           # symbolic SVG via Quickshell.iconPath, recolored by MultiEffect
```

**State stays in shell.qml.** Children declare `required property` for what they need; `shell.qml` passes via the Variants delegate. Action callbacks are arrow-wrapped (`setAccent: (n,h) => shellRoot.setAccent(n,h)`) so `this` doesn't get lost.

**Per-screen ownership.** Every modal-style PanelWindow is instantiated per-monitor via `Variants`. Without scoping, hover/IPC state opens on every monitor at once. Each variant filters on an *owner screen name*:
- Popouts: `current: popoutOwner === modelData.name ? popoutCurrent : ""`. `popoutOwner` is set on `popoutEnter(name, screen)` (bar passes `modelData.name`) or `popoutShow(name)` (IPC; uses `focusedScreen`).
- AppLauncher: `open: launcherOpen && launcherOwner === modelData.name`. Owner captured from `focusedScreen` on `launcherShow()`.
- ThemeSwitcher: each screen has its own EdgeBumper, so hover is naturally local.

`focusedScreen` is `Hyprland.focusedWorkspace.monitor.name`.

### Adding a new bar popout

1. Write `FooContent.qml` — plain `Item` with `implicitWidth`/`implicitHeight`. No `PanelWindow`.
2. In `Popouts.qml`: add a `Loader { active: true; opacity: current === "foo" ? 1 : 0 }`. Extend `_config(name)` with `{ side, anchor, item }`.
3. In `Bar.qml`: expose `fooLeftX` / `fooRightX` for the trigger anchor. `MouseArea.onEntered: bar.popoutEnter("foo")`. The wrapper `HoverHandler` already handles leave.
4. In `shell.qml`: route the new anchor through `_setBarAnchor` / `_barAnchors`.

Corner shape adapts automatically. Same wrapper, same morph.

### Bar (top)

- `barHeight: 48`, `cornerSize: 16` (= `gaps_out` 8 + window rounding 8). `implicitHeight: barHeight + cornerSize`, `exclusiveZone: barHeight` so corners overhang into workspace without reserving extra space.
- Layout sections anchor `verticalCenter: barBg.verticalCenter` (not parent's), to sit in the bar text area, not the corner overhang.
- Inverse corners drawn with `Shape` + `PathArc`.
- Volume reactive via `Quickshell.Services.Pipewire`. Battery + Bluetooth poll every 2 s via `Process` + `StdioCollector`.
- Right side wrapped in `HoverHandler` so the popout stays open while crossing BETWEEN icons. Per-icon `MouseArea` only fires `onEntered` to set which popout; the wrapper's `onHoveredChanged` decides when to close.
- **System tray** — `Quickshell.Services.SystemTray` items at 20 px. Hover opens the menu inline via Popouts (name `tray:<index>`). Left-click activates, middle = `secondaryActivate`, scroll = `scroll(delta, false)`. **Tray icons render the SNI image as a plain `Image` (full color), not via TintedIcon** — most tray icons aren't symbolic and Colloid lookup is inconsistent. Documented exception to the "all glyphs through TintedIcon" rule.
- **Workspaces cluster** — non-interactive pills (no per-pill click). Whole cluster hovers → workspaces overview popout. Pills are plain Rectangles (subtle fill + 1 px border, `cPrimary` on active, 22 → 44 px on active over 240 ms `OutCubic`); not `CardButton` because that brings interactivity.
- **Launcher button** — distro logo via Nerd Font glyph (U+F300–U+F33F), not icon-theme path. `bar.osLogoGlyph` switches on `shellRoot.osId` (parsed from `/etc/os-release`). Falls back to generic Tux glyph. Avoids the `distributor-logo-*` icons (full-color, off-aesthetic) and `*-uptodate-symbolic` (those are checkmarks, not logos).
- **NeedsAttention** items get a small `cPrimary` dot below the icon with slow-pulse opacity. `Passive` items are filtered out per SNI spec.

### Tray menu (`TrayMenuContent.qml`)

- **Cascade** — root menu rightmost; hovering a parent for ~300 ms opens a child column to the left (`menuPath` array, `Row { layoutDirection: RightToLeft }`). 6 px gap between columns is inside the popout's input mask, so cursor handoff is safe.
- **Checkable / radio** — show check/radio glyph based on `buttonType` and `checkState`. Without this, nm-applet's "Enable Wi-Fi" looks stateless.
- **Mnemonic stripping** — `_stripMnemonic` removes single `_`, collapses `__` → `_`.
- **Tooltip header** at the top of the root column (`tooltipTitle` + `tooltipDescription`).
- **Lazy submenu** — handled by `QsMenuOpener`; each cascade column has its own opener.

### Popouts wrapper

One PanelWindow per side per screen — `Variants` × 2 (right hosts volume/notifications/tray; left hosts calendar/power). **Cross-side hover is close-and-open of two windows, not a slide.** Same-side switches morph (280 ms `OutCubic`).

`_activeAnchor` managed imperatively via `Connections.onCurConfigChanged`:
- Open: set anchor instantly (Behavior disabled), then animate `panel.width` 0 → target. Anchor edge stays pinned; panel grows away.
- Switch: animate both `_activeAnchor` and `panel.width` from A → B.
- Close: leave anchor untouched; animate `panel.width` → 0.

- `WlrLayershell.layer: Overlay` so the cursor at bar/popout overlap is on the popout (bar is `Top` → can't steal hover).
- Input `mask` cuts the top `barHeight` strip so bar MouseAreas still receive hover (for switching popouts via icon hover).
- Per popout `{ side, anchor }`: volume → right + `volumeRightX`; notifications → right + `root.width`; calendar → left + `clockLeftX`; power → left + `powerLeftX`; `tray:<i>` → right + `trayItemRightX` (Bar updates per tray-icon `onEntered`; single shared `trayLoader` resolves via `SystemTray.items.values[N]`).
- Corner config: `_leftAtEdge` → TL+BL flush; `_rightAtEdge` → TR+BR flush; otherwise top inverse + bottom rounded. `contentArea` left/right margins flip between `0` and `invRadius` to match. `panel.clip: true` hides overflow during morph.

### Notifications

`NotificationsContent` groups by `appName`. Single-notif groups render as one card; multi as compact card with chevron + click-to-expand. Group close-X dismisses all; per-notif close-X in expanded mode.

- Arrival timestamps in `shellRoot.notifReceivedAt` (map keyed by `Notification.id`); set in `popNotif`, deleted in the `closed` handler.
- `shellRoot._notifNow` reassigned every 30 s to refresh "5m" labels without per-second redraw.
- Per-app expand state local to `NotificationsContent.expandedGroups`; cleared via Loader inactive.
- **Mute** — bell click toggles `shellRoot.notifMuted`. Muted: `popNotif` still tracks but skips the toast strip; bell icon swaps to `notifications-disabled-symbolic` and tints `cMuted`. Hover still opens the popout.
- **Toast vs full list** — auto-popped toasts and the user-opened panel share one `NotificationsContent` instance; `hovered` (= Popouts `interactive` flag, true only when `popoutHover`/`popoutForced` is set) gates which is shown. Toast: src=`popped`, no Clear-all button, no empty state. Hover/click: src=full tracked list, Clear-all + empty state shown.

### Standalone modals (AppLauncher, ThemeSwitcher)

Both extend `Modal.qml` — derives corner config from `edge`+`align`, builds SVG path generically, animates BOTH `implicitWidth` and `implicitHeight` 280 ms `OutCubic` (drawer feel matching Popouts).

- `WlrLayershell.layer: Overlay`. Mask excludes top `barHeight` on top-anchored modals.
- `closeOnOutsideClick: true` (AppLauncher only) — expands the PanelWindow fullscreen + transparent click-catcher behind. `_animatingClose` keeps `_fullscreen=true` until the close animation finishes so the panel has somewhere to animate inside.

**AppLauncher** — top-center. IPC: `qs ipc call launcher show|hide|toggle`. `WlrLayershell.keyboardFocus: Exclusive` while open; focus grabbed via 60 ms timer (`Qt.callLater` fires too early before the surface is mapped).
- **Search** — fuzzy subsequence match across name / genericName / exec basename / keywords / comment, with field weights (name > keywords > comment), exact-prefix and word-boundary bonuses. Empty query sorts by frecency only.
- **Frecency** — per-`.desktop` `{count, lastUsed}` persisted at `~/.cache/quickshell/launcher-frecency.json` (gitignored, outside repo). Score = `count / (1 + ageDays/7)`. With a query: adds `ln(1 + frecency) × 25` boost — meaningful tiebreaker, never enough to outrank a strong fuzzy hit. Bumped on launch (Enter or click); written via base64-piped atomic temp+rename to avoid quoting issues with the JSON payload.

**ThemeSwitcher** — bottom-center. Peek strip `collapsedHeight: 8` → `expandedHeight: 260` on hover. Internal 250 ms grace timer absorbs Wayland leave/enter spam during surface resize.
- Sets `surfaceHeight: expandedHeight` so the Wayland layer surface stays a constant 260 px and only the inner panel animates 8 ↔ 260. Without this, repeated surface-resize leaves a ghost copy of the inverse-rounded bottom corners (looks like a "second bar with inverse rounds" lagging).
- Modal promotes inverse corners to flush when `H < invRadius`. At the 8 px peek the elliptical inverse arc squashes into a stub that reads as a stray curl — flat-bottom looks intentional.
- Hover from two sources combined via `_hoverSources` counter: Modal's root `HoverHandler` and an `EdgeBumper` at the screen bottom.

### Workspaces overview

Hover-driven Modal (top edge, centered), name `"workspaces"`. Thumbnails are PNGs captured by `grim`:

- Cache: `$XDG_RUNTIME_DIR/quickshell/workspace-thumbs/<id>.png`. Wiped on reboot.
- Trigger: every workspace focus change (after 300 ms settle so the switch animation is done) + 5 s periodic for the active workspace.
- **Atomic write** — `grim` writes `<id>.png.tmp`, shell renames to `<id>.png`. Without this, `Image` readers can pick up half-written files ("Unable to read image data").
- **Cache busting** — `Image.cache: false` isn't enough; QML doesn't re-read when the source URL string is unchanged. `shellRoot._workspaceThumbVersion` increments after each capture; per-card `Connections.onThumbVersionChanged` resets `Image.source` to "" then back to path. Don't try `?v=N` — QML treats `file://` URLs as literal filenames.
- Multi-monitor: captures only the focused workspace's monitor (`grim -o <name>`). Each workspace is bound to one monitor in Hyprland.

### Adding a non-bar edge modal

Wayland sends pointer-leave when the cursor lands on the very last pixel row of a surface — closing the modal mid-open. `EdgeBumper` bleeds 1 px past the edge on its own surface to dodge this.

1. Modal subclass: `property bool externalHovered: false; onExternalHoveredChanged: externalHovered ? panelEnter() : panelLeave()`. Implement `_hoverSources` counter so enter/leave increment/decrement instead of toggling — keeps hover stable when the cursor crosses between bumper and panel (see `ThemeSwitcher.qml`).
2. shell.qml: add the modal's `Variants` block with `externalHovered: shellRoot._bumperHovered("<name>", modelData.name)`.
3. shell.qml: parallel `Variants { EdgeBumper }` with `edge`, `hitWidth`, and `onBumperEnter/Leave` calling `_setBumperHover("<name>", modelData.name, ...)`.

Registry (`_bumperHover`, `_bumperHovered`, `_setBumperHover`) is generic — no per-modal property needed.

## Critical invariants & gotchas

### `FileView.text` is a method, not a property

Accessing `colorsFile.text` returns the function reference. Capture via signal:
```qml
FileView { onLoaded: baseContents = text() }
property string baseContents: ""
```
Bindings on `baseContents` re-evaluate on change. Bindings on `colorsFile.text` do not.

### Inactive Loaders need `enabled: false` AND `z: 0`

When stacking Loaders inside Popouts (one per popout), each needs both:
- `enabled: current === "<this>"` — clicks don't leak through to invisible buttons. (Real consequence: clicking a calendar cell triggered a hidden Power-Menu shutdown button.)
- `z: current === "<this>" ? 1 : 0` — active Loader is z-topmost. **On Qt6/Wayland, click events propagate through disabled siblings but hover events do not.** Without z bump, descendant `MouseArea`/`HoverHandler` never see hover-enter when a disabled sibling is z-above at the same point. Symptom: cursor changes to pointer but `containsMouse` stays false.

### Popout hover uses a depth counter, not per-icon timer

`shellRoot._hoverDepth` increments on `popoutEnter`, decrements on `popoutLeave`; close timer only restarts when depth hits 0. **Don't replace with per-icon `onExited → timer.restart`** — Wayland doesn't guarantee icon A's `onExited` fires before icon B's `onEntered`, so naive timer restarts cause "open then instantly close" when sweeping between adjacent triggers (e.g. volume → bell).

AppLauncher's `_launcherHoverDepth` follows the same shape. **AppLauncher has dual modes via `_launcherHoverManaged`**: hover-opened → managed (250 ms close on leave); IPC/click-opened → unmanaged (stays open until explicit close). The flag is only set when hover *opens* a closed launcher; entering an already-open IPC launcher doesn't switch modes.

### Inverse-corner arcs at small H

When the panel collapses below `2 × invRadius`, a quarter-circle inverse arc can no longer fit. Two valid strategies:
- `Modal.qml` — elliptical arcs (`A invRadius R 0 0 0 …`). Carve keeps `invRadius` width; only the vertical extent squashes. Required for ThemeSwitcher's 8 px peek.
- `Popouts.qml` — assumes panel is always tall enough; uses circular arcs (`A R R 0 0 0 …`) and clamps `R` to `H/2` defensively.

Don't switch back to circular arcs in `Modal.qml` without clamping the carve width — the chord-vs-radius constraint breaks at small H.

### Modal `surfaceHeight` vs panel height

`Modal.qml` separates the Wayland-layer surface size (`surfaceHeight` → `implicitHeight`) from the inner `panel.height`. Default `surfaceHeight: contentHeight` — they animate together (AppLauncher).

Override to a constant when the panel toggles size frequently (ThemeSwitcher): repeated layer-surface resize on Wayland leaves a visible ghost of the previous-frame buffer. Mask follows the visible panel rect so the unused portion still passes input through.

## Style + consistency

### Colors

Any color anywhere in dotfiles must resolve to `colors.json` (or a derived palette). No literal `#xxxxxx` in configs/templates.

| Tool | Mechanism |
|---|---|
| Quickshell QML | `cBg`, `cFg`, `cPrimary`, `cAccent`, `cMuted`, `cRed`. Semi-transparent overlays via `Qt.rgba(cFg.r, cFg.g, cFg.b, alpha)` |
| oh-my-posh | `p:primary`, `p:accent`, `p:bg`, `p:mantle`, `p:fg`, `p:url`, `p:muted`, `p:border` (UI; live-updating) + `p:black/red/...` (ANSI; stable) |
| kitty | named directives (`background`, `color0..15`, `url_color`) |
| GTK | `@define-color window_bg_color`, etc. |
| bash | `$BG`, `$FG`, `$PRIMARY`, etc. |
| Hyprland | `$ACCENT`, `$PRIMARY`, `$BG`, `$FG`, `$MUTED`, `$BORDER` |

ANSI refs are for "I want a fixed hue" (git uses `p:yellow` so it contrasts with any accent).

**Known exception:** the 14-element `mochaAccents` array in `shell.qml` is hardcoded hex — represents *available* options, not the active theme. Move to a `palettes/` dir if expanded.

### Buttons

`CardButton.qml` is the single source of truth. Used everywhere: PowerMenu, Volume mute/transport, ThemeSwitcher reset, Calendar prev/next, Notifications close-X, workspace pills, etc.

- Radius **12** (override to `height/2` for round).
- Default fill `Qt.rgba(cFg…, 0.06)`; highlighted `0.18`. Default border `0.10`; highlighted `cPrimary`. Border 1 px, transitions 120 ms `ColorAnimation`.
- `highlighted = hovered || active` — set `active:` for stateful buttons (mute, current workspace, selected accent); don't manually mirror `containsMouse`.
- `PointingHandCursor` automatic.

Use `implicitWidth/Height` (not `Layout.preferredWidth/Height`) so the size flows through layouts AND establishes the hover hit-box.

**Don't hand-roll a button** with Rectangle + MouseArea. Only intentional opt-out: AppLauncher list delegate (selection state synced with keyboard nav).

### Icons

`TintedIcon.qml` is the single source for symbolic icons.
- **Theme-resolved (default)** — set `name`, leave `iconBase` empty. Goes through `Quickshell.iconPath(name)`, honoring inheritance (Colloid-Dark → Adwaita → hicolor).
- **Direct path** — set `iconBase` to a directory; `name` becomes `<iconBase>/<name>.svg`. Used by PowerMenu.
- Tint mandatory: `cFg` body, `cPrimary` accent/state.

**Use Colloid icons exclusively.** No ASCII/Unicode glyphs (▾ ▸ ✕ ✓ →). Common names: `pan-{end,down}-symbolic` (chevrons), `go-{previous,next}-symbolic`, `window-close-symbolic`, `media-playback-{start,pause,stop}-symbolic`. Documented exceptions: tray icons (full-color, not theme-resolvable) and bar launcher logo (Nerd Font glyph).

### Hover hit-boxes

Bar icons use `MouseArea` with negative `anchors.{top,bottom}Margin` so the hit-box fills bar height while the visible icon stays natural size. Pattern: `anchors.topMargin: -(bar.barHeight - icon.height) / 2`.

### Bar icons hover-trigger; click is for in-place toggles

Every bar icon with an associated popout/window opens it on **hover**. Click is reserved for stateful toggles (bell click → mute, volume mute icon → audio mute). Don't introduce a click-to-open icon.

Two state machines:
- **Bar popouts** — `popoutEnter(name, screen)` / `popoutLeave()`. Single global `_hoverDepth`, single 250 ms close timer, single `popoutCurrent` + `popoutOwner`.
- **Standalone modals (launcher, ThemeSwitcher)** — same shape (depth counter, close timer at zero) but local state.

### Modals are stateless containers

Each `*Content.qml` is a plain `Item` with `implicitWidth`/`implicitHeight` and no `PanelWindow`. State (`popoutHover`, `popoutForced`, `popoutCurrent`) lives in `shell.qml`. Inside-content close goes through a `requestClose` signal → `popoutHide()`.

## Animation timings

| Tier | Duration | Curve | Used for |
|---|---|---|---|
| Panel reveal/morph | 280 ms | OutCubic | Popouts size+position, Modal open/close, ThemeSwitcher hover-expand |
| Cross-icon close grace | 250 ms | — | Popout close timer (slightly less than panel anim, by design) |
| Workspace pill width | 240 ms | OutCubic | active indicator |
| Micro-interactions | 120 ms | ColorAnimation | hover tint, opacity, button hover |

Centralize via `Modal.animDuration` (default 280) when extending Modal.

## Accent picker writes 9 fields

Clicking a Catppuccin Mocha accent writes via inline Python to override:
- `theme.gtk` → `catppuccin-mocha-<name>-standard+default`
- `theme.cursor` → `catppuccin-mocha-<name>-cursors`
- `ui.primary`, `ui.accent`, `ui.url` → accent hex (unified)
- `ui.bg` → accent × 0.13; `ui.mantle` × 0.10; `ui.muted` × 0.40; `ui.border` × 0.28

Untouched: `ansi.*` (terminal apps assume "red is red"), `ui.fg` (readability).

## File layout

```
dotfiles/
├── install_x86_64.sh        # orchestrator (ARM variant: install_arm.sh)
├── packages/{pacman,aur}    # `- pkgname` per line
├── scripts/                 # one concern each, runnable on its own
│   ├── configure_pacman.sh    # enable [multilib]; point SDDM SessionDir at
│   │                          #   /usr/local/share/wayland-sessions/ which
│   │                          #   only contains hyprland-uwsm.desktop (so
│   │                          #   plain hyprland.desktop isn't listed)
│   ├── install_{pacman,aur,gpu_drivers,colloid_icons,yay,sddm_theme}.sh
│   ├── enable_services.sh     # sddm, NM, bluetooth, hyprpolkitagent
│   ├── render_configs.sh      # colors.json + override → generated configs
│   ├── symlink_dotfiles.sh    # .config/* → ~/.config/, home/* → ~/
│   ├── apply_gsettings.sh     # gsettings + hyprctl setcursor
│   ├── reload_all.sh          # IPC live-reload
│   └── hook_bashrc.sh
├── templates/               # hand-edited bases for generators
├── sddm-theme/dotfiles/     # SDDM greeter (Main.qml + metadata.desktop; theme.conf gen'd)
├── .config/                 # → ~/.config/
└── home/                    # → $HOME (.gtkrc-2.0 generated)
```

## Conventions

- Generated files are gitignored; source-of-truth + scripts are tracked.
- Script naming: `verb_object`. Each does one thing, runnable on its own.
- Override-first edits: settings UI writes override, never base.
- Live reload first, restart fallback. Document where it's impossible (GTK).
- No backwards-compat shims — obsolete code gets deleted, not deprecated.
- `origin/v1-(glass)` is for context, not a directive to mimic.

## Hyprland (`.config/hypr/`)

- Layout: **dwindle with `smart_split = true`** — cursor-position determines split direction. Avoids aspect-ratio surprises on near-square monitors.
- `gaps_out = 8`, `rounding = 8` — paired with bar's `cornerSize = 16`.
- Autostart: `nm-applet --indicator`, `blueman-applet`, `livepaper`, `qs`. XDG `~/.config/autostart/*.desktop` entries are launched by `dex --autostart --environment Hyprland` (Hyprland doesn't honor the spec on its own). **dex is exec-once'd bare, not via `uwsm app --`** — dex forks each entry then exits, so wrapping it would collapse every spawned app into a single `app-*-dex.scope` instead of letting them run as plain Hyprland-parented processes. Trade-off accepted: those four apps don't get their own scope units.
- **Don't try to replace dex with `systemctl --user start xdg-desktop-autostart.target`.** `systemd-xdg-autostart-generator` does generate `app-*@autostart.service` units from `~/.config/autostart/*.desktop`, but under uwsm `-e` mode there is no path to activate them: both `xdg-desktop-autostart.target` and `graphical-session.target` are `RefuseManualStart=yes`, and `app-graphical.slice` is `PartOf=graphical-session.target` (one-way teardown), **not `Wants=`** — so the slice activating does not pull the target up. With `-e` the wayland-wm service unit that would normally Want=graphical-session.target is skipped, and nothing else in the user manager wants it. The generated units exist but stay queued forever. dex is the only viable XDG-autostart mechanism in this setup.
- Session: **uwsm** via the package-shipped `hyprland-uwsm.desktop` (symlinked from `/usr/share/wayland-sessions/` into `/usr/local/share/wayland-sessions/` by `configure_pacman.sh` so SDDM only shows the uwsm-managed entry). Vanilla `Exec=uwsm start -e -D Hyprland hyprland.desktop`. `-e` mode skips the wayland-wm service unit, so `uwsm finalize` can't attach and `graphical-session.target` is never bound to compositor lifetime. `app-graphical.slice` is `PartOf=graphical-session.target` (one-way teardown), not `Wants=`, so the slice activating does NOT pull the target up — that's why `xdg-desktop-autostart.target` never fires under `-e` and dex is needed (see autostart bullet above). `autostart.conf` also runs `systemctl --user import-environment …` + `dbus-update-activation-environment --systemd …` to propagate Wayland env into the user systemd / dbus-activation environments so D-Bus-activated services (portals, future user services) get a working session — these are load-bearing under `-e` and stay even though they look redundant.
- **Logout-then-login cleanup** is handled by `hyprland-session-cleanup.service` (`.config/systemd/user/`, enabled by `enable_services.sh`). Under `-e` mode, nothing binds `graphical-session.target` to compositor lifetime — when something does end up activating it during a session (uwsm internals, a stray dependency, or `app-graphical.slice` on systemd versions where it `Wants=` instead of `PartOf=` the target), it stays active after Hyprland exits. The next `uwsm start -e` from SDDM then aborts ("compositor or graphical-session\* target is already active"), manifesting as black-screen relogin. The service runs `scripts/session-cleanup.sh`, which blocks on `socat -u UNIX-CONNECT:.socket2.sock` and on socket close stops `graphical-session.target` and `app-graphical.slice`. Load-bearing details:
  - The service stays in default `app.slice` — *not* `app-graphical.slice` — so it survives stopping its own targets. It is `WantedBy=default.target`, not `graphical-session.target`, for the same reason. Adding `PartOf=` or moving the install target defeats the mechanism.
  - The script's outer `while :;` loop is the real session-cycler. `Restart=always` is just a safety net; the daemon is meant to span many Hyprland sessions in one boot.
  - `find_live_socket` calls `hyprctl monitors` to verify a candidate instance dir is *actually responding*, not just a leftover `.socket2.sock` file. Hyprland's exit doesn't always reap the instance dir, and a stale file accepts `socat` connect()-then-immediate-close, which would fire cleanup in a tight loop. The `hyprctl` round-trip uses `.socket.sock` (command socket) and only succeeds against a live compositor.
  - After `socat` returns, re-run the liveness check before issuing cleanup — guards against transient socat hiccups (config reloads, IPC blips) being misread as session end.
- **Don't manually `uwsm app -- <daemon>` from a coordinator outside Hyprland's lifecycle** (e.g. iterating from a regular terminal). The scope outlives the compositor session; on the next logout it keeps `graphical-session.target` active and worsens the relogin issue above. Inside `autostart.conf` is fine — Hyprland's exit reaps everything in its process tree.
- **`uwsm app -- <cmd>` for every long-running autostart.** Wraps the process in a transient `app-*.scope` unit under `graphical-session.target`, so:
  - it gets restarted-on-crash semantics if you add a drop-in (plain `exec-once` does NOT — Hyprland fires it once and forgets),
  - it dies cleanly on logout (no orphaned daemons holding Wayland fds — see the xdg-desktop-portal SEGV note below),
  - logs go to the journal under a predictable unit name (`journalctl --user -u 'app-*special-workspace-guard*'`),
  - and it inherits the imported Wayland/DBus env from the systemd user manager, not just Hyprland's child env.
  Use it for: GUI apps (qs, nm-applet, blueman-applet), background daemons (livepaper, special-workspace-guard.sh), anything you'd otherwise want to `pkill` and restart manually. Do NOT wrap one-shot setup commands (`systemctl --user import-environment`, `hyprctl dispatch workspace 1`, `dbus-update-activation-environment`) — they exit immediately and the scope unit churn is wasted.
- No assumption about docker / per-user services — those are user-level concerns. If you want docker-desktop to start, `systemctl --user enable docker-desktop.service` plus a personal exec-once is the right path; dotfiles stays portable.
- **`misc.initial_workspace_tracking` MUST be 0** in `workspaces.conf`. With it non-zero, Hyprland pins each new window to the workspace its launcher was on, which overrides `windowrule = workspace special:<name> silent`. Since `dex --autostart` runs from workspace 1 (via the `hyprctl dispatch workspace 1` exec-once), every dex-launched app (discord, spotify, github-desktop, docker-desktop, kitty-special) would land on ws 1 instead of its special workspace. Don't set it to 1/2 without a concrete reason.
- **Pinned-class startup race.** Three distinct issues, all handled in `special-workspace-guard.sh`'s `openwindow` handler. (0) Floating popups/menus/tooltips/dialogs that apps spawn as separate toplevels on a special workspace (Electron context menus, file pickers, etc.) must be skipped — refocusing the pinned owner warps the cursor to its center (Hyprland's `focuswindow` default), yanking the user out of the menu they just opened. Guard checks `floating: true` via `hyprctl clients -j` and `continue`s before rogue tracking. Tiled windows on a special are the real rogues. (1) Electron apps (discord, github-desktop, docker-desktop) sometimes set WM_CLASS after their initial map, so the `windowrule = workspace special:X silent` rule misses at autostart and the window flashes on a regular workspace — guard catches `class in $pinned && workspace != expected`, dispatches `movetoworkspacesilent`. Don't try to fix this with `windowrulev2 initialClass` — the class is empty at map time, not just wrong. (2) Even when the windowrule DOES fire, `silent` only suppresses focus change — it does NOT keep the special hidden. Hyprland visibility-toggles the special whenever the first window appears on it, so every autostart app pops its special into view. Guard timestamps `pending_hide[ws]` on the pin event, then dispatches `togglespecialworkspace` on the matching `activespecial` show event (which arrives AFTER `openwindow`). The TTL (`pending_hide_ttl`, 5 s) is load-bearing — Hyprland renders only one special per monitor at a time, so at boot only the first-pinned app's special actually fires `special-show`; the others' flags would otherwise linger and incorrectly hide the workspace the first time the user pressed its toggle keybind. Also focus the show-event's monitor (`activespecial` payload's second field) before dispatching toggle and restore after — togglespecialworkspace acts on the focused monitor, and toggling from a different one inverts the internal state and breaks the first user keypress.
- **Special-workspace windows are pinned in place** by two complementary mechanisms. (1) `scripts/guard-move.sh` is the keybind wrapper — `swapwindow` and `movetoworkspace` go through `$guardMove` in `keybinds.conf` and NOP if the active window is on `special:*`. (2) `scripts/toggle-or-launch.sh` reconciles displacement at toggle time: before `togglespecialworkspace`, it sweeps `hyprctl clients` for any window of the target class not on `special:$workspace` and `movetoworkspacesilent`s it back. Covers `bindm` mouse drag — Hyprland reparents a window across monitors WITHOUT emitting `movewindow>>`/`movewindowv2>>`, so live event-based snap-back is impossible (was tried and removed). **Two-press semantics:** when the sweep actually moved a window, the script force-hides the special workspace (if currently visible on any monitor) and exits *without* calling the normal toggle — first press is "fix up to dormant state", second press summons. Without the force-hide, a `movetoworkspacesilent` into a previously-empty special leaves the overlay open after toggle and the keybind feels stuck-on. **Cross-monitor toggle:** `togglespecialworkspace` always acts on the focused monitor — pressing the keybind from monitor 2 while the overlay is open on monitor 1 would otherwise open a fresh overlay on 2 instead of toggling the existing one off (Hyprland's "drag overlay to focused monitor" default, which is wrong for a per-app summon keybind). `toggle_on <mon>` helper redirects the dispatch by `focusmonitor`-ing briefly and restoring. Used in BOTH the reconciled-fix-up path AND the normal-toggle path; whenever `specialWorkspace.name == target` matches a non-focused monitor, the toggle is sent there.
- **`special-workspace-guard.sh` event-loop shape is load-bearing.** The script reads Hyprland's event socket via `socat`, but the structure must be a single MAIN-shell loop with process substitution (`while :; do while IFS= read -r line; do …; done < <(socat -u UNIX-CONNECT:"$sock" -); done`), NOT the more obvious `while :; do socat …; done | while read …; done` pipeline. The pipeline form's left subshell was killed silently during Hyprland's autostart-time second `configreloaded` event (no signal trap caught it; subshells reset traps on fork) — daemon would log `boot`, process a few events, then exit cleanly with status 0 mid-loop. Single MAIN-shell form keeps everything in one process group and survives the storm. Do not refactor back to the pipeline.
- **HIS resolution in the daemon needs three fallbacks**, in order: own `$HYPRLAND_INSTANCE_SIGNATURE` env, `systemctl --user show-environment`, and a scan of `$XDG_RUNTIME_DIR/hypr/*/.socket2.sock` for an active socket. The runtime-dir scan is the load-bearing one — `import-environment` runs concurrently with the daemon's `uwsm app --` scope creation, so the systemd user manager may not have HIS in its env when our scope spawns. Hyprland creates the socket directory independently of any env propagation, so direct inspection always works. After resolving, `export HYPRLAND_INSTANCE_SIGNATURE=$his` so child `hyprctl` calls find the right socket.
- **`set -e` is wrong for the event daemon.** A single transient `hyprctl` failure (window closed mid-handle, IPC blip) must not terminate a long-running event reader. `set -u` only.
- **`special-workspace-guard.sh` MUST trap SIGUSR1/SIGUSR2.** `scripts/reload_all.sh` uses `pkill -USR1 -x bash` to nudge interactive shells into re-running `oh-my-posh init`. That matches every bash process by *name*, including this daemon — and bash's default action for SIGUSR1 is terminate. Without the trap, the daemon dies (status=0 in the EXIT trap, no signal trace because bash exits before handlers run) the first time the user changes theme / accent / colors. Trap is a no-op (`trap ':' USR1`); bash resumes the read loop after the handler runs. Symptom if removed: daemon "randomly" disappears mid-session, always coincident with a Quickshell apply-chain.
- `xdg-desktop-portal-hyprland.service` SEGVs on logout (its `atexit` cleanup writes to a Wayland connection Hyprland already tore down). Cosmetic — fresh portal spawns next session. `drkonqi` is in `packages/pacman` so the resulting coredump notification surfaces through the bar's notification daemon and is click-through-able for a backtrace; don't suppress it via `LimitCORE=0` drop-ins, that breaks the click-through.

## SDDM greeter (`sddm-theme/dotfiles/`)

Mirrors `Lock.qml`'s aesthetic — same centered clock + date + 320 × 48 password card with primary-tinted focus border. Activated via `/etc/sddm.conf.d/theme.conf` (`Current=dotfiles`) by `install_sddm_theme.sh`.

- `Theme-API=2.0`, `QtVersion=6` (Arch's sddm 0.21+). Imports unversioned.
- Colors come from `theme.conf` (gen'd by `render_configs.sh`), read in QML as `config.<key>`. Accent changes only reach the greeter on next `install_sddm_theme.sh` run — not part of the live `applyChain`.
- **Installed copy, not symlink.** SDDM runs as user `sddm` pre-login; symlinking into a user homedir risks unreadable target (encrypted/late-mounted).
- **No `Quickshell.iconPath` available.** Buttons use plain text labels styled like `CardButton` via inline `component CardBtn`. Documented exception to "all glyphs through TintedIcon" for the greeter context.
- **Model role indices** (stable since SDDM 0.20): `SessionModel.NameRole = Qt.UserRole + 4`; `UserModel.NameRole = Qt.UserRole + 1`.
- **Login is async** — `sddm.login(...)` returns immediately; wait for `loginSucceeded`/`loginFailed` via `Connections { target: sddm }`.
- **Multi-monitor — interactive UI is primary-only.** SDDM instantiates `Main.qml` once per screen with independent state. Without gating, clicking the session/user picker on one screen wouldn't propagate. Fix: `visible: primaryScreen` on every interactive element (password input, error text, bottom-left pickers, bottom-right power buttons). Clock + date stay on every screen so non-primary monitors aren't black. Canonical pattern (matches breeze/maldives); don't try to share state via a singleton.
- **User cycle button** mirrors the session button. `userModel.lastUser` is a name string, not an index — `_userIndexByName` translates on init.

## Misc

- **oh-my-posh git** uses the `branch_icon` property (not template prefix) — oh-my-posh auto-prepends to `.HEAD`. Setting both causes a duplicate.
- **Catppuccin GTK4 `headerbar` workaround** — Catppuccin's CSS only paints `headerbar` background inside `box.vertical`. Plain `headerbar` (e.g. Electron menu bars) falls through to default light. Our `gtk.css` includes both selectors with the same transparent override.
- **VM dev environment** — resolution `1914×999` is near-square (motivates `smart_split`); software rendering drops occasional hover events.

User-level preferences live in `~/.claude/projects/-home-sun-dotfiles/memory/` — don't restate here.
