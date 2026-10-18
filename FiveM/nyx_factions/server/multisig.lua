--[[
    Nyxframework: nyx_factions
    File: server/multisig.lua
    Description: Multi-signature corporate treasury queue, signatory verification,
                 threshold evaluation, and ledger disbursement.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

-- Utility: Generate UUIDv4
local function generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- 1. Initiate a corporate withdrawal (Direct or Multi-Sig queued)
function Nyx.Factions.InitiateWithdrawal(src, factionId, targetAccount, amount, reason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local transferAmount = tonumber(amount) or 0.00
    if transferAmount <= 0.00 then
        return false, "INVALID_AMOUNT"
    end

    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return false, "FACTION_NOT_FOUND" end

    local currentBalance = exports['nyx_treasury']:GetAccountBalance(faction.treasury_account_id) or 0.00
    if currentBalance < transferAmount then
        return false, "INSUFFICIENT_FACTION_LIQUIDITY"
    end

    local threshold = tonumber(faction.multisig_threshold_amount) or 50000.00

    -- Scenario A: Standard Low-Tier Withdrawal (Below Threshold)
    if transferAmount <= threshold then
        if not Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:withdraw_low") then
            return false, "INSUFFICIENT_PERMISSIONS_WITHDRAW_LOW"
        end

        local success, txId = exports['nyx_treasury']:ExecuteTransfer(
            faction.treasury_account_id,
            targetAccount,
            transferAmount,
            "faction_withdrawal",
            player.citizenId,
            reason or "Direct Authorized Organization Withdrawal",
            0.0
        )

        if success then
            return true, "DISBURSED_DIRECT", { txId = txId, amount = transferAmount }
        else
            return false, "TREASURY_TRANSFER_FAILED"
        end
    end

    -- Scenario B: High-Tier Withdrawal (Exceeds Threshold -> Multi-Sig Required)
    if not Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:withdraw_high") then
        return false, "INSUFFICIENT_PERMISSIONS_WITHDRAW_HIGH"
    end

    local requestId = generateUUID()
    local requiredSigs = tonumber(faction.multisig_required_signatures) or 2
    local currentSigs = {}

    -- Auto-sign if the initiator has signatory rights
    if Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:sign_tx") then
        table.insert(currentSigs, player.citizenId)
    end

    local expireHours = Config.MultiSig.RequestExpirationHours or 48
    local expireTime = os.date("%Y-%m-%d %H:%M:%S", os.time() + (expireHours * 3600))

    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_queue`
            (`request_id`, `faction_id`, `initiated_by`, `target_account`, `amount`, `reason`,
             `required_signatures`, `current_signatures`, `status`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)
    ]], {
        requestId,
        factionId,
        player.citizenId,
        targetAccount,
        transferAmount,
        reason or "High-Tier Multi-Sig Corporate Disbursement",
        requiredSigs,
        json.encode(currentSigs),
        expireTime
    })

    if not insertOk then
        return false, "DATABASE_ERROR"
    end

    -- Check if initial signatures already fulfill required threshold
    if #currentSigs >= requiredSigs then
        local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
            faction.treasury_account_id,
            targetAccount,
            transferAmount,
            "factions_multisig",
            "MULTISIG:" .. requestId,
            reason or "Multi-Sig Instant Quorum Transfer",
            0.0
        )

        if ok then
            MySQL.prepare.await([[
                UPDATE `nyx_factions_multisig_queue`
                SET `status` = 'approved'
                WHERE `request_id` = ?
            ]], { requestId })

            return true, "DISBURSED", { requestId = requestId, amount = transferAmount, txId = txId }
        end
    end

    -- Broadcast notification to online certified signatories
    local members = Nyx.Factions.GetFactionMembers(factionId)
    for _, member in ipairs(members) do
        local targetPlayer = Nyx.GetPlayerByCitizenId(member.citizenId)
        if targetPlayer and Nyx.Factions.HasPermission(member.citizenId, factionId, "treasury:sign_tx") then
            TriggerClientEvent("nyx:ui:notify", targetPlayer.source, {
                type = "warning",
                title = "MULTI-SIG APPROVAL REQUIRED",
                message = string.format("Withdrawal request for $%.2f pending signatory approval on %s.",
                    transferAmount, faction.legal_name)
            })
        end
    end

    return true, "QUEUED_MULTISIG", {
        requestId = requestId,
        amount = transferAmount,
        currentSignatures = #currentSigs,
        requiredSignatures = requiredSigs,
        expiresAt = expireTime
    }
end

-- 2. Approve a pending multi-sig request
function Nyx.Factions.ApproveMultiSigRequest(src, requestId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local req = MySQL.single.await([[
        SELECT r.*, f.treasury_account_id, f.legal_name
        FROM `nyx_factions_multisig_queue` r
        JOIN `nyx_factions_registry` f ON r.faction_id = f.faction_id
        WHERE r.request_id = ? AND r.status = 'pending'
    ]], { requestId })

    if not req then
        return false, "REQUEST_NOT_FOUND_OR_RESOLVED"
    end

    -- Verify expiration
    local nowStr = os.date("%Y-%m-%d %H:%M:%S")
    if req.expires_at <= nowStr then
        MySQL.prepare.await([[
            UPDATE `nyx_factions_multisig_queue` SET `status` = 'expired' WHERE `request_id` = ?
        ]], { requestId })
        return false, "REQUEST_EXPIRED"
    end

    -- Verify caller holds signatory privileges
    if not Nyx.Factions.HasPermission(player.citizenId, req.faction_id, "treasury:sign_tx") then
        return false, "INSUFFICIENT_SIGNATORY_PRIVILEGES"
    end

    local signatures = {}
    if type(req.current_signatures) == "string" then
        local ok, parsed = pcall(json.decode, req.current_signatures)
        if ok and type(parsed) == "table" then signatures = parsed end
    elseif type(req.current_signatures) == "table" then
        signatures = req.current_signatures
    end

    -- Prevent duplicate signatures
    for _, signerId in ipairs(signatures) do
        if signerId == player.citizenId then
            return false, "ALREADY_SIGNED"
        end
    end

    table.insert(signatures, player.citizenId)

    -- Threshold satisfied -> Execute authoritative transfer
    if #signatures >= tonumber(req.required_signatures) then
        local success, txId = exports['nyx_treasury']:ExecuteTransfer(
            req.treasury_account_id,
            req.target_account,
            tonumber(req.amount),
            "factions_multisig",
            "MULTISIG:" .. requestId,
            req.reason,
            0.0
        )

        if success then
            MySQL.prepare.await([[
                UPDATE `nyx_factions_multisig_queue`
                SET `current_signatures` = ?, `status` = 'approved'
                WHERE `request_id` = ?
            ]], { json.encode(signatures), requestId })

            -- Broadcast confirmation
            TriggerClientEvent("nyx:factions:client:multisigDisbursed", -1, {
                requestId = requestId,
                factionId = req.faction_id,
                amount = req.amount,
                targetAccount = req.target_account
            })

            return true, "DISBURSED", { txId = txId, amount = req.amount }
        else
            return false, "TREASURY_TRANSFER_FAILED"
        end
    else
        -- Append signature and wait for remaining quorum
        MySQL.prepare.await([[
            UPDATE `nyx_factions_multisig_queue`
            SET `current_signatures` = ?
            WHERE `request_id` = ?
        ]], { json.encode(signatures), requestId })

        return true, "SIGNATURE_REGISTERED", {
            currentSignatures = #signatures,
            requiredSignatures = req.required_signatures
        }
    end
end

-- 3. Reject a pending multi-sig request
function Nyx.Factions.RejectMultiSigRequest(src, requestId, rejectionReason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local req = MySQL.single.await([[
        SELECT `faction_id`, `status` FROM `nyx_factions_multisig_queue`
        WHERE `request_id` = ? AND `status` = 'pending'
    ]], { requestId })

    if not req then return false, "REQUEST_NOT_FOUND" end

    if not Nyx.Factions.HasPermission(player.citizenId, req.faction_id, "treasury:sign_tx") then
        return false, "INSUFFICIENT_SIGNATORY_PRIVILEGES"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_multisig_queue`
        SET `status` = 'rejected'
        WHERE `request_id` = ?
    ]], { requestId })

    return true, "REJECTED"
end

-- 4. Periodic background task: sweep timed-out requests
function Nyx.Factions.SweepExpiredMultiSig()
    local affected = MySQL.update.await([[
        UPDATE `nyx_factions_multisig_queue`
        SET `status` = 'expired'
        WHERE `status` = 'pending' AND `expires_at` <= CURRENT_TIMESTAMP
    ]])

    if affected and affected > 0 and Config.Debug then
        print(string.format("^3[Nyx:Factions]^7 Expired %d pending multi-sig requests^7", affected))
    end
end
