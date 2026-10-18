--[[
    Nyxframework: nyx_logistics
    File: server/pallets.lua
    Description: Authoritative physical freight pallet registry, lifecycle orchestration,
                 vehicle attachment matrix, shelf snapping, and audit logging.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Pallets = {} -- [palletId] = palletData

-- Helper to safely format coords JSON
local function jsonEncodeCoords(coords)
    if not coords then return nil end
    return json.encode({
        x = math.floor((coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or 0.0) * 100) / 100,
        z = math.floor((coords.z or 0.0) * 100) / 100
    })
end

-- 1. Bootloader: Load persisted pallets into memory
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_logistics_pallets`")
    if rows then
        -- Performance: Batch pre-load all physical pallet inventories in one array query
        local palletInvIds = {}
        for _, r in ipairs(rows) do
            if r.inventory_id and r.inventory_id ~= "" then
                palletInvIds[#palletInvIds + 1] = r.inventory_id
            end
        end

        if #palletInvIds > 0 and exports['nyx_inventory'] and exports['nyx_inventory'].BatchLoadInventories then
            exports['nyx_inventory']:BatchLoadInventories(palletInvIds, 'pallet')
        end

        for _, r in ipairs(rows) do
            local coords = nil
            if r.coords and type(r.coords) == "string" then
                local ok, parsed = pcall(json.decode, r.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(r.coords) == "table" then
                coords = r.coords
            end

            local offset = nil
            if r.attached_offset and type(r.attached_offset) == "string" then
                local ok, parsed = pcall(json.decode, r.attached_offset)
                if ok and type(parsed) == "table" then offset = parsed end
            elseif type(r.attached_offset) == "table" then
                offset = r.attached_offset
            end

            local forensicEvidence = {}
            if r.forensic_evidence_ids and type(r.forensic_evidence_ids) == "string" then
                local ok, parsed = pcall(json.decode, r.forensic_evidence_ids)
                if ok and type(parsed) == "table" then forensicEvidence = parsed end
            elseif type(r.forensic_evidence_ids) == "table" then
                forensicEvidence = r.forensic_evidence_ids
            end

            Nyx.Logistics.Pallets[r.pallet_id] = {
                id = r.pallet_id,
                inventory_id = r.inventory_id,
                label = r.label,
                model = r.model,
                coords = coords,
                heading = tonumber(r.heading) or 0.0,
                routing_bucket = tonumber(r.routing_bucket) or 0,
                attached_vehicle_plate = r.attached_vehicle_plate,
                attached_slot_index = tonumber(r.attached_slot_index) or 0,
                attached_offset = offset,
                shelf_node_id = r.shelf_node_id,
                is_sealed = (tonumber(r.is_sealed) == 1),
                is_tampered = (tonumber(r.is_tampered) == 1),
                seal_serial = r.seal_serial,
                sealed_at = r.sealed_at,
                sealed_by_citizen_id = r.sealed_by_citizen_id,
                breached_at = r.breached_at,
                breached_by_citizen_id = r.breached_by_citizen_id,
                tamper_tool = r.tamper_tool,
                forensic_evidence_ids = forensicEvidence,
                created_by_citizen_id = r.created_by_citizen_id
            }

            -- Ensure inventory container exists in nyx_inventory
            if exports['nyx_inventory'] then
                local inv = exports['nyx_inventory']:GetInventory(r.inventory_id)
                if not inv and exports['nyx_inventory'].CreateInventory then
                    exports['nyx_inventory']:CreateInventory(r.inventory_id, 'pallet', {
                        maxWeight = Nyx.Pallets.MaxWeight,
                        maxSlots = Nyx.Pallets.MaxSlots,
                        coords = coords
                    })
                end
            end
        end
        print(string.format("^2[Nyx:Logistics] Loaded %d physical freight pallets into memory.^7", #rows))
    end
end)

-- 2. Create a new physical freight pallet
function Nyx.Logistics.CreateFreightPallet(coords, heading, bucket, initialItems, citizenId, label)
    local nano = os.time()
    local rnd = math.random(1000, 9999)
    local palletId = string.format("plt_%x%04d", nano, rnd)
    local invId = string.format("pallet:%s", palletId)
    local palletLabel = label or ("Freight Pallet #" .. string.sub(palletId, -6))
    bucket = tonumber(bucket) or 0
    heading = tonumber(heading) or 0.0

    -- Ensure container in nyx_inventory
    if exports['nyx_inventory'] and exports['nyx_inventory'].CreateInventory then
        exports['nyx_inventory']:CreateInventory(invId, 'pallet', {
            maxWeight = Nyx.Pallets.MaxWeight,
            maxSlots = Nyx.Pallets.MaxSlots,
            coords = coords
        })
    end

    local totalWeight = 0
    local itemCount = 0

    if initialItems and type(initialItems) == "table" then
        for _, it in ipairs(initialItems) do
            local meta = it.metadata or {}
            meta.palletId = palletId
            exports['nyx_inventory']:AddItem(invId, it.item, it.amount, meta)
            itemCount = itemCount + 1
            local w = (exports['nyx_inventory'].GetItemWeight and exports['nyx_inventory']:GetItemWeight(it.item, it.amount)) or 1000
            totalWeight = totalWeight + w
        end
    end

    local model = Nyx.Pallets.ResolvePalletModel(totalWeight, itemCount)

    local palletData = {
        id = palletId,
        inventory_id = invId,
        label = palletLabel,
        model = model,
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
        heading = heading,
        routing_bucket = bucket,
        attached_vehicle_plate = nil,
        attached_slot_index = 0,
        attached_offset = nil,
        shelf_node_id = nil,
        is_sealed = false,
        is_tampered = false,
        seal_serial = nil,
        forensic_evidence_ids = {},
        created_by_citizen_id = citizenId
    }

    Nyx.Logistics.Pallets[palletId] = palletData

    local coordsJson = jsonEncodeCoords(coords)

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallets`
            (`pallet_id`, `inventory_id`, `label`, `model`, `coords`, `heading`, `routing_bucket`, `created_by_citizen_id`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { palletId, invId, palletLabel, model, coordsJson, heading, bucket, citizenId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_logs`
            (`pallet_id`, `action`, `actor_citizen_id`, `coords`, `details`)
        VALUES (?, 'created', ?, ?, ?)
    ]], { palletId, citizenId, coordsJson, json.encode({ totalWeight = totalWeight, itemCount = itemCount, model = model }) })

    TriggerClientEvent("nyx:logistics:client:palletSpawned", -1, palletData)

    return palletData
end

-- 3. Attach Pallet to Commercial Vehicle
function Nyx.Logistics.AttachPalletToVehicle(src, palletId, vehicleNetId, targetSlot)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return false, "PALLET_NOT_FOUND" end

    if pallet.attached_vehicle_plate then
        return false, "PALLET_ALREADY_ATTACHED"
    end

    local vehEntity = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId))
    if not DoesEntityExist(vehEntity) then
        return false, "VEHICLE_NOT_FOUND"
    end

    local modelHash = GetEntityModel(vehEntity)
    local profile = Nyx.Pallets.GetVehicleProfile(modelHash)
    if not profile then
        return false, "VEHICLE_NOT_PALLET_CARRIER"
    end

    local plate = GetVehicleNumberPlateText(vehEntity):gsub("^%s*(.-)%s*$", "%1")

    -- Query currently occupied slots on this vehicle plate
    local occupied = {}
    for _, p in pairs(Nyx.Logistics.Pallets) do
        if p.attached_vehicle_plate == plate and p.attached_slot_index > 0 then
            occupied[p.attached_slot_index] = true
        end
    end

    local slotIndex = tonumber(targetSlot)
    if slotIndex then
        if slotIndex < 1 or slotIndex > profile.maxSlots then
            return false, "INVALID_SLOT_INDEX"
        end
        if occupied[slotIndex] then
            return false, "SLOT_ALREADY_OCCUPIED"
        end
    else
        local availSlot, slotErr = Nyx.Pallets.FindAvailableSlot(modelHash, occupied)
        if not availSlot then
            return false, slotErr or "VEHICLE_PALLET_SLOTS_FULL"
        end
        slotIndex = availSlot
    end

    local slotData = Nyx.Pallets.GetVehicleSlotOffset(modelHash, slotIndex)
    if not slotData then
        return false, "SLOT_DATA_MISSING"
    end

    pallet.attached_vehicle_plate = plate
    pallet.attached_slot_index = slotIndex
    pallet.attached_offset = slotData.offset
    pallet.coords = nil
    pallet.shelf_node_id = nil

    MySQL.prepare.await([[
        UPDATE `nyx_logistics_pallets`
        SET `attached_vehicle_plate` = ?,
            `attached_slot_index` = ?,
            `attached_offset` = ?,
            `coords` = NULL,
            `shelf_node_id` = NULL
        WHERE `pallet_id` = ?
    ]], { plate, slotIndex, json.encode(slotData.offset), palletId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_logs`
            (`pallet_id`, `action`, `actor_citizen_id`, `vehicle_plate`, `details`)
        VALUES (?, 'loaded_to_vehicle', ?, ?, ?)
    ]], { palletId, player.citizenId, plate, json.encode({ slotIndex = slotIndex, offset = slotData.offset }) })

    TriggerClientEvent("nyx:logistics:client:palletAttached", -1, {
        palletId = palletId,
        vehicleNetId = vehicleNetId,
        plate = plate,
        slotIndex = slotIndex,
        offset = slotData.offset,
        bone = slotData.bone or 0
    })

    return true, { slotIndex = slotIndex, plate = plate, offset = slotData.offset }
end

-- 4. Detach Pallet from Vehicle
function Nyx.Logistics.DetachPalletFromVehicle(src, palletId, targetCoords, heading)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return false, "PALLET_NOT_FOUND" end

    if not pallet.attached_vehicle_plate then
        return false, "PALLET_NOT_ATTACHED"
    end

    local oldPlate = pallet.attached_vehicle_plate
    local coords = targetCoords or { x = 0.0, y = 0.0, z = 0.0 }
    heading = tonumber(heading) or 0.0

    pallet.attached_vehicle_plate = nil
    pallet.attached_slot_index = 0
    pallet.attached_offset = nil
    pallet.coords = coords
    pallet.heading = heading

    local coordsJson = jsonEncodeCoords(coords)

    MySQL.prepare.await([[
        UPDATE `nyx_logistics_pallets`
        SET `attached_vehicle_plate` = NULL,
            `attached_slot_index` = 0,
            `attached_offset` = NULL,
            `coords` = ?,
            `heading` = ?
        WHERE `pallet_id` = ?
    ]], { coordsJson, heading, palletId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_logs`
            (`pallet_id`, `action`, `actor_citizen_id`, `vehicle_plate`, `coords`, `details`)
        VALUES (?, 'unloaded_from_vehicle', ?, ?, ?, ?)
    ]], { palletId, player.citizenId, oldPlate, coordsJson, json.encode({ heading = heading }) })

    TriggerClientEvent("nyx:logistics:client:palletDetached", -1, {
        palletId = palletId,
        coords = coords,
        heading = heading
    })

    return true, { palletId = palletId, coords = coords, heading = heading }
end

-- 5. Seal / Unseal Pallet
function Nyx.Logistics.SealPallet(src, palletId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return false, "PALLET_NOT_FOUND" end

    if pallet.is_sealed then
        return false, "PALLET_ALREADY_SEALED"
    end

    -- Validate that pallet has items
    local inv = exports['nyx_inventory']:GetInventory(pallet.inventory_id)
    local items = inv and inv:getItems() or {}
    local itemCount = 0
    local totalWeight = 0
    for _, it in pairs(items) do
        itemCount = itemCount + 1
        local w = exports['nyx_inventory']:GetItemWeight(it.item_id, it.amount)
        totalWeight = totalWeight + w
    end

    local canSeal, err = Nyx.Pallets.CanSealPallet(itemCount, totalWeight)
    if not canSeal then
        return false, err or "CANNOT_SEAL_PALLET"
    end

    local sealSerial = Nyx.Pallets.GenerateSealSerial(palletId, os.time())
    pallet.is_sealed = true
    pallet.is_tampered = false
    pallet.seal_serial = sealSerial
    pallet.sealed_at = os.time()
    pallet.sealed_by_citizen_id = player.citizenId

    MySQL.prepare.await([[
        UPDATE `nyx_logistics_pallets`
        SET `is_sealed` = 1,
            `is_tampered` = 0,
            `seal_serial` = ?,
            `sealed_at` = CURRENT_TIMESTAMP,
            `sealed_by_citizen_id` = ?
        WHERE `pallet_id` = ?
    ]], { sealSerial, player.citizenId, palletId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_logs`
            (`pallet_id`, `action`, `actor_citizen_id`, `details`)
        VALUES (?, 'sealed', ?, ?)
    ]], { palletId, player.citizenId, json.encode({ sealSerial = sealSerial, itemCount = itemCount, totalWeight = totalWeight }) })

    TriggerClientEvent("nyx:logistics:client:palletSealUpdated", -1, palletId, true, sealSerial)

    return true, { palletId = palletId, isSealed = true, sealSerial = sealSerial }
