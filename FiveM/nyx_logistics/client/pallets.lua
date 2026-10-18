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

RegisterNetEvent("nyx:logistics:client:palletSealUpdated", function(palletId, isSealed, sealSerial)
    local pallet = Nyx.Logistics.ClientPalletState[palletId]
    if pallet then
        pallet.is_sealed = isSealed
        if sealSerial then
            pallet.seal_serial = sealSerial
        end
    end

    local msg = isSealed and "Raklap zárolva és plombálva a szállításhoz." or "Raklap plomba felnyitva, rakomány hozzáférhető."
    TriggerEvent("nyx:core:client:notify", msg, "info")
end)

RegisterNetEvent("nyx:logistics:client:palletBreached", function(data)
    if not data or not data.palletId then return end
    local pallet = Nyx.Logistics.ClientPalletState[data.palletId]
    if pallet then
        pallet.is_sealed = false
        pallet.is_tampered = true
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    if data.coords then
        local dist = #(pCoords - vector3(data.coords.x, data.coords.y, data.coords.z))
        if dist <= 30.0 then
            PlaySoundFrontend(-1, "Wood_Snap", "HUD_AWARDS", true)
            if dist <= 8.0 then
                ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", 0.15)
            end
        end
    end
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
                    label = "Plomba Kifeszítése (Feszítővas)",
                    icon = "fa-solid fa-screwdriver-wrench",
                    canInteract = function(entity)
                        local palletId = Entity(entity).state.palletId
                        local p = palletId and Nyx.Logistics.ClientPalletState[palletId]
                        return (p and p.is_sealed == true)
                    end,
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if not palletId then return end

                        local ped = PlayerPedId()
                        local dict = "melee@crowbar@streamed_core"
                        RequestAnimDict(dict)
                        local timeout = 0
                        while not HasAnimDictLoaded(dict) and timeout < 20 do
                            Wait(50)
                            timeout = timeout + 1
                        end

                        TaskPlayAnim(ped, dict, "attack_heavy", 8.0, -8.0, 3000, 49, 0, false, false, false)
                        TriggerEvent("nyx:core:client:notify", "Biztonsági acélpánt feszítése...", "info")
                        Wait(3000)
                        ClearPedTasks(ped)

                        local pCoords = GetEntityCoords(ped)
                        local res = exports['nyx_core']:TriggerRPCAwait("logistics:breachPallet", {
                            palletId = palletId,
                            toolItem = "tool_crowbar",
                            coords = { x = pCoords.x, y = pCoords.y, z = pCoords.z }
                        })

                        if res and res.success then
                            TriggerEvent("nyx:core:client:notify", "A raklap plomba sikeresen felfeszítve! Acélpántok elpattantak.", "success")
                        else
                            TriggerEvent("nyx:core:client:notify", "Felfeszítés meghiúsult: " .. tostring(res and res.error or "Hiba"), "error")
                        end
                    end
                },
                {
                    label = "Bűnügyi Helyszínelés / Nyomelemzés",
                    icon = "fa-solid fa-fingerprint",
                    canInteract = function(entity)
                        local palletId = Entity(entity).state.palletId
                        local p = palletId and Nyx.Logistics.ClientPalletState[palletId]
                        return (p and (p.is_tampered == true or p.is_sealed == false))
                    end,
                    action = function(entity)
                        local palletId = Entity(entity).state.palletId
                        if not palletId then return end

                        local res = exports['nyx_core']:TriggerRPCAwait("logistics:inspectPalletForensics", palletId)
                        if res and res.success and res.data then
                            local f = res.data
                            local tamperedText = f.isTampered and "^1ERŐSZAKOSAN FELTÖRVE^7" or "^2ÉP^7"
                            local sealText = f.sealSerial or "NINCS"
                            local markers = f.evidenceMarkers or {}
                            TriggerEvent("chat:addMessage", {
                                color = { 0, 180, 255 },
                                multiline = true,
                                args = { "Bűnügyi Helyszínelés", string.format("Raklap: %s | Állapot: %s | Plomba: %s | Rögzített nyomok: %d",
                                    f.palletId, tamperedText, sealText, #markers) }
                            })
                            for _, ev in ipairs(markers) do
                                TriggerEvent("chat:addMessage", {
                                    color = { 255, 200, 50 },
                                    args = { "Nyomjelző", string.format("Típus: %s | Hash: %s", string.upper(ev.type or "ISMERETLEN"), string.sub(ev.hash or "", 1, 16)) }
                                })
                            end
                        else
                            TriggerEvent("nyx:core:client:notify", "Nem található vizsgálati eredmény ezen a raklapon.", "info")
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

-- 7. Commands for Pallet Breach and Forensic Inspection
RegisterCommand("breachpallet", function(source, args)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local closestPalletId = nil
    local closestDist = 5.0

    for id, p in pairs(Nyx.Logistics.ClientPalletState) do
        if p.coords then
            local d = #(pCoords - vector3(p.coords.x, p.coords.y, p.coords.z))
            if d < closestDist then
                closestDist = d
                closestPalletId = id
            end
        end
    end

    if not closestPalletId then
        TriggerEvent("nyx:core:client:notify", "Nincs leplombált raklap a közeledben (5m)!", "error")
        return
    end

    local dict = "melee@crowbar@streamed_core"
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 20 do
        Wait(50)
        timeout = timeout + 1
    end

    TaskPlayAnim(ped, dict, "attack_heavy", 8.0, -8.0, 3000, 49, 0, false, false, false)
    TriggerEvent("nyx:core:client:notify", "Biztonsági acélpánt feszítése feszítővassal...", "info")
    Wait(3000)
    ClearPedTasks(ped)

    local res = exports['nyx_core']:TriggerRPCAwait("logistics:breachPallet", {
        palletId = closestPalletId,
        toolItem = "tool_crowbar",
        coords = { x = pCoords.x, y = pCoords.y, z = pCoords.z }
    })

    if res and res.success then
        TriggerEvent("nyx:core:client:notify", "A raklap plomba sikeresen feltörve!", "success")
    else
        TriggerEvent("nyx:core:client:notify", "Feltörés meghiúsult: " .. tostring(res and res.error or "Hiba"), "error")
    end
end, false)

RegisterCommand("inspectpallet", function(source, args)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local closestPalletId = nil
    local closestDist = 5.0

    for id, p in pairs(Nyx.Logistics.ClientPalletState) do
        if p.coords then
            local d = #(pCoords - vector3(p.coords.x, p.coords.y, p.coords.z))
            if d < closestDist then
                closestDist = d
                closestPalletId = id
            end
        end
    end

    if not closestPalletId then
        TriggerEvent("nyx:core:client:notify", "Nincs raklap a közeledben (5m)!", "error")
        return
    end

    local res = exports['nyx_core']:TriggerRPCAwait("logistics:inspectPalletForensics", closestPalletId)
    if res and res.success and res.data then
        local f = res.data
        local tamperedText = f.isTampered and "^1ERŐSZAKOSAN FELTÖRVE^7" or "^2ÉP^7"
        local sealText = f.sealSerial or "NINCS"
        local markers = f.evidenceMarkers or {}
        TriggerEvent("chat:addMessage", {
            color = { 0, 180, 255 },
            multiline = true,
            args = { "Helyszínelés", string.format("Raklap: %s | Állapot: %s | Plomba kód: %s | Nyomok száma: %d",
                f.palletId, tamperedText, sealText, #markers) }
        })
    else
        TriggerEvent("nyx:core:client:notify", "Nem található raklap adat.", "error")
    end
end, false)

