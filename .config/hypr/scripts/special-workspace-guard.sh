#!/usr/bin/env bash
# Watches Hyprland's event socket and reconciles the per-app special
# workspace pinning in two directions:
#
#   - Rogues on a special: when a non-pinned window spawns onto a
#     special workspace (e.g. an app launched from the launcher while
#     a special is shown — Hyprland places it on the special), track
#     it but don't move immediately. Special workspaces overlay the
#     active workspace and grab input, so moving a rogue off while the
#     special is still visible drops it under the overlay and looks
#     like the window vanished. Instead, on the next `activespecial`
#     close event, every rogue on that special is moved to the now-
#     active regular workspace via `movetoworkspacesilent`.
#   - Pinned class on a regular workspace: when a class in $pinned
#     spawns somewhere other than its dedicated special, snap it back
#     immediately. The `workspace special:X silent` windowrule misses
#     for Electron apps (discord, github-desktop, docker-desktop) at
#     startup because they set WM_CLASS after the initial map, so the
#     rule doesn't fire and the window flashes on workspace 1. This
#     guard catches that race.
#
# Cleanup of pinned/per-app rules in conf/visuals.conf is the other half
# of the contract — windows whose class is in $pinned never get tracked
# here, so they stay on their dedicated special workspace as intended.
# `set -u` only — we deliberately do NOT use `set -e`. This is a long-
# running event reader; a single failed `hyprctl dispatch` (e.g. window
# closed mid-handle, transient IPC error) must not terminate the whole
# daemon. Each event handler runs to completion regardless of inner
# command exit status, so the read loop keeps consuming.
set -u

# When launched via `uwsm app --`, our scope's env is captured from the
# systemd user manager at creation time. autostart.conf's
# `import-environment` exec-once runs concurrently with ours, so HIS may
# not be in the manager env yet when our scope is born — and inherited
# env is frozen, sleeping in-process won't help. Three sources, in
# order: own env, systemd user manager (kept up-to-date as imports
# land), and the runtime socket directory itself. The directory scan is
# the load-bearing fallback when the daemon scope spawns before
# import-environment completes; Hyprland creates the directory on
# startup independently of any env propagation.
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

