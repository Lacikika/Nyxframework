--[[
    Nyxframework: nyx_judiciary
    File: client/penal_labor.lua
    Description: Client-side interaction with Bolingbroke penitentiary work benches,
                 work animations, sentence telemetry, and discharge notifications.
]]

local isWorking = false
local cachedOverview = nil

--- Helper: Find the nearest penal workstation to local player ped
--- @return table|nil workstation, number distance
local function GetNearestWorkstation()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local nearest = nil
    local minDistance = 99999.0

    local workstations = Nyx.PenalLabor and Nyx.PenalLabor.GetAllWorkstations and Nyx.PenalLabor.GetAllWorkstations() or {}
    for _, ws in pairs(workstations) do
        if ws.coords then
            local dist = #(pCoords - ws.coords)
            if dist < minDistance then
                minDistance = dist
                nearest = ws
            end
        end
    end

    return nearest, minDistance
end

--- Play work animation with safety cancellation checks
--- @param animDict string
--- @param animName string
--- @param durationMs number
--- @return boolean completed
local function PlayWorkAnimation(animDict, animName, durationMs)
    local ped = PlayerPedId()

    RequestAnimDict(animDict)
    local timeout = 0
    while not HasAnimDictLoaded(animDict) and timeout < 50 do
        Wait(50)
        timeout = timeout + 1
    end

    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, durationMs, 1, 0, false, false, false)

    local elapsed = 0
    while elapsed < durationMs do
        Wait(500)
        elapsed = elapsed + 500
        if IsEntityDead(ped) then
            ClearPedTasks(ped)
            return false
        end
    end

    ClearPedTasks(ped)
    return true
end

--- Execute penal labor cycle command
RegisterCommand("penallabor", function(source, args)
    if isWorking then
        TriggerEvent("chat:addMessage", {
            color = { 239, 68, 68 },
            multiline = true,
            args = { "[Börtönmunka]", "Már folyamatban van egy munkaciklus!" }
        })
        return
    end

    local ws, dist = GetNearestWorkstation()
    if not ws or dist > ((ws.radius or 2.5) + 3.0) then
        TriggerEvent("chat:addMessage", {
            color = { 239, 68, 68 },
            multiline = true,
            args = { "[Börtönmunka]", "Nem tartózkodsz egyetlen bolingbroke-i munkaállomás közelében sem!" }
        })
        return
    end

    -- Determine target recipe
    local requestedRecipe = args[1]
    local targetRecipeId = nil

    if requestedRecipe and Nyx.PenalLabor.IsRecipeAllowedAtWorkstation(requestedRecipe, ws.id) then
        targetRecipeId = requestedRecipe
    else
        -- Pick the first allowed recipe for this workstation
        for recId, _ in pairs(ws.allowedRecipes or {}) do
            targetRecipeId = recId
            break
        end
    end

    if not targetRecipeId then
        TriggerEvent("chat:addMessage", {
            color = { 239, 68, 68 },
            multiline = true,
            args = { "[Börtönmunka]", "Ehhez a munkaállomáshoz nincs elérhető gyártási recept." }
        })
        return
    end

    local recipe = Nyx.PenalLabor.GetRecipe(targetRecipeId)
    local durationSec = recipe and recipe.durationSeconds or 15

    isWorking = true
    TriggerEvent("chat:addMessage", {
        color = { 59, 130, 246 },
        multiline = true,
        args = { "[Börtönmunka]", string.format("Munkaciklus megkezdése: %s (%d másodperc)...", recipe.label or targetRecipeId, durationSec) }
    })

    -- Play workstation animation
    local animDict = ws.animDict or "mini@repair"
    local animName = ws.anim or "fixing_a_ped"
    local completedAnim = PlayWorkAnimation(animDict, animName, durationSec * 1000)

    if not completedAnim then
        isWorking = false
        TriggerEvent("chat:addMessage", {
            color = { 239, 68, 68 },
            multiline = true,
            args = { "[Börtönmunka]", "A munka megszakadt." }
        })
        return
    end

    -- Submit authoritative labor execution to server RPC
    local payload = {
        workstationId = ws.id,
        recipeId = targetRecipeId,
        batchMultiplier = 1
    }

    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPC("judiciary:executePenalLabor", payload)
    end)

    isWorking = false

    if ok and res and res.success then
        TriggerEvent("chat:addMessage", {
            color = { 16, 185, 129 },
            multiline = true,
            args = {
                "[Börtönmunka]",
                string.format("Ciklus kész! Büntetés csökkentve: -%d hónap. Hátralévő: %d hónap. Közcélú alap jóváírás: $%.2f.",
                    res.reducedMonths or 0,
                    res.remainingMonths or 0,
                    res.civicFundsGenerated or 0.00)
            }
        })

        if res.isDischarged then
            TriggerEvent("chat:addMessage", {
                color = { 16, 185, 129 },
                multiline = true,
                args = { "[Börtön Igazgatóság]", "A teljes szabadságvesztési büntetést letöltötted! Hivatalosan szabadlábra helyeztek." }
            })
        end
    else
        local errMsg = (res and res.error) or "Ismeretlen hiba történt a munkavégzés során."
        if errMsg == "INSUFFICIENT_MATERIALS" then
            errMsg = string.format("Nincs elegendő alapanyag a műhelyraktárban (%s: szükséges %d, elérhető %d).",
                tostring(res.missingItem), tonumber(res.needed) or 0, tonumber(res.have) or 0)
        elseif errMsg == "NOT_INCARCERATED" then
            errMsg = "Nem vagy jogerősen elítélt fegyenc a Bolingbroke Büntetés-végrehajtási Intézetben."
        elseif errMsg == "SENTENCE_EXPIRED" then
            errMsg = "A büntetésed már lejárt. Használd a /szabadulas parancsot a távozáshoz."
        end

        TriggerEvent("chat:addMessage", {
            color = { 239, 68, 68 },
            multiline = true,
            args = { "[Börtönmunka Hiba]", errMsg }
        })
    end
