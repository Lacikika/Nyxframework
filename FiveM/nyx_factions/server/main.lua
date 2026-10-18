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

        -- 6. Initiate withdrawal (direct or multi-sig queue)
        exports['nyx_core']:RegisterRPC("factions:initiateWithdrawal", function(src, payload)
            local ok, status, res = Nyx.Factions.InitiateWithdrawal(
                src,
                payload.factionId,
                payload.targetAccount,
                payload.amount,
                payload.reason
            )
            return { success = ok, status = status, data = res, error = (not ok and status or nil) }
        end)

        -- 7. Approve / Sign multi-sig request
        exports['nyx_core']:RegisterRPC("factions:signMultiSig", function(src, requestId)
            local ok, status, res = Nyx.Factions.ApproveMultiSigRequest(src, requestId)
            return { success = ok, status = status, data = res, error = (not ok and status or nil) }
        end)

        -- 8. Reject multi-sig request
        exports['nyx_core']:RegisterRPC("factions:rejectMultiSig", function(src, requestId, reason)
            local ok, res = Nyx.Factions.RejectMultiSigRequest(src, requestId, reason)
            return { success = ok, error = (not ok and res or nil) }
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
