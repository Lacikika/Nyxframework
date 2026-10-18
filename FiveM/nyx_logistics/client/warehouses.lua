--[[
    Nyxframework: nyx_logistics
    File: client/warehouses.lua
    Description: Client-side warehouse interior management, physical shelf prop rendering,
                 Third-Eye interactions, and grid-snapping node resolution.
]]

Nyx = Nyx or {}
Nyx.Warehouses = Nyx.Warehouses or {}

Nyx.Warehouses.CurrentWarehouse = nil
Nyx.Warehouses.ActiveNodes = {}              -- [nodeId] = nodeObj
Nyx.Warehouses.SpawnedShelfEntities = {}     -- [shelfId] = entityHandle
Nyx.Warehouses.KnownWarehouses = {}          -- [warehouseId] = warehouseData

-- Resolve nearest snap node for placement hologram
function Nyx.Warehouses.GetNearbySnapNode(targetCoords, maxDist, currentDropId)
    if not targetCoords then return nil, nil end
    local searchDist = maxDist or (Config.Warehouse and Config.Warehouse.SnapDistance) or 0.85
    return Nyx.Warehouses.FindNearestSnapNode(Nyx.Warehouses.ActiveNodes, targetCoords, searchDist, currentDropId)
end

-- Spawn a physical shelf prop inside the warehouse interior
local function spawnShelfEntity(shelf)
    if not shelf or not shelf.coords then return nil end

    local modelName = shelf.model or Config.Warehouse.DefaultShelfModel or "prop_rub_cabinet02"
    local modelHash = (type(modelName) == "number") and modelName or GetHashKey(modelName)

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 40 do
        Wait(25)
        timeout = timeout + 1
    end

    if not HasModelLoaded(modelHash) then return nil end

    local cx = tonumber(shelf.coords.x or shelf.coords[1]) or 0.0
    local cy = tonumber(shelf.coords.y or shelf.coords[2]) or 0.0
    local cz = tonumber(shelf.coords.z or shelf.coords[3]) or 0.0
    local heading = tonumber(shelf.heading or (shelf.rotation and (shelf.rotation.heading or shelf.rotation.z))) or 0.0

    local obj = CreateObject(modelHash, cx, cy, cz, false, false, false)
    SetEntityHeading(obj, heading)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)

    return obj
end

-- Despawn all shelf props in the warehouse
local function cleanupShelfEntities()
    for shelfId, ent in pairs(Nyx.Warehouses.SpawnedShelfEntities) do
        if DoesEntityExist(ent) then
            if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
                exports['nyx_interact']:RemoveTargetEntity(ent)
            end
            DeleteEntity(ent)
        end
    end
    Nyx.Warehouses.SpawnedShelfEntities = {}
end

-- Receive interior layout synchronization from server upon entering warehouse
RegisterNetEvent("nyx:logistics:client:syncWarehouseInterior", function(warehouseId, routingBucket, shelves, nodes)
    cleanupShelfEntities()

    Nyx.Warehouses.CurrentWarehouse = warehouseId
    Nyx.Warehouses.ActiveNodes = {}

    -- Register nodes
    if nodes then
        for nodeId, nodeData in pairs(nodes) do
            Nyx.Warehouses.ActiveNodes[nodeId] = nodeData
        end
    end

    -- Spawn physical shelf racks in this interior
    if shelves then
        for shelfId, sData in pairs(shelves) do
            local ent = spawnShelfEntity(sData)
            if ent then
                Nyx.Warehouses.SpawnedShelfEntities[shelfId] = ent

                -- Register Third-Eye on shelf rack
                if exports['nyx_interact'] and exports['nyx_interact'].AddTargetEntity then
                    exports['nyx_interact']:AddTargetEntity(ent, {
                        options = {
                            {
                                icon = "fa-solid fa-boxes-stacked",
                                label = string.format("Inspect %s", sData.label or "Storage Rack"),
                                event = "nyx:logistics:client:inspectShelf",
                                args = { shelfId = shelfId, warehouseId = warehouseId },
                                canInteract = function() return true end
                            }
                        },
                        distance = 2.5
                    })
                end
            end
        end
    end

    if exports['nyx_ui'] and exports['nyx_ui'].Notify then
        exports['nyx_ui']:Notify("info", "WAREHOUSE", string.format("Entered storage facility (Virtual Bucket %d).", routingBucket))
    end
end)

-- Receive node state updates (e.g. drop placed or removed from shelf)
RegisterNetEvent("nyx:logistics:client:shelfNodeUpdated", function(warehouseId, shelfId, nodeId, dropId, itemData)
    if Nyx.Warehouses.CurrentWarehouse == warehouseId and Nyx.Warehouses.ActiveNodes[nodeId] then
        Nyx.Warehouses.ActiveNodes[nodeId].occupiedDropId = dropId
        Nyx.Warehouses.ActiveNodes[nodeId].itemData = itemData
    end
end)

