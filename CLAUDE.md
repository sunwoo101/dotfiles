# Dotfiles v2

Hyprland + Quickshell on Arch. Catppuccin Mocha base. Single source of truth for colors with live reload across kitty, hyprland, oh-my-posh, GTK, and the bar.

## Keeping this file current (instructions to Claude)

**This file is a contract.** Whenever you make a non-trivial change to the project — new component, new architectural pattern, a fix that depends on a non-obvious invariant, a new generated file, a new IPC handler, a Hyprland keybind change, an animation tier, a discovered Qt/Wayland gotcha — update CLAUDE.md in the same change so it stays in sync with the code. You don't need to be asked.

Update rules:
- Add brief, declarative entries (a sentence or two) to the relevant section. Don't dump narrative.
- If a fix depends on a non-obvious invariant ("this Loader must have `enabled: false` AND `z: 0`"), document the invariant AND a one-line "why" so the next agent doesn't undo it. Real-world consequence is great context.
- If you delete code or remove a file, delete its mention here too.
- File-tree diagrams, generated-file tables, and animation-tier tables must mirror reality. Update them when files are added/removed/renamed.
- New `.qml` files, new modal/popout patterns, new shell scripts → add to the relevant inventory section.

Don't add CLAUDE.md updates as a separate commit — fold them into the same change as the code.

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
| `.config/hypr/conf/colors.conf` | render_configs.sh (`$ACCENT`, `$PRIMARY`, etc. — sourced from `visuals.conf`) |
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

Multi-file structure. `shell.qml` holds shared state; per-screen panels live in their own files and are instantiated via `Variants`. **All top-bar drop-down popouts (volume, notifications, calendar, power) share one Popouts wrapper window** that morphs between contents — same window, animated `panel.x`/`width`/`height`, fading content. AppLauncher and ThemeSwitcher have their own positioning needs and stay as standalone `Modal` instances.

```
.config/quickshell/
├── shell.qml                   # entry point: state (colors, theme, popout, system) + Variants
├── Bar.qml                     # top bar PanelWindow (workspaces, clock, modules, corners).
│                               #   Exposes anchor X for each popout trigger:
│                               #     volumeRightX, bellRightX (right-side popouts)
│                               #     clockLeftX, powerLeftX  (left-side popouts)
├── Modal.qml                   # base PanelWindow for single-content standalone modals
│                               #   (AppLauncher, ThemeSwitcher). Derives corner config
│                               #   from edge+align, animates implicitWidth + implicitHeight
│                               #   at 280ms OutCubic (matches Popouts feel).
├── Popouts.qml                 # ONE PanelWindow per screen hosting all 4 bar popouts. Each
│                               #   has anchorSide ("left"|"right") + anchor X. Loaders stay
│                               #   active so morph starts instantly. SVG path adapts:
│                               #   inverse top corners + rounded bottom on sides not at a
│                               #   screen edge; flush at screen edges.
├── VolumeContent.qml           # MPRIS card + sink slider
├── NotificationsContent.qml    # popup + center, grouped by appName with click-to-expand
│                               #   per-group chevron + per-notif age (e.g. "5m")
├── CalendarContent.qml         # month grid, prev/next nav, today highlighted
├── PowerMenuContent.qml        # lock/hibernate/logout/reboot/shutdown
├── AppLauncher.qml             # centered top-anchored Modal (closeOnOutsideClick)
├── ThemeSwitcher.qml           # bottom centered Modal — accent grid, dark/light, reset
├── EdgeBumper.qml              # reusable invisible hover trigger anchored to a screen
│                               #   edge; bleeds 1 px past the edge to dodge Wayland's
│                               #   pointer-leave at screen-edge row. Pair with any
│                               #   non-bar Modal via shellRoot._bumperHover registry.
├── Lock.qml                    # WlSessionLock screen with PamContext auth
├── CardButton.qml              # reusable button surface (subtle fill + cPrimary border)
└── TintedIcon.qml              # symbolic SVG via Quickshell.iconPath, recolored by MultiEffect
```

**State stays in `shell.qml`** — colors loading (FileView × 2), `cBg`/`cFg`/`cPrimary`/etc., theme state (`currentAccent`, `currentFlavor`), action functions (`setAccent`, `toggleFlavor`, `clearOverride`), system polling (`volumeText`, `batteryText`, `btConnected`). Children declare `required property` for what they need; `shell.qml` passes them via the Variants delegate.

**Action callbacks** are passed as arrow-wrapped function properties:

