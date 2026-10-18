--[[
    Nyxframework: nyx_inventory
    File: client/main.lua
    Description: Client inventory controller, NUI bridge, and keybind listeners.
]]

Nyx = Nyx or {}
Nyx.Inventory = Nyx.Inventory or {}

Nyx.Inventory.IsOpen = false
Nyx.Inventory.ActiveTargetInv = nil
Nyx.Inventory.Weight = {
    current = 0,
    max = 30000,
    ratio = 0.0
}

RegisterNetEvent("nyx:inventory:client:updateWeight", function(data)
    if data then
        Nyx.Inventory.Weight = {
            current = tonumber(data.current) or 0,
            max = tonumber(data.max) or 30000,
            ratio = tonumber(data.ratio) or 0.0
        }
    end
end)

-- Request ground drops synchronization upon spawn
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(100)
    end
    TriggerServerEvent("nyx:inventory:server:requestDrops")
end)

-- Open Inventory Interface
function Nyx.Inventory.Open(targetInvId)
    if Nyx.Inventory.IsOpen then return end

    CreateThread(function()
        local ok, data = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("inventory:openContainer", targetInvId)
        end)

        if not ok or not data then
            if Config.Debug then
                print("^1[Nyx:Inventory] Failed to open container: RPC rejected.^7")
            end
            return
        end

        Nyx.Inventory.IsOpen = true
        Nyx.Inventory.ActiveTargetInv = targetInvId

        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "OPEN_INVENTORY",
            player = data.player,
            target = data.target
        })
    end)
end

-- Close Inventory Interface
function Nyx.Inventory.Close()
    if not Nyx.Inventory.IsOpen then return end

    local target = Nyx.Inventory.ActiveTargetInv
    Nyx.Inventory.IsOpen = false
    Nyx.Inventory.ActiveTargetInv = nil

    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "CLOSE_INVENTORY"
    })

    if target then
        exports['nyx_core']:TriggerRPC("inventory:closeContainer", target)
    end
end

-- Keybind Registration: TAB or configured command
RegisterCommand(Config.OpenInventoryCommand or "inventory", function()
    if Nyx.Inventory.IsOpen then
        Nyx.Inventory.Close()
    else
        Nyx.Inventory.Open(nil)
    end
end, false)

RegisterKeyMapping(Config.OpenInventoryCommand or "inventory", "Open Inventory", "keyboard", Config.OpenInventoryKey or "TAB")

-- Real-time Delta Listener from Server
RegisterNetEvent("nyx:inventory:client:delta", function(invId, eventType, payload)
    if Nyx.Inventory.IsOpen then
        SendNUIMessage({
            action = "INVENTORY_DELTA",
            invId = invId,
            eventType = eventType,
            payload = payload
        })
    end
end)

-- Authoritative Weapon Equip Event
RegisterNetEvent("nyx:inventory:client:equipWeapon", function(weaponName, metadata)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weaponName)

    if HasPedGotWeapon(ped, weaponHash, false) then
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        RemoveWeaponFromPed(ped, weaponHash)
    else
        GiveWeaponToPed(ped, weaponHash, 0, false, true)
        SetCurrentPedWeapon(ped, weaponHash, true)
    end
end)

-- NUI Handlers
RegisterNUICallback("close", function(_, cb)
    Nyx.Inventory.Close()
    cb("ok")
end)

RegisterNUICallback("moveSlot", function(payload, cb)
    CreateThread(function()
        local result = exports['nyx_core']:TriggerRPCAwait("inventory:moveSlot", payload)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)

RegisterNUICallback("dropItem", function(payload, cb)
    CreateThread(function()
        local result = exports['nyx_core']:TriggerRPCAwait("inventory:dropItem", payload)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)

RegisterNUICallback("useItem", function(payload, cb)
    CreateThread(function()
        local result = exports['nyx_core']:TriggerRPCAwait("inventory:useItem", payload)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)
