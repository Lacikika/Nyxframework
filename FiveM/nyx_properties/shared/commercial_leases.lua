--[[
    Nyxframework: nyx_properties & nyx_factions
    File: shared/commercial_leases.lua
    Description: Pure Lua 5.4 Commercial Real Estate Leasing & Public Storefront Lifecycle Engine.
                 Features zero-cent economic conservation, security deposit escrow, statutory municipal
                 rental tax splits, 4-tier delinquency interlocks, and doorlock / register evaluation.
]]

Nyx = Nyx or {}
Nyx.CommercialLeases = {}

-- Cent-precision rounding helper
local function roundToCent(val)
    val = tonumber(val) or 0.0
    return math.floor(val * 100.0 + 0.5) / 100.0
end

-- ----------------------------------------------------------------------------
-- 1. Statutory Zoning Types & Taxonomy
-- ----------------------------------------------------------------------------
Nyx.CommercialLeases.ZoningTypes = {
    retail_storefront = {
        label = "Kereskedelmi Kiskereskedelmi Üzlethelyiség",
        description = "Storefront suitable for consumer retail shelves and point-of-sale registers.",
        icon = "fa-solid fa-store",
        allowedRegisterCount = 4,
        allowedStashCapacityKg = 1500,
        rateMultiplier = 1.00
    },
    corporate_office = {
        label = "Vállalati Iroda & Adminisztrációs Központ",
        description = "Administrative hub for executive corporate management and legal contracts.",
        icon = "fa-solid fa-briefcase",
        allowedRegisterCount = 1,
        allowedStashCapacityKg = 800,
        rateMultiplier = 1.15
    },
    industrial_warehouse = {
        label = "Ipari Raktárbázis & Logisztikai Csarnok",
        description = "Heavy logistics facility with industrial pallet staging and bulk storage.",
        icon = "fa-solid fa-warehouse",
        allowedRegisterCount = 2,
        allowedStashCapacityKg = 10000,
        rateMultiplier = 0.90
    },
    hospitality_venue = {
        label = "Vendéglátóipari & Szórakoztató Létesítmény",
        description = "Social lounge, dining hall, or entertainment nightclub establishment.",
        icon = "fa-solid fa-martini-glass-citrus",
        allowedRegisterCount = 3,
        allowedStashCapacityKg = 2500,
        rateMultiplier = 1.25
    },
    medical_clinic = {
        label = "Közegészségügyi Rendelő & Magánklinika",
        description = "Sterile healthcare dispensary for trauma stabilization and pharmaceuticals.",
        icon = "fa-solid fa-hospital",
        allowedRegisterCount = 2,
        allowedStashCapacityKg = 1200,
        rateMultiplier = 1.10
    }
}

-- ----------------------------------------------------------------------------
-- 2. Statutory Constants
-- ----------------------------------------------------------------------------
Nyx.CommercialLeases.StandardSecurityDepositMultiplier = 1 -- 1 cycle rent held in escrow
Nyx.CommercialLeases.DefaultRentalTaxRate = 0.0500         -- 5.0% statutory municipal lease tax
Nyx.CommercialLeases.DefaultLatePenaltyRate = 0.1000       -- 10.0% statutory late surcharge on arrears
Nyx.CommercialLeases.DefaultBillingIntervalSeconds = 604800 -- 7 days / weekly cycle
Nyx.CommercialLeases.DefaultGracePeriodHours = 48          -- 48h before lease lapse
Nyx.CommercialLeases.DefaultEvictionDeadlineHours = 72     -- 72h before forced eviction
Nyx.CommercialLeases.MinCycleRent = 100.00
Nyx.CommercialLeases.MaxCycleRent = 1000000.00

