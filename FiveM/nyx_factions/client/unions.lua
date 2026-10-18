--[[
    Nyxframework: nyx_factions
    File: client/unions.lua
    Description: Client-side trade union interactions, Third-Eye (LALT) picket line overlays,
                 strike voting dialogs, and union status telemetry.
]]

-- Register Third-Eye (LALT) Union Interaction Options at Civic Terminals
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for idx, term in ipairs(Config.Terminals or {}) do
        exports['nyx_interact']:AddTargetCoords("union_terminal_" .. idx, term.coords, 2.0, {
            options = {
                {
                    icon = "fa-solid fa-users-line",
                    label = "Trade Union Registry & CBAs",
                    event = "nyx:factions:client:openUnionRegistry",
                    args = { terminal = term },
                    canInteract = function(entity, dist)
                        return dist <= 2.0
                    end
                },
                {
                    icon = "fa-solid fa-check-to-slot",
                    label = "Vote on Strike Authorization",
                    event = "nyx:factions:client:openStrikeVoting",
                    args = { terminal = term },
                    canInteract = function(entity, dist)
                        return dist <= 2.0
                    end
                },
                {
                    icon = "fa-solid fa-hand-holding-dollar",
                    label = "Claim Daily Strike Relief",
                    event = "nyx:factions:client:claimStrikeRelief",
                    args = { terminal = term },
                    canInteract = function(entity, dist)
                        return dist <= 2.0
                    end
                }
            },
            distance = 2.0
        })
    end
end)

-- Open Union Registry & Active CBAs
RegisterNetEvent("nyx:factions:client:openUnionRegistry", function()
    local ok, res = exports['nyx_core']:TriggerRPC("factions:getAllUnions")
    if not ok or not res or not res.success then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "TRADE UNION REGISTRY",
            message = "Unable to fetch union registry."
        })
        return
    end

    local unions = res.unions or {}
    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "ACCREDITED TRADE UNIONS",
        message = string.format("Found %d recognized labor organizations in Los Santos.", #unions)
    })
end)

-- Claim Daily Strike Relief
RegisterNetEvent("nyx:factions:client:claimStrikeRelief", function()
    local mOk, mRes = exports['nyx_core']:TriggerRPC("factions:getCitizenUnion")
    if not mOk or not mRes or not mRes.success or not mRes.membership then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "STRIKE RELIEF",
            message = "You are not registered in an accredited trade union."
        })
        return
    end

    local unionId = mRes.membership.union_id
    local ok, res = exports['nyx_core']:TriggerRPC("factions:claimStrikeRelief", unionId)
    if ok and res and res.success then
        local data = res.data or {}
        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "STRIKE RELIEF DISBURSED",
            message = string.format("Received $%.2f strike stipend. Fund balance: $%.2f",
                data.stipendPaid or 0.0, data.newStrikeFundBalance or 0.0)
        })
    else
        local err = res and res.error or "UNKNOWN_ERROR"
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "STRIKE RELIEF REJECTED",
            message = string.format("Claim denied: %s", tostring(err))
        })
    end
end)

-- Notification Handlers for Industrial Labor Events
RegisterNetEvent("nyx:factions:client:cbaUpdated", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "COLLECTIVE BARGAINING AGREEMENT",
        message = string.format("CBA %s updated for %s (Status: %s)",
            tostring(data.cbaId):sub(1, 8), tostring(data.enterpriseFactionId), tostring(data.status))
    })
end)

RegisterNetEvent("nyx:factions:client:strikeVoteStarted", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "warning",
        title = "STRIKE AUTHORIZATION VOTE CALLED",
        message = string.format("%s called strike vote on %s: %s",
            tostring(data.unionId), tostring(data.enterpriseFactionId), tostring(data.reason))
    })
end)

RegisterNetEvent("nyx:factions:client:strikeDeclared", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "error",
        title = "ACTIVE INDUSTRIAL STRIKE DECLARED",
        message = string.format("Picket lines active against %s! Facilities and depots locked.",
            tostring(data.enterpriseFactionId))
    })
end)

