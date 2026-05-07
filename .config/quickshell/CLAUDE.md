# Quickshell (`.config/quickshell/`)

Hyprland bar + popouts + games. `shell.qml` is the entry point and shared state store; everything else is instantiated per-monitor via `Variants`.

## File tree

```
shell.qml                  # shared state (colors, theme, popout, system) + Variants
Anims.qml                  # singleton animation duration tiers (panel/pill/accent/micro/pulse)
qmldir                     # registers Anims as singleton; lists all component types
Bar.qml                    # top bar; exposes anchor X per popout trigger
Modal.qml                  # base PanelWindow for all edge modals
Popouts.qml                # side-bar popout wrapper (volume/notif/tray/calendar/power)
EdgePopouts.qml            # top/bottom edge wrapper with peek mode
EdgeBumper.qml             # invisible hover trigger at screen edge
CardButton.qml             # reusable button surface
TintedIcon.qml             # symbolic SVG via Quickshell.iconPath + MultiEffect tint
Lock.qml                   # WlSessionLock screen with PamContext auth
AppLauncherContent.qml     # app launcher (top edge)
WorkspacesContent.qml      # workspace thumbnail overview (top edge)
ThemeSwitcherContent.qml   # accent + opacity + animation speed picker (bottom center)
StandardGameContent.qml    # osu Standard mini-game (bottom left)
ManiaGameContent.qml       # osu Mania 4-key game (bottom right)
NotificationsContent.qml   # notification list + toast
VolumeContent.qml          # volume slider + MPRIS media controls
CalendarContent.qml        # calendar (left side)
PowerMenuContent.qml       # power menu (left side)
TrayMenuContent.qml        # SNI tray menu cascade
```

## State management

**State stays in `shell.qml`.** Children declare `required property` for what they need; `shell.qml` passes via the Variants delegate. Callbacks are arrow-wrapped (`setAccent: (n,h) => shellRoot.setAccent(n,h)`) so `this` doesn't get lost.

**Per-screen ownership.** Every modal PanelWindow is instantiated per-monitor via `Variants`. Each filters on an owner screen name:
- Popouts: `current: popoutOwner === modelData.name ? popoutCurrent : ""`
- Top EdgePopouts: `current: centerOwner === modelData.name ? centerCurrent : ""`
- Bottom EdgePopouts: naturally local via per-screen EdgeBumpers

`focusedScreen` = `Hyprland.focusedWorkspace.monitor.name`.

## Bar

- `barHeight: 48`, `cornerSize: 16` (= `gaps_out` 8 + rounding 8). `exclusiveZone: barHeight` so corners overhang without reserving extra space.
- Layout sections anchor `verticalCenter: barBg.verticalCenter`.
- Right side: system tray → volume/media → bell. Wrapped in `HoverHandler` so the popout stays open crossing between icons. Per-icon `MouseArea` only fires `onEntered` to set which popout; hover margins sized to leave zero gap between adjacent zones (tray ±5 px, tray→volume bridge via volume leftMargin −11 px, volume/bell ±8 px).
- **System tray** — `Quickshell.Services.SystemTray` items at 20 px. Hover opens tray menu via Popouts (`tray:<index>`). Tray icons use raw SNI `Image` (full-color), not TintedIcon — documented exception.
- **Workspaces cluster** — non-interactive pills, hover opens workspaces overview. Active pill: 22→44 px over `Anims.pill` OutCubic.
- **Launcher button** — distro logo via Nerd Font glyph, not icon-theme path.
- Battery shown only when system reports battery info (laptops). No bluetooth icon.

## Popouts wrapper

One PanelWindow per side per screen. Right side: volume / notifications / tray. Left side: calendar / power.

**Panel shape:** TL + TR inverse cusps always (invariant — no snap on switch). BL + BR rounded corners. No screen-edge special-casing — panels that anchor at the screen edge overhang by `invRadius` (corner clipped by compositor); `panelAnchor` = content anchor ± `invRadius` always.

**`_activeAnchor`** is the panel edge X (right edge for right-side, left edge for left-side), always offset by `invRadius`. Managed imperatively:
- Open: snap to screen edge (Behavior disabled), then animate to `panelAnchor`.
- Switch: animate `_activeAnchor` and `panel.width` simultaneously.
- Close: animate `panel.width` → 0, slide `_activeAnchor` → screen edge.

**SVG path** uses `panel.width` (animated value), not `panelTotalWidth` (target) — so shape always matches visible rect.

**Content cross-fade:** all loaders use `Behavior on opacity { NumberAnimation { duration: Anims.panel } }` with `enabled`/`z` gated on active state. `z: active ? 1 : 0` — required because on Qt6/Wayland hover events don't propagate through disabled siblings; z ensures active Loader wins.

**Tray ping-pong:** two loaders (`trayLoaderA`/`B`) alternate via `_traySlot`. On `_trayIndex` change, the off-slot loader gets the new item and its slot flips — simultaneous fade-in/fade-out identical to other content pairs.

**Notifications `hovered` prop:** `root.current === "notifications" ? root.interactive : notifLoader.opacity > 0`. Keeps full-list mode visible during fade-out; switches to toast mode only once fully invisible.

**Surface height** is decoupled from inner panel and only grows. Collapses after `Anims.panel + 20 ms`. Animating surface in lockstep causes compositor ghost-buffer halo.

**`contentArea`** has `clip: true` — prevents content overflowing into transparent inverse-corner regions during morph.

### Adding a bar popout