```qml
ThemeSwitcher {
    setAccent: (name, hex) => shellRoot.setAccent(name, hex)
}
```

The arrow wrapping captures `shellRoot` so `this` doesn't get lost.

**Adding a new bar popout** (any of the 4 quadrants of the bar):

1. Write `FooContent.qml` — an `Item` with `implicitWidth` / `implicitHeight` declared. No `PanelWindow`.
2. In `Popouts.qml`:
   - Add a `Loader { id: fooLoader }` next to the existing ones inside `contentArea` (anchor `right` for right-side popouts, `left` for left-side; `active: true; opacity: current === "foo" ? 1 : 0`).
   - Extend `_config(name)` with a `{ side, anchor, item }` entry.
3. In `Bar.qml`: expose `fooLeftX` (or `fooRightX`) for the trigger icon's anchor. Add a `MouseArea` that calls `bar.popoutEnter("foo")` `onEntered`. The wrapper `HoverHandler` on `leftSection`/`rightSection` already handles leave.
4. In `shell.qml`: add `Foo` to the `_setBarAnchor` payload so the anchor X flows through; route the new anchor on `Popouts` via `_barAnchors`.
5. The corner shape adapts automatically based on whether `anchor` is at a screen edge.

No new PanelWindow created. No new animation timing to tune. Same wrapper, same morph behavior.

**Adding a new standalone modal** (different positioning rules — e.g. centered drop-down, fullscreen): extend `Modal { edge: ...; align: ... }` with your content; add a `Variants { Foo { ... } }` block in `shell.qml`. Corner config and SVG path derived from `edge`+`align`. Same 280ms OutCubic animation timing.

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
- Volume reactive via `Quickshell.Services.Pipewire` (`Pipewire.defaultAudioSink.audio.volume/.muted` with `PwObjectTracker`). Battery + Bluetooth still poll every 2s via `Process` + `StdioCollector`.
- Bar exposes `volumeRightX` and `bellRightX` (screen-relative X of icon right edges). `shell.qml` collects them into `_barAnchors[screenName]` so the matching `Popouts` panel anchors below the right icon.
- Right side is wrapped in a `HoverHandler` so the popout stays open while the cursor crosses BETWEEN icons (volume → bluetooth → battery → bell). Per-icon `MouseArea` only fires `onEntered` to set which popout to show; the wrapper's `onHoveredChanged` decides when to close.

### Popouts wrapper (volume + notifications + calendar + power)

`Popouts.qml` is one PanelWindow per side per screen — instantiated twice via `Variants` (`side: "right"` and `side: "left"`). Right side hosts volume + notifications; left side hosts calendar + power. **Cross-side hover (e.g. calendar → volume) is a close-and-open of two independent windows, not a slide across the screen.** Same-side switches morph: the inner `panel` Item animates `x`/`width`/`height` over 280ms `OutCubic`; content fades over the same duration.

`_activeAnchor` is managed imperatively (Connections → `onCurConfigChanged`):
- **Opening** (closed → popout): `_activeAnchor` is set instantly to the new target (Behavior disabled), then `panel.width` animates 0 → target. Result: the anchor edge stays pinned (right edge for right-side, left edge for left-side); the panel grows away from it.
- **Switching** (popout A → popout B on same side): `_activeAnchor` animates from A's anchor to B's; `panel.width` animates from A's width to B's. Smooth morph.
- **Closing** (popout → null): `_activeAnchor` is left untouched; `panel.width` animates → 0. Anchor edge stays pinned; panel shrinks toward it.

