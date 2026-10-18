--[[
    Nyxframework: nyx_inventory
    File: client/drops.lua
    Description: Client-side spatial ground drop streaming, entity rendering, orientation syncing,
                 and Third-Eye (LALT) interaction routing (zero-busywait, no-press-E).
]]

Nyx = Nyx or {}
Nyx.Drops = {} -- [dropId] = { id = dropId, coords = vector3, rotation = { x, y, z, heading }, entity = nil }

local dropModelHash = GetHashKey(Config.DropModel or "prop_paper_bag_small")

-- Target options generator for world drop entities
function Nyx.Drops.GetTargetOptions(dropId)
    return {
        {
            icon = "fa-solid fa-box-open",
            label = "Open Ground Loot",
            event = "nyx:inventory:client:openTargetDrop",
            args = { dropId = dropId },
            canInteract = function(entity, dist)
                return dist <= (Config.DropInteractDistance or 2.5) and not (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing())
            end
        },
        {
            icon = "fa-solid fa-arrows-up-down-left-right",
            label = "Reposition / Move",
            event = "nyx:inventory:client:grabTargetDrop",
            args = { dropId = dropId },
            canInteract = function(entity, dist)
                return dist <= ((Config.Placement and Config.Placement.MaxDistance) or 6.0) and not (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing())
            end
        }
    }
end

-- Find drop ID from entity or coordinates
local function findDropByEntityOrCoords(entity, coords)
    if entity and entity ~= 0 then
        for id, drop in pairs(Nyx.Drops) do
            if drop.entity == entity then
                return id, drop
            end
        end
    end

    if coords then
        local cVec = vector3(coords.x, coords.y, coords.z)
        local closestId, closestDrop = nil, nil
        local closestDist = 999.0
        for id, drop in pairs(Nyx.Drops) do
            local d = #(drop.coords - cVec)
            if d < closestDist and d <= 3.0 then
                closestDist = d
                closestId = id
                closestDrop = drop
            end
        end
        if closestId then
            return closestId, closestDrop
        end
    end

    -- Fallback: closest drop to player
    local pCoords = GetEntityCoords(PlayerPedId())
    local closestId, closestDrop = nil, nil
    local closestDist = 999.0
    for id, drop in pairs(Nyx.Drops) do
        local d = #(drop.coords - pCoords)
        if d < closestDist and d <= (Config.DropInteractDistance or 3.0) then
            closestDist = d
            closestId = id
            closestDrop = drop
        end
    end
    return closestId, closestDrop
end

-- Event to open drop container via Third-Eye selection
RegisterNetEvent("nyx:inventory:client:openTargetDrop", function(args, entity, netId, coords)
    local dropId = args and args.dropId
    if not dropId then
        dropId = findDropByEntityOrCoords(entity, coords)
    end
    if dropId then
        Nyx.Inventory.Open(dropId)
    end
end)

-- Event to grab drop and start zero-packet hologram placement mode
RegisterNetEvent("nyx:inventory:client:grabTargetDrop", function(args, entity, netId, coords)
    local dropId, drop = nil, nil
    if args and args.dropId then
        dropId = args.dropId
        drop = Nyx.Drops[dropId]
    else
        dropId, drop = findDropByEntityOrCoords(entity, coords)
    end

    if dropId and drop and Nyx.Placement and Nyx.Placement.Start then
        Nyx.Placement.Start({
            dropId = dropId,
            model = drop.entity and DoesEntityExist(drop.entity) and GetEntityModel(drop.entity) or dropModelHash,
            label = "Ground Container"
        })
    end
end)

-- Sync entire drop table from server
RegisterNetEvent("nyx:inventory:client:syncDrops", function(dropList)
    for _, d in ipairs(dropList) do
        if d and d.id and d.coords then
            Nyx.Drops[d.id] = {
                id = d.id,
                coords = vector3(d.coords.x, d.coords.y, d.coords.z),
                rotation = d.rotation or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
                entity = nil
            }
        end
    end
end)

-- Receive single newly created drop
RegisterNetEvent("nyx:inventory:client:dropCreated", function(dropId, coords, rotation)
    Nyx.Drops[dropId] = {
        id = dropId,
        coords = vector3(coords.x, coords.y, coords.z),
        rotation = rotation or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
        entity = nil
    }
end)

-- Receive position and rotation update when drop is moved/repositioned
RegisterNetEvent("nyx:inventory:client:dropMoved", function(dropId, coords, rotation)
    local drop = Nyx.Drops[dropId]
    if drop then
        drop.coords = vector3(coords.x, coords.y, coords.z)
        drop.rotation = rotation or drop.rotation
        if drop.entity and DoesEntityExist(drop.entity) then
            SetEntityCoords(drop.entity, drop.coords.x, drop.coords.y, drop.coords.z, false, false, false, true)
            SetEntityHeading(drop.entity, drop.rotation.heading or 0.0)
            SetEntityVisible(drop.entity, true, false)
        end
    else
        Nyx.Drops[dropId] = {
            id = dropId,
            coords = vector3(coords.x, coords.y, coords.z),
            rotation = rotation or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
            entity = nil
        }
    end
end)

-- Remove deleted drop
RegisterNetEvent("nyx:inventory:client:dropRemoved", function(dropId)
    local d = Nyx.Drops[dropId]
    if d then
        if d.entity and DoesEntityExist(d.entity) then
            if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                exports['nyx_interact']:RemoveTargetEntity(d.entity)
            end
            DeleteEntity(d.entity)
        end
        Nyx.Drops[dropId] = nil
    end
end)

-- Register drop model target with nyx_interact
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    exports['nyx_interact']:AddTargetModel({ dropModelHash, `prop_cs_cardbox_01`, `prop_boxpile_06a` }, {
        options = {
            {
                icon = "fa-solid fa-box-open",
                label = "Open Ground Loot",
                event = "nyx:inventory:client:openTargetDrop",
                canInteract = function(entity, dist)
                    return dist <= (Config.DropInteractDistance or 2.5) and not (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing())
                end
            },
            {
                icon = "fa-solid fa-arrows-up-down-left-right",
                label = "Reposition / Move",
                event = "nyx:inventory:client:grabTargetDrop",
                canInteract = function(entity, dist)
                    return dist <= ((Config.Placement and Config.Placement.MaxDistance) or 6.0) and not (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing())
                end
            }
        },
        distance = 3.0
    })
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
                    SetEntityCoords(obj, drop.coords.x, drop.coords.y, drop.coords.z, false, false, false, true)
                    SetEntityHeading(obj, drop.rotation and drop.rotation.heading or 0.0)
                    drop.entity = obj

                    -- Register entity with Third-Eye interact
                    if exports['nyx_interact'] and exports['nyx_interact'].AddTargetEntity then
                        exports['nyx_interact']:AddTargetEntity(obj, {
                            options = Nyx.Drops.GetTargetOptions(dropId),
                            distance = Config.DropInteractDistance or 2.5
                        })
                    end
                end
            -- Out of range: despawn prop
            elseif dist > (cullDist + 5.0) then
                if drop.entity and DoesEntityExist(drop.entity) then
                    if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                        exports['nyx_interact']:RemoveTargetEntity(drop.entity)
                    end
                    DeleteEntity(drop.entity)
                    drop.entity = nil
                end
            end
        end

        Wait(1000)
    end
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, drop in pairs(Nyx.Drops) do
        if drop.entity and DoesEntityExist(drop.entity) then
            if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                exports['nyx_interact']:RemoveTargetEntity(drop.entity)
            end
            DeleteEntity(drop.entity)
        end
    end
end)
