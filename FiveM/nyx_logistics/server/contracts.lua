--[[
    Nyxframework: nyx_logistics
    File: server/contracts.lua
    Description: Authoritative Freight Hauling Exchange, Escrow Bond Locking,
                 Dijkstra Dual-Mutex Pallet Loading/Unloading, and Lifecycle Orchestration.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.ActiveContracts = {} -- [contractId] = contractTable

-- Server RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- Restore active in-transit contracts into in-memory hot cache
MySQL.ready(function()
    local active = MySQL.query.await([[
        SELECT `contract_id`, `contract_uuid`, `contract_type`, `source_inventory_id`, `dest_inventory_id`,
               `source_coords`, `dest_coords`, `item_id`, `quantity`, `payout_per_unit`, `total_payout`,
               `escrow_deposit`, `claimed_by_char_id`, `claimed_by_citizen_id`, `status`,
               UNIX_TIMESTAMP(`expires_at`) AS `expires_at_unix`
        FROM `nyx_logistics_freight_contracts`
        WHERE `status` = 'in_transit'
    ]])

    if active then
        for _, c in ipairs(active) do
            Nyx.Logistics.ActiveContracts[c.contract_id] = {
                id = c.contract_id,
                uuid = c.contract_uuid,
                type = c.contract_type,
                sourceInv = c.source_inventory_id,
                destShelf = c.dest_inventory_id,
                sourceCoords = c.source_coords and json.decode(c.source_coords) or nil,
                destCoords = c.dest_coords and json.decode(c.dest_coords) or nil,
                itemId = c.item_id,
                quantity = c.quantity,
                payoutPerUnit = tonumber(c.payout_per_unit) or 0.0,
                totalPayout = tonumber(c.total_payout) or 0.0,
                escrowDeposit = tonumber(c.escrow_deposit) or 0.0,
                claimedByCharId = c.claimed_by_char_id,
                claimedByCitizenId = c.claimed_by_citizen_id,
                expiresAt = c.expires_at_unix or (os.time() + 1800),
                status = 'in_transit'
            }
        end
        if Config.Debug then
            print(string.format("^2[Nyx:Logistics] Restored %d in-transit freight contract(s) to memory cache.^7", #active))
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 1. Dynamic Shortage Contract Generation
-- ----------------------------------------------------------------------------
function Nyx.Logistics.CheckShortageContract(shelf, currentStock)
    local threshold = math.floor(shelf.target_capacity * (Config.ShortageContractThreshold or 0.10))

    if currentStock <= threshold then
        local existing = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_logistics_freight_contracts` 
            WHERE `dest_inventory_id` = ? AND `status` IN ('available', 'in_transit')
        ]], { shelf.inventory_id })

        if existing == 0 then
            local needed = shelf.target_capacity - currentStock
            local zone = Nyx.Logistics.GetZone and Nyx.Logistics.GetZone(shelf.zone_id)
            local zoneDemandMult = zone and zone.baseDemandMultiplier or 1.00
            local baseMultiplier = Config.DefaultFreightPayoutMultiplier or 0.35

            -- Dynamic freight payout scaling based on localized zone deficit
            local dynamicMultiplier = baseMultiplier
            if Config.DeliveryZones and Config.DeliveryZones.ShortageBountyScaling then
                local deficitRatio = math.max(0.0, (shelf.target_capacity - currentStock) / shelf.target_capacity)
                local scaleBonus = math.min(1.50, deficitRatio * zoneDemandMult)
                dynamicMultiplier = math.min(
                    Config.DeliveryZones.MaxShortageBountyMultiplier or 2.25,
                    baseMultiplier * (1.0 + scaleBonus)
                )
            end

            local payoutPerUnit = math.floor((shelf.base_price * dynamicMultiplier) * 100) / 100
            local totalPayout = math.floor((payoutPerUnit * needed) * 100) / 100
            local escrowBond = math.floor((totalPayout * (Nyx.Logistics.FreightConfig and Nyx.Logistics.FreightConfig.EscrowBondPercent or 0.15)) * 100) / 100
            local contractUuid = Nyx.RPC.GenerateNonce()

            local srcCoords = { x = 152.4, y = -3205.2, z = 5.9 }
            local dstCoords = shelf.coords or (zone and zone.coords and { x = zone.coords.x, y = zone.coords.y, z = zone.coords.z }) or { x = -48.2, y = -1757.4, z = 29.4 }

            local contractId = MySQL.insert.await([[
                INSERT INTO `nyx_logistics_freight_contracts`
                (`contract_uuid`, `contract_type`, `issuer_type`, `issuer_id`, `title`, 
                 `source_inventory_id`, `dest_inventory_id`, `source_coords`, `dest_coords`, `zone_id`,
                 `item_id`, `quantity`, `payout_per_unit`, `total_payout`, `escrow_deposit`, `status`, `deadline_seconds`)
                VALUES (?, 'shortage_auto', 'municipal_store', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'available', ?)
            ]], {
                contractUuid,
                shelf.store_id or "gov_civic_market",
                string.format("Sürgősségi Készletfeltöltés: %s [%s]", shelf.item_id, zone and zone.name or "Metro"),
                "stash:hub_central",
                shelf.inventory_id,
                json.encode(srcCoords),
                json.encode(dstCoords),
                shelf.zone_id or "zone_ls_metro",
                shelf.item_id,
                needed,
                payoutPerUnit,
                totalPayout,
                escrowBond,
                Nyx.Logistics.FreightConfig and Nyx.Logistics.FreightConfig.DefaultDeadlineSeconds or 1800
            })

            if contractId then
                MySQL.prepare([[
                    INSERT INTO `nyx_logistics_freight_audit`
                    (`contract_id`, `action`, `amount`, `debit_account`, `credit_account`, `notes`)
                    VALUES (?, 'CONTRACT_CREATED', ?, ?, ?, 'Automated shelf deficit contract generated with dynamic zone scaling')
                ]], {
                    contractId,
                    totalPayout,
                    shelf.store_id or "gov:city:master",
                    "escrow:logistics:freight"
                })

                if Config.Debug then
                    print(string.format("^3[Nyx:Logistics] Shortage contract #%d posted (%s): %dx %s ($%.2f total, $%.2f escrow)^7",
                        contractId, shelf.zone_id or "metro", needed, shelf.item_id, totalPayout, escrowBond))
                end

                TriggerClientEvent("nyx:logistics:client:newContractAvailable", -1, {
                    contractId = contractId,
                    title = string.format("Sürgősségi Szállítás: %s [%s]", shelf.item_id, zone and zone.name or "Metro"),
                    quantity = needed,
                    totalPayout = totalPayout,
                    escrowDeposit = escrowBond,
                    zoneId = shelf.zone_id or "zone_ls_metro"
                })
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 2. RPC: Query Live Freight Exchange Board
-- ----------------------------------------------------------------------------
Nyx.RPC.Register("logistics:getFreightBoard", function(src, filterType)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local query = [[
        SELECT `contract_id`, `contract_uuid`, `contract_type`, `issuer_type`, `issuer_id`, `title`,
               `source_inventory_id`, `dest_inventory_id`, `source_coords`, `dest_coords`,
               `item_id`, `quantity`, `payout_per_unit`, `total_payout`, `escrow_deposit`,
               `status`, `claimed_by_citizen_id`, `deadline_seconds`, `expires_at`, `created_at`
        FROM `nyx_logistics_freight_contracts`
        WHERE `status` = 'available' OR (`status` = 'in_transit' AND `claimed_by_citizen_id` = ?)
        ORDER BY `created_at` DESC
        LIMIT 50
    ]]

    local rows = MySQL.query.await(query, { player.citizenId })
    local parsedContracts = {}
    local activeContract = nil

    if rows then
        for _, r in ipairs(rows) do
            local item = {
                contractId = r.contract_id,
                uuid = r.contract_uuid,
                type = r.contract_type,
                title = r.title,
                sourceInv = r.source_inventory_id,
                destInv = r.dest_inventory_id,
                sourceCoords = r.source_coords and json.decode(r.source_coords) or { x = 0, y = 0, z = 0 },
                destCoords = r.dest_coords and json.decode(r.dest_coords) or { x = 0, y = 0, z = 0 },
                itemId = r.item_id,
                quantity = r.quantity,
                payoutPerUnit = tonumber(r.payout_per_unit) or 0.00,
                totalPayout = tonumber(r.total_payout) or 0.00,
                escrowDeposit = tonumber(r.escrow_deposit) or 0.00,
                status = r.status,
                isClaimedByMe = (r.claimed_by_citizen_id == player.citizenId),
                deadlineSeconds = r.deadline_seconds,
                expiresAt = r.expires_at
            }

            if item.isClaimedByMe and r.status == 'in_transit' then
                activeContract = item
            end

            parsedContracts[#parsedContracts + 1] = item
        end
    end

    return {
        success = true,
        contracts = parsedContracts,
        activeContract = activeContract
    }
end)

-- ----------------------------------------------------------------------------
-- 3. RPC: Claim Contract & Lock Escrow Collateral
-- ----------------------------------------------------------------------------
Nyx.RPC.Register("logistics:claimContract", function(src, contractId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    contractId = tonumber(contractId)
    if not contractId then return { success = false, error = "INVALID_CONTRACT_ID" } end

    -- Check if citizen already holds an active in-transit contract
    local activeCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_logistics_freight_contracts`
        WHERE `claimed_by_citizen_id` = ? AND `status` = 'in_transit'
    ]], { player.citizenId })

    if activeCount and activeCount >= (Nyx.Logistics.FreightConfig.MaxConcurrentContracts or 1) then
        return { success = false, error = "ACTIVE_CONTRACT_LIMIT" }
    end

    local contract = MySQL.single.await([[
        SELECT * FROM `nyx_logistics_freight_contracts` WHERE `contract_id` = ?
    ]], { contractId })

    if not contract then return { success = false, error = "CONTRACT_NOT_FOUND" } end
    if contract.status ~= 'available' then return { success = false, error = "CONTRACT_ALREADY_CLAIMED" } end

    local escrow = tonumber(contract.escrow_deposit) or 0.00
    local bankBal = player:getWallet("bank") or 0

    if bankBal < escrow then
        return { success = false, error = "INSUFFICIENT_ESCROW_FUNDS" }
    end

    -- Debit player escrow bond and credit municipal logistics escrow account
    if escrow > 0 then
        player:removeMoney("bank", escrow, string.format("Freight Escrow Bond: Contract #%d", contractId))
        exports['nyx_treasury']:EnsureAccount("escrow:logistics:freight", "Freight Bond Escrow Pool", "escrow", 0.00)
        MySQL.prepare([[
            UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?
        ]], { escrow, "escrow:logistics:freight" })
    end

    local nowSec = os.time()
    local expirySec = nowSec + (contract.deadline_seconds or 1800)
    local expiryDate = os.date("!%Y-%m-%d %H:%M:%S", expirySec)

    local updated = MySQL.prepare.await([[
        UPDATE `nyx_logistics_freight_contracts`
        SET `status` = 'in_transit', `claimed_by_char_id` = ?, `claimed_by_citizen_id` = ?, 
            `claimed_at` = NOW(), `expires_at` = ?
        WHERE `contract_id` = ? AND `status` = 'available'
    ]], { player.charId, player.citizenId, expiryDate, contractId })

    if not updated or updated == 0 then
        -- Refund escrow if race condition lost
        if escrow > 0 then
            player:addMoney("bank", escrow, "Escrow Refund (Claim Collision)")
        end
        return { success = false, error = "CONTRACT_ALREADY_CLAIMED" }
    end

    -- Record Audit Trail
    MySQL.prepare([[
        INSERT INTO `nyx_logistics_freight_audit`
        (`contract_id`, `action`, `carrier_citizen_id`, `amount`, `debit_account`, `credit_account`, `notes`)
        VALUES (?, 'ESCROW_LOCKED', ?, ?, ?, 'escrow:logistics:freight', 'Carrier claimed contract and deposited escrow')
    ]], {
        contractId,
        player.citizenId,
        escrow,
        string.format("char:%s:bank", player.citizenId)
    })

    -- Add to in-memory active cache
    Nyx.Logistics.ActiveContracts[contractId] = {
        id = contractId,
        uuid = contract.contract_uuid,
        type = contract.contract_type,
        sourceInv = contract.source_inventory_id,
        destShelf = contract.dest_inventory_id,
        sourceCoords = contract.source_coords and json.decode(contract.source_coords) or nil,
        destCoords = contract.dest_coords and json.decode(contract.dest_coords) or nil,
        itemId = contract.item_id,
        quantity = contract.quantity,
        payoutPerUnit = tonumber(contract.payout_per_unit) or 0.0,
        totalPayout = tonumber(contract.total_payout) or 0.0,
        escrowDeposit = escrow,
        claimedByCharId = player.charId,
        claimedByCitizenId = player.citizenId,
        claimedBySource = src,
        expiresAt = expirySec,
        status = 'in_transit'
    }

    return {
        success = true,
        contractId = contractId,
        expiresAt = expirySec,
        sourceCoords = contract.source_coords and json.decode(contract.source_coords) or nil,
        destCoords = contract.dest_coords and json.decode(contract.dest_coords) or nil
    }
end)

-- ----------------------------------------------------------------------------
-- 4. RPC: Load Freight Pallet at Source Hub (Dual Mutex Transfer)
-- ----------------------------------------------------------------------------
Nyx.RPC.Register("logistics:loadFreightPallet", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local contractId = payload and tonumber(payload.contractId)
    local vehicleNetId = payload and tonumber(payload.vehicleNetId)

    if not contractId or not vehicleNetId then
        return { success = false, error = "INVALID_PARAMETERS" }
    end

    local contract = MySQL.single.await([[
        SELECT * FROM `nyx_logistics_freight_contracts` WHERE `contract_id` = ?
    ]], { contractId })

    if not contract or contract.status ~= 'in_transit' or contract.claimed_by_citizen_id ~= player.citizenId then
        return { success = false, error = "INVALID_CONTRACT_STATE" }
    end

    -- Verify vehicle entity
    local vehEntity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehEntity) then
        return { success = false, error = "VEHICLE_NOT_FOUND" }
    end

    local modelHash = GetEntityModel(vehEntity)
    if not Nyx.Logistics.FreightConfig.CommercialVehicles[modelHash] then
        return { success = false, error = "VEHICLE_INVALID_CLASS" }
    end

    -- Proximity verification
    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local vCoords = GetEntityCoords(vehEntity)
    local srcCoords = contract.source_coords and json.decode(contract.source_coords) or nil

    if srcCoords then
        local dockVec = vector3(srcCoords.x, srcCoords.y, srcCoords.z)
        if #(pCoords - dockVec) > Nyx.Logistics.FreightConfig.MaxLoadingDistance or
           #(vCoords - dockVec) > Nyx.Logistics.FreightConfig.MaxLoadingDistance then
            return { success = false, error = "VEHICLE_OUT_OF_RANGE" }
        end
    end

    local plate = GetVehicleNumberPlateText(vehEntity):gsub("^%s*(.-)%s*$", "%1")
    local vehInvId = string.format("trunk:%s", plate)
    local sourceInvId = contract.source_inventory_id

    -- Dijkstra Dual-Mutex Lock Transfer
    local okLock, resOrErr = exports['nyx_inventory']:WithDualLock(sourceInvId, vehInvId, function()
        local srcContainer = exports['nyx_inventory']:GetContainer(sourceInvId)
        local dstContainer = exports['nyx_inventory']:GetContainer(vehInvId)

        if not srcContainer or not dstContainer then
            return false, "CONTAINER_NOT_FOUND"
        end

        local totalWeight = exports['nyx_inventory']:GetItemWeight(contract.item_id, contract.quantity)
        if not dstContainer:canHoldWeight(totalWeight) then
            return false, "CONTAINER_OVERWEIGHT"
        end

        local okRemove = exports['nyx_inventory']:RemoveItem(sourceInvId, contract.item_id, contract.quantity)
        if not okRemove then
            return false, "HUB_INVENTORY_DEPLETED"
        end

        local okAdd = exports['nyx_inventory']:AddItem(vehInvId, contract.item_id, contract.quantity, {
            freightContractId = contractId,
            issuer = contract.issuer_id,
            carrier = player.citizenId
        })

        if not okAdd then
            exports['nyx_inventory']:AddItem(sourceInvId, contract.item_id, contract.quantity)
            return false, "VEHICLE_TRUNK_FULL"
        end

        return true
    end)

    if not okLock or not resOrErr then
        return { success = false, error = resOrErr or "LOCK_COLLISION" }
    end

    MySQL.prepare([[
        INSERT INTO `nyx_logistics_freight_audit`
        (`contract_id`, `action`, `carrier_citizen_id`, `vehicle_net_id`, `notes`)
        VALUES (?, 'FREIGHT_LOADED', ?, ?, 'Freight loaded into vehicle container')
    ]], { contractId, player.citizenId, vehicleNetId })

    return { success = true, vehicleTrunk = vehInvId }
end)

