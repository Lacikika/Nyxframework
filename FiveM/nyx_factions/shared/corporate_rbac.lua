--[[
    Nyxframework: nyx_factions
    File: shared/corporate_rbac.lua
    Description: Pure Lua 5.4 deterministic algorithms for corporate Role-Based Access Control (RBAC),
                 equity budget conservation, multi-sig escrow quorum & timelock evaluations,
                 and Collective Bargaining Agreement (CBA) contract validation.
]]

Nyx = Nyx or {}
Nyx.CorporateRBAC = Nyx.CorporateRBAC or {}

-- 1. Standard Permission Node Taxonomy
Nyx.CorporateRBAC.Taxonomy = {
    treasury = {
        "treasury:view_ledger",
        "treasury:deposit",
        "treasury:initiate_tx",
        "treasury:sign_tx",
        "treasury:freeze_vault",
        "treasury:distribute_dividends"
    },
    roster = {
        "roster:view",
        "roster:invite",
        "roster:promote",
        "roster:terminate",
        "roster:set_wage",
        "roster:set_equity"
    },
    fleet = {
        "fleet:view",
        "fleet:spawn",
        "fleet:store",
        "fleet:purchase"
    },
    inventory = {
        "inventory:view",
        "inventory:deposit",
        "inventory:withdraw",
        "inventory:manage_stashes"
    },
    cba = {
        "cba:view",
        "cba:propose",
        "cba:ratify",
        "cba:strike_action"
    }
}

