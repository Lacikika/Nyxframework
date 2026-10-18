--[[
    Nyxframework: nyx_treasury / nyx_factions
    File: shared/cash_transit.lua
    Description: Pure Lua 5.4 domain engine for commercial store cash transit,
                 exact zero-cent split conservation (Delta = 0.00), excess accumulation
                 threshold evaluations, vault deposits, and criminal breach forensics.
]]

Nyx = Nyx or {}
Nyx.CashTransit = Nyx.CashTransit or {}

-- 1. Statutory Constants & Policy Parameters
Nyx.CashTransit.DefaultTransitThreshold = 10000.00  -- When register clean cash reaches $10k, transit recommended
Nyx.CashTransit.MinBoxAmount = 1000.00              -- Minimum cash box parcel size
Nyx.CashTransit.MaxBoxAmount = 250000.00            -- Maximum cash transit capacity per armored box
Nyx.CashTransit.TillFloatFloor = 1000.00            -- Recommended operational cash left in store till
Nyx.CashTransit.StandardDepositFeePct = 1.00        -- 1.00% handling fee to municipal treasury
Nyx.CashTransit.StandardCourierRewardPct = 2.00     -- 2.00% payout to CIT courier/escort guard

-- 2. Mechanical & Forensic Profiles for Breach Tools
Nyx.CashTransit.BreachTools = {
    ['tool_angle_grinder'] = {
        name = 'tool_angle_grinder',
        label = 'Angle Grinder',
        baseChance = 0.65,
        durabilityLoss = 25.0,
        dyeRisk = 0.40,
        noiseRadius = 25.0,
        timeRequiredMs = 8000
    },
    ['thermite_charge'] = {
        name = 'thermite_charge',
        label = 'Thermite Incendiary Charge',
        baseChance = 0.85,
        durabilityLoss = 100.0,
        dyeRisk = 0.70,
        noiseRadius = 35.0,
        timeRequiredMs = 6000
    },
    ['tool_crowbar'] = {
        name = 'tool_crowbar',
        label = 'Heavy Crowbar',
        baseChance = 0.30,
        durabilityLoss = 35.0,
        dyeRisk = 0.20,
        noiseRadius = 20.0,
        timeRequiredMs = 10000
    }
}

-- 3. Double-Entry Transit Split Calculator (Strict Zero-Cent Conservation Law: Delta == 0.00)
function Nyx.CashTransit.CalculateTransitSplit(grossAmount, depositFeePct, courierRewardPct)
    grossAmount = tonumber(grossAmount) or 0.0
    local grossCents = math.floor(grossAmount * 100)
    if grossCents <= 0 then
        return {
            grossAmount = 0.00,
            municipalBankFee = 0.00,
            courierPayout = 0.00,
            netCorporateDeposit = 0.00
        }
    end

    depositFeePct = math.max(0.0, math.min(10.0, tonumber(depositFeePct) or Nyx.CashTransit.StandardDepositFeePct))
    courierRewardPct = math.max(0.0, math.min(10.0, tonumber(courierRewardPct) or Nyx.CashTransit.StandardCourierRewardPct))

    local feeCents = math.floor((grossCents * (depositFeePct / 100.0)))
    local rewardCents = math.floor((grossCents * (courierRewardPct / 100.0)))
    local netCents = grossCents - (feeCents + rewardCents)

    local gross = grossCents / 100.0
    local fee = feeCents / 100.0
    local reward = rewardCents / 100.0
    local net = netCents / 100.0

    return {
        grossAmount = gross,
        municipalBankFee = fee,
        courierPayout = reward,
        netCorporateDeposit = net
    }
end

-- 4. Evaluate Register Excess Cash Transit Need
function Nyx.CashTransit.EvaluateRegisterTransitNeed(register)
    if not register or tonumber(register.is_active or 1) == 0 then
        return false, "REGISTER_INACTIVE"
    end

    if tonumber(register.is_frozen or 0) == 1 then
        return false, "REGISTER_FROZEN"
    end

    if register.pending_transit_box_id and tostring(register.pending_transit_box_id) ~= "" and register.pending_transit_box_id ~= "NULL" then
        return false, "TRANSIT_ALREADY_PENDING"
    end

    local cleanCash = tonumber(register.clean_cash_balance) or 0.0
    local threshold = tonumber(register.transit_threshold) or Nyx.CashTransit.DefaultTransitThreshold

    if cleanCash < threshold then
        return false, "BELOW_TRANSIT_THRESHOLD"
    end

    local suggestedBox = cleanCash - Nyx.CashTransit.TillFloatFloor
    if suggestedBox < Nyx.CashTransit.MinBoxAmount then
        suggestedBox = cleanCash
    end

    suggestedBox = math.min(Nyx.CashTransit.MaxBoxAmount, math.floor(suggestedBox * 100) / 100)

    return true, {
        registerId = register.register_id,
        factionId = register.faction_id,
        cleanCashBalance = cleanCash,
        threshold = threshold,
        suggestedBoxAmount = suggestedBox
    }
end

