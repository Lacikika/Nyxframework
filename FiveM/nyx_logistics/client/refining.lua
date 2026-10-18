--[[
    Nyxframework: nyx_logistics
    File: client/refining.lua
    Description: Client spatial interaction, Third-Eye target registration (nyx_interact),
                 refining facility control, commands, and telemetry formatters.
]]

local CachedRefiningFacilities = {}
local RegisteredInteractPoints = {}

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

-- 1. Cache Synchronization Listeners
RegisterNetEvent("nyx:logistics:client:facilityStarted", function(data)
    if data and data.facilityId then
        local fac = CachedRefiningFacilities[data.facilityId] or {}
        fac.is_active = true
        fac.active_recipe = data.recipeKey
        fac.batches = data.batches
        fac.power_consumption_kw = data.powerKw
        CachedRefiningFacilities[data.facilityId] = fac
    end
end)

RegisterNetEvent("nyx:logistics:client:facilityCompleted", function(facilityId)
    if facilityId and CachedRefiningFacilities[facilityId] then
        local fac = CachedRefiningFacilities[facilityId]
        fac.is_active = false
        fac.active_recipe = nil
        fac.progress = 0.0
        fac.batches = 1
        fac.power_consumption_kw = 0.0
    end
end)

RegisterNetEvent("nyx:logistics:client:facilityPowerLost", function(facilityId, powerGridId, reason)
    if facilityId and CachedRefiningFacilities[facilityId] then
        local fac = CachedRefiningFacilities[facilityId]
        fac.power_status = "offline"
    end
end)

RegisterNetEvent("nyx:logistics:client:facilityPowerRestored", function(facilityId, powerGridId)
    if facilityId and CachedRefiningFacilities[facilityId] then
        local fac = CachedRefiningFacilities[facilityId]
        fac.power_status = "online"
    end
end)

-- 2. Fetch Initial Facilities from Server
CreateThread(function()
    Wait(1500)
    local res = callRpc("logistics:getRefiningFacilities")
    if res and type(res) == "table" then
        for _, fac in ipairs(res) do
            if fac.id then
                CachedRefiningFacilities[fac.id] = fac
            end
        end
    end
end)

-- 3. Canonical Spatial Interaction Points
local KnownRefiningFacilities = {
    ['fac_paleto_sawmill'] = {
        label = "Paleto Forest Fűrészüzem & Fafeldolgozó (Sawmill)",
        coords = vector3(-552.4, 5324.8, 73.6),
        radius = 3.0,
        type = "sawmill"
    },
    ['fac_elysian_foundry'] = {
        label = "Elysian Island Acélöntöde & Fémhengerlő (Foundry)",
        coords = vector3(1088.5, -2004.2, 31.5),
        radius = 3.0,
        type = "foundry"
    },
    ['fac_davis_textile'] = {
        label = "Davis Textilipari Szövőgyár & Pamutfonoda (Textile Mill)",
        coords = vector3(716.2, -962.4, 30.4),
        radius = 3.0,
        type = "textile"
    },
    ['fac_cypress_chemical'] = {
        label = "Cypress Vegyipari Szubsztrátüzem (Chemical Plant)",
        coords = vector3(920.0, -2150.0, 30.5),
        radius = 3.0,
        type = "chemical"
    },
    ['fac_davis_assembly'] = {
        label = "Davis Precíziós Összeszerelő Üzem (Assembly Plant)",
        coords = vector3(1085.0, -2002.0, 31.5),
        radius = 3.0,
        type = "assembly"
    }
}

