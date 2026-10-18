--[[
    Nyxframework: nyx_judiciary
    File: client/courtroom.lua
    Description: Courtroom spatial anchors, seating kinematics, jury box interactions,
                 and deliberation secret balloting interface.
]]

local isSeated = false
local currentSeatIndex = nil
local activeSummonedDocket = nil

-- Courtroom Seating Positions
local CourtSeats = {
    { id = "judge", label = "Judge's Bench", coords = vector4(-545.2, -203.8, 38.2, 210.0) },
    { id = "witness", label = "Witness Stand", coords = vector4(-542.5, -204.5, 38.2, 120.0) },
    { id = "prosecution", label = "Prosecution Counsel", coords = vector4(-548.5, -200.5, 38.2, 30.0) },
    { id = "defense", label = "Defense Counsel", coords = vector4(-542.0, -200.5, 38.2, 30.0) },
    { id = "jury_1", label = "Jury Seat 1", coords = vector4(-551.5, -204.0, 38.2, 120.0) },
    { id = "jury_2", label = "Jury Seat 2", coords = vector4(-551.5, -205.5, 38.2, 120.0) },
    { id = "jury_3", label = "Jury Seat 3", coords = vector4(-551.5, -207.0, 38.2, 120.0) },
    { id = "jury_4", label = "Jury Seat 4", coords = vector4(-553.0, -204.0, 38.2, 120.0) },
    { id = "jury_5", label = "Jury Seat 5", coords = vector4(-553.0, -205.5, 38.2, 120.0) },
    { id = "jury_6", label = "Jury Seat 6", coords = vector4(-553.0, -207.0, 38.2, 120.0) }
}

-- Handle Civic Jury Summons Route
RegisterNetEvent("nyx:judiciary:client:jurySummons", function(data)
    activeSummonedDocket = data.docketId
    local courtCenter = Config.Courtroom and Config.Courtroom.InteriorCenter or vector3(-545.2, -203.8, 38.2)

    -- Set GPS Waypoint for citizen
    SetNewWaypoint(courtCenter.x, courtCenter.y)

    if exports['nyx_ui'] then
        exports['nyx_ui']:Notify({
            type = "info",
            title = "COURT GPS ACTIVE",
            message = "Waypoint set to San Andreas District Courthouse for jury duty."
        })
    end
end)

-- Main Courtroom Spatial Thread (Tick rate: 1000ms idle, 0ms when at interactive bench)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)
            local courtCenter = Config.Courtroom and Config.Courtroom.InteriorCenter or vector3(-545.2, -203.8, 38.2)
            local distToCourt = #(pCoords - courtCenter)

            if distToCourt < 50.0 then
                sleep = 250
                local nearestSeat = nil
                local nearestDist = 999.0

                for i, seat in ipairs(CourtSeats) do
                    local seatVec = vector3(seat.coords.x, seat.coords.y, seat.coords.z)
                    local d = #(pCoords - seatVec)
                    if d < nearestDist then
                        nearestDist = d
                        nearestSeat = seat
                    end
                end

                if nearestSeat and nearestDist < 2.0 then
                    sleep = 0

                    if not isSeated then
                        BeginTextCommandDisplayText("STRING")
                        AddTextComponentSubstringPlayerName(string.format("[~g~E~w~] Take %s", nearestSeat.label))
                        SetTextFont(0)
                        SetTextScale(0.32, 0.32)
                        SetTextColour(255, 255, 255, 220)
                        SetTextCentre(true)

                        SetDrawOrigin(nearestSeat.coords.x, nearestSeat.coords.y, nearestSeat.coords.z + 0.3, 0)
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()

                        if IsControlJustPressed(0, 38) then -- E key: Sit
                            isSeated = true
                            currentSeatIndex = nearestSeat.id
                            SetEntityCoords(ped, nearestSeat.coords.x, nearestSeat.coords.y, nearestSeat.coords.z - 0.95, false, false, false, true)
                            SetEntityHeading(ped, nearestSeat.coords.w)
                            TaskStartScenarioInPlace(ped, "PROP_HUMAN_SEAT_CHAIR_MP_PLAYER", 0, true)
                            Wait(500)
                        end
                    else
                        -- Currently seated prompt
                        local exitPrompt = "[~r~X~w~] Stand Up"
                        if currentSeatIndex and string.sub(currentSeatIndex, 1, 4) == "jury" and activeSummonedDocket then
                            exitPrompt = exitPrompt .. " | [~y~1~w~] Vote Guilty | [~b~2~w~] Not Guilty | [~w~3~w~] Abstain"

                            -- Deliberation Voting Keys
                            if IsControlJustPressed(0, 157) then -- 1 Key: Guilty
                                if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                                    exports['nyx_core']:TriggerServerRPC("judiciary:castJuryVote", activeSummonedDocket, "guilty")
                                end
                                Wait(500)
                            elseif IsControlJustPressed(0, 158) then -- 2 Key: Not Guilty
                                if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                                    exports['nyx_core']:TriggerServerRPC("judiciary:castJuryVote", activeSummonedDocket, "not_guilty")
                                end
                                Wait(500)
                            elseif IsControlJustPressed(0, 160) then -- 3 Key: Abstain
                                if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                                    exports['nyx_core']:TriggerServerRPC("judiciary:castJuryVote", activeSummonedDocket, "abstain")
                                end
                                Wait(500)
                            end
                        end

                        BeginTextCommandDisplayText("STRING")
                        AddTextComponentSubstringPlayerName(exitPrompt)
                        SetTextFont(0)
                        SetTextScale(0.32, 0.32)
                        SetTextColour(255, 255, 255, 220)
                        SetTextCentre(true)

                        local sc = nearestSeat.coords
                        SetDrawOrigin(sc.x, sc.y, sc.z + 0.3, 0)
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()

                        if IsControlJustPressed(0, 73) then -- X key: Stand
                            isSeated = false
                            currentSeatIndex = nil
                            ClearPedTasksImmediately(ped)
                            Wait(500)
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
