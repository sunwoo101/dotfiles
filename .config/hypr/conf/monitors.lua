-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

-- Default
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Dual monitor
hl.monitor({ output = "DP-3",     mode = "1920x1080@300", position = "0x0",    scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@120", position = "1920x0", scale = 1 })
