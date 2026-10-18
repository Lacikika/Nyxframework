--[[
    Nyxframework: nyx_factions
    File: client/cash_transit.lua
    Description: Client-side interaction triggers for packing commercial register excess cash
                 into physical armored cash boxes for Cash-In-Transit (CIT) couriers.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.CashTransit = Nyx.CashTransit or {}

-- 1. Client Event to Pack Excess Cash for Transit
RegisterNetEvent("nyx:factions:client:createTransitBox", function(data)
    local regId = (type(data) == "table" and data.registerId)
    local amount = (type(data) == "table" and data.amount)

    if not regId then
        TriggerEvent("nyx:core:notify", {
            type = "error",
            title = "Kassza Hiba",
            message = "Hiányzó kassza azonosító!"
        })
        return
    end

    local ped = PlayerPedId()
    RequestAnimDict("anim@heists@money_grab@briefcase@")
    while not HasAnimDictLoaded("anim@heists@money_grab@briefcase@") do
        Wait(10)
    end
    TaskPlayAnim(ped, "anim@heists@money_grab@briefcase@", "money_grab_idle", 8.0, -8.0, 3000, 1, 0, false, false, false)

    Wait(3000)
    ClearPedTasks(ped)

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("factions:createCashTransitBox", {
            registerId = regId,
            amount = amount or 10000.00
        }, function(response)
            if response and response.success then
                PlaySoundFrontend(-1, "LOCAL_PLYR_CASH_COUNTER_COMPLETE", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
            else
                TriggerEvent("nyx:core:notify", {
                    type = "error",
                    title = "Szállítási Hiba",
                    message = "Nem sikerült a készpénzt lezárni: " .. tostring(response and response.error)
                })
            end
        end)
    end
end)

-- 2. Chat Commands
RegisterCommand("createtransitbox", function(source, args, rawCommand)
    local regId = args[1]
    local amount = tonumber(args[2])

    if not regId then
        TriggerEvent("nyx:core:notify", {
            type = "info",
            title = "Használat",
            message = "/createtransitbox <registerId> [amount]"
        })
        return
    end

    TriggerEvent("nyx:factions:client:createTransitBox", {
        registerId = regId,
        amount = amount or 10000.00
    })
end, false)

RegisterCommand("transitstatus", function(source, args, rawCommand)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("factions:getRegistersNeedingTransit", {}, function(registers)
            if not registers or #registers == 0 then
                TriggerEvent("nyx:core:notify", {
                    type = "info",
                    title = "Páncélozott Szállítás",
                    message = "Jelenleg egyetlen kassza sem éri el a szállítási limitet."
                })
                return
            end

            print("^3=== REGISTERS NEEDING CASH TRANSIT ===^7")
            for _, r in ipairs(registers) do
                print(string.format("^2[%s]^7 %s | Egyenleg: $%.2f | Javasolt doboz: $%.2f",
                    r.registerId, r.label, r.cleanCashBalance, r.suggestedBoxAmount))
            end
            TriggerEvent("nyx:core:notify", {
                type = "success",
                title = "Szállítási Igény",
                message = string.format("%d kassza igényel készpénzszállítást. Részletek a konzolon (F8).", #registers)
            })
        end)
    end
end, false)

-- 3. Client Exports
exports("CreateCashTransitBox", function(registerId, amount)
    TriggerEvent("nyx:factions:client:createTransitBox", { registerId = registerId, amount = amount })
end)
