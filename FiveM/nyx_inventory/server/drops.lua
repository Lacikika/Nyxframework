--[[
    Nyxframework: nyx_inventory
    File: server/drops.lua
    Description: Spatial grid ground drops manager with entity culling and persistence.
]]

Nyx = Nyx or {}
Nyx.Drops = {} -- [dropId] = { id = dropId, coords = { x, y, z }, invId = dropId }

-- Register and spawn a new physical ground drop container
function Nyx.Drops.Create(coords, itemData)
    local dropUuid = Nyx.RPC.GenerateNonce():sub(1, 8)
    local dropId = string.format("drop:%s", dropUuid)

    local safeCoords = {
        x = math.floor((coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or 0.0) * 100) / 100,
        z = math.floor(((coords.z or 70.0) + (Config.DropZOffset or -0.95)) * 100) / 100
    }

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

    Nyx.Drops[dropId] = {
        id = dropId,
        coords = safeCoords
    }

    -- Broadcast to clients within streaming range
    TriggerClientEvent("nyx:inventory:client:dropCreated", -1, dropId, safeCoords)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Created world drop '%s' at (%.2f, %.2f, %.2f)^7", dropId, safeCoords.x, safeCoords.y, safeCoords.z))
    end

    return dropId
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

    local rows = MySQL.query.await("SELECT `id`, `coords` FROM `nyx_inventories` WHERE `type` = 'drop'")
    if rows then
        for _, row in ipairs(rows) do
            if row.coords then
                local ok, parsed = pcall(json.decode, row.coords)
                if ok and parsed and parsed.x and parsed.y and parsed.z then
                    Nyx.Drops[row.id] = {
                        id = row.id,
                        coords = parsed
                    }
                    -- Preload container
                    Nyx.Inventory.Get(row.id)
                end
            end
        end
        print(string.format("^2[Nyx:Drops] Recovered %d persistent world drops from database.^7", #rows))
    end
end)
