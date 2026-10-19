--[[
    Nyxframework: nyx_factions
    File: server/storage_networks.lua
    Description: Authoritative server subsystems for organizational warehousing and storage networks:
                 in-memory asset registry, dynamic nyx_inventory container registration,
                 multi-tier RBAC access verification, pallet drop zone staging, and audit logging.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.Factions.DeployedAssets = {} -- [assetId] = assetData

-- Safe JSON parsing helper
local function safeJsonDecode(raw, fallback)
    if not raw or raw == "" then return fallback end
    local ok, res = pcall(json.decode, raw)
    return (ok and res) and res or fallback
end

-- UUID generator helper
local function generateAssetUuid()
    local template = "asset-xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end))
end

-- Audit logging helper
function Nyx.Factions.LogStorageAccessAudit(assetId, factionId, citizenId, action, permissionEvaluated, notes)
    local auditUuid = generateAssetUuid()
    pcall(function()
        MySQL.prepare([[
            INSERT INTO `nyx_factions_storage_access_audit`
                (`audit_uuid`, `asset_id`, `faction_id`, `citizen_id`, `action`, `permission_evaluated`, `notes`)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], { auditUuid, assetId, factionId, citizenId, action, permissionEvaluated or "unknown", notes or "" })
    end)
end

-- Hydrate deployed assets on server startup
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    while not (exports['nyx_core'] and exports['nyx_core'].IsDatabaseReady and exports['nyx_core']:IsDatabaseReady()) do
        Wait(50)
    end

    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_factions_deployed_assets`
        WHERE `decommissioned` = 0
    ]])

    if rows then
        for _, r in ipairs(rows) do
            local coords = safeJsonDecode(r.coords, { x = 0.0, y = 0.0, z = 0.0, h = 0.0 })
            local stagedPallets = safeJsonDecode(r.staged_pallets_json, {})

            local asset = {
                asset_id = r.asset_id,
                asset_uuid = r.asset_uuid,
                faction_id = r.faction_id,
                facility_type = r.facility_type,
                facility_id = r.facility_id,
                asset_type = r.asset_type,
                asset_label = r.asset_label,
                model_name = r.model_name,
                coords = coords,
                routing_bucket = tonumber(r.routing_bucket) or 0,
                access_permission_node = r.access_permission_node or "inventory:view",
                min_rank_level = tonumber(r.min_rank_level) or 1,
                inventory_id = r.inventory_id,
                capacity_grams = tonumber(r.capacity_grams) or 1000000,
                slots_count = tonumber(r.slots_count) or 60,
                workbench_subtype = r.workbench_subtype or "none",
                pallet_max_capacity = tonumber(r.pallet_max_capacity) or 4,
                staged_pallets = stagedPallets,
                is_locked = (tonumber(r.is_locked) == 1),
                deployed_by_citizen_id = r.deployed_by_citizen_id
            }

            Nyx.Factions.DeployedAssets[r.asset_id] = asset

            -- If secured stash, ensure dynamic container exists in nyx_inventory
            if r.asset_type == "secured_stash" and r.inventory_id and r.inventory_id ~= "" then
                if exports['nyx_inventory'] and exports['nyx_inventory'].RegisterContainer then
                    exports['nyx_inventory']:RegisterContainer(
                        r.inventory_id,
                        r.asset_label,
                        asset.capacity_grams,
                        asset.slots_count,
                        "permanent",
                        nil
                    )
                end
            end
        end

        local count = 0
        for _ in pairs(Nyx.Factions.DeployedAssets) do count = count + 1 end
        print(string.format("^2[Nyx:Factions] Loaded %d deployed organizational storage & processing assets.^7", count))
    end
end)

-- Retrieve single asset by numeric ID or UUID
function Nyx.Factions.GetDeployedAsset(assetId)
    if not assetId then return nil end
    local numId = tonumber(assetId)
    if numId and Nyx.Factions.DeployedAssets[numId] then
        return Nyx.Factions.DeployedAssets[numId]
    end

    for _, a in pairs(Nyx.Factions.DeployedAssets) do
        if a.asset_uuid == tostring(assetId) then
            return a
        end
    end
    return nil
end

-- Retrieve all assets deployed in a given facility (warehouse, property, storefront)
function Nyx.Factions.GetFacilityAssets(facilityId)
    if not facilityId then return {} end
    local results = {}
    for _, a in pairs(Nyx.Factions.DeployedAssets) do
        if a.facility_id == tostring(facilityId) then
            table.insert(results, a)
        end
    end
    return results
end

-- Evaluates citizen authorization against an asset
function Nyx.Factions.CanCitizenAccessAsset(citizenId, assetId)
    local asset = Nyx.Factions.GetDeployedAsset(assetId)
    if not asset then return false, "ASSET_NOT_FOUND", "denied" end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(asset.faction_id, citizenId)
    if not member then
        return false, "NOT_A_MEMBER", "denied"
    end

    return Nyx.StorageNetworks.EvaluateAssetAccess(asset, member)
end

-- ----------------------------------------------------------------------------
-- RPC Endpoints
-- ----------------------------------------------------------------------------

-- RPC: Get all assets deployed within a facility
Nyx.RPC.Register("factions:getFacilityAssets", function(src, facilityId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local assets = Nyx.Factions.GetFacilityAssets(facilityId)
    return {
        success = true,
        facilityId = facilityId,
        assets = assets
    }
end)

-- RPC: Deploy a new storage or processing asset
Nyx.RPC.Register("factions:deployStorageAsset", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if not payload or type(payload) ~= "table" then
        return { success = false, error = "INVALID_PAYLOAD" }
    end

    local factionId = payload.factionId or payload.faction_id or player:getFaction()
    if not factionId then
        return { success = false, error = "NO_FACTION_AFFILIATION" }
    end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(factionId, player.citizenId)
    if not member then
        return { success = false, error = "NOT_A_FACTION_MEMBER" }
    end

    -- Authorization check: requires inventory:manage_stashes or supreme executive (*)
    local hasManage = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "inventory:manage_stashes")
    local isExec = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "*")
    if not (hasManage or isExec) then
        return { success = false, error = "UNAUTHORIZED_NO_MANAGE_PERMISSION" }
    end

    local facilityType = payload.facilityType or payload.facility_type or "warehouse"
    local facilityId = payload.facilityId or payload.facility_id
    local assetType = payload.assetType or payload.asset_type
    local subtypeOrTier = payload.subtypeOrTier or payload.subtype or payload.tier
    local coords = payload.coords or { x = 0.0, y = 0.0, z = 0.0, h = 0.0 }
    local customLabel = payload.label or payload.asset_label

    -- Check existing count in facility
    local existing = Nyx.Factions.GetFacilityAssets(facilityId)
    local sameTypeCount = 0
    for _, a in ipairs(existing) do
        if a.asset_type == assetType then
            sameTypeCount = sameTypeCount + 1
        end
    end

    local okVal, valMsg, sanitized = Nyx.StorageNetworks.ValidateDeploymentParameters(
        facilityType, facilityId, assetType, subtypeOrTier, coords, sameTypeCount
    )
    if not okVal then
        return { success = false, error = valMsg }
    end

    -- Financial deduction: fee paid from faction treasury account
    local fee = sanitized.fee or 2500.00
    local corpTreasuryAcc = "faction:" .. factionId
    local municipalAcc = "gov:city:master"

    local currentBal = exports['nyx_treasury']:GetAccountBalance(corpTreasuryAcc) or 0.00
    if currentBal < fee then
        return { success = false, error = string.format("INSUFFICIENT_CORPORATE_FUNDS_REQUIRED_%.2f", fee) }
    end

    local feeOk, feeErr = exports['nyx_treasury']:ExecuteTransfer(
        corpTreasuryAcc,
        municipalAcc,
        fee,
        "facility_deployment_fee",
        corpTreasuryAcc,
        string.format("Asset deployment fee: %s (%s)", sanitized.label, facilityId),
        0.0
    )

    if not feeOk then
        return { success = false, error = feeErr or "FEE_TRANSFER_FAILED" }
    end

    local assetUuid = generateAssetUuid()
    local routingBucket = tonumber(payload.routingBucket or payload.routing_bucket) or 0
    local accessNode = payload.accessPermissionNode or payload.access_permission_node or "inventory:view"
    local minRank = math.max(1, math.floor(tonumber(payload.minRankLevel or payload.min_rank_level) or 1))
    local finalLabel = customLabel and string.len(customLabel) > 2 and string.sub(customLabel, 1, 64) or sanitized.label

    local inventoryId = nil
    if assetType == "secured_stash" then
        inventoryId = string.format("faction:stash:deployed:%s", assetUuid)
    end

    local insertId = MySQL.insert.await([[
        INSERT INTO `nyx_factions_deployed_assets`
            (`asset_uuid`, `faction_id`, `facility_type`, `facility_id`, `asset_type`, `asset_label`, `model_name`,
             `coords`, `routing_bucket`, `access_permission_node`, `min_rank_level`, `inventory_id`, `capacity_grams`,
             `slots_count`, `workbench_subtype`, `pallet_max_capacity`, `staged_pallets_json`, `is_locked`, `decommissioned`, `deployed_by_citizen_id`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', 0, 0, ?)
    ]], {
        assetUuid,
        factionId,
        facilityType,
        facilityId,
        assetType,
        finalLabel,
        sanitized.model,
        json.encode(sanitized.coords),
        routingBucket,
        accessNode,
        minRank,
        inventoryId,
        sanitized.capacity_grams or 0,
        sanitized.slots or 0,
        sanitized.workbench_subtype or "none",
        sanitized.pallet_max_capacity or 0,
        player.citizenId
    })

    if not insertId then
        -- Refund fee if database insertion failed
        exports['nyx_treasury']:ExecuteTransfer(
            municipalAcc, corpTreasuryAcc, fee, "fee_refund", municipalAcc, "Deployment rollback", 0.0
        )
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    local assetData = {
        asset_id = insertId,
        asset_uuid = assetUuid,
        faction_id = factionId,
        facility_type = facilityType,
        facility_id = facilityId,
        asset_type = assetType,
        asset_label = finalLabel,
        model_name = sanitized.model,
        coords = sanitized.coords,
        routing_bucket = routingBucket,
        access_permission_node = accessNode,
        min_rank_level = minRank,
        inventory_id = inventoryId,
        capacity_grams = sanitized.capacity_grams or 0,
        slots_count = sanitized.slots or 0,
        workbench_subtype = sanitized.workbench_subtype or "none",
        pallet_max_capacity = sanitized.pallet_max_capacity or 0,
        staged_pallets = {},
        is_locked = false,
        deployed_by_citizen_id = player.citizenId
    }

    Nyx.Factions.DeployedAssets[insertId] = assetData

    -- Register container in nyx_inventory
    if inventoryId and exports['nyx_inventory'] and exports['nyx_inventory'].RegisterContainer then
        exports['nyx_inventory']:RegisterContainer(
            inventoryId,
            finalLabel,
            assetData.capacity_grams,
            assetData.slots_count,
            "permanent",
            nil
        )
    end

    Nyx.Factions.LogStorageAccessAudit(insertId, factionId, player.citizenId, "DEPLOYED", "inventory:manage_stashes", "Deployed new " .. assetType)

    -- Broadcast to clients
    TriggerClientEvent("nyx:factions:client:assetDeployed", -1, assetData)

    return {
        success = true,
        asset = assetData,
        feePaid = fee
    }
end)

-- RPC: Access a deployed asset (evaluates permissions and returns access token / container)
Nyx.RPC.Register("factions:accessStorageAsset", function(src, assetId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local asset = Nyx.Factions.GetDeployedAsset(assetId)
    if not asset then return { success = false, error = "ASSET_NOT_FOUND" } end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(asset.faction_id, player.citizenId)
    if not member then
        return { success = false, error = "NOT_A_FACTION_MEMBER" }
    end

    local okAccess, reason, tier = Nyx.StorageNetworks.EvaluateAssetAccess(asset, member)
    if not okAccess then
        return { success = false, error = reason }
    end

    local action = "ACCESSED"
    if asset.asset_type == "secured_stash" then action = "STASH_OPENED"
    elseif asset.asset_type == "industrial_workbench" then action = "WORKBENCH_USED"
    end

    Nyx.Factions.LogStorageAccessAudit(asset.asset_id, asset.faction_id, player.citizenId, action, tier, "Authorized " .. tier)

    return {
        success = true,
        accessTier = tier,
        asset = asset
    }
end)

-- RPC: Update asset access rule / rank requirement
Nyx.RPC.Register("factions:updateAssetAccessRule", function(src, assetId, newPermission, minRank)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local asset = Nyx.Factions.GetDeployedAsset(assetId)
    if not asset then return { success = false, error = "ASSET_NOT_FOUND" } end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(asset.faction_id, player.citizenId)
    if not member then return { success = false, error = "NOT_A_FACTION_MEMBER" } end

    local hasManage = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "inventory:manage_stashes")
    local isExec = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "*")
    if not (hasManage or isExec) then
        return { success = false, error = "UNAUTHORIZED_NO_MANAGE_PERMISSION" }
    end

    local perm = tostring(newPermission or "inventory:view")
    local rank = math.max(1, math.floor(tonumber(minRank) or 1))

    asset.access_permission_node = perm
    asset.min_rank_level = rank

    MySQL.prepare([[
        UPDATE `nyx_factions_deployed_assets`
        SET `access_permission_node` = ?, `min_rank_level` = ?
        WHERE `asset_id` = ?
    ]], { perm, rank, asset.asset_id })

    Nyx.Factions.LogStorageAccessAudit(asset.asset_id, asset.faction_id, player.citizenId, "ACCESS_RULE_CHANGED", perm, "Updated rule to " .. perm .. ", rank " .. rank)
    TriggerClientEvent("nyx:factions:client:assetUpdated", -1, asset)

    return { success = true, asset = asset }
end)

-- RPC: Toggle asset security lock
Nyx.RPC.Register("factions:toggleAssetLock", function(src, assetId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local asset = Nyx.Factions.GetDeployedAsset(assetId)
    if not asset then return { success = false, error = "ASSET_NOT_FOUND" } end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(asset.faction_id, player.citizenId)
    if not member then return { success = false, error = "NOT_A_FACTION_MEMBER" } end

    local hasManage = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "inventory:manage_stashes")
    local isExec = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "*")
    if not (hasManage or isExec) then
        return { success = false, error = "UNAUTHORIZED_NO_MANAGE_PERMISSION" }
    end

    asset.is_locked = not asset.is_locked
    MySQL.prepare([[
        UPDATE `nyx_factions_deployed_assets`
        SET `is_locked` = ?
        WHERE `asset_id` = ?
    ]], { asset.is_locked and 1 or 0, asset.asset_id })

    Nyx.Factions.LogStorageAccessAudit(asset.asset_id, asset.faction_id, player.citizenId, "LOCK_TOGGLED", "is_locked=" .. tostring(asset.is_locked), "Lock state flipped")
    TriggerClientEvent("nyx:factions:client:assetUpdated", -1, asset)

    return { success = true, isLocked = asset.is_locked }
end)

-- RPC: Decommission a deployed asset
Nyx.RPC.Register("factions:decommissionStorageAsset", function(src, assetId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local asset = Nyx.Factions.GetDeployedAsset(assetId)
    if not asset then return { success = false, error = "ASSET_NOT_FOUND" } end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(asset.faction_id, player.citizenId)
    if not member then return { success = false, error = "NOT_A_FACTION_MEMBER" } end

    local hasManage = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "inventory:manage_stashes")
    local isExec = Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission(member.permissions, "*")
    if not (hasManage or isExec) then
        return { success = false, error = "UNAUTHORIZED_NO_MANAGE_PERMISSION" }
    end

    -- If stash, verify it is empty
    if asset.asset_type == "secured_stash" and asset.inventory_id and exports['nyx_inventory'] then
        local inv = exports['nyx_inventory']:GetInventory(asset.inventory_id)
        if inv and inv.items and next(inv.items) ~= nil then
            return { success = false, error = "CANNOT_DECOMMISSION_NON_EMPTY_STASH" }
        end
    end

    MySQL.prepare([[
        UPDATE `nyx_factions_deployed_assets`
        SET `decommissioned` = 1
        WHERE `asset_id` = ?
    ]], { asset.asset_id })

    Nyx.Factions.DeployedAssets[asset.asset_id] = nil
    Nyx.Factions.LogStorageAccessAudit(asset.asset_id, asset.faction_id, player.citizenId, "DECOMMISSIONED", "manage", "Decommissioned asset")
    TriggerClientEvent("nyx:factions:client:assetDecommissioned", -1, asset.asset_id, asset.facility_id)

    return { success = true, decommissionedAssetId = asset.asset_id }
end)

-- RPC: Stage a pallet in a Pallet Drop Zone
Nyx.RPC.Register("factions:stagePalletInDropZone", function(src, assetId, palletId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local asset = Nyx.Factions.GetDeployedAsset(assetId)
    if not asset or asset.asset_type ~= "pallet_drop_zone" then
        return { success = false, error = "INVALID_DROP_ZONE" }
    end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(asset.faction_id, player.citizenId)
    if not member then return { success = false, error = "NOT_A_FACTION_MEMBER" } end

    local okAccess, reason = Nyx.StorageNetworks.EvaluateAssetAccess(asset, member)
    if not okAccess then return { success = false, error = reason } end

    local okStage, stageMsg, updatedStaged = Nyx.StorageNetworks.EvaluatePalletStaging(asset, palletId, "stage")
    if not okStage then
        return { success = false, error = stageMsg }
    end

    asset.staged_pallets = updatedStaged
    MySQL.prepare([[
        UPDATE `nyx_factions_deployed_assets`
        SET `staged_pallets_json` = ?
        WHERE `asset_id` = ?
    ]], { json.encode(updatedStaged), asset.asset_id })

    Nyx.Factions.LogStorageAccessAudit(asset.asset_id, asset.faction_id, player.citizenId, "PALLET_STAGED", palletId, "Staged pallet " .. palletId)
    TriggerClientEvent("nyx:factions:client:assetUpdated", -1, asset)

    return { success = true, stagedPallets = updatedStaged }
end)

-- RPC: Retrieve a pallet from a Pallet Drop Zone
Nyx.RPC.Register("factions:retrievePalletFromDropZone", function(src, assetId, palletId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local asset = Nyx.Factions.GetDeployedAsset(assetId)
    if not asset or asset.asset_type ~= "pallet_drop_zone" then
        return { success = false, error = "INVALID_DROP_ZONE" }
    end

    local member = Nyx.Factions.GetMember and Nyx.Factions.GetMember(asset.faction_id, player.citizenId)
    if not member then return { success = false, error = "NOT_A_FACTION_MEMBER" } end

    local okAccess, reason = Nyx.StorageNetworks.EvaluateAssetAccess(asset, member)
    if not okAccess then return { success = false, error = reason } end

    local okRetrieve, retMsg, updatedStaged = Nyx.StorageNetworks.EvaluatePalletStaging(asset, palletId, "retrieve")
    if not okRetrieve then
        return { success = false, error = retMsg }
    end

    asset.staged_pallets = updatedStaged
    MySQL.prepare([[
        UPDATE `nyx_factions_deployed_assets`
        SET `staged_pallets_json` = ?
        WHERE `asset_id` = ?
    ]], { json.encode(updatedStaged), asset.asset_id })

    Nyx.Factions.LogStorageAccessAudit(asset.asset_id, asset.faction_id, player.citizenId, "PALLET_RETRIEVED", palletId, "Retrieved pallet " .. palletId)
    TriggerClientEvent("nyx:factions:client:assetUpdated", -1, asset)

    return { success = true, stagedPallets = updatedStaged }
end)
