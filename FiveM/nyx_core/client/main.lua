--[[
    Nyxframework: nyx_core
    File: client/main.lua
    Description: Client runtime core, local cache, and zero-busywait event handlers.
]]

Nyx = Nyx or {}
Nyx.Client = Nyx.Client or {}

Nyx.Client.IsLoaded = false
Nyx.Client.PlayerData = {
    citizenId = nil,
    data = {},
    wallets = {},
    metadata = {},
    position = {}
}

-- Initial handshake when player spawns into game world
CreateThread(function()
    -- Wait until game engine finishes initial session load
    while not NetworkIsSessionStarted() do
        Wait(50)
    end

    -- Notify server to isolate client in Virtual Bucket (1000 + source)
    TriggerServerEvent("nyx:core:client:joined")
    if Config.Debug then
        print("^2[Nyx:Client] Handshake emitted to server. Awaiting character selection...^7")
    end
end)

-- Character Load Sync Event
RegisterNetEvent("nyx:core:client:playerLoaded", function(characterPayload)
    Nyx.Client.PlayerData = characterPayload
    Nyx.Client.IsLoaded = true

    if Config.Debug then
        print(string.format("^2[Nyx:Client] Player loaded as Citizen %s^7", characterPayload.citizenId))
    end

    -- Forward event to other client modules
    TriggerEvent("nyx:core:client:onCharacterLoaded", characterPayload)

    -- Trigger local spawn sequence if position provided
    if characterPayload.position then
        Nyx.Spawn.Execute(characterPayload.position)
    end
end)

-- Real-time Wallet State Sync
RegisterNetEvent("nyx:core:client:walletUpdated", function(walletType, newBalance, delta, reason)
    if not Nyx.Client.PlayerData.wallets then
        Nyx.Client.PlayerData.wallets = {}
    end
    Nyx.Client.PlayerData.wallets[walletType] = newBalance

    TriggerEvent("nyx:core:client:onWalletChanged", walletType, newBalance, delta, reason)
end)

-- Real-time Metadata State Sync
RegisterNetEvent("nyx:core:client:metadataUpdated", function(key, value)
    if not Nyx.Client.PlayerData.metadata then
        Nyx.Client.PlayerData.metadata = {}
    end
    Nyx.Client.PlayerData.metadata[key] = value

    TriggerEvent("nyx:core:client:onMetadataChanged", key, value)
end)
