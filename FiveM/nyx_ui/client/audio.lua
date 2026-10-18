--[[
    Nyxframework: nyx_ui
    File: client/audio.lua
    Description: Centralized audio subsystem triggering native sound sets and web audio cues.
]]

Nyx = Nyx or {}
Nyx.UI = Nyx.UI or {}
Nyx.UI.Audio = {}

-- Play Sound by Registered Config Key or Custom Bank
function Nyx.UI.PlaySound(soundKey, customBank)
    if not soundKey then return end

    local cfg = Config.Audio.Sounds[soundKey]
    if cfg then
        PlaySoundFrontend(-1, cfg.name, cfg.bank, true)
    elseif customBank then
        PlaySoundFrontend(-1, soundKey, customBank, true)
    else
        -- Fallback to web audio dispatch
        Nyx.UI.Send("audio", "PLAY_SOUND", {
            sound = soundKey
        })
    end
end

-- Network & Local Audio Triggers
RegisterNetEvent("nyx:ui:client:playSound", function(soundKey, customBank)
    Nyx.UI.PlaySound(soundKey, customBank)
end)
