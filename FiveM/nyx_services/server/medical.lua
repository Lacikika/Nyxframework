--[[
    Nyxframework: nyx_services
    File: server/medical.lua
    Description: Physical consumable-dependent healthcare engine, finite hospital container tracking
                 (stash:pillbox_meds), dynamic supply depletion, shortage penalties, and emergency
                 medical hauling contract orchestration.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.Hospitals = {}

-- Helper to safely generate nonces/UUIDs
local function generateUuid()
    local ok, nonce = pcall(function()
        return exports['nyx_core']:GenerateNonce()
    end)
    if ok and nonce then return nonce end
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

-- 1. Load Hospital Medical Facilities & Preload Stash Containers
function Nyx.Services.LoadHospitals()
    local rows = MySQL.query.await("SELECT * FROM `nyx_services_hospitals`")
    if rows then
        local stashIdsToPreload = {}

        for _, r in ipairs(rows) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(r.coords) == "string" then
                local ok, parsed = pcall(json.decode, r.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(r.coords) == "table" then
                coords = r.coords
            end

            local stashId = r.stash_id or Nyx.HospitalSupplies.GetStashIdForHospital(r.hospital_id)
            stashIdsToPreload[#stashIdsToPreload + 1] = stashId

            Nyx.Services.Hospitals[r.hospital_id] = {
                id = r.hospital_id,
                label = r.label,
                coords = vector3(coords.x, coords.y, coords.z),
                substationId = r.substation_id,
                stashId = stashId,
                criticalThreshold = tonumber(r.critical_threshold) or 5,
                degradedThreshold = tonumber(r.degraded_threshold) or 15,
                traumaKits = tonumber(r.trauma_kits) or 0,
                sterilePlasma = tonumber(r.sterile_plasma) or 0,
                surgicalPacks = tonumber(r.surgical_packs) or 0,
                status = r.status or "optimal",
                lastEmergencyContractAt = r.last_emergency_contract_at
            }
        end

        -- Preload / Register all hospital stashes in nyx_inventory
        if exports['nyx_inventory'] and exports['nyx_inventory'].RegisterContainer then
            for _, h in pairs(Nyx.Services.Hospitals) do
                exports['nyx_inventory']:RegisterContainer(
                    h.stashId,
                    h.label .. " Medical Stash",
                    250000,
                    100,
                    { x = h.coords.x, y = h.coords.y, z = h.coords.z }
                )
            end
        end

        -- Perform initial supply level evaluation across all hospitals
        for hospId, _ in pairs(Nyx.Services.Hospitals) do
            Nyx.Services.EvaluateHospitalStatus(hospId)
        end

        if Config.Debug then
            print(string.format("^2[Nyx:Services]^7 Loaded %d hospital facilities with finite stashes from database.^7", #rows))
        end
    end
end

-- 2. Query Current Supply Counts from Finite Stash Container
function Nyx.Services.GetHospitalStashCounts(hospitalId)
    local h = Nyx.Services.Hospitals[hospitalId]
    if not h then return {} end

    local counts = {}
    if exports['nyx_inventory'] and exports['nyx_inventory'].GetItemCount then
        for itemId, _ in pairs(Nyx.HospitalSupplies.TrackedItems) do
            counts[itemId] = exports['nyx_inventory']:GetItemCount(h.stashId, itemId) or 0
        end
    else
        -- Fallback to database query if inventory export is temporarily unavailable
        local rows = MySQL.query.await([[
            SELECT `item_id`, SUM(`amount`) AS `total`
            FROM `nyx_inventory_items`
            WHERE `inventory_id` = ?
            GROUP BY `item_id`
        ]], { h.stashId })

        for itemId, _ in pairs(Nyx.HospitalSupplies.TrackedItems) do
            counts[itemId] = 0
        end

        if rows then
            for _, row in ipairs(rows) do
                if counts[row.item_id] ~= nil then
                    counts[row.item_id] = tonumber(row.total) or 0
                end
            end
        end
    end

    -- Keep backward-compatible in-memory properties synchronized
    h.sterilePlasma = counts['med_plasma'] or 0
    h.traumaKits = (counts['med_firstaid'] or 0) + (counts['first_aid_pack'] or 0)
    h.surgicalPacks = counts['med_surgical_pack'] or 0

    return counts
end

-- 3. Authoritative Audit Logger
function Nyx.Services.LogSupplyAudit(hospitalId, stashId, action, itemId, qty, remaining, status, citId, contractId, notes)
    local auditUuid = generateUuid()
    MySQL.prepare([[
        INSERT INTO `nyx_services_hospital_supply_audit`
            (`audit_uuid`, `hospital_id`, `stash_id`, `action`, `item_id`, `quantity`,
             `remaining_count`, `status`, `citizen_id`, `contract_id`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        auditUuid,
        hospitalId,
        stashId,
        action,
        itemId,
        qty,
        remaining,
        status,
        citId,
        contractId,
        notes
    })
end

-- 4. Evaluate Hospital Supply Status & Trigger Emergency Logistics Contracts
function Nyx.Services.EvaluateHospitalStatus(hospitalId)
    local h = Nyx.Services.Hospitals[hospitalId]
    if not h then return "optimal", {} end

    local counts = Nyx.Services.GetHospitalStashCounts(hospitalId)
    local prevStatus = h.status

    local newStatus, metrics = Nyx.HospitalSupplies.EvaluateSupplyLevel(counts, {
        critical = h.criticalThreshold,
        degraded = h.degradedThreshold
    })

    h.status = newStatus

    if h.status ~= prevStatus then
        MySQL.prepare.await([[
            UPDATE `nyx_services_hospitals`
            SET `status` = ?,
                `sterile_plasma` = ?,
                `trauma_kits` = ?,
                `surgical_packs` = ?
            WHERE `hospital_id` = ?
        ]], { h.status, h.sterilePlasma, h.traumaKits, h.surgicalPacks, h.id })

        if h.status == "critical_shortage" then
            TriggerClientEvent("nyx:services:client:hospitalShortage", -1, {
                hospitalId = h.id,
                hospitalLabel = h.label,
                status = h.status,
                readinessPercent = metrics.readinessPercent
            })
        end
    end

    -- If critical, dispatch emergency medical hauling contract via nyx_logistics_freight_contracts
    if h.status == "critical_shortage" then
        local existingContract = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_logistics_freight_contracts`
            WHERE `dest_inventory_id` = ? AND `status` IN ('available', 'in_transit')
        ]], { h.stashId })

        if not existingContract or existingContract == 0 then
            -- Find the item with the highest deficit
            local targetItemId = "med_plasma"
            local maxDeficit = 0
            for itemId, defData in pairs(metrics.deficits) do
                if defData.needed > maxDeficit then
                    maxDeficit = defData.needed
                    targetItemId = itemId
                end
            end

            local contractSpec = Nyx.HospitalSupplies.CalculateEmergencyContract(
                h.id,
                targetItemId,
                counts[targetItemId] or 0
            )

            local contractUuid = generateUuid()
            local srcCoords = { x = 152.4, y = -3205.2, z = 5.9 }
            local dstCoords = { x = h.coords.x, y = h.coords.y, z = h.coords.z }

            local contractId = MySQL.insert.await([[
                INSERT INTO `nyx_logistics_freight_contracts`
                    (`contract_uuid`, `contract_type`, `issuer_type`, `issuer_id`, `title`,
                     `source_inventory_id`, `dest_inventory_id`, `source_coords`, `dest_coords`,
                     `zone_id`, `item_id`, `quantity`, `payout_per_unit`, `total_payout`,
                     `escrow_deposit`, `status`, `deadline_seconds`)
                VALUES (?, 'emergency_medical', 'hospital', ?, ?, ?, ?, ?, ?, 'zone_ls_metro', ?, ?, ?, ?, ?, 'available', ?)
            ]], {
                contractUuid,
                "hospital:" .. h.id,
                contractSpec.title,
                contractSpec.sourceInv,
                h.stashId,
                json.encode(srcCoords),
                json.encode(dstCoords),
                contractSpec.itemId,
                contractSpec.quantity,
                contractSpec.payoutPerUnit,
                contractSpec.totalPayout,
                contractSpec.escrowDeposit,
                contractSpec.deadlineSeconds
            })

            if contractId then
                MySQL.prepare.await([[
                    UPDATE `nyx_services_hospitals`
                    SET `last_emergency_contract_at` = NOW()
                    WHERE `hospital_id` = ?
                ]], { h.id })

                Nyx.Services.LogSupplyAudit(
                    h.id,
                    h.stashId,
                    'CONTRACT_TRIGGERED',
                    contractSpec.itemId,
                    contractSpec.quantity,
                    counts[contractSpec.itemId] or 0,
                    h.status,
                    nil,
                    contractId,
                    string.format("Dispatched emergency medical freight contract #%d for %dx %s", contractId, contractSpec.quantity, contractSpec.itemLabel)
                )

                TriggerClientEvent("nyx:logistics:client:newContractAvailable", -1, {
                    contractId = contractId,
                    title = contractSpec.title,
                    quantity = contractSpec.quantity,
                    totalPayout = contractSpec.totalPayout,
                    escrowDeposit = contractSpec.escrowDeposit,
                    zoneId = "zone_ls_metro"
                })

                print(string.format("^1[Nyx:Services] HOSPITAL SUPPLY DEPLETION: '%s' triggered emergency contract #%d for %dx %s ($%.2f total)!^7",
                    h.id, contractId, contractSpec.quantity, contractSpec.itemId, contractSpec.totalPayout))
            end
        end
    end

    return h.status, metrics
end

-- 5. Process Patient Revival and Consume Medical Inventory from Finite Container
function Nyx.Services.ProcessRevival(src, hospitalId, requiresSurgery)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local h = Nyx.Services.Hospitals[hospitalId]
    if not h then return false, "HOSPITAL_NOT_FOUND" end

    -- Verify regional electrical power
    local isPowered = true
    if h.substationId and Nyx.Services.Substations[h.substationId] then
        isPowered = not Nyx.Services.Substations[h.substationId].isBlackout
    end

    local penaltySeconds = Nyx.HospitalSupplies.CalculateRespawnPenalty(h.status, isPowered)

    -- Verify surgical capability if requested
    if requiresSurgery then
        local surgeryCount = exports['nyx_inventory'] and exports['nyx_inventory']:GetItemCount(h.stashId, "med_surgical_pack") or 0
        if surgeryCount <= 0 then
            return false, "SURGICAL_UNAVAILABLE_SUPPLY_DEPLETED"
        end

        local okSurg, _ = exports['nyx_inventory']:RemoveItem(h.stashId, "med_surgical_pack", 1)
        if okSurg then
            Nyx.Services.LogSupplyAudit(
                h.id, h.stashId, 'CONSUMED', 'med_surgical_pack', 1,
                surgeryCount - 1, h.status, player.citizenId, nil, "Surgical procedure consumable consumed"
            )
        end
    end

    -- Check and consume primary resuscitation consumables from finite container
    local hasPlasma = exports['nyx_inventory'] and exports['nyx_inventory']:HasItem(h.stashId, "med_plasma", 1)
    local hasTrauma = exports['nyx_inventory'] and (exports['nyx_inventory']:HasItem(h.stashId, "med_firstaid", 1) or exports['nyx_inventory']:HasItem(h.stashId, "first_aid_pack", 1))

    if hasPlasma and hasTrauma then
        local remP, _ = exports['nyx_inventory']:RemoveItem(h.stashId, "med_plasma", 1)
        local traumaItem = exports['nyx_inventory']:HasItem(h.stashId, "med_firstaid", 1) and "med_firstaid" or "first_aid_pack"
        local remT, _ = exports['nyx_inventory']:RemoveItem(h.stashId, traumaItem, 1)

        if remP then
            local pLeft = exports['nyx_inventory']:GetItemCount(h.stashId, "med_plasma")
            Nyx.Services.LogSupplyAudit(h.id, h.stashId, 'CONSUMED', 'med_plasma', 1, pLeft, h.status, player.citizenId, nil, "Patient resuscitation plasma unit consumed")
        end
        if remT then
            local tLeft = exports['nyx_inventory']:GetItemCount(h.stashId, traumaItem)
            Nyx.Services.LogSupplyAudit(h.id, h.stashId, 'CONSUMED', traumaItem, 1, tLeft, h.status, player.citizenId, nil, "Patient trauma kit consumed")
        end

        Nyx.Services.EvaluateHospitalStatus(hospitalId)
    else
        -- Zero-stock fallback: Maximum penalty delay applied
        penaltySeconds = penaltySeconds + 60
        Nyx.Services.EvaluateHospitalStatus(hospitalId)
    end

    local counts = Nyx.Services.GetHospitalStashCounts(hospitalId)

    return true, {
        hospitalId = hospitalId,
        stashId = h.stashId,
        respawnDelay = penaltySeconds,
        facilityStatus = h.status,
        isGridPowered = isPowered,
        remainingSupplies = {
            plasma = counts['med_plasma'] or 0,
            traumaKits = (counts['med_firstaid'] or 0) + (counts['first_aid_pack'] or 0),
            surgicalPacks = counts['med_surgical_pack'] or 0,
            bandages = counts['bandage_sterile'] or 0,
            tourniquets = counts['tourniquet'] or 0
        }
    }
end

-- 6. Restock Hospital Medical Reserves from Player Freight
function Nyx.Services.RestockHospital(src, hospitalId, supplyItem, amount)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local h = Nyx.Services.Hospitals[hospitalId]
    if not h then return false, "HOSPITAL_NOT_FOUND" end

    local valid, itemInfo = Nyx.HospitalSupplies.ValidateRestockItem(supplyItem, amount)
    if not valid then
        return false, itemInfo or "INVALID_MEDICAL_SUPPLY_ITEM"
    end

    local count = itemInfo.amount
    local invId = string.format("char:%s:main", player.citizenId)

    local removed, remErr = exports['nyx_inventory']:RemoveItem(invId, supplyItem, count)
    if not removed then
        -- Try fallback citizen: prefix
        local invIdAlt = "citizen:" .. player.citizenId
        removed, remErr = exports['nyx_inventory']:RemoveItem(invIdAlt, supplyItem, count)
        if not removed then
            return false, "INSUFFICIENT_ITEMS_IN_INVENTORY"
        end
    end

    local added, addErr = exports['nyx_inventory']:AddItem(h.stashId, supplyItem, count)
    if not added then
        -- Return items to player on failure
        exports['nyx_inventory']:AddItem(invId, supplyItem, count)
        return false, addErr or "STASH_FULL_OR_ERROR"
    end

    local newRemaining = exports['nyx_inventory']:GetItemCount(h.stashId, supplyItem)

    Nyx.Services.LogSupplyAudit(
        h.id, h.stashId, 'RESTOCKED', supplyItem, count, newRemaining,
        h.status, player.citizenId, nil, string.format("Restocked %dx %s by citizen %s", count, supplyItem, player.citizenId)
    )

    Nyx.Services.EvaluateHospitalStatus(hospitalId)

    -- If restock fulfills an open emergency freight contract, fulfill it
    MySQL.prepare.await([[
        UPDATE `nyx_logistics_freight_contracts`
        SET `status` = 'completed', `completed_at` = NOW()
        WHERE `dest_inventory_id` = ? AND `status` IN ('available', 'in_transit')
    ]], { h.stashId })

    return true, {
        hospitalId = hospitalId,
        stashId = h.stashId,
        restockedItem = supplyItem,
        newQuantity = newRemaining,
        status = h.status
    }
end

-- 7. Listener: Fulfillment of Courier Logistics Contract Delivery to Hospital Stash
RegisterNetEvent("nyx:services:server:hospitalSuppliesDelivered", function(hospitalId, contractId, itemId, quantity)
    local h = Nyx.Services.Hospitals[hospitalId]
    if not h then
        -- Try finding hospital by stashId
        for _, hosp in pairs(Nyx.Services.Hospitals) do
            if hosp.stashId == hospitalId then
                h = hosp
                hospitalId = hosp.id
                break
            end
        end
    end

    if h then
        local newRemaining = exports['nyx_inventory']:GetItemCount(h.stashId, itemId)
        Nyx.Services.LogSupplyAudit(
            h.id, h.stashId, 'DELIVERY_FULFILLED', itemId, quantity, newRemaining,
            h.status, nil, contractId, string.format("Emergency medical delivery fulfilled via contract #%s", tostring(contractId))
        )
        Nyx.Services.EvaluateHospitalStatus(hospitalId)
        print(string.format("^2[Nyx:Services] Hospital '%s' received emergency delivery of %dx %s. New stock: %d.^7",
            h.id, quantity, itemId, newRemaining))
    end
end)

-- 8. Query specific hospital state
function Nyx.Services.GetHospital(hospitalId)
    return Nyx.Services.Hospitals[hospitalId]
end

-- 9. Query all hospitals
function Nyx.Services.GetAllHospitals()
    return Nyx.Services.Hospitals
end

-- 10. Background Heartbeat Thread: Hospital Supply Monitoring (Every 60s)
CreateThread(function()
    while true do
        Wait(60000)
        for hospitalId, _ in pairs(Nyx.Services.Hospitals) do
            Nyx.Services.EvaluateHospitalStatus(hospitalId)
        end
    end
end)
