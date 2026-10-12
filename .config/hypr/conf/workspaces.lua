-- Assign workspaces to specific monitors
for ws = 1, 3 do
    hl.workspace_rule({ workspace = tostring(ws), monitor = "DP-3" })
end
for ws = 4, 6 do
    hl.workspace_rule({ workspace = tostring(ws), monitor = "HDMI-A-1" })
end

hl.config({
    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles   = true,
        pass_mouse_when_bound    = false,
    },

    misc = {
        initial_workspace_tracking = 0,
        focus_on_activate          = true,
    },
})
