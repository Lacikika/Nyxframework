--[[
    Nyxframework: nyx_vehicles
    File: client/transit_permits.lua
    Description: Client-side spatial interaction with municipal permit issuance terminals and weigh scale permit checks.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.TransitPermitsClient = Nyx.TransitPermitsClient or {}

-- Municipal Commercial Transit Permit Issuing Terminals
Nyx.TransitPermitsClient.Terminals = {
    { id = "terminal_paleto_weigh", name = "Paleto Bay Port Transit Terminal", coords = vector3(-138.0, 6265.0, 31.0), radius = 3.0 },
    { id = "terminal_davis_freight", name = "Davis Industrial Freight Depot", coords = vector3(115.0, -2530.0, 6.0), radius = 3.0 },
    { id = "terminal_port_ls", name = "Port of Los Santos Logistics Terminal", coords = vector3(1072.0, -2900.0, 5.0), radius = 3.0 }
}

--- Spatial interaction: Request transit permit purchase from nearby terminal
--- @param terminalId string Target terminal ID
--- @param plate string Vehicle license plate
--- @param permitType string ('SINGLE_TRIP', 'DAILY_PASS', 'ANNUAL_HEAVY_HAUL')
--- @param requestedMaxWeightKg number Requested capacity in kg
--- @param cb function Callback with server response
function Nyx.TransitPermitsClient.RequestTransitPermit(terminalId, plate, permitType, requestedMaxWeightKg, cb)
    if not Nyx.RPC or not Nyx.RPC.Call then
        if cb then cb({ success = false, error = "RPC_UNAVAILABLE" }) end
        return
    end

    Nyx.RPC.Call("vehicles:transit:issuePermit", {
        terminalId = terminalId,
        plate = plate,
        permitType = permitType,
        maxWeightCapacityKg = requestedMaxWeightKg
    }, function(response)
        if cb then cb(response or { success = false, error = "NO_RESPONSE" }) end
    end)
end

--- Spatial interaction: Query active permit for driver vehicle
--- @param plate string
--- @param measuredWeightKg number
--- @param cb function
function Nyx.TransitPermitsClient.QueryActivePermit(plate, measuredWeightKg, cb)
    if not Nyx.RPC or not Nyx.RPC.Call then
        if cb then cb({ isValid = false, status = "RPC_UNAVAILABLE" }) end
        return
    end

    Nyx.RPC.Call("vehicles:transit:checkPermit", {
        plate = plate,
        measuredWeightKg = measuredWeightKg
    }, function(response)
        if cb then cb(response or { isValid = false, status = "NO_RESPONSE" }) end
    end)
end
