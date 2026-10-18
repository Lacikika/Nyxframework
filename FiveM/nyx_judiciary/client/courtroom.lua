--[[
    Nyxframework: nyx_judiciary
    File: client/courtroom.lua
    Description: Courtroom spatial anchors, seating kinematics, Third-Eye (LALT) integration,
                 isolated deliberation voting, and virtual routing transitions.
]]

local isSeated = false
local currentSeatIndex = nil
local activeSummonedDocket = nil
local isInDeliberation = false

-- Courtroom Seating Positions
local CourtSeats = {
    { id = "judge", label = "Judge's Bench", coords = vector4(-545.2, -203.8, 38.2, 210.0) },
    { id = "witness", label = "Witness Stand", coords = vector4(-542.5, -204.5, 38.2, 120.0) },
    { id = "prosecution", label = "Prosecution Counsel", coords = vector4(-548.5, -200.5, 38.2, 30.0) },
    { id = "defense", label = "Defense Counsel", coords = vector4(-542.0, -200.5, 38.2, 30.0) },
    { id = "jury_1", label = "Jury Seat 1", seatIndex = 1, coords = vector4(-551.5, -204.0, 38.2, 120.0) },
    { id = "jury_2", label = "Jury Seat 2", seatIndex = 2, coords = vector4(-551.5, -205.5, 38.2, 120.0) },
    { id = "jury_3", label = "Jury Seat 3", seatIndex = 3, coords = vector4(-551.5, -207.0, 38.2, 120.0) },
    { id = "jury_4", label = "Jury Seat 4", seatIndex = 4, coords = vector4(-553.0, -204.0, 38.2, 120.0) },
    { id = "jury_5", label = "Jury Seat 5", seatIndex = 5, coords = vector4(-553.0, -205.5, 38.2, 120.0) },
    { id = "jury_6", label = "Jury Seat 6", seatIndex = 6, coords = vector4(-553.0, -207.0, 38.2, 120.0) }
}

-- ----------------------------------------------------------------------------
-- 1. Civic Jury Summons Route Handler
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:judiciary:client:jurySummons", function(data)
    activeSummonedDocket = data.docketId
    local courtCenter = Config.Courtroom and Config.Courtroom.InteriorCenter or vector3(-545.2, -203.8, 38.2)

    -- Set GPS Waypoint for citizen
    SetNewWaypoint(courtCenter.x, courtCenter.y)

    if exports['nyx_ui'] then
        exports['nyx_ui']:Notify({
            type = "warning",
            title = "JURY DUTY SUMMONS",
            message = string.format("Report to District Court within %d seconds to check-in for Case %s.",
                data.timeoutSeconds or 180, data.docketId)
        })
    end
end)

-- ----------------------------------------------------------------------------
-- 2. Register Courtroom Benches & Chairs with Third-Eye (LALT) Raycast Engine
-- ----------------------------------------------------------------------------
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for idx, seat in ipairs(CourtSeats) do
        local options = {
            {
                icon = "fa-solid fa-chair",
                label = "Take " .. (seat.label or "Court Seat"),
                event = "nyx:judiciary:client:sitChair",
                args = { seat = seat },
                canInteract = function(entity, dist)
                    return dist <= 1.8 and not isSeated
                end
            }
        }

        -- Add dedicated Third-Eye check-in option on jury seats for summoned citizens
        if seat.seatIndex then
            table.insert(options, {
                icon = "fa-solid fa-scale-balanced",
                label = string.format("Check-in & Take %s", seat.label),
                event = "nyx:judiciary:client:checkInJurySeat",
                args = { seat = seat },
                canInteract = function(entity, dist)
                    return dist <= 1.8 and not isSeated and (activeSummonedDocket ~= nil)
                end
            })
        end

        exports['nyx_interact']:AddTargetCoords("court_seat_" .. seat.id, seat.coords, 1.8, {
            options = options,
            distance = 1.8
        })
    end
end)

