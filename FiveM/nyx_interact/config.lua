--[[
    Nyxframework: nyx_interact
    File: config.lua
    Description: Configuration for spatial raycasting parameters, activation keybinds,
                 entity mask filters, and interaction distance thresholds.
]]

Config = {}

Config.Debug = false

-- Keybind settings
Config.ActivationKey = "LMENU" -- Left Alt keymapping
Config.ActivationCommand = "+nyx_target"
Config.DeactivationCommand = "-nyx_target"

-- Raycasting bounds and options
Config.Raycast = {
    MaxDistance = 4.5,           -- Maximum detection range in meters
    LosProbeFlag = -1,           -- -1 evaluates peds, vehicles, objects, world collision
    GlassIgnored = 4,            -- Ignore see-through glass & transparent materials
    InactiveSleepMs = 250,       -- Sleep interval when interaction key is released (0.00 ms CPU)
    ActiveSleepMs = 0            -- Raycast loop tick when interaction key is held active
}

-- Default distance thresholds by interaction category
Config.Distances = {
    Default = 2.5,
    VehicleTrunk = 2.2,
    VehicleDoor = 1.8,
    VehicleEngine = 2.0,
    AtmTerminal = 1.8,
    FreightPallet = 3.0,
    Crate = 2.0
}

-- Audio feedback on valid target acquisition
Config.Audio = {
    Enabled = true,
    TargetAcquiredSound = "NAV_UP_DOWN",
    TargetAcquiredBank = "HUD_FRONTEND_DEFAULT_SOUNDSET"
}
