--[[
    Nyxframework: nyx_factions
    File: shared/storage_networks.lua
    Description: Pure Lua 5.4 deterministic algorithms for organizational warehousing
                 and storage networks: taxonomy profiles, RBAC access evaluation,
                 deployment parameters validation, pallet staging arithmetic, and status badges.
]]

Nyx = Nyx or {}
Nyx.StorageNetworks = Nyx.StorageNetworks or {}

-- 1. Asset Type Taxonomy and Technical Specifications
Nyx.StorageNetworks.Taxonomy = {
    secured_stash = {
        tiers = {
            standard = {
                capacity_grams = 1000000, -- 1,000 kg
                slots = 60,
                model = "prop_cabinet_02b",
                fee = 2500.00,
                label = "Standard Széf"
            },
            reinforced = {
                capacity_grams = 3000000, -- 3,000 kg
                slots = 100,
                model = "prop_ld_greenscrn_01",
                fee = 6000.00,
                label = "Megerősített Raktárkonténer"
            },
            vault = {
                capacity_grams = 10000000, -- 10,000 kg
                slots = 150,
                model = "ch_prop_ch_vault_metal_01a",
                fee = 15000.00,
                label = "Páncélterem Raktárrekesz"
            }
        },
        defaultTier = "standard"
    },
    industrial_workbench = {
        subtypes = {
            assembly = {
                model = "prop_toolchest_01",
                fee = 5000.00,
                label = "Ipari Összeszerelő Pad"
            },
            refining = {
                model = "gr_prop_gr_bench_02b",
                fee = 7500.00,
                label = "Nyersanyag Finomító Munkapad"
            },
            weapons = {
                model = "gr_prop_gr_bench_02b",
                fee = 12000.00,
                label = "Fegyverkovács Munkapad"
            },
            medical = {
                model = "prop_toolchest_01",
                fee = 8500.00,
                label = "Gyógyszerészeti Szintetizátor"
            }
        },
        defaultSubtype = "assembly"
    },
    pallet_drop_zone = {
        maxPallets = 4,
        radius = 4.5,
        fee = 1500.00,
        model = "prop_pallet_01a",
        label = "Raklap Átrakó Zóna"
    }
}

-- 2. Facility Asset Density Limits
Nyx.StorageNetworks.FacilityLimits = {
    warehouse = {
        secured_stash = 10,
        industrial_workbench = 4,
        pallet_drop_zone = 4
    },
    commercial_storefront = {
        secured_stash = 4,
        industrial_workbench = 2,
        pallet_drop_zone = 1
    },
    property = {
        secured_stash = 2,
        industrial_workbench = 1,
        pallet_drop_zone = 0
    }
}