-- Event hook to check in and seat as juror
RegisterNetEvent("nyx:judiciary:client:checkInJurySeat", function(args)
    local seat = (type(args) == "table" and args.seat) or args
    if not seat or not activeSummonedDocket then return end

    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:seatJuror", {
            docketId = activeSummonedDocket,
            seatIndex = seat.seatIndex
        }, function(res)
            if res and res.success then
                TriggerEvent("nyx:judiciary:client:sitChair", { seat = seat })
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "success",
                        title = "JUROR CHECKED IN",
                        message = string.format("Seated as Juror #%d for Case %s.", seat.seatIndex, activeSummonedDocket)
                    })
                end
            else
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "error",
                        title = "CHECK-IN REJECTED",
                        message = res and res.error or "Could not seat as juror."
                    })
                end
            end
        end)
    end
end)

-- Event hook to sit in a courtroom chair
RegisterNetEvent("nyx:judiciary:client:sitChair", function(args)
    local seat = (type(args) == "table" and args.seat) or args
    if not seat or not seat.coords then return end

    local ped = PlayerPedId()
    isSeated = true
    currentSeatIndex = seat.id
    SetEntityCoords(ped, seat.coords.x, seat.coords.y, seat.coords.z - 0.95, false, false, false, true)
    SetEntityHeading(ped, seat.coords.w)
    TaskStartScenarioInPlace(ped, "PROP_HUMAN_SEAT_CHAIR_MP_PLAYER", 0, true)
end)

-- ----------------------------------------------------------------------------
-- 3. Trial Lifecycle Client Hooks & Bucket Transition Handlers
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:judiciary:client:jurorSeated", function(data)
    if data and data.seatCoords then
        local ped = PlayerPedId()
        isSeated = true
        currentSeatIndex = "jury_" .. tostring(data.seatIndex)
        SetEntityCoords(ped, data.seatCoords.x, data.seatCoords.y, data.seatCoords.z - 0.95, false, false, false, true)
        SetEntityHeading(ped, data.seatCoords.w)
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_SEAT_CHAIR_MP_PLAYER", 0, true)
    end
end)

RegisterNetEvent("nyx:judiciary:client:trialSessionEnter", function(data)
    if data and data.coords then
        local ped = PlayerPedId()
        SetEntityCoords(ped, data.coords.x, data.coords.y, data.coords.z - 0.95, false, false, false, true)
        SetEntityHeading(ped, data.coords.w or 0.0)
        isSeated = true
        currentSeatIndex = data.role
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_SEAT_CHAIR_MP_PLAYER", 0, true)
    end

    if exports['nyx_ui'] then
        exports['nyx_ui']:Notify({
            type = "info",
            title = "COURT IN SESSION",
            message = string.format("Case %s is now being heard. Role: %s.", data.docketId, string.upper(data.role or "attendee"))
        })
    end
end)

RegisterNetEvent("nyx:judiciary:client:enterDeliberation", function(data)
    isInDeliberation = true
    isSeated = false
    ClearPedTasksImmediately(PlayerPedId())

    if data and data.chamberCoords then
        local ped = PlayerPedId()
        SetEntityCoords(ped, data.chamberCoords.x, data.chamberCoords.y, data.chamberCoords.z, false, false, false, true)
        SetEntityHeading(ped, data.chamberCoords.w or 0.0)
    end

    if exports['nyx_ui'] then
        exports['nyx_ui']:Notify({
            type = "warning",
            title = "JURY DELIBERATION",
            message = "You are in private deliberation. Cast your secret ballot using /juryvote [guilty|not_guilty|abstain] or keys 1/2/3."
        })
    end
end)

RegisterNetEvent("nyx:judiciary:client:exitDeliberation", function(data)
    isInDeliberation = false

    if data and data.seatCoords then
        local ped = PlayerPedId()
        isSeated = true
        currentSeatIndex = "jury_" .. tostring(data.seatIndex or 1)
        SetEntityCoords(ped, data.seatCoords.x, data.seatCoords.y, data.seatCoords.z - 0.95, false, false, false, true)
        SetEntityHeading(ped, data.seatCoords.w)
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_SEAT_CHAIR_MP_PLAYER", 0, true)
    end

    if exports['nyx_ui'] then
        exports['nyx_ui']:Notify({
            type = "info",
            title = "VERDICT REACHED",
            message = "Deliberations have concluded. Returning to the courtroom for verdict delivery."
        })
    end
end)

