--[[
    Nyxframework: nyx_judiciary
    File: server/execution.lua
    Description: Automated execution of judicial rulings: restitution splits, penal fines via nyx_treasury,
                 custodial sentencing, and warrant invalidation.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

-- 1. Automatic Execution of Court Rulings & Verdicts
function Nyx.Judiciary.ExecuteVerdict(docketId, verdictPayload, presidingJudgeCitId)
    if not docketId or not verdictPayload then
        return false, "MISSING_VERDICT_PAYLOAD"
    end

    local docket = MySQL.single.await([[
        SELECT `docket_id`, `title`, `plaintiff_citizen_id`, `defendant_citizen_id`, `case_type`, `status`
        FROM `nyx_judiciary_dockets`
        WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    if docket.status == 'concluded' or docket.status == 'dismissed' then
        return false, "DOCKET_ALREADY_CONCLUDED"
    end

    local ruling = verdictPayload.ruling or "dismissed" -- 'guilty', 'not_guilty', 'dismissed'
    local restitution = math.max(0, tonumber(verdictPayload.restitution) or 0)
    local fine = math.max(0, tonumber(verdictPayload.fine) or 0)
    local sentenceMonths = math.max(0, math.floor(tonumber(verdictPayload.sentenceMonths) or 0))
    local summary = verdictPayload.summary or "Judgment rendered by authority of San Andreas District Court."

    local executionLog = {
        restitutionPaid = 0,
        restitutionDebt = 0,
        finePaid = 0,
        fineDebt = 0,
        custodialApplied = false
    }

    local defendantAcc = "citizen:" .. docket.defendant_citizen_id
    local plaintiffAcc = "citizen:" .. docket.plaintiff_citizen_id
    local cityMasterAcc = "gov:city:master"

    if ruling == "guilty" then
        -- Step 1: Execute Civil Restitution to Plaintiff
        if restitution > 0 then
            local defBalance = exports['nyx_treasury']:GetAccountBalance(defendantAcc) or 0.0
            local transferAmount = math.min(restitution, defBalance)

            if transferAmount > 0 then
                local ok, err = exports['nyx_treasury']:ExecuteTransfer(
                    defendantAcc,
                    plaintiffAcc,
                    transferAmount,
                    "restitution",
                    "judiciary:" .. docketId,
                    string.format("Court Restitution Order: %s", docketId),
                    0.0
                )
                if ok then
                    executionLog.restitutionPaid = transferAmount
                end
            end

            if transferAmount < restitution then
                executionLog.restitutionDebt = restitution - transferAmount
            end
        end

        -- Step 2: Execute Statutory Penal Fine to Municipal Master Account
        if fine > 0 then
            local currentBal = exports['nyx_treasury']:GetAccountBalance(defendantAcc) or 0.0
            local fineAmount = math.min(fine, currentBal)

            if fineAmount > 0 then
                local ok, err = exports['nyx_treasury']:ExecuteTransfer(
                    defendantAcc,
                    cityMasterAcc,
                    fineAmount,
                    "fine",
                    "judiciary:" .. docketId,
                    string.format("Court Statutory Penalty: %s", docketId),
                    0.0
                )
                if ok then
                    executionLog.finePaid = fineAmount
                end
            end

            if fineAmount < fine then
                executionLog.fineDebt = fine - fineAmount
            end
        end

        -- Step 3: Custodial Sentencing Enforcement
        if sentenceMonths > 0 then
            -- Commit incarceration record into penal labor database
            if Nyx.Judiciary.IncarcerateCitizen then
                Nyx.Judiciary.IncarcerateCitizen(docket.defendant_citizen_id, sentenceMonths, "cell_block_a")
            end

            local defendantPlayer = Nyx.GetPlayerByCitizenId(docket.defendant_citizen_id)
            if defendantPlayer then
                defendantPlayer:setMetadata("inJail", true)
                defendantPlayer:setMetadata("prisonSentence", sentenceMonths)
                defendantPlayer:setMetadata("jailTimestamp", os.time())

                -- Transition network traffic to isolated penitentiary routing bucket
                local bucket = Config.Penitentiary and Config.Penitentiary.RoutingBucket or 5000
                exports['nyx_core']:SetRoutingBucket(defendantPlayer.source, bucket)

                -- Teleport ped to Bolingbroke cell
                local ped = GetPlayerPed(tostring(defendantPlayer.source))
                if DoesEntityExist(ped) and Config.Penitentiary and Config.Penitentiary.CellCoords then
                    local c = Config.Penitentiary.CellCoords
                    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, true)
                    SetEntityHeading(ped, c.w or 0.0)
                end

                TriggerClientEvent("nyx:judiciary:client:sentenced", defendantPlayer.source, {
                    sentenceMonths = sentenceMonths,
                    docketId = docketId
                })
                executionLog.custodialApplied = true
            else
                -- Target is offline: commit prison sentence directly into database metadata
                local charRow = MySQL.single.await([[
                    SELECT `char_id`, `metadata` FROM `nyx_characters` WHERE `citizen_id` = ?
                ]], { docket.defendant_citizen_id })

                if charRow then
                    local meta = {}
                    if type(charRow.metadata) == "string" then
                        local ok, parsed = pcall(json.decode, charRow.metadata)
                        if ok and type(parsed) == "table" then meta = parsed end
                    elseif type(charRow.metadata) == "table" then
                        meta = charRow.metadata
                    end

                    meta.inJail = true
                    meta.prisonSentence = sentenceMonths
                    meta.jailTimestamp = os.time()

                    MySQL.prepare.await([[
                        UPDATE `nyx_characters` SET `metadata` = ? WHERE `char_id` = ?
                    ]], { json.encode(meta), charRow.char_id })

                    executionLog.custodialApplied = true
                end
            end
        end

        -- Step 4: Invalidate active arrest warrants related to this offender
        MySQL.prepare.await([[
            UPDATE `nyx_judiciary_warrants`
            SET `status` = 'executed'
            WHERE `target_citizen_id` = ? AND `type` = 'arrest' AND `status` = 'active'
        ]], { docket.defendant_citizen_id })
    else
        -- Not guilty or dismissed: rescind active arrest warrants for this defendant
        MySQL.prepare.await([[
            UPDATE `nyx_judiciary_warrants`
            SET `status` = 'rescinded'
            WHERE `target_citizen_id` = ? AND `type` = 'arrest' AND `status` = 'active'
        ]], { docket.defendant_citizen_id })
    end

    -- Store formal verdict and close docket
    local finalVerdictRecord = {
        ruling = ruling,
        restitution = restitution,
        fine = fine,
        sentenceMonths = sentenceMonths,
        summary = summary,
        adjudicatedBy = presidingJudgeCitId or "COURT_TRIBUNAL",
        executionLog = executionLog,
        closedAt = os.time()
    }

    local finalStatus = (ruling == "dismissed") and "dismissed" or "concluded"

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `status` = ?,
            `verdict` = ?
        WHERE `docket_id` = ?
    ]], { finalStatus, json.encode(finalVerdictRecord), docketId })

    -- Broadcast verdict public announcement
    TriggerClientEvent("nyx:judiciary:client:verdictAnnounced", -1, {
        docketId = docketId,
        title = docket.title,
        ruling = ruling,
        restitution = restitution,
        fine = fine,
        sentenceMonths = sentenceMonths
    })

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Executed verdict on %s: Ruling: %s, Restitution: $%.2f, Fine: $%.2f, Prison: %d mo^7",
            docketId, ruling, restitution, fine, sentenceMonths))
    end

    -- Pre-Trial Bail Exoneration: resolve any active bail bond escrow
    if Nyx.Judiciary.ExonerateBail then
        Nyx.Judiciary.ExonerateBail(docketId, string.format("Verdict rendered (%s); bail exonerated.", ruling))
    end

    -- Conclude trial session: award juror stipends, log civic service, restore public routing bucket
    if Nyx.Judiciary.ConcludeTrial then
        Nyx.Judiciary.ConcludeTrial(docketId, ruling)
    end

    return true, finalVerdictRecord
end