-- ----------------------------------------------------------------------------
-- 3. Initial Lease Upfront Cost Calculation (Zero-Cent Conservation)
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.CalculateLeaseInitialCosts(baseRent, depositMultiplier, taxRate)
    local rent = math.max(Nyx.CommercialLeases.MinCycleRent, tonumber(baseRent) or 1000.00)
    rent = roundToCent(rent)

    local depMult = tonumber(depositMultiplier) or Nyx.CommercialLeases.StandardSecurityDepositMultiplier
    local tRate = tonumber(taxRate) or Nyx.CommercialLeases.DefaultRentalTaxRate
    tRate = math.max(0.00, math.min(0.30, tRate))

    local securityDeposit = roundToCent(rent * depMult)
    local municipalTax = roundToCent(rent * tRate)
    local netToLessor = roundToCent(rent - municipalTax)

    -- Strict exact cent conservation assertion: netToLessor + municipalTax == rent
    local delta = roundToCent(rent - (netToLessor + municipalTax))
    if math.abs(delta) > 0.0001 then
        netToLessor = roundToCent(netToLessor + delta)
    end

    local totalUpfrontRequired = roundToCent(rent + securityDeposit)

    return {
        cycleRent = rent,
        securityDeposit = securityDeposit,
        municipalTax = municipalTax,
        netToLessor = netToLessor,
        totalUpfrontRequired = totalUpfrontRequired,
        taxRate = tRate
    }
end

-- ----------------------------------------------------------------------------
-- 4. Recurring Lease Rent Split Calculation (Zero-Cent Conservation)
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.CalculateRecurringRentSplit(cycleRent, taxRate)
    local rent = math.max(0.00, roundToCent(cycleRent or 0.00))
    local tRate = tonumber(taxRate) or Nyx.CommercialLeases.DefaultRentalTaxRate
    tRate = math.max(0.00, math.min(0.30, tRate))

    local municipalTax = roundToCent(rent * tRate)
    local netToLessor = roundToCent(rent - municipalTax)

    -- Exact cent conservation check
    local delta = roundToCent(rent - (netToLessor + municipalTax))
    if math.abs(delta) > 0.0001 then
        netToLessor = roundToCent(netToLessor + delta)
    end

    return {
        grossRent = rent,
        municipalTax = municipalTax,
        netToLessor = netToLessor,
        taxRate = tRate
    }
end

-- ----------------------------------------------------------------------------
-- 5. Arrears & Late Settlement Calculation
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.CalculateArrearsSettlement(arrearsBalance, latePenaltyRate)
    local arrears = math.max(0.00, roundToCent(arrearsBalance or 0.00))
    local pRate = tonumber(latePenaltyRate) or Nyx.CommercialLeases.DefaultLatePenaltyRate

    local penaltyAmount = roundToCent(arrears * pRate)
    local totalSettlementDue = roundToCent(arrears + penaltyAmount)

    return {
        arrearsBalance = arrears,
        penaltyAmount = penaltyAmount,
        penaltyRate = pRate,
        totalSettlementDue = totalSettlementDue
    }
end

-- ----------------------------------------------------------------------------
-- 6. Delinquency State Machine Evaluation
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.EvaluateDelinquencyState(consecutiveMissedCycles, arrearsBalance, graceExpiresAt, evictionDeadlineAt, now)
    consecutiveMissedCycles = math.max(0, math.floor(tonumber(consecutiveMissedCycles) or 0))
    arrearsBalance = math.max(0.00, roundToCent(arrearsBalance or 0.00))
    now = tonumber(now) or os.time()

    local graceTime = tonumber(graceExpiresAt)
    local evictionTime = tonumber(evictionDeadlineAt)

    -- Tier 0: Solvent
    if consecutiveMissedCycles == 0 and arrearsBalance <= 0.00 then
        return {
            tier = 0,
            status = "active",
            label = "Aktív & Érvényes",
            badgeClass = "badge-success",
            isLockedOut = false,
            isRegistersDisabled = false,
            isEvictionDue = false
        }
    end

    -- Tier 4: Eviction Due / Lapsed Expiry
    if consecutiveMissedCycles >= 4 or (evictionTime and now >= evictionTime) then
        return {
            tier = 4,
            status = "evicted",
            label = "Kilakoltatva / Felszámolva",
            badgeClass = "badge-danger",
            isLockedOut = true,
            isRegistersDisabled = true,
            isEvictionDue = true
        }
    end

    -- Tier 2 or 3: Lapsed & Electronic Lockout
    if consecutiveMissedCycles >= 2 or (graceTime and now >= graceTime) then
        local tier = (consecutiveMissedCycles >= 3) and 3 or 2
        local statusLabel = (tier == 3) and "Kilakoltatási Felszólítás (Tier 3)" or "Bérlet Zárolva (Tier 2)"
        return {
            tier = tier,
            status = "lapsed",
            label = statusLabel,
            badgeClass = "badge-danger",
            isLockedOut = true,
            isRegistersDisabled = true,
            isEvictionDue = false
        }
    end

    -- Tier 1: In Grace Period
    return {
        tier = 1,
        status = "grace_period",
        label = "Türelmi Időszak (Tier 1)",
        badgeClass = "badge-warning",
        isLockedOut = false,
        isRegistersDisabled = false,
        isEvictionDue = false
    }