-- ----------------------------------------------------------------------------
-- 5. RPC: Deliver Contract & Settle Payout + Escrow
-- ----------------------------------------------------------------------------
Nyx.RPC.Register("logistics:deliverContract", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local contractId = payload and tonumber(payload.contractId)
    local vehicleNetId = payload and tonumber(payload.vehicleNetId)

    if not contractId or not vehicleNetId then
        return { success = false, error = "INVALID_PARAMETERS" }
    end

    local contract = MySQL.single.await([[
        SELECT * FROM `nyx_logistics_freight_contracts` WHERE `contract_id` = ?
    ]], { contractId })

    if not contract or contract.status ~= 'in_transit' or contract.claimed_by_citizen_id ~= player.citizenId then
        return { success = false, error = "INVALID_CONTRACT_STATE" }
    end

    -- Verify vehicle entity
    local vehEntity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehEntity) then
        return { success = false, error = "VEHICLE_NOT_FOUND" }
    end

    -- Proximity to delivery destination
    local dstCoords = contract.dest_coords and json.decode(contract.dest_coords) or nil
    if dstCoords then
        local dropVec = vector3(dstCoords.x, dstCoords.y, dstCoords.z)
        local vCoords = GetEntityCoords(vehEntity)
        if #(vCoords - dropVec) > Nyx.Logistics.FreightConfig.MaxLoadingDistance then
            return { success = false, error = "VEHICLE_OUT_OF_RANGE" }
        end
    end

    local plate = GetVehicleNumberPlateText(vehEntity):gsub("^%s*(.-)%s*$", "%1")
    local vehInvId = string.format("trunk:%s", plate)
    local destInvId = contract.dest_inventory_id

    -- Dijkstra Dual-Mutex Transfer: Vehicle -> Shelf
    local okLock, resOrErr = exports['nyx_inventory']:WithDualLock(vehInvId, destInvId, function()
        local hasItems = exports['nyx_inventory']:HasItem(vehInvId, contract.item_id, contract.quantity)
        if not hasItems then
            return false, "VEHICLE_MISSING_CONTRACT_ITEMS"
        end

        local okRemove = exports['nyx_inventory']:RemoveItem(vehInvId, contract.item_id, contract.quantity)
        if not okRemove then
            return false, "FAILED_TO_UNLOAD_VEHICLE"
        end

        local okAdd = exports['nyx_inventory']:AddItem(destInvId, contract.item_id, contract.quantity)
        if not okAdd then
            exports['nyx_inventory']:AddItem(vehInvId, contract.item_id, contract.quantity)
            return false, "DESTINATION_CAPACITY_ERROR"
        end

        return true
    end)

    if not okLock or not resOrErr then
        return { success = false, error = resOrErr or "LOCK_COLLISION" }
    end

    -- Atomic Settlement: Refund Escrow Bond + Credit Carrier Payout
    local escrow = tonumber(contract.escrow_deposit) or 0.00
    local payout = tonumber(contract.total_payout) or 0.00
    local totalCredits = payout + escrow

    player:addMoney("bank", totalCredits, string.format("Logistics Freight Settlement: #%d (Payout: $%.2f, Escrow Refund: $%.2f)", contractId, payout, escrow))

    -- Mark contract completed in database and in memory
    Nyx.Logistics.ActiveContracts[contractId] = nil

    MySQL.prepare([[
        UPDATE `nyx_logistics_freight_contracts`
        SET `status` = 'completed', `completed_at` = NOW()
        WHERE `contract_id` = ?
    ]], { contractId })

    -- Audit record
    MySQL.prepare([[
        INSERT INTO `nyx_logistics_freight_audit`
        (`contract_id`, `action`, `carrier_citizen_id`, `amount`, `debit_account`, `credit_account`, `notes`)
        VALUES (?, 'DELIVERY_FULFILLED', ?, ?, 'gov:city:master', ?, 'Delivery completed, payout credited and escrow refunded')
    ]], {
        contractId,
        player.citizenId,
        totalCredits,
        string.format("char:%s:bank", player.citizenId)
    })

    -- Recalibrate shelf price downwards
    local targetShelf = nil
    if Nyx.Logistics.Shelves then
        for _, s in pairs(Nyx.Logistics.Shelves) do
            if s.inventory_id == destInvId or s.id == destInvId then
                targetShelf = s
                break
            end
        end
    end

    if targetShelf then
        local newStock = exports['nyx_inventory']:GetItemCount(destInvId, targetShelf.item_id)
        local newPrice, newMult, newRatio = Nyx.Logistics.CalculateShelfPrice(
            targetShelf.base_price, targetShelf.target_capacity, newStock, targetShelf.zone_id, targetShelf.item_id, targetShelf
        )
        targetShelf.current_price = newPrice
        MySQL.prepare("UPDATE `nyx_logistics_shelves` SET `current_price` = ? WHERE `inventory_id` = ?", { newPrice, destInvId })
        TriggerClientEvent("nyx:logistics:client:shelfUpdated", -1, targetShelf.id or destInvId, newPrice, newStock, targetShelf.zone_id, newRatio)
    end

    return {
        success = true,
        payout = payout,
        escrowRefunded = escrow,
        totalCredited = totalCredits
    }
