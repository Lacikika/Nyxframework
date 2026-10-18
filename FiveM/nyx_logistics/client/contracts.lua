--[[
    Nyxframework: nyx_logistics
    File: client/contracts.lua
    Description: Freight dispatch terminal targets (nyx_interact), NUI bridge,
                 and event-driven GPS waypoint tracking (0.00 ms idle).
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}

local activeBlip = nil
local activeRouteBlip = nil

-- ----------------------------------------------------------------------------
-- 1. Register Dispatch Terminals via nyx_interact (0.00 ms Idle)
-- ----------------------------------------------------------------------------
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for _, term in ipairs(Nyx.Logistics.FreightConfig.DispatchTerminals) do
        -- Register interaction point at coordinates
        exports['nyx_interact']:AddTargetCoords(term.id, term.coords, 2.5, {
            options = {
                {
                    label = "Fuvarozási Tőzsde Megnyitása",
                    icon = "fa-solid fa-truck-ramp-box",
                    action = function()
                        Nyx.Logistics.OpenFreightBoard()
                    end
                }
            },
            distance = 2.5
        })
    end
end)

-- ----------------------------------------------------------------------------
-- 2. Open / Close Freight Board UI via nyx_ui Master SPA
-- ----------------------------------------------------------------------------
function Nyx.Logistics.OpenFreightBoard()
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local data = exports['nyx_core']:TriggerRPCAwait("logistics:getFreightBoard")
        if data and data.success then
            SetNuiFocus(true, true)
            SendNUIMessage({
                action = "FREIGHT_BOARD_OPEN",
                contracts = data.contracts,
                activeContract = data.activeContract
            })
        end
    end
end

-- Fallback client command
RegisterCommand("freightboard", function()
    Nyx.Logistics.OpenFreightBoard()
end, false)

-- ----------------------------------------------------------------------------
-- 3. Dynamic GPS Route & Blip Management
-- ----------------------------------------------------------------------------
local function clearFreightBlips()
    if activeBlip and DoesBlipExist(activeBlip) then
        RemoveBlip(activeBlip)
        activeBlip = nil
    end
    if activeRouteBlip and DoesBlipExist(activeRouteBlip) then
        RemoveBlip(activeRouteBlip)
        activeRouteBlip = nil
    end
end

local function setFreightDestination(coords, label)
    clearFreightBlips()
    if not coords then return end

    activeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(activeBlip, 477) -- Logistics cargo sprite
    SetBlipColour(activeBlip, 5)   -- Yellow
    SetBlipScale(activeBlip, 0.9)
    SetBlipRoute(activeBlip, true)
    SetBlipRouteColour(activeBlip, 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label or "Logisztikai Célállomás")
    EndTextCommandSetBlipName(activeBlip)

    SetNewWaypoint(coords.x, coords.y)
end

-- ----------------------------------------------------------------------------
-- 4. NUI Event Callbacks
-- ----------------------------------------------------------------------------
RegisterNUICallback("closeFreightBoard", function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "FREIGHT_BOARD_CLOSE" })
    cb({ success = true })
end)

RegisterNUICallback("claimFreightContract", function(payload, cb)
    local contractId = payload and payload.contractId
    if not contractId then return cb({ success = false, error = "INVALID_ID" }) end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:claimContract", contractId)
        if res and res.success then
            if res.destCoords then
                setFreightDestination(res.destCoords, "Áruszállítási Célállomás")
            elseif res.sourceCoords then
                setFreightDestination(res.sourceCoords, "Rakomány Felvételi Depó")
            end

            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "MEGBÍZÁS ELFOGADVA",
                message = "A fuvar lefoglalva. A GPS útvonal beállításra került."
            })
            cb(res)
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "MEGBÍZÁS HIBA",
                message = res and res.error or "Nem sikerült lefoglalni a megbízást."
            })
            cb(res or { success = false })
        end
    else
        cb({ success = false, error = "RPC_UNAVAILABLE" })
    end
end)

RegisterNUICallback("loadFreightPallet", function(payload, cb)
    local ped = PlayerPedId()
    local closeVeh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(closeVeh) then
        local pCoords = GetEntityCoords(ped)
        closeVeh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 8.0, 0, 71)
    end

    if not DoesEntityExist(closeVeh) then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "JÁRMŰ HIÁNYZIK",
            message = "Nem található tehergépjármű a rakodóállomás közelében!"
        })
        return cb({ success = false, error = "NO_VEHICLE_NEARBY" })
    end

    local netId = NetworkGetNetworkIdFromEntity(closeVeh)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:loadFreightPallet", {
            contractId = payload and payload.contractId,
            vehicleNetId = netId
        })
        cb(res or { success = false })
    end
end)

RegisterNUICallback("deliverFreightContract", function(payload, cb)
    local ped = PlayerPedId()
    local closeVeh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(closeVeh) then
        local pCoords = GetEntityCoords(ped)
        closeVeh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 8.0, 0, 71)
    end

    if not DoesEntityExist(closeVeh) then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "JÁRMŰ HIÁNYZIK",
            message = "Nem található a rakományt szállító tehergépjármű a lerakodónál!"
        })
        return cb({ success = false, error = "NO_VEHICLE_NEARBY" })
    end

    local netId = NetworkGetNetworkIdFromEntity(closeVeh)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:deliverContract", {
            contractId = payload and payload.contractId,
            vehicleNetId = netId
        })

        if res and res.success then
            clearFreightBlips()
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "FUVAR TELJESÍTVE",
                message = string.format("Sikeres leadás! Fuvardíj: $%.2f, Letét feloldva: $%.2f", res.payout, res.escrowRefunded)
            })
        end
        cb(res or { success = false })
    end
end)

-- Resource Cleanup
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearFreightBlips()
end)
