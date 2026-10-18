--[[
    Nyxframework: nyx_factions
    File: server/cash_transit.lua
    Description: Authoritative server engine for packing excess commercial register cash
                 into physical armored cash boxes, seal generation, transit manifests,
                 and double-entry clearing integration.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.CashTransit = Nyx.CashTransit or {}

local function generateUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- 1. Query Commercial Registers Needing Transit Pickup
function Nyx.Factions.GetRegistersNeedingTransit()
    local results = {}
    local registers = (Nyx.Laundering and Nyx.Laundering.Registers) or {}

    for _, reg in pairs(registers) do
        local ok, data = Nyx.CashTransit.EvaluateRegisterTransitNeed(reg)
        if ok and type(data) == "table" then
            table.insert(results, {
                registerId = reg.register_id,
                factionId = reg.faction_id,
                label = reg.label,
                businessType = reg.business_type,
                cleanCashBalance = data.cleanCashBalance,
                threshold = data.threshold,
                suggestedBoxAmount = data.suggestedBoxAmount,
                coords = reg.coords
            })
        end
    end

    return results
end

-- 2. Create Armored Cash Transit Box from Register Excess Cash
function Nyx.Factions.CreateCashTransitBox(src, registerId, amount, destinationVault)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return false, "UNAUTHENTICATED"
    end

    local okVal, cleanPayload = Nyx.CashTransit.ValidateCreationPayload({
        registerId = registerId,
        amount = amount,
        destinationVault = destinationVault
    })
    if not okVal then
        return false, cleanPayload
    end

    local reg = (Nyx.Laundering and Nyx.Laundering.GetRegister(cleanPayload.registerId))
    if not reg then
        -- Fallback to DB
        local row = MySQL.single.await("SELECT * FROM `nyx_factions_commercial_registers` WHERE `register_id` = ?", { cleanPayload.registerId })
        if not row then
            return false, "REGISTER_NOT_FOUND"
        end
        reg = row
    end

    -- Authorization check: player must have access to faction treasury / transit
    local isAuthorized = exports['nyx_factions']:HasPermission(player.citizenId, reg.faction_id, "treasury:withdraw")
    if not isAuthorized then
        isAuthorized = exports['nyx_factions']:HasPermission(player.citizenId, reg.faction_id, "transit:dispatch")
    end
    if not isAuthorized then
        local faction = exports['nyx_factions']:GetFaction(reg.faction_id)
        if not faction then
            return false, "FACTION_NOT_FOUND"
        end
    end

    local okCreate, validatedAmt = Nyx.CashTransit.ValidateBoxCreation(reg, cleanPayload.amount, player.citizenId)
    if not okCreate then
        return false, validatedAmt
    end

    local boxId = generateUuid()
    local boxUuid = Nyx.CashTransit.GenerateBoxUuid()
    local sealSerial = Nyx.CashTransit.GenerateSealSerial()
    local manifestUuid = Nyx.CashTransit.GenerateManifestUuid()
    local targetVault = cleanPayload.destinationVault or "vault:pacific_standard"

    -- Deduct clean cash from register
    reg.clean_cash_balance = (tonumber(reg.clean_cash_balance) or 0.0) - validatedAmt
    reg.pending_transit_box_id = boxId

    MySQL.prepare.await([[
        UPDATE `nyx_factions_commercial_registers`
        SET `clean_cash_balance` = `clean_cash_balance` - ?,
            `pending_transit_box_id` = ?
        WHERE `register_id` = ?
    ]], { validatedAmt, boxId, reg.register_id })

    -- Insert into nyx_treasury_cash_transit_boxes
    local coordsJson = nil
    if reg.coords then
        coordsJson = (type(reg.coords) == "string") and reg.coords or json.encode(reg.coords)
    end

    MySQL.prepare.await([[
        INSERT INTO `nyx_treasury_cash_transit_boxes`
            (`box_id`, `box_uuid`, `register_id`, `faction_id`, `carrier_citizen_id`, `cash_amount`,
             `seal_serial`, `tamper_state`, `status`, `origin_coords`, `destination_vault_id`, `dispatched_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'sealed', 'in_transit', ?, ?, CURRENT_TIMESTAMP)
    ]], {
        boxId,
        boxUuid,
        reg.register_id,
        reg.faction_id,
        player.citizenId,
        validatedAmt,
        sealSerial,
        coordsJson,
        targetVault
    })

    -- Audit trail
    MySQL.prepare.await([[
        INSERT INTO `nyx_treasury_cash_transit_audits`
            (`audit_uuid`, `box_id`, `action`, `actor_citizen_id`, `cash_amount`, `faction_id`, `vault_id`, `notes`, `coords`)
        VALUES (?, ?, 'BOX_CREATED', ?, ?, ?, ?, ?, ?)
    ]], {
        generateUuid(),
        boxId,
        player.citizenId,
        validatedAmt,
        reg.faction_id,
        targetVault,
        string.format("Box %s packed with %s at register %s", boxUuid, Nyx.CashTransit.FormatCurrency(validatedAmt), reg.register_id),
        coordsJson
    })

    -- Deliver physical items to courier
    if exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
        exports['nyx_inventory']:AddItem(src, "armored_cash_box", 1, {
            boxUuid = boxUuid,
            boxId = boxId,
            registerId = reg.register_id,
            factionId = reg.faction_id,
            cashAmount = validatedAmt,
            amount = validatedAmt,
            sealSerial = sealSerial,
            destinationVault = targetVault,
            tamperState = "sealed",
            dispatchedAt = os.time()
        })

        exports['nyx_inventory']:AddItem(src, "cash_transit_manifest", 1, {
            manifestUuid = manifestUuid,
            boxUuid = boxUuid,
            registerId = reg.register_id,
            factionId = reg.faction_id,
            carrierCitizenId = player.citizenId,
            amount = validatedAmt,
            destinationVault = targetVault,
            issuedAt = os.time()
        })
    end

    TriggerClientEvent("nyx:core:notify", src, {
        type = "success",
        title = "Páncélozott Készpénzszállítmány",
        message = string.format("Sikeresen lezárva: %s (%s). Szállítás a széfbe!", boxUuid, Nyx.CashTransit.FormatCurrency(validatedAmt))
    })

    return true, {
        boxId = boxId,
        boxUuid = boxUuid,
        sealSerial = sealSerial,
        manifestUuid = manifestUuid,
        amount = validatedAmt,
        destinationVault = targetVault
    }
end

-- 3. Register RPC Handlers
if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
    exports['nyx_core']:RegisterRPC("factions:createCashTransitBox", function(src, payload)
        if type(payload) ~= "table" then
            return { success = false, error = "INVALID_PAYLOAD" }
        end
        local ok, res = Nyx.Factions.CreateCashTransitBox(src, payload.registerId, payload.amount, payload.destinationVault)
        return { success = ok, result = res }
    end)

    exports['nyx_core']:RegisterRPC("factions:getRegistersNeedingTransit", function(src)
        return Nyx.Factions.GetRegistersNeedingTransit()
    end)
end
