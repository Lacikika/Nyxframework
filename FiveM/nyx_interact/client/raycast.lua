--[[
    Nyxframework: nyx_interact
    File: client/raycast.lua
    Description: Spatial raycasting math, camera vector calculations, and dormant state execution loop.
]]

Nyx = Nyx or {}
Nyx.Math = Nyx.Math or {}
Nyx.Interact = Nyx.Interact or {}

Nyx.Interact.IsActive = false
Nyx.Interact.CurrentTarget = nil
Nyx.Interact.HasAudibleTarget = false

-- 1. Math: Ensure Camera Rotation to Direction Vector is available
if not Nyx.Math.RotationToDirection then
    function Nyx.Math.RotationToDirection(rot)
        local z = math.rad(rot.z)
        local x = math.rad(rot.x)
        local num = math.abs(math.cos(x))
        return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
    end
end

-- 2. Execute Hardware-Accelerated LosProbe Shape Test
function Nyx.Interact.CastCameraRay(distance)
    local camRot = GetGameplayCamRot(2)
    local camCoord = GetGameplayCamCoord()
    local forwardVector = Nyx.Math.RotationToDirection(camRot)
    local targetCoord = camCoord + (forwardVector * (distance or Config.Raycast.MaxDistance))

    local rayHandle = StartShapeTestLosProbe(
        camCoord.x, camCoord.y, camCoord.z,
        targetCoord.x, targetCoord.y, targetCoord.z,
        Config.Raycast.LosProbeFlag or -1,
        PlayerPedId(),
        Config.Raycast.GlassIgnored or 4
    )

    local retval, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
    return (hit == 1), entityHit, endCoords, surfaceNormal
end

-- 3. Dormant Execution Thread (0.00 ms idle, active only during key press)
CreateThread(function()
    while true do
        if not Nyx.Interact.IsActive then
            Wait(Config.Raycast.InactiveSleepMs or 250)
        else
            local hit, entityHit, endCoords = Nyx.Interact.CastCameraRay(Config.Raycast.MaxDistance)
            local options = {}
            local category = nil

            if hit and (entityHit ~= 0 or endCoords) then
                options, category = Nyx.Interact.EvaluateTarget(entityHit, endCoords)
            end

            if options and #options > 0 then
                if not Nyx.Interact.HasAudibleTarget then
                    Nyx.Interact.HasAudibleTarget = true
                    if Config.Audio and Config.Audio.Enabled then
                        PlaySoundFrontend(-1, Config.Audio.TargetAcquiredSound, Config.Audio.TargetAcquiredBank, true)
                    end
                end

                Nyx.Interact.CurrentTarget = {
                    entity = entityHit,
                    coords = endCoords,
                    category = category,
                    options = options
                }

                -- Dispatch NUI update to nyx_ui
                if exports['nyx_ui'] and exports['nyx_ui'].Send then
                    exports['nyx_ui']:Send("interact", "SET_TARGET", {
                        hasTarget = true,
                        category = category,
                        options = options,
                        coords = { x = endCoords.x, y = endCoords.y, z = endCoords.z }
                    })
                end
            else
                if Nyx.Interact.HasAudibleTarget then
                    Nyx.Interact.HasAudibleTarget = false
                    Nyx.Interact.CurrentTarget = nil

                    if exports['nyx_ui'] and exports['nyx_ui'].Send then
                        exports['nyx_ui']:Send("interact", "CLEAR_TARGET", {
                            hasTarget = false
                        })
                    end
                end
            end

            Wait(Config.Raycast.ActiveSleepMs or 0)
        end
    end
end)
