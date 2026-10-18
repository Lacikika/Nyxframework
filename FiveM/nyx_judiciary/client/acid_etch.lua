--[[
    Nyxframework: nyx_judiciary
    File: client/acid_etch.lua
    Description: Client-side chemical acid-etching interface, forensic laboratory
                 examination animations, metallurgical reports, and third-eye integration.
]]

Nyx = Nyx or {}
Nyx.AcidEtch = Nyx.AcidEtch or {}

-- 1. Client-Side Chemical Etch Execution
function Nyx.AcidEtch.StartEtching(weaponSlot, kitSlot)
    weaponSlot = tonumber(weaponSlot)
    kitSlot = tonumber(kitSlot)

    if not weaponSlot then
        TriggerEvent("chat:addMessage", {
            color = { 0, 180, 255 },
            multiline = true,
            args = { "[Kriminalisztika]", "Használat: /acidetch [fegyver_slot] [kit_slot (opcionális)]" }
        })
        return
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TriggerEvent("chat:addMessage", {
            color = { 255, 60, 60 },
            args = { "[Kriminalisztika]", "Járműben ülve nem végezhetsz laboratóriumi savas maratást!" }
        })
        return
    end

    -- Play Forensic Swab / Chemical Pipette Animation
    local animDict = "anim@amb@business@weed@weed_inspecting_high_dry@"
    local animName = "weed_inspecting_high_base_inspector"
    RequestAnimDict(animDict)
    local timeout = 0
    while not HasAnimDictLoaded(animDict) and timeout < 30 do
        Wait(50)
        timeout = timeout + 1
    end

    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 9000, 1, 0, false, false, false)

    TriggerEvent("chat:addMessage", {
        color = { 0, 220, 255 },
        args = { "[Kriminalisztika]", "Fry-reagens felvitele a lecsiszolt fémfelületre... Kristályszerkezeti előhívás folyamatban (9 mp)..." }
    })

    Wait(8500)
    ClearPedTasks(ped)

    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPCAwait("judiciary:acidEtchWeapon", {
            weaponSlot = weaponSlot,
            kitSlot = kitSlot
        })
    end)

    if ok and res and res.success then
        local out = res.outcome or {}
        local hits = (res.matches and #res.matches) or 0

        TriggerEvent("chat:addMessage", {
            color = { 50, 255, 120 },
            multiline = true,
            args = {
                "[Kriminalisztika]",
                string.format("ELŐHÍVÁS BEFEJEZVE!\n- Helyreállított azonosító: ^3%s^7\n- Foka: ^2%s^7\n- Balisztikai találatok a bűnjel-nyilvántartásban: ^1%d db hüvely/kapcsolat^7",
                    tostring(out.restoredSerial or "N/A"),
                    tostring(out.statusLabel or out.outcome),
                    hits)
            }
        })

        if hits > 0 then
            PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
        end
    else
        local errMsg = (res and res.error) or "A savas maratás meghiúsult (nincs reagens készlet, nem lecsiszolt fegyver, vagy nem vagy laborban)."
        TriggerEvent("chat:addMessage", {
            color = { 255, 60, 60 },
            args = { "[Kriminalisztika]", "HIBA: " .. tostring(errMsg) }
        })
    end
end

-- 2. Register Player Command: /acidetch
RegisterCommand("acidetch", function(source, args)
    local wSlot = tonumber(args[1])
    local kSlot = tonumber(args[2])
    Nyx.AcidEtch.StartEtching(wSlot, kSlot)
end, false)

-- 3. Export Client Action
exports("StartAcidEtching", function(weaponSlot, kitSlot)
    Nyx.AcidEtch.StartEtching(weaponSlot, kitSlot)
end)
