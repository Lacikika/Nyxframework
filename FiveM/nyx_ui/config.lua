--[[
    Nyxframework: nyx_ui
    File: config.lua
    Description: Configuration for master SPA shell, HUD intervals, notification defaults,
                 and audio feedback sound sets.
]]

Config = {}

Config.Debug = false

-- HUD Sync Settings (Strict 100ms-250ms throttled delta updates, never Wait(0))
Config.Hud = {
    Enabled = true,
    UpdateIntervalMs = 150,     -- Delta-throttled polling interval (100ms-250ms)
    HideInPauseMenu = true,
    ShowStamina = true,
    ShowOxygen = true
}

-- Notification Defaults
Config.Notifications = {
    DefaultDuration = 4500,     -- Milliseconds to display toast
    MaxStacked = 5              -- Maximum simultaneous toasts before queueing
}

-- Central Audio Presets
Config.Audio = {
    Sounds = {
        ['click']     = { name = "CLICK", bank = "DLC_HEIST_HACKING_SNAKE_SOUNDS" },
        ['beep']      = { name = "Beep_Green", bank = "DLC_HEIST_HACKING_SNAKE_SOUNDS" },
        ['error']     = { name = "Keycard_Fail", bank = "DLC_HEISTS_BIOLAB_FINALE_SOUNDS" },
        ['success']   = { name = "Keycard_Success", bank = "DLC_HEISTS_BIOLAB_FINALE_SOUNDS" },
        ['open']      = { name = "NAV_UP_DOWN", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET" },
        ['close']     = { name = "BACK", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET" }
    }
}
