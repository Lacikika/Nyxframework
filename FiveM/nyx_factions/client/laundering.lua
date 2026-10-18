--[[
    Nyxframework: nyx_factions
    File: client/laundering.lua
    Description: Client-side interaction points for commercial front registers,
                 dirty cash deposit animations, and register status inspections.
]]

Nyx = Nyx or {}
Nyx.Laundering = Nyx.Laundering or {}
Nyx.Laundering.KnownRegisters = {}

-- Utility: Find closest registered commercial register
function Nyx.Laundering.GetNearestRegister()
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local closest = nil
    local minDistance = 99999.0

    for regId, reg in pairs(Nyx.Laundering.KnownRegisters) do
        if reg.coords then
            local dist = #(playerCoords - vector3(reg.coords.x, reg.coords.y, reg.coords.z))
            if dist < minDistance then
                minDistance = dist
                closest = reg
            end
        end
    end

    return closest, minDistance
end

-- Refresh known registers from server
function Nyx.Laundering.RefreshRegisters()
    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        local ok, data = exports['nyx_core']:CallRPC("factions:getCommercialRegisters", nil)
        if ok and type(data) == "table" then
            Nyx.Laundering.KnownRegisters = {}
            for _, reg in ipairs(data) do
                Nyx.Laundering.KnownRegisters[reg.register_id] = reg
            end
        end
    end
end

-- Interactive cash injection action
function Nyx.Laundering.StartInjection(registerId, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Kereskedelem]", "Érvénytelen befizetendő összeg." }
        })
        return
    end

    local reg = nil
    if registerId then
        reg = Nyx.Laundering.KnownRegisters[registerId]
    else
        local closest, dist = Nyx.Laundering.GetNearestRegister()
        if closest and dist <= 3.5 then
            reg = closest
        end
    end

    if not reg then
        TriggerEvent("chat:addMessage", {
            color = { 255, 120, 0 },
            multiline = true,
            args = { "[Kereskedelem]", "Nem található kereskedelmi pénztárgép a közeledben." }
        })
        return
    end

    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, "PROP_HUMAN_PARKING_METER", 0, true)
    Wait(2500)
    ClearPedTasks(ped)

    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        local success, result = exports['nyx_core']:CallRPC("factions:injectDirtyCash", {
            registerId = reg.register_id,
            amount = amount,
            sourceNote = "Front Store Counter Deposit"
        })

        if success and type(result) == "table" then
            PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
            TriggerEvent("chat:addMessage", {
                color = { 80, 220, 100 },
                multiline = true,
                args = { "[Pénztárgép]", string.format("Sikeres befizetés! $%.2f elhelyezve (%s). Új várakozó pool: $%.2f", amount, reg.label, result.newDirtyPool or 0.0) }
            })
            Nyx.Laundering.RefreshRegisters()
        else
            TriggerEvent("chat:addMessage", {
                color = { 255, 80, 80 },
                multiline = true,
                args = { "[Hiba]", string.format("Befizetés sikertelen: %s", tostring(result)) }
            })
        end
    end
end

-- Command: /injectcash [amount] [registerId]
RegisterCommand("injectcash", function(_, args)
    local amount = tonumber(args[1])
    local regId = args[2]
    Nyx.Laundering.StartInjection(regId, amount)
end, false)

RegisterCommand("launder", function(_, args)
    local amount = tonumber(args[1])
    local regId = args[2]
    Nyx.Laundering.StartInjection(regId, amount)
end, false)

-- Command: /registerinfo [registerId]
RegisterCommand("registerinfo", function(_, args)
    local regId = args[1]
    local reg = nil

    if regId and Nyx.Laundering.KnownRegisters[regId] then
        reg = Nyx.Laundering.KnownRegisters[regId]
    else
        local closest, dist = Nyx.Laundering.GetNearestRegister()
        if closest and dist <= 4.0 then
            reg = closest
        end
    end

    if not reg then
        TriggerEvent("chat:addMessage", {
            color = { 255, 120, 0 },
            multiline = true,
            args = { "[Kereskedelem]", "Nincs pénztárgép megadva vagy a közeledben." }
        })
        return
    end

    local badge = Nyx.Laundering.FormatStatusBadge and Nyx.Laundering.FormatStatusBadge(reg) or "[OK]"
    TriggerEvent("chat:addMessage", {
        color = { 100, 200, 255 },
        multiline = true,
        args = {
            "[Pénztárgép Adatok]",
            string.format("%s (%s) %s\nTiszta forgalom: $%.2f | Várakozó piszkos pool: $%.2f\nÖsszes tisztított: $%.2f | Napi limit: $%.2f",
                reg.label, reg.business_type, badge,
                reg.clean_cash_balance or 0.0, reg.dirty_cash_pool or 0.0,
                reg.total_washed or 0.0, reg.max_daily_laundering_cap or 0.0
            )
        }
    })
end, false)

CreateThread(function()
    Wait(2000)
    Nyx.Laundering.RefreshRegisters()
end)
