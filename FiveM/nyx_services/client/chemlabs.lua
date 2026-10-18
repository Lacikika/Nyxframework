--[[
    Nyxframework: nyx_services
    File: client/chemlabs.lua
    Description: Client spatial interaction, Third-Eye target registration (nyx_interact),
                 pharmaceutical synthesis dialogs, and real-time laboratory telemetry.
]]

local CachedChemLabs = {}
local RegisteredInteractTargets = {}

-- Helper to safely call RPC
local function callRpc(name, ...)
    local promiseObj = promise.new()
    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        exports['nyx_core']:CallRPC(name, function(response)
            promiseObj:resolve(response)
        end, ...)
    else
        promiseObj:resolve({ success = false, message = "RPC subsystem unavailable" })
    end
    return Citizen.Await(promiseObj)
end

-- 1. Cache Synchronization Listener
RegisterNetEvent("nyx:services:client:chemlabStatusChanged", function(labId, labData)
    if labId and labData then
        CachedChemLabs[labId] = labData
    end
end)

-- 2. Fetch Initial Lab State from Server
CreateThread(function()
    Wait(1500)
    local res = callRpc("services:getChemicalLabs")
    if res and res.success and res.labs then
        for _, lab in ipairs(res.labs) do
            CachedChemLabs[lab.labId] = lab
        end
    end
end)

-- 3. Register Third-Eye Spatial Interaction Targets (nyx_interact)
local KnownLabPoints = {
    ['chemlab_humane_biotech'] = {
        label = "Humane Bio-Research Pharmacological Suite",
        coords = vector3(3538.5, 3660.2, 28.1),
        radius = 2.0
    },
    ['chemlab_cypress_refinery'] = {
        label = "Cypress Industrial Chemical Processing Lab",
        coords = vector3(922.5, -2148.0, 30.5),
        radius = 2.0
    },
    ['chemlab_pillbox_pharmacy'] = {
        label = "Pillbox Hill Clinical Synthesis Laboratory",
        coords = vector3(356.2, -598.4, 43.3),
        radius = 2.0
    },
    ['chemlab_sandy_lab'] = {
        label = "Senora Desert Remote Bio-Synthesis Station",
        coords = vector3(1852.3, 3680.1, 34.2),
        radius = 2.0
    }
}

CreateThread(function()
    Wait(2000)
    if exports['nyx_interact'] and exports['nyx_interact'].AddInteractionPoint then
        for labId, point in pairs(KnownLabPoints) do
            local pointId = "chemlab_" .. labId
            RegisteredInteractTargets[#RegisteredInteractTargets + 1] = pointId

            exports['nyx_interact']:AddInteractionPoint({
                id = pointId,
                coords = point.coords,
                radius = point.radius,
                label = point.label,
                options = {
                    {
                        label = "Gyógyszerszintézis Indítása (Bio-Chemical Synthesis)",
                        icon = "fas fa-flask",
                        action = function()
                            TriggerEvent("nyx:services:client:openSynthesisMenu", labId)
                        end
                    },
                    {
                        label = "Autokláv Sterilizálása (Sterilize Lab)",
                        icon = "fas fa-shield-virus",
                        action = function()
                            TriggerEvent("nyx:services:client:sterilizeLab", labId)
                        end
                    },
                    {
                        label = "Laboratóriumi Diagnosztika & Telemetria",
                        icon = "fas fa-microscope",
                        action = function()
                            TriggerEvent("nyx:services:client:inspectLab", labId)
                        end
                    }
                }
            })
        end
    end
end)

-- 4. Event Handlers for UI & Actions
RegisterNetEvent("nyx:services:client:openSynthesisMenu", function(labId)
    local res = callRpc("services:getChemicalLabDetails", labId)
    if not res or not res.success then
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = res and res.message or "A laboratórium állapota nem elérhető."
        })
        return
    end

    local lab = res.lab
    if lab.status == "synthesizing" then
        TriggerEvent("nyx:core:client:notify", {
            type = "warning",
            message = string.format("Az autokláv jelenleg foglalt! Aktív recept: %s", lab.activeRecipe or "Szintézis")
        })
        return
    elseif lab.status == "contaminated" then
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = "A laboratórium kontaminálódott! Végezz sterilizálást fertőtlenítőszerrel a használat előtt."
        })
        return
    elseif not res.isPowered then
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = "A körzetben áramkimaradás van! A centrifugák és autoklávok áram nélkül nem üzemelnek."
        })
        return
    end

    -- Trigger UI or console selection
    TriggerEvent("nyx:core:client:notify", {
        type = "info",
        message = string.format("[%s] Sterilitás: %.1f%%. Használd a /synthesize [recept] [mennyiség] parancsot!", lab.labLabel, lab.sterilityLevel)
    })
end)