RegisterNetEvent("nyx:factions:client:strikeEnded", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "INDUSTRIAL STRIKE SETTLED",
        message = string.format("Strike against %s concluded (%s). Operations restored.",
            tostring(data.enterpriseFactionId), tostring(data.reason))
    })
end)

-- Command: /unionstatus
RegisterCommand("unionstatus", function()
    local ok, res = exports['nyx_core']:TriggerRPC("factions:getCitizenUnion")
    if not ok or not res or not res.success or not res.membership then
        TriggerEvent("chat:addMessage", {
            color = { 220, 80, 80 },
            multiline = true,
            args = { "[Trade Union]", "You are not a member of any trade union. Visit City Hall to organize or join a union local." }
        })
        return
    end

    local m = res.membership
    local uOk, uRes = exports['nyx_core']:TriggerRPC("factions:getUnion", m.union_id)
    local unionData = (uOk and uRes and uRes.union) or {}
    local runway = unionData.runway or {}

    TriggerEvent("chat:addMessage", {
        color = { 50, 180, 240 },
        multiline = true,
        args = {
            "[Trade Union]",
            string.format("Guild: %s (%s) | Role: %s | Standing: %s | Sector: %s",
                m.legal_name, m.union_id, string.upper(m.role or "member"), m.standing or "good_standing", m.industry_sector or "general")
        }
    })

    TriggerEvent("chat:addMessage", {
        color = { 240, 200, 80 },
        multiline = true,
        args = {
            "[Strike Fund]",
            string.format("Balance: $%.2f | Daily Burn: $%.2f | Runway: %d days (%s)",
                unionData.strikeFundBalance or 0.0, runway.daily_burn or 0.0, runway.runway_days or 0, runway.solvency_status or "SOLVENT")
        }
    })

    if m.enterprise_faction_id then
        local cbaOk, cbaRes = exports['nyx_core']:TriggerRPC("factions:getEnterpriseCBA", m.enterprise_faction_id)
        if cbaOk and cbaRes and cbaRes.cba then
            local c = cbaRes.cba
            TriggerEvent("chat:addMessage", {
                color = { 80, 220, 120 },
                multiline = true,
                args = {
                    "[Ratified CBA]",
                    string.format("Employer: %s | Wage Floor: $%.2f/hr | Overtime: %.1fx | Hazard Bonus: $%.2f",
                        m.enterprise_faction_id, tonumber(c.wage_floor) or 0.0, tonumber(c.overtime_multiplier) or 1.5, tonumber(c.hazard_pay_bonus) or 0.0)
                }
            })
        end
    end
end, false)

-- Command: /strikevote [yes|no|abstain]
RegisterCommand("strikevote", function(source, args)
    local vote = args[1] and string.lower(args[1]) or "yes"
    if vote ~= "yes" and vote ~= "no" and vote ~= "abstain" then
        TriggerEvent("chat:addMessage", {
            color = { 240, 120, 80 },
            args = { "[Usage]", "/strikevote <yes|no|abstain> [strikeId]" }
        })
        return
    end

    local strikeId = args[2]
    if not strikeId then
        -- Default to active strikes in state bag or prompt
        local strikes = GlobalState.activeStrikes or {}
        for _, s in pairs(strikes) do
            strikeId = s.strikeId
            break
        end
    end

    if not strikeId then
        TriggerEvent("chat:addMessage", {
            color = { 240, 80, 80 },
            args = { "[Error]", "No active strike vote identified. Provide strike ID: /strikevote <yes|no|abstain> <strikeId>" }
        })
        return
    end

    local ok, res = exports['nyx_core']:TriggerRPC("factions:castStrikeVote", { strikeId = strikeId, vote = vote })
    if ok and res and res.success then
        TriggerEvent("chat:addMessage", {
            color = { 80, 220, 120 },
            args = { "[Strike Ballot]", string.format("Recorded '%s' on strike %s (Total cast: %d)", vote, strikeId:sub(1,8), res.data.totalCast or 1) }
        })
    else
        TriggerEvent("chat:addMessage", {
            color = { 240, 80, 80 },
            args = { "[Strike Ballot]", string.format("Ballot rejected: %s", tostring(res and res.error or "ERROR")) }
        })
    end
end, false)