-- 3. Helper: Permission Evaluator Fallback (mirrors Nyx.CorporateRBAC.EvaluatePermission)
local function evaluatePermission(nodesList, requiredNode)
    if Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission then
        return Nyx.CorporateRBAC.EvaluatePermission(nodesList, requiredNode)
    end

    if not nodesList or type(nodesList) ~= "table" or not requiredNode then
        return false
    end

    for _, node in ipairs(nodesList) do
        if type(node) == "string" then
            if node == "*" or node == requiredNode then
                return true
            end
            if string.sub(node, -2) == ":*" then
                local prefix = string.sub(node, 1, -2)
                if string.sub(requiredNode, 1, #prefix) == prefix then
                    return true
                end
            end
        end
    end

    return false
end

--- 4. Evaluates whether a member has authorization to interact with a deployed asset.
--- Returns: boolean canAccess, string reason, string accessTier ('full', 'deposit_only', 'read_only', 'denied')
function Nyx.StorageNetworks.EvaluateAssetAccess(asset, member)
    if not asset or type(asset) ~= "table" or not member or type(member) ~= "table" then
        return false, "INVALID_ARGUMENTS", "denied"
    end

    local assetFaction = asset.faction_id or asset.factionId
    local memberFaction = member.faction_id or member.factionId
    if not assetFaction or not memberFaction or assetFaction ~= memberFaction then
        return false, "ACCESS_DENIED_FACTION_MISMATCH", "denied"
    end

    local perms = member.permissions or {}
    local isExec = evaluatePermission(perms, "*")
    local hasManage = evaluatePermission(perms, "inventory:manage_stashes")

    -- Check lock state
    local isLocked = (asset.is_locked == 1 or asset.is_locked == true or asset.isLocked == true)
    if isLocked and not (isExec or hasManage) then
        return false, "ACCESS_DENIED_ASSET_LOCKED", "denied"
    end

    -- Check minimum rank level
    local minRank = math.max(1, math.floor(tonumber(asset.min_rank_level or asset.minRankLevel) or 1))
    local memberRank = math.max(1, math.floor(tonumber(member.rank_level or member.rankLevel) or 1))
    if memberRank < minRank and not isExec then
        return false, "ACCESS_DENIED_INSUFFICIENT_RANK", "denied"
    end

    -- Full management or executive access
    if isExec or hasManage then
        return true, "AUTHORIZED_FULL", "full"
    end

    -- Specific permission nodes
    if evaluatePermission(perms, "inventory:withdraw") or evaluatePermission(perms, "inventory:*") then
        return true, "AUTHORIZED_FULL", "full"
    end

    if evaluatePermission(perms, "inventory:deposit") then
        return true, "AUTHORIZED_DEPOSIT_ONLY", "deposit_only"
    end

    local reqNode = asset.access_permission_node or asset.accessPermissionNode or "inventory:view"
    if evaluatePermission(perms, reqNode) or evaluatePermission(perms, "inventory:view") then
        return true, "AUTHORIZED_READ_ONLY", "read_only"
    end

    return false, "ACCESS_DENIED_NO_PERMISSION", "denied"
end

--- 5. Validates deployment parameters, spatial coordinates, and density limits.
--- Returns: boolean success, string message, table|nil sanitizedData
function Nyx.StorageNetworks.ValidateDeploymentParameters(facilityType, facilityId, assetType, subtypeOrTier, coords, existingCount)
    if not facilityType or not Nyx.StorageNetworks.FacilityLimits[facilityType] then
        return false, "INVALID_FACILITY_TYPE", nil
    end

    if not facilityId or type(facilityId) ~= "string" or string.len(string.gsub(facilityId, "^%s*(.-)%s*$", "%1")) < 2 then
        return false, "INVALID_FACILITY_ID", nil
    end

    local cleanFacilityId = string.gsub(facilityId, "^%s*(.-)%s*$", "%1")
    if not assetType or not Nyx.StorageNetworks.Taxonomy[assetType] then
        return false, "INVALID_ASSET_TYPE", nil
    end

    local limits = Nyx.StorageNetworks.FacilityLimits[facilityType]
    local maxAllowed = limits[assetType] or 0
    existingCount = math.max(0, math.floor(tonumber(existingCount) or 0))
    if existingCount >= maxAllowed then
        return false, string.format("FACILITY_LIMIT_EXCEEDED_MAX_%d", maxAllowed), nil
    end

    if not coords or type(coords) ~= "table" then
        return false, "INVALID_COORDINATES", nil
    end

    local x = tonumber(coords.x or coords[1]) or 0.0
    local y = tonumber(coords.y or coords[2]) or 0.0
    local z = tonumber(coords.z or coords[3]) or 0.0
    local h = (tonumber(coords.h or coords.heading or coords[4]) or 0.0) % 360.0

    local sanitized = {
        facility_type = facilityType,
        facility_id = cleanFacilityId,
        asset_type = assetType,
        coords = {
            x = math.floor(x * 100 + 0.5) / 100,
            y = math.floor(y * 100 + 0.5) / 100,
            z = math.floor(z * 100 + 0.5) / 100,
            h = math.floor(h * 100 + 0.5) / 100
        }
    }

    if assetType == "secured_stash" then
        local tier = tostring(subtypeOrTier or "standard")
        if not Nyx.StorageNetworks.Taxonomy.secured_stash.tiers[tier] then
            tier = "standard"
        end
        local spec = Nyx.StorageNetworks.Taxonomy.secured_stash.tiers[tier]
        sanitized.tier = tier
        sanitized.capacity_grams = spec.capacity_grams
        sanitized.slots = spec.slots
        sanitized.model = spec.model
        sanitized.fee = spec.fee
        sanitized.label = spec.label
    elseif assetType == "industrial_workbench" then
        local sub = tostring(subtypeOrTier or "assembly")
        if not Nyx.StorageNetworks.Taxonomy.industrial_workbench.subtypes[sub] then
            sub = "assembly"
        end
        local spec = Nyx.StorageNetworks.Taxonomy.industrial_workbench.subtypes[sub]
        sanitized.workbench_subtype = sub
        sanitized.model = spec.model
        sanitized.fee = spec.fee
        sanitized.label = spec.label
    elseif assetType == "pallet_drop_zone" then
        local spec = Nyx.StorageNetworks.Taxonomy.pallet_drop_zone
        sanitized.pallet_max_capacity = spec.maxPallets
        sanitized.radius = spec.radius
        sanitized.model = spec.model
        sanitized.fee = spec.fee
        sanitized.label = spec.label
    end

    return true, "VALIDATION_OK", sanitized
end

--- 6. Evaluates Pallet Staging / Retrieval logic in a Pallet Drop Zone.
--- Returns: boolean success, string reason, table updatedStagedList
function Nyx.StorageNetworks.EvaluatePalletStaging(dropZone, palletId, action)
    if not dropZone or type(dropZone) ~= "table" then
        return false, "INVALID_DROP_ZONE", {}
    end

    if not palletId or type(palletId) ~= "string" or palletId == "" then
        return false, "INVALID_PALLET_ID", {}
    end

    local staged = {}
    local raw = dropZone.staged_pallets or dropZone.stagedPallets or {}
    for _, pid in ipairs(raw) do
        table.insert(staged, pid)
    end

    local maxCap = math.max(1, math.floor(tonumber(dropZone.pallet_max_capacity or dropZone.palletMaxCapacity) or 4))

    if action == "stage" then
        if #staged >= maxCap then
            return false, "DROP_ZONE_CAPACITY_FULL", staged
        end
        for _, pid in ipairs(staged) do
            if pid == palletId then
                return false, "PALLET_ALREADY_STAGED", staged
            end
        end
        table.insert(staged, palletId)
        return true, "STAGED_SUCCESSFULLY", staged
    elseif action == "retrieve" then
        local foundIndex = nil
        for i, pid in ipairs(staged) do
            if pid == palletId then
                foundIndex = i
                break
            end
        end
        if not foundIndex then
            return false, "PALLET_NOT_FOUND_IN_ZONE", staged
        end
        table.remove(staged, foundIndex)
        return true, "RETRIEVED_SUCCESSFULLY", staged
    end

    return false, "UNKNOWN_ACTION", staged
end

--- 7. Formats a descriptive summary and status badge for a deployed asset.
function Nyx.StorageNetworks.FormatAssetSummary(asset)
    if not asset or type(asset) ~= "table" then
        return { label = "Ismeretlen", badgeClass = "badge-secondary", statusText = "INACTIVE" }
    end

    local aType = asset.asset_type or asset.assetType or "unknown"
    local isLocked = (asset.is_locked == 1 or asset.is_locked == true)

    local typeLabels = {
        secured_stash = "Biztonsági Széf",
        industrial_workbench = "Ipari Munkapad",
        pallet_drop_zone = "Raklap Átrakó Zóna"
    }

    local badge = {
        typeLabel = typeLabels[aType] or aType,
        isLocked = isLocked,
        badgeClass = isLocked and "badge-danger" or "badge-success",
        statusText = isLocked and "ZÁROLVA" or "AKTÍV",
        capacityDesc = ""
    }

    if aType == "secured_stash" then
        local kg = math.floor((tonumber(asset.capacity_grams or asset.capacityGrams) or 0) / 1000)
        local slots = tonumber(asset.slots_count or asset.slotsCount) or 0
        badge.capacityDesc = string.format("%d kg / %d rekesz", kg, slots)
    elseif aType == "pallet_drop_zone" then
        local maxP = tonumber(asset.pallet_max_capacity or asset.palletMaxCapacity) or 4
        badge.capacityDesc = string.format("Max %d raklap", maxP)
    elseif aType == "industrial_workbench" then
        local sub = asset.workbench_subtype or asset.workbenchSubtype or "assembly"
        badge.capacityDesc = string.format("Típus: %s", sub)
    end

    return badge
end
