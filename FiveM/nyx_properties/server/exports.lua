--[[
    Nyxframework: nyx_properties
    File: server/exports.lua
    Description: Public server exports for querying property state, keys, deeds,
                 tax assessments, delinquency status, and auction operations.
]]

exports('GetProperty', function(propertyId)
    return Nyx.Properties.Loaded and Nyx.Properties.Loaded[tonumber(propertyId)]
end)

exports('GetPropertyByCode', function(propertyCode)
    if not Nyx.Properties.Loaded then return nil end
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
    if not Nyx.Properties.Loaded then return result end
    for _, p in pairs(Nyx.Properties.Loaded) do
        if p.ownerCitizenId == citizenId then
            result[#result + 1] = p
        end
    end
    return result
end)

exports('GetPropertyTaxAssessment', function(propertyId)
    if Nyx.Properties.GetAssessmentForProperty then
        return Nyx.Properties.GetAssessmentForProperty(propertyId)
    end
    return nil
end)

exports('AssessPropertyTaxes', function(propertyId)
    if Nyx.Properties.ExecuteTaxCollection then
        return Nyx.Properties.ExecuteTaxCollection(propertyId)
    end
    return false, "UNAVAILABLE"
end)

exports('CountCitizenProperties', function(citizenId)
    if Nyx.Properties.CountCitizenProperties then
        return Nyx.Properties.CountCitizenProperties(citizenId)
    end
    return 1
end)

exports('ForfeitPropertyToAuction', function(propertyId)
    if Nyx.Properties.ForfeitPropertyToAuction then
        return Nyx.Properties.ForfeitPropertyToAuction(propertyId)
    end
    return false, "UNAVAILABLE"
end)

exports('PlaceAuctionBid', function(citizenId, auctionId, bidAmount)
    if Nyx.Properties.PlaceAuctionBid then
        return Nyx.Properties.PlaceAuctionBid(citizenId, auctionId, bidAmount)
    end
    return false, "UNAVAILABLE"
end)

exports('SettleAuction', function(auctionId)
    if Nyx.Properties.SettleAuction then
        return Nyx.Properties.SettleAuction(auctionId)
    end
    return false, "UNAVAILABLE"
end)
