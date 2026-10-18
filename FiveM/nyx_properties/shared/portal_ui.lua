--[[
    Nyxframework: nyx_properties
    File: shared/portal_ui.lua
    Description: Pure Lua 5.4 computation and validation engine for the Property Blind-Auction
                 & Stewardship Web Portal. Provides sealed-bid validation, blind data masking,
                 stewardship proxy payload guards, catalog filtering, and status badge taxonomy.
]]

Nyx = Nyx or {}
Nyx.PropertyPortalUI = {}

local PropertyPortalUI = Nyx.PropertyPortalUI

-- 1. Format Currency Helper ($X,XXX.XX)
function PropertyPortalUI.FormatCurrency(amount)
    amount = tonumber(amount) or 0.00
    local formatted = string.format("%.2f", amount)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return "$" .. formatted
end

-- 2. Validate Blind Auction Bid Payload
function PropertyPortalUI.ValidateBidPayload(payload, auctionData)
    if not payload or type(payload) ~= "table" then
        return false, nil, "INVALID_PAYLOAD"
    end

    local auctionId = tonumber(payload.auctionId)
    if not auctionId or auctionId <= 0 or math.floor(auctionId) ~= auctionId then
        return false, nil, "INVALID_AUCTION_ID"
    end

    local bidAmount = tonumber(payload.bidAmount)
    if not bidAmount or bidAmount <= 0.00 then
        return false, nil, "INVALID_BID_AMOUNT"
    end

    -- Enforce 2 decimal places maximum
    local roundedBid = math.floor((bidAmount * 100) + 0.5) / 100
    if math.abs(roundedBid - bidAmount) > 0.0001 then
        return false, nil, "FRACTIONAL_CENTS_NOT_ALLOWED"
    end

    if auctionData then
        local minBid = tonumber(auctionData.minimum_bid or auctionData.minimumBid) or 1000.00
        if roundedBid < minBid then
            return false, nil, "BID_BELOW_MINIMUM"
        end

        local highestBid = tonumber(auctionData.highest_bid or auctionData.highestBid) or 0.00
        if roundedBid <= highestBid then
            return false, nil, "BID_NOT_HIGHER_THAN_CURRENT"
        end
    end

    local sanitized = {
        auctionId = auctionId,
        bidAmount = roundedBid,
        note = payload.note and string.sub(tostring(payload.note), 1, 128) or nil
    }

    return true, sanitized, nil
end

-- 3. Mask Blind Auction Data for Public View
function PropertyPortalUI.MaskBlindAuction(auction, viewerCitizenId, mySealedBidsMap)
    if not auction or type(auction) ~= "table" then return nil end

    local auctionId = tonumber(auction.auction_id or auction.auctionId)
    local minBid = tonumber(auction.minimum_bid or auction.minimumBid) or 0.00
    local isBlind = (auction.is_blind ~= 0 and auction.is_blind ~= false)
    local highestBidder = auction.highest_bidder_citizen_id or auction.highestBidderCitizenId
    local isWinnerOrLeading = (viewerCitizenId and highestBidder == viewerCitizenId)

    local myBidAmount = 0.00
    if mySealedBidsMap and auctionId and mySealedBidsMap[auctionId] then
        myBidAmount = tonumber(mySealedBidsMap[auctionId]) or 0.00
    elseif viewerCitizenId and highestBidder == viewerCitizenId then
        myBidAmount = tonumber(auction.highest_bid or auction.highestBid) or 0.00
    end

    local masked = {
        auctionId = auctionId,
        propertyId = tonumber(auction.property_id or auction.propertyId),
        propertyLabel = auction.property_label or auction.label or string.format("Ingatlan #%d", auction.property_id or 0),
        propertyCode = auction.property_code or auction.code or "unknown",
        propertyType = auction.property_type or auction.type or "residential",
        zoneId = auction.zone_id or auction.zoneId or "zone_ls_metro",
        landAreaSqm = tonumber(auction.land_area_sqm or auction.landAreaSqm) or 150.00,
        valuationPrice = tonumber(auction.property_price or auction.price) or 0.00,
        minimumBid = minBid,
        totalBidsPlaced = tonumber(auction.total_bids_placed or auction.totalBidsPlaced) or 0,
        isBlind = isBlind,
        startedAt = auction.started_at or auction.startedAt,
        endsAt = auction.ends_at or auction.endsAt,
        status = auction.auction_status or auction.status or "active",
        hasPlacedBid = (myBidAmount > 0.00),
        mySealedBid = myBidAmount,
        isLeading = isWinnerOrLeading
    }

    -- If auction is concluded or viewer is admin/owner, highest bid may be exposed
    if not isBlind or masked.status == "completed" or isWinnerOrLeading then
        masked.highestBid = tonumber(auction.highest_bid or auction.highestBid) or 0.00
    else
        masked.highestBid = nil -- Masked to preserve blind auction integrity
    end

    return masked
