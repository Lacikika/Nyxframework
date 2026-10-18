--[[
    Nyxframework: nyx_factions
    File: client/storage_networks.lua
    Description: Client-side spatial prop synchronization, third-eye target registration,
                 and interactive actions for organizational storage networks and workbenches.
]]

Nyx = Nyx or {}
Nyx.StorageNetworksClient = Nyx.StorageNetworksClient or {}
Nyx.StorageNetworksClient.SpawnedProps = {} -- [assetId] = entity
Nyx.StorageNetworksClient.FacilityAssets = {} -- [assetId] = assetData

local function notify(msgType, title, message)
    if exports['nyx_core'] and exports['nyx_core'].Notify then
        exports['nyx_core']:Notify({ type = msgType, title = title, message = message })
    else
        TriggerEvent("chat:addMessage", {
            color = (msgType == "error" and { 255, 60, 60 } or { 60, 200, 100 }),
            multiline = true,
            args = { title, message }
        })
    end
end

-- Safely request and load prop model
local function loadModel(modelHash)
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = 100
        while not HasModelLoaded(modelHash) and timeout > 0 do
            Wait(10)
            timeout = timeout - 1
        end
    end
    return HasModelLoaded(modelHash)
end

-- Spawn a physical prop for an asset
function Nyx.StorageNetworksClient.SpawnAssetProp(asset)
    if not asset or not asset.asset_id or not asset.coords then return end
    local assetId = asset.asset_id

    -- Clean existing entity if already spawned
    if Nyx.StorageNetworksClient.SpawnedProps[assetId] then
        local oldEnt = Nyx.StorageNetworksClient.SpawnedProps[assetId]
        if DoesEntityExist(oldEnt) then
            DeleteEntity(oldEnt)
        end
        Nyx.StorageNetworksClient.SpawnedProps[assetId] = nil
    end

    local modelName = asset.model_name or "prop_cabinet_02b"
    local modelHash = GetHashKey(modelName)

    if loadModel(modelHash) then
        local c = asset.coords
        local obj = CreateObjectNoOffset(modelHash, c.x, c.y, c.z, false, false, false)
        if DoesEntityExist(obj) then
            SetEntityHeading(obj, c.h or 0.0)
            FreezeEntityPosition(obj, true)
            SetEntityInvincible(obj, true)
            Nyx.StorageNetworksClient.SpawnedProps[assetId] = obj

            -- Register Third-Eye Spatial Target options via nyx_interact or ox_target
            if exports['nyx_interact'] and exports['nyx_interact'].AddTargetEntity then
                local options = {}

                if asset.asset_type == "secured_stash" then
                    table.insert(options, {
                        name = string.format("factions:open_stash:%d", assetId),
                        icon = "fa-solid fa-vault",
                        label = string.format("%s Megnyitása", asset.asset_label or "Széf"),
                        onSelect = function()
                            Nyx.StorageNetworksClient.InteractAsset(assetId)
                        end
                    })
                    table.insert(options, {
                        name = string.format("factions:lock_stash:%d", assetId),
                        icon = "fa-solid fa-lock",
                        label = "Zár Átkapcsolása",
                        onSelect = function()
                            Nyx.StorageNetworksClient.ToggleLock(assetId)
                        end
                    })
                elseif asset.asset_type == "industrial_workbench" then
                    table.insert(options, {
                        name = string.format("factions:use_workbench:%d", assetId),
                        icon = "fa-solid fa-screwdriver-wrench",
                        label = string.format("%s Használata", asset.asset_label or "Munkapad"),
                        onSelect = function()
                            Nyx.StorageNetworksClient.InteractAsset(assetId)
                        end
                    })
                elseif asset.asset_type == "pallet_drop_zone" then
                    table.insert(options, {
                        name = string.format("factions:stage_pallet:%d", assetId),
                        icon = "fa-solid fa-pallet",
                        label = "Raklap Lerakása Zónába",
                        onSelect = function()
                            Nyx.StorageNetworksClient.StageHeldPallet(assetId)
                        end
                    })
                end

                exports['nyx_interact']:AddTargetEntity(obj, {
                    options = options,
                    distance = 2.5
                })
            end
        end
        SetModelAsNoLongerNeeded(modelHash)
    end
