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
        SELECT `warrant_id`, `type`, `probable_cause_summary`, `expires_at`
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
        FROM `nyx_vehicles` v
        LEFT JOIN `nyx_characters` c ON v.owner_citizen_id = c.citizen_id
        WHERE REPLACE(v.plate, ' ', '') = ?
    ]], { cleanPlate })

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

    return {
        success = true,
        vehicle = {
            plate = veh.plate,
            model = veh.model,
            ownerName = veh.owner_name or "Nincs Nyilvántartva",
            ownerCitizenId = veh.owner_citizen_id,
            garage = veh.garage_id,
            isImpounded = (veh.impound_state and veh.impound_state > 0),
            hasOwnerWarrant = (ownerWarrant and ownerWarrant > 0)
        }
    }
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
