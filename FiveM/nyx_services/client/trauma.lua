--[[
    Nyxframework: nyx_services
    File: client/trauma.lua
    Description: Client-side damage detection, anatomical bone mapping,
                 physiological debuff loop (limping, tremors, ragdoll fainting), and triage commands.
]]

Nyx = Nyx or {}
Nyx.Trauma = Nyx.Trauma or {}

local localTrauma = Nyx.Trauma.CreateInitialTraumaState()
local isInjuredMovementActive = false

-- 1. State Synchronization Events
RegisterNetEvent("nyx:services:client:traumaSync", function(state)
    if type(state) == "table" then
        if state.bloodVolume then localTrauma.bloodVolume = state.bloodVolume end
        if state.bleedingRate then localTrauma.bleedingRate = state.bleedingRate end
        if state.painLevel then localTrauma.painLevel = state.painLevel end
        if state.isUnconscious ~= nil then localTrauma.isUnconscious = state.isUnconscious end
        if type(state.limbs) == "table" then
            localTrauma.limbs = state.limbs
        end
    end
end)

RegisterNetEvent("nyx:services:client:hemodynamicTick", function(tickData)
    if type(tickData) == "table" then
        if tickData.bloodVolume then localTrauma.bloodVolume = tickData.bloodVolume end
        if tickData.bleedingRate then localTrauma.bleedingRate = tickData.bleedingRate end
        if tickData.isUnconscious ~= nil then localTrauma.isUnconscious = tickData.isUnconscious end
    end
end)

RegisterNetEvent("nyx:services:client:unconsciousState", function(isUnconscious)
    localTrauma.isUnconscious = isUnconscious
    if isUnconscious then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "KRITIKUS VÉRNYOMÁS-ÖSSZEOMLÁS",
            message = "A súlyos hipovolémia miatt elvesztetted az eszméletedet!"
        })
    end
end)

-- 2. Damage Ingestion & Anatomical Bone Hit Detection
AddEventHandler("gameEventTriggered", function(name, args)
    if name ~= "CEventNetworkEntityDamage" then return end

    local victim = args[1]
    local attacker = args[2]
    local isFatal = (args[6] == 1)
    local weaponHash = args[7]

    local myPed = PlayerPedId()
    if victim ~= myPed then return end

    -- Extract damaged bone index
    local ok, boneId = GetPedLastDamageBone(myPed)
    local hitBone = 24818 -- Fallback: Spine
    if ok and boneId then
        hitBone = boneId
    end

    local limb = Nyx.Trauma.GetLimbFromBone(hitBone)
    local woundType = "laceration"

    -- Classify wound type by weapon damage type
    if weaponHash then
        local weaponType = GetWeaponDamageType(weaponHash)
        if weaponType == 2 then -- Melee / Slash
            woundType = "laceration"
        elseif weaponType == 3 then -- Ballistic / Bullets
            woundType = "ballistic"
        elseif weaponType == 4 or weaponType == 5 then -- Explosive / Fire
            woundType = "burn"
        elseif weaponType == 6 or weaponType == 13 then -- Blunt / Collision
            woundType = "blunt"
        end
    end

    -- High-impact threshold: chance of bone fracture or arterial bleeding
    local currentHealth = GetEntityHealth(myPed)
    local severity = 1.0
    if isFatal or currentHealth <= 120 then
        severity = 2.0
        if woundType == "ballistic" and (limb == "left_leg" or limb == "right_leg" or limb == "left_arm" or limb == "right_arm") then
            -- 35% chance of arterial puncture on high-impact extremity ballistic trauma
            if math.random(1, 100) <= 35 then
                woundType = "arterial_bleed"
            end
        end
    end

    -- Report trauma damage to server
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:syncTraumaDamage", {
            limb = limb,
            woundType = woundType,
            severity = severity
        }, function(response)
            if response and response.success then
                -- Local feedback
                if woundType == "arterial_bleed" then
                    TriggerEvent("nyx:ui:notify", {
                        type = "error",
                        title = "ARTÉRIÁS VÉRZÉS!",
                        message = string.format("Kritikus artériás vérzés a(z) %s területén! Helyezz fel érszorítót!",
                            Nyx.Trauma.LimbLabels[limb] or limb)
                    })
                end
            end
        end)
    end
end)

