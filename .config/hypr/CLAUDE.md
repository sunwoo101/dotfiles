# Hyprland (`.config/hypr/`)

## Layout

- **Dwindle** with `smart_split = true` — cursor position determines split direction. Avoids aspect-ratio surprises on near-square monitors.
- `gaps_out = 8`, `rounding = 8` — paired with bar's `cornerSize = 16`.

## Session (uwsm)

Session runs via `hyprland-uwsm.desktop` (symlinked to `/usr/local/share/wayland-sessions/` by `configure_pacman.sh` so SDDM only shows this entry). `Exec=uwsm start -e -D Hyprland hyprland.desktop`.

**`-e` mode** skips the wayland-wm service unit. Consequences:
- `graphical-session.target` is never bound to compositor lifetime.
- `app-graphical.slice` is `PartOf=graphical-session.target` (one-way teardown), NOT `Wants=` — slice activating does NOT pull the target up.
- `xdg-desktop-autostart.target` never fires under `-e`.

`autostart.conf` runs `systemctl --user import-environment` + `dbus-update-activation-environment --systemd` — load-bearing under `-e` for portals and D-Bus-activated services.

## Autostart

XDG autostart entries in `~/.config/autostart/*.desktop` are launched by `dex --autostart --environment Hyprland`.

**`dex` is exec-once'd bare, not via `uwsm app --`** — dex forks each entry then exits; wrapping it collapses every spawned app into a single scope. Trade-off accepted.

**Don't replace dex with `systemctl --user start xdg-desktop-autostart.target`** — under `-e` mode there is no path to activate it (both `xdg-desktop-autostart.target` and `graphical-session.target` are `RefuseManualStart=yes`). The generated units exist but stay queued forever.

**`uwsm app -- <cmd>` for every long-running autostart** (GUI apps, background daemons). Gives scope unit, clean logout, journal logging. Do NOT wrap one-shot setup commands.

**Don't manually `uwsm app --` from outside Hyprland's lifecycle** — scope outlives the compositor session and worsens the relogin issue.

## Logout-then-login cleanup

`hyprland-session-cleanup.service` (`.config/systemd/user/`, enabled by `enable_services.sh`) prevents black-screen relogin caused by `graphical-session.target` staying active after Hyprland exits.

- Stays in `app.slice` (NOT `app-graphical.slice`) so it survives stopping its own targets.
- `WantedBy=default.target`, not `graphical-session.target`.
- Blocks on `socat -u UNIX-CONNECT:.socket2.sock`; on socket close, stops `graphical-session.target` + `app-graphical.slice`.
- `find_live_socket` calls `hyprctl monitors` to verify a socket is actually responding — stale `.socket2.sock` files accept connect then immediately close, which would trigger cleanup in a tight loop.
- Re-runs liveness check after `socat` returns before issuing cleanup — guards against IPC blips.
- Outer `while :;` loop spans multiple Hyprland sessions per boot.

## Special workspaces

**`misc.initial_workspace_tracking` MUST be 0** — with it non-zero, `dex`-launched apps land on ws 1 (the `exec-once` workspace) instead of their special workspace.

**`special-workspace-guard.sh`** handles three startup races via `openwindow` handler:
1. Skip floating popups/menus/tooltips — refocusing the pinned owner warps cursor, yanking user out of menus.
2. Electron apps set WM_CLASS after map — catch `class in $pinned && workspace != expected`, dispatch `movetoworkspacesilent`.
3. `silent` only suppresses focus, not visibility — guard hides the special on the `activespecial` show event with a 5 s TTL.

**`toggle-or-launch.sh`** reconciles displacement at toggle time. Sweeps `hyprctl clients` for displaced windows, moves them back. **Two-press semantics:** first press fixes and hides, second press summons. **Cross-monitor toggle:** `toggle_on <mon>` helper redirects dispatch to the correct monitor.

**`guard-move.sh`** — keybind wrapper that NOPs `swapwindow`/`movetoworkspace` for special-workspace windows.

## `special-workspace-guard.sh` invariants

**Event loop shape is load-bearing:** must be single MAIN-shell loop with process substitution (`while :; do while IFS= read -r line; done < <(socat ...); done`), NOT a pipeline. Pipeline left-subshell was killed silently during autostart `configreloaded` event.

**Three HIS fallbacks:** own env → `systemctl --user show-environment` → scan `$XDG_RUNTIME_DIR/hypr/*/.socket2.sock`. Runtime-dir scan is load-bearing — `import-environment` races with scope creation.

**`set -e` is wrong** for the event daemon — a transient `hyprctl` failure must not terminate a long-running reader. Use `set -u` only.

**Must trap SIGUSR1/SIGUSR2** — `reload_all.sh` sends `pkill -USR1 -x bash` to nudge oh-my-posh re-init. Without the trap, the daemon dies silently on every theme change.

## Misc

- `xdg-desktop-portal-hyprland.service` SEGVs on logout (cosmetic). `drkonqi` surfaces the coredump via the notification bar — don't suppress with `LimitCORE=0`.
- `autostart.conf` dispatches `workspace 1` before dex so dex-launched apps start on ws 1 (otherwise `initial_workspace_tracking` issues).
