# TODO

Possible additions for the v2 dotfiles. Order is rough priority, not commitment.

## Idle / auto-lock

- `hypridle` daemon: dim screen → lock → suspend on inactivity.
- Wires into existing `qs ipc call lock lock`.
- Add `hypridle` to `packages/pacman` and an autostart line in `hyprland.conf`.

## OSD overlays (volume / brightness)

- Pop-up indicator when XF86 volume / brightness keys are pressed.
- New `Osd.qml` (PanelWindow, brief) + IPC handler; wire keybinds in `keybinds.conf`
  to `qs ipc call osd show volume`/`brightness` after the action.

## System tray

- Status notifier items (Discord, Slack, Steam, etc. are invisible without it).
- Quickshell exposes `Quickshell.Services.SystemTray` — add a tray Row in `Bar.qml`'s
  RIGHT section.

## Media controls

- mpris play/pause/skip + currently-playing title.
- `Quickshell.Services.Mpris` is already on disk (`/usr/lib/qt6/qml/Quickshell/Services/Mpris`).
- Could live left of the workspaces or as a separate hover-reveal.

## Screenshot

- Keybind for region / fullscreen capture → clipboard + file.
- `grim` + `slurp` + `wl-copy` is the standard combo. Add to `packages/pacman`,
  bind in `keybinds.conf`.

## Clipboard manager

- History + picker. `cliphist` is the usual pick on wayland.
- Wire into the AppLauncher pattern, or a separate Quickshell modal.

## Notifications: clear-all / DND

- "Clear all" button at the top of the notifications panel.
- DND toggle (mute popups while keeping them tracked) — drives `notifSrv` behavior.
