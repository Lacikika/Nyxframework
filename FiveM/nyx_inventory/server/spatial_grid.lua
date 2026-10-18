--[[
    Nyxframework: nyx_inventory
    File: server/spatial_grid.lua
    Description: Authoritative server spatial grid index for ground drops.
                 Maintains constant-time (O(1)) cell indexing, neighborhood lookups,
                 and candidate filtering for auto-merging and interest management.
]]

Nyx = Nyx or {}
Nyx.SpatialGrid = Nyx.SpatialGrid or {}

-- In-memory spatial index state
Nyx.SpatialGrid.cells = {}      -- [cellKey] = { [dropId] = true }
Nyx.SpatialGrid.dropCells = {}  -- [dropId] = cellKey
Nyx.SpatialGrid.dropCoords = {} -- [dropId] = { x = number, y = number, z = number, bucket = integer }

-- Insert a drop into its appropriate spatial grid cell
function Nyx.SpatialGrid.Insert(dropId, coords, bucket)
    if not dropId or not coords then return nil end

    bucket = tonumber(bucket) or 0
    local cellKey, cx, cy = Nyx.SpatialGrid.GetCellKeyFromCoords(coords, bucket)

    -- If drop already in another cell, remove it first
    local oldCellKey = Nyx.SpatialGrid.dropCells[dropId]
    if oldCellKey and oldCellKey ~= cellKey then
        if Nyx.SpatialGrid.cells[oldCellKey] then
            Nyx.SpatialGrid.cells[oldCellKey][dropId] = nil
            if next(Nyx.SpatialGrid.cells[oldCellKey]) == nil then
                Nyx.SpatialGrid.cells[oldCellKey] = nil
            end
        end
    end

    Nyx.SpatialGrid.cells[cellKey] = Nyx.SpatialGrid.cells[cellKey] or {}
    Nyx.SpatialGrid.cells[cellKey][dropId] = true
    Nyx.SpatialGrid.dropCells[dropId] = cellKey
    Nyx.SpatialGrid.dropCoords[dropId] = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        bucket = bucket
    }

    return cellKey, cx, cy
end

-- Remove a drop from the spatial grid index
function Nyx.SpatialGrid.Remove(dropId)
    if not dropId then return false end

    local cellKey = Nyx.SpatialGrid.dropCells[dropId]
    if cellKey and Nyx.SpatialGrid.cells[cellKey] then
        Nyx.SpatialGrid.cells[cellKey][dropId] = nil
        if next(Nyx.SpatialGrid.cells[cellKey]) == nil then
            Nyx.SpatialGrid.cells[cellKey] = nil
        end
    end

    Nyx.SpatialGrid.dropCells[dropId] = nil
    Nyx.SpatialGrid.dropCoords[dropId] = nil
    return true
end

-- Update spatial coordinates and cell positioning of an existing drop
function Nyx.SpatialGrid.Update(dropId, newCoords, newBucket)
    if not dropId or not newCoords then return nil end
    return Nyx.SpatialGrid.Insert(dropId, newCoords, newBucket)
end

-- Retrieve list of drop IDs residing in a specific spatial cell
function Nyx.SpatialGrid.GetDropsInCell(cellKey)
    local cell = Nyx.SpatialGrid.cells[cellKey]
    if not cell then return {} end

    local list = {}
    for dropId, _ in pairs(cell) do
        list[#list + 1] = dropId
    end
    return list
end

-- Retrieve drops within radial distance of target coordinates
-- Queries only candidate cells overlapping the radius, converting O(N) full-server scan to O(1)
function Nyx.SpatialGrid.GetNearbyDrops(coords, radius, bucket)
    if not coords or not coords.x or not coords.y or not coords.z then
        return {}
    end

    radius = tonumber(radius) or 10.0
    bucket = tonumber(bucket) or 0
    local cx, cy, cz = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)

    -- Retrieve candidate cell keys covering the radius
    local candidateKeys = Nyx.SpatialGrid.GetCellsInRadius(cx, cy, radius, bucket)
    local candidates = {}
    local seen = {}

    for _, cellKey in ipairs(candidateKeys) do
        local cell = Nyx.SpatialGrid.cells[cellKey]
        if cell then
            for dropId, _ in pairs(cell) do
                if not seen[dropId] then
                    seen[dropId] = true
                    local dropData = Nyx.SpatialGrid.dropCoords[dropId]
                    if dropData and dropData.bucket == bucket then
                        local dx = dropData.x - cx
                        local dy = dropData.y - cy
                        local dz = dropData.z - cz
                        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if dist <= radius then
                            candidates[#candidates + 1] = {
                                dropId = dropId,
                                distance = dist,
                                coords = dropData
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.distance < b.distance
    end)

    return candidates
end

-- Get assigned cell key for a drop
function Nyx.SpatialGrid.GetCellForDrop(dropId)
    return Nyx.SpatialGrid.dropCells[dropId]
end

-- Retrieve current spatial index telemetry
function Nyx.SpatialGrid.GetStats()
    local totalCells = 0
    local maxDensity = 0
    local totalDrops = 0

    for cellKey, cell in pairs(Nyx.SpatialGrid.cells) do
        totalCells = totalCells + 1
        local count = 0
        for _ in pairs(cell) do
            count = count + 1
        end
        totalDrops = totalDrops + count
        if count > maxDensity then
            maxDensity = count
        end
    end

    return {
        totalCells = totalCells,
        totalDrops = totalDrops,
        maxDensity = maxDensity,
        cellSize = Nyx.SpatialGrid.GetCellSize()
    }
end

-- Clear entire spatial index (used for testing and resets)
function Nyx.SpatialGrid.Clear()
    Nyx.SpatialGrid.cells = {}
    Nyx.SpatialGrid.dropCells = {}
    Nyx.SpatialGrid.dropCoords = {}
end
