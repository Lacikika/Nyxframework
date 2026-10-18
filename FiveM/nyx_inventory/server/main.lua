--[[
    Nyxframework: nyx_inventory
    File: server/main.lua
    Description: Inventory server lifecycle, player container binding, and shutdown persistence.
]]

Nyx = Nyx or {}

-- Initialize player inventory upon character selection / ready
AddEventHandler("nyx:core:playerReady", function(src, citizenId)
    local invId = string.format("char:%s:main", citizenId)
    local defaults = Config.Containers['player']

    CreateThread(function()
        local container = Nyx.Inventory.Get(invId, 'player')
        if container and Config.Debug then
            print(string.format("^2[Nyx:Inventory] Loaded player inventory '%s' for source %s (%d items)^7", invId, src, #container.items))
        end
    end)
end)

-- Player Disconnection Handling: Persist and Evict to eliminate memory leak
AddEventHandler("playerDropped", function()
    local src = source
    local player = exports['nyx_core']:GetPlayer(src)
    
    if player and player.citizenId then
        local invId = string.format("char:%s:main", player.citizenId)
        local container = Nyx.Inventories[invId]
        if container then
            -- Immediately persist container state
            if container.isDirty then
                container:save()
            end
            -- Evict from memory to prevent leak & unnecessary decay cycles
            Nyx.Inventories[invId] = nil
            Nyx.DirtyInventories[invId] = nil
            if Config.Debug then
                print(string.format("^3[Nyx:Inventory] Evicted disconnected player container '%s'^7", invId))
            end
        end
    end

    -- Remove from listeners across all containers
    for _, container in pairs(Nyx.Inventories) do
        if container then
            container:removeListener(src)
        end
    end
end)

-- Emergency Synchronous Flush on Resource Shutdown
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    print("^3[Nyx:Inventory] Resource stopping. Executing emergency container flush...^7")
    local count = 0
    for _, container in pairs(Nyx.DirtyInventories) do
        if container and container.isDirty then
            container:save()
            count = count + 1
        end
    end
    print(string.format("^2[Nyx:Inventory] Shutdown flush finished. %d modified containers persisted.^7", count))
end)
