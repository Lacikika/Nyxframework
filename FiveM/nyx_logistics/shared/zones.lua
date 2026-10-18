--[[
    Nyxframework: nyx_logistics
    File: shared/zones.lua
    Description: Shared delivery zone topologies, spatial lookups, and demand formulas.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.DefaultZones = {
    ['zone_ls_metro'] = {
        id = 'zone_ls_metro',
        name = 'Los Santos Metro',
        coords = vector3(-48.2, -1757.4, 29.4),
        radius = 2500.0,
        baseDemandMultiplier = 1.35,
        taxSurcharge = 0.0150,
        importTariffRate = 0.0000
    },
    ['zone_sandy_shores'] = {
        id = 'zone_sandy_shores',
        name = 'Blaine County Central',
        coords = vector3(1845.2, 3782.1, 33.5),
        radius = 2000.0,
        baseDemandMultiplier = 0.85,
        taxSurcharge = 0.0000,
        importTariffRate = 0.0050
    },
    ['zone_paleto_bay'] = {
        id = 'zone_paleto_bay',
        name = 'Paleto Bay Enclave',
        coords = vector3(-140.5, 6350.2, 31.5),
        radius = 1800.0,
        baseDemandMultiplier = 0.75,
        taxSurcharge = 0.0000,
        importTariffRate = 0.0200
    },
    ['zone_port_industrial'] = {
        id = 'zone_port_industrial',
        name = 'Port of Los Santos Logistics Basin',
        coords = vector3(152.4, -3205.2, 5.9),
        radius = 1600.0,
        baseDemandMultiplier = 1.15,
        taxSurcharge = 0.0050,
        importTariffRate = 0.0000
    }
}

-- Spatial resolver: Finds the closest matching delivery zone for given coordinates
function Nyx.Logistics.ResolveZoneFromCoords(coords, customZones)
    if not coords then return "zone_ls_metro" end
    local zones = customZones or Nyx.Logistics.Zones or Nyx.Logistics.DefaultZones

    local targetVec
    if type(coords) == "vector3" then
        targetVec = coords
    elseif type(coords) == "table" and coords.x and coords.y then
        targetVec = vector3(coords.x, coords.y, coords.z or 0.0)
    else
        return "zone_ls_metro"
    end

    local bestZoneId = "zone_ls_metro"
    local bestDistance = math.huge

    for zoneId, z in pairs(zones) do
        local zCoords = z.coords
        local zVec = type(zCoords) == "vector3" and zCoords or vector3(zCoords.x, zCoords.y, zCoords.z or 0.0)
        local dist = #(vector2(targetVec.x, targetVec.y) - vector2(zVec.x, zVec.y))
        
        -- If inside radius, prefer the closest match
        if dist <= (z.radius or 2000.0) and dist < bestDistance then
            bestDistance = dist
            bestZoneId = zoneId
        end
    end

    return bestZoneId
end