end

function Nyx.Logistics.UnsealPallet(src, palletId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return false, "PALLET_NOT_FOUND" end

    if not pallet.is_sealed then
        return false, "PALLET_ALREADY_UNSEALED"
    end

    pallet.is_sealed = false

    MySQL.prepare.await([[
        UPDATE `nyx_logistics_pallets`
        SET `is_sealed` = 0
        WHERE `pallet_id` = ?
    ]], { palletId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_logs`
            (`pallet_id`, `action`, `actor_citizen_id`)
        VALUES (?, 'unsealed', ?)
    ]], { palletId, player.citizenId })

    TriggerClientEvent("nyx:logistics:client:palletSealUpdated", -1, palletId, false, nil)

    return true, { palletId = palletId, isSealed = false }
end

-- 5b. Breach Sealed Freight Pallet (Crowbar Prying & Forensic Contamination)
function Nyx.Logistics.BreachPallet(src, palletId, toolItem)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return false, "PALLET_NOT_FOUND" end

    if not pallet.is_sealed then
        return false, "PALLET_NOT_SEALED"
    end

    toolItem = toolItem or "tool_crowbar"
    if not Nyx.Pallets.BreachTools[toolItem] then
        toolItem = "tool_crowbar"
    end

    local invId = "citizen:" .. player.citizenId

    -- Verify player possesses required prying tool
    local hasTool = false
    local toolItemData = nil
    if exports['nyx_inventory'] then
        if exports['nyx_inventory'].HasItem and exports['nyx_inventory']:HasItem(invId, toolItem, 1) then
            hasTool = true
        elseif exports['nyx_inventory'].HasItem and exports['nyx_inventory']:HasItem(invId, "weapon_crowbar", 1) then
            hasTool = true
            toolItem = "weapon_crowbar"
        end

        if hasTool and exports['nyx_inventory'].GetFirstItem then
            toolItemData = exports['nyx_inventory']:GetFirstItem(invId, toolItem)
        end
    else
        hasTool = true
    end

    if not hasTool then
        return false, "MISSING_BREACH_TOOL"
    end

    local toolDurability = (toolItemData and toolItemData.metadata and toolItemData.metadata.durability) or 100.0
    local toolSerial = (toolItemData and toolItemData.metadata and toolItemData.metadata.toolSerial) or string.format("CRW-%06d", math.random(100000, 999999))

    -- Check glove status for forensic fingerprint immunity
    local hasGloves = false
    if player:getMetadata("glovesEquipped") == true then
        hasGloves = true
    elseif exports['nyx_inventory'] and exports['nyx_inventory'].HasItem then
        if exports['nyx_inventory']:HasItem(invId, "latex_gloves", 1) or exports['nyx_inventory']:HasItem(invId, "nitrile_gloves", 1) then
            hasGloves = true
        end
    end

    -- Check trade union membership for mechanical leverage buff
    local isUnionMember = false
    if exports['nyx_factions'] and exports['nyx_factions'].IsCitizenInUnion then
        isUnionMember = exports['nyx_factions']:IsCitizenInUnion(player.citizenId, "union:transport_workers")
    end

    -- Calculate physical breach outcome
    local outcome = Nyx.Pallets.CalculateBreachOutcome(toolItem, toolDurability, hasGloves, isUnionMember)

    -- Apply tool wear / breakage
    if exports['nyx_inventory'] then
        if outcome.isBroken then
            exports['nyx_inventory']:RemoveItem(invId, toolItem, 1)
            TriggerClientEvent("nyx:core:client:notify", src, "A feszítővas elpattant a fém zárópánt feszítése közben!", "error")
        else
            if toolItemData and toolItemData.slot and exports['nyx_inventory'].SetItemMetadata then
                toolItemData.metadata = toolItemData.metadata or {}
                toolItemData.metadata.durability = outcome.remainingDurability
                toolItemData.metadata.toolSerial = toolSerial
                exports['nyx_inventory']:SetItemMetadata(invId, toolItemData.slot, toolItemData.metadata)
            end
        end
    end

    -- Resolve coordinates
    local pPos = player:getPosition()
    local palletCoords = pallet.coords or { x = pPos.x, y = pPos.y, z = pPos.z }
    local coordsJson = jsonEncodeCoords(palletCoords)

    -- Audit failure if roll failed
    if not outcome.success then
        local auditUuid = string.format("pba_%x%04d", os.time(), math.random(1000, 9999))
        MySQL.prepare.await([[
            INSERT INTO `nyx_logistics_pallet_breach_audits`
                (`audit_uuid`, `pallet_id`, `citizen_id`, `tool_used`, `tool_serial`, `success`,
                 `alarm_triggered`, `dna_left`, `fingerprint_left`, `toolmark_left`, `coords`, `notes`)
            VALUES (?, ?, ?, ?, ?, 0, ?, 0, 0, 1, ?, 'Failed breach attempt')
        ]], { auditUuid, palletId, player.citizenId, toolItem, toolSerial, outcome.alarmTriggered and 1 or 0, coordsJson })

        return false, "BREACH_ATTEMPT_FAILED", outcome
    end

    -- Success State: Pallet seal severed and opened
    pallet.is_sealed = false
    pallet.is_tampered = true
    pallet.breached_at = os.time()
    pallet.breached_by_citizen_id = player.citizenId
    pallet.tamper_tool = toolItem

    local evidenceRecords = {}

    -- 1. Register microscopic toolmark striation evidence in nyx_judiciary
    local toolmarkHash = Nyx.Pallets.DetermineToolmarkHash(toolSerial, player.citizenId, palletCoords)
    if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterToolmarkEvent then
        local tmId, tmHash = exports['nyx_judiciary']:RegisterToolmarkEvent(src, toolItem, "severed_steel_pallet_banding", palletCoords, toolSerial)
        if tmId then
            evidenceRecords[#evidenceRecords + 1] = { type = "toolmark", id = tmId, hash = tmHash or toolmarkHash }
        end
    else
        evidenceRecords[#evidenceRecords + 1] = { type = "toolmark", id = "tm_" .. palletId, hash = toolmarkHash }
    end

    -- 2. Register latent fingerprints if operating without gloves
    if outcome.fingerprintLeft then
        if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterFingerprintEvent then
            local fpId, fpHash = exports['nyx_judiciary']:RegisterFingerprintEvent(src, "pallet_tamper_seal_casing", palletCoords)
            if fpId then
                evidenceRecords[#evidenceRecords + 1] = { type = "fingerprint", id = fpId, hash = fpHash }
            end
        end
    end

    -- 3. Register biological DNA / blood if laceration injury occurred
    if outcome.dnaLeft then
        if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterTraumaEvent then
            local blId, blHash = exports['nyx_judiciary']:RegisterTraumaEvent(src, src, "slashing", palletCoords)
            if blId then
                evidenceRecords[#evidenceRecords + 1] = { type = "blood", id = blId, hash = blHash }
            end
        end
        TriggerClientEvent("nyx:core:client:notify", src, string.format("A feszítővas megcsúszott a fém szalagon! Kézfejsérülés (-%d HP).", outcome.lacerationDamage), "error")
    end

    pallet.forensic_evidence_ids = evidenceRecords

    -- 4. Commercial Alarm & MDT Dispatch Trigger
    if outcome.alarmTriggered then
        if exports['nyx_mdt'] and exports['nyx_mdt'].CreateDispatchCall then
            exports['nyx_mdt']:CreateDispatchCall({
                code = "10-31",
                title = "Ipari Teheráru / Raklap Felfeszítés",
                message = string.format("Riasztó rezgésérzékelő aktiválódott: leplombált raklap (#%s) feltörve feszítővassal.", palletId),
                coords = palletCoords,
                priority = 2,
                caller = "CIVIC_AUTOMATED_SECURITY"
            })
        end
    end

    -- Commit to Database
    local evidenceJson = json.encode(evidenceRecords)
    MySQL.prepare.await([[
        UPDATE `nyx_logistics_pallets`
        SET `is_sealed` = 0,
            `is_tampered` = 1,
            `breached_at` = CURRENT_TIMESTAMP,
            `breached_by_citizen_id` = ?,
            `tamper_tool` = ?,
            `forensic_evidence_ids` = ?
        WHERE `pallet_id` = ?
    ]], { player.citizenId, toolItem, evidenceJson, palletId })

    local auditUuid = string.format("pba_%x%04d", os.time(), math.random(1000, 9999))
    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_breach_audits`
            (`audit_uuid`, `pallet_id`, `citizen_id`, `tool_used`, `tool_serial`, `success`,
             `alarm_triggered`, `dna_left`, `fingerprint_left`, `toolmark_left`, `evidence_hashes`, `coords`, `notes`)
        VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, 1, ?, ?, 'Successful crowbar breach')
    ]], {
        auditUuid,
        palletId,
        player.citizenId,
        toolItem,
        toolSerial,
        outcome.alarmTriggered and 1 or 0,
        outcome.dnaLeft and 1 or 0,
        outcome.fingerprintLeft and 1 or 0,
        evidenceJson,
        coordsJson
    })

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_logs`
            (`pallet_id`, `action`, `actor_citizen_id`, `coords`, `details`)
        VALUES (?, 'breached', ?, ?, ?)
    ]], { palletId, player.citizenId, coordsJson, json.encode({ tool = toolItem, toolSerial = toolSerial, outcome = outcome }) })

    -- Synchronize with clients
    TriggerClientEvent("nyx:logistics:client:palletSealUpdated", -1, palletId, false, nil)
    TriggerClientEvent("nyx:logistics:client:palletBreached", -1, {
        palletId = palletId,
        coords = palletCoords,
        toolItem = toolItem,
        outcome = outcome
    })

    return true, {
        palletId = palletId,
        isBreached = true,
        outcome = outcome,
        evidence = evidenceRecords,
        sealSerial = pallet.seal_serial
    }
end

-- 5c. Inspect Pallet Forensics (Forensic Investigator Analysis)
function Nyx.Logistics.InspectPalletForensics(src, palletId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return false, "PALLET_NOT_FOUND" end

    local statusBadge = Nyx.Pallets.FormatPalletStatusBadge(pallet)
    local result = {
        palletId = pallet.id,
        label = pallet.label,
        statusBadge = statusBadge,
        isSealed = pallet.is_sealed,
        isTampered = pallet.is_tampered,
        sealSerial = pallet.seal_serial,
        sealedAt = pallet.sealed_at,
        sealedBy = pallet.sealed_by_citizen_id,
        breachedAt = pallet.breached_at,
        breachedBy = pallet.breached_by_citizen_id,
        tamperTool = pallet.tamper_tool,
        evidenceMarkers = pallet.forensic_evidence_ids or {}
    }

    return true, result
end


-- 6. Snap Pallet to Warehouse Shelf Node
function Nyx.Logistics.SnapPalletToShelf(src, palletId, shelfNodeId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return false, "PALLET_NOT_FOUND" end

    if pallet.attached_vehicle_plate then
        return false, "CANNOT_SNAP_ATTACHED_PALLET"
    end

    -- Reserve shelf node via nyx_logistics warehouse subsystem
    if exports['nyx_logistics'] and exports['nyx_logistics'].SetShelfNodeOccupant then
        local okReserve, resErr = exports['nyx_logistics']:SetShelfNodeOccupant(shelfNodeId, pallet.inventory_id)
        if not okReserve then
            return false, resErr or "SHELF_NODE_UNAVAILABLE"
        end
    end

    pallet.shelf_node_id = shelfNodeId
    pallet.coords = nil

    MySQL.prepare.await([[
        UPDATE `nyx_logistics_pallets`
        SET `shelf_node_id` = ?, `coords` = NULL
        WHERE `pallet_id` = ?
    ]], { shelfNodeId, palletId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_logistics_pallet_logs`
            (`pallet_id`, `action`, `actor_citizen_id`, `details`)
        VALUES (?, 'attached_to_shelf', ?, ?)
    ]], { palletId, player.citizenId, json.encode({ shelfNodeId = shelfNodeId }) })

    return true, { palletId = palletId, shelfNodeId = shelfNodeId }
