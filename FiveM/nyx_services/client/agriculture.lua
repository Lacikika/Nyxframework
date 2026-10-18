--[[
    Nyxframework: nyx_services
    File: client/agriculture.lua
    Description: Client-side agricultural interactions, harvesting animations,
                 emergency food pantry telemetry, and food freshness inspection.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.CachedFarms = {}
Nyx.Services.CachedPantries = {}

local isHarvesting = false

-- ----------------------------------------------------------------------------
-- 1. Proximity Resolution Helpers
-- ----------------------------------------------------------------------------

--- Find the nearest registered agricultural farmland node
--- @param maxDist number|nil
--- @return table|nil nearestFarm, number distance
function Nyx.Services.GetNearestFarm(maxDist)
    maxDist = maxDist or 6.0
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local nearest, minDist = nil, maxDist

    for _, farm in pairs(Nyx.Services.CachedFarms) do
        local fCoords = farm.coords and vector3(farm.coords.x, farm.coords.y, farm.coords.z)
        if fCoords then
            local dist = #(coords - fCoords)
            if dist < minDist then
                minDist = dist
                nearest = farm
            end
        end
    end

    return nearest, minDist
end

--- Find the nearest registered emergency food pantry
--- @param maxDist number|nil
--- @return table|nil nearestPantry, number distance
function Nyx.Services.GetNearestPantry(maxDist)
    maxDist = maxDist or 8.0
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local nearest, minDist = nil, maxDist

    for _, pantry in pairs(Nyx.Services.CachedPantries) do
        local pCoords = pantry.coords and vector3(pantry.coords.x, pantry.coords.y, pantry.coords.z)
        if pCoords then
            local dist = #(coords - pCoords)
            if dist < minDist then
                minDist = dist
                nearest = pantry
            end
        end
    end

    return nearest, minDist
end

-- ----------------------------------------------------------------------------
-- 2. Crop Harvesting Action & Animation
-- ----------------------------------------------------------------------------

function Nyx.Services.PerformCropHarvest()
    if isHarvesting then return end

    local farm, dist = Nyx.Services.GetNearestFarm(6.0)
    if not farm then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "AGRICULTURE",
            message = "No agricultural farmland or crop field nearby."
        })
        return
    end

    if (farm.currentReserve or farm.current_reserve or 0) <= 0 then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "DEPLETED CROP FIELD",
            message = "This field's crop reserves are currently exhausted. Awaiting regeneration."
        })
        return
    end

    isHarvesting = true
    local ped = PlayerPedId()

    -- Play planting / gathering animation
    local animDict = "amb@world_human_gardener_plant@male@base"
    local animName = "base"
    RequestAnimDict(animDict)
    local timeout = 50
    while not HasAnimDictLoaded(animDict) and timeout > 0 do
        Wait(50)
        timeout = timeout - 1
    end

    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "HARVESTING",
        message = string.format("Harvesting %s... (Soil fertility: %.1f%%)", farm.name or "Crops", farm.soilFertility or 100.0)
    })

    Wait(3000)

    ClearPedTasks(ped)
    isHarvesting = false

    -- Authoritative server RPC invocation
    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        exports['nyx_core']:CallRPC("services:harvestCrop", { farmId = farm.id }, function(resp)
            if resp and resp.success and resp.data then
                local d = resp.data
                TriggerEvent("nyx:ui:notify", {
                    type = "success",
                    title = "HARVEST COMPLETE",
                    message = string.format("Gathered %d units of %s! Field reserve: %d remaining.", d.yield, d.cropType, d.remainingReserve)
                })
            else
                local err = (resp and resp.error) or "Harvest failed"
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "HARVEST FAILED",
                    message = tostring(err)
                })
            end
        end)
    end
end

-- ----------------------------------------------------------------------------
-- 3. Player Commands
-- ----------------------------------------------------------------------------

-- Command: Harvest nearest crop field
RegisterCommand("harvestcrop", function()
    Nyx.Services.PerformCropHarvest()
end, false)
RegisterCommand("harvest", function()
    Nyx.Services.PerformCropHarvest()
end, false)
RegisterCommand("aratas", function()
    Nyx.Services.PerformCropHarvest()
end, false)

-- Command: Check nearby pantry stock and food security index
RegisterCommand("pantrystock", function()
    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        exports['nyx_core']:CallRPC("services:getFoodPantries", {}, function(resp)
            if resp and resp.success and resp.pantries then
                local msg = "^5=== MUNICIPAL EMERGENCY FOOD PANTRIES ===^7\n"
                for _, p in ipairs(resp.pantries) do
                    local badgeStr = (p.status == "optimal") and "^2[OPTIMAL]^7" or (p.status == "degraded" and "^3[DEGRADED]^7" or "^1[CRITICAL SHORTAGE]^7")
                    msg = msg .. string.format("• %s (%s): %s | Security: %.1f%% | Rations: %d/%d | Bread: %d/%d\n",
                        p.name, p.zoneId, badgeStr, p.securityPercent or 0.0,
                        (p.counts and p.counts.food_ration) or 0, (p.metrics and p.metrics.targetRations) or 100,
                        (p.counts and p.counts.food_bread) or 0, (p.metrics and p.metrics.targetBread) or 50)
                end
                msg = msg .. "^5========================================^7"

                TriggerEvent("chat:addMessage", {
                    color = { 255, 180, 50 },
                    multiline = true,
                    args = { "FoodSecurity", msg }
                })
            end
        end)
    end
end, false)
RegisterCommand("elelmiszer", function()
    ExecuteCommand("pantrystock")
end, false)

-- ----------------------------------------------------------------------------
-- 4. Sync Listeners & Telemetry
-- ----------------------------------------------------------------------------

RegisterNetEvent("nyx:services:client:farmUpdated", function(farmId, reserve, soilFertility)
    if Nyx.Services.CachedFarms[farmId] then
        Nyx.Services.CachedFarms[farmId].currentReserve = reserve
        Nyx.Services.CachedFarms[farmId].soilFertility = soilFertility
    end
end)

-- Initial farm sync on boot
CreateThread(function()
    Wait(2000)
    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        exports['nyx_core']:CallRPC("services:getAgricultureFarms", {}, function(resp)
            if resp and resp.success and resp.farms then
                for _, f in ipairs(resp.farms) do
                    Nyx.Services.CachedFarms[f.id] = f
                end
            end
        end)

        exports['nyx_core']:CallRPC("services:getFoodPantries", {}, function(resp)
            if resp and resp.success and resp.pantries then
                for _, p in ipairs(resp.pantries) do
                    Nyx.Services.CachedPantries[p.id] = p
                end
            end
        end)
    end
end)

-- Export helper state
function Nyx.Services.IsHarvesting()
    return isHarvesting
end
