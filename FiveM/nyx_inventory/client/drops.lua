--[[
    Nyxframework: nyx_inventory
    File: client/drops.lua
    Description: Client-side spatial ground drop streaming, entity rendering, and interaction hooks.
]]

Nyx = Nyx or {}
Nyx.Drops = {} -- [dropId] = { id = dropId, coords = vector3, entity = nil }

local dropModelHash = GetHashKey(Config.DropModel or "prop_paper_bag_small")

-- Sync entire drop table from server
RegisterNetEvent("nyx:inventory:client:syncDrops", function(dropList)
    for _, d in ipairs(dropList) do
        if d and d.id and d.coords then
            Nyx.Drops[d.id] = {
                id = d.id,
                coords = vector3(d.coords.x, d.coords.y, d.coords.z),
                entity = nil
            }
        end
    end
end)

-- Receive single newly created drop
RegisterNetEvent("nyx:inventory:client:dropCreated", function(dropId, coords)
    Nyx.Drops[dropId] = {
        id = dropId,
        coords = vector3(coords.x, coords.y, coords.z),
        entity = nil
    }
end)

-- Remove deleted drop
RegisterNetEvent("nyx:inventory:client:dropRemoved", function(dropId)
    local d = Nyx.Drops[dropId]
    if d then
        if d.entity and DoesEntityExist(d.entity) then
            DeleteEntity(d.entity)
        end
        Nyx.Drops[dropId] = nil
    end
end)

-- Spatial Streaming & Model Management Thread (Runs at 1-second interval - Zero busy wait)
CreateThread(function()
    RequestModel(dropModelHash)
    while not HasModelLoaded(dropModelHash) do
        Wait(50)
    end

    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local cullDist = Config.DropCullDistance or 25.0

        for dropId, drop in pairs(Nyx.Drops) do
            local dist = #(playerCoords - drop.coords)

            -- In range: spawn visual prop
            if dist <= cullDist then
                if not drop.entity or not DoesEntityExist(drop.entity) then
                    local obj = CreateObject(dropModelHash, drop.coords.x, drop.coords.y, drop.coords.z, false, false, false)
                    SetEntityAsMissionEntity(obj, true, true)
                    FreezeEntityPosition(obj, true)
                    SetEntityCollision(obj, true, true)
                    PlaceObjectOnGroundProperly(obj)
                    drop.entity = obj
                end
            -- Out of range: despawn prop
            elseif dist > (cullDist + 5.0) then
                if drop.entity and DoesEntityExist(drop.entity) then
                    DeleteEntity(drop.entity)
                    drop.entity = nil
                end
            end
        end

        Wait(1000)
    end
end)

-- Interaction Proximity Tick (Checks closest drop for E keypress when within 2.0m)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local closestDrop = nil
        local closestDist = 999.0

        for dropId, drop in pairs(Nyx.Drops) do
            local dist = #(playerCoords - drop.coords)
            if dist <= (Config.DropInteractDistance or 2.0) and dist < closestDist then
                closestDist = dist
                closestDrop = drop
            end
        end

        if closestDrop then
            -- Near a drop, display prompt and check input
            -- Wait(0) only when actively in prompt radius; otherwise idle for 500ms
            BeginTextCommandDisplayHelp("STRING")
            AddTextComponentSubstringPlayerName("Press ~INPUT_CONTEXT~ to open Ground Loot")
            EndTextCommandDisplayHelp(0, false, true, -1)

            if IsControlJustPressed(0, 38) then -- INPUT_CONTEXT (E)
                Nyx.Inventory.Open(closestDrop.id)
            end
            Wait(0)
        else
            Wait(400)
        end
    end
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, drop in pairs(Nyx.Drops) do
        if drop.entity and DoesEntityExist(drop.entity) then
            DeleteEntity(drop.entity)
        end
    end
end)