end

-- 7. Query Pallet State
function Nyx.Logistics.GetPallet(palletId)
    return Nyx.Logistics.Pallets[palletId]
end

function Nyx.Logistics.GetAllPallets()
    return Nyx.Logistics.Pallets
end

-- ----------------------------------------------------------------------------
-- RPC Endpoints
-- ----------------------------------------------------------------------------
Nyx.RPC.Register("logistics:createPallet", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local coords = payload and payload.coords
    local heading = payload and payload.heading or 0.0
    local bucket = payload and payload.bucket or 0
    local label = payload and payload.label

    local pallet = Nyx.Logistics.CreateFreightPallet(coords, heading, bucket, nil, player.citizenId, label)
    return { success = true, pallet = pallet }
end)

Nyx.RPC.Register("logistics:attachPalletToVehicle", function(src, payload)
    local palletId = payload and payload.palletId
    local vehicleNetId = payload and payload.vehicleNetId
    local targetSlot = payload and payload.targetSlot

    local ok, resOrErr = Nyx.Logistics.AttachPalletToVehicle(src, palletId, vehicleNetId, targetSlot)
    if not ok then
        return { success = false, error = resOrErr }
    end
    return { success = true, data = resOrErr }
end)

Nyx.RPC.Register("logistics:detachPalletFromVehicle", function(src, payload)
    local palletId = payload and payload.palletId
    local coords = payload and payload.coords
    local heading = payload and payload.heading or 0.0

    local ok, resOrErr = Nyx.Logistics.DetachPalletFromVehicle(src, palletId, coords, heading)
    if not ok then
        return { success = false, error = resOrErr }
    end
    return { success = true, data = resOrErr }
end)