end

-- ----------------------------------------------------------------------------
-- 7. Doorlock Access Control Evaluation
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.EvaluateDoorlockAuthorization(property, lease, citizenId, playerJob, playerFactionId, permissions, hasWarrant)
    if not property then
        return false, "PROPERTY_NOT_FOUND"
    end

    -- 1. Emergency services with search warrant bypass
    if playerJob == "police" or playerJob == "sheriff" then
        if hasWarrant then
            return true, "AUTHORIZED_POLICE_WARRANT"
        end
    end

    -- If property is not commercial or not leased, fallback to standard property logic
    if not lease or not lease.lease_status or lease.lease_status == "not_leased" then
        return nil, "USE_STANDARD_PROPERTY_LOCKS"
    end

    -- 2. Delinquency Lockout: If lease is lapsed or evicted, regular commercial access is barred
    if lease.lease_status == "lapsed" or lease.lease_status == "evicted" or (lease.delinquency_tier and lease.delinquency_tier >= 2) then
        return false, "LOCK_OFFLINE_LEASE_LAPSED"
    end

    -- 3. Lessee Authorization Check
    if lease.lessee_type == "citizen" then
        if citizenId and (citizenId == lease.lessee_id or citizenId == lease.authorized_signer_citizen_id) then
            return true, "AUTHORIZED_CITIZEN_LESSEE"
        end
    elseif lease.lessee_type == "faction" then
        if playerFactionId and playerFactionId == lease.lessee_id then
            local perms = permissions or {}
            if perms["*"] or perms["property:manage"] or perms["warehouse:access"] or perms["funds:withdraw"] or (citizenId == lease.authorized_signer_citizen_id) then
                return true, "AUTHORIZED_FACTION_MEMBER"
            end
        end
    end

    -- 4. Landlord / Property Owner Inspection Privileges
    if property.ownerCitizenId and property.ownerCitizenId == citizenId then
        return true, "AUTHORIZED_LANDLORD_INSPECTION"
    end

    return false, "UNAUTHORIZED_NO_LEASE_KEY"
end

-- ----------------------------------------------------------------------------
-- 8. Commercial Register Operation Evaluation
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.EvaluateRegisterOperation(property, lease)
    if not lease then
        return false, "NO_ACTIVE_LEASE"
    end

    if lease.lease_status ~= "active" and lease.lease_status ~= "grace_period" then
        return false, "REGISTER_DISABLED_LEASE_LAPSED"
    end

    if lease.delinquency_tier and lease.delinquency_tier >= 2 then
        return false, "REGISTER_DISABLED_DELINQUENT"
    end

    return true, "REGISTER_OPERATIONAL"
end

