--[[
    Nyxframework: nyx_core
    File: client/movement.lua
    Description: Dynamic inventory weight penalty enforcement on player ped locomotion,
                 sprint/jump control inhibition, and stamina degradation.
]]

Nyx = Nyx or {}
Nyx.Movement = Nyx.Movement or {}

local WeightState = {
    current = 0,
    max = 30000,
    ratio = 0.0
}

local CurrentTier = "normal"
local CurrentTierData = (Config.WeightPenalties and Config.WeightPenalties.tiers and Config.WeightPenalties.tiers.normal) or {
    moveRate = 1.0,
    sprintAllowed = true,
    jumpAllowed = true,
    climbAllowed = true,
    staminaDrainMult = 1.0,
    label = "NORMAL"
}
local IsOverridden = false

-- Determine weight penalty tier based on ratio
function Nyx.Movement.CalculateTier(ratio)
    local cfg = Config.WeightPenalties
    if not cfg or not cfg.enabled or not cfg.tiers then
        return "normal", {
            moveRate = 1.0,
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.0,
            label = "NORMAL"
        }
    end

    local tiers = cfg.tiers
    if tiers.critical and ratio >= tiers.critical.minRatio then
        return "critical", tiers.critical
    elseif tiers.overburdened and ratio >= tiers.overburdened.minRatio then
        return "overburdened", tiers.overburdened
    elseif tiers.heavy and ratio >= tiers.heavy.minRatio then
        return "heavy", tiers.heavy
    elseif tiers.encumbered and ratio >= tiers.encumbered.minRatio then
        return "encumbered", tiers.encumbered
    else
        return "normal", tiers.normal
    end
end

-- Update weight state and recompute penalties
function Nyx.Movement.SetWeight(data)
    if not data then return end

    WeightState.current = math.max(0, tonumber(data.current) or 0)
    WeightState.max = math.max(1, tonumber(data.max) or 30000)
    WeightState.ratio = WeightState.current / WeightState.max

    local newTierKey, newTierData = Nyx.Movement.CalculateTier(WeightState.ratio)
    local oldTier = CurrentTier

    CurrentTier = newTierKey
    CurrentTierData = newTierData

    -- Update state bags for external consumers (e.g., UI HUD)
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("weightRatio", WeightState.ratio, false)
        LocalPlayer.state:set("weightTier", CurrentTierData.label, false)
        LocalPlayer.state:set("moveRateOverride", CurrentTierData.moveRate, false)
    end

    if oldTier ~= newTierKey then
        TriggerEvent("nyx:core:client:onWeightPenaltyChanged", newTierKey, CurrentTierData.moveRate, WeightState.ratio, oldTier)
        if Config.Debug then
            print(string.format("^3[Nyx:Movement]^7 Weight tier shifted from %s -> %s (Ratio: %.2f, MoveRate: %.2f)",
                oldTier, newTierKey, WeightState.ratio, CurrentTierData.moveRate))
        end
    end
end

-- Event Listeners for Weight Synchronization
RegisterNetEvent("nyx:core:client:updateWeight", function(data)
    Nyx.Movement.SetWeight(data)
end)

RegisterNetEvent("nyx:core:client:playerLoaded", function(payload)
    if payload and payload.metadata and payload.metadata.inventory_weight then
        Nyx.Movement.SetWeight(payload.metadata.inventory_weight)
    end
end)

RegisterNetEvent("nyx:core:client:onMetadataChanged", function(key, value)
    if key == "inventory_weight" and type(value) == "table" then
        Nyx.Movement.SetWeight(value)
    end
end)

-- Main Frame Loop: Enforce Movement Rate Override & Control Locks
CreateThread(function()
    while true do
        local playerPed = PlayerPedId()

        if not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then
            Wait(500)
        else
            local inVehicle = IsPedInAnyVehicle(playerPed, false)

            if inVehicle then
                if IsOverridden then
                    SetPedMoveRateOverride(playerPed, 1.0)
                    IsOverridden = false
                end
                Wait(500)
            else
                if CurrentTier == "normal" then
                    if IsOverridden then
                        SetPedMoveRateOverride(playerPed, 1.0)
                        IsOverridden = false
                    end
                    Wait(300) -- Zero busywait when unencumbered
                else
                    -- Enforce frame-by-frame locomotion constraints
                    IsOverridden = true
                    SetPedMoveRateOverride(playerPed, CurrentTierData.moveRate)

                    -- Control Lock: Sprint
                    if not CurrentTierData.sprintAllowed then
                        DisableControlAction(0, 21, true) -- INPUT_SPRINT
                        DisableControlAction(1, 21, true)
                        DisableControlAction(2, 21, true)
                    end

                    -- Control Lock: Jump
                    if not CurrentTierData.jumpAllowed then
                        DisableControlAction(0, 22, true) -- INPUT_JUMP
                        DisableControlAction(1, 22, true)
                        DisableControlAction(2, 22, true)
                    end

                    -- Control Lock: Mantle / Climb
                    if CurrentTierData.climbAllowed == false then
                        DisableControlAction(0, 44, true) -- INPUT_COVER (vault/climb)
                        DisableControlAction(1, 44, true)
                        DisableControlAction(2, 44, true)
                    end

                    Wait(0)
                end
            end
        end
    end
end)

-- Stamina & Fatigue Processing Thread
CreateThread(function()
    local interval = (Config.WeightPenalties and Config.WeightPenalties.staminaTickIntervalMs) or 250

    while true do
        Wait(interval)

        local playerPed = PlayerPedId()
        if DoesEntityExist(playerPed) and not IsEntityDead(playerPed) and not IsPedInAnyVehicle(playerPed, false) then
            if CurrentTierData and CurrentTierData.staminaDrainMult and CurrentTierData.staminaDrainMult > 1.0 then
                local isSprinting = IsPedSprinting(playerPed)
                local isRunning = IsPedRunning(playerPed)

                if isSprinting then
                    local extraDrain = (CurrentTierData.staminaDrainMult - 1.0) * 1.5
                    RestorePlayerStamina(PlayerId(), -extraDrain)
                elseif isRunning and CurrentTierData.staminaDrainMult >= 2.0 then
                    RestorePlayerStamina(PlayerId(), -0.75)
                end

                if CurrentTierData.cameraShake and (isSprinting or isRunning or IsPedWalking(playerPed)) then
                    ShakeGameplayCam("ROAD_VIBRATION_SHAKE", 0.10)
                end
            end
        end
    end
end)

-- Public Client Exports
exports("GetMovementPenalty", function()
    return {
        tier = CurrentTierData.label,
        tierKey = CurrentTier,
        moveRate = CurrentTierData.moveRate,
        current = WeightState.current,
        max = WeightState.max,
        ratio = WeightState.ratio,
        sprintAllowed = CurrentTierData.sprintAllowed,
        jumpAllowed = CurrentTierData.jumpAllowed,
        climbAllowed = CurrentTierData.climbAllowed
    }
end)

exports("GetWeightRatio", function()
    return WeightState.ratio
end)

exports("IsOverweight", function()
    return WeightState.ratio > 1.0
end)

exports("IsEncumbered", function()
    local threshold = (Config.WeightPenalties and Config.WeightPenalties.tiers and Config.WeightPenalties.tiers.normal and Config.WeightPenalties.tiers.normal.maxRatio) or 0.70
    return WeightState.ratio > threshold
end)
