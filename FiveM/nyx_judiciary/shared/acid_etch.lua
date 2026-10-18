--[[
    Nyxframework: nyx_judiciary
    File: shared/acid_etch.lua
    Description: Pure Lua 5.4 domain logic for forensic chemical acid-etching serial restoration,
                 reagent interaction models, crystal lattice deformation physics,
                 deterministic character masking, and certified laboratory analysis reports.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}
Nyx.AcidEtch = Nyx.AcidEtch or {}

-- 1. Certified Configuration & Reagent Chemistry
Nyx.AcidEtch.Config = {
    DurationMs = 10000,
    BaseSuccessRate = 0.60,      -- 60% full serial number restoration
    PartialSuccessRate = 0.30,   -- 30% partial restoration (masked digits)
    FailureRate = 0.10,          -- 10% completely obliterated crystal structure
    RequiredKitItem = 'acid_etch_kit',
    EtchingReagent = "Fry's Reagent (Cupric Chloride + Hydrochloric Acid + H2O)",
    MaxLabDistance = 3.5,
    AuthorizedJobs = {
        ['police'] = true,
        ['sheriff'] = true,
        ['state_police'] = true,
        ['doj'] = true,
        ['judge'] = true,
        ['forensics'] = true,
        ['admin'] = true
    },
    CertifiedLocations = {
        ['lab_davis_forensics'] = true,
        ['locker_mrpd_01'] = true,
        ['locker_sandy_01'] = true,
        ['locker_paleto_01'] = true,
        ['vault_court_district'] = true
    }
}

-- 2. Can Weapon Be Subject to Acid-Etching
function Nyx.AcidEtch.CanEtchWeapon(weaponItem, kitItem, userJob)
    if not weaponItem or type(weaponItem) ~= 'table' then
        return false, "INVALID_WEAPON"
    end

    local meta = weaponItem.metadata or {}
    if meta.scratched ~= true then
        return false, "WEAPON_NOT_SCRATCHED"
    end

    if meta.acidEtched == true then
        return false, "WEAPON_ALREADY_ETCHED"
    end

    if userJob and not Nyx.AcidEtch.Config.AuthorizedJobs[userJob] then
        return false, "UNAUTHORIZED_JOB"
    end

    if not kitItem or type(kitItem) ~= 'table' or kitItem.item_id ~= Nyx.AcidEtch.Config.RequiredKitItem then
        return false, "MISSING_ACID_ETCH_KIT"
    end

    local uses = (kitItem.metadata and tonumber(kitItem.metadata.usesRemaining)) or 1
    if uses <= 0 then
        return false, "ACID_KIT_EXHAUSTED"
    end

    return true
end

-- 3. Deterministic Masking of Unrecovered Digits
function Nyx.AcidEtch.MaskSerial(originalSerial, visibleRatio, seed)
    if not originalSerial or type(originalSerial) ~= 'string' then
        return "UNKNOWN"
    end

    visibleRatio = math.max(0.2, math.min(0.9, tonumber(visibleRatio) or 0.5))
    seed = tonumber(seed) or 12345

    local rng = function()
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        return (seed % 10000) / 10000.0
    end

    local prefix, digits = originalSerial:match("^(%a+%-)(.+)$")
    if not prefix or not digits then
        prefix = ""
        digits = originalSerial
    end

    local chars = {}
    for i = 1, #digits do
        chars[i] = digits:sub(i, i)
    end

    local totalChars = #chars
    local visibleCount = math.max(1, math.floor(totalChars * visibleRatio))
    local maskedCount = totalChars - visibleCount

    local indices = {}
    for i = 1, totalChars do indices[i] = i end

    -- Fisher-Yates shuffle on indices using deterministic rng
    for i = totalChars, 2, -1 do
        local j = math.floor(rng() * i) + 1
        indices[i], indices[j] = indices[j], indices[i]
    end

    -- Mask the selected indices
    for k = 1, maskedCount do
        local idxToMask = indices[k]
        chars[idxToMask] = "*"
    end

    return prefix .. table.concat(chars)
end

-- 4. Pure Mathematical Evaluator for Chemical Etch Restoration
function Nyx.AcidEtch.CalculateEtchOutcome(weaponItem, options)
    options = options or {}
    local meta = (weaponItem and weaponItem.metadata) or {}
    local originalSerial = tostring(meta.originalSerial or meta.serialNumber or "NYX-000000")
    local grindQuality = tonumber(meta.grindQuality) or 85

    local seed = tonumber(options.seed) or os.time()
    local rng = function()
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        return (seed % 10000) / 10000.0
    end

    -- Deep aggressive grind reduces full recovery chance
    -- Base full: 60%. At quality 100: 60% - 15% = 45%. At quality 50: 60% + 10% = 70%.
    local qualityFactor = (grindQuality - 70) * 0.005
    local fullRate = math.max(0.35, math.min(0.75, Nyx.AcidEtch.Config.BaseSuccessRate - qualityFactor))
    local partialRate = Nyx.AcidEtch.Config.PartialSuccessRate

    local roll = rng()
    local outcome = "FAILED"
    local restoredSerial = "[MEGSEMMISÜLT / OBLITERATED]"
    local recoveryRatio = 0.0
    local statusLabel = "SIKERTELEN - A KRISTÁLYSZERKEZET TÚLETCHELT VAGY TÚL MÉLYEN CSISZOLT"

    if roll < fullRate then
        outcome = "FULL"
        restoredSerial = originalSerial
        recoveryRatio = 1.0
        statusLabel = "TELJES HELYREÁLLÍTÁS (FULL CRYSTALLINE RESTORATION)"
    elseif roll < (fullRate + partialRate) then
        outcome = "PARTIAL"
        local visRatio = 0.40 + (rng() * 0.35) -- 40% to 75% revealed
        restoredSerial = Nyx.AcidEtch.MaskSerial(originalSerial, visRatio, seed)
        recoveryRatio = math.floor(visRatio * 100) / 100
        statusLabel = string.format("RÉSZLEGES HELYREÁLLÍTÁS (%.0f%% MATRIX RECOVERED)", recoveryRatio * 100)
    else
        outcome = "FAILED"
        restoredSerial = "[MEGSEMMISÜLT / OBLITERATED]"
        recoveryRatio = 0.0
        statusLabel = "SIKERTELEN - TÚL MÉLY METALLURGIAI BEAVATKOZÁS"
    end

    return {
        success = (outcome ~= "FAILED"),
        outcome = outcome,
        originalSerial = originalSerial,
        restoredSerial = restoredSerial,
        recoveryRatio = recoveryRatio,
        statusLabel = statusLabel,
        reagent = Nyx.AcidEtch.Config.EtchingReagent,
        grindQuality = grindQuality,
        timestamp = os.time()
    }
end

-- 5. Format Certified Laboratory Report
function Nyx.AcidEtch.FormatLabReport(reportData)
    reportData = reportData or {}
    local timeStr = os.date("!%Y-%m-%d %H:%M:%SZ", reportData.timestamp or os.time())
    local techCit = reportData.technicianCitizenId or "DOJ-FORENSIC-TECH"
    local facility = reportData.facilityName or "Davis Regional Forensic Crime Laboratory"
    local original = reportData.originalSerial or "UNKNOWN"
    local restored = reportData.restoredSerial or "N/A"
    local status = reportData.outcome or "UNKNOWN"
    local hits = tonumber(reportData.ballisticsHitCount) or 0

    local lines = {
        "==================================================================",
        "     SAN ANDREAS JUDICIARY - FORENSIC METALLURGY REPORT",
        "         CHEMICAL ACID-ETCH SERIAL RESTORATION ANALYSIS",
        "==================================================================",
        string.format("VIZSGÁLAT IDŐPONTJA: %s", timeStr),
        string.format("LABORATÓRIUM:         %s", facility),
        string.format("VEZETŐ TECHNIKUS:     %s", techCit),
        string.format("ALKALMAZOTT REAGENS:  %s", reportData.reagent or Nyx.AcidEtch.Config.EtchingReagent),
        "------------------------------------------------------------------",
        string.format("EREDETI GYÁRI SZÁM:   %s", (status == "FULL" and original) or "TITKOSÍTOTT / ISMERETLEN"),
        string.format("ELŐHÍVOTT GYÁRI SZÁM: %s", restored),
        string.format("HELYREÁLLÍTÁS FOKA:   %s (%s)", status, reportData.statusLabel or ""),
        string.format("BALISZTIKAI TALÁLAT:  %d db archivált hüvely / nyomkapcsolat", hits),
        "------------------------------------------------------------------"
    }

    if hits > 0 and reportData.ballisticsEvidenceIds then
        lines[#lines + 1] = "BALISZTIKAI BŰNJEL AZONOSÍTÓK:"
        for _, evid in ipairs(reportData.ballisticsEvidenceIds) do
            lines[#lines + 1] = string.format(" - BŰNJEL #%s (DOCKET REFERENCIA)", tostring(evid))
        end
        lines[#lines + 1] = "------------------------------------------------------------------"
    end

    lines[#lines + 1] = "HIVATALOS IGAZSÁGÜGYI DOKUMENTUM - BÍRÓSÁGI BIZONYÍTÉKKÉNT FELHASZNÁLHATÓ"
    lines[#lines + 1] = "=================================================================="

    return table.concat(lines, "\n")
end

-- 6. Zero-Trust Payload Validator
function Nyx.AcidEtch.ValidatePayload(payload)
    if not payload or type(payload) ~= 'table' then
        return false, "PAYLOAD_MUST_BE_TABLE"
    end

    local weaponSlot = tonumber(payload.weaponSlot)
    if not weaponSlot or weaponSlot < 1 then
        return false, "INVALID_WEAPON_SLOT"
    end

    if payload.kitSlot ~= nil then
        local kitSlot = tonumber(payload.kitSlot)
        if not kitSlot or kitSlot < 1 then
            return false, "INVALID_KIT_SLOT"
        end
    end

    return true
end
