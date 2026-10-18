--[[
    Nyxframework: nyx_inventory
    File: shared/spatial_grid.lua
    Description: Shared spatial partitioning grid utilities for constant-time ground drop
                 queries, cell hashing, and neighborhood calculations.
]]

Nyx = Nyx or {}
Nyx.SpatialGrid = Nyx.SpatialGrid or {}

-- Get cell size in meters from configuration or fallback to 64.0m
function Nyx.SpatialGrid.GetCellSize()
    return (Config and Config.SpatialGridCellSize) or 64.0
end

-- Convert 2D or 3D coordinates to integer cell indices (cellX, cellY)
function Nyx.SpatialGrid.CoordsToCell(x, y, cellSize)
    cellSize = tonumber(cellSize) or Nyx.SpatialGrid.GetCellSize()
    if Nyx.Math and Nyx.Math.CoordsToCell then
        return Nyx.Math.CoordsToCell(x, y, cellSize)
    end
    cellSize = (cellSize > 0) and cellSize or 64.0
    return math.floor((tonumber(x) or 0.0) / cellSize), math.floor((tonumber(y) or 0.0) / cellSize)
end

-- Generate deterministic cell identifier key "cellX:cellY:bucket"
function Nyx.SpatialGrid.GetCellKey(cellX, cellY, bucket)
    if Nyx.Math and Nyx.Math.GetCellKey then
        return Nyx.Math.GetCellKey(cellX, cellY, bucket)
    end
    return string.format("%d:%d:%d", math.floor(tonumber(cellX) or 0), math.floor(tonumber(cellY) or 0), math.floor(tonumber(bucket) or 0))
end

-- Convert coordinate table/vector and routing bucket directly into string cell key
function Nyx.SpatialGrid.GetCellKeyFromCoords(coords, bucket, cellSize)
    cellSize = tonumber(cellSize) or Nyx.SpatialGrid.GetCellSize()
    bucket = tonumber(bucket) or 0
    if not coords then return Nyx.SpatialGrid.GetCellKey(0, 0, bucket), 0, 0 end

    local x = tonumber(coords.x or coords[1]) or 0.0
    local y = tonumber(coords.y or coords[2]) or 0.0
    local cx, cy = Nyx.SpatialGrid.CoordsToCell(x, y, cellSize)
    return Nyx.SpatialGrid.GetCellKey(cx, cy, bucket), cx, cy
end

-- Retrieve adjacent Moore neighborhood cell keys around a center cell
-- For radiusCells = 1, returns 9 keys (center + 8 surrounding cells)
function Nyx.SpatialGrid.GetNeighborKeys(cellX, cellY, bucket, radiusCells)
    if Nyx.Math and Nyx.Math.GetNeighborCellKeys then
        return Nyx.Math.GetNeighborCellKeys(cellX, cellY, bucket, radiusCells)
    end

    cellX = math.floor(tonumber(cellX) or 0)
    cellY = math.floor(tonumber(cellY) or 0)
    bucket = math.floor(tonumber(bucket) or 0)
    radiusCells = math.max(0, math.floor(tonumber(radiusCells) or 1))

    local keys = {}
    for dx = -radiusCells, radiusCells do
        for dy = -radiusCells, radiusCells do
            keys[#keys + 1] = string.format("%d:%d:%d", cellX + dx, cellY + dy, bucket)
        end
    end
    return keys
end

-- Compute all cell keys covering a circular area of given radius around center coordinates
function Nyx.SpatialGrid.GetCellsInRadius(centerX, centerY, radius, bucket, cellSize)
    cellSize = tonumber(cellSize) or Nyx.SpatialGrid.GetCellSize()
    if Nyx.Math and Nyx.Math.GetCellsInRadius then
        return Nyx.Math.GetCellsInRadius(centerX, centerY, radius, cellSize, bucket)
    end

    radius = math.max(0.0, tonumber(radius) or 0.0)
    bucket = math.floor(tonumber(bucket) or 0)
    local minCx = math.floor((centerX - radius) / cellSize)
    local maxCx = math.floor((centerX + radius) / cellSize)
    local minCy = math.floor((centerY - radius) / cellSize)
    local maxCy = math.floor((centerY + radius) / cellSize)

    local keys = {}
    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            keys[#keys + 1] = string.format("%d:%d:%d", cx, cy, bucket)
        end
    end
    return keys
end

-- Calculate 3D Euclidean distance between two coordinate tables
function Nyx.SpatialGrid.Distance(c1, c2)
    if not c1 or not c2 then return 999999.0 end
    local x1, y1, z1 = tonumber(c1.x or c1[1]) or 0.0, tonumber(c1.y or c1[2]) or 0.0, tonumber(c1.z or c1[3]) or 0.0
    local x2, y2, z2 = tonumber(c2.x or c2[1]) or 0.0, tonumber(c2.y or c2[2]) or 0.0, tonumber(c2.z or c2[3]) or 0.0
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Filter a collection of spatial elements (must contain .coords) within maxDistance
function Nyx.SpatialGrid.FilterElementsInRadius(elements, centerCoords, maxRadius, bucket)
    if not elements or not centerCoords then return {} end
    maxRadius = tonumber(maxRadius) or 10.0
    bucket = tonumber(bucket) or 0

    local results = {}
    for id, el in pairs(elements) do
        local elBucket = tonumber(el.routingBucket or el.bucket) or 0
        if elBucket == bucket and el.coords then
            local dist = Nyx.SpatialGrid.Distance(centerCoords, el.coords)
            if dist <= maxRadius then
                results[#results + 1] = {
                    id = el.id or id,
                    element = el,
                    distance = dist,
                    coords = el.coords
                }
            end
        end
    end

    table.sort(results, function(a, b)
        return a.distance < b.distance
    end)

    return results
end