end

-- Despawn asset prop
function Nyx.StorageNetworksClient.DespawnAssetProp(assetId)
    local ent = Nyx.StorageNetworksClient.SpawnedProps[assetId]
    if ent and DoesEntityExist(ent) then
        if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity then
            exports['nyx_interact']:RemoveTargetEntity(ent)
        end
        DeleteEntity(ent)
    end
    Nyx.StorageNetworksClient.SpawnedProps[assetId] = nil
end

-- Interact with a deployed asset
function Nyx.StorageNetworksClient.InteractAsset(assetId)
    if not exports['nyx_core'] or not exports['nyx_core'].CallRPC then return end

    exports['nyx_core']:CallRPC("factions:accessStorageAsset", assetId, function(res)
        if not res or not res.success then
            notify("error", "HOZZÁFÉRÉS MEGTAGADVA", res and res.error or "Nem sikerült az azonosítás.")
            return
        end

        local asset = res.asset
        local tier = res.accessTier

        if asset.asset_type == "secured_stash" then
            notify("success", "SZÉF MEGNYITVA", string.format("Jogosultság szint: %s (%s)", tier, asset.asset_label))
            if asset.inventory_id and exports['nyx_inventory'] and exports['nyx_inventory'].OpenContainer then
                exports['nyx_inventory']:OpenContainer(asset.inventory_id)
            end
        elseif asset.asset_type == "industrial_workbench" then
            notify("success", "MUNKAPAD", string.format("Aktív munkapad: %s [%s]", asset.asset_label, asset.workbench_subtype or "assembly"))
            -- Trigger crafting / assembly recipe menu
            TriggerEvent("nyx:logistics:client:openAssemblyTerminal", {
                stationType = asset.workbench_subtype or "assembly",
                stationLabel = asset.asset_label
            })
        end
    end)
end

-- Toggle lock on an asset
function Nyx.StorageNetworksClient.ToggleLock(assetId)
    if not exports['nyx_core'] or not exports['nyx_core'].CallRPC then return end

    exports['nyx_core']:CallRPC("factions:toggleAssetLock", assetId, function(res)
        if not res or not res.success then
            notify("error", "HIBA", res and res.error or "Nem sikerült a zár állapotát módosítani.")
            return
        end

        local statusText = res.isLocked and "ZÁROLVA" or "FELOLDVA"
        notify("success", "BIZTONSÁGI ZÁR", string.format("Tárolóegység új állapota: %s", statusText))
    end)
end