1. Write `FooContent.qml` — plain `Item` with `implicitWidth`/`implicitHeight`. No `PanelWindow`.
2. In `Popouts.qml`: add a `Loader` with `opacity: current === "foo" ? 1 : 0` Behavior. Extend `_config(name)`.
3. In `Bar.qml`: expose anchor X. `MouseArea.onEntered: bar.popoutEnter("foo")`.
4. In `shell.qml`: route anchor through `_setBarAnchor`.

## Modal + EdgePopouts

`Modal.qml` is the base for all edge modals (top/bottom). Centered panels span the full surface width; `panel` is centered inside via `anchors.horizontalCenter + horizontalCenterOffset`.

**SVG path** uses `panel.width` (animated) for `W` and `panel.height` for `H` — both track the animated values so shape always matches.

**`contentArea`** has `clip: true` and is inset by `leftInverseWidth`/`rightInverseWidth`.

`EdgePopouts` extends `Modal`. Content loaders use `anchors.horizontalCenter: parent.horizontalCenter` + explicit `width/height: item.implicitWidth/Height` — centered in contentArea so morph clips symmetrically from both sides.

**Peek mode (`peekHeight > 0`):** panel stays mounted at `peekHeight` when `current === ""`. Bottom EdgePopouts uses `peekHeight: 8`.

**`animatePanelWidth` toggle:** flipped false/true around the `_stickyWidth` assignment on open-from-closed so only height animates (no diagonal grow). Stays true on content switches so both axes morph.

### Bottom edge layout

Three sibling EdgePopouts share `bottomCurrent` / `bottomEnter` / `bottomLeave` / `bottomCloseTimer` in `shell.qml`:
- **ThemeSwitcher** — centered (`panelXOffset: 0`)
- **StandardGame** — left (`panelXOffset: -(screenW + 596)/4`)
- **ManiaGame** — right (`panelXOffset: +(screenW + 596)/4`)

All three peek bars stay simultaneously visible. Shared depth counter + 250 ms close timer handles cross-bumper handoff.

### Adding a bottom-edge popout

1. Write `FooContent.qml`.
2. In `shell.qml` bottom EdgePopouts: add `{ name: "foo", source: fooComp }` and wire a sibling `Component`.
3. Add/subdivide an `EdgeBumper` and wire `bottomEnter("foo", screen)`.

## ThemeSwitcherContent

Accent color grid + two sliders:
- **Transparency** — `opacity.bg` (range 0.2–1.0, step 0.01). Written to override via `apply_palette.py`, live-reloads kitty via `set-background-opacity`.
- **Animations** — `anim.speed` multiplier (range 0.1–5.0, step 0.1). Sets `Anims.multiplier` live; persisted in override.

## Games

**StandardGameContent** (`osu Standard`) — osu-style click game. Hit circles spawn on 1 s timer, approach circle shrinks over 1.4 s. Resource-gated via `Loader { active: ... }`. Overlap rejection checks `game.liveCircles` array (not `game.children` — includes Timers/Components).

**ManiaGameContent** (`osu Mania`) — 4-key (D/F/J/K) falling-note game. Uses `kbdFocusName: "mania"`, `kbdExclusive: false` (OnDemand focus — cursor must be on surface; Exclusive caused delay when switching to ThemeSwitcher). Notes fall via `NumberAnimation on y`. Stray keypresses flash the pad but don't break combo.

Scoring (both games): Perfect/Great/Good/Miss tiers. Combo multiplier: `round(base × (1 + (combo-1) × 0.05))`. Miss resets combo.

## Workspaces overview

Thumbnails: PNGs at `$XDG_RUNTIME_DIR/quickshell/workspace-thumbs/<id>.png`, captured by `grim`. Atomic write (`.tmp` rename). Cache-busting via `_workspaceThumbVersion` counter (reset source to "" then back — `?v=N` doesn't work with `file://` URLs). `implicitHeight: row.implicitHeight + padding * 2` (not a hardcoded formula).

## AppLauncher

IPC: `qs ipc call launcher show|hide|toggle`. Fuzzy search with frecency boost. Frecency at `~/.cache/quickshell/launcher-frecency.json`. Focus grabbed via 60 ms timer after surface maps.

## Critical QML invariants

### `FileView.text` is a method
`colorsFile.text` returns the function reference. Capture via `onLoaded: baseContents = text()`.

### Inactive Loaders need `enabled: false` AND `z: 0`
`enabled: false` blocks click pass-through. `z: 0` is required because Qt6/Wayland hover events don't propagate through disabled siblings — a disabled Loader at z=1 silently blocks hover for the active one beneath it.

### Hover depth counter, not per-icon timer
`_hoverDepth` increments on enter, decrements on leave; close timer only restarts at 0. Per-icon `onExited → timer.restart` is broken — Wayland doesn't guarantee exit-before-enter ordering.

### Surface height only grows
Shrinking the surface mid-animation causes the compositor to hold the previous frame — manifesting as an unrounded halo. Surface collapses only after `_surfaceCollapseTimer` fires post-close.

### SVG uses animated `panel.width`, not target
`var W = panel.width` (not `panelTotalWidth`). Using the target value causes the SVG to snap to target geometry while `panel.width` is still animating — visible as a shape snap on the opposite side.

### `contentArea.clip: true` is load-bearing
Without it, outgoing content overflows into the transparent inverse-corner regions during morph.

### EdgePopouts loaders are centered, not fill
`anchors.horizontalCenter: parent.horizontalCenter; width: item.implicitWidth` — ensures morph clips symmetrically from both sides. `anchors.fill: parent` clips only from the right.

### Bottom EdgePopouts `kbdExclusive: false` for ManiaGame
`kbdExclusive: true` held exclusive focus for the full 250 ms close-timer window, blocking pointer-enter on ThemeSwitcher. OnDemand grants focus when cursor is on the surface (sufficient for gameplay).