RegisterNetEvent("nyx:judiciary:client:juryServiceConcluded", function(data)
    isSeated = false
    isInDeliberation = false
    activeSummonedDocket = nil
    currentSeatIndex = nil
    ClearPedTasksImmediately(PlayerPedId())

    if exports['nyx_ui'] then
        exports['nyx_ui']:Notify({
            type = "success",
            title = "JURY SERVICE COMPLETE",
            message = string.format("Your civic service is complete. A stipend of $%.2f has been credited to your account.",
                data.stipend or 500.0)
        })
    end
end)

-- ----------------------------------------------------------------------------
-- 4. Deliberation Voting Command (/juryvote)
-- ----------------------------------------------------------------------------
RegisterCommand("juryvote", function(source, args)
    local vote = args[1] and string.lower(args[1])
    if vote ~= "guilty" and vote ~= "not_guilty" and vote ~= "abstain" then
        if exports['nyx_ui'] then
            exports['nyx_ui']:Notify({
                type = "error",
                title = "INVALID VOTE",
                message = "Usage: /juryvote [guilty | not_guilty | abstain]"
            })
        end
        return
    end

    local docketId = activeSummonedDocket or (Player and LocalPlayer and LocalPlayer.state and LocalPlayer.state.courtroomDocket)
    if not docketId then
        if exports['nyx_ui'] then
            exports['nyx_ui']:Notify({
                type = "error",
                title = "NOT ON JURY",
                message = "You are not an active juror on a pending docket."
            })
        end
        return
    end

    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:castJuryVote", docketId, vote, function(res)
            if res and res.success then
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "success",
                        title = "BALLOT CAST",
                        message = string.format("Your secret vote of '%s' has been recorded.", string.upper(vote))
                    })
                end
            else
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "error",
                        title = "VOTE REJECTED",
                        message = res and res.error or "Failed to record vote."
                    })
                end
            end
        end)
    end
end, false)

-- ----------------------------------------------------------------------------
-- 5. Main Courtroom Seated State Thread (Sleeps 1000ms idle, runs only when seated)
-- ----------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and isSeated then
            sleep = 0
            local exitPrompt = "[~r~X~w~] Stand Up"
            local docketId = activeSummonedDocket or (Player and LocalPlayer and LocalPlayer.state and LocalPlayer.state.courtroomDocket)

            if (isInDeliberation or (currentSeatIndex and string.sub(currentSeatIndex, 1, 4) == "jury")) and docketId then
                exitPrompt = exitPrompt .. " | [~y~1~w~] Vote Guilty | [~b~2~w~] Not Guilty | [~w~3~w~] Abstain"

                -- Deliberation Voting Keys
                if IsControlJustPressed(0, 157) then -- 1 Key: Guilty
                    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                        exports['nyx_core']:TriggerServerRPC("judiciary:castJuryVote", docketId, "guilty")
                    end
                    Wait(500)
                elseif IsControlJustPressed(0, 158) then -- 2 Key: Not Guilty
                    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                        exports['nyx_core']:TriggerServerRPC("judiciary:castJuryVote", docketId, "not_guilty")
                    end
                    Wait(500)
                elseif IsControlJustPressed(0, 160) then -- 3 Key: Abstain
                    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                        exports['nyx_core']:TriggerServerRPC("judiciary:castJuryVote", docketId, "abstain")
                    end
                    Wait(500)
                end
            end

            local pCoords = GetEntityCoords(ped)
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName(exitPrompt)
            SetTextFont(0)
            SetTextScale(0.32, 0.32)
            SetTextColour(255, 255, 255, 220)
            SetTextCentre(true)

            SetDrawOrigin(pCoords.x, pCoords.y, pCoords.z + 0.3, 0)
            EndTextCommandDisplayText(0.0, 0.0)
            ClearDrawOrigin()

            if IsControlJustPressed(0, 73) then -- X key: Stand
                isSeated = false
                currentSeatIndex = nil
                ClearPedTasksImmediately(ped)
                Wait(500)
            end
        end

        Wait(sleep)
    end
