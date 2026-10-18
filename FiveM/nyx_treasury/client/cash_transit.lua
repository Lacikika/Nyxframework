--[[
    Nyxframework: nyx_treasury
    File: client/cash_transit.lua
    Description: Client-side spatial interactions for municipal bank vaults,
                 armored cash transit box deposits, and criminal breaching mechanics.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}
Nyx.CashTransit = Nyx.CashTransit or {}

local bankVaults = {
    {
        vaultId = "vault:pacific_standard",
        label = "Pacific Standard Municipal Central Vault",
        coords = vector3(255.2, 217.4, 101.9)
    },
    {
        vaultId = "vault:blaine_county",
        label = "Blaine County Savings Vault",
        coords = vector3(-111.4, 6465.1, 31.6)
    },
    {
        vaultId = "vault:legion_square",
        label = "Legion Square Commercial Reserve Vault",
        coords = vector3(150.1, -1040.5, 29.4)
    }
}

-- 1. Register Third-Eye (LALT) Target at Bank Vault Locations
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for idx, vault in ipairs(bankVaults) do
        exports['nyx_interact']:AddTargetCoords("treasury_vault_" .. idx, vault.coords, 2.5, {
            options = {
                {
                    icon = "fa-solid fa-vault",
                    label = "Páncélozott Készpénzdoboz Leadása (Széf)",
                    event = "nyx:treasury:client:depositBox",
                    vaultId = vault.vaultId,
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                },
                {
                    icon = "fa-solid fa-file-invoice-dollar",
                    label = "Banki Széf Tranzakciós Napló",
                    event = "nyx:treasury:client:viewVaultStatus",
                    vaultId = vault.vaultId,
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                }
            },
            distance = 2.5
        })
    end
end)

-- 2. Client Deposit Event Handler
RegisterNetEvent("nyx:treasury:client:depositBox", function(data)
    local targetVaultId = (type(data) == "table" and data.vaultId) or "vault:pacific_standard"

    -- Find nearest vault if not passed
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    -- Play deposit animation
    RequestAnimDict("anim@heists@keycard@")
    while not HasAnimDictLoaded("anim@heists@keycard@") do
        Wait(10)
    end
    TaskPlayAnim(ped, "anim@heists@keycard@", "exit", 8.0, -8.0, 2000, 0, 0, false, false, false)

    -- Call server RPC
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("treasury:depositCashTransitBox", {
            boxUuid = "BOX-CIT-ACTIVE",
            vaultId = targetVaultId
        }, function(response)
            if response and response.success then
                PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
            else
                local err = (response and response.error) or "DEPOSIT_FAILED"
                TriggerEvent("nyx:core:notify", {
                    type = "error",
                    title = "Széf Hiba",
                    message = "A letét meghiúsult: " .. tostring(err)
                })
            end
        end)
    end
end)

-- 3. Player Chat Commands
RegisterCommand("depositcashbox", function(source, args, rawCommand)
    local vaultId = args[1] or "vault:pacific_standard"
    local boxUuid = args[2] or "BOX-CIT-ACTIVE"

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("treasury:depositCashTransitBox", {
            boxUuid = boxUuid,
            vaultId = vaultId
        }, function(response)
            if response and response.success then
                PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
            else
                TriggerEvent("nyx:core:notify", {
                    type = "error",
                    title = "Széf Hiba",
                    message = "Letét sikertelen: " .. tostring(response and response.error)
                })
            end
        end)
    end
end, false)

RegisterCommand("breachcashbox", function(source, args, rawCommand)
    local tool = args[1] or "tool_angle_grinder"

    local ped = PlayerPedId()
    RequestAnimDict("melee@crowbar@streamed_core")
    while not HasAnimDictLoaded("melee@crowbar@streamed_core") do
        Wait(10)
    end
    TaskPlayAnim(ped, "melee@crowbar@streamed_core", "car_turnaround", 8.0, -8.0, 5000, 1, 0, false, false, false)

    Wait(5000)
    ClearPedTasks(ped)

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("treasury:breachCashTransitBox", {
            toolName = tool
        }, function(response)
            if response and response.success then
                TriggerEvent("nyx:core:notify", {
                    type = "success",
                    title = "Feltörés Sikeres",
                    message = "A dobozt kinyitottad!"
                })
            else
                TriggerEvent("nyx:core:notify", {
                    type = "error",
                    title = "Feltörés Sikertelen",
                    message = "A dobozt nem sikerült kinyitni: " .. tostring(response and response.error)
                })
            end
        end)
    end
end, false)

-- 4. Client Public Exports
exports("DepositCashTransitBox", function(boxUuid, vaultId)
    TriggerEvent("nyx:treasury:client:depositBox", { boxUuid = boxUuid, vaultId = vaultId })
end)

exports("BreachCashTransitBox", function(toolName)
    ExecuteCommand("breachcashbox " .. (toolName or "tool_angle_grinder"))
end)
