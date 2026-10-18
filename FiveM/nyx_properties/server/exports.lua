--[[
    Nyxframework: nyx_properties
    File: server/exports.lua
    Description: Public server exports for querying property state, keys, and deeds.
]]

exports('GetProperty', function(propertyId)
    return Nyx.Properties.Loaded[tonumber(propertyId)]
end)

exports('GetPropertyByCode', function(propertyCode)
    for _, p in pairs(Nyx.Properties.Loaded) do
        if p.code == propertyCode then
            return p
        end
    end
    return nil
end)

exports('HasKey', function(propertyId, citizenId, minTier)
    return Nyx.Properties.HasKey(propertyId, citizenId, minTier)
end)

exports('GetPlayerProperties', function(citizenId)
    local result = {}
    for _, p in pairs(Nyx.Properties.Loaded) do
        if p.ownerCitizenId == citizenId then
            result[#result + 1] = p
        end
    end
    return result
end)