-- 5. Validate Armored Cash Box Creation Request
function Nyx.CashTransit.ValidateBoxCreation(register, requestAmount, citizenId)
    if not register or tonumber(register.is_active or 1) == 0 then
        return false, "REGISTER_INACTIVE"
    end

    if tonumber(register.is_frozen or 0) == 1 then
        return false, "REGISTER_FROZEN"
    end

    if not citizenId or citizenId == "" then
        return false, "INVALID_CITIZEN_ID"
    end

    local amt = tonumber(requestAmount) or 0.0
    amt = math.floor(amt * 100) / 100

    if amt < Nyx.CashTransit.MinBoxAmount then
        return false, "AMOUNT_BELOW_MINIMUM"
    end

    if amt > Nyx.CashTransit.MaxBoxAmount then
        return false, "AMOUNT_EXCEEDS_MAXIMUM"
    end

    local cleanCash = tonumber(register.clean_cash_balance) or 0.0
    if amt > cleanCash then
        return false, "INSUFFICIENT_REGISTER_CASH"
    end

    return true, amt
end

-- 6. Validate Municipal Bank Vault Deposit Request
function Nyx.CashTransit.ValidateVaultDeposit(boxData, vaultData, citizenId)
    if not vaultData or tonumber(vaultData.is_active or 1) == 0 then
        return false, "VAULT_INACTIVE"
    end

    if not boxData then
        return false, "BOX_NOT_FOUND"
    end

    if not citizenId or citizenId == "" then
        return false, "INVALID_CITIZEN_ID"
    end

    if boxData.status == "deposited" then
        return false, "BOX_ALREADY_DEPOSITED"
    end

    if boxData.tamper_state == "breached" then
        return false, "BOX_ALREADY_BREACHED"
    end

    if boxData.status ~= "staged" and boxData.status ~= "in_transit" then
        return false, "INVALID_BOX_STATUS"
    end

    return true, "OK"
end

-- 7. Calculate Criminal Breach Attempt Outcome
function Nyx.CashTransit.CalculateBreachOutcome(toolName, userRoll, dyeRoll, hasGloves)
    local prof = Nyx.CashTransit.BreachTools[toolName]
    if not prof then
        return false, "UNKNOWN_TOOL"
    end

    local roll = tonumber(userRoll) or math.random()
    local dRoll = tonumber(dyeRoll) or math.random()

    local success = (roll <= prof.baseChance)
    local dyeTriggered = (dRoll <= prof.dyeRisk)
    local fingerprintLeft = not (hasGloves == true)

    return true, {
        success = success,
        dyeTriggered = dyeTriggered,
        fingerprintLeft = fingerprintLeft,
        noiseRadius = prof.noiseRadius,
        durabilityLoss = prof.durabilityLoss
    }
end

-- 8. Unique Serial and UUID Generators
function Nyx.CashTransit.GenerateBoxUuid()
    return string.format("BOX-CIT-%06d", math.random(100000, 999999))
end

function Nyx.CashTransit.GenerateSealSerial()
    return string.format("SEAL-CIT-%07d", math.random(1000000, 9999999))
end

function Nyx.CashTransit.GenerateManifestUuid()
    return string.format("MNF-CIT-%06d", math.random(100000, 999999))
end

-- 9. Zero-Trust Payload Sanitizers
function Nyx.CashTransit.ValidateCreationPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local regId = tostring(payload.registerId or ""):gsub("^%s*(.-)%s*$", "%1")
    if #regId < 3 then
        return false, "INVALID_REGISTER_ID"
    end

    local amt = tonumber(payload.amount)
    if not amt or amt <= 0.0 then
        return false, "INVALID_AMOUNT"
    end

    return true, {
        registerId = regId,
        amount = math.floor(amt * 100) / 100,
        destinationVault = payload.destinationVault or "vault:pacific_standard"
    }
end

function Nyx.CashTransit.ValidateDepositPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local boxUuid = tostring(payload.boxUuid or ""):gsub("^%s*(.-)%s*$", "%1")
    if #boxUuid < 6 then
        return false, "INVALID_BOX_UUID"
    end

    local vaultId = tostring(payload.vaultId or "vault:pacific_standard"):gsub("^%s*(.-)%s*$", "%1")
    if #vaultId < 3 then
        return false, "INVALID_VAULT_ID"
    end

    return true, {
        boxUuid = boxUuid,
        vaultId = vaultId
    }
end

-- 10. Display Badges & Formatting Helpers
function Nyx.CashTransit.FormatBoxStatusBadge(status, tamperState)
    status = string.upper(tostring(status or "UNKNOWN"))
    tamperState = string.upper(tostring(tamperState or "SEALED"))

    if tamperState == "BREACHED" then
        return "^1[BREACHED] " .. status .. "^7"
    elseif tamperState == "TAMPERED" then
        return "^3[TAMPERED] " .. status .. "^7"
    elseif status == "DEPOSITED" then
        return "^2[DEPOSITED] VAULT SETTLED^7"
    elseif status == "IN_TRANSIT" then
        return "^5[SEALED] IN TRANSIT^7"
    else
        return "^6[" .. tamperState .. "] " .. status .. "^7"
    end
end

function Nyx.CashTransit.FormatCurrency(amount)
    local val = tonumber(amount) or 0.0
    return string.format("$%.2f", val)
end
