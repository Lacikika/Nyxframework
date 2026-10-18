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
