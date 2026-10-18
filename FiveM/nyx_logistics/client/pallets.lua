--[[
    Nyxframework: nyx_logistics
    File: client/pallets.lua
    Description: Physical heavy freight pallet entity handling and vehicle loading mechanics.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.LocalPallets = {}

local palletModelHash = GetHashKey(Config.PalletModel or "prop_boxpile_06a")

-- Spawn physical freight pallet prop at coordinates
function Nyx.Logistics.SpawnPallet(coords, heading)
    RequestModel(palletModelHash)
    while not HasModelLoaded(palletModelHash) do
        Wait(50)
    end

    local obj = CreateObject(palletModelHash, coords.x, coords.y, coords.z, true, true, true)
    SetEntityHeading(obj, heading or 0.0)
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityDynamic(obj, true)
    ActivatePhysics(obj)

    Nyx.Logistics.LocalPallets[#Nyx.Logistics.LocalPallets + 1] = obj
    return obj
end

-- Attach pallet to commercial flatbed or forklift
function Nyx.Logistics.AttachPalletToVehicle(palletObj, vehicle, boneIndex, offset)
    if not DoesEntityExist(palletObj) or not DoesEntityExist(vehicle) then return false end

    offset = offset or vector3(0.0, -1.5, 0.5)
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

-- Detach pallet and drop on ground
function Nyx.Logistics.DetachPallet(palletObj)
    if not DoesEntityExist(palletObj) then return end
    DetachEntity(palletObj, true, true)
    PlaceObjectOnGroundProperly(palletObj)
end

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, obj in ipairs(Nyx.Logistics.LocalPallets) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
end)
