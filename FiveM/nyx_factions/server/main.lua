--[[
    Nyxframework: nyx_factions
    File: server/main.lua
    Description: Server initialization, RPC endpoint registration, background sweeps,
                 and lifecycle orchestration.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

CreateThread(function()
    print("^4[Nyx:Factions]^7 Initializing Autonomous Player Organizations & Multi-Sig Vaults...^7")

    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- 1. Create a legal autonomous organization charter
        exports['nyx_core']:RegisterRPC("factions:createCharter", function(src, payload)
            local legalName = payload.legalName
            local charterType = payload.charterType
            local initialDeposit = payload.initialDeposit
            local ok, res = Nyx.Factions.CreateCharter(src, legalName, charterType, initialDeposit)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 2. Query organizational overview
        exports['nyx_core']:RegisterRPC("factions:getOverview", function(src, factionId)
            local overview = Nyx.Factions.GetFactionOverview(factionId)
            return { success = (overview ~= nil), overview = overview }
        end)

        -- 3. Add new member
        exports['nyx_core']:RegisterRPC("factions:addMember", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.AddMember(
                player.citizenId,
                payload.factionId,
                payload.targetCitizenId,
                payload.roleTitle,
                payload.permissionNodes,
                payload.equityShares,
                payload.wageHourly
            )
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 4. Update member role / permissions / equity
        exports['nyx_core']:RegisterRPC("factions:updateMember", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.UpdateMember(
                player.citizenId,
                payload.factionId,
                payload.targetCitizenId,
                payload.roleTitle,
                payload.permissionNodes,
                payload.equityShares,
                payload.wageHourly
            )
            return { success = ok, member = res, error = (not ok and res or nil) }
        end)

        -- 5. Terminate member employment
        exports['nyx_core']:RegisterRPC("factions:removeMember", function(src, factionId, targetCitId)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.RemoveMember(player.citizenId, factionId, targetCitId)
            return { success = ok, error = (not ok and res or nil) }
        end)

        -- 6. Initiate withdrawal (direct or multi-sig queue with vault binding)
        exports['nyx_core']:RegisterRPC("factions:initiateWithdrawal", function(src, payload)
            local ok, status, res = Nyx.Factions.InitiateWithdrawal(
                src,
                payload.factionId,
                payload.vaultId,
                payload.targetAccount,
                payload.amount,
                payload.reason
            )
            return { success = ok, status = status, data = res, error = (not ok and status or nil) }
        end)

        -- 7. Approve / Sign multi-sig request
        exports['nyx_core']:RegisterRPC("factions:signMultiSig", function(src, payload)
            local requestId = (type(payload) == "table") and payload.requestId or payload
            local note = (type(payload) == "table") and payload.note or nil
            local ok, status, res = Nyx.Factions.ApproveMultiSigRequest(src, requestId, note)
            return { success = ok, status = status, data = res, error = (not ok and status or nil) }
        end)

        -- 8. Reject multi-sig request
        exports['nyx_core']:RegisterRPC("factions:rejectMultiSig", function(src, requestId, reason)
            local ok, res = Nyx.Factions.RejectMultiSigRequest(src, requestId, reason)
            return { success = ok, error = (not ok and res or nil) }
        end)

        -- 8b. Cancel multi-sig request (Initiator or Authorized Executive)
        exports['nyx_core']:RegisterRPC("factions:cancelMultiSig", function(src, payload)
            local requestId = (type(payload) == "table") and payload.requestId or payload
            local reason = (type(payload) == "table") and payload.reason or "Cancelled via Client Request"
            local ok, res = Nyx.Factions.CancelMultiSigRequest(src, requestId, reason)
            return { success = ok, error = (not ok and res or nil) }
        end)

        -- 8c. Execute timelocked multi-sig request
        exports['nyx_core']:RegisterRPC("factions:executeTimelocked", function(src, requestId)
            local ok, status, res = Nyx.Factions.ExecuteTimelockedMultiSig(src, requestId)
            return { success = ok, status = status, data = res, error = (not ok and status or nil) }
        end)

        -- 8d. Corporate Vaults: Query all vaults
        exports['nyx_core']:RegisterRPC("factions:getVaults", function(src, factionId)
            local vaults = Nyx.Factions.GetFactionVaults(factionId)
            return { success = true, vaults = vaults }
        end)

        -- 8e. Corporate Vaults: Create new designated sub-vault
        exports['nyx_core']:RegisterRPC("factions:createVault", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.CreateVault(player.citizenId, payload.factionId, payload.vaultLabel, payload.dailyLimit)
            return { success = ok, vault = res, error = (not ok and res or nil) }
        end)

        -- 8f. Corporate Vaults: Emergency freeze / unfreeze toggle
        exports['nyx_core']:RegisterRPC("factions:freezeVault", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.SetVaultFreeze(player.citizenId, payload.factionId, payload.vaultId, payload.isFrozen, payload.reason)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 8g. Corporate Vaults: Inter-vault capital transfer
        exports['nyx_core']:RegisterRPC("factions:transferVaultFunds", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.TransferVaultFunds(player.citizenId, payload.factionId, payload.fromVaultId, payload.toVaultId, payload.amount, payload.memo)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 8h. Corporate Vaults: Deposit capital
        exports['nyx_core']:RegisterRPC("factions:depositVault", function(src, payload)
            local ok, res = Nyx.Factions.DepositToVault(src, payload.factionId, payload.vaultId, payload.amount)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 8i. Sign-Off Rules: Query rules
        exports['nyx_core']:RegisterRPC("factions:getSignoffRules", function(src, payload)
            local factionId = (type(payload) == "table") and payload.factionId or payload
            local vaultId = (type(payload) == "table") and payload.vaultId or nil
            local rules = Nyx.Factions.GetSignoffRules(factionId, vaultId)
            return { success = true, rules = rules }
        end)

        -- 8j. Sign-Off Rules: Set rule
        exports['nyx_core']:RegisterRPC("factions:setSignoffRule", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.SetSignoffRule(player.citizenId, payload.factionId, payload.ruleData)
            return { success = ok, rule = res, error = (not ok and res or nil) }
        end)

        -- 8k. Sign-Off Rules: Delete rule
        exports['nyx_core']:RegisterRPC("factions:deleteSignoffRule", function(src, payload)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.DeleteSignoffRule(player.citizenId, payload.factionId, payload.ruleId)
            return { success = ok, error = (not ok and res or nil) }
        end)

        -- 8l. Multi-Sig Audit Log
        exports['nyx_core']:RegisterRPC("factions:getAuditLog", function(src, payload)
            local factionId = (type(payload) == "table") and payload.factionId or payload
            local limit = (type(payload) == "table") and payload.limit or 50
            local logs = Nyx.Factions.GetMultiSigAuditLog(factionId, limit)
            return { success = true, logs = logs }
        end)

        -- 9. Preview dividends
        exports['nyx_core']:RegisterRPC("factions:previewDividends", function(src, factionId, netProfit, rate)
            local ok, res = Nyx.Factions.PreviewDividends(factionId, netProfit, rate)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 10. Execute dividend disbursement
        exports['nyx_core']:RegisterRPC("factions:distributeDividends", function(src, factionId, netProfit, rate)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local ok, res = Nyx.Factions.DistributeDividends(factionId, netProfit, rate, player.citizenId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 11. Query commercial fleet
        exports['nyx_core']:RegisterRPC("factions:getFleet", function(src, factionId)
            local fleet = Nyx.Factions.GetFactionFleet(factionId)
            return { success = true, fleet = fleet }
        end)

        -- 12. Spawn commercial vehicle from depot
        exports['nyx_core']:RegisterRPC("factions:spawnFleetVehicle", function(src, factionId, vin, depotId)
            local ok, res = Nyx.Factions.SpawnVehicle(src, factionId, vin, depotId)
            return { success = ok, vehicle = res, error = (not ok and res or nil) }
        end)

        -- 13. Store commercial vehicle to depot
        exports['nyx_core']:RegisterRPC("factions:storeFleetVehicle", function(src, factionId, vin, depotId, condition)
            local ok, res = Nyx.Factions.StoreVehicle(src, factionId, vin, depotId, condition)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 14. Trade Unions: Register Union
        exports['nyx_core']:RegisterRPC("factions:registerUnion", function(src, payload)
            local ok, res = Nyx.Factions.RegisterUnion(src, payload.legalName, payload.industrySector, payload.duesAmount, payload.duesMode)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 15. Trade Unions: Join Union
        exports['nyx_core']:RegisterRPC("factions:joinUnion", function(src, payload)
            local ok, res = Nyx.Factions.JoinUnion(src, payload.unionId, payload.enterpriseFactionId)
            return { success = ok, unionId = res, error = (not ok and res or nil) }
        end)

        -- 16. Trade Unions: Leave Union
        exports['nyx_core']:RegisterRPC("factions:leaveUnion", function(src, unionId)
            local ok, res = Nyx.Factions.LeaveUnion(src, unionId)
            return { success = ok, error = (not ok and res or nil) }
        end)

        -- 17. Trade Unions: Get Union Overview
        exports['nyx_core']:RegisterRPC("factions:getUnion", function(src, unionId)
            local union = Nyx.Factions.GetUnion(unionId)
            return { success = (union ~= nil), union = union }
        end)

        -- 18. Trade Unions: List All Unions
        exports['nyx_core']:RegisterRPC("factions:getAllUnions", function(src)
            local unions = Nyx.Factions.GetAllUnions()
            return { success = true, unions = unions }
        end)

        -- 19. Trade Unions: Get Citizen Membership
        exports['nyx_core']:RegisterRPC("factions:getCitizenUnion", function(src)
            local player = Nyx.GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end
            local membership = Nyx.Factions.GetCitizenUnionMembership(player.citizenId)
            return { success = (membership ~= nil), membership = membership }
        end)

        -- 20. Trade Unions: Deposit to Strike Fund
        exports['nyx_core']:RegisterRPC("factions:depositStrikeFund", function(src, payload)
            local ok, res = Nyx.Factions.DepositStrikeFund(src, payload.unionId, payload.amount)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 21. Trade Unions: Claim Daily Strike Pay
        exports['nyx_core']:RegisterRPC("factions:claimStrikeRelief", function(src, unionId)
            local ok, res = Nyx.Factions.ClaimStrikeRelief(src, unionId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 22. CBA: Propose Agreement
        exports['nyx_core']:RegisterRPC("factions:proposeCBA", function(src, payload)
            local ok, res = Nyx.Factions.ProposeCBA(src, payload.unionId, payload.enterpriseFactionId, payload.title, payload.wageFloor, payload.overtimeMultiplier, payload.hazardBonus)
            return { success = ok, cba = res, error = (not ok and res or nil) }
        end)

        -- 23. CBA: Ratify Agreement
        exports['nyx_core']:RegisterRPC("factions:ratifyCBA", function(src, cbaId)
            local ok, res = Nyx.Factions.RatifyCBA(src, cbaId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 24. CBA: Get Enterprise Ratified CBA
        exports['nyx_core']:RegisterRPC("factions:getEnterpriseCBA", function(src, enterpriseFactionId)
            local cba = Nyx.Factions.GetEnterpriseCBA(enterpriseFactionId)
            return { success = (cba ~= nil), cba = cba }
        end)

        -- 25. Strikes: Call Strike Vote
        exports['nyx_core']:RegisterRPC("factions:callStrikeVote", function(src, payload)
            local ok, res = Nyx.Factions.CallStrikeVote(src, payload.unionId, payload.enterpriseFactionId, payload.reason)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 26. Strikes: Cast Strike Vote
        exports['nyx_core']:RegisterRPC("factions:castStrikeVote", function(src, payload)
            local ok, res = Nyx.Factions.CastStrikeVote(src, payload.strikeId, payload.vote)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 27. Strikes: Petition Labor Arbitration
        exports['nyx_core']:RegisterRPC("factions:petitionLaborArbitration", function(src, strikeId)
            local ok, res = Nyx.Factions.PetitionLaborArbitration(src, strikeId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- 28. Strikes: Execute Arbitration Award
        exports['nyx_core']:RegisterRPC("factions:executeArbitrationAward", function(src, payload)
            local player = Nyx.GetPlayer(src)
            local arbitratorCitId = player and player.citizenId or "SYSTEM_ARBITRATOR"
            local ok, res = Nyx.Factions.ExecuteArbitrationAward(arbitratorCitId, payload.strikeId, payload.underpaidHours, payload.hourlyDeficit, payload.penaltyRate, payload.revisedWageFloor)
            return { success = ok, award = res, error = (not ok and res or nil) }
        end)
    end

    -- Background Task: Sweep expired multi-sig requests (every 10 minutes)
    CreateThread(function()
        while true do
            Wait(Config.MultiSig and (Config.MultiSig.AutoSweepInterval * 1000) or 600000)
            Nyx.Factions.SweepExpiredMultiSig()
        end
    end)

    print("^2[Nyx:Factions]^7 Online and authoritative.^7")
end)
