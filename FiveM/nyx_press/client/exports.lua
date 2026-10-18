--[[
    Nyxframework: nyx_press
    File: client/exports.lua
    Description: Client exports for external resource interaction with media and newsstands.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

exports('OpenPublicationReader', function(pubData)
    return Nyx.Press.OpenPublicationReader(pubData)
end)

exports('PurchaseAtStand', function(standId)
    return Nyx.Press.PurchaseAtStand(standId)
end)

exports('GetLoadedNewsstands', function()
    return Nyx.Press.NewsstandsCache or {}
end)