- `WlrLayershell.layer: Overlay` so the cursor at the bar/popout overlap is always on the popout — bar (`Top`) doesn't steal hover.
- Input `mask` cuts out the top `barHeight` strip so bar's MouseAreas still receive hover events (for switching popouts via icon hover).
- Each popout has `{ side: "left"|"right", anchor: <X> }`:
  - `volume` → side right, anchor `volumeRightX` (volume icon's right edge).
  - `notifications` → side right, anchor `root.width` (flush against screen edge).
  - `calendar` → side left, anchor `clockLeftX` (clock's left edge).
  - `power` → side left, anchor `powerLeftX` (currently 0 — flush against screen left edge).
- Corner config adapts to edge state:
  - `_leftAtEdge` (panel's left at x=0) → TL+BL flush.
  - `_rightAtEdge` (panel's right at root.width) → TR+BR flush.
  - Otherwise outer (top) is inverse and bottom is rounded.
- `contentArea`'s `leftMargin`/`rightMargin` flip between `0` and `invRadius` to match the corner config (so content doesn't bleed into the inverse-curve area).
- `panel.clip: true` hides content overflow during morph (e.g. notifs' wider content as the wrapper shrinks toward volume's narrower size).

#### Notifications grouping + age labels

`NotificationsContent` groups by `appName`. Single-notif groups render as one card; multi-notif groups render compactly with the latest visible and a chevron — clicking the card or header toggles expand. Group close-X dismisses every notif in that group; in expanded mode each notif also has its own small close-X.

Arrival timestamps live in `shellRoot.notifReceivedAt` (map keyed by `Notification.id`), set in `popNotif` and deleted in the `closed` handler. Bound age labels read from this map plus `shellRoot._notifNow`, which a 30 s `Timer` reassigns to refresh "5m"-style labels without redrawing per-second. Per-app expand state is local to `NotificationsContent.expandedGroups` (map keyed by appName); cleared automatically when the popout content is destroyed via Loader inactive.

### Standalone modals (AppLauncher, ThemeSwitcher)

Both extend `Modal.qml`. The base derives corner config from `edge` + `align` and builds the SVG path generically. **Animates BOTH `implicitWidth` and `implicitHeight`** at 280ms `OutCubic` (panel grows diagonally from its anchor corner — same drawer feel as Popouts).

- `WlrLayershell.layer: Overlay`. Input mask excludes top `barHeight` strip on top-anchored modals.
- `closeOnOutsideClick: true` (AppLauncher only) — expands the PanelWindow to fullscreen and adds a transparent click-catcher MouseArea behind the visible panel. `_animatingClose` linger keeps `_fullscreen=true` until the close animation finishes so the panel has somewhere to animate inside.

#### Bar popout IPC

The Popouts wrapper exposes IPC for the power menu:

- `qs ipc call power show | hide | toggle` — `popoutShow("power")` / `popoutHide()`.

`shellRoot.popoutForced` is the IPC-driven name; `popoutHover` overrides it whenever the user hovers a different bar trigger. Both feed `popoutCurrent`. Closing a popout from inside (e.g. clicking a power-menu action) goes through `requestClose` → `popoutHide()`.

#### AppLauncher

- `edge: "top"; align: "center"` — symmetric inverse top corners, rounded bottom corners.
- IPC: `qs ipc call launcher show | hide | toggle`.
- `WlrLayershell.keyboardFocus: Exclusive` while open so the search input receives input. Focus is grabbed via a 60ms timer after open (`Qt.callLater` fires too early before the surface is mapped).
- Click outside closes (via `closeOnOutsideClick`).

#### ThemeSwitcher

- `edge: "bottom"; align: "center"` — at screen-bottom edge, so BL/BR are flush; rounded TL/TR.
- Always-on peek strip (height `collapsedHeight: 8`) expands to `expandedHeight: 260` on hover. Internal grace timer (250ms) absorbs Wayland leave/enter events that fire during surface resize.
- Sets `surfaceHeight: expandedHeight` so the Wayland layer surface stays a constant 260 px and only the inner panel animates 8 ↔ 260. Without this, the compositor's repeated surface-resize cycle leaves a ghost copy of the inverse-rounded bottom corners visible while the panel collapses (looks like a "second bar with inverse rounds" lagging behind the visible panel).
- Modal promotes inverse corners to flush when `H < invRadius`. At the 8 px peek the elliptical inverse arc squashes into a near-flat stub that reads as a stray curl rather than a corner; flat-bottom looks intentional. Transition happens late in the collapse animation so the snap is almost invisible.
- Hover detection comes from **two sources** combined via a counter (`_hoverSources` in `ThemeSwitcher.qml`, mirrors `shellRoot._hoverDepth`): Modal's own root-level `HoverHandler` and an `EdgeBumper` at the screen bottom. See "Adding a non-bar edge modal" below for the reusable pattern.

#### Adding a non-bar edge modal

For a Modal anchored to a screen edge (top or bottom) that hover-triggers from cursor proximity to that edge, you need an `EdgeBumper` because Wayland sends a pointer-leave when the cursor lands on the very last pixel row of a surface — closing the modal mid-open. The bumper bleeds 1 px past the edge on its own invisible surface so the visible modal stays fully on-screen.

1. Modal subclass: declare `property bool externalHovered: false` and `onExternalHoveredChanged: externalHovered ? panelEnter() : panelLeave()`. Implement `_hoverSources` counter so `onPanelEnter`/`onPanelLeave` increment/decrement instead of unconditionally toggling — keeps hover stable when the cursor crosses between the bumper and the visible panel (see `ThemeSwitcher.qml` for the reference shape).
2. shell.qml: add the modal to its `Variants` block as usual, with `externalHovered: shellRoot._bumperHovered("<modalName>", modelData.name)`.
3. shell.qml: add a parallel `Variants` block for `EdgeBumper` with `edge: "bottom"` (or `"top"`), `hitWidth: <modal.panelTotalWidth>`, and `onBumperEnter`/`onBumperLeave` calling `shellRoot._setBumperHover("<modalName>", modelData.name, true/false)`.

`<modalName>` is any unique string. The registry (`_bumperHover`, `_bumperHovered`, `_setBumperHover`) is generic — no per-modal property needed.

## Style + consistency rules

### Buttons

`CardButton.qml` is the single source of truth for clickable button surfaces. Every interactive button in the shell uses it (PowerMenu cards, Volume mute + transport, ThemeSwitcher dark/light + reset, Calendar prev/next, Notifications "Clear all" + alt-action buttons + close-X, Bar workspace pills). Visual contract:

- Radius **12** by default; override to `height/2` for round (workspace pills, notification close-X).
- **Default fill** `Qt.rgba(cFg.r, cFg.g, cFg.b, 0.06)`; **highlighted fill** `Qt.rgba(..., 0.18)`.
- **Default border** `Qt.rgba(cFg.r, cFg.g, cFg.b, 0.10)`; **highlighted border** `cPrimary`.
- Border width **1** flat; transitions are 120ms `ColorAnimation`.
- `highlighted = hovered || active` — set `active: someBoundCondition` for stateful buttons (mute toggle, current workspace, selected accent), don't manually mirror `containsMouse`.
- Cursor is `PointingHandCursor` automatically.

**Don't hand-roll a button with Rectangle + MouseArea + custom hover colors.** The only intentional opt-out is the AppLauncher list delegate, which has tighter timing requirements (selection state synced with keyboard navigation) — its custom delegate stays in `AppLauncher.qml`.

### Sizing buttons in layouts

Use `implicitWidth` / `implicitHeight` on `CardButton` (not `Layout.preferredWidth/Height`) — the size hint then flows naturally through `RowLayout`/`ColumnLayout` AND establishes the correct hit-box for hover.

### Icons

`TintedIcon.qml` is the single source for symbolic icons. Two modes:

1. **Theme-resolved** (preferred, default): set `name`, leave `iconBase` empty. Resolves through `Quickshell.iconPath(name)`, which honors the active icon theme + inheritance chain (Colloid-Dark → Adwaita → hicolor for things Colloid doesn't ship, e.g. media controls).
2. **Direct path**: set `iconBase` to a directory and `name` is treated as `<iconBase>/<name>.svg`. Used by PowerMenu (`/.local/share/icons/Colloid-Dark/actions/symbolic/`) for icons known to exist at a specific location.

Tint is mandatory and should be `cFg` for body icons, `cPrimary` for accent/state icons.

**Use Colloid icons exclusively for any visual glyph.** No ASCII/Unicode text glyphs (▾ ▸ ✕ ✓ → etc.) — even small chevrons, close marks, and arrows go through `TintedIcon` so they pick up the icon theme's stroke weight and stay consistent with everything else. If Colloid doesn't ship the exact glyph, the inheritance chain falls back to Adwaita/hicolor; if even that doesn't exist, add a custom SVG to a known location and use the direct-path mode rather than falling back to text. Common names worth knowing: `pan-end-symbolic` / `pan-down-symbolic` (chevrons), `go-previous-symbolic` / `go-next-symbolic` (back/forward), `window-close-symbolic` (✕), `media-playback-{start,pause,stop}-symbolic`.

### Hover hit-boxes

Bar icons (volume, bell, power, clock) use a `MouseArea` with negative `anchors.topMargin` / `bottomMargin` so the hit-box fills the full bar height while the visible icon stays its natural size. Pattern: `anchors.topMargin: -(bar.barHeight - icon.height) / 2`.

### Modals are stateless containers; state lives in shell.qml

Each modal/popout content (`PowerMenuContent`, `VolumeContent`, `NotificationsContent`, `CalendarContent`) is a plain `Item` with declared `implicitWidth` / `implicitHeight` and no `PanelWindow`. State (`popoutHover`, `popoutForced`, `popoutCurrent`, `popped`, etc.) lives in `shell.qml`. Closing from inside the content goes through a `requestClose` signal → `popoutHide()`.

When adding a new bar popout, follow the recipe under "Adding a new bar popout" above — no new `PanelWindow` should be created.

### Inactive Loaders must be `enabled: false` AND `z: 0`

When stacking multiple Loaders inside the Popouts wrapper (one per popout), each Loader needs both:

- `enabled: root.current === "<thisName>"` — so click events don't leak through the visible content to invisible buttons in inactive Loaders. (Real-world consequence: clicking a calendar cell triggered a hidden Power-Menu shutdown button.)
- `z: root.current === "<thisName>" ? 1 : 0` — so the active Loader is z-topmost. On Qt6/Wayland, click events propagate through disabled siblings but **hover events do not**. Sibling Loaders may overlap in screen space (Power's 520×160 footprint covers Calendar's top-left prev/next buttons, for instance) — without the z bump, descendant `MouseArea` / `HoverHandler` on the active popout never see hover-enter when a disabled sibling is z-above them at the same point. Symptom: cursor changes to pointer on hover (cursor-shape uses a separate query path) but `containsMouse` stays false; click forces a hover re-evaluation, leaving the button stuck "hovered" until the next click.

### Inverse-corner arcs are elliptical at small H

When the panel collapses below `2 × invRadius`, a quarter-circle inverse arc can no longer fit (`R` clamps to `H/2`, but the carve width is `invRadius`). Two acceptable strategies:

1. **Modal.qml** — use elliptical arcs `A invRadius R 0 0 0 …`. The carve keeps its `invRadius` width as the panel shrinks; only the vertical extent (`ry = R`) squashes. Body left/right edges stay anchored at `invRadius` so they don't drift inward. Required for ThemeSwitcher's 8 px peek strip.
2. **Popouts.qml** — assumes the panel is always tall enough for `R = invRadius` to fit, so it uses simple circular arcs `A R R 0 0 0 …` and clamps `R` to `H/2` defensively.

Don't switch back to circular arcs in `Modal.qml` without also clamping the carve width — the chord-vs-radius constraint breaks at small H and SVG silently up-scales the radius, drifting the curves.

### Modal `surfaceHeight` vs inner panel height

`Modal.qml` separates the Wayland-layer surface size (`surfaceHeight`, drives `implicitHeight`) from the visible inner panel height (`panel.height`, animates with `contentHeight`). Default: `surfaceHeight: contentHeight` — surface and panel animate together (AppLauncher).

Override `surfaceHeight` to a constant when the panel toggles size frequently (e.g. ThemeSwitcher hover-collapse). Repeated layer-surface resize on Wayland produces a visible ghost of the previous-frame buffer. Keeping the surface a fixed size and animating only the inner panel avoids this.

The mask follows the visible panel rect (not the surface) when not in fullscreen mode, so the unused portion of an oversized surface still passes input through.

### Popout hover uses a depth counter, not per-icon timer

`shellRoot._hoverDepth` is incremented on each `popoutEnter` and decremented on each `popoutLeave`; the 250ms close timer only restarts when depth hits 0. **Don't replace this with a simpler per-icon `onExited → timer.restart` pattern** — Wayland's event delivery doesn't guarantee that icon A's `onExited` fires before icon B's `onEntered`, so naive timer restarts cause the popout to "open then instantly close" when sweeping the cursor between adjacent triggers (e.g. volume → bell). The counter ignores ordering: as long as cursor is on at least one trigger or on a panel, the timer stays stopped.

### Color sources

See "No hardcoded colors" below. Quickshell QML always uses `cBg/cFg/cPrimary/cAccent/cMuted/cRed`. Even semi-transparent overlays should be `Qt.rgba(cFg.r, cFg.g, cFg.b, alpha)` rather than literal hex.

## Animation timings

Pick the right tier for new animations:

- **Panel reveal / morph** (Popouts size + position, Modal open/close, ThemeSwitcher hover-expand): **280ms `OutCubic`**.
- **Cross-icon close grace timer**: 250ms (slightly less than animation, by design).
- **Workspace pill width** (active indicator): 240ms `OutCubic`.
- **Micro-interactions** (hover color/border tint, opacity changes, button hover): **120ms** (color animation, no easing curve).
- **Workspace number opacity** (active fade-in): 120ms (tier match).

Centralize via `Modal.animDuration` (default 280) when extending Modal. Popouts hardcodes 280 to match.

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
| Hyprland | `$ACCENT`, `$PRIMARY`, `$BG`, `$FG`, `$MUTED`, `$BORDER` defined in generated `.config/hypr/conf/colors.conf` (sourced from `visuals.conf`) — drives `col.active_border` and any other color refs |

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