-- ----------------------------------------------------------------------------
-- 9. Proposal Validation
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.ValidateLeaseProposal(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local propertyId = tonumber(payload.propertyId)
    if not propertyId or propertyId <= 0 then
        return false, "INVALID_PROPERTY_ID"
    end

    local lesseeType = payload.lesseeType or "faction"
    if lesseeType ~= "faction" and lesseeType ~= "citizen" then
        return false, "INVALID_LESSEE_TYPE"
    end

    local lesseeId = tostring(payload.lesseeId or ""):gsub("%s+", "")
    if #lesseeId < 2 or #lesseeId > 64 then
        return false, "INVALID_LESSEE_ID"
    end

    local signer = tostring(payload.authorizedSignerCitizenId or ""):gsub("%s+", "")
    if #signer < 2 or #signer > 16 then
        return false, "INVALID_SIGNER_CITIZEN_ID"
    end

    local zoning = payload.zoningUsage or "retail_storefront"
    if not Nyx.CommercialLeases.ZoningTypes[zoning] then
        return false, "INVALID_ZONING_TYPE"
    end

    local cycleRent = tonumber(payload.cycleRent)
    if not cycleRent or cycleRent < Nyx.CommercialLeases.MinCycleRent or cycleRent > Nyx.CommercialLeases.MaxCycleRent then
        return false, "INVALID_CYCLE_RENT"
    end

    local termCycles = tonumber(payload.leaseTermCycles) or 4
    if termCycles < 1 or termCycles > 52 then
        return false, "INVALID_TERM_CYCLES"
    end

    return true, {
        propertyId = propertyId,
        lesseeType = lesseeType,
        lesseeId = lesseeId,
        authorizedSignerCitizenId = signer,
        zoningUsage = zoning,
        cycleRent = roundToCent(cycleRent),
        leaseTermCycles = termCycles
    }
end

-- ----------------------------------------------------------------------------
-- 10. Serial Generators & Formatters
-- ----------------------------------------------------------------------------
function Nyx.CommercialLeases.GenerateLeaseId(propCodeOrId, lesseeId)
    local cleanProp = tostring(propCodeOrId):gsub("[^%w_]", ""):lower()
    local cleanLessee = tostring(lesseeId):gsub("[^%w_]", ""):lower()
    return string.format("lease:%s_%s", cleanProp, cleanLessee)
end

function Nyx.CommercialLeases.GenerateLeaseUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

function Nyx.CommercialLeases.FormatStatusBadge(status)
    status = status or "not_leased"
    if status == "active" or status == "leased_active" then
        return { label = "Aktív Bérlet", badgeClass = "badge-success", icon = "fa-solid fa-circle-check" }
    elseif status == "available_for_lease" then
        return { label = "Bérelhető", badgeClass = "badge-info", icon = "fa-solid fa-key" }
    elseif status == "grace_period" or status == "in_grace_period" then
        return { label = "Türelmi Időszak", badgeClass = "badge-warning", icon = "fa-solid fa-triangle-exclamation" }
    elseif status == "lapsed" or status == "lease_lapsed" then
        return { label = "Zárolt Bérlet (Hátralék)", badgeClass = "badge-danger", icon = "fa-solid fa-lock" }
    elseif status == "evicted" or status == "evicted_relisting" then
        return { label = "Kilakoltatva / Újra Hirdetve", badgeClass = "badge-danger", icon = "fa-solid fa-gavel" }
    end
    return { label = "Nem Bérelhető", badgeClass = "badge-secondary", icon = "fa-solid fa-ban" }
end

function Nyx.CommercialLeases.FormatLeaseReceipt(lease, audit)
    if not lease then return "NO_LEASE_DATA" end
    local rent = lease.cycle_rent or lease.cycleRent or 0.00
    local deposit = lease.security_deposit_held or lease.securityDeposit or 0.00
    local arrears = lease.arrears_balance or lease.arrearsBalance or 0.00

    return string.format([[
======================================================================
         SAN ANDREAS MUNICIPAL COMMERCIAL LEASE AGREEMENT
======================================================================
  Lease ID:            %s
  Property ID:         #%s (%s)
  Zoning Usage:        %s
  Lessor:              %s
  Lessee:              %s (%s)
  Signer Citizen:      %s
----------------------------------------------------------------------
  Cycle Rent:          $%10.2f
  Escrowed Deposit:    $%10.2f
  Arrears Balance:     $%10.2f
  Status:              %s
  Next Billing Due:    %s
======================================================================
]],
        tostring(lease.lease_id or lease.leaseId),
        tostring(lease.property_id or lease.propertyId),
        tostring(lease.property_code or "PROP"),
        tostring(lease.zoning_usage or lease.zoningUsage or "retail_storefront"),
        tostring(lease.lessor_account_id or lease.lessorAccountId or "gov:city:master"),
        tostring(lease.lessee_id or lease.lesseeId),
        tostring(lease.lessee_type or lease.lesseeType or "faction"),
        tostring(lease.authorized_signer_citizen_id or lease.authorizedSignerCitizenId or "N/A"),
        tonumber(rent) or 0.0,
        tonumber(deposit) or 0.0,
        tonumber(arrears) or 0.0,
        string.upper(tostring(lease.lease_status or lease.status or "active")),
        tostring(lease.next_billing_due_at or "SCHEDULED")
    )
end