resolve_his() {
    local h=${HYPRLAND_INSTANCE_SIGNATURE:-}
    [ -n "$h" ] && { printf '%s\n' "$h"; return 0; }
    h=$(systemctl --user show-environment 2>/dev/null \
        | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p')
    [ -n "$h" ] && { printf '%s\n' "$h"; return 0; }
    # Pick whichever instance dir actually has a live event socket.
    # Filters out leftovers from a prior crashed session.
    local d
    for d in "${runtime_dir}/hypr"/*/; do
        [ -S "${d}.socket2.sock" ] || continue
        basename "$d"
        return 0
    done
    return 1
}

his=""
for _ in $(seq 1 100); do
    his=$(resolve_his) && break
    sleep 0.1
done
[ -n "$his" ] || { echo "HIS never appeared (env, user-manager, or runtime dir)" >&2; exit 1; }

# Every `hyprctl dispatch …` we issue (refocus-owner, disown, etc.)
# reads HIS from the env to pick a socket. If our scope spawned before
# import-environment finished, our env doesn't have it — events still
# arrive (we connect to .socket2.sock directly with the resolved $his)
# but every corrective dispatch silently goes nowhere. Export so the
# child hyprctls inherit it.
export HYPRLAND_INSTANCE_SIGNATURE=$his

sock="${runtime_dir}/hypr/${his}/.socket2.sock"

# Per-event log so we can trace what the daemon saw and did. One line
# per event, tab-separated columns: timestamp, action, address, class,
# workspace-from, workspace-to. Lives in XDG_RUNTIME_DIR so it's wiped
# at boot.
log_file="${runtime_dir}/special-workspace-guard.log"
: >"$log_file"
log_startup() { printf '%s\t%s\n' "$(date '+%H:%M:%S')" "$1" >>"$log_file"; }
log_startup "boot his=$his sock=$sock"

# Send stderr (socat reconnect noise, hyprctl complaints) to the log
# alongside our structured event lines. EXIT trap leaves a breadcrumb
# so we know if/why we ever fall out of the read loop.
exec 2>>"$log_file"
trap 'log_startup "EXIT status=$?"' EXIT
# SIGUSR1 trap is LOAD-BEARING, not diagnostic. `bashrc/ohmyposh` uses
# `pkill -USR1 -x bash` (via scripts/reload_all.sh) to nudge interactive
# shells into re-running `oh-my-posh init`. That blanket-matches every
# bash process by *name*, including this daemon — and bash's default
# action for SIGUSR1 is terminate. Without this trap, the daemon dies
# silently with status=0 the first time the user changes theme / accent
# / colors (which fires reload_all.sh through the Quickshell apply chain).
# Trap as a no-op (the log is just so we know it landed); bash resumes
# the read loop after the handler runs.
trap ':' USR1
trap ':' USR2

log() {
    # log <action> <addr> <class> <from> <to>
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%H:%M:%S')" "$1" "$2" "$3" "$4" "$5" >>"$log_file"
}

# class -> the special workspace that class is pinned to. Anything in
# this map is allowed to stay on its special workspace. Keep in sync
# with the per-app `workspace special:NAME` rules in conf/visuals.conf.
declare -A pinned=(
    ["kitty-special"]="special:term"
    ["discord"]="special:discord"
    ["Spotify"]="special:spotify"
    ["Docker Desktop"]="special:docker"
    ["GitHub Desktop"]="special:github"
    ["livepaper"]="special:livepaper"
)

# Reverse lookup: workspace -> pinned class. Built once at startup so
# we can refocus the "owner" window of a special workspace whenever a
# rogue window opens and steals focus.
declare -A pinned_class_for
for _cls in "${!pinned[@]}"; do
    pinned_class_for[${pinned[$_cls]}]=$_cls
done
unset _cls

# Per-monitor: name of the currently-visible special workspace, so when
# we get the "special closed" event (empty workspace name) we know which
# special just got dismissed.
declare -A active_special

# Per-window-address: special workspace it was born on. Only contains
# rogues (windows we want to disown later).
declare -A rogues

# Set of special workspace names that should be hidden on their next
# `activespecial` show event. Populated when a pinned window opens on
# its expected special — `workspace special:X silent` doesn't prevent
# Hyprland from visibility-toggling the special when content first
# appears on it, and the openwindow event fires before activespecial,
# so we can't dispatch `togglespecialworkspace` until the show arrives.
declare -A pending_hide

# Resolves the active regular workspace name. Used as the move target
# when a special workspace closes and we're disowning its rogues.
active_regular_workspace() {
    hyprctl activeworkspace -j 2>/dev/null \
        | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' | head -1
}

# exec-once fires before Hyprland has finished creating .socket2.sock,
# and even after it exists socat occasionally exits at session start.
# Wait for the socket, then keep reconnecting if the stream ever closes —
# otherwise the script silently exits with rc=0 and its app-*.scope is
# reaped without a journal trace.
while [ ! -S "$sock" ]; do sleep 0.2; done

log_startup "loop-start"
# Run the read loop in the MAIN shell (process substitution feeds
# socat's stdout via an FD), not in a pipeline subshell. The previous
# `while :; do socat …; done | while read …` form was killed by an
# invisible signal hitting the left-side subshell during Hyprland's
# second `configreloaded` event at autostart — subshells reset our
# signal traps on fork, so the kill left no breadcrumb. Keeping
# everything in MAIN means our SIGTERM/HUP/INT/PIPE traps cover the
# whole event loop. Outer loop reconnects if socat ever exits.
while :; do
    while IFS= read -r line; do
        case "$line" in
        "openwindow>>"*)
            payload=${line#"openwindow>>"}
            addr=${payload%%,*}
            rest=${payload#*,}
            workspace=${rest%%,*}
            rest=${rest#*,}
            class=${rest%%,*}

            expected=${pinned[$class]:-}

            # Pinned class spawned on a non-special workspace — the
            # windowrule missed (Electron apps set WM_CLASS after the
            # initial map, so `workspace special:X silent` doesn't fire
            # in time). Snap it back to its dedicated special silently
            # so it doesn't flash on the active workspace at startup.
            if [ -n "$expected" ] && [ "$expected" != "$workspace" ]; then
                hyprctl dispatch movetoworkspacesilent \
                    "${expected},address:0x${addr}" >/dev/null || true
                log snap-pin "$addr" "$class" "$workspace" "$expected"
                continue
            fi

            case "$workspace" in
                special:*) ;;
                *) continue ;;
            esac

            if [ "$expected" = "$workspace" ]; then
                log pin "$addr" "$class" "-" "$workspace"
                # `workspace special:X silent` only suppresses focus
                # change — it does NOT prevent Hyprland from making the
                # special workspace visible when a window first appears
                # on it. Queue a hide for the upcoming activespecial
                # show event (which fires AFTER openwindow).
                pending_hide[$workspace]=1
                continue
            fi

            rogues[$addr]=$workspace
            log open-rogue "$addr" "$class" "-" "$workspace"

            # The new window steals focus from the pinned owner of this
            # special workspace. Refocus the owner so the user keeps
            # interacting with the special's "main" app (e.g. kitty-
            # special) until they explicitly choose otherwise.
            owner=${pinned_class_for[$workspace]:-}
            if [ -n "$owner" ]; then
                hyprctl dispatch focuswindow "class:$owner" \
                    >/dev/null || true
                log refocus-owner "-" "$owner" "$workspace" "$workspace"
            fi
            ;;

        "movewindow>>"*)
            # User (or another tool) moved a window between workspaces.
            # If it was tracked as a rogue, update or drop it from the
            # registry so we don't try to re-disown it later.
            payload=${line#"movewindow>>"}
            addr=${payload%%,*}
            new_ws=${payload#*,}

            if [ -n "${rogues[$addr]:-}" ]; then
                old_ws=${rogues[$addr]}
                case "$new_ws" in
                    special:*)
                        rogues[$addr]=$new_ws
                        log move-rogue "$addr" "?" "$old_ws" "$new_ws"
                        ;;
                    *)
                        unset "rogues[$addr]"
                        log untrack "$addr" "?" "$old_ws" "$new_ws"
                        ;;
                esac
            fi
            ;;

        "closewindow>>"*)
            addr=${line#"closewindow>>"}
            if [ -n "${rogues[$addr]:-}" ]; then
                log close "$addr" "?" "${rogues[$addr]}" "-"
                unset "rogues[$addr]"
            fi
            ;;

        "activespecial>>"*)
            payload=${line#"activespecial>>"}
            ws=${payload%%,*}
            mon=${payload#*,}

            if [ -n "$ws" ]; then
                # Special workspace just became visible on this monitor.
                active_special[$mon]=$ws
                log special-show "-" "$mon" "-" "$ws"
                # If this show was triggered by a pinned window opening
                # (autostart pop-up), hide it back. togglespecialworkspace
                # acts on the focused monitor; that's where Hyprland just
                # showed it, so this works even on a multi-monitor setup.
                if [ -n "${pending_hide[$ws]:-}" ]; then
                    unset "pending_hide[$ws]"
                    hyprctl dispatch togglespecialworkspace \
                        "${ws#special:}" >/dev/null || true
                    log auto-hide "-" "$mon" "$ws" "-"
                fi
            else
                # Special workspace just got dismissed on this monitor.
                # Disown anything we tracked as rogue on that special.
                prev=${active_special[$mon]:-}
                if [ -z "$prev" ]; then
                    log special-hide "-" "$mon" "?" "-"
                    continue
                fi

                target=$(active_regular_workspace)
                if [ -z "$target" ] || [[ "$target" == special:* ]]; then
                    log special-hide-skip "-" "$mon" "$prev" "${target:-?}"
                    unset "active_special[$mon]"
                    continue
                fi

                log special-hide "-" "$mon" "$prev" "$target"
                # Track the last-disowned address so we can focus it
                # after the loop. If there are multiple rogues we focus
                # whichever bash visits last; in practice users hit this
                # path one window at a time.
                focus_addr=""
                for addr in "${!rogues[@]}"; do
                    if [ "${rogues[$addr]}" = "$prev" ]; then
                        hyprctl dispatch movetoworkspacesilent \
                            "${target},address:0x${addr}" >/dev/null || true
                        log disown "$addr" "?" "$prev" "$target"
                        unset "rogues[$addr]"
                        focus_addr=$addr
                    fi
                done
                if [ -n "$focus_addr" ]; then
                    hyprctl dispatch focuswindow "address:0x${focus_addr}" \
                        >/dev/null || true
                    log focus "$focus_addr" "?" "$prev" "$target"
                fi
                unset "active_special[$mon]"
            fi
            ;;
        esac
    done < <(socat -u UNIX-CONNECT:"$sock" - || true)
    log_startup "socat exited; reconnecting"
    sleep 1
done