end)

-- ----------------------------------------------------------------------------
-- 6. RPC: Abandon Contract (Forfeits Escrow Bond)
-- ----------------------------------------------------------------------------
Nyx.RPC.Register("logistics:abandonContract", function(src, contractId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    contractId = tonumber(contractId)
    local contract = MySQL.single.await([[
        SELECT * FROM `nyx_logistics_freight_contracts` WHERE `contract_id` = ?
    ]], { contractId })

    if not contract or contract.status ~= 'in_transit' or contract.claimed_by_citizen_id ~= player.citizenId then
        return { success = false, error = "INVALID_CONTRACT_STATE" }
    end

    local escrow = tonumber(contract.escrow_deposit) or 0.00

    -- Evict from in-memory active cache
    Nyx.Logistics.ActiveContracts[contractId] = nil

    MySQL.prepare([[
        UPDATE `nyx_logistics_freight_contracts`
        SET `status` = 'forfeited', `claimed_by_char_id` = NULL, `claimed_by_citizen_id` = NULL
        WHERE `contract_id` = ?
    ]], { contractId })

    MySQL.prepare([[
        INSERT INTO `nyx_logistics_freight_audit`
        (`contract_id`, `action`, `carrier_citizen_id`, `amount`, `debit_account`, `credit_account`, `notes`)
        VALUES (?, 'ESCROW_FORFEITED', ?, ?, 'escrow:logistics:freight', 'gov:city:master', 'Carrier abandoned contract, bond forfeited')
    ]], {
        contractId,
        player.citizenId,
        escrow
    })

    return { success = true, forfeitedEscrow = escrow }
end)

-- ----------------------------------------------------------------------------
-- 7. Background Heartbeat Worker: In-Memory Expiry & Escrow Forfeiture Sweep (30s Tick)
-- ----------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(30000)

        local now = os.time()
        for contractId, contract in pairs(Nyx.Logistics.ActiveContracts) do
            if contract.status == 'in_transit' and contract.expiresAt and now > contract.expiresAt then
                local escrow = contract.escrowDeposit or 0.00
                Nyx.Logistics.ActiveContracts[contractId] = nil

                MySQL.prepare.await([[
                    UPDATE `nyx_logistics_freight_contracts`
                    SET `status` = 'expired', `claimed_by_char_id` = NULL, `claimed_by_citizen_id` = NULL
                    WHERE `contract_id` = ?
                ]], { contractId })

                MySQL.prepare.await([[
                    INSERT INTO `nyx_logistics_freight_audit`
                    (`contract_id`, `action`, `carrier_citizen_id`, `amount`, `debit_account`, `credit_account`, `notes`)
                    VALUES (?, 'CONTRACT_EXPIRED', ?, ?, 'escrow:logistics:freight', 'gov:city:master', 'Delivery deadline elapsed, escrow forfeited')
                ]], {
                    contractId,
                    contract.claimedByCitizenId or "UNKNOWN",
                    escrow
                })

                local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(contract.claimedByCitizenId)
                if targetPlayer then
                    TriggerClientEvent("nyx:core:client:notify", targetPlayer.source, {
                        type = "error",
                        title = "SZERZŐDÉS LEJÁRT",
                        message = "A fuvarozási határidő lejárt! A letéti kaució elkobzásra került."
                    })
                end

                if Config.Debug then
                    print(string.format("^1[Nyx:Logistics] Contract #%d elapsed deadline in-memory. Escrow $%.2f forfeited.^7", contractId, escrow))
                end
            end
        end
    end
end)
