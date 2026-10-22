--[[
    Nyxframework: nyx_services
    File: client/livestock.lua
    Description: Client-side spatial interaction checks, ranch & slaughterhouse
                 NUI data bridge, and cold storage status indicators.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.ClientLivestock = {}

local RANCH_LOCATIONS = {
    {
        id = "ranch_grapeseed",
        name = "O'Neil Grapeseed Livestock Ranch",
        coords = vector3(2440.5, 4980.2, 45.0)
    },
    {
        id = "ranch_paleto",
        name = "Paleto Bay Coastal Cattle Ranch",
        coords = vector3(-380.2, 6180.4, 31.0)
    }
}

local SLAUGHTERHOUSE_LOCATIONS = {
    {
        id = "slaughterhouse_cypress_flats",
        name = "Cypress Flats Industrial Slaughterhouse",
        coords = vector3(960.5, -2180.2, 30.5)
    },
    {
        id = "slaughterhouse_paleto",
        name = "Paleto Meat Processing Plant",
        coords = vector3(-375.0, 6195.0, 31.5)
    }
}

--- Find nearest registered livestock ranch
function Nyx.Services.ClientLivestock.GetNearestRanch(playerCoords)
    playerCoords = playerCoords or GetEntityCoords(PlayerPedId())
    for _, ranch in ipairs(RANCH_LOCATIONS) do
        if #(playerCoords - ranch.coords) <= 15.0 then
            return ranch
        end
    end
    return nil
end

--- Find nearest registered slaughterhouse
function Nyx.Services.ClientLivestock.GetNearestSlaughterhouse(playerCoords)
    playerCoords = playerCoords or GetEntityCoords(PlayerPedId())
    for _, facility in ipairs(SLAUGHTERHOUSE_LOCATIONS) do
        if #(playerCoords - facility.coords) <= 15.0 then
            return facility
        end
    end
    return nil
end

-- Spatial Interaction Registration with nyx_interact
CreateThread(function()
    while not exports or not exports["nyx_interact"] do
        Wait(500)
    end

    for _, ranch in ipairs(RANCH_LOCATIONS) do
        exports["nyx_interact"]:AddInteractionPoint({
            id = "ranch_feed_" .. ranch.id,
            coords = ranch.coords,
            radius = 3.0,
            label = "Feed Cattle Ranch (" .. ranch.name .. ")",
            action = function()
                TriggerServerEvent("nyx_services:server:feedRanch", ranch.id)
            end
        })
    end

    for _, facility in ipairs(SLAUGHTERHOUSE_LOCATIONS) do
        exports["nyx_interact"]:AddInteractionPoint({
            id = "slaughterhouse_" .. facility.id,
            coords = facility.coords,
            radius = 3.0,
            label = "Slaughterhouse Processing (" .. facility.name .. ")",
            action = function()
                TriggerServerEvent("nyx_services:server:slaughterCattle", facility.id)
            end
        })
    end
end)
