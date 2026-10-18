--[[
    Nyxframework: nyx_mdt
    File: server/records.lua
    Description: Citizen profile queries, vehicle registry cross-checks,
                 active warrant integration, and double-entry fine collection.
]]

Nyx = Nyx or {}
Nyx.MDT = Nyx.MDT or {}

-- 1. RPC: Search Citizen Records
exports['nyx_core']:RegisterRPC("mdt:searchCitizen", function(src, query)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    if not query or #query < 2 then
        return { success = false, error = "QUERY_TOO_SHORT" }
    end

    local searchParam = "%" .. query .. "%"

    -- Find citizen profile
    local citizen = MySQL.single.await([[
        SELECT `char_id`, `citizen_id`, `first_name`, `last_name`, `gender`, `date_of_birth`
        FROM `nyx_characters`
        WHERE `citizen_id` = ? OR CONCAT(`first_name`, ' ', `last_name`) LIKE ?
        LIMIT 1
    ]], { query, searchParam })

    if not citizen then
        return { success = false, error = "CITIZEN_NOT_FOUND" }
    end

    local citId = citizen.citizen_id

    -- 1. Fetch Registered Vehicles
    local vehicles = MySQL.query.await([[
        SELECT `plate`, `model`, `garage_id`, `impound_state`
        FROM `nyx_vehicles`
        WHERE `owner_citizen_id` = ?
    ]], { citId }) or {}

    -- 2. Fetch Owned Properties
    local properties = MySQL.query.await([[
        SELECT `property_id`, `label`, `type`
        FROM `nyx_properties`
        WHERE `owner_citizen_id` = ?
    ]], { citId }) or {}

    -- 3. Fetch Prior Citations / Fines
    local priors = MySQL.query.await([[
        SELECT `fine_id`, `charge_title`, `amount`, `status`, `created_at`
        FROM `nyx_mdt_fines`
        WHERE `target_citizen_id` = ?
        ORDER BY `created_at` DESC
        LIMIT 15
    ]], { citId }) or {}

    -- 4. Fetch Active Warrants from nyx_judiciary
    local warrants = MySQL.query.await([[
        SELECT `warrant_id`, `type`, `probable_cause_summary`, `judicial_signature`, `subpoena_scope`, `tracking_active`, `expires_at`
        FROM `nyx_judiciary_warrants`
        WHERE `target_citizen_id` = ? AND `status` = 'active'
    ]], { citId }) or {}

    return {
        success = true,
        profile = {
            citizenId = citId,
            fullName = string.format("%s %s", citizen.first_name, citizen.last_name),
            gender = citizen.gender,
            dob = citizen.date_of_birth,
            vehicles = vehicles,
            properties = properties,
            priors = priors,
            warrants = warrants
        }
    }
end)

