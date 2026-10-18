--[[
    Nyxframework: nyx_properties
    File: server/main.lua
    Description: Authoritative Property Engine, Routing Bucket Isolation,
                 Deed Transfers, Stash Initialization, Land Footprint & Utility Meter Binding.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}
Nyx.Properties.Loaded = {} -- [property_id] = propertyData

-- Standardized Bridge to nyx_core
Nyx.GetPlayer = Nyx.GetPlayer or function(src)
    if exports['nyx_core'] and exports['nyx_core'].GetPlayer then
        return exports['nyx_core']:GetPlayer(src)
    end
    return nil
end

Nyx.GetPlayerByCitizenId = Nyx.GetPlayerByCitizenId or function(citizenId)
    if exports['nyx_core'] and exports['nyx_core'].GetPlayerByCitizenId then
        return exports['nyx_core']:GetPlayerByCitizenId(citizenId)
    end
    return nil
end

Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
            exports['nyx_core']:RegisterRPC(route, handler)
        end
    end
}

-- 1. Initialize Default Properties and Load Database State
MySQL.ready(function()
    -- Seed default properties if table empty
    local count = MySQL.scalar.await("SELECT COUNT(*) FROM `nyx_properties`")
    if count == 0 and Config.DefaultProperties then
        for i, prop in ipairs(Config.DefaultProperties) do
            local stashId = string.format("property:%s:main", prop.code)
            local meterId = string.format("meter:prop:%s", prop.code)
            local bucketId = 1000 + i -- Virtual routing bucket per property interior
            local landArea = prop.landAreaSqm or 150.00
            local zone = prop.zoneId or "zone_ls_metro"
            local initialCond = prop.initialCondition or 100.00

            MySQL.insert.await([[
                INSERT INTO `nyx_properties`
                    (`property_code`, `label`, `type`, `price`, `millage_tax_rate`,
                     `land_area_sqm`, `zone_id`, `maintenance_condition`,
                     `entrance_coords`, `interior_coords`, `routing_bucket`,
                     `stash_inventory_id`, `utility_meter_id`, `linked_substation_id`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                prop.code,
                prop.label,
                prop.type,
                prop.price,
                prop.millageRate,
                landArea,
                zone,
                initialCond,
                json.encode(prop.entrance),
                json.encode(prop.interior),
                bucketId,
                stashId,
                meterId,
                prop.linkedSubstation or "substation_central"
            })
        end
        print("^2[Nyx:Properties] Seeded default property registry into database.^7")
    end

    -- Load all properties into memory
    local rows = MySQL.query.await("SELECT * FROM `nyx_properties`")
    if rows then
        -- Performance: Batch pre-load all real estate property stashes in one array query
        local stashIds = {}
        for _, r in ipairs(rows) do
            local stashId = r.stash_inventory_id or string.format("property:%s:main", r.property_code)
            if stashId and stashId ~= "" then
                stashIds[#stashIds + 1] = stashId
            end
        end

        if #stashIds > 0 and exports['nyx_inventory'] and exports['nyx_inventory'].BatchLoadInventories then
            exports['nyx_inventory']:BatchLoadInventories(stashIds, 'stash')
        end

        for _, r in ipairs(rows) do
            local propData = {
                id = r.property_id,
                code = r.property_code,
                label = r.label,
                type = r.type,
                ownerCitizenId = r.owner_citizen_id,
                price = tonumber(r.price) or 0.00,
                millageRate = tonumber(r.millage_tax_rate) or 0.0150,
                landAreaSqm = tonumber(r.land_area_sqm) or 150.00,
                maintenanceCondition = tonumber(r.maintenance_condition) or 100.00,
                lastMaintenanceAt = r.last_maintenance_at,
                delinquencyTier = tonumber(r.delinquency_tier) or 0,
                delinquentAmount = tonumber(r.delinquent_amount) or 0.00,
                consecutiveMissedCycles = tonumber(r.consecutive_missed_cycles) or 0,
                zoneId = r.zone_id or "zone_ls_metro",
                reclaimedForAuction = (r.reclaimed_for_auction == 1),
                entrance = json.decode(r.entrance_coords),
                interior = json.decode(r.interior_coords),
                routingBucket = r.routing_bucket,
                isLocked = (r.is_locked == 1),
                stashId = r.stash_inventory_id,
                meterId = r.utility_meter_id,
                linkedSubstation = r.linked_substation_id
            }

            Nyx.Properties.Loaded[r.property_id] = propData

            -- Register stash in nyx_inventory
            if exports['nyx_inventory'] and exports['nyx_inventory'].RegisterContainer then
                local maxKg = (r.type == 'industrial') and 500000 or ((r.type == 'commercial') and 250000 or 100000)
                local maxSlots = (r.type == 'industrial') and 100 or ((r.type == 'commercial') and 80 or 50)
                exports['nyx_inventory']:RegisterContainer(propData.stashId, r.label .. " Széf", maxKg, maxSlots)
            end

            -- Register meter in nyx_services if owned
            if r.owner_citizen_id and exports['nyx_services'] and exports['nyx_services'].RegisterMeter then
                exports['nyx_services']:RegisterMeter(propData.meterId, r.owner_citizen_id, propData.linkedSubstation, r.type)
            end
        end
        print(string.format("^2[Nyx:Properties] Loaded %d real estate properties into server memory.^7", #rows))
    end
end)

-- 2. RPC: Query Properties List
exports['nyx_core']:RegisterRPC("properties:getProperties", function(src, filter)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local citizenId = player.citizenId
    local result = {}

    for _, p in pairs(Nyx.Properties.Loaded) do
        local hasKey, tier = Nyx.Properties.HasKey(p.id, citizenId)
        result[#result + 1] = {
            id = p.id,
            code = p.code,
            label = p.label,
            type = p.type,
            price = p.price,
            landAreaSqm = p.landAreaSqm,
            maintenanceCondition = p.maintenanceCondition,
            delinquencyTier = p.delinquencyTier,
            delinquentAmount = p.delinquentAmount,
            consecutiveMissedCycles = p.consecutiveMissedCycles,
            zoneId = p.zoneId,
            reclaimedForAuction = p.reclaimedForAuction,
            owner = p.ownerCitizenId,
            isOwnedByMe = (p.ownerCitizenId == citizenId),
            hasKey = hasKey,
            keyTier = tier or 0,
            isLocked = p.isLocked,
            entrance = p.entrance
        }
    end

    return { success = true, properties = result }
end)

-- 3. RPC: Purchase Property Deed
exports['nyx_core']:RegisterRPC("properties:buyProperty", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    if prop.reclaimedForAuction then
        return { success = false, error = "PROPERTY_IN_AUCTION" }
    end

    if prop.ownerCitizenId ~= nil then
        return { success = false, error = "PROPERTY_ALREADY_OWNED" }
    end

    local bankBal = player:getWallet("bank") or 0
    if bankBal < prop.price then
        return { success = false, error = "INSUFFICIENT_FUNDS" }
    end

    -- Deduct money from buyer and credit municipal treasury
    player:removeMoney("bank", prop.price, string.format("Property Deed Purchase: %s", prop.label))
    
    local treasuryAccount = Config.Millage.TreasuryAccount or "gov:city:master"
    if exports['nyx_treasury'] and exports['nyx_treasury'].EnsureAccount then
        exports['nyx_treasury']:EnsureAccount(treasuryAccount, "City Treasury", "department", 0.00)
    end

    MySQL.prepare([[
        UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?
    ]], { prop.price, treasuryAccount })

    -- Update database ownership
    MySQL.prepare([[
        UPDATE `nyx_properties`
        SET `owner_citizen_id` = ?,
            `last_tax_billed_at` = NOW(),
            `delinquency_tier` = 0,
            `delinquent_amount` = 0.00,
            `consecutive_missed_cycles` = 0,
            `maintenance_condition` = 100.00
        WHERE `property_id` = ?
    ]], { player.citizenId, propertyId })

    -- Issue Tier 4 (Owner) RFID Key
    MySQL.prepare([[
        INSERT INTO `nyx_property_keys` (`property_id`, `citizen_id`, `tier`, `label`)
        VALUES (?, ?, 4, 'Tulajdonosi Mesterkártya')
        ON DUPLICATE KEY UPDATE `tier` = 4
    ]], { propertyId, player.citizenId })

    -- Audit trail
    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
            (`property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
        VALUES (?, 'PURCHASE', ?, ?, 'Full deed ownership acquired')
    ]], { propertyId, player.citizenId, prop.price })

    -- Update in-memory state
    prop.ownerCitizenId = player.citizenId
    prop.delinquencyTier = 0
    prop.delinquentAmount = 0.00
    prop.consecutiveMissedCycles = 0
    prop.maintenanceCondition = 100.00

    -- Register utility meter in nyx_services
    if exports['nyx_services'] and exports['nyx_services'].RegisterMeter then
        exports['nyx_services']:RegisterMeter(prop.meterId, player.citizenId, prop.linkedSubstation, prop.type)
    end

    return { success = true, propertyId = propertyId, label = prop.label }
end)

-- 4. RPC: Enter Property Interior (Virtual Routing Bucket Isolation)
exports['nyx_core']:RegisterRPC("properties:enterProperty", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    -- Check permission
    local hasKey, tier = Nyx.Properties.HasKey(propertyId, player.citizenId)

    -- Foreclosure Sanction: Tier 3+ delinquency locks out residents (unless law enforcement tier 5)
    if prop.delinquencyTier and prop.delinquencyTier >= 3 and (not hasKey or tier < 5) then
        return { success = false, error = "PROPERTY_SEIZED_TAX_DELINQUENCY" }
    end

    -- Zero-Trust Distance Check
    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local entVec = vector3(prop.entrance.x, prop.entrance.y, prop.entrance.z)

    if #(pCoords - entVec) > 5.0 then
        return { success = false, error = "TOO_FAR_FROM_ENTRANCE" }
    end

    -- Check access permission
    if prop.isLocked and (not hasKey or tier < 2) then
        return { success = false, error = "DOOR_LOCKED" }
    end

    -- Set OneSync Virtual Routing Bucket
    SetPlayerRoutingBucket(tostring(src), prop.routingBucket)

    -- Teleport Ped into Interior
    SetEntityCoords(ped, prop.interior.x, prop.interior.y, prop.interior.z, false, false, false, true)
    if prop.interior.h then
        SetEntityHeading(ped, prop.interior.h)
    end

    -- Record utility consumption trigger (lights turned on in property)
    if exports['nyx_services'] and exports['nyx_services'].RecordConsumption then
        exports['nyx_services']:RecordConsumption(prop.meterId, 0.25, 0.05)
    end

    return {
        success = true,
        interiorCoords = prop.interior,
        routingBucket = prop.routingBucket,
        stashId = prop.stashId
    }
end)

-- 5. RPC: Exit Property Interior (Restore World Routing Bucket 0)
exports['nyx_core']:RegisterRPC("properties:exitProperty", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local intVec = vector3(prop.interior.x, prop.interior.y, prop.interior.z)

    if #(pCoords - intVec) > 8.0 then
        return { success = false, error = "TOO_FAR_FROM_EXIT" }
    end

    -- Reset to Default Shared World Routing Bucket 0
    SetPlayerRoutingBucket(tostring(src), 0)

    -- Teleport back to Street Entrance
    SetEntityCoords(ped, prop.entrance.x, prop.entrance.y, prop.entrance.z, false, false, false, true)
    if prop.entrance.h then
        SetEntityHeading(ped, prop.entrance.h)
    end

    return { success = true, entranceCoords = prop.entrance }
end)
