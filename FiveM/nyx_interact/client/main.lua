--[[
    Nyxframework: nyx_interact
    File: client/main.lua
    Description: Keymapping hooks, default world targets, and interaction selection dispatcher.
]]

Nyx = Nyx or {}
Nyx.Interact = Nyx.Interact or {}

-- 1. Key Mapping Hooks (+nyx_target and -nyx_target)
RegisterCommand(Config.ActivationCommand or "+nyx_target", function()
    if IsPauseMenuActive() or IsPlayerDead(PlayerPedId()) then return end

    Nyx.Interact.IsActive = true
    SetCursorLocation(0.5, 0.5)

    if exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:Send("interact", "ACTIVATE", {
            active = true
        })
    end
end, false)

RegisterCommand(Config.DeactivationCommand or "-nyx_target", function()
    Nyx.Interact.IsActive = false
    Nyx.Interact.HasAudibleTarget = false
    Nyx.Interact.CurrentTarget = nil

    if exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:Send("interact", "DEACTIVATE", {
            active = false
        })
    end
end, false)

RegisterKeyMapping(Config.ActivationCommand or "+nyx_target", "Activate Eye Target", "keyboard", Config.ActivationKey or "LMENU")

-- 2. Option Selection Handler (Dispatched from nyx_ui NUI callback)
RegisterNetEvent("nyx:interact:client:triggerOption", function(optionData)
    if not optionData then return end

    if optionData.event then
        TriggerEvent(optionData.event, optionData.args, optionData.entity, optionData.netId)
    elseif optionData.serverEvent then
        TriggerServerEvent(optionData.serverEvent, optionData.args, optionData.entity, optionData.netId)
    end
end)

-- 3. Register Default Core Framework Targets
CreateThread(function()
    Wait(1000)

    -- A. Freight Pallets (nyx_logistics)
    Nyx.Interact.AddTargetModel({ `prop_boxpile_06a`, `prop_pallet_01a` }, {
        options = {
            {
                icon = "fa-solid fa-dolly",
                label = "Move Pallet",
                event = "nyx:logistics:client:movePallet",
                canInteract = function(entity, dist)
                    return dist < 3.0 and not IsPedInAnyVehicle(PlayerPedId(), true)
                end
            },
            {
                icon = "fa-solid fa-box-open",
                label = "Inspect Freight",
                event = "nyx:inventory:client:openPallet",
                canInteract = function(entity, dist)
                    return dist < 2.5
                end
            }
        },
        distance = 3.0
    })

    -- B. World ATMs (nyx_treasury)
    Nyx.Interact.AddTargetModel({ `prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm` }, {
        options = {
            {
                icon = "fa-solid fa-credit-card",
                label = "Access ATM",
                event = "nyx:treasury:client:openAtm",
                canInteract = function(entity, dist)
                    return dist < 1.8
                end
            }
        },
        distance = 1.8
    })

    -- C. Vehicle Bones (nyx_vehicles & nyx_inventory)
    Nyx.Interact.AddTargetBone({ "boot", "trunk" }, {
        options = {
            {
                icon = "fa-solid fa-box-archive",
                label = "Open Trunk",
                event = "nyx:vehicles:client:openTrunk",
                canInteract = function(entity, dist)
                    return dist < 2.2 and GetVehicleDoorLockStatus(entity) <= 1
                end
            }
        },
        distance = 2.2
    })

    Nyx.Interact.AddTargetBone({ "bonnet" }, {
        options = {
            {
                icon = "fa-solid fa-wrench",
                label = "Inspect Engine / Repair",
                event = "nyx:vehicles:client:repairAtHood",
                canInteract = function(entity, dist)
                    return dist < 2.0
                end
            }
        },
        distance = 2.0
    })
end)
