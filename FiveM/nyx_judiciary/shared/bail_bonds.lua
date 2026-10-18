--[[
    Nyxframework: nyx_judiciary
    File: shared/bail_bonds.lua
    Description: Pure Lua 5.4 deterministic domain engine for judicial bail schedules,
                 cash & surety payment breakdowns, release condition compliance,
                 courtroom appearance verification, and forfeiture bounty calculations.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}
Nyx.BailBonds = {}

-- 1. Status & Bond Type Constants
Nyx.BailBonds.STATUS_POSTED     = "posted"
Nyx.BailBonds.STATUS_EXONERATED = "exonerated"
Nyx.BailBonds.STATUS_FORFEITED  = "forfeited"
Nyx.BailBonds.STATUS_REVOKED    = "revoked"

Nyx.BailBonds.BOND_CASH         = "cash"
Nyx.BailBonds.BOND_SURETY       = "surety"
Nyx.BailBonds.BOND_RECOGNIZANCE = "recognizance"

-- Statutory Ratios & Limits
Nyx.BailBonds.CLERK_ADMIN_FEE_PERCENT    = 0.05   -- 5% administrative court fee upon exoneration
Nyx.BailBonds.SURETY_PREMIUM_PERCENT     = 0.10   -- 10% non-refundable premium for commercial surety bonds
Nyx.BailBonds.FUGITIVE_BOUNTY_PERCENT    = 0.15   -- 15% bounty on forfeited bail for licensed recovery agents
Nyx.BailBonds.MIN_BAIL_AMOUNT            = 500.00 -- Statutory minimum bail
Nyx.BailBonds.MAX_BAIL_AMOUNT            = 1000000.00 -- Statutory maximum bail cap
Nyx.BailBonds.MAX_COURTROOM_CHECKIN_DIST = 3.5    -- Max radius (meters) from courtroom terminal

-- Standard Base Bail Schedules per Case Classification
Nyx.BailBonds.BASE_SCHEDULES = {
    ['civil']                 = 0.00,
    ['criminal_misdemeanor']  = 2500.00,
    ['criminal_felony']       = 50000.00,
    ['constitutional']        = 100000.00
}

-- Canonical Courtroom & Jail Bail Terminals in San Andreas
Nyx.BailBonds.TERMINALS = {
    ['court_central_ls'] = {
        id = "court_central_ls",
        label = "San Andreas Superior Court District Terminal",
        coords = vector3(240.5, -1075.2, 29.2),
        heading = 350.0,
        type = "courtroom"
    },
    ['jail_mission_row'] = {
        id = "jail_mission_row",
        label = "Mission Row Central Holding Facility Bail Kiosk",
        coords = vector3(460.2, -988.5, 24.9),
        heading = 90.0,
        type = "booking_kiosk"
    },
    ['penitentiary_bolingbroke'] = {
        id = "penitentiary_bolingbroke",
        label = "Bolingbroke State Penitentiary Intake & Escrow Kiosk",
        coords = vector3(1848.2, 2585.8, 45.6),
        heading = 270.0,
        type = "prison_escrow"
    }
}

--- Helper: Round float to 2 decimal places
local function round2(num)
    return math.floor(num * 100.0 + 0.5) / 100.0
end

--- Calculate statutory bail schedule recommendation based on case type, prior FTAs, and gravity multiplier
--- @param caseType string
--- @param priorFTAs number|nil
--- @param offenseGravityMultiplier number|nil
--- @return number recommendedBailAmount
function Nyx.BailBonds.CalculateBailSchedule(caseType, priorFTAs, offenseGravityMultiplier)
    local base = Nyx.BailBonds.BASE_SCHEDULES[caseType] or 10000.00
    if base <= 0.0 then
        return 0.00
    end

    local ftas = math.max(0, math.floor(tonumber(priorFTAs) or 0))
    local gravity = math.max(0.50, math.min(3.00, tonumber(offenseGravityMultiplier) or 1.00))

    -- Each prior failure to appear incurs a 50% compounding penalty
    local ftaFactor = 1.0 + (ftas * 0.50)
    local raw = base * ftaFactor * gravity

    local clamped = math.max(Nyx.BailBonds.MIN_BAIL_AMOUNT, math.min(Nyx.BailBonds.MAX_BAIL_AMOUNT, raw))
    return round2(clamped)
end

--- Evaluate whether a docket defendant is legally eligible for pre-trial bail release
--- @param docket table
--- @param defendantRecord table|nil
--- @return boolean isEligible, string reason
function Nyx.BailBonds.EvaluateBailEligibility(docket, defendantRecord)
    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    if docket.bail_status == "remand_no_bail" then
        return false, "DEFENDANT_REMANDED_NO_BAIL"
    end

    if docket.case_type == "civil" then
        return false, "CIVIL_CASE_NO_BAIL"
    end

    if docket.status == "concluded" or docket.status == "dismissed" then
        return false, "DOCKET_ALREADY_CONCLUDED"
    end

    if defendantRecord and defendantRecord.hasViolentCapitalFlag then
        return false, "CAPITAL_CRIME_REQUIRES_JUDICIAL_HEARING"
    end

    return true, "ELIGIBLE"
end

--- Calculate exact payment breakdown, upfront deposit, surety collateral, and statutory clerk fee
--- @param bailAmount number
--- @param bondType string 'cash', 'surety', 'recognizance'
--- @return table breakdown
function Nyx.BailBonds.CalculateBailPaymentBreakdown(bailAmount, bondType)
    local amount = math.max(Nyx.BailBonds.MIN_BAIL_AMOUNT, tonumber(bailAmount) or Nyx.BailBonds.MIN_BAIL_AMOUNT)
    amount = round2(amount)

    local clerkFee = round2(amount * Nyx.BailBonds.CLERK_ADMIN_FEE_PERCENT)
    local exonerationRefund = round2(amount - clerkFee)

    bondType = bondType or Nyx.BailBonds.BOND_CASH

    if bondType == Nyx.BailBonds.BOND_CASH then
        return {
            bondType = Nyx.BailBonds.BOND_CASH,
            bailAmount = amount,
            requiredUpfrontDeposit = amount,
            suretyPremiumPaid = 0.00,
            suretyCollateral = amount,
            exonerationRefund = exonerationRefund,
            clerkAdminFee = clerkFee
        }
    elseif bondType == Nyx.BailBonds.BOND_SURETY then
        local premium = round2(amount * Nyx.BailBonds.SURETY_PREMIUM_PERCENT)
        return {
            bondType = Nyx.BailBonds.BOND_SURETY,
            bailAmount = amount,
            requiredUpfrontDeposit = premium,
            suretyPremiumPaid = premium,
            suretyCollateral = amount,
            exonerationRefund = exonerationRefund,
            clerkAdminFee = clerkFee
        }
    elseif bondType == Nyx.BailBonds.BOND_RECOGNIZANCE then
        return {
            bondType = Nyx.BailBonds.BOND_RECOGNIZANCE,
            bailAmount = amount,
            requiredUpfrontDeposit = 0.00,
            suretyPremiumPaid = 0.00,
            suretyCollateral = 0.00,
            exonerationRefund = 0.00,
            clerkAdminFee = 0.00
        }
    end

    return nil
end

--- Evaluate physical court appearance verification within designated courtroom distance
--- @param checkinCoords table {x, y, z}
--- @param courtroomCoords table {x, y, z}
--- @param maxDist number|nil (default 3.5m)
--- @return boolean isVerified, number distance
function Nyx.BailBonds.EvaluateCourtAppearance(checkinCoords, courtroomCoords, maxDist)
    if not checkinCoords or not courtroomCoords then
        return false, 9999.0
    end

    maxDist = tonumber(maxDist) or Nyx.BailBonds.MAX_COURTROOM_CHECKIN_DIST

    local dx = (checkinCoords.x or 0.0) - (courtroomCoords.x or 0.0)
    local dy = (checkinCoords.y or 0.0) - (courtroomCoords.y or 0.0)
    local dz = (checkinCoords.z or 0.0) - (courtroomCoords.z or 0.0)
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

    local isNear = (dist <= maxDist)
    return isNear, round2(dist)
end

--- Calculate forfeited treasury revenue and fugitive recovery bounty upon Failure to Appear (FTA)
--- @param bailAmount number
--- @return number forfeitedToTreasury, number fugitiveRecoveryBounty
function Nyx.BailBonds.CalculateForfeitureAndBounty(bailAmount)
    local amount = math.max(0.0, tonumber(bailAmount) or 0.0)
    amount = round2(amount)

    local bounty = round2(amount * Nyx.BailBonds.FUGITIVE_BOUNTY_PERCENT)
    return amount, bounty
end

--- Validate release conditions compliance (curfew, weapon possession, jurisdictional territory)
--- @param conditions table array of condition strings e.g. {'no_weapons', 'curfew_2200', 'stay_in_county'}
--- @param inventoryItems table array of item names or map of items in possession
--- @param currentHour number 0-23
--- @param playerCoords table {x, y, z}
--- @param centerCoords table {x, y, z}
--- @param maxJurisdictionRadius number|nil (default 3500.0m)
--- @return boolean isCompliant, table violations
function Nyx.BailBonds.ValidateReleaseConditions(conditions, inventoryItems, currentHour, playerCoords, centerCoords, maxJurisdictionRadius)
    conditions = conditions or {}
    inventoryItems = inventoryItems or {}
    currentHour = tonumber(currentHour) or 12
    maxJurisdictionRadius = tonumber(maxJurisdictionRadius) or 3500.0

    local violations = {}

    local condLookup = {}
    for _, c in ipairs(conditions) do
        condLookup[c] = true
    end

    -- 1. No weapons prohibition
    if condLookup['no_weapons'] then
        local weaponKeywords = { "weapon_", "ammo_", "pistol", "smg", "rifle", "shotgun" }
        for k, v in pairs(inventoryItems) do
            local itemName = type(k) == "string" and k or tostring(v)
            local lowerName = string.lower(itemName)
            for _, kw in ipairs(weaponKeywords) do
                if string.find(lowerName, kw, 1, true) then
                    table.insert(violations, "WEAPON_PROHIBITION_VIOLATED")
                    break
                end
            end
            if #violations > 0 and violations[#violations] == "WEAPON_PROHIBITION_VIOLATED" then
                break
            end
        end
    end

    -- 2. Curfew (active 22:00 to 06:00)
    if condLookup['curfew_2200'] and playerCoords and centerCoords then
        if currentHour >= 22 or currentHour < 6 then
            local dx = (playerCoords.x or 0.0) - (centerCoords.x or 0.0)
            local dy = (playerCoords.y or 0.0) - (centerCoords.y or 0.0)
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 50.0 then -- more than 50m from designated curfew domicile
                table.insert(violations, "CURFEW_VIOLATED")
            end
        end
    end

    -- 3. Stay in county jurisdiction
    if condLookup['stay_in_county'] and playerCoords and centerCoords then
        local dx = (playerCoords.x or 0.0) - (centerCoords.x or 0.0)
        local dy = (playerCoords.y or 0.0) - (centerCoords.y or 0.0)
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > maxJurisdictionRadius then
            table.insert(violations, "JURISDICTION_BOUNDARY_VIOLATED")
        end
    end

    return (#violations == 0), violations
end

--- Format UI status badge and presentation strings
--- @param status string
--- @param bondType string
--- @return table badgeInfo
function Nyx.BailBonds.FormatBailBadge(status, bondType)
    local badges = {
        ['posted'] = {
            class = "badge-warning",
            label = "Óvadék Letétbe Helyezve (Bail Posted)",
            active = true,
            description = "A vádlott feltételes szabadlábon védekezik a tárgyalás kitűzéséig."
        },
        ['exonerated'] = {
            class = "badge-success",
            label = "Óvadék Felmentve (Bail Exonerated)",
            active = false,
            description = "A tárgyalás lezárult, a letéti kaució visszautalásra került."
        },
        ['forfeited'] = {
            class = "badge-danger",
            label = "Óvadék Elkobozva / Szökevény (Forfeited FTA)",
            active = false,
            description = "A vádlott nem jelent meg a bíróság előtt; elfogatóparancs érvényben."
        },
        ['revoked'] = {
            class = "badge-dark",
            label = "Óvadék Visszavonva (Bail Revoked)",
            active = false,
            description = "A feltételes szabadlábra helyezési feltételek megsértése miatt visszavonva."
        }
    }

    return badges[status] or {
        class = "badge-secondary",
        label = "Ismeretlen Státusz",
        active = false,
        description = "Nem definiált óvadéki állapot."
    }
end
