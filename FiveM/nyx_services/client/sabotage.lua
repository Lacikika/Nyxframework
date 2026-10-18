--[[
    Nyxframework: nyx_services
    File: client/sabotage.lua
    Description: Client-side transformer sabotage interactions, high-voltage spark particle FX,
                 audiovisual camera shake, and emergency dispatch sound triggers.
]]

local isSabotaging = false

--- Resolve nearest substation transformer within distance
function Nyx.Services.GetNearestTransformer(maxDist)
    maxDist = maxDist or 5.0
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local nearestId = nil
    local shortestDist = maxDist

    for subId, sub in pairs(Config.PowerGrid.Substations or {}) do
        local tCoords = sub.transformerCoords or sub.coords
        local dist = #(pCoords - tCoords)
        if dist < shortestDist then
            shortestDist = dist
            nearestId = subId
        end
    end

    return nearestId, shortestDist
end

--- Play localized high-voltage electrical arc explosion and particle effects
local function playSabotagePtfx(coords)
    if not coords then return end

    -- Distance check for audiovisual cues
    local pCoords = GetEntityCoords(PlayerPedId())
    local dist = #(pCoords - vector3(coords.x, coords.y, coords.z))

    if dist < 300.0 then
        -- Play loud electrical explosion sound
        PlaySoundFromCoord(-1, "DISTANT_EXPLOSION", coords.x, coords.y, coords.z, "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", false, 0, false)

        -- Load core particles
        RequestNamedPtfxAsset("core")
        local timeout = 0
        while not HasNamedPtfxAssetLoaded("core") and timeout < 20 do
            Wait(50)
            timeout = timeout + 1
        end

        if HasNamedPtfxAssetLoaded("core") then
            UseParticleFxAssetNextCall("core")
            StartParticleFxNonLoopedAtCoord("sparks", coords.x, coords.y, coords.z + 1.5,
                0.0, 0.0, 0.0, 3.5, false, false, false
            )
        end

        -- Camera shake for players near ground zero
        if dist < 45.0 then
            ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", 0.45)
        end
    end
end

--- Primary client sabotage action
RegisterNetEvent("nyx:services:client:sabotageTransformer", function(args)
    if isSabotaging then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "MŰVELET FOLYAMATBAN",
            message = "Már végrehajtás alatt áll egy művelet!"
        })
        return
    end

    local subId = (type(args) == "table" and args.subId) or args
    if not subId then
        subId = Nyx.Services.GetNearestTransformer(4.5)
    end

    if not subId then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "NINCS TRANSZFORMÁTOR",
            message = "Nem vagy elég közel egyetlen alállomás transzformátorához sem!"
        })
        return
    end

    local cfgSub = Config.PowerGrid.Substations and Config.PowerGrid.Substations[subId]
    local subLabel = (cfgSub and cfgSub.label) or subId

    -- Default tool selection: prefers wire_cutters -> thermite_charge -> tool_repairkit
    local toolToUse = "wire_cutters"
    if type(args) == "table" and args.tool then
        toolToUse = args.tool
    end

    local profile = Nyx.Sabotage and Nyx.Sabotage.GetToolProfile(toolToUse)
    local duration = (profile and profile.actionDurationMs) or 8000

    local ped = PlayerPedId()
    isSabotaging = true

    -- Play cutting / wiring mechanic animation
    local animDict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@"
    local animName = "machinic_loop_mechandplayer"

    RequestAnimDict(animDict)
    local timeout = 0
    while not HasAnimDictLoaded(animDict) and timeout < 20 do
        Wait(50)
        timeout = timeout + 1
    end

    if HasAnimDictLoaded(animDict) then
        TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, duration, 1, 0, false, false, false)
    end

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "SZABOTÁZS",
        message = string.format("Nagyfeszültségű vezetékek átvágása (%s)...", subLabel)
    })

    Wait(duration)

    ClearPedTasks(ped)
    isSabotaging = false

    -- Trigger server RPC
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("services:sabotageSubstation", {
            substationId = subId,
            tool = toolToUse
        })

        if res and res.success and res.result then
            local r = res.result
            if r.success then
                TriggerEvent("nyx:ui:notify", {
                    type = "success",
                    title = "TRANSZFORMÁTOR SZABOTÁLVA",
                    message = string.format("Sikeres szabotázs! A(z) '%s' körzet áramellátása leállt.", subLabel)
                })
            else
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "SZABOTÁZS SIKERTELEN",
                    message = "A szabotázs kísérlet megszakadt vagy meghiúsult!"
                })
            end

            if r.shockInflicted then
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "ÁRAMÜTÉS!",
                    message = string.format("Nagyfeszültségű ívkisülés ért! Sérülés: -%d HP.", r.shockDamage or 25)
                })
            end

            if r.alarmTriggered then
                TriggerEvent("nyx:ui:notify", {
                    type = "warning",
                    title = "RIASZTÓ BEKAPCSOLT",
                    message = "A hálózati figyelőrendszer azonnali riasztást küldött a rendőrségnek!"
                })
            end
        else
            local errCode = (res and res.error) or "ISMERETLEN_HIBA"
            local errLabels = {
                ['MISSING_SABOTAGE_TOOL'] = "Nincs nálad megfelelő szerszám (Vezetékvágó vagy Termit)! ",
                ['SUBSTATION_ALREADY_SABOTAGED'] = "Ez a transzformátor már meg van rongálva!",
                ['SABOTAGE_COOLDOWN_ACTIVE'] = "A transzformátor biztonsági védelmi zárlat alatt áll!",
                ['TOO_FAR_FROM_TRANSFORMER'] = "Túl messze vagy a transzformátortól!",
                ['SUBSTATION_NOT_FOUND'] = "Alállomás nem található."
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "SIKERTELEN MŰVELET",
                message = errLabels[errCode] or ("Hiba: " .. tostring(errCode))
            })
        end
    end
end)

--- Event listener for server broadcast when a substation transformer is sabotaged
RegisterNetEvent("nyx:services:client:transformerSabotaged", function(data)
    if data and data.coords then
        playSabotagePtfx(data.coords)
    end
end)

--- Accessible CLI command for testing / fallback interaction
RegisterCommand("sabotage", function(source, args)
    local tool = args[1] or "wire_cutters"
    local subId, dist = Nyx.Services.GetNearestTransformer(4.5)
    if not subId then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "SZABOTÁZS",
            message = "Nem vagy transzformátor közelében! (pl. /sabotage [wire_cutters|thermite_charge])"
        })
        return
    end

    TriggerEvent("nyx:services:client:sabotageTransformer", {
        subId = subId,
        tool = tool
    })
end, false)

RegisterCommand("sabotagesubstation", function(source, args)
    ExecuteCommand("sabotage " .. (args[1] or ""))
end, false)
