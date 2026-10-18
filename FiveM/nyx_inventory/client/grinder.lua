--[[
    Nyxframework: nyx_inventory
    File: client/grinder.lua
    Description: Client-side firearm serial grinding animations, particle sparks,
                 acoustic feedback, and third-eye/command interaction triggers.
]]

Nyx = Nyx or {}
Nyx.SerialGrind = Nyx.SerialGrind or {}

-- 1. Audiovisual Event Listener: Sparks & Noise Generation
RegisterNetEvent("nyx:inventory:client:weaponGrinded", function(data)
    if not data or not data.coords then return end

    local ped = PlayerPedId()
    local myCoords = GetEntityCoords(ped)
    local targetCoords = vector3(data.coords.x, data.coords.y, data.coords.z)
    local dist = #(myCoords - targetCoords)

    if dist <= (data.radius or 30.0) then
        -- Play grinding sound / metal scrape
        PlaySoundFromCoord(-1, "Drill_Pin_Break", targetCoords.x, targetCoords.y, targetCoords.z, "DLC_HEIST_FLEX_SOUNDS", false, 25, false)

        -- Load & Trigger Sparks Particle FX
        local ptfxAsset = "core"
        RequestNamedPtfxAsset(ptfxAsset)
        local timeout = 0
        while not HasNamedPtfxAssetLoaded(ptfxAsset) and timeout < 20 do
            Wait(50)
            timeout = timeout + 1
        end

        if HasNamedPtfxAssetLoaded(ptfxAsset) then
            UseParticleFxAssetNextCall(ptfxAsset)
            local ptfx = StartParticleFxLoopedAtCoord(
                "ent_amb_sparking_wires",
                targetCoords.x, targetCoords.y, targetCoords.z + 0.1,
                0.0, 0.0, 0.0,
                1.0, false, false, false, false
            )
            SetTimeout(4000, function()
                if ptfx and DoesParticleFxLoopedExist(ptfx) then
                    StopParticleFxLooped(ptfx, false)
                end
            end)
        end

        if dist <= 5.0 then
            ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", 0.15)
        end
    end
end)

-- 2. Client-Side Grind Invocation
function Nyx.SerialGrind.StartGrind(weaponSlot, toolSlot, diskSlot)
    weaponSlot = tonumber(weaponSlot)
    toolSlot = tonumber(toolSlot)
    diskSlot = tonumber(diskSlot)

    if not weaponSlot or not toolSlot then
        TriggerEvent("chat:addMessage", {
            color = { 255, 120, 0 },
            multiline = true,
            args = { "[Fegyverkovács]", "Használat: /grindserial [fegyver_slot] [sarokcsiszoló_slot] [vágókorong_slot]" }
        })
        return
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TriggerEvent("chat:addMessage", {
            color = { 255, 50, 50 },
            args = { "[Fegyverkovács]", "Járműben ülve nem csiszolhatsz fegyvert!" }
        })
        return
    end

    -- Play Mechanic / Grinding Animation
    local animDict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@"
    local animName = "machinic_loop_mechandplayer"
    RequestAnimDict(animDict)
    local timeout = 0
    while not HasAnimDictLoaded(animDict) and timeout < 30 do
        Wait(50)
        timeout = timeout + 1
    end

    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 8000, 1, 0, false, false, false)

    TriggerEvent("chat:addMessage", {
        color = { 255, 200, 50 },
        args = { "[Fegyverkovács]", "Gyári azonosító szám lecsiszolása folyamatban... (8 mp)" }
    })

    Wait(7500)
    ClearPedTasks(ped)

    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPCAwait("inventory:grindWeaponSerial", {
            weaponSlot = weaponSlot,
            toolSlot = toolSlot,
            diskSlot = diskSlot
        })
    end)

    if ok and res and res.success then
        TriggerEvent("chat:addMessage", {
            color = { 50, 255, 100 },
            args = { "[Fegyverkovács]", string.format("SIKERES CSISZOLÁS! A gyári szám eltávolítva. Új állapot: %s (Minőség: %d%%)",
                res.outcome.scratchedSerial, res.outcome.grindQuality or 85) }
        })
    else
        local errMsg = (res and res.error) or "Nem sikerült a csiszolás (hiányzó szerszám vagy nem lőfegyver)."
        TriggerEvent("chat:addMessage", {
            color = { 255, 50, 50 },
            args = { "[Fegyverkovács]", "HIBA: " .. tostring(errMsg) }
        })
    end
end

-- 3. Register Player Command: /grindserial
RegisterCommand("grindserial", function(source, args)
    local wSlot = tonumber(args[1])
    local tSlot = tonumber(args[2])
    local dSlot = tonumber(args[3])
    Nyx.SerialGrind.StartGrind(wSlot, tSlot, dSlot)
end, false)

-- 4. Export Client Action
exports("StartGrind", function(weaponSlot, toolSlot, diskSlot)
    Nyx.SerialGrind.StartGrind(weaponSlot, toolSlot, diskSlot)
end)
