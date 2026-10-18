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

exports('RegisterStewardshipDelegate', function(ownerCitizenId, delegateCitizenId, scope, notes)
    if Nyx.Properties.RegisterStewardshipDelegate then
        return Nyx.Properties.RegisterStewardshipDelegate(ownerCitizenId, delegateCitizenId, scope, notes)
    end
    return false, "UNAVAILABLE"
end)

exports('RevokeStewardshipDelegate', function(ownerCitizenId, delegateCitizenId, scope)
    if Nyx.Properties.RevokeStewardshipDelegate then
        return Nyx.Properties.RevokeStewardshipDelegate(ownerCitizenId, delegateCitizenId, scope)
    end
    return false, "UNAVAILABLE"
end)

exports('AssignPropertySteward', function(propertyId, ownerCitizenId, delegateCitizenId)
    if Nyx.Properties.AssignPropertySteward then
        return Nyx.Properties.AssignPropertySteward(propertyId, ownerCitizenId, delegateCitizenId)
    end
    return false, "UNAVAILABLE"
end)

exports('GetCitizenStewardshipOverview', function(citizenId)
    if Nyx.Properties.GetCitizenStewardshipOverview then
        return Nyx.Properties.GetCitizenStewardshipOverview(citizenId)
    end
    return nil
end)

exports('SweepPropertyInactivity', function()
    if Nyx.Properties.SweepPropertyInactivity then
        return Nyx.Properties.SweepPropertyInactivity()
    end
    return nil
end)

exports('GetRealEstatePortalOverview', function(citizenId)
    if Nyx.Properties.GetRealEstatePortalOverview then
        return Nyx.Properties.GetRealEstatePortalOverview(citizenId)
    end
    return nil
end)

exports('GetAuctionBidsHistory', function(auctionId, citizenId)
    if Nyx.Properties.GetAuctionBidsHistory then
        return Nyx.Properties.GetAuctionBidsHistory(auctionId, citizenId)
    end
    return {}
end)

exports('IsPropertyUtilitySuspended', function(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[tonumber(propertyId)]
    return prop and prop.isUtilitySuspended or false
end)

