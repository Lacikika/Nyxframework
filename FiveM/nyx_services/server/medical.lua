--[[
    Nyxframework: nyx_services
    File: server/medical.lua
    Description: Physical consumable-dependent healthcare engine, hospital inventory tracking,
                 shortage penalties, and automated freight restock contract dispatching.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.Hospitals = {}

-- 1. Load Hospital Medical Facilities
function Nyx.Services.LoadHospitals()
    local rows = MySQL.query.await("SELECT * FROM `nyx_services_hospitals`")
    if rows then
        for _, r in ipairs(rows) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(r.coords) == "string" then
                local ok, parsed = pcall(json.decode, r.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(r.coords) == "table" then
                coords = r.coords
            end

            Nyx.Services.Hospitals[r.hospital_id] = {
                id = r.hospital_id,
                label = r.label,
                coords = vector3(coords.x, coords.y, coords.z),
                substationId = r.substation_id,
                traumaKits = tonumber(r.trauma_kits) or 0,
                sterilePlasma = tonumber(r.sterile_plasma) or 0,
                surgicalPacks = tonumber(r.surgical_packs) or 0,
                status = r.status or "optimal"
            }
        end
        if Config.Debug then
            print(string.format("^2[Nyx:Services]^7 Loaded %d hospital facilities from database.^7", #rows))
        end
    end
end

-- 2. Evaluate Hospital Status and Trigger Logistics Contracts upon Shortages
local function evaluateHospitalStatus(h)
    local degThreshold = Config.Healthcare.ShortageThresholds.Degraded or 15
    local critThreshold = Config.Healthcare.ShortageThresholds.Critical or 5

    local prevStatus = h.status
    if h.traumaKits <= critThreshold or h.sterilePlasma <= critThreshold then
        h.status = "critical_shortage"
    elseif h.traumaKits <= degThreshold or h.sterilePlasma <= degThreshold then
        h.status = "degraded"
    else
        h.status = "optimal"
    end

    if h.status ~= prevStatus then
        MySQL.prepare.await([[
            UPDATE `nyx_services_hospitals`
            SET `status` = ?
            WHERE `hospital_id` = ?
        ]], { h.status, h.id })
    end

    -- If critical, dispatch emergency medical hauling contract via nyx_logistics
    if h.status == "critical_shortage" then
        local destShelfId = "hospital:" .. h.id
        local existing = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_logistics_contracts`
            WHERE `dest_shelf_id` = ? AND `status` IN ('available', 'in_transit')
        ]], { destShelfId })

        if existing == 0 then
            local qty = Config.Healthcare.FreightRestockContract.Quantity or 25
            local payout = Config.Healthcare.FreightRestockContract.PayoutPerUnit or 120.00

            MySQL.prepare.await([[
                INSERT INTO `nyx_logistics_contracts`
                    (`source_inventory_id`, `dest_shelf_id`, `item_id`, `quantity`, `payout_per_unit`, `issuer_faction_id`, `status`)
                VALUES (?, ?, ?, ?, ?, 'dept:ems', 'available')
            ]], {
                "stash:chemical_refinery",
                destShelfId,
                "med_plasma",
                qty,
                payout
            })

            TriggerClientEvent("nyx:logistics:client:newContractAvailable", -1, destShelfId, qty, payout)
            print(string.format("^1[Nyx:Services] HOSPITAL CRITICAL SHORTAGE: '%s' triggered emergency medical contract for %dx Plasma!^7",
                h.id, qty))
        end
    end
end

-- 3. Process Patient Revival and Consume Medical Inventory
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

    local penaltySeconds = Config.Healthcare.RespawnTimePenalties[h.status] or 0
    if not isPowered then
        penaltySeconds = penaltySeconds + 30 -- Emergency generator delay
    end

    -- Verify surgical capability if requested
    if requiresSurgery and h.surgicalPacks <= 0 then
        return false, "SURGICAL_UNAVAILABLE_SUPPLY_DEPLETED"
    end

    -- Deduct consumables if in stock
    if h.sterilePlasma > 0 and h.traumaKits > 0 then
        h.sterilePlasma = h.sterilePlasma - 1
        h.traumaKits = h.traumaKits - 1
        if requiresSurgery and h.surgicalPacks > 0 then
            h.surgicalPacks = h.surgicalPacks - 1
        end

        MySQL.prepare.await([[
            UPDATE `nyx_services_hospitals`
            SET `sterile_plasma` = ?,
                `trauma_kits` = ?,
                `surgical_packs` = ?
            WHERE `hospital_id` = ?
        ]], { h.sterilePlasma, h.traumaKits, h.surgicalPacks, hospitalId })

        evaluateHospitalStatus(h)
    else
        -- Zero-stock fallback: Maximum penalty delay applied
        penaltySeconds = penaltySeconds + 60
    end

    return true, {
        hospitalId = hospitalId,
        respawnDelay = penaltySeconds,
        facilityStatus = h.status,
        isGridPowered = isPowered,
        remainingSupplies = {
            plasma = h.sterilePlasma,
            traumaKits = h.traumaKits,
            surgicalPacks = h.surgicalPacks
        }
    }
end

-- 4. Restock Hospital Medical Reserves from Player Freight
function Nyx.Services.RestockHospital(src, hospitalId, supplyItem, amount)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local h = Nyx.Services.Hospitals[hospitalId]
    if not h then return false, "HOSPITAL_NOT_FOUND" end

    local count = math.max(1, math.floor(tonumber(amount) or 1))
    local invId = "citizen:" .. player.citizenId

    local validItems = {
        ['med_plasma'] = "sterilePlasma",
        ['med_firstaid'] = "traumaKits",
        ['med_surgical_pack'] = "surgicalPacks"
    }

    local targetProp = validItems[supplyItem]
    if not targetProp then
        return false, "INVALID_MEDICAL_SUPPLY_ITEM"
    end

    local removed, remErr = exports['nyx_inventory']:RemoveItem(invId, supplyItem, count)
    if not removed then
        return false, "INSUFFICIENT_ITEMS_IN_INVENTORY"
    end

    h[targetProp] = h[targetProp] + count

    MySQL.prepare.await([[
        UPDATE `nyx_services_hospitals`
        SET `sterile_plasma` = ?,
            `trauma_kits` = ?,
            `surgical_packs` = ?
        WHERE `hospital_id` = ?
    ]], { h.sterilePlasma, h.traumaKits, h.surgicalPacks, hospitalId })

    evaluateHospitalStatus(h)

    -- If restock fulfills open contract, fulfill it
    local destShelfId = "hospital:" .. hospitalId
    MySQL.prepare.await([[
        UPDATE `nyx_logistics_contracts`
        SET `status` = 'fulfilled'
        WHERE `dest_shelf_id` = ? AND `status` IN ('available', 'in_transit')
    ]], { destShelfId })

    return true, {
        hospitalId = hospitalId,
        restockedItem = supplyItem,
        newQuantity = h[targetProp],
        status = h.status
    }
end

-- 5. Query specific hospital
function Nyx.Services.GetHospital(hospitalId)
    return Nyx.Services.Hospitals[hospitalId]
end

-- 6. Query all hospitals
function Nyx.Services.GetAllHospitals()
    return Nyx.Services.Hospitals
end
