--[[
    Nyxframework: nyx_core
    File: client/spawn.lua
    Description: World entity positioning, collision pre-streaming, and camera transitions upon spawn.
]]

Nyx = Nyx or {}
Nyx.Spawn = {}

-- Execute atomic spawn sequence with collision streaming
function Nyx.Spawn.Execute(position)
    CreateThread(function()
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do
            Wait(10)
        end

        local ped = PlayerPedId()
        local x = tonumber(position.x) or 0.0
        local y = tonumber(position.y) or 0.0
        local z = tonumber(position.z) or 70.0
        local heading = tonumber(position.heading) or 0.0

        -- Ensure model is alive and invisible during warp
        SetEntityVisible(ped, false, false)
        SetEntityCoords(ped, x, y, z, false, false, false, false)
        SetEntityHeading(ped, heading)

        -- Stream collision geometries before dropping freeze
        RequestCollisionAtCoord(x, y, z)
        local timeout = GetGameTimer() + 5000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
            Wait(50)
        end

        -- Re-affirm coordinates post-collision load
        SetEntityCoords(ped, x, y, z, false, false, false, false)
        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, true, false)

        -- Clear unwanted states
        ClearPedBloodDamage(ped)
        ClearPedWetness(ped)

        Wait(200)
        DoScreenFadeIn(1000)

        TriggerEvent("nyx:core:client:spawnComplete", position)
        if Config.Debug then
            print(string.format("^2[Nyx:Spawn] Collision streamed and spawn completed at (%.2f, %.2f, %.2f)^7", x, y, z))
        end
    end)
end