end

-- 4. Validate Delegation Payload (Proxy Steward Appointment)
function PropertyPortalUI.ValidateDelegationPayload(payload, ownerCitizenId)
    if not payload or type(payload) ~= "table" then
        return false, nil, "INVALID_PAYLOAD"
    end

    local delegateCitizenId = payload.delegateCitizenId
    if not delegateCitizenId or type(delegateCitizenId) ~= "string" then
        return false, nil, "INVALID_DELEGATE_ID"
    end

    delegateCitizenId = string.gsub(delegateCitizenId, "%s+", "")
    if #delegateCitizenId < 3 or #delegateCitizenId > 16 then
        return false, nil, "INVALID_DELEGATE_LENGTH"
    end

    if ownerCitizenId and delegateCitizenId == ownerCitizenId then
        return false, nil, "CANNOT_DELEGATE_TO_SELF"
    end

    local scope = payload.scope or "all"
    if scope ~= "all" and scope ~= "properties" and scope ~= "factions" then
        return false, nil, "INVALID_DELEGATION_SCOPE"
    end

    local notes = payload.notes or "Stewardship proxy authorization"
    if type(notes) ~= "string" then notes = "Stewardship proxy authorization" end
    notes = string.sub(notes, 1, 255)

    return true, {
        delegateCitizenId = delegateCitizenId,
        scope = scope,
        notes = notes
    }, nil
end

-- 5. Validate Steward Assignment Payload
function PropertyPortalUI.ValidateStewardAssignmentPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, nil, "INVALID_PAYLOAD"
    end

    local propertyId = tonumber(payload.propertyId)
    if not propertyId or propertyId <= 0 or math.floor(propertyId) ~= propertyId then
        return false, nil, "INVALID_PROPERTY_ID"
    end

    local delegateCitizenId = payload.delegateCitizenId
    if delegateCitizenId ~= nil and delegateCitizenId ~= "" then
        if type(delegateCitizenId) ~= "string" then
            return false, nil, "INVALID_DELEGATE_ID"
        end
        delegateCitizenId = string.gsub(delegateCitizenId, "%s+", "")
        if #delegateCitizenId < 3 or #delegateCitizenId > 16 then
            return false, nil, "INVALID_DELEGATE_LENGTH"
        end
    else
        delegateCitizenId = nil -- Unassignment request
    end

    return true, {
        propertyId = propertyId,
        delegateCitizenId = delegateCitizenId
    }, nil
end

