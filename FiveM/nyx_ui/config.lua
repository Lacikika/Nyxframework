--[[
    Nyxframework: nyx_ui
    File: config.lua
    Description: Configuration for master SPA shell, HUD intervals, notification defaults,
                 and audio feedback sound sets.
]]

Config = {}

Config.Debug = false

-- HUD Sync Settings
Config.Hud = {
    Enabled = true,
    UpdateIntervalMs = 500,     -- Polling interval for health, armor, stamina, cash
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