-- Stage currently held / targeted pallet in drop zone
function Nyx.StorageNetworksClient.StageHeldPallet(assetId)
    local heldPalletId = "pallet:auto_staged"
    if exports['nyx_logistics'] and exports['nyx_logistics'].GetHeldPalletId then
        heldPalletId = exports['nyx_logistics']:GetHeldPalletId() or heldPalletId
    end

    exports['nyx_core']:CallRPC("factions:stagePalletInDropZone", assetId, heldPalletId, function(res)
        if not res or not res.success then
            notify("error", "RAKLAP HIBA", res and res.error or "Nem sikerült a raklapot átadni a zónának.")
            return
        end

        notify("success", "RAKLAP LERAKVA", string.format("Raklap sikeresen elhelyezve a drop zone-ban! (Összes: %d)", #res.stagedPallets))
    end)
end

-- Network Event Handlers
RegisterNetEvent("nyx:factions:client:assetDeployed", function(asset)
    if not asset or not asset.asset_id then return end
    Nyx.StorageNetworksClient.FacilityAssets[asset.asset_id] = asset
    Nyx.StorageNetworksClient.SpawnAssetProp(asset)
end)

RegisterNetEvent("nyx:factions:client:assetUpdated", function(asset)
    if not asset or not asset.asset_id then return end
    Nyx.StorageNetworksClient.FacilityAssets[asset.asset_id] = asset
    -- Re-spawn or update target
    Nyx.StorageNetworksClient.SpawnAssetProp(asset)
end)

RegisterNetEvent("nyx:factions:client:assetDecommissioned", function(assetId, facilityId)
    Nyx.StorageNetworksClient.FacilityAssets[assetId] = nil
    Nyx.StorageNetworksClient.DespawnAssetProp(assetId)
    notify("info", "LESZERELVE", string.format("Tárolóegység #%d leszerelésre került.", assetId))
end)

RegisterNetEvent("nyx:factions:client:syncFacilityAssets", function(assetsList)
    if not assetsList or type(assetsList) ~= "table" then return end
    for _, asset in ipairs(assetsList) do
        Nyx.StorageNetworksClient.FacilityAssets[asset.asset_id] = asset
        Nyx.StorageNetworksClient.SpawnAssetProp(asset)
    end
end)

-- Player Command: /deployasset [stash|workbench|pallet_zone] [tier/subtype] [label]
RegisterCommand("deployasset", function(source, args)
    local assetTypeKey = string.lower(args[1] or "")
    local typeMap = {
        stash = "secured_stash",
        szef = "secured_stash",
        workbench = "industrial_workbench",
        munkapad = "industrial_workbench",
        pallet_zone = "pallet_drop_zone",
        raklap = "pallet_drop_zone"
    }

    local assetType = typeMap[assetTypeKey] or "secured_stash"
    local subtypeOrTier = args[2] or (assetType == "secured_stash" and "standard" or (assetType == "industrial_workbench" and "assembly" or nil))
    local label = args[3] or (assetType == "secured_stash" and "Vállalati Széf" or "Ipari Állomás")

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- Determine current facility from warehouse or property exports
    local facilityId = "wh_elysian_04"
    local facilityType = "warehouse"
    if exports['nyx_logistics'] and exports['nyx_logistics'].GetPlayerWarehouse then
        local currentWh = exports['nyx_logistics']:GetPlayerWarehouse(GetPlayerServerId(PlayerId()))
        if currentWh then
            facilityId = currentWh.id
            facilityType = "warehouse"
        end
    end

    local payload = {
        facilityType = facilityType,
        facilityId = facilityId,
        assetType = assetType,
        subtypeOrTier = subtypeOrTier,
        label = label,
        coords = {
            x = math.floor(coords.x * 100 + 0.5) / 100,
            y = math.floor(coords.y * 100 + 0.5) / 100,
            z = math.floor(coords.z * 100 + 0.5) / 100,
            h = math.floor(heading * 100 + 0.5) / 100
        }
    }

    exports['nyx_core']:CallRPC("factions:deployStorageAsset", payload, function(res)
        if not res or not res.success then
            notify("error", "TELEPÍTÉSI HIBA", res and res.error or "A tárolóegység nem telepíthető.")
            return
        end

        notify("success", "SIKERES TELEPÍTÉS", string.format("%s sikeresen kihelyezve! Levont díj: $%.2f", res.asset.asset_label, res.feePaid or 0.0))
    end)
end, false)

-- Player Command: /facilityassets
RegisterCommand("facilityassets", function()
    local facilityId = "wh_elysian_04"
    exports['nyx_core']:CallRPC("factions:getFacilityAssets", facilityId, function(res)
        if not res or not res.success then
            notify("error", "HIBA", "Nem sikerült lekérdezni a létesítmény egységeit.")
            return
        end

        local count = #(res.assets or {})
        notify("info", "LÉTESÍTMÉNY EGYSÉGEK", string.format("Találatok (%s): %d db aktív tárolóegység.", facilityId, count))
    end)
end, false)
