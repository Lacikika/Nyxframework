--[[
    Nyxframework: nyx_inventory
    File: client/drops.lua
    Description: Client-side spatial ground drop streaming, entity rendering, orientation syncing,
                 smart weight-tiered 3D props, and Third-Eye (LALT) interaction routing (zero-busywait, no-press-E).
]]

Nyx = Nyx or {}
Nyx.Drops = {} -- [dropId] = { id = dropId, coords = vector3, rotation = { x, y, z, heading }, model = "...", entity = nil }

local defaultDropModelHash = GetHashKey(Config.DropModel or "prop_paper_bag_small")

-- Target options generator for world drop entities
function Nyx.Drops.GetTargetOptions(dropId)
    local drop = Nyx.Drops[dropId]
    local openLabel = (drop and drop.shelfNodeId) and "Open Shelf Storage" or "Open Ground Loot"
    local moveLabel = (drop and drop.shelfNodeId) and "Reposition / Move on Shelf" or "Reposition / Drag on Ground (LALT)"

    return {
        {
            icon = "fa-solid fa-box-open",
            label = openLabel,
            event = "nyx:inventory:client:openTargetDrop",
            args = { dropId = dropId },
            canInteract = function(entity, dist)
                return dist <= (Config.DropInteractDistance or 2.5) and not (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing())
            end
        },
        {
            icon = "fa-solid fa-arrows-up-down-left-right",
            label = moveLabel,
            event = "nyx:inventory:client:grabTargetDrop",
            args = { dropId = dropId },
            canInteract = function(entity, dist)
                return dist <= ((Config.Placement and Config.Placement.MaxDistance) or 6.0) and not (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing())
            end
        },
        {
            icon = "fa-solid fa-hands-holding",
            label = "Pick Up & Carry (Two-Handed)",
            event = "nyx:inventory:client:pickupHeavyFreight",
            args = { dropId = dropId },
            canInteract = function(entity, dist)
                local isPlacing = (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing())
                local isCarrying = (Nyx.Freight and Nyx.Freight.IsCarryingFreight and Nyx.Freight.IsCarryingFreight())
                local maxDist = (Config.HeavyCarry and Config.HeavyCarry.InteractDistance) or 2.5
                return dist <= maxDist and not isPlacing and not isCarrying
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
        local modelToPlace = drop.model
        if not modelToPlace and drop.entity and DoesEntityExist(drop.entity) then
            modelToPlace = GetEntityModel(drop.entity)
        end
        if not modelToPlace then
            modelToPlace = defaultDropModelHash
        end

        Nyx.Placement.Start({
            dropId = dropId,
            model = modelToPlace,
            label = "Ground Container"
        })
    end
end)

-- Client-Side Spatial Partitioning Grid Index
Nyx.ClientSpatialGrid = {
    cells = {},      -- [cellKey] = { [dropId] = true }
    dropCells = {}   -- [dropId] = cellKey
}

function Nyx.ClientSpatialGrid.Insert(dropId, coords, bucket)
    if not dropId or not coords then return end
    bucket = tonumber(bucket) or 0
    local cellKey = nil
    if Nyx.SpatialGrid and Nyx.SpatialGrid.GetCellKeyFromCoords then
        cellKey = Nyx.SpatialGrid.GetCellKeyFromCoords(coords, bucket)
    else
        cellKey = string.format("%d:%d:%d", math.floor(coords.x / 64.0), math.floor(coords.y / 64.0), bucket)
    end

    local oldKey = Nyx.ClientSpatialGrid.dropCells[dropId]
    if oldKey and oldKey ~= cellKey and Nyx.ClientSpatialGrid.cells[oldKey] then
        Nyx.ClientSpatialGrid.cells[oldKey][dropId] = nil
        if next(Nyx.ClientSpatialGrid.cells[oldKey]) == nil then
            Nyx.ClientSpatialGrid.cells[oldKey] = nil
        end
    end

    Nyx.ClientSpatialGrid.cells[cellKey] = Nyx.ClientSpatialGrid.cells[cellKey] or {}
    Nyx.ClientSpatialGrid.cells[cellKey][dropId] = true
    Nyx.ClientSpatialGrid.dropCells[dropId] = cellKey
    return cellKey
end

function Nyx.ClientSpatialGrid.Remove(dropId)
    local cellKey = Nyx.ClientSpatialGrid.dropCells[dropId]
    if cellKey and Nyx.ClientSpatialGrid.cells[cellKey] then
        Nyx.ClientSpatialGrid.cells[cellKey][dropId] = nil
        if next(Nyx.ClientSpatialGrid.cells[cellKey]) == nil then
            Nyx.ClientSpatialGrid.cells[cellKey] = nil
        end
    end
    Nyx.ClientSpatialGrid.dropCells[dropId] = nil
end

-- Sync entire drop table from server
RegisterNetEvent("nyx:inventory:client:syncDrops", function(dropList)
    -- Despawn any drops not in new list or mismatched bucket
    local newIds = {}
    for _, d in ipairs(dropList) do
        if d and d.id and d.coords then
            newIds[d.id] = true
            local existing = Nyx.Drops[d.id]
            local cVec = vector3(d.coords.x, d.coords.y, d.coords.z)
            local bucket = tonumber(d.routingBucket) or 0
            local cellKey = Nyx.ClientSpatialGrid.Insert(d.id, cVec, bucket)

            Nyx.Drops[d.id] = {
                id = d.id,
                coords = cVec,
                rotation = d.rotation or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
                model = d.model or Config.DropModel or "prop_paper_bag_small",
                routingBucket = bucket,
                shelfNodeId = d.shelfNodeId,
                gridCell = cellKey,
                entity = existing and existing.entity or nil
            }
        end
    end

    -- Clean up removed drops
    for dropId, drop in pairs(Nyx.Drops) do
        if not newIds[dropId] then
            Nyx.ClientSpatialGrid.Remove(dropId)
            if drop.entity and DoesEntityExist(drop.entity) then
                if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                    exports['nyx_interact']:RemoveTargetEntity(drop.entity)
                end
                DeleteEntity(drop.entity)
            end
            Nyx.Drops[dropId] = nil
        end
    end
end)

-- Sync cell-specific drops from interest management dispatcher
RegisterNetEvent("nyx:inventory:client:syncCellDrops", function(dropList)
    if type(dropList) ~= "table" then return end
    for _, d in ipairs(dropList) do
        if d and d.id and d.coords then
            local existing = Nyx.Drops[d.id]
            local cVec = vector3(d.coords.x, d.coords.y, d.coords.z)
            local bucket = tonumber(d.routingBucket) or 0
            local cellKey = Nyx.ClientSpatialGrid.Insert(d.id, cVec, bucket)

            Nyx.Drops[d.id] = {
                id = d.id,
                coords = cVec,
                rotation = d.rotation or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
                model = d.model or Config.DropModel or "prop_paper_bag_small",
                routingBucket = bucket,
                shelfNodeId = d.shelfNodeId,
                gridCell = cellKey,
                entity = existing and existing.entity or nil
            }
        end
    end
end)

-- Receive single newly created drop
RegisterNetEvent("nyx:inventory:client:dropCreated", function(dropId, coords, rotation, model, routingBucket, shelfNodeId, cellKey)
    local cVec = vector3(coords.x, coords.y, coords.z)
    local bucket = tonumber(routingBucket) or 0
    cellKey = cellKey or Nyx.ClientSpatialGrid.Insert(dropId, cVec, bucket)

    Nyx.Drops[dropId] = {
        id = dropId,
        coords = cVec,
        rotation = rotation or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
        model = model or Config.DropModel or "prop_paper_bag_small",
        routingBucket = bucket,
        shelfNodeId = shelfNodeId,
        gridCell = cellKey,
        entity = nil
    }
end)

-- Receive position and rotation update when drop is moved/repositioned
RegisterNetEvent("nyx:inventory:client:dropMoved", function(dropId, coords, rotation, shelfNodeId, cellKey)
    local drop = Nyx.Drops[dropId]
    local cVec = vector3(coords.x, coords.y, coords.z)
    local bucket = drop and drop.routingBucket or 0
    cellKey = cellKey or Nyx.ClientSpatialGrid.Insert(dropId, cVec, bucket)

    if drop then
        drop.coords = cVec
        drop.rotation = rotation or drop.rotation
        drop.gridCell = cellKey
        if shelfNodeId ~= nil then
            drop.shelfNodeId = (shelfNodeId and shelfNodeId ~= "") and shelfNodeId or nil
        end
        if drop.entity and DoesEntityExist(drop.entity) then
            SetEntityCoords(drop.entity, drop.coords.x, drop.coords.y, drop.coords.z, false, false, false, true)
            SetEntityHeading(drop.entity, drop.rotation.heading or 0.0)
            SetEntityVisible(drop.entity, true, false)
        end
    else
        Nyx.Drops[dropId] = {
            id = dropId,
            coords = cVec,
            rotation = rotation or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
            model = Config.DropModel or "prop_paper_bag_small",
            routingBucket = 0,
            shelfNodeId = shelfNodeId,
            gridCell = cellKey,
            entity = nil
        }
    end
end)

-- Receive model update when items merge or change weight
RegisterNetEvent("nyx:inventory:client:dropModelUpdated", function(dropId, newModel)
    local drop = Nyx.Drops[dropId]
    if drop then
        drop.model = newModel
        -- If entity is spawned, despawn old entity so spatial thread spawns updated 3D prop
        if drop.entity and DoesEntityExist(drop.entity) then
            if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                exports['nyx_interact']:RemoveTargetEntity(drop.entity)
            end
            DeleteEntity(drop.entity)
            drop.entity = nil
        end
    end
end)

-- Remove deleted drop
RegisterNetEvent("nyx:inventory:client:dropRemoved", function(dropId)
    Nyx.ClientSpatialGrid.Remove(dropId)
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

-- Register all fallback drop models with nyx_interact
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    local fallbackNames = (Nyx.Drops and Nyx.Drops.GetAllFallbackModels) and Nyx.Drops.GetAllFallbackModels() or {
        Config.DropModel or "prop_paper_bag_small",
        "prop_cs_cardbox_01",
        "prop_boxpile_06a"
    }

    local targetModelHashes = {}
    for _, name in ipairs(fallbackNames) do
        targetModelHashes[#targetModelHashes + 1] = (type(name) == "number") and name or GetHashKey(name)
    end

    exports['nyx_interact']:AddTargetModel(targetModelHashes, {
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
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local cullDist = Config.DropCullDistance or 25.0
        local currentBucket = (LocalPlayer and LocalPlayer.state and LocalPlayer.state.routingBucket) or 0

        -- Query candidates only from adjacent spatial grid cells
        local candidateDropIds = {}
        if Nyx.SpatialGrid and Nyx.SpatialGrid.GetCellsInRadius then
            local cellKeys = Nyx.SpatialGrid.GetCellsInRadius(playerCoords.x, playerCoords.y, cullDist + 10.0, currentBucket)
            for _, cKey in ipairs(cellKeys) do
                local c = Nyx.ClientSpatialGrid.cells[cKey]
                if c then
                    for id, _ in pairs(c) do
                        candidateDropIds[id] = true
                    end
                end
            end
        else
            for id, _ in pairs(Nyx.Drops) do
                candidateDropIds[id] = true
            end
        end

        for dropId, drop in pairs(Nyx.Drops) do
            local dropBucket = tonumber(drop.routingBucket) or 0

            if dropBucket ~= currentBucket or not candidateDropIds[dropId] then
                -- Despawn if in mismatched virtual routing bucket or outside active cell neighborhood
                if drop.entity and DoesEntityExist(drop.entity) then
                    if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                        exports['nyx_interact']:RemoveTargetEntity(drop.entity)
                    end
                    DeleteEntity(drop.entity)
                    drop.entity = nil
                end
            else
                local dist = #(playerCoords - drop.coords)

                -- In range: spawn visual prop
                if dist <= cullDist then
                    local targetModel = drop.model or Config.DropModel or "prop_paper_bag_small"
                    local modelHash = (type(targetModel) == "number") and targetModel or GetHashKey(targetModel)

                    -- If existing entity has outdated model hash (e.g. upgraded box after merge), despawn it
                    if drop.entity and DoesEntityExist(drop.entity) and GetEntityModel(drop.entity) ~= modelHash then
                        if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                            exports['nyx_interact']:RemoveTargetEntity(drop.entity)
                        end
                        DeleteEntity(drop.entity)
                        drop.entity = nil
                    end

                    if not drop.entity or not DoesEntityExist(drop.entity) then
                        RequestModel(modelHash)
                        local loadTimeout = 0
                        while not HasModelLoaded(modelHash) and loadTimeout < 25 do
                            Wait(20)
                            loadTimeout = loadTimeout + 1
                        end

                        if HasModelLoaded(modelHash) then
                            local obj = CreateObject(modelHash, drop.coords.x, drop.coords.y, drop.coords.z, false, false, false)
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
        end

        Wait(1000)
    end
end)

-- Public client export to query nearby ground drops
exports("GetNearbyGroundDrops", function(radius)
    radius = tonumber(radius) or (Config.DropInteractDistance or 2.5)
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local currentBucket = (LocalPlayer and LocalPlayer.state and LocalPlayer.state.routingBucket) or 0
    local results = {}

    local candidateDropIds = {}
    if Nyx.SpatialGrid and Nyx.SpatialGrid.GetCellsInRadius then
        local cellKeys = Nyx.SpatialGrid.GetCellsInRadius(playerCoords.x, playerCoords.y, radius, currentBucket)
        for _, cKey in ipairs(cellKeys) do
            local c = Nyx.ClientSpatialGrid.cells[cKey]
            if c then
                for id, _ in pairs(c) do candidateDropIds[id] = true end
            end
        end
    else
        for id, _ in pairs(Nyx.Drops) do candidateDropIds[id] = true end
    end

    for dropId, _ in pairs(candidateDropIds) do
        local drop = Nyx.Drops[dropId]
        if drop and (drop.routingBucket or 0) == currentBucket and drop.coords then
            local dist = #(playerCoords - drop.coords)
            if dist <= radius then
                results[#results + 1] = {
                    id = dropId,
                    dropId = dropId,
                    distance = dist,
                    coords = drop.coords,
                    model = drop.model,
                    shelfNodeId = drop.shelfNodeId
                }
            end
        end
    end

    table.sort(results, function(a, b) return a.distance < b.distance end)
    return results
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

