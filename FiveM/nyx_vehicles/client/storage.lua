--[[
    Nyxframework: nyx_vehicles
    File: client/storage.lua
    Description: Physical model bone proximity detection for trunk and glovebox containers,
                 lock validation, and nyx_inventory opening bridges.
]]

-- 1. Glovebox Interaction via Key Mapping (0.00 ms Idle)
RegisterCommand('nyx_open_glovebox', function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end

    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then return end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:openGlovebox", netId)
        if res and res.success then
            TriggerEvent("nyx:inventory:client:openContainer", res.containerId, "glovebox")
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "GLOVEBOX LOCKED",
                message = "The vehicle interior compartment is locked."
            })
        end
    end
end, false)

RegisterKeyMapping('nyx_open_glovebox', 'Open Glovebox Compartment', 'keyboard', 'G')

-- 2. Trunk Interaction via Key Mapping (0.00 ms Idle)
RegisterCommand('nyx_open_trunk', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local pCoords = GetEntityCoords(ped)
    local closeVeh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 5.0, 0, 71)
    if not DoesEntityExist(closeVeh) then return end

    local bootIndex = GetEntityBoneIndexByName(closeVeh, "boot")
    if bootIndex == -1 then bootIndex = GetEntityBoneIndexByName(closeVeh, "trunk") end

    local trunkCoords = nil
    if bootIndex ~= -1 then
        trunkCoords = GetWorldPositionOfEntityBone(closeVeh, bootIndex)
    else
        local min, max = GetModelDimensions(GetEntityModel(closeVeh))
        trunkCoords = GetOffsetFromEntityInWorldCoords(closeVeh, 0.0, min.y - 0.2, 0.0)
    end

    local distToTrunk = #(pCoords - trunkCoords)
    if distToTrunk <= (Config.Access and Config.Access.TrunkBoneDistance or 2.5) then
        local netId = NetworkGetNetworkIdFromEntity(closeVeh)
        if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
            local res = exports['nyx_core']:TriggerRPCAwait("vehicles:openTrunk", netId)
            if res and res.success then
                SetVehicleDoorOpen(closeVeh, 5, false, false)
                TriggerEvent("nyx:inventory:client:openContainer", res.containerId, "trunk")
            else
                PlaySoundFrontend(-1, "Keycard_Fail", "DLC_HEISTS_BIOLAB_FINALE_SOUNDS", true)
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "TRUNK LOCKED",
                    message = "The trunk is locked. Unlock the vehicle to access storage."
                })
            end
        end
    end
end, false)

RegisterKeyMapping('nyx_open_trunk', 'Open Vehicle Trunk', 'keyboard', 'E')
