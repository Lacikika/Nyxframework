--[[
    Nyxframework: nyx_ui
    File: client/hud.lua
    Description: Player vital telemetry synchronizer (health, armor, stamina, cash, fuel, speed).
]]

Nyx = Nyx or {}
Nyx.UI = Nyx.UI or {}
Nyx.UI.Hud = {}

Nyx.UI.Hud.LastPayload = {}

CreateThread(function()
    while true do
        if not Config.Hud.Enabled then
            Wait(1000)
        else
            local isPaused = IsPauseMenuActive()
            if isPaused and Config.Hud.HideInPauseMenu then
                Nyx.UI.Send("hud", "SET_VISIBILITY", { visible = false })
                Wait(500)
            else
                local playerPed = PlayerPedId()
                local playerId = PlayerId()

                -- Vitals calculation
                local maxHealth = GetEntityMaxHealth(playerPed)
                local currentHealth = GetEntityHealth(playerPed)
                local healthPct = math.max(0, math.min(100, math.floor(((currentHealth - 100) / math.max(1, maxHealth - 100)) * 100)))
                local armorPct = math.max(0, math.min(100, GetPedArmour(playerPed)))
                local staminaPct = math.max(0, math.min(100, math.floor(100 - GetPlayerSprintStaminaRemaining(playerId))))
                local isUnderwater = IsPedSwimmingUnderWater(playerPed)
                local oxygenPct = isUnderwater and math.max(0, math.min(100, math.floor(GetPlayerUnderwaterTimeRemaining(playerId) * 10))) or 100

                -- State Bag Integration for Hunger, Thirst, Voice Proximity
                local hunger = LocalPlayer.state.hunger or 100
                local thirst = LocalPlayer.state.thirst or 100
                local voiceRange = LocalPlayer.state.proximity or 2

                -- Vehicle Telemetry
                local inVehicle = IsPedInAnyVehicle(playerPed, false)
                local speedMph = 0
                local fuelLevel = 100
                local gear = 0
                local rpm = 0.0
                local engineHealth = 1000.0

                if inVehicle then
                    local veh = GetVehiclePedIsIn(playerPed, false)
                    speedMph = math.floor(GetEntitySpeed(veh) * 2.236936) -- m/s to mph
                    gear = GetVehicleCurrentGear(veh)
                    rpm = GetVehicleCurrentRpm(veh)
                    engineHealth = GetVehicleEngineHealth(veh)

                    -- Integrate with nyx_vehicles fuel if available
                    if exports['nyx_vehicles'] and exports['nyx_vehicles'].GetActiveVehicleFuel then
                        fuelLevel = exports['nyx_vehicles']:GetActiveVehicleFuel() or 100
                    else
                        fuelLevel = math.floor(GetVehicleFuelLevel(veh))
                    end
                end

                -- Financial telemetry from nyx_core session cache
                local cashBalance = 0
                local bankBalance = 0
                if exports['nyx_core'] and exports['nyx_core'].GetPlayerData then
                    local pData = exports['nyx_core']:GetPlayerData()
                    if pData and pData.money then
                        cashBalance = pData.money.cash or 0
                        bankBalance = pData.money.bank or 0
                    end
                end

                local payload = {
                    visible = true,
                    vitals = {
                        health = healthPct,
                        armor = armorPct,
                        hunger = hunger,
                        thirst = thirst,
                        stamina = staminaPct,
                        oxygen = oxygenPct,
                        voiceRange = voiceRange,
                        isUnderwater = isUnderwater,
                        isDead = IsPlayerDead(playerPed)
                    },
                    vehicle = {
                        inVehicle = inVehicle,
                        speed = speedMph,
                        rpm = rpm,
                        engineHealth = engineHealth,
                        fuel = fuelLevel,
                        gear = gear
                    },
                    finances = {
                        cash = cashBalance,
                        bank = bankBalance
                    }
                }

                Nyx.UI.Send("hud", "UPDATE_STATUS", payload)
                Wait(Config.Hud.UpdateIntervalMs or 500)
            end
        end
    end
end)