RegisterNetEvent("nyx:services:client:sterilizeLab", function(labId)
    local res = callRpc("services:startLabSterilization", labId)
    if res and res.success then
        TriggerEvent("nyx:core:client:notify", {
            type = "success",
            message = string.format("Sterilizálási ciklus elindítva (%s felhasználásával)... Időtartam: %d mp.", res.data.consumedItem, res.data.durationSeconds)
        })
    else
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = res and res.data or "A sterilizálás nem sikerült."
        })
    end
end)

RegisterNetEvent("nyx:services:client:inspectLab", function(labId)
    local res = callRpc("services:getChemicalLabDetails", labId)
    if not res or not res.success then
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = "Nem sikerült lekérdezni a laboratóriumi telemetriát."
        })
        return
    end

    local lab = res.lab
    local powerStatus = res.isPowered and "^2ONLINE (STABIL)^7" or "^1OFFLINE (ÁRAMKIMARADÁS)^7"
    local lines = {
        string.format("^3=== %s ===^7", lab.labLabel),
        string.format("• Hálózati Állapot: %s", powerStatus),
        string.format("• Autokláv Státusz: %s", lab.statusLabel),
        string.format("• Sterilitási Szint: %.1f%%", lab.sterilityLevel),
        string.format("• Áramfelvétel: %.1f kW", lab.powerDrawKw),
        string.format("• Összes Termelt Tétel: %d db", lab.totalBatches)
    }

    for _, l in ipairs(lines) do
        TriggerEvent("chat:addMessage", { args = { "[Labor]", l } })
    end
end)

-- 5. Player Commands
RegisterCommand("chemlabs", function()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local nearby = {}

    for labId, point in pairs(KnownLabPoints) do
        local dist = #(pCoords - point.coords)
        if dist <= 150.0 then
            local cached = CachedChemLabs[labId]
            local sterility = cached and cached.sterilityLevel or 100.0
            local status = cached and cached.statusLabel or "ÜZEMKÉSZ"
            table.insert(nearby, string.format("• %s (%.1fm) - %s [Sterilitás: %.1f%%]", point.label, dist, status, sterility))
        end
    end

    if #nearby == 0 then
        TriggerEvent("chat:addMessage", { args = { "[Labor]", "Nincs a közeledben ismert kémiai laboratórium (150m-en belül)." } })
    else
        TriggerEvent("chat:addMessage", { args = { "[Labor]", "^3Közeli Kémiai & Gyógyszerészeti Munkaállomások:^7" } })
        for _, n in ipairs(nearby) do
            TriggerEvent("chat:addMessage", { args = { "[Labor]", n } })
        end
    end
end, false)

RegisterCommand("synthesize", function(_, args)
    local recipeKey = args[1]
    local quantity = tonumber(args[2]) or 1

    if not recipeKey then
        TriggerEvent("chat:addMessage", { args = { "[Labor]", "Használat: /synthesize [recept] [mennyiség]" } })
        TriggerEvent("chat:addMessage", { args = { "[Labor]", "Receptek: saline_purification, synthetic_plasma_synthesis, surgical_pack_autoclave, disinfectant_compounding, hospital_linens_sanitization, sterile_pressure_bandage, tourniquet_assembly, morphine_ampoule_synthesis" } })
        return
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local closestLabId = nil
    local closestDist = 999.0

    for labId, point in pairs(KnownLabPoints) do
        local dist = #(pCoords - point.coords)
        if dist < closestDist then
            closestDist = dist
            closestLabId = labId
        end
    end

    if not closestLabId or closestDist > Nyx.ChemicalLabs.MaxInteractionDistance + 2.0 then
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = "Nem vagy kémiai laboratórium közvetlen közelében!"
        })
        return
    end

    local res = callRpc("services:startChemicalSynthesis", closestLabId, recipeKey, quantity)
    if res and res.success then
        TriggerEvent("nyx:core:client:notify", {
            type = "success",
            message = string.format("Szintézis elindítva: %s (x%d)... Időtartam: %d mp.", res.data.recipeLabel, res.data.quantity, res.data.durationSeconds)
        })
    else
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = res and res.data or "A szintézis nem indítható el."
        })
    end
end, false)

RegisterCommand("sterilizelab", function()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local closestLabId = nil
    local closestDist = 999.0

    for labId, point in pairs(KnownLabPoints) do
        local dist = #(pCoords - point.coords)
        if dist < closestDist then
            closestDist = dist
            closestLabId = labId
        end
    end

    if not closestLabId or closestDist > Nyx.ChemicalLabs.MaxInteractionDistance + 2.0 then
        TriggerEvent("nyx:core:client:notify", {
            type = "error",
            message = "Nem vagy kémiai laboratórium közvetlen közelében!"
        })
        return
    end

    TriggerEvent("nyx:services:client:sterilizeLab", closestLabId)
end, false)

-- 6. Resource Stop Cleanup
AddEventHandler("onResourceStop", function(resName)
    if resName ~= GetCurrentResourceName() then return end
    if exports['nyx_interact'] and exports['nyx_interact'].RemoveInteractionPoint then
        for _, id in ipairs(RegisteredInteractTargets) do
            exports['nyx_interact']:RemoveInteractionPoint(id)
        end
    end
end)