end)

-- ----------------------------------------------------------------------------
-- 6. Judicial Warrant & Subpoena Registry Commands & Third-Eye Hooks
-- ----------------------------------------------------------------------------

-- Register Third-Eye Target at Courthouse Clerk / Judge Chambers
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(300)
    end

    local registryCoords = vector3(-540.8, -198.2, 38.2)
    exports['nyx_interact']:AddTargetCoords("court_warrant_registry", registryCoords, 2.5, {
        options = {
            {
                icon = "fa-solid fa-scale-balanced",
                label = "Courtroom Terminal & Forensic Explorer",
                event = "nyx:judiciary:client:openCourtTerminal",
                canInteract = function(entity, dist)
                    return dist <= 2.5
                end
            },
            {
                icon = "fa-solid fa-file-contract",
                label = "Warrant & Subpoena Petition Registry",
                event = "nyx:judiciary:client:openWarrantRegistry",
                canInteract = function(entity, dist)
                    return dist <= 2.5
                end
            }
        },
        distance = 2.5
    })
end)

RegisterNetEvent("nyx:judiciary:client:openWarrantRegistry", function()
    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:getPendingPetitions", function(res)
            if res and res.success and res.petitions then
                local count = #res.petitions
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "info",
                        title = "BÍRÓI PARANCS REGISZTER",
                        message = string.format("Függőben lévő kérvények: %d db. Használd a /reviewpetition parancsot az elbíráláshoz.", count)
                    })
                end
            else
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "error",
                        title = "HOZZÁFÉRÉS ELUTASÍTVA",
                        message = res and res.error or "Nincs jogosultságod a bírói kérvények megtekintésére."
                    })
                end
            end
        end)
    end
end)

-- Command: /petitionwarrant <targetCitId> <type> <hours> <probable cause narrative>
RegisterCommand("petitionwarrant", function(source, args)
    if #args < 4 then
        if exports['nyx_ui'] then
            exports['nyx_ui']:Notify({
                type = "error",
                title = "HIÁNYZÓ ADATOK",
                message = "Használat: /petitionwarrant [citizenId] [arrest|search_property|search_vehicle|subpoena|wiretap] [hours] [indoklás...]"
            })
        end
        return
    end

    local targetCitId = args[1]
    local warrantType = args[2]:lower()
    local hours = tonumber(args[3]) or 72
    local causeWords = {}
    for i = 4, #args do
        table.insert(causeWords, args[i])
    end
    local causeSummary = table.concat(causeWords, " ")

    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:petitionWarrant", {
            targetCitizenId = targetCitId,
            warrantType = warrantType,
            requestedDurationHours = hours,
            probableCauseSummary = causeSummary
        }, function(res)
            if res and res.success then
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "success",
                        title = "KÉRVÉNY BENYÚJTVA",
                        message = string.format("Kérvény azonosító: %s. A bírói tanács értesítve lett.", res.petition.petitionId)
                    })
                end
            else
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "error",
                        title = "KÉRVÉNY ELUTASÍTVA",
                        message = res and res.error or "Hiba történt a kérvény benyújtásakor."
                    })
                end
            end
        end)
    end
end, false)

