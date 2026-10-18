--[[
    Nyxframework: nyx_logistics
    File: shared/warehouses.lua
    Description: Pure Lua 5.4 3D physical shelf matrices, grid snapping calculations,
                 and coordinate transformations.
]]

Nyx = Nyx or {}
Nyx.Warehouses = Nyx.Warehouses or {}

-- Precision rounding helper
local function round(val, decimals)
    local mult = 10 ^ (decimals or 2)
    return math.floor(val * mult + 0.5) / mult
end

--- Computes the full 3D spatial node matrix for a physical storage shelf rack.
--- Applies 2D Euler heading rotations to align grid tiers and slots with the prop.
--- @param shelf table Shelf configuration
--- @return table nodesMap Keyed by nodeId
--- @return table nodesList Sequential array of nodes
function Nyx.Warehouses.CalculateShelfNodes(shelf)
    if not shelf then return {}, {} end

    local shelfId = tostring(shelf.shelf_id or shelf.id or "shelf_unknown")
    local warehouseId = tostring(shelf.warehouse_id or shelf.warehouseId or "wh_default")
    local label = shelf.label or "Shelf Unit"

    local c = shelf.coords or { x = 0.0, y = 0.0, z = 0.0 }
    local shelfX = tonumber(c.x or c[1]) or 0.0
    local shelfY = tonumber(c.y or c[2]) or 0.0
    local shelfZ = tonumber(c.z or c[3]) or 0.0

    local rot = shelf.rotation or {}
    local heading = tonumber(rot.heading or rot.z or shelf.heading) or 0.0
    heading = (heading % 360.0 + 360.0) % 360.0

    local tiers = math.max(1, math.floor(tonumber(shelf.tiers) or 3))
    local slotsPerTier = math.max(1, math.floor(tonumber(shelf.slots_per_tier or shelf.slotsPerTier) or 3))
    local tierSpacing = tonumber(shelf.tier_spacing or shelf.tierSpacing) or 0.50
    local slotSpacing = tonumber(shelf.slot_spacing or shelf.slotSpacing) or 0.55
    local tierBaseZ = tonumber(shelf.tier_base_z or shelf.tierBaseZ) or 0.35
    local depthOffset = tonumber(shelf.depth_offset or shelf.depthOffset) or 0.05
    local routingBucket = tonumber(shelf.routing_bucket or shelf.routingBucket) or 0

    local rad = math.rad(heading)
    local cosA = math.cos(rad)
    local sinA = math.sin(rad)

    local nodesMap = {}
    local nodesList = {}

    for t = 1, tiers do
        local dz = tierBaseZ + (t - 1) * tierSpacing
        for s = 1, slotsPerTier do
            local dx = (s - (slotsPerTier + 1) / 2.0) * slotSpacing
            local dy = depthOffset

            -- 2D rotation of local (dx, dy) into GTA world space
            local wx = shelfX + (dx * cosA - dy * sinA)
            local wy = shelfY + (dx * sinA + dy * cosA)
            local wz = shelfZ + dz

            local nodeId = string.format("%s:t%d_s%d", shelfId, t, s)
            local nodeObj = {
                id = nodeId,
                shelfId = shelfId,
                warehouseId = warehouseId,
                shelfLabel = label,
                tier = t,
                slot = s,
                localOffset = {
                    x = round(dx, 3),
                    y = round(dy, 3),
                    z = round(dz, 3)
                },
                worldCoords = {
                    x = round(wx, 2),
                    y = round(wy, 2),
                    z = round(wz, 2)
                },
                heading = round(heading, 2),
                routingBucket = routingBucket,
                occupiedDropId = nil,
                itemData = nil
            }

            nodesMap[nodeId] = nodeObj
            nodesList[#nodesList + 1] = nodeObj
        end
    end

    return nodesMap, nodesList
end

--- Validates if a shelf snap node is currently available for placement.
--- @param node table Node object
--- @param currentDropId string|nil The drop being moved (if repositioning existing drop)
--- @return boolean
function Nyx.Warehouses.IsNodeAvailable(node, currentDropId)
    if not node then return false end
    if not node.occupiedDropId then return true end
    if currentDropId and tostring(node.occupiedDropId) == tostring(currentDropId) then
        return true
    end
    return false
end

--- Scans a collection or map of nodes to find the closest eligible snap point.
--- @param nodesCollection table Map or array of shelf nodes
--- @param targetPoint table Vector or table with x, y, z
--- @param maxSnapDistance number|nil Maximum radius in meters (default 0.85m)
--- @param currentDropId string|nil The drop ID being manipulated
--- @return table|nil closestNode
--- @return number|nil closestDist
function Nyx.Warehouses.FindNearestSnapNode(nodesCollection, targetPoint, maxSnapDistance, currentDropId)
    if not nodesCollection or not targetPoint then return nil, nil end

    local maxDist = tonumber(maxSnapDistance) or (Config.Warehouse and Config.Warehouse.SnapDistance) or 0.85
    local tx = tonumber(targetPoint.x or targetPoint[1]) or 0.0
    local ty = tonumber(targetPoint.y or targetPoint[2]) or 0.0
    local tz = tonumber(targetPoint.z or targetPoint[3]) or 0.0

    local closestNode = nil
    local closestDist = maxDist + 0.001

    -- Support both key-value maps and sequential lists
    for _, node in pairs(nodesCollection) do
        if type(node) == "table" and node.worldCoords then
            if Nyx.Warehouses.IsNodeAvailable(node, currentDropId) then
                local nx = node.worldCoords.x
                local ny = node.worldCoords.y
                local nz = node.worldCoords.z

                local dx = tx - nx
                local dy = ty - ny
                local dz = tz - nz
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                if dist <= maxDist and dist < closestDist then
                    closestDist = dist
                    closestNode = node
                end
            end
        end
    end

    if closestNode then
        return closestNode, round(closestDist, 3)
    end
    return nil, nil
end