-- 3. Physiological Debuff & Hemodynamic Reaction Loop
CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            local limbs = localTrauma.limbs or {}
            local leftLeg = limbs.left_leg or {}
            local rightLeg = limbs.right_leg or {}
            local leftArm = limbs.left_arm or {}
            local rightArm = limbs.right_arm or {}

            -- 3A. Mobility & Limping Debuff
            local hasLegFracture = (leftLeg.isFractured == true or rightLeg.isFractured == true)
            local hasSevereLegDamage = ((leftLeg.health or 100) < 30 or (rightLeg.health or 100) < 30)

            if hasLegFracture or hasSevereLegDamage then
                if not isInjuredMovementActive then
                    RequestAnimSet("move_m@injured")
                    while not HasAnimSetLoaded("move_m@injured") do
                        Wait(50)
                    end
                    SetPedMovementClipset(ped, "move_m@injured", 1.0)
                    isInjuredMovementActive = true
                end
            else
                if isInjuredMovementActive then
                    ResetPedMovementClipset(ped, 0.0)
                    isInjuredMovementActive = false
                end
            end

            -- 3B. Weapon Sway / Aim Tremor Debuff
            local hasArmFracture = (leftArm.isFractured == true or rightArm.isFractured == true)
            if hasArmFracture and IsPedArmed(ped, 4) and IsPlayerFreeAiming(PlayerId()) then
                ShakeGameplayCam("HAND_SHAKE", 0.4)
            end

            -- 3C. Hypovolemic Shock Vitals & Syncope (Fainting)
            local shockClass, _, isUnc, meta = Nyx.Trauma.CalculateShockClass(localTrauma.bloodVolume)

            if isUnc or localTrauma.isUnconscious then
                -- Ragdoll fainting collapse
                if not IsPedRagdoll(ped) then
                    SetPedToRagdoll(ped, 3000, 3000, 0, false, false, false)
                end
            elseif shockClass == 3 then
                -- Severe shock: occasional stumbling
                if math.random() < (meta.stumbleChance or 0.20) and not IsPedRagdoll(ped) and IsPedOnFoot(ped) then
                    SetPedToRagdoll(ped, 1200, 1200, 0, false, false, false)
                end
            end
        end
    end
end)

-- 4. Triage Examination Command
RegisterCommand("diagnose", function(source, args)
    local targetId = tonumber(args[1]) or GetPlayerServerId(PlayerId())

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:diagnosePatient", targetId, function(response)
            if response and response.success and response.diagnosis then
                local d = response.diagnosis
                print("^5[Nyx:Medical] ====== ANATÓMIAI TRIÁZS JELENTÉS ======^7")
                print(string.format("^3Vértérfogat:^7 %d mL / %d mL | ^3Vérzésráta:^7 %.2f mL/s",
                    d.bloodVolume, d.maxBloodVolume, d.bleedingRate))
                print(string.format("^3Sokk Osztály:^7 %s (^1Fájdalom: %d/100^7)", d.shockLabel, d.painLevel))
                for limbKey, limbData in pairs(d.limbs or {}) do
                    local bleedTag = limbData.isBleeding and "^1[VÉRZIK]^7" or "^2[Stabil]^7"
                    local fracTag = limbData.isFractured and "^1[TÖRÖTT]^7" or ""
                    local tournTag = limbData.hasTourniquet and "^3[Érszorító]^7" or ""
                    print(string.format("  - %s: Életerő %d/100 %s %s %s (%d seb)",
                        limbData.label, limbData.health, bleedTag, fracTag, tournTag, limbData.woundsCount))
                end
                print("^5==================================================^7")

                TriggerEvent("nyx:ui:notify", {
                    type = "info",
                    title = "ORVOSI VIZSGÁLAT",
                    message = string.format("Állapot: %s. Vértérfogat: %d mL. Részletek a konzolban (F8).",
                        d.shockLabel, d.bloodVolume)
                })
            else
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "HIBA",
                    message = tostring(response and response.error or "A vizsgálat sikertelen.")
                })
            end
        end)
    end
end, false)

-- 5. Field Stabilization Treatment Command
RegisterCommand("treat", function(source, args)
    local targetId = tonumber(args[1])
    local limb = args[2]
    local item = args[3]

    if not targetId or not limb or not item then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "HASZNÁLAT",
            message = "Használat: /treat [célpontId] [testrész: head|torso|left_arm|right_arm|left_leg|right_leg] [tárgy]"
        })
        return
    end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:applyMedicalItem", {
            targetSrc = targetId,
            limb = limb,
            item = item
        }, function(response)
            if response and response.success then
                TriggerEvent("nyx:ui:notify", {
                    type = "success",
                    title = "SIKERES KEZELÉS",
                    message = string.format("Ellátás (%s) felhelyezve: %s.", item, limb)
                })
            else
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "ELLÁTÁSI HIBA",
                    message = tostring(response and response.error or "A kezelés meghiúsult.")
                })
            end
        end)
    end
end, false)

-- 6. Client Exports
exports("GetLocalTraumaState", function()
    return localTrauma
end)

exports("GetLimbHealth", function(limb)
    if localTrauma and localTrauma.limbs and localTrauma.limbs[limb] then
        return localTrauma.limbs[limb].health or 100
    end
    return 100
end)

exports("IsBleeding", function()
    return (localTrauma and localTrauma.bleedingRate and localTrauma.bleedingRate > 0) or false
end)

exports("GetShockClass", function()
    local vol = localTrauma and localTrauma.bloodVolume or 5000
    local classNum, classLabel, isUnc, meta = Nyx.Trauma.CalculateShockClass(vol)
    return classNum, classLabel, isUnc, meta
end)
