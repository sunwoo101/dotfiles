#!/usr/bin/env bash
# Watches Hyprland's event socket and "disowns" rogue windows from
# special workspaces:
#
#   - When a window spawns onto a special workspace, decide if it's
#     pinned (e.g. discord onto special:discord) or rogue (anything
#     else, e.g. an app launched from the launcher while a special
#     workspace is shown — Hyprland places it on the special).
#   - Rogues are tracked but NOT moved immediately. Special workspaces
#     overlay the active workspace and grab input, so moving a rogue
#     off while the special is still visible drops it under the overlay
#     and looks to the user like the window vanished.
#   - When the special workspace toggles OFF, every rogue we tracked on
#     that special gets moved to the now-active regular workspace via
#     `movetoworkspacesilent`. The window pops out where the user
#     expects it.
#
# Cleanup of pinned/per-app rules in conf/visuals.conf is the other half
# of the contract — windows whose class is in $pinned never get tracked
# here, so they stay on their dedicated special workspace as intended.
set -eu

his=${HYPRLAND_INSTANCE_SIGNATURE:?HYPRLAND_INSTANCE_SIGNATURE not set}
sock="${XDG_RUNTIME_DIR}/hypr/${his}/.socket2.sock"

# Per-event log so we can trace what the daemon saw and did. One line
# per event, tab-separated columns: timestamp, action, address, class,
# workspace-from, workspace-to. Lives in XDG_RUNTIME_DIR so it's wiped
# at boot.
log_file="${XDG_RUNTIME_DIR}/special-workspace-guard.log"
: >"$log_file"

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

# Resolves the active regular workspace name. Used as the move target
# when a special workspace closes and we're disowning its rogues.
active_regular_workspace() {
    hyprctl activeworkspace -j 2>/dev/null \
        | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' | head -1
}

socat -u UNIX-CONNECT:"$sock" - | while IFS= read -r line; do
    case "$line" in
        "openwindow>>"*)
            payload=${line#"openwindow>>"}
            addr=${payload%%,*}
            rest=${payload#*,}
            workspace=${rest%%,*}
            rest=${rest#*,}
            class=${rest%%,*}

            case "$workspace" in
                special:*) ;;
                *) continue ;;
            esac

            expected=${pinned[$class]:-}
            if [ "$expected" = "$workspace" ]; then
                log pin "$addr" "$class" "-" "$workspace"
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
done