-- Receive exit cleanup
RegisterNetEvent("nyx:logistics:client:exitWarehouseCleanup", function()
    cleanupShelfEntities()
    Nyx.Warehouses.CurrentWarehouse = nil
    Nyx.Warehouses.ActiveNodes = {}

    if exports['nyx_ui'] and exports['nyx_ui'].Notify then
        exports['nyx_ui']:Notify("info", "WAREHOUSE", "Exited storage facility (Restored Public Bucket 0).")
    end
end)

-- Third-Eye action: Enter Warehouse
RegisterNetEvent("nyx:logistics:client:enterWarehouse", function(args)
    local warehouseId = args and args.warehouseId
    if not warehouseId then return end

    local res = exports['nyx_core']:TriggerRPCAwait("logistics:enterWarehouse", warehouseId)
    if not res or not res.success then
        if exports['nyx_ui'] and exports['nyx_ui'].Notify then
            exports['nyx_ui']:Notify("error", "WAREHOUSE", res and res.error or "Failed to enter warehouse.")
        end
    end
end)

-- Third-Eye action: Exit Warehouse
RegisterNetEvent("nyx:logistics:client:exitWarehouse", function(args)
    local warehouseId = (args and args.warehouseId) or Nyx.Warehouses.CurrentWarehouse
    local res = exports['nyx_core']:TriggerRPCAwait("logistics:exitWarehouse", warehouseId)
    if not res or not res.success then
        if exports['nyx_ui'] and exports['nyx_ui'].Notify then
            exports['nyx_ui']:Notify("error", "WAREHOUSE", res and res.error or "Failed to exit warehouse.")
        end
    end
end)

-- Third-Eye action: Inspect Shelf
RegisterNetEvent("nyx:logistics:client:inspectShelf", function(args)
    local shelfId = args and args.shelfId
    if not shelfId then return end

    local occupiedCount = 0
    local totalCount = 0

    for _, node in pairs(Nyx.Warehouses.ActiveNodes) do
        if node.shelfId == shelfId then
            totalCount = totalCount + 1
            if node.occupiedDropId then
                occupiedCount = occupiedCount + 1
            end
        end
    end

    if exports['nyx_ui'] and exports['nyx_ui'].Notify then
        exports['nyx_ui']:Notify("info", "SHELF MATRIX", string.format("Rack Occupancy: %d / %d slots filled. Hold LALT to snap boxes.", occupiedCount, totalCount))
    end
end)

-- Register Initial Third-Eye Door Targets
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    -- Default seed exterior warehouse doors
    local initialDoors = {
        {
            id = "wh_dock_ls_01",
            coords = vector3(899.6, -2982.5, -4.0),
            label = "Enter Port Warehouse 4"
        },
        {
            id = "wh_sandy_dist_01",
            coords = vector3(1700.2, 3780.5, 34.5),
            label = "Enter Sandy Freight Depot"
        }
    }

    for _, door in ipairs(initialDoors) do
        exports['nyx_interact']:AddTargetPoint(door.coords, {
            options = {
                {
                    icon = "fa-solid fa-warehouse",
                    label = door.label,
                    event = "nyx:logistics:client:enterWarehouse",
                    args = { warehouseId = door.id },
                    canInteract = function(entity, dist)
                        return dist <= (Config.Warehouse.DoorInteractDistance or 3.0) and Nyx.Warehouses.CurrentWarehouse == nil
                    end
                }
            },
            distance = Config.Warehouse.DoorInteractDistance or 3.0
        })
    end

    -- Interior exit door interaction (placed near interior exit point)
    local interiorExitCoords = vector3(1048.5, -3100.0, -39.0)
    exports['nyx_interact']:AddTargetPoint(interiorExitCoords, {
        options = {
            {
                icon = "fa-solid fa-door-open",
                label = "Exit Warehouse",
                event = "nyx:logistics:client:exitWarehouse",
                args = {},
                canInteract = function(entity, dist)
                    return dist <= 3.5 and Nyx.Warehouses.CurrentWarehouse ~= nil
                end
            }
        },
        distance = 3.5
    })
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    cleanupShelfEntities()
end)

-- Public Exports
exports('GetNearbySnapNode', function(targetCoords, maxDist, currentDropId)
    return Nyx.Warehouses.GetNearbySnapNode(targetCoords, maxDist, currentDropId)
end)

exports('GetCurrentWarehouse', function()
    return Nyx.Warehouses.CurrentWarehouse
end)

exports('IsInWarehouse', function()
    return Nyx.Warehouses.CurrentWarehouse ~= nil
end)
