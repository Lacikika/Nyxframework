--[[
    Nyxframework: nyx_inventory
    File: client/placement.lua
    Description: 60 FPS client-side hologram interpolation, zero-packet dragging & rotation engine,
                 and movement freeze control lock during physical world placement.
]]

Nyx = Nyx or {}
Nyx.Placement = Nyx.Placement or {}

Nyx.Placement.IsActive = false
Nyx.Placement.GhostEntity = nil
Nyx.Placement.CurrentData = nil
Nyx.Placement.CurrentCoords = nil
Nyx.Placement.CurrentHeading = 0.0
Nyx.Placement.OriginalDropEntity = nil

-- Check if currently actively placing/rotating an item in the world
function Nyx.Placement.IsPlacing()
    return Nyx.Placement.IsActive
end

-- Start Hologram Placement Mode
function Nyx.Placement.Start(data)
    if not data then return end
    if Nyx.Placement.IsActive then
        Nyx.Placement.Cancel()
    end

    local ped = PlayerPedId()
    if IsPlayerDead(ped) or IsPedInAnyVehicle(ped, true) then return end

    Nyx.Placement.CurrentData = data
    Nyx.Placement.CurrentHeading = 0.0
    Nyx.Placement.OriginalDropEntity = nil

    -- Determine model hash
    local modelHash = nil
    if data.model then
        modelHash = (type(data.model) == "string") and GetHashKey(data.model) or data.model
    elseif data.itemId and Nyx.Items and Nyx.Items.Get then
        local itemDef = Nyx.Items.Get(data.itemId)
        if itemDef and itemDef.client and itemDef.client.model then
            modelHash = itemDef.client.model
        end
    end

    if not modelHash then
        modelHash = GetHashKey(Config.DropModel or "prop_paper_bag_small")
    end

    -- If repositioning an existing drop, temporarily hide its physical world entity
    if data.dropId and Nyx.Drops and Nyx.Drops[data.dropId] then
        local existingDrop = Nyx.Drops[data.dropId]
        if existingDrop.entity and DoesEntityExist(existingDrop.entity) then
            SetEntityVisible(existingDrop.entity, false, false)
            Nyx.Placement.OriginalDropEntity = existingDrop.entity
        end
        if existingDrop.rotation and existingDrop.rotation.heading then
            Nyx.Placement.CurrentHeading = tonumber(existingDrop.rotation.heading) or 0.0
        end
    end

    -- Request Model
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 50 do
        Wait(20)
        timeout = timeout + 1
    end

    if not HasModelLoaded(modelHash) then
        if Nyx.Placement.OriginalDropEntity and DoesEntityExist(Nyx.Placement.OriginalDropEntity) then
            SetEntityVisible(Nyx.Placement.OriginalDropEntity, true, false)
        end
        return
    end

    -- Create local ghost prop (100% client-side, zero network presence)
    local pCoords = GetEntityCoords(ped)
    local ghost = CreateObject(modelHash, pCoords.x, pCoords.y, pCoords.z, false, false, false)
    SetEntityCollision(ghost, false, false)
    SetEntityAlpha(ghost, (Config.Placement and Config.Placement.HologramAlpha) or 180, false)
    SetEntityInvincible(ghost, true)

    Nyx.Placement.GhostEntity = ghost
    Nyx.Placement.IsActive = true
    Nyx.Placement.CurrentCoords = pCoords

    -- Inform UI about placement mode
    if exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:Send("placement", "START", {
            label = data.label or data.itemId or "World Object"
        })
    end

    -- 60 FPS Client-Side Interpolation & Movement Freeze Thread
    CreateThread(function()
        local maxPlacementDist = (Config.Placement and Config.Placement.MaxDistance) or 6.0
        local rotationStep = (Config.Placement and Config.Placement.RotationStep) or 5.0
        local fineStep = (Config.Placement and Config.Placement.FineRotationStep) or 1.0

        while Nyx.Placement.IsActive and DoesEntityExist(Nyx.Placement.GhostEntity) do
            -- 1. Movement & Combat Freeze: Lock character locomotion while keeping camera/look active
            DisableControlAction(0, 30, true)  -- MoveLeftRight (A/D)
            DisableControlAction(0, 31, true)  -- MoveUpDown (W/S)
            DisableControlAction(0, 21, true)  -- Sprint (Shift)
            DisableControlAction(0, 22, true)  -- Jump (Space)
            DisableControlAction(0, 23, true)  -- Enter vehicle (F)
            DisableControlAction(0, 24, true)  -- Attack (LMB)
            DisableControlAction(0, 25, true)  -- Aim (RMB)
            DisableControlAction(0, 44, true)  -- Cover (Q)
            DisableControlAction(0, 140, true) -- Light Melee
            DisableControlAction(0, 141, true) -- Heavy Melee
            DisableControlAction(0, 142, true) -- Melee Block

            -- 2. Precision Camera Raycast for Surface Snapping
            local playerCoords = GetEntityCoords(ped)
            local hit, entityHit, hitCoords = false, 0, nil

            if Nyx.Interact and Nyx.Interact.CastCameraRay then
                hit, entityHit, hitCoords = Nyx.Interact.CastCameraRay(maxPlacementDist)
            else
                local camRot = GetGameplayCamRot(2)
                local camCoord = GetGameplayCamCoord()
                local z = math.rad(camRot.z)
                local x = math.rad(camRot.x)
                local num = math.abs(math.cos(x))
                local fwd = vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
                local target = camCoord + (fwd * maxPlacementDist)

                local ray = StartShapeTestLosProbe(camCoord.x, camCoord.y, camCoord.z, target.x, target.y, target.z, -1, ped, 4)
                local retval, hitRes, endCoords = GetShapeTestResult(ray)
                hit = (hitRes == 1)
                hitCoords = endCoords
            end

            local targetCoords = hitCoords
            if not hit or not targetCoords then
                local camRot = GetGameplayCamRot(2)
                local camCoord = GetGameplayCamCoord()
                local z = math.rad(camRot.z)
                local x = math.rad(camRot.x)
                local num = math.abs(math.cos(x))
                local fwd = vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
                targetCoords = camCoord + (fwd * (maxPlacementDist * 0.75))
            end

            -- Clamp distance to player
            local dist = #(playerCoords - targetCoords)
            if dist > maxPlacementDist then
                local dir = targetCoords - playerCoords
                local normDir = dir / dist
                targetCoords = playerCoords + (normDir * maxPlacementDist)
            end

            -- Update Ghost Entity Transform (Zero network traffic)
            Nyx.Placement.CurrentCoords = targetCoords
            SetEntityCoords(Nyx.Placement.GhostEntity, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false, true)
            SetEntityHeading(Nyx.Placement.GhostEntity, Nyx.Placement.CurrentHeading)

            -- 3. Rotation Input Handling
            local step = IsDisabledControlPressed(0, 21) and fineStep or rotationStep
            -- Mouse wheel up / Q / Left arrow
            if IsDisabledControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 44) or IsDisabledControlJustPressed(0, 174) then
                Nyx.Placement.CurrentHeading = (Nyx.Placement.CurrentHeading + step) % 360.0
            end
            -- Mouse wheel down / E / Right arrow
            if IsDisabledControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 175) then
                Nyx.Placement.CurrentHeading = (Nyx.Placement.CurrentHeading - step + 360.0) % 360.0
            end

            -- 4. Confirm Placement (LMB)
            if IsDisabledControlJustPressed(0, 24) then
                Nyx.Placement.Commit()
                break
            end

            -- 5. Cancel Placement (RMB or ESC)
            if IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 200) then
                Nyx.Placement.Cancel()
                break
            end

            Wait(0)
        end
    end)
