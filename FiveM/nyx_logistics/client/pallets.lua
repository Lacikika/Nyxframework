--[[
    Nyxframework: nyx_logistics
    File: client/pallets.lua
    Description: Physical heavy freight pallet entity handling, 3D prop streaming,
                 vehicle attachment matrices, and Third-Eye (LALT) interaction.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.LocalPallets = {}        -- Array of spawned entity handles
Nyx.Logistics.PalletEntities = {}      -- [palletId] = entityHandle
Nyx.Logistics.ClientPalletState = {}   -- [palletId] = palletData

local palletModelHash = GetHashKey(Config.PalletModel or "prop_boxpile_06a")

-- 1. Helper to spawn physical freight pallet prop
function Nyx.Logistics.SpawnPallet(coords, heading, modelName)
    local hash = modelName and GetHashKey(modelName) or palletModelHash
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end

    if not HasModelLoaded(hash) then
        return nil
    end

    local obj = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityDynamic(obj, true)
    ActivatePhysics(obj)
    PlaceObjectOnGroundProperly(obj)

    Nyx.Logistics.LocalPallets[#Nyx.Logistics.LocalPallets + 1] = obj
    return obj
end

-- 2. Attach pallet prop to commercial flatbed, truck, or forklift
function Nyx.Logistics.AttachPalletToVehicle(palletObj, vehicle, boneIndex, offset)
    if not DoesEntityExist(palletObj) or not DoesEntityExist(vehicle) then return false end

    offset = offset or vector3(0.0, -1.5, 0.45)
    AttachEntityToEntity(
        palletObj,
        vehicle,
        boneIndex or 0,
        offset.x, offset.y, offset.z,
        0.0, 0.0, 0.0,
        true, false, true, false, 2, true
    )
    return true
end

-- 3. Detach pallet and drop on ground
function Nyx.Logistics.DetachPallet(palletObj, coords, heading)
    if not DoesEntityExist(palletObj) then return end
    DetachEntity(palletObj, true, true)
    if coords then
        SetEntityCoords(palletObj, coords.x, coords.y, coords.z, false, false, false, false)
    end
    if heading then
        SetEntityHeading(palletObj, heading)
    end
    PlaceObjectOnGroundProperly(palletObj)
end

-- 4. Network Synchronization Handlers
RegisterNetEvent("nyx:logistics:client:palletSpawned", function(palletData)
    if not palletData or not palletData.id then return end
    Nyx.Logistics.ClientPalletState[palletData.id] = palletData

    if palletData.coords then
        local pPed = PlayerPedId()
        local pCoords = GetEntityCoords(pPed)
        local dist = #(pCoords - vector3(palletData.coords.x, palletData.coords.y, palletData.coords.z))
        if dist < 60.0 then
            local obj = Nyx.Logistics.SpawnPallet(palletData.coords, palletData.heading, palletData.model)
            if obj then
                Nyx.Logistics.PalletEntities[palletData.id] = obj
                Entity(obj).state:set("palletId", palletData.id, false)
            end
        end
    end
end)

RegisterNetEvent("nyx:logistics:client:palletAttached", function(data)
    if not data or not data.palletId then return end
    local pallet = Nyx.Logistics.ClientPalletState[data.palletId]
    if pallet then
        pallet.attached_vehicle_plate = data.plate
        pallet.attached_slot_index = data.slotIndex
        pallet.attached_offset = data.offset
        pallet.coords = nil
    end

    local obj = Nyx.Logistics.PalletEntities[data.palletId]
    local veh = NetworkGetEntityFromNetworkId(tonumber(data.vehicleNetId))
    if DoesEntityExist(obj) and DoesEntityExist(veh) then
        local off = data.offset or { x = 0.0, y = -1.5, z = 0.45 }
        Nyx.Logistics.AttachPalletToVehicle(obj, veh, data.bone or 0, vector3(off.x, off.y, off.z))
    end
end)

RegisterNetEvent("nyx:logistics:client:palletDetached", function(data)
    if not data or not data.palletId then return end
    local pallet = Nyx.Logistics.ClientPalletState[data.palletId]
    if pallet then
        pallet.attached_vehicle_plate = nil
        pallet.attached_slot_index = 0
        pallet.attached_offset = nil
        pallet.coords = data.coords
        pallet.heading = data.heading
    end

    local obj = Nyx.Logistics.PalletEntities[data.palletId]
    if DoesEntityExist(obj) then
        Nyx.Logistics.DetachPallet(obj, data.coords, data.heading)
    end
end)

RegisterNetEvent("nyx:logistics:client:palletSealUpdated", function(palletId, isSealed)
    local pallet = Nyx.Logistics.ClientPalletState[palletId]
    if pallet then
        pallet.is_sealed = isSealed
    end

    local msg = isSealed and "Raklap zárolva és plombálva a szállításhoz." or "Raklap plomba feltörve, rakomány hozzáférhető."
    TriggerEvent("nyx:core:client:notify", msg, "info")
end)

-- 5. Third-Eye (LALT) Raycast Integration on Freight Pallets
CreateThread(function()
    while GetResourceState("nyx_interact") ~= "started" do
        Wait(100)
    end

    local palletModels = {
        "prop_boxpile_06a",
        "prop_boxpile_05a",
        "prop_boxpile_04a",
        "prop_boxpile_02b",
        "prop_pallet_01a"
    }

    if exports['nyx_interact'] and exports['nyx_interact'].AddTargetModel then
        exports['nyx_interact']:AddTargetModel(palletModels, {
            options = {
                {
                    label = "Raklap Ellenőrzése",
                    icon = "fa-solid fa-clipboard-check",
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if not palletId then
                            for pid, handle in pairs(Nyx.Logistics.PalletEntities) do
                                if handle == entity then palletId = pid break end
                            end
                        end

                        if palletId then
                            local state = exports['nyx_core']:TriggerRPCAwait("logistics:getPalletState", palletId)
                            if state and state.pallet then
                                local p = state.pallet
                                local snap = state.snapshot or {}
                                local sealStatus = p.is_sealed and "LEZÁRT (PLOMBÁLT)" or "NYITOTT"
                                TriggerEvent("nyx:core:client:notify",
                                    string.format("[%s] Súly: %.1fkg | Tételek: %d | Állapot: %s",
                                        p.label or palletId,
                                        (snap.totalWeight or 0) / 1000.0,
                                        snap.itemCount or 0,
                                        sealStatus),
                                    "info")
                            end
                        end
                    end
                },
                {
                    label = "Raklap Kinyitása",
                    icon = "fa-solid fa-box-open",
                    canInteract = function(entity)
                        local palletId = Entity(entity).state.palletId
                        local p = palletId and Nyx.Logistics.ClientPalletState[palletId]
                        return not (p and p.is_sealed)
                    end,
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if palletId then
                            local invId = "pallet:" .. palletId
                            TriggerEvent("nyx:inventory:client:openSecondary", invId)
                        end
                    end
                },
                {
                    label = "Felrakodás Járműre",
                    icon = "fa-solid fa-truck-ramp-box",
                    canInteract = function(entity)
                        local palletId = Entity(entity).state.palletId
                        local p = palletId and Nyx.Logistics.ClientPalletState[palletId]
                        return not (p and p.attached_vehicle_plate)
                    end,
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if not palletId then return end

                        -- Find nearest commercial carrier vehicle within 6.0 meters
                        local ped = PlayerPedId()
                        local pCoords = GetEntityCoords(ped)
                        local veh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 6.0, 0, 71)
                        if not DoesEntityExist(veh) then
                            TriggerEvent("nyx:core:client:notify", "Nincs alkalmas teherjármű a közelben (6m-en belül)!", "error")
                            return
                        end

                        local vehNetId = NetworkGetNetworkIdFromEntity(veh)
                        local res = exports['nyx_core']:TriggerRPCAwait("logistics:attachPalletToVehicle", {
                            palletId = palletId,
                            vehicleNetId = vehNetId
                        })

                        if res and res.success then
                            TriggerEvent("nyx:core:client:notify", string.format("Raklap sikeresen rögzítve a járműre (#%d. pozíció).", res.data.slotIndex), "success")
                        else
                            TriggerEvent("nyx:core:client:notify", "Felrakodás sikertelen: " .. tostring(res and res.error or "Hiba"), "error")
                        end
                    end
                },
                {
                    label = "Lerakodás Járműről",
                    icon = "fa-solid fa-dolly",
                    canInteract = function(entity)
                        local palletId = Entity(entity).state.palletId
                        local p = palletId and Nyx.Logistics.ClientPalletState[palletId]
                        return (p and p.attached_vehicle_plate ~= nil)
                    end,
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if not palletId then return end

                        local ped = PlayerPedId()
                        local pCoords = GetEntityCoords(ped)
                        local pHeading = GetEntityHeading(ped)

                        local res = exports['nyx_core']:TriggerRPCAwait("logistics:detachPalletFromVehicle", {
                            palletId = palletId,
                            coords = { x = pCoords.x, y = pCoords.y, z = pCoords.z },
                            heading = pHeading
                        })

                        if res and res.success then
                            TriggerEvent("nyx:core:client:notify", "Raklap lerakodva a talajra.", "success")
                        else
                            TriggerEvent("nyx:core:client:notify", "Lerakodás sikertelen: " .. tostring(res and res.error or "Hiba"), "error")
                        end
                    end
                },
                {
                    label = "Raklap Leplombálása",
                    icon = "fa-solid fa-lock",
                    canInteract = function(entity)
                        local palletId = Entity(entity).state.palletId
                        local p = palletId and Nyx.Logistics.ClientPalletState[palletId]
                        return not (p and p.is_sealed)
                    end,
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if palletId then
                            local res = exports['nyx_core']:TriggerRPCAwait("logistics:sealPallet", palletId)
                            if not res or not res.success then
                                TriggerEvent("nyx:core:client:notify", "Leplombálás sikertelen: " .. tostring(res and res.error or "Üres raklap"), "error")
                            end
                        end
                    end
                },
                {
                    label = "Plomba Feltörése",
                    icon = "fa-solid fa-lock-open",
                    canInteract = function(entity)
                        local palletId = Entity(entity).state.palletId
                        local p = palletId and Nyx.Logistics.ClientPalletState[palletId]
                        return (p and p.is_sealed == true)
                    end,
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if palletId then
                            exports['nyx_core']:TriggerRPCAwait("logistics:unsealPallet", palletId)
                        end
                    end
                }
            },
            distance = 3.0
        })
    end
end)

-- 6. Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, obj in ipairs(Nyx.Logistics.LocalPallets) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
end)
