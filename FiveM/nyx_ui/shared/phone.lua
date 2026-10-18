--[[
    Nyxframework: nyx_ui
    File: shared/phone.lua
    Description: Pure Lua 5.4 shared logic engine for Citizen OS Smartphone Framework.
                 Handles deterministic phone number formatting, P2P wire transfer fee math,
                 payload validation, alert taxonomy, and mobile freight contract filtering.
]]

Nyx = Nyx or {}
Nyx.Phone = Nyx.Phone or {}

-- 1. Standardized Currency Formatter
function Nyx.Phone.FormatCurrency(amount)
    local n = tonumber(amount) or 0.0
    local isNegative = (n < 0)
    n = math.abs(n)

    local formatted = string.format("%.2f", n)
    local integerPart, decimalPart = formatted:match("^(%d+)%.(%d+)$")

    local k
    while true do
        integerPart, k = string.gsub(integerPart, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end

    if isNegative then
        return string.format("-$%s.%s", integerPart, decimalPart)
    else
        return string.format("$%s.%s", integerPart, decimalPart)
    end
end

-- 2. Deterministic Phone Number Formatter & Derivation
function Nyx.Phone.FormatPhoneNumber(raw)
    local clean = string.gsub(tostring(raw or ""), "[^%d]", "")
    local len = #clean
    if len == 7 then
        return string.format("%s-%s", clean:sub(1, 3), clean:sub(4, 7))
    elseif len == 10 then
        return string.format("(%s) %s-%s", clean:sub(1, 3), clean:sub(4, 6), clean:sub(7, 10))
    elseif len >= 4 then
        return string.format("555-%s", clean:sub(-4))
    else
        return "555-0100"
    end
end

function Nyx.Phone.GeneratePhoneNumber(citizenId)
    if not citizenId or #tostring(citizenId) == 0 then
        return "555-0199"
    end
    local hash = 0
    local str = tostring(citizenId)
    for i = 1, #str do
        hash = (hash * 31 + string.byte(str, i)) % 9000
    end
    local num = 1000 + hash
    return string.format("555-%04d", num)
end

-- 3. Pure Mathematical Wire Transfer Tax & Fee Calculation
-- Closed-loop double-entry conservation invariant
function Nyx.Phone.CalculateTransferTax(amount, taxRate)
    local amt = tonumber(amount) or 0.0
    if amt <= 0.0 then
        return 0.0, 0.0
    end

    local rate = tonumber(taxRate)
    if rate == nil then rate = 0.02 end
    rate = math.max(0.0, math.min(0.25, rate)) -- Clamped between 0% and 25%

    local fee = math.floor((amt * rate) * 100 + 0.5) / 100
    local totalDebit = math.floor((amt + fee) * 100 + 0.5) / 100
    return fee, totalDebit
end

-- 4. Zero-Trust Wire Transfer Payload Validator
function Nyx.Phone.ValidateTransferPayload(payload, senderCitizenId)
    if type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local recipient = tostring(payload.recipientCitizenId or ""):gsub("^%s*(.-)%s*$", "%1")
    if #recipient < 2 or #recipient > 64 then
        return false, "INVALID_RECIPIENT"
    end

    if senderCitizenId and recipient == tostring(senderCitizenId) then
        return false, "CANNOT_TRANSFER_TO_SELF"
    end

    local amount = tonumber(payload.amount)
    if not amount or amount < 1.0 or amount > 10000000.0 then
        return false, "AMOUNT_OUT_OF_BOUNDS"
    end
    amount = math.floor(amount * 100) / 100

    local memo = tostring(payload.memo or "")
    if #memo > 128 then
        return false, "MEMO_TOO_LONG"
    end

    return true, {
        recipientCitizenId = recipient,
        amount = amount,
        memo = memo
    }
end

-- 5. Zero-Trust Citizen Emergency Alert Payload Validator
function Nyx.Phone.ValidateEmergencyAlertPayload(payload)
    if type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local validCategories = {
        police = true,
        medical = true,
        fire = true,
        traffic = true,
        general = true
    }

    local cat = tostring(payload.category or ""):lower():gsub("^%s*(.-)%s*$", "%1")
    if not validCategories[cat] then
        return false, "INVALID_CATEGORY"
    end

    local msg = tostring(payload.message or ""):gsub("^%s*(.-)%s*$", "%1")
    if #msg < 5 then
        return false, "MESSAGE_TOO_SHORT"
    end
    if #msg > 500 then
        return false, "MESSAGE_TOO_LONG"
    end

    local validPriorities = {
        low = true,
        medium = true,
        high = true,
        critical = true
    }

    local priority = tostring(payload.priority or "medium"):lower():gsub("^%s*(.-)%s*$", "%1")
    if not validPriorities[priority] then
        priority = "medium"
    end

    local loc = tostring(payload.locationLabel or "Los Santos"):gsub("^%s*(.-)%s*$", "%1")
    if #loc == 0 then loc = "Los Santos" end
    if #loc > 128 then loc = loc:sub(1, 128) end

    return true, {
        category = cat,
        message = msg,
        priority = priority,
        locationLabel = loc
    }
end

-- 6. Emergency Alert Visual Taxonomy Badge Formatter
function Nyx.Phone.FormatAlertBadge(priority, category)
    local p = tostring(priority or "medium"):lower()
    local cat = tostring(category or "general"):lower()

    local pMap = {
        critical = { badgeClass = "badge-danger", label = "KRITIKUS", icon = "fa-solid fa-triangle-exclamation" },
        high     = { badgeClass = "badge-danger", label = "SÜRGŐS", icon = "fa-solid fa-bell" },
        medium   = { badgeClass = "badge-warning", label = "FIGYELMEZTETÉS", icon = "fa-solid fa-circle-exclamation" },
        low      = { badgeClass = "badge-info", label = "TÁJÉKOZTATÁS", icon = "fa-solid fa-circle-info" }
    }

    local cMap = {
        police  = { label = "Rendőrség (911)", icon = "fa-solid fa-shield-halved", color = "#3B82F6" },
        medical = { label = "Mentőszolgálat", icon = "fa-solid fa-truck-medical", color = "#EF4444" },
        fire    = { label = "Katasztrófavédelem", icon = "fa-solid fa-fire-extinguisher", color = "#F97316" },
        traffic = { label = "Közlekedésrendészet", icon = "fa-solid fa-car-burst", color = "#F59E0B" },
        general = { label = "Polgári Riasztás", icon = "fa-solid fa-bullhorn", color = "#10B981" }
    }

    local badgeInfo = pMap[p] or pMap.medium
    local catInfo = cMap[cat] or cMap.general

    return {
        priorityBadgeClass = badgeInfo.badgeClass,
        priorityLabel = badgeInfo.label,
        priorityIcon = badgeInfo.icon,
        categoryLabel = catInfo.label,
        categoryIcon = catInfo.icon,
        categoryColor = catInfo.color
    }
end

-- 7. Mobile Freight Contract Card Formatter
function Nyx.Phone.FormatContractCard(contract)
    if type(contract) ~= "table" then return nil end

    local totalPayout = tonumber(contract.total_payout or contract.totalPayout or 0.0)
    local escrowBond = tonumber(contract.escrow_deposit or contract.escrowDeposit or 0.0)
    local qty = tonumber(contract.quantity or 0)
    local item = tostring(contract.item_id or contract.itemId or "Általános Áru")

    local status = tostring(contract.status or "available")
    local statusBadge = "badge-info"
    local statusLabel = "ELÉRHETŐ"

    if status == "in_transit" then
        statusBadge = "badge-warning"
        statusLabel = "FOLYAMATBAN"
    elseif status == "completed" then
        statusBadge = "badge-success"
        statusLabel = "TELJESÍTVE"
    elseif status == "abandoned" then
        statusBadge = "badge-danger"
        statusLabel = "MEGSZAKÍTVA"
    end

    return {
        id = contract.contract_id or contract.id,
        uuid = contract.contract_uuid or contract.uuid,
        itemId = item,
        quantity = qty,
        totalPayout = totalPayout,
        escrowDeposit = escrowBond,
        formattedPayout = Nyx.Phone.FormatCurrency(totalPayout),
        formattedEscrow = Nyx.Phone.FormatCurrency(escrowBond),
        status = status,
        statusBadge = statusBadge,
        statusLabel = statusLabel,
        expiresAt = contract.expires_at_unix or contract.expiresAt or 0
    }
end

-- 8. Freight Contract Filtering
function Nyx.Phone.FilterFreightContracts(contracts, filterType, search)
    if type(contracts) ~= "table" then return {} end
    local query = tostring(search or ""):lower():gsub("^%s*(.-)%s*$", "%1")
    local filter = tostring(filterType or "all"):lower()

    local filtered = {}
    for _, c in ipairs(contracts) do
        local matchesFilter = (filter == "all") or (c.status == filter)
        local matchesSearch = true

        if #query > 0 then
            local item = tostring(c.item_id or c.itemId or ""):lower()
            local cid = tostring(c.contract_id or c.id or ""):lower()
            matchesSearch = (item:find(query, 1, true) ~= nil) or (cid:find(query, 1, true) ~= nil)
        end

        if matchesFilter and matchesSearch then
            table.insert(filtered, c)
        end
    end
    return filtered
end