end, false)

-- Hungarian & English command aliases
RegisterKeyMapping('penallabor', 'Bolingbroke Börtönmunka Megkezdése', 'keyboard', '')
RegisterCommand("labor", function(src, args) ExecuteCommand("penallabor " .. table.concat(args, " ")) end, false)
RegisterCommand("bortonmunka", function(src, args) ExecuteCommand("penallabor " .. table.concat(args, " ")) end, false)

--- Check inmate custodial status command
RegisterCommand("penalstatus", function()
    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPC("judiciary:getPenalOverview")
    end)

    if ok and res and res.success then
        cachedOverview = res
        local rec = res.penalRecord
        if rec then
            TriggerEvent("chat:addMessage", {
                color = { 245, 158, 11 },
                multiline = true,
                args = {
                    "[Büntetés Állapot]",
                    string.format("Státusz: %s | Eredeti: %d hó | Hátralévő: %d hó | Ledolgozott: %d ciklus (-%d hó) | Megtermelt érték: $%.2f",
                        string.upper(rec.status or "ismeretlen"),
                        rec.original_sentence_months or 0,
                        rec.current_sentence_months or 0,
                        rec.labor_cycles_completed or 0,
                        rec.total_reduction_months or 0,
                        tonumber(rec.total_civic_value_generated) or 0.00)
                }
            })
        else
            TriggerEvent("chat:addMessage", {
                color = { 107, 114, 128 },
                multiline = true,
                args = { "[Büntetés Állapot]", "Nincs aktív büntetés-végrehajtási nyilvántartásod." }
            })
        end
    else
        TriggerEvent("chat:addMessage", {
            color = { 239, 68, 68 },
            multiline = true,
            args = { "[Büntetés Állapot]", "Nem sikerült lekérdezni a büntetés-végrehajtási adatokat." }
        })
    end
end, false)

RegisterCommand("sentence", function() ExecuteCommand("penalstatus") end, false)
RegisterCommand("buntetes", function() ExecuteCommand("penalstatus") end, false)

--- Request discharge when sentence reaches 0
RegisterCommand("requestrelease", function()
    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPC("judiciary:requestPenalRelease")
    end)

    if ok and res and res.success then
        TriggerEvent("chat:addMessage", {
            color = { 16, 185, 129 },
            multiline = true,
            args = { "[Börtön Igazgatóság]", "A szabadlábra helyezési kérelem jóváhagyva. Távozhatsz a létesítményből." }
        })
    else
        local err = (res and res.error) or "Nem sikerült a szabadlábra helyezés."
        if err == "SENTENCE_NOT_COMPLETED" then
            err = string.format("Még %d hónap büntetésed van hátra. Folytasd a munkát a büntetés csökkentéséhez!", tonumber(res.remaining) or 0)
        end
        TriggerEvent("chat:addMessage", {
            color = { 239, 68, 68 },
            multiline = true,
            args = { "[Szabadulás Hiba]", err }
        })
    end
end, false)

RegisterCommand("szabadulas", function() ExecuteCommand("requestrelease") end, false)

--- Event: Inmate officially released
RegisterNetEvent("nyx:judiciary:client:released", function(data)
    PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
    TriggerEvent("chat:addMessage", {
        color = { 16, 185, 129 },
        multiline = true,
        args = { "[Bolingbroke Állami Fegyház]", data.message or "Hivatalosan szabadlábra helyeztek. Tiszta lappal távozhatsz." }
    })
end)

--- Event: Workshop stock updated
RegisterNetEvent("nyx:judiciary:client:workshopStockUpdated", function(data)
    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Workshop stock updated: %s (+%d)^7", tostring(data.itemId), tonumber(data.quantity) or 0))
    end
end)

-- ----------------------------------------------------------------------------
-- Client Public API Exports
-- ----------------------------------------------------------------------------
exports("GetNearestPenalWorkstation", function()
    return GetNearestWorkstation()
end)

exports("IsPerformingLabor", function()
    return isWorking
end)

exports("GetCachedPenalOverview", function()
    return cachedOverview
end)
