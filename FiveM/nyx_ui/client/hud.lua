--[[
    Nyxframework: nyx_ui
    File: client/hud.lua
    Description: Player vital telemetry synchronizer (health, armor, stamina, cash, fuel, speed).
]]

Nyx = Nyx or {}
Nyx.UI = Nyx.UI or {}
Nyx.UI.Hud = {}

Nyx.UI.Hud.LastPayload = {}
Nyx.UI.Hud.WasVisible = nil

local function AreVitalsEqual(a, b)
    if not a or not b then return false end
    return a.health == b.health and
           a.armor == b.armor and
           a.hunger == b.hunger and
           a.thirst == b.thirst and
           a.stamina == b.stamina and
           a.oxygen == b.oxygen and
           a.voiceRange == b.voiceRange and
           a.isUnderwater == b.isUnderwater and
           a.isDead == b.isDead
end

local function AreVehiclesEqual(a, b)
    if not a or not b then return false end
    if a.inVehicle ~= b.inVehicle then return false end
    if not a.inVehicle then return true end
    return a.speed == b.speed and
           a.gear == b.gear and
           a.fuel == b.fuel and
           a.engineHealth == b.engineHealth and
           math.abs((a.rpm or 0) - (b.rpm or 0)) < 0.05
end

local function AreFinancesEqual(a, b)
    if not a or not b then return false end
    return a.cash == b.cash and a.bank == b.bank
end

local function HasHudDelta(curr, prev)
    if not prev or not prev.vitals then return true end
    if not AreVitalsEqual(curr.vitals, prev.vitals) then return true end
    if not AreVehiclesEqual(curr.vehicle, prev.vehicle) then return true end
    if not AreFinancesEqual(curr.finances, prev.finances) then return true end
    return false
end

CreateThread(function()
    while true do
        if not Config.Hud.Enabled then
            Wait(1000)
        else
            -- Strict throttle: zero busy-wait, clamp polling interval to 100ms-250ms
            local pollInterval = math.max(100, math.min(250, Config.Hud.UpdateIntervalMs or 150))
            local isPaused = IsPauseMenuActive()

            if isPaused and Config.Hud.HideInPauseMenu then
                if Nyx.UI.Hud.WasVisible ~= false then
                    Nyx.UI.Hud.WasVisible = false
                    Nyx.UI.Send("hud", "SET_VISIBILITY", { visible = false })
                end
                Wait(300)
            else
                if Nyx.UI.Hud.WasVisible == false then
                    Nyx.UI.Hud.WasVisible = true
                    Nyx.UI.Send("hud", "SET_VISIBILITY", { visible = true })
                end

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
                    rpm = math.floor(GetVehicleCurrentRpm(veh) * 100) / 100 -- 2 decimal precision
                    engineHealth = math.floor(GetVehicleEngineHealth(veh))

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

                -- Enforce State Delta-Checking: only send NUI message when data changed
                if HasHudDelta(payload, Nyx.UI.Hud.LastPayload) then
                    Nyx.UI.Hud.LastPayload = payload
                    Nyx.UI.Send("hud", "UPDATE_STATUS", payload)
                end

                Wait(pollInterval)
            end
        end
    end
end)
