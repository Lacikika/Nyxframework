--[[
    Nyxframework: nyx_inventory
    File: server/drops.lua
    Description: Spatial grid ground drops manager with entity culling, orientation persistence,
                 and zero-packet placement synchronization.
]]

Nyx = Nyx or {}
Nyx.Drops = {} -- [dropId] = { id = dropId, coords = { x, y, z }, rotation = { x, y, z, heading }, invId = dropId }

-- Sanitize rotation angles and normalize heading (0 to 360 degrees)
local function sanitizeRotation(rotation)
    local heading = 0.0
    if type(rotation) == "table" then
        heading = tonumber(rotation.heading) or tonumber(rotation.z) or 0.0
    elseif type(rotation) == "number" then
        heading = rotation
    end
    heading = (heading % 360.0 + 360.0) % 360.0
    heading = math.floor(heading * 100) / 100
    return {
        x = 0.0,
        y = 0.0,
        z = heading,
        heading = heading
    }
end

-- Register and spawn a new physical ground drop container
function Nyx.Drops.Create(coords, itemData, rotation)
    local dropUuid = Nyx.RPC.GenerateNonce():sub(1, 8)
    local dropId = string.format("drop:%s", dropUuid)

    local safeCoords = {
        x = math.floor((coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or 0.0) * 100) / 100,
        z = math.floor(((coords.z or 70.0) + (Config.DropZOffset or -0.95)) * 100) / 100
    }
    local safeRotation = sanitizeRotation(rotation)

    local container = Nyx.Inventory.NewContainer(
        dropId,
        'drop',
        Config.Containers['drop'].maxWeight,
        Config.Containers['drop'].maxSlots,
        safeCoords
    )

    if itemData then
        container:setItem(1, itemData)
    end

    container:save()

    -- Persist rotation to database
    MySQL.query("UPDATE `nyx_inventories` SET `rotation` = ? WHERE `id` = ?", {
        json.encode(safeRotation),
        dropId
    })

    Nyx.Drops[dropId] = {
        id = dropId,
        coords = safeCoords,
        rotation = safeRotation
    }

    -- Broadcast to clients within streaming range
    TriggerClientEvent("nyx:inventory:client:dropCreated", -1, dropId, safeCoords, safeRotation)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Created world drop '%s' at (%.2f, %.2f, %.2f) h:%.1f^7",
            dropId, safeCoords.x, safeCoords.y, safeCoords.z, safeRotation.heading))
    end

    return dropId
end

-- Update spatial coordinates and orientation of an existing drop (zero-packet placement release)
function Nyx.Drops.Update(dropId, coords, rotation)
    local drop = Nyx.Drops[dropId]
    if not drop then return false, "DROP_NOT_FOUND" end

    local safeCoords = {
        x = math.floor((coords.x or drop.coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or drop.coords.y or 0.0) * 100) / 100,
        z = math.floor((coords.z or drop.coords.z or 70.0) * 100) / 100
    }
    local safeRotation = sanitizeRotation(rotation or drop.rotation)

    drop.coords = safeCoords
    drop.rotation = safeRotation

    local container = Nyx.Inventories[dropId]
    if container then
        container.coords = safeCoords
    end

    -- Update database record
    MySQL.query("UPDATE `nyx_inventories` SET `coords` = ?, `rotation` = ? WHERE `id` = ?", {
        json.encode(safeCoords),
        json.encode(safeRotation),
        dropId
    })

    -- Broadcast position update to all clients
    TriggerClientEvent("nyx:inventory:client:dropMoved", -1, dropId, safeCoords, safeRotation)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Moved world drop '%s' to (%.2f, %.2f, %.2f) h:%.1f^7",
            dropId, safeCoords.x, safeCoords.y, safeCoords.z, safeRotation.heading))
    end

    return true
end

-- Delete empty ground drop from world and storage
function Nyx.Drops.Remove(dropId)
    local drop = Nyx.Drops[dropId]
    if not drop then return end

    Nyx.Drops[dropId] = nil
    Nyx.Inventories[dropId] = nil
    Nyx.DirtyInventories[dropId] = nil

    MySQL.query("DELETE FROM `nyx_inventories` WHERE `id` = ?", { dropId })

    TriggerClientEvent("nyx:inventory:client:dropRemoved", -1, dropId)

    if Config.Debug then
        print(string.format("^3[Nyx:Drops] Removed empty ground drop '%s'^7", dropId))
    end
end

-- Check and cleanup drop container if empty
function Nyx.Drops.CheckCleanup(dropId)
    local container = Nyx.Inventories[dropId]
    if not container or container.type ~= "drop" then return end

    local hasItems = false
    for _, item in pairs(container.items) do
        if item then
            hasItems = true
            break
        end
    end

    if not hasItems then
        Nyx.Drops.Remove(dropId)
    end
end

-- Synchronize active drops to connecting or streaming clients
RegisterNetEvent("nyx:inventory:server:requestDrops", function()
    local src = source
    local dropList = {}
    for id, data in pairs(Nyx.Drops) do
        dropList[#dropList + 1] = data
    end
    TriggerClientEvent("nyx:inventory:client:syncDrops", src, dropList)
end)

-- Bootstrap and recover existing world drops from database on resource boot
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(100)
    end

    local rows = MySQL.query.await("SELECT `id`, `coords`, `rotation` FROM `nyx_inventories` WHERE `type` = 'drop'")
    if rows then
        for _, row in ipairs(rows) do
            if row.coords then
                local okCoords, parsedCoords = pcall(json.decode, row.coords)
                local okRot, parsedRot = pcall(json.decode, row.rotation or "{}")

                if okCoords and parsedCoords and parsedCoords.x and parsedCoords.y and parsedCoords.z then
                    Nyx.Drops[row.id] = {
                        id = row.id,
                        coords = parsedCoords,
                        rotation = (okRot and parsedRot and parsedRot.heading) and parsedRot or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
                    }
                    -- Preload container
                    Nyx.Inventory.Get(row.id)
                end
            end
        end
        print(string.format("^2[Nyx:Drops] Recovered %d persistent world drops from database.^7", #rows))
    end
end)
