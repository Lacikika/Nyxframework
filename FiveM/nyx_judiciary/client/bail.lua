--[[
    Nyxframework: nyx_judiciary
    File: client/bail.lua
    Description: Client-side interaction with judicial bail kiosks, courtroom appearance
                 verification check-in, release conditions telemetry, and fugitive bounty claims.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

local myBailCache = nil
local activeBlips = {}

--- Find if local player is near any authorized bail terminal or kiosk
--- @param maxDist number|nil
--- @return boolean isNear, string|nil terminalId, number minDistance
function Nyx.Judiciary.IsNearBailKiosk(maxDist)
    local maxRadius = maxDist or 3.5
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local nearestTerm = nil
    local minDistance = 99999.0

    local terminals = Nyx.BailBonds and Nyx.BailBonds.TERMINALS or {}
    for termId, term in pairs(terminals) do
        if term.coords then
            local dist = #(pCoords - term.coords)
            if dist < minDistance then
                minDistance = dist
                if dist <= maxRadius then
                    nearestTerm = termId
                end
            end
        end
    end

    return (nearestTerm ~= nil), nearestTerm, minDistance
end

--- Query active bail status of local citizen from server
--- @return table|nil bailRecord
function Nyx.Judiciary.GetMyBailStatus()
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerClientRPC then
        return myBailCache
    end

    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerClientRPC("judiciary:getDefendantBailStatus")
    end)

    if ok and res then
        myBailCache = res
        return res
    end
    return myBailCache
end

-- Initialize map blips for bail kiosks and courtroom check-in terminals
local function createBailBlips()
    local terminals = Nyx.BailBonds and Nyx.BailBonds.TERMINALS or {}
    for termId, term in pairs(terminals) do
        if term.coords then
            local blip = AddBlipForCoord(term.coords.x, term.coords.y, term.coords.z)
            SetBlipSprite(blip, term.type == "courtroom" and 408 or 498)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, 0.75)
            SetBlipColour(blip, term.type == "courtroom" and 3 or 5)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(term.label or "Óvadék Terminál (Bail Kiosk)")
            EndTextCommandSetBlipName(blip)
            activeBlips[#activeBlips + 1] = blip
        end
    end
end

-- Network event listener: Live bail status change notification
RegisterNetEvent("nyx:judiciary:client:bailStatusChanged", function(data)
    if not data then return end
    myBailCache = data

    local badge = Nyx.BailBonds and Nyx.BailBonds.FormatStatusBadge and Nyx.BailBonds.FormatStatusBadge(data.status, data.bondType or "cash")
    local statusText = badge and badge.label or tostring(data.status)

    if exports['nyx_core'] and exports['nyx_core'].ShowNotification then
        exports['nyx_core']:ShowNotification(string.format("Óvadék státusz frissítve: %s (Ügyszám: %s)", statusText, tostring(data.docketId)), "info")
    else
        TriggerEvent("chat:addMessage", {
            color = { 255, 204, 0 },
            multiline = true,
            args = { "[Bail System]", string.format("Óvadék státusz: %s (Ügy: %s)", statusText, tostring(data.docketId)) }
        })
    end
end)

-- Command: /bailstatus [targetCitizenId]
RegisterCommand("bailstatus", function(source, args)
    local targetCitId = args[1]
    local res = exports['nyx_core']:TriggerClientRPC("judiciary:getDefendantBailStatus", targetCitId)

    if not res then
        TriggerEvent("chat:addMessage", {
            color = { 200, 200, 200 },
            multiline = true,
            args = { "[Bail]", "Nincs aktív óvadéki nyilvántartás ehhez a személyhez." }
        })
        return
    end

    local badge = Nyx.BailBonds and Nyx.BailBonds.FormatStatusBadge and Nyx.BailBonds.FormatStatusBadge(res.status, res.bond_type or "cash")
    local statusLabel = badge and badge.label or res.status
    local amount = tonumber(res.bail_amount) or 0.00
    local docketId = res.docket_id or "N/A"
    local appChecked = (tonumber(res.court_appearance_verified) == 1) and "^2IGAZOLVA^7" or "^1HIÁNYZIK^7"

    TriggerEvent("chat:addMessage", {
        color = { 255, 255, 255 },
        multiline = true,
        args = { "[Bail Registry]", string.format("Ügy: ^3%s^7 | Összeg: ^2$%.2f^7 | Típus: ^3%s^7 | Státusz: %s | Bírósági jelenlét: %s",
            docketId, amount, res.bond_type or "cash", statusLabel, appChecked) }
    })
end, false)

-- Command: /postbail <docketId> [cash|surety]
RegisterCommand("postbail", function(source, args)
    local isNear, termId, dist = Nyx.Judiciary.IsNearBailKiosk(4.0)
    if not isNear then
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Bail]", string.format("Nem vagy óvadékterminál közelében (legközelebbi: %.1fm). Keresd fel a Bíróságot vagy a Rendőrséget!", dist) }
        })
        return
    end

    local docketId = args[1]
    local bondType = args[2] or "cash"

    if not docketId then
        TriggerEvent("chat:addMessage", {
            color = { 255, 200, 50 },
            multiline = true,
            args = { "[Bail]", "Használat: /postbail <docketId> [cash|surety]" }
        })
        return
    end

    local ok, res = exports['nyx_core']:TriggerClientRPC("judiciary:postBail", docketId, bondType)
    if ok and res then
        TriggerEvent("chat:addMessage", {
            color = { 50, 255, 100 },
            multiline = true,
            args = { "[Bail]", string.format("Óvadék sikeresen letétbe helyezve! Ügy: %s, Összeg: $%.2f (%s)", docketId, tonumber(res.bailAmount) or 0.0, bondType) }
        })
    else
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Bail]", string.format("Óvadék letét elutasítva: %s", tostring(res)) }
        })
    end