-- 6. Filter Properties Catalog
function PropertyPortalUI.FilterPropertiesCatalog(properties, filterQuery, typeFilter, statusFilter)
    if not properties or type(properties) ~= "table" then return {} end

    local query = filterQuery and string.lower(string.gsub(filterQuery, "^%s*(.-)%s*$", "%1")) or ""
    local tFilter = typeFilter and string.lower(typeFilter) or "all"
    local sFilter = statusFilter and string.lower(statusFilter) or "all"

    local filtered = {}
    for _, p in ipairs(properties) do
        local matchesQuery = true
        if query ~= "" then
            local label = string.lower(p.label or p.propertyLabel or "")
            local code = string.lower(p.code or p.propertyCode or "")
            local zone = string.lower(p.zoneId or p.zone_id or "")
            matchesQuery = (string.find(label, query, 1, true) ~= nil) or
                           (string.find(code, query, 1, true) ~= nil) or
                           (string.find(zone, query, 1, true) ~= nil)
        end

        local pType = string.lower(p.type or p.propertyType or "residential")
        local matchesType = (tFilter == "all" or pType == tFilter)

        local matchesStatus = true
        if sFilter == "owned" then
            matchesStatus = (p.isOwnedByMe == true)
        elseif sFilter == "delinquent" then
            matchesStatus = ((tonumber(p.delinquencyTier or 0) > 0) or (tonumber(p.delinquentAmount or 0) > 0))
        elseif sFilter == "pristine" then
            matchesStatus = (tonumber(p.maintenanceCondition or 100) >= 95.0 and tonumber(p.delinquencyTier or 0) == 0)
        elseif sFilter == "auctioned" then
            matchesStatus = (p.reclaimedForAuction == true or p.reclaimed_for_auction == 1)
        elseif sFilter == "managed" then
            matchesStatus = (p.isManagedByMe == true or p.isSteward == true)
        end

        if matchesQuery and matchesType and matchesStatus then
            table.insert(filtered, p)
        end
    end

    return filtered
end

-- 7. Format Delinquency Status Badge
function PropertyPortalUI.FormatDelinquencyBadge(tier, arrearsAmount)
    tier = tonumber(tier) or 0
    arrearsAmount = tonumber(arrearsAmount) or 0.00

    if tier <= 0 and arrearsAmount <= 0.00 then
        return {
            tier = 0,
            badgeClass = "badge-success",
            statusLabel = "RENDEZETT",
            description = "Nincs hátralék, az ingatlan jogi státusza tiszta."
        }
    elseif tier == 1 then
        return {
            tier = 1,
            badgeClass = "badge-warning",
            statusLabel = "1. FOKÚ FIGYELMEZTETÉS",
            description = "Késedelmes adófizetés. Kérjük rendezze tartozását."
        }
    elseif tier == 2 then
        return {
            tier = 2,
            badgeClass = "badge-warning",
            statusLabel = "2. FOKÚ KÉSEDELMI PÓTDÍJ",
            description = "+15% önkormányzati késedelmi pótdíj felszámolva."
        }
    elseif tier == 3 then
        return {
            tier = 3,
            badgeClass = "badge-danger",
            statusLabel = "3. FOKÚ HATÓSÁGI ZÁROLÁS",
            description = "Az ajtózárak zárolva! Kilakoltatási figyelmeztetés érvényben."
        }
    else
        return {
            tier = 4,
            badgeClass = "badge-danger",
            statusLabel = "4. FOKÚ ÁRVERÉSI KOBZÁS",
            description = "Tulajdonjog megvonva! Az ingatlan nyilvános vakárverésre került."
        }
    end
end

-- 8. Calculate Remaining Time on Auction Countdown
function PropertyPortalUI.CalculateRemainingTime(endsAtUnix, currentUnix)
    currentUnix = currentUnix or os.time()
    endsAtUnix = tonumber(endsAtUnix) or currentUnix

    local diff = endsAtUnix - currentUnix
    if diff <= 0 then
        return {
            secondsRemaining = 0,
            isExpired = true,
            formattedTime = "LEJÁRT"
        }
    end

    local hours = math.floor(diff / 3600)
    local mins = math.floor((diff % 3600) / 60)
    local secs = diff % 60

    local formatted
    if hours >= 24 then
        local days = math.floor(hours / 24)
        local remHours = hours % 24
        formatted = string.format("%dn %dó", days, remHours)
    else
        formatted = string.format("%02dó %02dp %02dmp", hours, mins, secs)
    end

    return {
        secondsRemaining = diff,
        isExpired = false,
        formattedTime = formatted
    }
end

-- Export module globally
Nyx.PropertyPortalUI = PropertyPortalUI
return PropertyPortalUI