-- 2. RPC: Search Vehicle Registry
exports['nyx_core']:RegisterRPC("mdt:searchVehicle", function(src, plate)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    if not plate or #plate < 2 then
        return { success = false, error = "INVALID_PLATE" }
    end

    local cleanPlate = string.gsub(plate, "%s+", ""):upper()

    local veh = MySQL.single.await([[
        SELECT v.*, CONCAT(c.first_name, ' ', c.last_name) AS `owner_name`
        FROM `nyx_vehicles_owned` v
        LEFT JOIN `nyx_characters` c ON v.owner_citizen_id = c.citizen_id
        WHERE REPLACE(v.plate, ' ', '') = ?
    ]], { cleanPlate })

    if not veh then
        -- Fallback to legacy view/table if present
        veh = MySQL.single.await([[
            SELECT v.*, CONCAT(c.first_name, ' ', c.last_name) AS `owner_name`
            FROM `nyx_vehicles` v
            LEFT JOIN `nyx_characters` c ON v.owner_citizen_id = c.citizen_id
            WHERE REPLACE(v.plate, ' ', '') = ?
        ]], { cleanPlate })
    end

    if not veh then
        return { success = false, error = "VEHICLE_NOT_FOUND" }
    end

    -- Check if owner has active arrest warrants
    local ownerWarrant = nil
    if veh.owner_citizen_id then
        ownerWarrant = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_judiciary_warrants`
            WHERE `target_citizen_id` = ? AND `status` = 'active'
        ]], { veh.owner_citizen_id })
    end

    local isImpounded = (veh.storage_state == "impounded" or (veh.impound_state and veh.impound_state > 0))

    return {
        success = true,
        vehicle = {
            vin = veh.vin,
            plate = veh.plate,
            model = veh.model_name or veh.model,
            ownerName = veh.owner_name or "Nincs Nyilvántartva",
            ownerCitizenId = veh.owner_citizen_id,
            garage = veh.garage_id,
            storageState = veh.storage_state or "stored",
            isImpounded = isImpounded,
            impoundLotId = veh.impound_lot_id,
            impoundFee = veh.impound_fee or 0.0,
            impoundReason = veh.impound_reason,
            registrationStatus = veh.registration_status or "valid",
            registrationExpiresAt = veh.registration_expires_at or 0,
            hasOwnerWarrant = (ownerWarrant and ownerWarrant > 0)
        }
    }
end)

-- 2b. RPC: MDT Impound Vehicle
exports['nyx_core']:RegisterRPC("mdt:impoundVehicle", function(src, payload)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end
    local player = Nyx.GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local vin = payload and payload.vin
    local reason = payload and payload.reason
    local fee = payload and payload.fee
    local lotId = payload and payload.lotId or "impound_lot_ls"

    local ok, res = exports['nyx_vehicles']:ImpoundVehicle(vin, reason, fee, lotId, player.citizenId)
    if not ok then
        return { success = false, error = res }
    end
    return { success = true, result = res }
end)

-- 3. RPC: Issue Citation & Automated Direct Fine Debit
exports['nyx_core']:RegisterRPC("mdt:issueFine", function(src, payload)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    local targetCitizenId = payload and payload.targetCitizenId
    local chargeTitle = payload and payload.chargeTitle
    local amount = payload and tonumber(payload.amount)

    if not targetCitizenId or not chargeTitle or not amount or amount <= 0 then
        return { success = false, error = "INVALID_PARAMETERS" }
    end

    -- Enforce statutory limits from nyx_parliament if registered
    local chargeId = payload and payload.chargeId
    local maxAllowedFine = Config.MDT.DefaultFineLimit or 25000.00
    local minAllowedFine = 0.0

    if exports['nyx_parliament'] then
        local targetId = chargeId or ("penal:" .. chargeTitle:lower():gsub("[^%w]", "_"))
        local law = exports['nyx_parliament']:GetLaw(targetId)
        if law then
            if law.maxAllowed and law.maxAllowed.fine then
                maxAllowedFine = tonumber(law.maxAllowed.fine) or maxAllowedFine
            end
            if law.minAllowed and law.minAllowed.fine then
                minAllowedFine = tonumber(law.minAllowed.fine) or 0.0
            end
        end
    end

    if amount > maxAllowedFine then
        return {
            success = false,
            error = "EXCEEDS_STATUTORY_MAXIMUM",
            maxAllowed = maxAllowedFine,
            charge = chargeTitle
        }
    end

    if amount < minAllowedFine then
        return {
            success = false,
            error = "BELOW_STATUTORY_MINIMUM",
            minAllowed = minAllowedFine,
            charge = chargeTitle
        }
    end

    local officer = exports['nyx_core']:GetPlayer(src)
    local officerCitId = officer and officer.citizenId or "SYSTEM"

    local destAccount = Config.MDT.TreasuryFinesAccount or "gov:dept:police"
    exports['nyx_treasury']:EnsureAccount(destAccount, "Police Department Fund", "department", 0.00)

    -- Attempt direct bank debit
    local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(targetCitizenId)
    local fineStatus = "debited"
    local txUuid = string.format("fine_%s_%d", targetCitizenId, os.time())

    if targetPlayer then
        targetPlayer:removeMoney("bank", amount, string.format("Rendőrségi Bírság: %s", chargeTitle))
    else
        -- Debit offline citizen
        local charRow = MySQL.single.await("SELECT `money` FROM `nyx_characters` WHERE `citizen_id` = ?", { targetCitizenId })
        if charRow and charRow.money then
            local moneyData = json.decode(charRow.money) or {}
            local curBank = tonumber(moneyData.bank) or 0
            moneyData.bank = curBank - amount -- Can result in delinquent negative balance
            MySQL.prepare("UPDATE `nyx_characters` SET `money` = ? WHERE `citizen_id` = ?", { json.encode(moneyData), targetCitizenId })
        end
    end

    -- Credit Municipal Account
    MySQL.prepare([[
        UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?
    ]], { amount, destAccount })

    -- Double-entry ledger insertion
    MySQL.prepare([[
        INSERT INTO `nyx_treasury_ledger`
            (`tx_uuid`, `category`, `debit_account`, `credit_account`, `amount`, `memo`)
        VALUES (?, 'court_fine', ?, ?, ?, ?)
    ]], {
        txUuid,
        string.format("char:%s:bank", targetCitizenId),
        destAccount,
        amount,
        string.format("Fine Citation: %s (Officer: %s)", chargeTitle, officerCitId)
    })

    -- Insert fine record
    local fineId = MySQL.insert.await([[
        INSERT INTO `nyx_mdt_fines`
            (`target_citizen_id`, `officer_citizen_id`, `charge_title`, `amount`, `treasury_tx_uuid`, `status`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        targetCitizenId,
        officerCitId,
        chargeTitle,
        amount,
        txUuid,
        fineStatus,
        payload.notes or "Standard citation"
    })

    if targetPlayer then
        TriggerClientEvent("nyx:ui:notify", targetPlayer.source, {
            type = "error",
            title = "BÍRSÁG KISZABVA",
            message = string.format("Rendőrségi bírság levonva: $%.2f (%s)", amount, chargeTitle)
        })
    end

    return {
        success = true,
        fineId = fineId,
        amount = amount,
        targetCitizenId = targetCitizenId
    }
end)

-- 4. RPC: Query Live Penal Code Catalog
exports['nyx_core']:RegisterRPC("mdt:getPenalCode", function(src)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    local penal = nil
    if exports['nyx_parliament'] then
        penal = exports['nyx_parliament']:GetPenalCode()
    elseif GlobalState.penalCode then
        penal = GlobalState.penalCode
    end

    return {
        success = true,
        penalCode = penal or {}
    }
end)

-- 5. Event Listener: Live Penal Code & Statutory Law Sync from nyx_parliament
RegisterNetEvent("nyx:parliament:lawsUpdated", function(actions)
    print(string.format("^2[Nyx:MDT] Synchronized %d live statutory amendments from Parliament.^7", #(actions or {})))
    for src, _ in pairs(Nyx.MDT.OnDutyUnits or {}) do
        TriggerClientEvent("nyx:ui:notify", src, {
            type = "info",
            title = "MDT: JOGSZABÁLY MÓDOSÍTÁS",
            message = "A Parlament új büntető törvénykönyvi és adózási rendeletet hirdetett ki. Bírsághatárok frissítve."
        })
    end
end)

-- 6. RPC: Subpoena Confidential Financial & Asset Records
exports['nyx_core']:RegisterRPC("mdt:getSubpoenaRecords", function(src, targetCitizenId)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    if not targetCitizenId then
        return { success = false, error = "MISSING_TARGET_CITIZEN_ID" }
    end

    local officer = exports['nyx_core']:GetPlayer(src)
    local officerCitId = officer and officer.citizenId or "OFFICER"

    if exports['nyx_judiciary'] and exports['nyx_judiciary'].GetSubpoenaFinancials then
        local ok, records = exports['nyx_judiciary']:GetSubpoenaFinancials(targetCitizenId, officerCitId)
        if not ok then
            return { success = false, error = records }
        end
        return { success = true, records = records }
    end

    return { success = false, error = "JUDICIARY_SUBSYSTEM_UNAVAILABLE" }
end)

-- 7. RPC: File Formal Warrant Petition from MDT Terminal
exports['nyx_core']:RegisterRPC("mdt:petitionWarrant", function(src, payload)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    local officer = exports['nyx_core']:GetPlayer(src)
    local officerCitId = officer and officer.citizenId or "OFFICER"

    if exports['nyx_judiciary'] and exports['nyx_judiciary'].PetitionWarrant then
        local ok, petition = exports['nyx_judiciary']:PetitionWarrant(
            officerCitId,
            payload.targetCitizenId,
            payload.warrantType,
            payload.probableCauseSummary,
            payload.targetEntityId,
            payload.subpoenaScope,
            payload.requestedDurationHours
        )
        return { success = ok, petition = petition, error = (not ok and petition or nil) }
    end

    return { success = false, error = "JUDICIARY_SUBSYSTEM_UNAVAILABLE" }
end)

-- 8. RPC: Judicial Council Petition Review from MDT
exports['nyx_core']:RegisterRPC("mdt:reviewWarrantPetition", function(src, payload)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    local player = exports['nyx_core']:GetPlayer(src)
    local job = player and player:getMetadata("job")
    if job ~= "judge" and job ~= "doj" and not (player and player.hasPermission and player:hasPermission("admin")) then
        return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
    end

    if exports['nyx_judiciary'] and exports['nyx_judiciary'].ReviewPetition then
        local ok, res = exports['nyx_judiciary']:ReviewPetition(
            payload.petitionId,
            player.citizenId,
            payload.decision,
            payload.reviewNotes
        )
        return { success = ok, result = res, error = (not ok and res or nil) }
    end

    return { success = false, error = "JUDICIARY_SUBSYSTEM_UNAVAILABLE" }
end)
