--[[
    Nyxframework: nyx_interact
    File: client/registry.lua
    Description: Declarative target registries for models, entities, bones, and spatial coords.
]]

Nyx = Nyx or {}
Nyx.Interact = Nyx.Interact or {}

Nyx.Interact.Registry = {
    Models = {},    -- [modelHash] = { options = {}, distance = number }
    Entities = {},  -- [netId/handle] = { options = {}, distance = number }
    Bones = {},     -- [boneName] = { options = {}, distance = number }
    Coords = {}     -- [id] = { coords = vector3, radius = number, options = {}, distance = number }
}

-- 1. Register Models (prop hashes, vehicle hashes, ped hashes)
function Nyx.Interact.AddTargetModel(models, data)
    if not models or not data or not data.options then return end

    local modelList = (type(models) == "table") and models or { models }
    local maxDist = data.distance or Config.Distances.Default

    for _, model in ipairs(modelList) do
        local hash = (type(model) == "string") and joaat(model) or model
        Nyx.Interact.Registry.Models[hash] = {
            options = data.options,
            distance = maxDist
        }
    end
end

function Nyx.Interact.RemoveTargetModel(models)
    if not models then return end
    local modelList = (type(models) == "table") and models or { models }
    for _, model in ipairs(modelList) do
        local hash = (type(model) == "string") and joaat(model) or model
        Nyx.Interact.Registry.Models[hash] = nil
    end
end

-- 2. Register Specific Entities
function Nyx.Interact.AddTargetEntity(entities, data)
    if not entities or not data or not data.options then return end

    local entList = (type(entities) == "table") and entities or { entities }
    local maxDist = data.distance or Config.Distances.Default

    for _, ent in ipairs(entList) do
        local id = NetworkGetEntityIsNetworked(ent) and NetworkGetNetworkIdFromEntity(ent) or ent
        Nyx.Interact.Registry.Entities[id] = {
            options = data.options,
            distance = maxDist,
            handle = ent
        }
    end
end

function Nyx.Interact.RemoveTargetEntity(entities)
    if not entities then return end
    local entList = (type(entities) == "table") and entities or { entities }
    for _, ent in ipairs(entList) do
        local id = NetworkGetEntityIsNetworked(ent) and NetworkGetNetworkIdFromEntity(ent) or ent
        Nyx.Interact.Registry.Entities[id] = nil
    end
end

-- 3. Register Vehicle Bones (boot, bonnet, door_dside_f, dash, etc.)
function Nyx.Interact.AddTargetBone(bones, data)
    if not bones or not data or not data.options then return end

    local boneList = (type(bones) == "table") and bones or { bones }
    local maxDist = data.distance or Config.Distances.VehicleDoor

    for _, bone in ipairs(boneList) do
        local key = string.lower(bone)
        Nyx.Interact.Registry.Bones[key] = {
            options = data.options,
            distance = maxDist
        }
    end
end

function Nyx.Interact.RemoveTargetBone(bones)
    if not bones then return end
    local boneList = (type(bones) == "table") and bones or { bones }
    for _, bone in ipairs(boneList) do
        local key = string.lower(bone)
        Nyx.Interact.Registry.Bones[key] = nil
    end
end

-- 4. Register Coordinate Spheres (terminals, desks, voting booths)
function Nyx.Interact.AddTargetCoords(id, coords, radius, data)
    if not id or not coords or not data or not data.options then return end

    Nyx.Interact.Registry.Coords[id] = {
        coords = vector3(coords.x, coords.y, coords.z),
        radius = radius or 2.0,
        options = data.options,
        distance = data.distance or (radius or 2.0)
    }
end

function Nyx.Interact.RemoveTargetCoords(id)
    if not id then return end
    Nyx.Interact.Registry.Coords[id] = nil
end

