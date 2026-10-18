--[[
    Nyxframework: nyx_inventory
    File: client/freight.lua
    Description: Client-side heavy freight physics controller: two-handed physical carry animations,
                 locomotion overrides, prop attachment, and vehicle loading interactions.
]]

Nyx = Nyx or {}
Nyx.Freight = Nyx.Freight or {}
Nyx.Freight.IsCarrying = false
Nyx.Freight.AttachedProp = nil
Nyx.Freight.CarriedDropId = nil
Nyx.Freight.CarriedModel = nil

local animDict = (Config.HeavyCarry and Config.HeavyCarry.AnimDict) or "anim@heists@box_carry@"
local animName = (Config.HeavyCarry and Config.HeavyCarry.AnimName) or "idle"

-- Check if player is currently carrying heavy freight physically
function Nyx.Freight.IsCarryingFreight()
    return Nyx.Freight.IsCarrying or ((LocalPlayer and LocalPlayer.state and LocalPlayer.state.isCarryingHeavyFreight == true) or false)
end

-- Start physical two-handed carry on client
function Nyx.Freight.StartCarry(dropId, modelName)
    if Nyx.Freight.IsCarrying then return end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end

    modelName = modelName or "prop_box_wood02a"
    local modelHash = (type(modelName) == "string") and GetHashKey(modelName) or modelName

    -- Request Prop Model
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 50 do
        Wait(20)
        timeout = timeout + 1
    end

    -- Request Carry Animation Dictionary
    RequestAnimDict(animDict)
    local animTimeout = 0
    while not HasAnimDictLoaded(animDict) and animTimeout < 50 do
        Wait(20)
        animTimeout = animTimeout + 1
    end

    -- Create local physical attached prop
    local pCoords = GetEntityCoords(ped)
    local propObj = CreateObject(modelHash, pCoords.x, pCoords.y, pCoords.z, true, true, true)
    SetEntityCollision(propObj, false, false)

    local boneIdx = GetPedBoneIndex(ped, (Config.HeavyCarry and Config.HeavyCarry.BoneIndex) or 60309)
    local offset = (Config.HeavyCarry and Config.HeavyCarry.AttachOffset) or { x = 0.0, y = 0.40, z = -0.15 }
    local rot = (Config.HeavyCarry and Config.HeavyCarry.AttachRot) or { x = 0.0, y = 0.0, z = 0.0 }

    AttachEntityToEntity(
        propObj,
        ped,
        boneIdx,
        offset.x, offset.y, offset.z,
        rot.x, rot.y, rot.z,
        true, true, false, true, 1, true
    )

    Nyx.Freight.IsCarrying = true
    Nyx.Freight.AttachedProp = propObj
    Nyx.Freight.CarriedDropId = dropId
    Nyx.Freight.CarriedModel = modelName

    -- Play Initial Upper-Body Carry Animation (Flag 49: upper body only, allowing walk)
    TaskPlayAnim(ped, animDict, animName, 3.0, 3.0, -1, 49, 0, false, false, false)

    -- Inform UI HUD of Heavy Freight Carry Mode
    if exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:Send("freight", "CARRY_START", {
            dropId = dropId,
            model = modelName,
            label = "Heavy Industrial Crate"
        })
    end

    -- Active Carry Processing Thread: Animation Maintenance & Control Lockouts
    CreateThread(function()
        while Nyx.Freight.IsCarrying and DoesEntityExist(Nyx.Freight.AttachedProp) do
            local currentPed = PlayerPedId()

            if IsEntityDead(currentPed) or IsPedInAnyVehicle(currentPed, false) then
                Nyx.Freight.StopCarry()
                break
            end

            -- Re-trigger upper-body animation if interrupted
            if not IsEntityPlayingAnim(currentPed, animDict, animName, 3) then
                TaskPlayAnim(currentPed, animDict, animName, 3.0, 3.0, -1, 49, 0, false, false, false)
            end

            -- Tier 3 Heavy Freight Locomotion & Combat Invariant Lockouts
            DisableControlAction(0, 21, true)  -- Sprint (Shift)
            DisableControlAction(0, 22, true)  -- Jump (Space)
            DisableControlAction(0, 23, true)  -- Enter vehicle (F)
            DisableControlAction(0, 24, true)  -- Attack (LMB)
            DisableControlAction(0, 25, true)  -- Aim (RMB)
            DisableControlAction(0, 44, true)  -- Cover / Mantle (Q)
            DisableControlAction(0, 140, true) -- Light Melee
            DisableControlAction(0, 141, true) -- Heavy Melee
            DisableControlAction(0, 142, true) -- Melee Block

            -- Fast-Drop Input: Press G (Control 47) to place crate on ground
            if IsControlJustPressed(0, 47) and not (Nyx.Placement and Nyx.Placement.IsPlacing and Nyx.Placement.IsPlacing()) then
                Nyx.Freight.PlaceDown()
            end

            Wait(0)
        end
    end)
end