Nyx.RPC.Register("logistics:sealPallet", function(src, palletId)
    local ok, resOrErr = Nyx.Logistics.SealPallet(src, palletId)
    if not ok then return { success = false, error = resOrErr } end
    return { success = true, data = resOrErr }
end)

Nyx.RPC.Register("logistics:unsealPallet", function(src, palletId)
    local ok, resOrErr = Nyx.Logistics.UnsealPallet(src, palletId)
    if not ok then return { success = false, error = resOrErr } end
    return { success = true, data = resOrErr }
end)

Nyx.RPC.Register("logistics:snapPalletToShelf", function(src, payload)
    local palletId = payload and payload.palletId
    local shelfNodeId = payload and payload.shelfNodeId

    local ok, resOrErr = Nyx.Logistics.SnapPalletToShelf(src, palletId, shelfNodeId)
    if not ok then return { success = false, error = resOrErr } end
    return { success = true, data = resOrErr }
end)

Nyx.RPC.Register("logistics:getPalletState", function(src, palletId)
    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return nil, "PALLET_NOT_FOUND" end

    local inv = exports['nyx_inventory']:GetInventory(pallet.inventory_id)
    return {
        pallet = pallet,
        snapshot = inv and inv:getSnapshot() or nil
    }
end)

Nyx.RPC.Register("logistics:packItemsToPallet", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local palletId = payload and payload.palletId
    local sourceInvId = payload and payload.sourceInventoryId or ("citizen:" .. player.citizenId)
    local itemId = payload and payload.itemId
    local amount = math.max(1, tonumber(payload and payload.amount) or 1)

    local pallet = Nyx.Logistics.Pallets[palletId]
    if not pallet then return { success = false, error = "PALLET_NOT_FOUND" } end

    if pallet.is_sealed then
        return { success = false, error = "PALLET_IS_SEALED" }
    end

    local okLock, resOrErr = exports['nyx_inventory']:WithDualLock(sourceInvId, pallet.inventory_id, function()
        local srcInv = exports['nyx_inventory']:GetInventory(sourceInvId)
        local palInv = exports['nyx_inventory']:GetInventory(pallet.inventory_id)

        if not srcInv or not palInv then
            return false, "INVENTORY_NOT_FOUND"
        end

        local itemWeight = exports['nyx_inventory']:GetItemWeight(itemId, amount)
        if not Nyx.Pallets.CanHoldWeight(palInv:getTotalWeight(), itemWeight) then
            return false, "PALLET_OVERWEIGHT"
        end

        local removed = exports['nyx_inventory']:RemoveItem(sourceInvId, itemId, amount)
        if not removed then
            return false, "INSUFFICIENT_ITEMS"
        end

        local added = exports['nyx_inventory']:AddItem(pallet.inventory_id, itemId, amount, {
            palletId = palletId,
            packedBy = player.citizenId,
            packedAt = os.time()
        })

        if not added then
            exports['nyx_inventory']:AddItem(sourceInvId, itemId, amount)
            return false, "PALLET_FULL"
        end

        -- Update model based on new total weight
        local newWeight = palInv:getTotalWeight()
        local newCount = palInv:getItemCount()
        local newModel = Nyx.Pallets.ResolvePalletModel(newWeight, newCount)

        if newModel ~= pallet.model then
            pallet.model = newModel
            MySQL.prepare("UPDATE `nyx_logistics_pallets` SET `model` = ? WHERE `pallet_id` = ?", { newModel, palletId })
            TriggerClientEvent("nyx:logistics:client:palletModelUpdated", -1, palletId, newModel)
        end

        return true, { newWeight = newWeight, newCount = newCount, model = pallet.model }
    end)

    if not okLock or not resOrErr then
        return { success = false, error = resOrErr or "LOCK_COLLISION" }
    end

    return { success = true, data = resOrErr }
end)

Nyx.RPC.Register("logistics:breachPallet", function(src, payload)
    local okPayload, payloadErr = Nyx.Pallets.ValidateBreachPayload(payload)
    if not okPayload then
        return { success = false, error = payloadErr }
    end

    local palletId = payload.palletId
    local toolItem = payload.toolItem or "tool_crowbar"

    local ok, resOrErr, extra = Nyx.Logistics.BreachPallet(src, palletId, toolItem)
    if not ok then
        return { success = false, error = resOrErr, data = extra }
    end
    return { success = true, data = resOrErr }
end)

Nyx.RPC.Register("logistics:inspectPalletForensics", function(src, palletId)
    local ok, resOrErr = Nyx.Logistics.InspectPalletForensics(src, palletId)
    if not ok then
        return { success = false, error = resOrErr }
    end
    return { success = true, data = resOrErr }
end)

