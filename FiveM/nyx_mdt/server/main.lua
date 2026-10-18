--[[
    Nyxframework: nyx_mdt
    File: server/main.lua
    Description: Mobile Data Terminal CAD engine, authorization gates,
                 and master state synchronization.
]]

Nyx = Nyx or {}
Nyx.MDT = Nyx.MDT or {}
Nyx.MDT.ActiveCalls = {} -- [call_id] = callData
Nyx.MDT.OnDutyUnits = {} -- [source] = { citizenId, callsign, job, grade }

-- Check if player is authorized for MDT
function Nyx.MDT.IsAuthorized(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false end

    -- Check job/faction
    local job = player.job or (player.getJob and player:getJob()) or "unemployed"
    if Config.MDT.AuthorizedJobs[job] then return true end

    -- Check permission override
    if player.hasPermission and player.hasPermission("police_officer") then return true end

    return false
end

-- Load active calls on database ready
MySQL.ready(function()
    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_mdt_calls`
        WHERE `status` IN ('active', 'assigned')
        ORDER BY `created_at` DESC
        LIMIT 50
    ]])

    if rows then
        for _, r in ipairs(rows) do
            Nyx.MDT.ActiveCalls[r.call_id] = {
                id = r.call_id,
                code = r.code,
                title = r.title,
                description = r.description,
                caller = r.caller,
                coords = json.decode(r.coords),
                location = r.location_label,
                priority = r.priority,
                status = r.status,
                assignedUnit = r.assigned_unit,
                time = os.date("%H:%M", math.floor(os.time()))
            }
        end
        print(string.format("^2[Nyx:MDT] Loaded %d active dispatch calls into memory cache.^7", #rows))
    end
end)

-- RPC: Open MDT Terminal (Returns dispatch feed, warrants, and unit status)
exports['nyx_core']:RegisterRPC("mdt:getDashboard", function(src)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED_PERSONNEL" }
    end

    local callsList = {}
    for _, c in pairs(Nyx.MDT.ActiveCalls) do
        callsList[#callsList + 1] = c
    end

    -- Query active warrants from nyx_judiciary
    local warrants = MySQL.query.await([[
        SELECT `warrant_id`, `target_citizen_id`, `type`, `probable_cause_summary`, `expires_at`
        FROM `nyx_judiciary_warrants`
        WHERE `status` = 'active'
        ORDER BY `created_at` DESC
        LIMIT 25
    ]]) or {}

    return {
        success = true,
        calls = callsList,
        warrants = warrants
    }
end)