-- Stop carry and clean up entity
function Nyx.Freight.StopCarry()
    Nyx.Freight.IsCarrying = false

    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        StopAnimTask(ped, animDict, animName, 1.0)
    end

    if Nyx.Freight.AttachedProp and DoesEntityExist(Nyx.Freight.AttachedProp) then
        DetachEntity(Nyx.Freight.AttachedProp, true, true)
        DeleteEntity(Nyx.Freight.AttachedProp)
    end
    Nyx.Freight.AttachedProp = nil
    Nyx.Freight.CarriedDropId = nil
    Nyx.Freight.CarriedModel = nil

    if exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:Send("freight", "CARRY_STOP", {})
    end
end

-- Place down carried crate onto ground or shelf
function Nyx.Freight.PlaceDown()
    if not Nyx.Freight.IsCarrying then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- Project 0.8m forward in front of character
    local fwdX = -math.sin(math.rad(heading)) * 0.85
    local fwdY = math.cos(math.rad(heading)) * 0.85
    local placeVec = vector3(coords.x + fwdX, coords.y + fwdY, coords.z + (Config.DropZOffset or -0.95))

    local payload = {
        coords = {
            x = math.floor(placeVec.x * 100) / 100,
            y = math.floor(placeVec.y * 100) / 100,
            z = math.floor(placeVec.z * 100) / 100
        },
        rotation = {
            x = 0.0,
            y = 0.0,
            z = math.floor(heading * 100) / 100,
            heading = math.floor(heading * 100) / 100
        }
    }

    local res = exports['nyx_core']:TriggerRPCAwait("inventory:dropHeavyCarry", payload)
    if res and res.success then
        Nyx.Freight.StopCarry()
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

-- Interaction: Pick Up & Carry (Two-Handed) via Third-Eye (LALT)
RegisterNetEvent("nyx:inventory:client:pickupHeavyFreight", function(args, entity, netId, coords)
    local dropId = args and args.dropId
    if not dropId then return end

    local res = exports['nyx_core']:TriggerRPCAwait("inventory:startHeavyCarry", dropId)
    if res and res.success then
        Nyx.Freight.StartCarry(res.dropId, res.model)
    else
        local err = (res and res.error) or "CANNOT_CARRY"
        TriggerEvent("nyx:core:client:notify", string.format("Cannot carry: %s", err), "error")
    end
end)

-- Interaction: Load Carried Freight directly into nearby vehicle trunk
RegisterNetEvent("nyx:inventory:client:loadFreightToVehicle", function(args, entity, netId, coords)
    if not Nyx.Freight.IsCarrying then
        TriggerEvent("nyx:core:client:notify", "You are not carrying any freight crate!", "error")
        return
    end

    local vehicle = entity
    if not vehicle or not DoesEntityExist(vehicle) then
        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        vehicle = GetClosestVehicle and GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 4.0, 0, 71)
    end

    if not vehicle or not DoesEntityExist(vehicle) then
        TriggerEvent("nyx:core:client:notify", "No vehicle nearby to load freight!", "error")
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate then return end
    plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")

    local res = exports['nyx_core']:TriggerRPCAwait("inventory:loadHeavyFreightToVehicle", { plate = plate })
    if res and res.success then
        Nyx.Freight.StopCarry()
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        TriggerEvent("nyx:core:client:notify", "Heavy freight crate secured into vehicle trunk!", "success")
    else
        local err = (res and res.error) or "VEHICLE_LOAD_FAILED"
        TriggerEvent("nyx:core:client:notify", string.format("Failed to load vehicle: %s", err), "error")
    end
end)

-- Network Events: Synchronize world entity visibility when carried/released
RegisterNetEvent("nyx:inventory:client:dropCarried", function(dropId, carrierSource)
    if Nyx.Drops and Nyx.Drops[dropId] then
        local drop = Nyx.Drops[dropId]
        if drop.entity and DoesEntityExist(drop.entity) then
            SetEntityVisible(drop.entity, false, false)
        end
    end
end)

RegisterNetEvent("nyx:inventory:client:dropReleased", function(dropId, coords, rotation)
    if Nyx.Drops and Nyx.Drops[dropId] then
        local drop = Nyx.Drops[dropId]
        if coords then
            drop.coords = vector3(coords.x, coords.y, coords.z)
        end
        if rotation then
            drop.rotation = rotation
        end
        if drop.entity and DoesEntityExist(drop.entity) then
            SetEntityCoords(drop.entity, drop.coords.x, drop.coords.y, drop.coords.z, false, false, false, true)
            SetEntityHeading(drop.entity, (rotation and rotation.heading) or 0.0)
            SetEntityVisible(drop.entity, true, false)
        end
    end
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Nyx.Freight.StopCarry()
    end
end)

-- Public Client Exports
exports("IsCarryingFreight", function()
    return Nyx.Freight.IsCarryingFreight()
end)

exports("PlaceDownFreight", function()
    Nyx.Freight.PlaceDown()
end)
