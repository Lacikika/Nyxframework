--[[
    Nyxframework: nyx_press
    File: server/exports.lua
    Description: Authoritative server exports for inter-resource press and whistleblower integration.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

exports('PublishArticle', function(src, payload)
    return Nyx.Press.PublishArticle(src, payload)
end)

exports('PrintCirculationCopies', function(src, pubId, copies, targetStandId)
    return Nyx.Press.PrintCirculationCopies(src, pubId, copies, targetStandId)
end)

exports('DepositWhistleblowerLeak', function(src, payload)
    return Nyx.Press.DepositWhistleblowerLeak(src, payload)
end)

exports('GetAvailableLeaks', function(src)
    return Nyx.Press.GetAvailableLeaks(src)
end)

exports('ClaimWhistleblowerLeak', function(src, leakId)
    return Nyx.Press.ClaimWhistleblowerLeak(src, leakId)
end)

exports('PurchaseNewspaper', function(src, standId)
    return Nyx.Press.PurchaseNewspaper(src, standId)
end)

exports('RetractPublication', function(src, pubId, reason)
    return Nyx.Press.RetractPublication(src, pubId, reason)
end)

exports('CheckPlayerAccreditation', function(citizenId, outletId)
    return Nyx.Press.CheckPlayerAccreditation(citizenId, outletId)
end)

exports('GetPublication', function(pubId)
    if not pubId then return nil end
    return MySQL.single.await("SELECT * FROM `nyx_press_publications` WHERE `publication_id` = ?", { pubId })
end)

exports('CalculatePrintingCost', function(copies, contentLen, baseCost, pageFactor, overhead)
    return Nyx.Press.CalculatePrintingCost(copies, contentLen, baseCost, pageFactor, overhead)
end)

exports('CalculateSaleRevenueSplit', function(coverPrice, publisherSplitRatio)
    return Nyx.Press.CalculateSaleRevenueSplit(coverPrice, publisherSplitRatio)
end)

exports('SubscribeCitizen', function(src, planId, deliveryPropertyId)
    return Nyx.Press.Subscribe(src, planId, deliveryPropertyId)
end)

exports('CancelSubscription', function(src, subscriptionId)
    return Nyx.Press.CancelSubscription(src, subscriptionId)
end)

exports('GetCitizenSubscriptions', function(citizenId)
    return Nyx.Press.GetCitizenSubscriptions(citizenId)
end)

exports('AwardWhistleblowerBounty', function(src, leakId, amount)
    return Nyx.Press.AwardWhistleblowerBounty(src, leakId, amount)
end)

exports('ClaimWhistleblowerBounty', function(src, bountyId, salt, nonce, dropboxId)
    return Nyx.Press.ClaimWhistleblowerBounty(src, bountyId, salt, nonce, dropboxId)
end)

exports('DeliverPublicationToSubscribers', function(pubId)
    return Nyx.Press.DeliverPublicationToSubscribers(pubId)
end)

exports('CalculateSubscriptionSplit', function(price, pubRatio, poolRatio, taxRatio)
    return Nyx.Press.Subscriptions.CalculateSubscriptionSplit(price, pubRatio, poolRatio, taxRatio)
end)

