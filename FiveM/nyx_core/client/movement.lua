--[[
    Nyxframework: nyx_core
    File: client/movement.lua
    Description: Dynamic inventory weight penalty enforcement on player ped locomotion,
                 server-authoritative State Bag synchronization (no polling), sprint/jump
                 control inhibition, and heavy freight physics.
]]

Nyx = Nyx or {}
Nyx.Movement = Nyx.Movement or {}

local WeightState = {
    current = 0,
    max = (Config and Config.WeightPenalties and Config.WeightPenalties.defaultPlayerCapacity) or 60000,
    ratio = 0.0
}

local CurrentTier = "tier_0"
local CurrentTierData = (Config.WeightPenalties and Config.WeightPenalties.tiers and Config.WeightPenalties.tiers.tier_0) or {
    moveRate = 1.0,
    sprintAllowed = true,
    jumpAllowed = true,
    climbAllowed = true,
    staminaDrainMult = 1.0,
    label = "TIER_0"
}
local IsOverridden = false

-- Determine weight penalty tier based on ratio and freight status
function Nyx.Movement.CalculateTier(ratio, isHeavyFreight)
    if Nyx.Weights and Nyx.Weights.CalculateTier then
        return Nyx.Weights.CalculateTier(ratio, isHeavyFreight)
    end

    local cfg = Config.WeightPenalties
    if not cfg or not cfg.enabled or not cfg.tiers then
        return "tier_0", {
            moveRate = 1.0,
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.0,
            label = "TIER_0"
        }
    end

    local tiers = cfg.tiers
    if isHeavyFreight then
        return "tier_3", tiers.tier_3 or { moveRate = 0.65, sprintAllowed = false, jumpAllowed = false, climbAllowed = false, staminaDrainMult = 2.5, label = "TIER_3" }
    elseif ratio > ((tiers.tier_2 and tiers.tier_2.minRatio) or 0.95) then
        return "tier_2", tiers.tier_2 or tiers.overburdened
    elseif ratio > ((tiers.tier_1 and tiers.tier_1.minRatio) or 0.70) then
        return "tier_1", tiers.tier_1 or tiers.encumbered
    else
        return "tier_0", tiers.tier_0 or tiers.normal
    end
end

-- Synchronize state from server-authoritative State Bags (zero client polling)
local function applyStateBag(pState)
    if not pState then return end
    local tierLabel = pState.weightTier
    if tierLabel == nil then return end

    local tierKey = pState.weightTierKey or "tier_0"
    local moveRate = tonumber(pState.moveRateOverride) or 1.0
    local sprintAllowed = (pState.sprintAllowed ~= false)
    local jumpAllowed = (pState.jumpAllowed ~= false)
    local climbAllowed = (pState.climbAllowed ~= false)
    local isHeavy = (pState.isCarryingHeavyFreight == true)

    local oldTier = CurrentTier
    CurrentTier = tierKey
    CurrentTierData = {
        moveRate = moveRate,
        sprintAllowed = sprintAllowed,
        jumpAllowed = jumpAllowed,
        climbAllowed = climbAllowed,
        staminaDrainMult = (tierKey == "tier_3" and 2.50) or (tierKey == "tier_2" and 2.00) or (tierKey == "tier_1" and 1.30) or 1.0,
        label = tostring(tierLabel),
        isHeavyFreight = isHeavy
    }

    WeightState.current = tonumber(pState.weightCurrent) or WeightState.current
    WeightState.max = tonumber(pState.weightMax) or WeightState.max
    WeightState.ratio = tonumber(pState.weightRatio) or (WeightState.current / math.max(1, WeightState.max))

    if oldTier ~= CurrentTier then
        TriggerEvent("nyx:core:client:onWeightPenaltyChanged", CurrentTier, CurrentTierData.moveRate, WeightState.ratio, oldTier)
        if Config.Debug then
            print(string.format("^3[Nyx:Movement]^7 State Bag sync: Tier shifted %s -> %s (Ratio: %.2f, MoveRate: %.2f)",
                oldTier, CurrentTier, WeightState.ratio, CurrentTierData.moveRate))
        end
    end
end

-- State Bag Change Handler: Listens for server changes without any polling loop
if AddStateBagChangeHandler then
    AddStateBagChangeHandler("weightTier", nil, function(bagName, key, value, reserved, replicated)
        local plyServerId = GetPlayerServerId(PlayerId())
        if bagName == ("player:%s"):format(plyServerId) then
            if LocalPlayer and LocalPlayer.state then
                applyStateBag(LocalPlayer.state)
            end
        end
    end)

    AddStateBagChangeHandler("isCarryingHeavyFreight", nil, function(bagName, key, value, reserved, replicated)
        local plyServerId = GetPlayerServerId(PlayerId())
        if bagName == ("player:%s"):format(plyServerId) then
            if LocalPlayer and LocalPlayer.state then
                applyStateBag(LocalPlayer.state)
            end
        end
    end)
end

-- Update weight state and recompute penalties
function Nyx.Movement.SetWeight(data)
    if not data then return end

    local defaultMax = (Config.WeightPenalties and Config.WeightPenalties.defaultPlayerCapacity) or 60000
    WeightState.current = math.max(0, tonumber(data.current) or 0)
    WeightState.max = math.max(1, tonumber(data.max) or defaultMax)
    WeightState.ratio = WeightState.current / WeightState.max

    local isHeavy = (LocalPlayer and LocalPlayer.state and LocalPlayer.state.isCarryingHeavyFreight == true) or false
    local newTierKey, newTierData = Nyx.Movement.CalculateTier(WeightState.ratio, isHeavy)
    local oldTier = CurrentTier

    CurrentTier = newTierKey
    CurrentTierData = newTierData

    -- Update state bags for external consumers (e.g., UI HUD)
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set("weightRatio", WeightState.ratio, false)
        LocalPlayer.state:set("weightTier", CurrentTierData.label, false)
        LocalPlayer.state:set("weightTierKey", CurrentTier, false)
        LocalPlayer.state:set("moveRateOverride", CurrentTierData.moveRate, false)
        LocalPlayer.state:set("sprintAllowed", CurrentTierData.sprintAllowed, false)
        LocalPlayer.state:set("jumpAllowed", CurrentTierData.jumpAllowed, false)
        LocalPlayer.state:set("climbAllowed", CurrentTierData.climbAllowed, false)
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
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.weightTier then
        applyStateBag(LocalPlayer.state)
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
                local isUnencumbered = (CurrentTier == "tier_0" or CurrentTier == "normal")
                if isUnencumbered and not CurrentTierData.isHeavyFreight then
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
        climbAllowed = CurrentTierData.climbAllowed,
        isHeavyFreight = CurrentTierData.isHeavyFreight or (CurrentTier == "tier_3")
    }
end)

exports("GetWeightRatio", function()
    return WeightState.ratio
end)

exports("IsOverweight", function()
    return WeightState.ratio > 0.95
end)

exports("IsEncumbered", function()
    local threshold = (Config.WeightPenalties and Config.WeightPenalties.tiers and Config.WeightPenalties.tiers.tier_0 and Config.WeightPenalties.tiers.tier_0.maxRatio) or 0.70
    return WeightState.ratio > threshold
end)

exports("IsCarryingHeavyFreight", function()
    return CurrentTier == "tier_3" or CurrentTierData.isHeavyFreight == true or ((LocalPlayer and LocalPlayer.state and LocalPlayer.state.isCarryingHeavyFreight == true) or false)
end)
