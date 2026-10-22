--[[
    Nyxframework: nyx_judiciary
    File: server/main.lua
    Description: Core server initialization, RPC registration, background sweeper cycles,
                 and event bridging.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

-- Initialize Server Lifecycle
CreateThread(function()
    print("^4[Nyx:Judiciary]^7 Initializing Decentralized Judiciary & Forensic Engine...^7")

    -- 1. Register RPC endpoints on the nyx_core bus
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- File a new docket
        exports['nyx_core']:RegisterRPC("judiciary:fileDocket", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local defCitId = payload.defendantCitizenId
            local title = payload.title
            local caseType = payload.caseType or "civil"
            local brief = payload.brief or ""

            local ok, res = Nyx.Judiciary.CreateDocket(player.citizenId, defCitId, title, caseType, brief, nil)
            return { success = ok, docketId = res, error = (not ok and res or nil) }
        end)

        -- Collect physical evidence from crime scene
        exports['nyx_core']:RegisterRPC("judiciary:collectEvidence", function(src, evidenceId, useGloves)
            local ok, res = Nyx.Judiciary.CollectEvidence(src, evidenceId, useGloves)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Cryptographic tamper verification
        exports['nyx_core']:RegisterRPC("judiciary:verifyEvidence", function(src, evidenceIdOrHash)
            local ok, status, data = Nyx.Judiciary.VerifyEvidence(evidenceIdOrHash)
            return { success = ok, status = status, data = data }
        end)

        -- Issue judicial warrant (requires judicial permission)
        exports['nyx_core']:RegisterRPC("judiciary:issueWarrant", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            -- Permission gate: check judge / DOJ permissions
            local isAuthorized = false
            for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                if player:hasPermission(perm) then isAuthorized = true break end
            end

            local job = player:getMetadata("job")
            if job == "judge" or job == "doj" then isAuthorized = true end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            local ok, warrant = Nyx.Judiciary.IssueWarrant(
                player.citizenId,
                payload.targetCitizenId,
                payload.type,
                payload.causeSummary,
                payload.targetEntityId,
                payload.durationHours,
                payload.petitionId,
                payload.subpoenaScope
            )
            return { success = ok, warrant = warrant, error = (not ok and warrant or nil) }
        end)

        -- Submit formal probable cause warrant petition (Officer -> Judicial Council)
        exports['nyx_core']:RegisterRPC("judiciary:petitionWarrant", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            local isAuthorized = (Config.Warrants.AuthorizedPetitioners and Config.Warrants.AuthorizedPetitioners[job]) or false
            if not isAuthorized then
                for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                    if player:hasPermission(perm) then isAuthorized = true break end
                end
            end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_PETITIONER" }
            end

            local ok, petition = Nyx.Judiciary.PetitionWarrant(
                player.citizenId,
                payload.targetCitizenId,
                payload.warrantType,
                payload.probableCauseSummary,
                payload.targetEntityId,
                payload.subpoenaScope,
                payload.requestedDurationHours
            )
            return { success = ok, petition = petition, error = (not ok and petition or nil) }
        end)

        -- Query pending warrant petitions (Judicial Council review queue)
        exports['nyx_core']:RegisterRPC("judiciary:getPendingPetitions", function(src)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            local isAuthorized = (job == "judge" or job == "doj") or player:hasPermission("admin")
            if not isAuthorized then
                for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                    if player:hasPermission(perm) then isAuthorized = true break end
                end
            end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            local petitions = Nyx.Judiciary.GetPendingPetitions()
            return { success = true, petitions = petitions }
        end)

        -- Review warrant petition: Approve with SHA-256 seal or Reject with cause (Judge)
        exports['nyx_core']:RegisterRPC("judiciary:reviewPetition", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            local isAuthorized = (job == "judge" or job == "doj") or player:hasPermission("admin")
            if not isAuthorized then
                for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                    if player:hasPermission(perm) then isAuthorized = true break end
                end
            end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            if not payload or not payload.petitionId or not payload.decision then
                return { success = false, error = "INVALID_PAYLOAD" }
            end

            local ok, res = Nyx.Judiciary.ReviewPetition(
                payload.petitionId,
                player.citizenId,
                payload.decision,
                payload.reviewNotes
            )
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        -- Subpoena Financial Records Disclosure Gatekeeper
        exports['nyx_core']:RegisterRPC("judiciary:getSubpoenaRecords", function(src, targetCitizenId)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            local isAuthorized = (Config.Warrants.AuthorizedPetitioners and Config.Warrants.AuthorizedPetitioners[job]) or false
            if not isAuthorized then
                for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                    if player:hasPermission(perm) then isAuthorized = true break end
                end
            end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_LAW_ENFORCEMENT_ACCESS" }
            end

            local ok, records = Nyx.Judiciary.GetSubpoenaFinancials(targetCitizenId, player.citizenId)
            return { success = ok, records = records, error = (not ok and records or nil) }
        end)

        -- Query active tracking warrants (wiretaps and active arrest warrants)
        exports['nyx_core']:RegisterRPC("judiciary:getActiveTrackingWarrants", function(src)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            local isAuthorized = (Config.Warrants.AuthorizedPetitioners and Config.Warrants.AuthorizedPetitioners[job]) or false
            if not isAuthorized then
                for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                    if player:hasPermission(perm) then isAuthorized = true break end
                end
            end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_LAW_ENFORCEMENT_ACCESS" }
            end

            local warrants = Nyx.Judiciary.GetActiveTrackingWarrants()
            return { success = true, warrants = warrants }
        end)

        -- Execute active warrant upon arrest or search
        exports['nyx_core']:RegisterRPC("judiciary:executeWarrant", function(src, warrantId)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            local isAuthorized = (Config.Warrants.AuthorizedPetitioners and Config.Warrants.AuthorizedPetitioners[job]) or false
            if not isAuthorized then
                for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                    if player:hasPermission(perm) then isAuthorized = true break end
                end
            end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_LAW_ENFORCEMENT_ACCESS" }
            end

            local ok, err = Nyx.Judiciary.ExecuteWarrant(warrantId, player.citizenId)
            return { success = ok, error = (not ok and err or nil) }
        end)

        -- Rescind active warrant
        exports['nyx_core']:RegisterRPC("judiciary:rescindWarrant", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            local isAuthorized = (job == "judge" or job == "doj") or player:hasPermission("admin")
            if not isAuthorized then
                for perm, _ in pairs(Config.Warrants.AuthorizedPermissions) do
                    if player:hasPermission(perm) then isAuthorized = true break end
                end
            end

            if not isAuthorized then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            local warrantId = type(payload) == "table" and payload.warrantId or payload
            local reason = type(payload) == "table" and payload.reason or "Judicial motion to quash"
            local ok, err = Nyx.Judiciary.RescindWarrant(warrantId, player.citizenId, reason)
            return { success = ok, error = (not ok and err or nil) }
        end)

        -- Start formal trial session in isolated courtroom routing bucket
        exports['nyx_core']:RegisterRPC("judiciary:startTrial", function(src, docketId)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            if job ~= "judge" and job ~= "doj" and not player:hasPermission("admin") then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            local ok, res = Nyx.Judiciary.StartTrial(docketId, player.citizenId)
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        -- Transition trial to deliberation chamber bucket
        exports['nyx_core']:RegisterRPC("judiciary:startDeliberation", function(src, docketId)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            if job ~= "judge" and job ~= "doj" and not player:hasPermission("admin") then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            local ok, res = Nyx.Judiciary.StartDeliberation(docketId, player.citizenId)
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        -- Seat summoned juror in designated jury box seat
        exports['nyx_core']:RegisterRPC("judiciary:seatJuror", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local docketId = (type(payload) == "table" and payload.docketId) or payload
            local preferredSeat = type(payload) == "table" and payload.seatIndex
            local ok, res = Nyx.Judiciary.SeatJuror(docketId, player.citizenId, preferredSeat)
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        -- Excuse juror on case
        exports['nyx_core']:RegisterRPC("judiciary:excuseJuror", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            if not payload or not payload.docketId or not payload.citizenId then
                return { success = false, error = "INVALID_PAYLOAD" }
            end

            local ok, res = Nyx.Judiciary.ExcuseJuror(payload.docketId, payload.citizenId, payload.reason)
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        -- Query jury roster for docket
        exports['nyx_core']:RegisterRPC("judiciary:getJuryStatus", function(src, docketId)
            local status = Nyx.Judiciary.GetJuryStatus(docketId)
            return { success = true, jurors = status }
        end)

        -- Manually dispatch or replenish jury pool for a docket
        exports['nyx_core']:RegisterRPC("judiciary:summonJury", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            if job ~= "judge" and job ~= "doj" and not player:hasPermission("admin") then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            local docketId = (type(payload) == "table" and payload.docketId) or payload
            local count = type(payload) == "table" and payload.requiredCount
            local ok, res = Nyx.Judiciary.SummonJury(docketId, count)
            return { success = ok, selected = res, error = (not ok and res or nil) }
        end)

        -- Cast secret ballot by seated juror
        exports['nyx_core']:RegisterRPC("judiciary:castJuryVote", function(src, docketId, voteOutcome)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Judiciary.CastSecretBallot(docketId, player.citizenId, voteOutcome)
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        -- Close docket with formal judgment execution
        exports['nyx_core']:RegisterRPC("judiciary:closeDocket", function(src, docketId, verdictPayload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Judiciary.ExecuteVerdict(docketId, verdictPayload, player.citizenId)
            return { success = ok, verdict = res, error = (not ok and res or nil) }
        end)

        -- Query active warrants
        exports['nyx_core']:RegisterRPC("judiciary:getActiveWarrants", function(src, targetCitId)
            local warrants = Nyx.Judiciary.GetActiveWarrants(targetCitId)
            return { success = true, warrants = warrants }
        end)

        -- Query specific docket details
        exports['nyx_core']:RegisterRPC("judiciary:getDocket", function(src, docketId)
            local docket = Nyx.Judiciary.GetDocket(docketId)
            return { success = (docket ~= nil), docket = docket }
        end)

        -- Query all active court proceedings
        exports['nyx_core']:RegisterRPC("judiciary:getActiveDockets", function(src)
            local dockets = Nyx.Judiciary.GetActiveDockets()
            return { success = true, dockets = dockets }
        end)

        -- Query full chronological chain-of-custody ledger
        exports['nyx_core']:RegisterRPC("judiciary:getChainOfCustody", function(src, evidenceId)
            local chain = Nyx.Judiciary.GetEvidenceChainOfCustody(evidenceId)
            return { success = true, chain = chain }
        end)

        -- Full cryptographic merkle / hash chain integrity verification
        exports['nyx_core']:RegisterRPC("judiciary:verifyChainOfCustody", function(src, evidenceId)
            local ok, status, data = Nyx.Judiciary.VerifyChainOfCustody(evidenceId)
            return { success = ok, status = status, data = data }
        end)

        -- Physical custody handoff (Officer to Officer)
        exports['nyx_core']:RegisterRPC("judiciary:transferCustody", function(src, payload)
            if not payload or not payload.evidenceId or not payload.targetCitizenId then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local ok, res = Nyx.Judiciary.TransferCustody(src, payload.evidenceId, payload.targetCitizenId, payload.notes)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Deposit evidence into secure police locker or court vault
        exports['nyx_core']:RegisterRPC("judiciary:storeInLocker", function(src, payload)
            if not payload or not payload.evidenceId or not payload.lockerId then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local ok, res = Nyx.Judiciary.StoreInLocker(src, payload.evidenceId, payload.lockerId, payload.notes)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Check out evidence from locker for active investigation / lab
        exports['nyx_core']:RegisterRPC("judiciary:checkoutFromLocker", function(src, payload)
            if not payload or not payload.evidenceId or not payload.lockerId then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local ok, res = Nyx.Judiciary.CheckoutFromLocker(src, payload.evidenceId, payload.lockerId, payload.reason)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Certified Forensic Crime Lab analysis submission
        exports['nyx_core']:RegisterRPC("judiciary:submitLabAnalysis", function(src, payload)
            if not payload or not payload.evidenceId or not payload.analysisType then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local ok, res = Nyx.Judiciary.SubmitLabAnalysis(src, payload.evidenceId, payload.analysisType, payload.findings)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Submit evidence as court exhibit linked to active docket
        exports['nyx_core']:RegisterRPC("judiciary:submitExhibitToCourt", function(src, payload)
            if not payload or not payload.evidenceId or not payload.docketId then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local ok, res = Nyx.Judiciary.SubmitExhibitToCourt(src, payload.evidenceId, payload.docketId, payload.exhibitLabel, payload.notes)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Create photographic / CCTV digital evidence
        exports['nyx_core']:RegisterRPC("judiciary:createPhotoEvidence", function(src, payload)
            if not payload or not payload.coords then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local ok, res = Nyx.Judiciary.RegisterPhotoEvidence(src, payload.cameraLocation, payload.snapshotHash, payload.coords, payload.notes)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Create forensic swab evidence (GSR or DNA)
        exports['nyx_core']:RegisterRPC("judiciary:createSwabEvidence", function(src, payload)
            if not payload or not payload.coords then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local dropId, hash = Nyx.Judiciary.RegisterSwabEvent(src, payload.targetCitizenId, payload.swabType, payload.coords, payload.isGSRPositive)
            return { success = (dropId ~= false), dropId = dropId, evidenceHash = hash }
        end)

        -- Query registered evidence lockers and forensic facilities
        exports['nyx_core']:RegisterRPC("judiciary:getLockers", function(src)
            return { success = true, lockers = Config.Forensics and Config.Forensics.Lockers or {} }
        end)

        -- ====================================================================
        -- Courtroom Terminal & Forensic Explorer UI RPC Endpoints
        -- ====================================================================

        -- Query full courtroom terminal overview
        exports['nyx_core']:RegisterRPC("judiciary:getCourtOverview", function(src)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local citId = player.citizenId
            local job = player:getMetadata("job") or "unemployed"
            local isJudge = (job == "judge" or job == "doj") or player:hasPermission("admin")
            local isLEO = (job == "police" or job == "sheriff" or job == "statepolice" or job == "marshal" or isJudge)

            -- 1. Active Dockets
            local dockets = Nyx.Judiciary.GetActiveDockets() or {}

            -- 2. Check if user is summoned/seated/deliberating juror on any active docket
            local myJuryRecord = nil
            local activeDocketForJuror = nil
            local juryRows = MySQL.query.await([[
                SELECT j.`jury_id`, j.`docket_id`, j.`citizen_id`, j.`seat_index`, j.`selection_status`,
                       j.`secret_ballot`, j.`stipend_paid`, d.`title` AS `docket_title`, d.`status` AS `docket_status`
                FROM `nyx_judiciary_juries` j
                INNER JOIN `nyx_judiciary_dockets` d ON j.`docket_id` = d.`docket_id`
                WHERE j.`citizen_id` = ? AND d.`status` IN ('scheduled', 'in_trial', 'deliberation')
                LIMIT 1
            ]], { citId })

            if juryRows and #juryRows > 0 then
                myJuryRecord = juryRows[1]
                activeDocketForJuror = juryRows[1].docket_id
            end

            -- 3. Recent forensic evidence records (top 25)
            local evidenceList = Nyx.Judiciary.GetEvidenceList(nil, nil, false, 25, 0)

            -- 4. Pending Petitions & Active Warrants
            local pendingPetitions = {}
            local activeWarrants = {}
            if isJudge or isLEO then
                pendingPetitions = Nyx.Judiciary.GetPendingPetitions() or {}
                activeWarrants = Nyx.Judiciary.GetActiveWarrants() or {}
            end

            -- 5. Jury status if juror or judge
            local juryDetails = nil
            if activeDocketForJuror then
                juryDetails = Nyx.Judiciary.GetJuryStatus(activeDocketForJuror)
            elseif #dockets > 0 and isJudge then
                juryDetails = Nyx.Judiciary.GetJuryStatus(dockets[1].docketId)
            end

            return {
                success = true,
                overview = {
                    citizenId = citId,
                    job = job,
                    isJudge = isJudge,
                    isLawEnforcement = isLEO,
                    dockets = dockets,
                    jurorRecord = myJuryRecord,
                    activeDocketForJuror = activeDocketForJuror,
                    juryDetails = juryDetails,
                    evidence = evidenceList,
                    pendingPetitions = pendingPetitions,
                    activeWarrants = activeWarrants
                }
            }
        end)

        -- Query evidence list with filters & pagination
        exports['nyx_core']:RegisterRPC("judiciary:getEvidenceList", function(src, payload)
            payload = payload or {}
            local rows = Nyx.Judiciary.GetEvidenceList(payload.search, payload.type, payload.isSealedOnly, payload.limit, payload.offset)
            return { success = true, evidence = rows }
        end)

        -- Query single evidence record with full chronological custody chain
        exports['nyx_core']:RegisterRPC("judiciary:getEvidenceChain", function(src, evidenceId)
            if not evidenceId then return { success = false, error = "INVALID_INPUT" } end
            local evidence = MySQL.single.await([[
                SELECT `evidence_id`, `docket_id`, `type`, `evidence_hash`, `collector_citizen_id`,
                       `current_custodian_id`, `current_facility`, `current_chain_hash`, `chain_length`,
                       `is_contaminated`, `contamination_source`, `is_sealed`, `metadata`, `lab_analysis`,
                       `exhibit_label`, `verified_by_judge_at`, `created_at`
                FROM `nyx_judiciary_evidence`
                WHERE `evidence_id` = ? OR `evidence_hash` = ?
            ]], { evidenceId, evidenceId })

            if not evidence then
                return { success = false, error = "EVIDENCE_NOT_FOUND" }
            end

            local meta = {}
            if type(evidence.metadata) == "string" then
                local ok, parsed = pcall(json.decode, evidence.metadata)
                if ok and type(parsed) == "table" then meta = parsed end
            elseif type(evidence.metadata) == "table" then
                meta = evidence.metadata
            end
            evidence.metadata = meta

            local lab = {}
            if type(evidence.lab_analysis) == "string" then
                local ok, parsed = pcall(json.decode, evidence.lab_analysis)
                if ok and type(parsed) == "table" then lab = parsed end
            elseif type(evidence.lab_analysis) == "table" then
                lab = evidence.lab_analysis
            end
            evidence.lab_analysis = lab

            local blocks = Nyx.Judiciary.GetEvidenceChainOfCustody(evidence.evidence_id)

            return {
                success = true,
                evidence = evidence,
                chain = blocks
            }
        end)

        -- Execute full SHA-256 chain verification & log audit entry
        exports['nyx_core']:RegisterRPC("judiciary:verifyEvidenceChain", function(src, evidenceId)
            local player = Nyx.GetPlayer(src)
            local citId = player and player.citizenId or "CIT_UNKNOWN"
            local job = player and player:getMetadata("job") or ""
            local isJudge = (job == "judge" or job == "doj")

            local ok, status, data = Nyx.Judiciary.VerifyChainOfCustody(evidenceId)

            -- Log formal verification in audit table
            local rootHash = data and data.rootHash or ""
            local headHash = data and data.currentChainHash or ""
            local chainLen = data and data.chainLength or 0

            Nyx.Judiciary.LogEvidenceVerification(evidenceId, citId, status, ok, chainLen, rootHash, headHash)

            if ok and isJudge then
                MySQL.prepare.await([[
                    UPDATE `nyx_judiciary_evidence`
                    SET `verified_by_judge_at` = CURRENT_TIMESTAMP
                    WHERE `evidence_id` = ?
                ]], { evidenceId })
            end

            return { success = ok, status = status, data = data }
        end)

        -- Conclude trial session with verdict ruling
        exports['nyx_core']:RegisterRPC("judiciary:concludeTrial", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local job = player:getMetadata("job")
            if job ~= "judge" and job ~= "doj" and not player:hasPermission("admin") then
                return { success = false, error = "UNAUTHORIZED_JUDICIAL_ACCESS" }
            end

            local docketId = type(payload) == "table" and payload.docketId or payload
            local verdict = type(payload) == "table" and payload.verdictRuling or "guilty"

            local ok, res = Nyx.Judiciary.ConcludeTrial(docketId, verdict)
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        -- Forensic Ballistics & NIBIN Integration RPCs
        exports['nyx_core']:RegisterRPC("judiciary:registerNIBINEntry", function(src, payload)
            if not payload or not payload.evidenceId then
                return { success = false, error = "INVALID_PAYLOAD" }
            end
            local ok, res = Nyx.Judiciary.Ballistics.RegisterNIBINEntry(src, payload.evidenceId, payload.docketId)
            return { success = ok, result = res, error = (not ok and res or nil) }
        end)

        exports['nyx_core']:RegisterRPC("judiciary:queryNIBINRecords", function(src, payload)
            payload = payload or {}
            local rows = Nyx.Judiciary.Ballistics.QueryNIBINRecords(payload.caliber, payload.matchStatus)
            return { success = true, records = rows }
        end)

        exports['nyx_core']:RegisterRPC("judiciary:getRiflingProfile", function(src, weaponSerial)
            if not weaponSerial then return { success = false, error = "INVALID_SERIAL" } end
            local profile = Nyx.Judiciary.Ballistics.GetOrCreateRiflingProfile(weaponSerial, "weapon_pistol")
            return { success = true, profile = profile }
        end)
    end

    -- 2. Evidence Sweeper Background Task (every 60s)
    CreateThread(function()
        while true do
            Wait(Config.Forensics and Config.Forensics.AutoSweepInterval and (Config.Forensics.AutoSweepInterval * 1000) or 60000)
            Nyx.Judiciary.SweepExpiredEvidence()
        end
    end)

    -- 3. Warrant Expiration Sweeper (every 10 minutes)
    CreateThread(function()
        while true do
            Wait(600000)
            Nyx.Judiciary.SweepExpiredWarrants()
        end
    end)

    -- 4. Jury Summons Timeout & Auto-Replacement Sweeper (every 30 seconds)
    CreateThread(function()
        while true do
            Wait(30000)
            if Nyx.Judiciary.CheckSummonsTimeouts then
                Nyx.Judiciary.CheckSummonsTimeouts()
            end
        end
    end)

    -- 5. Jury Deliberation Timeout Sweeper (every 30 seconds)
    CreateThread(function()
        while true do
            Wait(30000)
            if Nyx.Judiciary.CheckDeliberationTimeouts then
                Nyx.Judiciary.CheckDeliberationTimeouts()
            end
        end
    end)

    -- 6. Live Suspect Tracking Dispatcher Sweep (every 20 seconds)
    CreateThread(function()
        local interval = (Config.Warrants and Config.Warrants.Tracking and Config.Warrants.Tracking.IntervalSeconds or 20) * 1000
        while true do
            Wait(interval)
            local trackingWarrants = Nyx.Judiciary.GetActiveTrackingWarrants()
            if trackingWarrants and #trackingWarrants > 0 then
                for _, w in ipairs(trackingWarrants) do
                    local targetPlayer = Nyx.GetPlayerByCitizenId(w.target_citizen_id)
                    if targetPlayer and targetPlayer.source then
                        local ped = GetPlayerPed(tostring(targetPlayer.source))
                        if ped and DoesEntityExist(ped) then
                            local pCoords = GetEntityCoords(ped)
                            local accRadius = (Config.Warrants and Config.Warrants.Tracking and Config.Warrants.Tracking.DefaultAccuracyRadius) or 35.0
                            local pingResult = Nyx.Warrants.CalculateTrackingPing(pCoords, accRadius)
                            if pingResult then
                                Nyx.Judiciary.RecordTrackingPing(w.warrant_id, w.target_citizen_id, pingResult.coords, accRadius, "cellular_triangulation")

                                local pingPayload = {
                                    warrantId = w.warrant_id,
                                    targetCitizenId = w.target_citizen_id,
                                    targetName = targetPlayer.name or ("Suspect " .. w.target_citizen_id),
                                    warrantType = w.type,
                                    coords = pingResult.coords,
                                    accuracyRadius = accRadius,
                                    timestamp = pingResult.timestamp
                                }

                                for _, officerSrc in ipairs(GetPlayers()) do
                                    local oId = tonumber(officerSrc)
                                    local isAuth = false
                                    if exports['nyx_mdt'] and exports['nyx_mdt'].IsAuthorized then
                                        isAuth = exports['nyx_mdt']:IsAuthorized(oId)
                                    else
                                        local oPlr = Nyx.GetPlayer(oId)
                                        local oJob = oPlr and oPlr:getMetadata("job")
                                        if oJob == "police" or oJob == "sheriff" or oJob == "state_police" or oJob == "doj" then
                                            isAuth = true
                                        end
                                    end

                                    if isAuth then
                                        TriggerClientEvent("nyx:mdt:client:warrantTrackingPing", oId, pingPayload)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    print("^2[Nyx:Judiciary]^7 Online and authoritative.^7")
end)

-- Clean up juror / courtroom state on player disconnect
AddEventHandler("playerDropped", function(reason)
    local src = source
    local docketId = Player and Player(src) and Player(src).state and Player(src).state.courtroomDocket
    if docketId then
        local player = Nyx.GetPlayer(src)
        local citId = player and player.citizenId
        if citId then
            local juror = MySQL.single.await([[
                SELECT `selection_status` FROM `nyx_judiciary_juries` WHERE `docket_id` = ? AND `citizen_id` = ?
            ]], { docketId, citId })
            if juror and juror.selection_status == 'summoned' then
                Nyx.Judiciary.ExcuseJuror(docketId, citId, "disconnect")
            end
        end
    end
end)


-- Network Event Bridges for Client Action Hooks
RegisterNetEvent("nyx:judiciary:server:weaponFired", function(weaponHash, coords, ejectionAngleDeg)
    local src = source
    if not coords or type(coords) ~= "vector3" and type(coords) ~= "table" then return end
    if Nyx.Judiciary.Ballistics and Nyx.Judiciary.Ballistics.RegisterDischargeEvent then
        Nyx.Judiciary.Ballistics.RegisterDischargeEvent(src, weaponHash, coords, ejectionAngleDeg)
    else
        Nyx.Judiciary.RegisterBallisticEvent(src, weaponHash, coords)
    end
end)

RegisterNetEvent("nyx:judiciary:server:traumaOccurred", function(victimSrc, damageType, coords)
    local attackerSrc = source
    if not victimSrc or not coords then return end
    Nyx.Judiciary.RegisterTraumaEvent(victimSrc, attackerSrc, damageType, coords)
end)

RegisterNetEvent("nyx:judiciary:server:surfaceTouched", function(surfaceDesc, coords)
    local src = source
    if not coords then return end
    Nyx.Judiciary.RegisterFingerprintEvent(src, surfaceDesc, coords)
end)

RegisterNetEvent("nyx:judiciary:server:swabTaken", function(targetCitId, swabType, coords, isGSRPositive)
    local src = source
    if not coords then return end
    Nyx.Judiciary.RegisterSwabEvent(src, targetCitId, swabType, coords, isGSRPositive)
end)

RegisterNetEvent("nyx:judiciary:server:photoCaptured", function(cameraLocation, snapshotHash, coords, notes)
    local src = source
    if not coords then return end
    Nyx.Judiciary.RegisterPhotoEvidence(src, cameraLocation, snapshotHash, coords, notes)
end)