end, false)

-- Command: /bailcheckin <docketId>
RegisterCommand("bailcheckin", function(source, args)
    local docketId = args[1]
    if not docketId then
        TriggerEvent("chat:addMessage", {
            color = { 255, 200, 50 },
            multiline = true,
            args = { "[Bail]", "Használat: /bailcheckin <docketId>" }
        })
        return
    end

    local ok, res = exports['nyx_core']:TriggerClientRPC("judiciary:checkinCourtAppearance", docketId)
    if ok and res and res.appearanceVerified then
        TriggerEvent("chat:addMessage", {
            color = { 50, 255, 100 },
            multiline = true,
            args = { "[Bail]", string.format("Bírósági jelenléted sikeresen regisztrálva a tárgyalásra! (Ügy: %s)", docketId) }
        })
    else
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Bail]", string.format("Bírósági jelenlét igazolása sikertelen: %s", tostring(res)) }
        })
    end
end, false)

-- Third-Eye spatial interaction targets
local function registerInteractTargets()
    if not exports['nyx_interact'] or not exports['nyx_interact'].AddTargetModel then
        return
    end

    local terminals = Nyx.BailBonds and Nyx.BailBonds.TERMINALS or {}
    for termId, term in pairs(terminals) do
        if term.coords then
            exports['nyx_interact']:AddTargetPoint({
                id = "bail_terminal_" .. termId,
                coords = term.coords,
                radius = 2.5,
                options = {
                    {
                        label = "Óvadék Nyilvántartás & Letét (Bail Kiosk)",
                        icon = "fas fa-balance-scale",
                        action = function()
                            ExecuteCommand("bailstatus")
                        end
                    },
                    {
                        label = "Tárgyalási Jelenlét Igazolása (Check-In)",
                        icon = "fas fa-clipboard-check",
                        action = function()
                            TriggerEvent("chat:addMessage", {
                                color = { 255, 200, 50 },
                                args = { "[Bail]", "Add meg a bírósági ügyszámot: /bailcheckin <docketId>" }
                            })
                        end
                    }
                }
            })
        end
    end
end

-- Lifecycle Thread
CreateThread(function()
    createBailBlips()
    registerInteractTargets()
end)

-- Teardown
AddEventHandler("onResourceStop", function(resName)
    if resName ~= GetCurrentResourceName() then return end
    for _, blip in ipairs(activeBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    activeBlips = {}
end)