end

-- Commit Placement via Single Validated RPC
function Nyx.Placement.Commit()
    if not Nyx.Placement.IsActive then return end

    local data = Nyx.Placement.CurrentData
    local coords = Nyx.Placement.CurrentCoords
    local heading = Nyx.Placement.CurrentHeading
    local ghost = Nyx.Placement.GhostEntity
    local origEnt = Nyx.Placement.OriginalDropEntity

    -- Delete local ghost entity
    Nyx.Placement.IsActive = false
    if ghost and DoesEntityExist(ghost) then
        DeleteEntity(ghost)
    end
    Nyx.Placement.GhostEntity = nil

    if exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:Send("placement", "STOP", {})
    end

    if not coords or not data then
        if origEnt and DoesEntityExist(origEnt) then
            SetEntityVisible(origEnt, true, false)
        end
        return
    end

    -- Play acoustic placement confirmation
    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)

    -- Transmit single validated RPC call to server
    CreateThread(function()
        local payload = {
            dropId = data.dropId,
            fromInv = data.fromInv,
            slot = data.slot,
            amount = data.amount,
            itemId = data.itemId,
            coords = {
                x = math.floor(coords.x * 100) / 100,
                y = math.floor(coords.y * 100) / 100,
                z = math.floor(coords.z * 100) / 100
            },
            rotation = {
                x = 0.0,
                y = 0.0,
                z = math.floor(heading * 100) / 100,
                heading = math.floor(heading * 100) / 100
            }
        }

        local result = exports['nyx_core']:TriggerRPCAwait("inventory:commitWorldPlacement", payload)
        if not result or not result.success then
            -- Fallback restore if failed
            if origEnt and DoesEntityExist(origEnt) then
                SetEntityVisible(origEnt, true, false)
            end
            if exports['nyx_ui'] and exports['nyx_ui'].Notify then
                exports['nyx_ui']:Notify("error", "PLACEMENT", result and result.error or "Failed to place item.")
            end
        else
            if exports['nyx_ui'] and exports['nyx_ui'].Notify then
                exports['nyx_ui']:Notify("success", "PLACEMENT", "World item positioned successfully.")
            end
        end
    end)
end

-- Cancel Placement Mode
function Nyx.Placement.Cancel()
    if not Nyx.Placement.IsActive then return end

    Nyx.Placement.IsActive = false
    if Nyx.Placement.GhostEntity and DoesEntityExist(Nyx.Placement.GhostEntity) then
        DeleteEntity(Nyx.Placement.GhostEntity)
    end
    Nyx.Placement.GhostEntity = nil

    if Nyx.Placement.OriginalDropEntity and DoesEntityExist(Nyx.Placement.OriginalDropEntity) then
        SetEntityVisible(Nyx.Placement.OriginalDropEntity, true, false)
    end
    Nyx.Placement.OriginalDropEntity = nil

    if exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:Send("placement", "STOP", {})
    end
    if exports['nyx_ui'] and exports['nyx_ui'].Notify then
        exports['nyx_ui']:Notify("info", "PLACEMENT", "Placement cancelled.")
    end
end

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if Nyx.Placement.IsActive then
        Nyx.Placement.Cancel()
    end
end)

-- Public Exports
exports('StartPlacement', function(data)
    Nyx.Placement.Start(data)
end)

exports('CancelPlacement', function()
    Nyx.Placement.Cancel()
end)

exports('IsPlacing', function()
    return Nyx.Placement.IsPlacing()
end)

-- Event Listeners
RegisterNetEvent("nyx:inventory:client:startPlacement", function(data)
    Nyx.Placement.Start(data)
end)
