--[[
    Nyxframework: nyx_interact
    File: client/exports.lua
    Description: Public client exports for adding and removing raycast targets.
]]

exports('AddTargetModel', function(models, data)
    Nyx.Interact.AddTargetModel(models, data)
end)

exports('RemoveTargetModel', function(models)
    Nyx.Interact.RemoveTargetModel(models)
end)

exports('AddTargetEntity', function(entities, data)
    Nyx.Interact.AddTargetEntity(entities, data)
end)

exports('RemoveTargetEntity', function(entities)
    Nyx.Interact.RemoveTargetEntity(entities)
end)

exports('AddTargetBone', function(bones, data)
    Nyx.Interact.AddTargetBone(bones, data)
end)

exports('RemoveTargetBone', function(bones)
    Nyx.Interact.RemoveTargetBone(bones)
end)

exports('AddTargetCoords', function(id, coords, radius, data)
    Nyx.Interact.AddTargetCoords(id, coords, radius, data)
end)

exports('RemoveTargetCoords', function(id)
    Nyx.Interact.RemoveTargetCoords(id)
end)

exports('GetCurrentTarget', function()
    return Nyx.Interact.CurrentTarget
end)

exports('IsActive', function()
    return Nyx.Interact.IsActive
end)

exports('GetNearbyTargetCoords', function(radius)
    radius = tonumber(radius) or 10.0
    local playerCoords = GetEntityCoords(PlayerPedId())
    local results = {}

    local candidateCoordIds = {}
    if Nyx.Math and Nyx.Math.GetCellsInRadius then
        local cellKeys = Nyx.Math.GetCellsInRadius(playerCoords.x, playerCoords.y, radius, 64.0, 0)
        for _, nKey in ipairs(cellKeys) do
            local cell = Nyx.Interact.Registry.CoordCells[nKey]
            if cell then
                for id, _ in pairs(cell) do candidateCoordIds[id] = true end
            end
        end
    else
        for id, _ in pairs(Nyx.Interact.Registry.Coords) do candidateCoordIds[id] = true end
    end

    for id, _ in pairs(candidateCoordIds) do
        local entry = Nyx.Interact.Registry.Coords[id]
        if entry and entry.coords then
            local dist = #(playerCoords - entry.coords)
            if dist <= radius then
                results[#results + 1] = {
                    id = id,
                    coords = entry.coords,
                    distance = dist,
                    radius = entry.radius,
                    options = entry.options
                }
            end
        end
    end

    table.sort(results, function(a, b) return a.distance < b.distance end)
    return results
end)

