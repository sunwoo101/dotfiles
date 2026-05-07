# Scripts (`scripts/`)

One concern each, runnable standalone. Named `verb_object`.

| Script | Purpose |
|---|---|
| `render_configs.sh` | `colors.json` + override → all generated files (kitty, GTK, hyprland, ohmyposh, sddm theme.conf) |
| `apply_palette.py` | Writes `~/.cache/quickshell/colors-override.json`. Args: `FLAVOR ACCENT_NAME ACCENT_HEX [OPACITY [ANIM_SPEED]]`. Preserves `opacity.bg` and `anim.speed` in every write so accent changes don't clobber slider values. |
| `apply_gsettings.sh` | Applies GTK theme + cursor via gsettings + `hyprctl setcursor` |
| `reload_all.sh` | Live-reloads kitty (`set-colors` + `set-background-opacity` per PID), hyprland (`hyprctl reload`), and bash/oh-my-posh (`pkill -USR1 -x bash`). Called by Quickshell's `applyChain` after `render_configs.sh` + `apply_gsettings.sh`. |
| `symlink_dotfiles.sh` | `.config/*` → `~/.config/`, `home/*` → `~/` |
| `configure_pacman.sh` | Enables `[multilib]`; symlinks `hyprland-uwsm.desktop` to `/usr/local/share/wayland-sessions/` |
| `install_pacman.sh` | Installs packages from `packages/pacman` |
| `install_aur.sh` | Installs packages from `packages/aur` via yay |
| `install_gpu_drivers.sh` | GPU driver setup |
| `install_colloid_icons.sh` | Clones + installs Colloid icon theme |
| `install_yay.sh` | Bootstraps yay AUR helper |
| `install_sddm_theme.sh` | Copies greeter to `/usr/share/sddm/themes/dotfiles/` (installed copy, not symlink) |
| `enable_services.sh` | Enables sddm, NetworkManager, bluetooth, hyprpolkitagent, hyprland-session-cleanup |
| `hook_bashrc.sh` | Sources dotfiles bashrc from `~/.bashrc` |
| `session-cleanup.sh` | Daemon run by `hyprland-session-cleanup.service`; blocks on Hyprland socket, stops `graphical-session.target` on exit |
| `guard-move.sh` | Keybind wrapper: NOPs `swapwindow`/`movetoworkspace` for special-workspace windows |
| `toggle-or-launch.sh` | Special-workspace toggle with displacement reconciliation and cross-monitor support |

## apply_palette.py notes

Rebuilds the full override on every call — no merging of stale fields. All five optional values (`opacity`, `anim_speed`) must be passed by callers (Quickshell's `applyPalette()`) to preserve them. Default values: `opacity=0.7`, `anim_speed=1.0`.

## reload_all.sh notes

- Iterates every `kitty` PID for socket name (`@mykitty-{PID}`). Reads `background_opacity` from `~/.config/colors.conf` and sends via `kitty @ set-background-opacity` — `set-colors` alone doesn't update opacity.
- `pkill -USR1 -x bash` matches all bash processes by name, including `special-workspace-guard.sh`. That daemon traps USR1 as a no-op; without the trap it would terminate silently.