-- Command: /reviewpetition <petitionId> <approve|reject> [notes]
RegisterCommand("reviewpetition", function(source, args)
    if #args < 2 then
        if exports['nyx_ui'] then
            exports['nyx_ui']:Notify({
                type = "error",
                title = "HIÁNYZÓ ADATOK",
                message = "Használat: /reviewpetition [petitionId] [approve | reject] [indoklás...]"
            })
        end
        return
    end

    local petitionId = args[1]
    local decision = (args[2]:lower() == "approve" or args[2]:lower() == "approved") and "approved" or "rejected"
    local noteWords = {}
    for i = 3, #args do
        table.insert(noteWords, args[i])
    end
    local notes = #noteWords > 0 and table.concat(noteWords, " ") or nil

    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:reviewPetition", {
            petitionId = petitionId,
            decision = decision,
            reviewNotes = notes
        }, function(res)
            if res and res.success then
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "success",
                        title = "BÍRÓI DÖNTÉS RÖGZÍTVE",
                        message = string.format("Kérvény %s elbírálva: %s", petitionId, string.upper(decision))
                    })
                end
            else
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "error",
                        title = "HIBA AZ ELBÍRÁLÁSKOR",
                        message = res and res.error or "Nem sikerült elbírálni a kérvényt."
                    })
                end
            end
        end)
    end
end, false)

-- Command: /subpoenarecords <targetCitizenId>
RegisterCommand("subpoenarecords", function(source, args)
    if #args < 1 then
        if exports['nyx_ui'] then
            exports['nyx_ui']:Notify({
                type = "error",
                title = "HIÁNYZÓ ADAT",
                message = "Használat: /subpoenarecords [citizenId]"
            })
        end
        return
    end

    local targetCitId = args[1]
    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:getSubpoenaRecords", targetCitId, function(res)
            if res and res.success and res.records then
                local rec = res.records
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "success",
                        title = "IDÉZÉS HITELT ÉRDEMLŐ",
                        message = string.format("Bank: $%.2f | Tranzakciók: %d db | Ingatlanok: %d db | Részvények: %d db",
                            rec.accountBalance and rec.accountBalance.bank or 0.0,
                            rec.transactions and #rec.transactions or 0,
                            rec.properties and #rec.properties or 0,
                            rec.corporateShares and #rec.corporateShares or 0)
                    })
                end
            else
                if exports['nyx_ui'] then
                    exports['nyx_ui']:Notify({
                        type = "error",
                        title = "HOZZÁFÉRÉS MEGTAGADVA",
                        message = res and res.error or "Nincs aktív jóváhagyott idézési parancs ehhez a személyhez."
                    })
                end
            end
        end)
    end
end, false)

-- ----------------------------------------------------------------------------
-- 7. Visual Courtroom Terminal UI Dispatcher & Chat Commands
-- ----------------------------------------------------------------------------
function OpenCourtTerminal(activeTab)
    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:getCourtOverview", function(res)
            local overviewData = (res and res.success and res.overview) or {}
            overviewData.activeTab = activeTab or "evidence"

            if exports['nyx_ui'] and exports['nyx_ui'].OpenCourtTerminal then
                exports['nyx_ui']:OpenCourtTerminal(overviewData)
            elseif exports['nyx_ui'] and exports['nyx_ui'].Send then
                exports['nyx_ui']:SetFocus(true, true)
                exports['nyx_ui']:Send("court", "COURT_TERMINAL_OPEN", overviewData)
            end
        end)
    else
        if exports['nyx_ui'] and exports['nyx_ui'].OpenCourtTerminal then
            exports['nyx_ui']:OpenCourtTerminal({ activeTab = activeTab or "evidence" })
        end
    end
end

RegisterNetEvent("nyx:judiciary:client:openCourtTerminal", function(data)
    local tab = type(data) == "table" and data.activeTab or data
    OpenCourtTerminal(tab)
end)

RegisterCommand("courtroom", function(source, args)
    local tab = args[1] and string.lower(args[1]) or "evidence"
    OpenCourtTerminal(tab)
end, false)

RegisterCommand("court", function(source, args)
    local tab = args[1] and string.lower(args[1]) or "evidence"
    OpenCourtTerminal(tab)
end, false)

RegisterCommand("judiciary", function(source, args)
    local tab = args[1] and string.lower(args[1]) or "evidence"
    OpenCourtTerminal(tab)
end, false)