-- 2. Granular Permission Evaluator with Wildcard Hierarchies
-- Supports root wildcard (*), category prefix wildcards (<cat>:*), and exact matches.
function Nyx.CorporateRBAC.EvaluatePermission(nodesList, requiredNode)
    if not nodesList or type(nodesList) ~= "table" or not requiredNode then
        return false
    end

    for _, node in ipairs(nodesList) do
        if type(node) == "string" then
            -- Exact match or global root wildcard
            if node == "*" or node == requiredNode then
                return true
            end

            -- Category prefix wildcard (e.g. 'treasury:*' matches 'treasury:sign_tx')
            if string.sub(node, -2) == ":*" then
                local prefix = string.sub(node, 1, -2) -- includes the trailing colon
                if string.sub(requiredNode, 1, #prefix) == prefix then
                    return true
                end
            end
        end
    end

    return false
end

-- 3. Equity Shares Budget Validator
-- Enforces total corporate equity conservation <= 100.00% with 2-decimal cent precision.
function Nyx.CorporateRBAC.ValidateEquityBudget(currentTotal, oldMemberEquity, newMemberEquity)
    currentTotal = math.max(0.0, math.floor((tonumber(currentTotal) or 0.0) * 100 + 0.5) / 100)
    oldMemberEquity = math.max(0.0, math.floor((tonumber(oldMemberEquity) or 0.0) * 100 + 0.5) / 100)
    newMemberEquity = math.max(0.0, math.floor((tonumber(newMemberEquity) or 0.0) * 100 + 0.5) / 100)

    if newMemberEquity < 0.0 or newMemberEquity > 100.0 then
        return false, currentTotal, "EQUITY_OUT_OF_BOUNDS_0_TO_100"
    end

    local adjustedTotal = math.floor((currentTotal - oldMemberEquity + newMemberEquity) * 100 + 0.5) / 100
    if adjustedTotal > 100.00 then
        return false, adjustedTotal, "EXCEEDS_MAXIMUM_EQUITY_100_PERCENT"
    end

    return true, adjustedTotal, nil
end

-- 4. Multi-Sig Escrow Quorum & Timelock Status Evaluator
-- Determines whether a multi-sig escrow withdrawal is awaiting signatures, timelocked, or ready for execution.
function Nyx.CorporateRBAC.EvaluateEscrowStatus(currentSignatures, requiredSignatures, timelockSeconds, initiatedAtUnix, currentUnix)
    currentSignatures = math.max(0, math.floor(tonumber(currentSignatures) or 0))
    requiredSignatures = math.max(1, math.floor(tonumber(requiredSignatures) or 2))
    timelockSeconds = math.max(0, math.floor(tonumber(timelockSeconds) or 0))
    initiatedAtUnix = math.max(0, math.floor(tonumber(initiatedAtUnix) or 0))
    currentUnix = math.max(0, math.floor(tonumber(currentUnix) or os.time()))

    if currentSignatures < requiredSignatures then
        return {
            status = "AWAITING_SIGNATURES",
            isExecutable = false,
            missingSignatures = requiredSignatures - currentSignatures,
            remainingTimelockSeconds = 0,
            currentSignatures = currentSignatures,
            requiredSignatures = requiredSignatures
        }
    end

    local elapsed = math.max(0, currentUnix - initiatedAtUnix)
    if timelockSeconds > 0 and elapsed < timelockSeconds then
        return {
            status = "TIMELOCKED",
            isExecutable = false,
            missingSignatures = 0,
            remainingTimelockSeconds = timelockSeconds - elapsed,
            currentSignatures = currentSignatures,
            requiredSignatures = requiredSignatures
        }
    end

    return {
        status = "READY_FOR_EXECUTION",
        isExecutable = true,
        missingSignatures = 0,
        remainingTimelockSeconds = 0,
        currentSignatures = currentSignatures,
        requiredSignatures = requiredSignatures
    }
end

-- 5. CBA Contract Parameters Validator
-- Sanitizes and validates contract builder terms: wage floor, overtime multiplier, hazard bonus.
function Nyx.CorporateRBAC.ValidateCBAParameters(title, wageFloor, overtimeMultiplier, hazardBonus, notes)
    if not title or type(title) ~= "string" or string.len(string.gsub(title, "^%s*(.-)%s*$", "%1")) < 3 then
        return false, nil, "INVALID_CBA_TITLE_MIN_3_CHARS"
    end

    local cleanTitle = string.sub(string.gsub(title, "^%s*(.-)%s*$", "%1"), 1, 64)
    local wage = tonumber(wageFloor) or 35.00
    if wage < 15.00 or wage > 500.00 then
        return false, nil, "WAGE_FLOOR_OUT_OF_BOUNDS_15_TO_500"
    end
    wage = math.floor(wage * 100 + 0.5) / 100

    local ot = tonumber(overtimeMultiplier) or 1.50
    if ot < 1.00 or ot > 3.00 then
        return false, nil, "OVERTIME_MULTIPLIER_OUT_OF_BOUNDS_1_TO_3"
    end
    ot = math.floor(ot * 100 + 0.5) / 100

    local hazard = tonumber(hazardBonus) or 0.00
    if hazard < 0.00 or hazard > 200.00 then
        return false, nil, "HAZARD_BONUS_OUT_OF_BOUNDS_0_TO_200"
    end
    hazard = math.floor(hazard * 100 + 0.5) / 100

    local cleanNotes = ""
    if notes and type(notes) == "string" then
        cleanNotes = string.sub(string.gsub(notes, "^%s*(.-)%s*$", "%1"), 1, 255)
    end

    return true, {
        title = cleanTitle,
        wageFloor = wage,
        overtimeMultiplier = ot,
        hazardBonus = hazard,
        notes = cleanNotes
    }, nil
end

-- 6. Role Presets Helper
function Nyx.CorporateRBAC.GetStandardRoleTemplates()
    return {
        {
            roleTitle = "Chief Executive Officer",
            permissionNodes = { "*" },
            suggestedWage = 0.00,
            isExecutive = true
        },
        {
            roleTitle = "Chief Financial Officer",
            permissionNodes = { "treasury:*", "roster:view", "fleet:view", "inventory:view", "cba:view" },
            suggestedWage = 75.00,
            isExecutive = true
        },
        {
            roleTitle = "Operations Manager",
            permissionNodes = { "treasury:view_ledger", "treasury:deposit", "roster:view", "roster:invite", "fleet:*", "inventory:*", "cba:view" },
            suggestedWage = 55.00,
            isExecutive = false
        },
        {
            roleTitle = "Senior Associate",
            permissionNodes = { "treasury:view_ledger", "fleet:spawn", "fleet:store", "inventory:view", "cba:view" },
            suggestedWage = 40.00,
            isExecutive = false
        },
        {
            roleTitle = "Junior Apprentice",
            permissionNodes = { "inventory:view", "cba:view" },
            suggestedWage = 25.00,
            isExecutive = false
        }
    }
end
