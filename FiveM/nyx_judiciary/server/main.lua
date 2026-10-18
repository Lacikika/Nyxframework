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
                payload.durationHours
            )
            return { success = ok, warrant = warrant, error = (not ok and warrant or nil) }
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

    print("^2[Nyx:Judiciary]^7 Online and authoritative.^7")
end)

-- Network Event Bridges for Client Action Hooks
RegisterNetEvent("nyx:judiciary:server:weaponFired", function(weaponHash, coords)
    local src = source
    if not coords or type(coords) ~= "vector3" and type(coords) ~= "table" then return end
    Nyx.Judiciary.RegisterBallisticEvent(src, weaponHash, coords)
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
