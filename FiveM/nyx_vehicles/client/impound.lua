--[[
    Nyxframework: nyx_vehicles
    File: client/impound.lua
    Description: Client-side municipal impound lot terminals, Third-Eye (LALT) integration,
                 and vehicle registration renewal dialogs.
]]

local impoundLots = {
    { id = "impound_lot_ls", label = "Los Santos Municipal Auto Impound", coords = vector3(401.2, -1631.5, 29.3) },
    { id = "impound_lot_sandy", label = "Blaine County Sheriff Impound Compound", coords = vector3(1853.2, 3685.4, 34.2) }
}

-- Register Third-Eye (LALT) Impound Lot Targets
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(500)
    end

    for _, lot in ipairs(impoundLots) do
        exports['nyx_interact']:AddTargetCoords("impound_terminal_" .. lot.id, lot.coords, 2.5, {
            options = {
                {
                    icon = "fa-solid fa-truck-pickup",
                    label = "Lefoglalt Járművek Kiváltása (Impound Retrieval)",
                    event = "nyx:vehicles:client:openImpoundMenu",
                    args = { lotId = lot.id, lotLabel = lot.label },
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                },
                {
                    icon = "fa-solid fa-id-card",
                    label = "Forgalmi Engedély Megújítása (Renew Registration)",
                    event = "nyx:vehicles:client:openRegistrationMenu",
                    args = { lotId = lot.id },
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                }
            },
            distance = 2.5
        })
    end
end)

-- Open Impound Menu
RegisterNetEvent("nyx:vehicles:client:openImpoundMenu", function(data)
    local lotId = data and data.lotId or "impound_lot_ls"
    local lotLabel = data and data.lotLabel or "Városi Telep"

    local ok, vehicles = exports['nyx_core']:TriggerRPC("vehicles:getImpoundedVehicles", { lotId = lotId })
    if not ok or not vehicles then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "VÁROSI AUTÓMENTŐ",
            message = "Nem sikerült lekérdezni a lefoglalt járműveket."
        })
        return
    end

    if #vehicles == 0 then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = lotLabel,
            message = "Önnek nincs lefoglalt járműve ezen a telepen."
        })
        return
    end

    print(string.format("^3[Nyx:Vehicles] %d impounded vehicles found for lot %s^7", #vehicles, lotId))
    for _, v in ipairs(vehicles) do
        local msg = string.format("[%s] %s | Összes díj: $%.2f (Alap: $%.2f, Tárolás: $%.2f, Felár: $%.2f) - Kiváltás: /releasevehicle %s",
            v.plate, v.modelName, v.cost.totalFee, v.cost.baseFee, v.cost.storageFee, v.cost.emergencySurcharge, v.vin)
        TriggerEvent("chat:addMessage", {
            color = { 255, 180, 0 },
            multiline = true,
            args = { "IMPOUND", msg }
        })
    end
end)

-- Command to inspect impounded vehicles
RegisterCommand("myimpounds", function()
    TriggerEvent("nyx:vehicles:client:openImpoundMenu", { lotId = nil, lotLabel = "Városi Autómentő" })
end, false)

-- Command to release vehicle from impound
RegisterCommand("releasevehicle", function(source, args)
    local vin = args[1]
    if not vin or vin == "" then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "KIVÁLTÁS",
            message = "Használat: /releasevehicle <VIN>"
        })
        return
    end

    local ok, res = exports['nyx_core']:TriggerRPC("vehicles:releaseImpoundedVehicle", { vin = vin })
    if not ok or not res then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "KIVÁLTÁS SIKERTELEN",
            message = tostring(res or "A kiváltás meghiúsult. Ellenőrizze egyenlegét!")
        })
        return
    end

    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "JÁRMŰ KIVÁLTVA",
        message = string.format("Jármű [%s] sikeresen kiváltva! Kifizetve: $%.2f.", res.plate, res.totalPaid)
    })
end, false)

-- Open Registration Menu
RegisterNetEvent("nyx:vehicles:client:openRegistrationMenu", function(data)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then
        local plate = GetVehicleNumberPlateText(veh)
        local ok, reg = exports['nyx_core']:TriggerRPC("vehicles:getRegistration", { vin = plate })
        if ok and reg then
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "FORGALMI ENGEDÉLY",
                message = string.format("Rendszám: %s | Állapot: %s | Hosszabbítási díj: $%.2f (/renewreg %s)",
                    reg.plate, reg.status, reg.fee.totalFee, reg.vin)
            })
            return
        end
    end

    TriggerEvent("chat:addMessage", {
        color = { 0, 180, 255 },
        multiline = true,
        args = { "FORGALMI", "Használat: /vehiclereg <VIN> vagy /renewreg <VIN>" }
    })
end)

-- Command to check vehicle registration
RegisterCommand("vehiclereg", function(source, args)
    local vin = args[1]
    if not vin or vin == "" then
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh and veh ~= 0 then
            vin = GetVehicleNumberPlateText(veh)
        end
    end

    if not vin or vin == "" then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "FORGALMI",
            message = "Használat: /vehiclereg <VIN>"
        })
        return
    end

    local ok, reg = exports['nyx_core']:TriggerRPC("vehicles:getRegistration", { vin = vin })
    if not ok or not reg then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "FORGALMI HIBA",
            message = "A megadott jármű nem található."
        })
        return
    end

    local expStr = os.date("%Y-%m-%d %H:%M", reg.expiresAt)
    TriggerEvent("chat:addMessage", {
        color = { 0, 200, 150 },
        multiline = true,
        args = { "FORGALMI", string.format("Jármű: %s [%s] | Állapot: %s | Lejárat: %s | Megújítás: $%.2f (/renewreg %s)",
            reg.modelName, reg.plate, reg.status, expStr, reg.fee.totalFee, reg.vin) }
    })
end, false)

-- Command to renew registration
RegisterCommand("renewreg", function(source, args)
    local vin = args[1]
    if not vin or vin == "" then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "MEGÚJÍTÁS",
            message = "Használat: /renewreg <VIN>"
        })
        return
    end

    local ok, res = exports['nyx_core']:TriggerRPC("vehicles:renewRegistration", { vin = vin })
    if not ok or not res then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "MEGÚJÍTÁS SIKERTELEN",
            message = tostring(res or "A forgalmi megújítása meghiúsult. Ellenőrizze egyenlegét!")
        })
        return
    end

    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "FORGALMI MEGÚJÍTVA",
        message = string.format("Jármű [%s] forgalmi engedélye megújítva! Levonva: $%.2f.", res.plate, res.totalPaid)
    })
end, false)