-- 5. Evaluate Target Options on Raycast Hit
function Nyx.Interact.EvaluateTarget(hitEntity, hitCoords)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local results = {}
    local matchedCategory = nil

    -- A. Evaluate Raycast Hit Entity
    if hitEntity and hitEntity ~= 0 and DoesEntityExist(hitEntity) then
        local entCoords = GetEntityCoords(hitEntity)
        local entDist = #(playerCoords - entCoords)
        local modelHash = GetEntityModel(hitEntity)

        -- Check Entity-specific options
        local netId = NetworkGetEntityIsNetworked(hitEntity) and NetworkGetNetworkIdFromEntity(hitEntity) or nil
        local entEntry = (netId and Nyx.Interact.Registry.Entities[netId]) or Nyx.Interact.Registry.Entities[hitEntity]
        if entEntry and entDist <= entEntry.distance then
            matchedCategory = "entity"
            for idx, opt in ipairs(entEntry.options) do
                local allowed = true
                if opt.canInteract then
                    allowed = opt.canInteract(hitEntity, entDist, entCoords)
                end
                if allowed then
                    table.insert(results, {
                        id = "ent_" .. idx,
                        icon = opt.icon or "fa-solid fa-hand",
                        label = opt.label or "Interact",
                        event = opt.event,
                        action = opt.action,
                        args = opt.args or {},
                        entity = hitEntity,
                        netId = netId
                    })
                end
            end
        end

        -- Check Model-specific options
        local modelEntry = Nyx.Interact.Registry.Models[modelHash]
        if modelEntry and entDist <= modelEntry.distance then
            matchedCategory = "model"
            for idx, opt in ipairs(modelEntry.options) do
                local allowed = true
                if opt.canInteract then
                    allowed = opt.canInteract(hitEntity, entDist, entCoords)
                end
                if allowed then
                    table.insert(results, {
                        id = "model_" .. idx,
                        icon = opt.icon or "fa-solid fa-hand",
                        label = opt.label or "Interact",
                        event = opt.event,
                        action = opt.action,
                        args = opt.args or {},
                        entity = hitEntity,
                        netId = netId
                    })
                end
            end
        end

        -- Check Vehicle Bones if vehicle hit
        if IsEntityAVehicle(hitEntity) then
            for boneName, boneEntry in pairs(Nyx.Interact.Registry.Bones) do
                local boneIndex = GetEntityBoneIndexByName(hitEntity, boneName)
                if boneIndex ~= -1 then
                    local boneCoords = GetWorldPositionOfEntityBone(hitEntity, boneIndex)
                    local boneDist = #(playerCoords - boneCoords)
                    if boneDist <= boneEntry.distance then
                        matchedCategory = "bone"
                        for idx, opt in ipairs(boneEntry.options) do
                            local allowed = true
                            if opt.canInteract then
                                allowed = opt.canInteract(hitEntity, boneDist, boneCoords, boneName)
                            end
                            if allowed then
                                table.insert(results, {
                                    id = "bone_" .. boneName .. "_" .. idx,
                                    icon = opt.icon or "fa-solid fa-car",
                                    label = opt.label or ("Vehicle: " .. boneName),
                                    event = opt.event,
                                    action = opt.action,
                                    args = opt.args or {},
                                    entity = hitEntity,
                                    netId = netId,
                                    bone = boneName
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- B. Evaluate Spatial Coordinate Spheres
    for id, coordEntry in pairs(Nyx.Interact.Registry.Coords) do
        local dist = #(playerCoords - coordEntry.coords)
        if dist <= coordEntry.distance then
            matchedCategory = "coords"
            for idx, opt in ipairs(coordEntry.options) do
                local allowed = true
                if opt.canInteract then
                    allowed = opt.canInteract(nil, dist, coordEntry.coords)
                end
                if allowed then
                    table.insert(results, {
                        id = "coord_" .. id .. "_" .. idx,
                        icon = opt.icon or "fa-solid fa-location-dot",
                        label = opt.label or "Interact",
                        event = opt.event,
                        action = opt.action,
                        args = opt.args or {},
                        coordId = id
                    })
                end
            end
        end
    end

    return results, matchedCategory
end