-- 4. Third-Eye Spatial Interaction Targets (nyx_interact)
CreateThread(function()
    Wait(2000)
    if exports['nyx_interact'] and exports['nyx_interact'].AddInteractionPoint then
        for facId, point in pairs(KnownRefiningFacilities) do
            local pointId = "refining_" .. facId
            RegisteredInteractPoints[#RegisteredInteractPoints + 1] = pointId

            exports['nyx_interact']:AddInteractionPoint({
                id = pointId,
                coords = point.coords,
                radius = point.radius,
                label = point.label,
                options = {
                    {
                        label = "Ipari Finomítás & Gyártás Indítása (Start Refining)",
                        icon = "fas fa-cogs",
                        action = function()
                            TriggerEvent("nyx:logistics:client:openRefiningMenu", facId)
                        end
                    },
                    {
                        label = "Üzemi Telemetria & Áramellátás (Facility Telemetry)",
                        icon = "fas fa-bolt",
                        action = function()
                            TriggerEvent("nyx:logistics:client:inspectRefiningFacility", facId)
                        end
                    },
                    {
                        label = "Aktív Gyártási Ciklus Leállítása (Cancel Batch)",
                        icon = "fas fa-stop-circle",
                        action = function()
                            TriggerEvent("nyx:logistics:client:cancelRefiningBatch", facId)
                        end
                    }
                }
            })
        end
    end
end)

-- 5. Client Event Handlers
RegisterNetEvent("nyx:logistics:client:openRefiningMenu", function(facId)
    local fac = CachedRefiningFacilities[facId]
    local telemetry = callRpc("logistics:getRefiningFacilityTelemetry", facId)

    if telemetry then
        local def = Nyx.Refining.GetFacilityDefinition(telemetry.type)
        print(string.format("^2[Nyx:Logistics] %s (%s) - Állapot: %s, Fogyasztás: %.1f kW, Energia: %s^7",
            telemetry.typeLabel or facId, facId, telemetry.status, telemetry.powerConsumptionKw, telemetry.energyFormatted))

        if def and def.supportedRecipes then
            print("^3Támogatott Receptek:^7 " .. table.concat(def.supportedRecipes, ", "))
            print("^3Indításhoz használd:^7 /startrefining " .. facId .. " [recept_azonosító] [adag]")
        end
    else
        print(string.format("^1[Nyx:Logistics] Nem sikerült lekérdezni a(z) '%s' üzem adatait.^7", facId))
    end
end)

RegisterNetEvent("nyx:logistics:client:inspectRefiningFacility", function(facId)
    local telemetry = callRpc("logistics:getRefiningFacilityTelemetry", facId)
    if telemetry then
        print("^5==================================================^7")
        print(string.format("^5   NYX INDUSTRIAL TELEMETRY: %s^7", string.upper(telemetry.typeLabel or facId)))
        print("^5==================================================^7")
        print(string.format("  Üzem Azonosító: ^7%s", facId))
        print(string.format("  Típus:          ^7%s", telemetry.type or "N/A"))
        print(string.format("  Állapot:        ^7%s", telemetry.status))
        print(string.format("  Hálózat:        ^7%s", telemetry.powerLabel))
        print(string.format("  Teljesítmény:   ^7%.1f kW", telemetry.powerConsumptionKw))
        print(string.format("  Összes Energia: ^7%s", telemetry.energyFormatted))
        print(string.format("  Kimeneti Mód:   ^7%s", telemetry.outputMode))
        if telemetry.activeRecipeKey then
            print(string.format("  Aktív Termelés: ^7%s (%.1f%%)", telemetry.activeRecipeLabel or telemetry.activeRecipeKey, telemetry.progress))
        end
        print("^5==================================================^7")
    end
end)

RegisterNetEvent("nyx:logistics:client:cancelRefiningBatch", function(facId)
    local res = callRpc("logistics:cancelRefiningBatch", facId)
    if res and res.success then
        print(string.format("^2[Nyx:Logistics] A(z) '%s' üzem aktív gyártási ciklusát sikeresen leállítottad.^7", facId))
    else
        print(string.format("^1[Nyx:Logistics] Hiba a leállítás során: %s^7", res and res.error or "ISMERETLEN"))
    end
end)

-- 6. Player Commands
RegisterCommand("refining", function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    print("^5--- Közeli Ipari Finomítók & Üzemek ---^7")
    local found = 0
    for facId, point in pairs(KnownRefiningFacilities) do
        local dist = #(coords - point.coords)
        if dist <= 150.0 then
            found = found + 1
            local telemetry = callRpc("logistics:getRefiningFacilityTelemetry", facId)
            local statusStr = telemetry and telemetry.status or "Elérhető"
            print(string.format("  [^3%s^7] %s - Távolság: %.1fm | Állapot: %s", facId, point.label, dist, statusStr))
        end
    end

    if found == 0 then
        print("^3[Nyx:Logistics] Nincs a közeledben 150 méteren belül ipari üzem vagy finomító.^7")
    end
end, false)

RegisterCommand("startrefining", function(_, args)
    local facId = args[1]
    local recipeKey = args[2]
    local batchCount = tonumber(args[3]) or 1

    if not facId or not recipeKey then
        print("^3Használat:^7 /startrefining [facilityId] [recipeKey] [batchCount]")
        return
    end

    local res = callRpc("logistics:startRefiningBatch", facId, recipeKey, batchCount)
    if res and res.success then
        print(string.format("^2[Nyx:Logistics] Gyártási tétel sikeresen elindítva!^7"))
        print(string.format("  Üzem: %s | Recept: %s | Adag: %d | Teljesítmény: %.1f kW | Időtartam: %ds",
            res.facilityId, res.recipeKey, res.batchCount, res.powerKw, res.durationSeconds))
    else
        print(string.format("^1[Nyx:Logistics] Hiba a tétel indításakor: %s^7", res and res.error or "ISMERETLEN"))
        if res and res.missingItem then
            print(string.format("  Hiányzó Alapanyag: %s (Szükséges: %d, Elérhető: %d)",
                res.missingItem, res.needed or 0, res.have or 0))
        end
    end
end, false)

-- 7. Public Client Helpers
function Nyx.Logistics.GetClosestRefiningFacility()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closestId, closestDist = nil, 999999.0

    for facId, point in pairs(KnownRefiningFacilities) do
        local dist = #(coords - point.coords)
        if dist < closestDist then
            closestDist = dist
            closestId = facId
        end
    end

    return closestId, closestDist
end

function Nyx.Logistics.GetNearbyRefiningFacilities(maxDist)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local list = {}
    local maxD = tonumber(maxDist) or 100.0

    for facId, point in pairs(KnownRefiningFacilities) do
        local dist = #(coords - point.coords)
        if dist <= maxD then
            list[#list + 1] = {
                id = facId,
                label = point.label,
                type = point.type,
                coords = point.coords,
                distance = dist
            }
        end
    end

    return list
end

-- 8. Teardown
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if exports['nyx_interact'] and exports['nyx_interact'].RemoveInteractionPoint then
            for _, pointId in ipairs(RegisteredInteractPoints) do
                pcall(function()
                    exports['nyx_interact']:RemoveInteractionPoint(pointId)
                end)
            end
        end
    end
end)
