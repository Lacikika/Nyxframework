--[[
    Nyxframework: nyx_core
    File: shared/math.lua
    Description: Authoritative shared mathematical, vector algebra, and spatial geometry utility library.
                 Provides optimized, defensive, zero-busywait algorithms for both server and client runtimes.
]]

Nyx = Nyx or {}
Nyx.Math = Nyx.Math or {}

-- Localized standard math references for peak execution performance
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_ceil = math.ceil
local math_abs = math.abs
local math_sqrt = math.sqrt
local math_sin = math.sin
local math_cos = math.cos
local math_rad = math.rad
local math_deg = math.deg
local math_atan = math.atan
local math_acos = math.acos
local math_pi = math.pi

--------------------------------------------------------------------------------
-- 1. SCALAR MATHEMATICS
--------------------------------------------------------------------------------

--- Clamps a numeric value between a minimum and maximum boundary.
--- @param value number The input value to clamp.
--- @param minVal number Lower boundary.
--- @param maxVal number Upper boundary.
--- @return number Clamped value.
function Nyx.Math.Clamp(value, minVal, maxVal)
    value = tonumber(value) or 0.0
    minVal = tonumber(minVal) or 0.0
    maxVal = tonumber(maxVal) or minVal
    if minVal > maxVal then
        minVal, maxVal = maxVal, minVal
    end
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

--- Rounds a numeric value to a specified decimal precision.
--- @param value number Value to round.
--- @param numDecimals integer? Number of decimal places (default 0).
--- @return number Rounded value.
function Nyx.Math.Round(value, numDecimals)
    value = tonumber(value) or 0.0
    numDecimals = math_max(0, math_floor(tonumber(numDecimals) or 0))
    local mult = 10 ^ numDecimals
    if value >= 0.0 then
        return math_floor(value * mult + 0.5) / mult
    else
        return math_ceil(value * mult - 0.5) / mult
    end
end

--- Linear interpolation between two scalar numbers.
--- @param a number Starting value.
--- @param b number Ending value.
--- @param t number Interpolation factor (0.0 to 1.0).
--- @return number Interpolated result.
function Nyx.Math.Lerp(a, b, t)
    a = tonumber(a) or 0.0
    b = tonumber(b) or 0.0
    t = tonumber(t) or 0.0
    return a + (b - a) * t
end

--- Inverse linear interpolation: computes the fraction t of value between a and b.
--- @param a number Range start.
--- @param b number Range end.
--- @param value number Target value.
--- @return number Factor t in [0.0, 1.0].
function Nyx.Math.InvLerp(a, b, value)
    a = tonumber(a) or 0.0
    b = tonumber(b) or 0.0
    value = tonumber(value) or 0.0
    local range = b - a
    if math_abs(range) < 1e-9 then
        return 0.0
    end
    return (value - a) / range
end

--- Remaps a numeric value from an input range to an output range.
--- @param value number Input value.
--- @param inMin number Input range start.
--- @param inMax number Input range end.
--- @param outMin number Output range start.
--- @param outMax number Output range end.
--- @return number Remapped value.
function Nyx.Math.Remap(value, inMin, inMax, outMin, outMax)
    local t = Nyx.Math.InvLerp(inMin, inMax, value)
    return Nyx.Math.Lerp(outMin, outMax, t)
end

--- Returns the sign of a number (-1, 0, or 1).
--- @param value number Input number.
--- @return integer -1 if negative, 1 if positive, 0 if zero.
function Nyx.Math.Sign(value)
    value = tonumber(value) or 0.0
    if value > 0.0 then return 1 end
    if value < 0.0 then return -1 end
    return 0
end

--- Compares two floating point numbers within an epsilon tolerance.
--- @param a number First value.
--- @param b number Second value.
--- @param epsilon number? Tolerance threshold (default 1e-6).
--- @return boolean True if difference is within epsilon.
function Nyx.Math.IsNear(a, b, epsilon)
    a = tonumber(a) or 0.0
    b = tonumber(b) or 0.0
    epsilon = tonumber(epsilon) or 1e-6
    return math_abs(a - b) <= epsilon
end

--- Converts degrees to radians.
--- @param degrees number Degrees.
--- @return number Radians.
function Nyx.Math.DegToRad(degrees)
    return math_rad(tonumber(degrees) or 0.0)
end

--- Converts radians to degrees.
--- @param radians number Radians.
--- @return number Degrees.
function Nyx.Math.RadToDeg(radians)
    return math_deg(tonumber(radians) or 0.0)
end

--------------------------------------------------------------------------------
-- 2. VECTOR PARSING & TRANSFORMATIONS
--------------------------------------------------------------------------------

--- Unpacks any vector3, table, or array into pure vector3 coordinates (x, y, z).
--- @param input any vector3, table {x,y,z}, array {1,2,3}, or nil.
--- @param defaultZ number? Fallback Z coordinate if missing.
--- @return vector3
function Nyx.Math.ToVector3(input, defaultZ)
    if not input then
        return vector3(0.0, 0.0, defaultZ or 0.0)
    end
    if type(input) == "vector3" then
        return input
    end
    if type(input) == "vector4" then
        return vector3(input.x, input.y, input.z)
    end
    if type(input) == "table" then
        local x = tonumber(input.x or input[1]) or 0.0
        local y = tonumber(input.y or input[2]) or 0.0
        local z = tonumber(input.z or input[3]) or (defaultZ or 0.0)
        return vector3(x, y, z)
    end
    return vector3(0.0, 0.0, defaultZ or 0.0)
end

--- Unpacks any vector2/3, table, or array into pure vector2 coordinates (x, y).
--- @param input any
--- @return vector2
function Nyx.Math.ToVector2(input)
    if not input then
        return vector2(0.0, 0.0)
    end
    if type(input) == "vector2" then
        return input
    end
    if type(input) == "vector3" or type(input) == "vector4" then
        return vector2(input.x, input.y)
    end
    if type(input) == "table" then
        local x = tonumber(input.x or input[1]) or 0.0
        local y = tonumber(input.y or input[2]) or 0.0
        return vector2(x, y)
    end
    return vector2(0.0, 0.0)
end

--- Converts vector or coordinates into a JSON/database-serializable table {x, y, z}.
--- @param vec any
--- @return table
function Nyx.Math.VectorToTable(vec)
    local v = Nyx.Math.ToVector3(vec)
    return { x = v.x, y = v.y, z = v.z }
end

--- Normalizes a vector into a unit vector of magnitude 1.0.
--- @param vec any
--- @return vector3
function Nyx.Math.Normalize(vec)
    local v = Nyx.Math.ToVector3(vec)
    local magSq = v.x * v.x + v.y * v.y + v.z * v.z
    if magSq < 1e-12 then
        return vector3(0.0, 0.0, 0.0)
    end
    local invMag = 1.0 / math_sqrt(magSq)
    return vector3(v.x * invMag, v.y * invMag, v.z * invMag)
end

--------------------------------------------------------------------------------
-- 3. SPATIAL & DISTANCE CALCULATIONS
--------------------------------------------------------------------------------

--- Computes Euclidean 3D distance between two points.
--- @param p1 any
--- @param p2 any
--- @return number
function Nyx.Math.Distance(p1, p2)
    local v1 = Nyx.Math.ToVector3(p1)
    local v2 = Nyx.Math.ToVector3(p2)
    local dx = v1.x - v2.x
    local dy = v1.y - v2.y
    local dz = v1.z - v2.z
    return math_sqrt(dx * dx + dy * dy + dz * dz)
end

--- Computes Euclidean 2D distance between two points ignoring elevation (Z).
--- @param p1 any
--- @param p2 any
--- @return number
function Nyx.Math.Distance2D(p1, p2)
    local v1 = Nyx.Math.ToVector2(p1)
    local v2 = Nyx.Math.ToVector2(p2)
    local dx = v1.x - v2.x
    local dy = v1.y - v2.y
    return math_sqrt(dx * dx + dy * dy)
end

--- Computes squared 3D distance between two points (avoids expensive math.sqrt).
--- @param p1 any
--- @param p2 any
--- @return number
function Nyx.Math.DistanceSquared(p1, p2)
    local v1 = Nyx.Math.ToVector3(p1)
    local v2 = Nyx.Math.ToVector3(p2)
    local dx = v1.x - v2.x
    local dy = v1.y - v2.y
    local dz = v1.z - v2.z
    return (dx * dx + dy * dy + dz * dz)
end

--- Computes squared 2D distance between two points.
--- @param p1 any
--- @param p2 any
--- @return number
function Nyx.Math.Distance2DSquared(p1, p2)
    local v1 = Nyx.Math.ToVector2(p1)
    local v2 = Nyx.Math.ToVector2(p2)
    local dx = v1.x - v2.x
    local dy = v1.y - v2.y
    return (dx * dx + dy * dy)
end

--- Efficiently verifies if two 3D points are within a specified distance threshold.
--- Uses squared distance comparison to guarantee 0.00ms idle overhead.
--- @param p1 any First position.
--- @param p2 any Second position.
--- @param maxDistance number Distance threshold.
--- @return boolean True if distance <= maxDistance.
function Nyx.Math.IsWithinRange(p1, p2, maxDistance)
    maxDistance = tonumber(maxDistance) or 0.0
    if maxDistance <= 0.0 then return false end
    return Nyx.Math.DistanceSquared(p1, p2) <= (maxDistance * maxDistance)
end

--- Efficiently verifies if two 2D points are within a specified distance threshold.
--- @param p1 any First position.
--- @param p2 any Second position.
--- @param maxDistance number Distance threshold.
--- @return boolean True if 2D distance <= maxDistance.
function Nyx.Math.IsWithinRange2D(p1, p2, maxDistance)
    maxDistance = tonumber(maxDistance) or 0.0
    if maxDistance <= 0.0 then return false end
    return Nyx.Math.Distance2DSquared(p1, p2) <= (maxDistance * maxDistance)
end

--------------------------------------------------------------------------------
-- 4. VECTOR ALGEBRA
--------------------------------------------------------------------------------

--- Computes the dot product of two vectors.
--- @param v1 any
--- @param v2 any
--- @return number
function Nyx.Math.Dot(v1, v2)
    local u = Nyx.Math.ToVector3(v1)
    local w = Nyx.Math.ToVector3(v2)
    return (u.x * w.x + u.y * w.y + u.z * w.z)
end

--- Computes the 3D cross product of two vectors (u x v).
--- @param v1 any
--- @param v2 any
--- @return vector3
function Nyx.Math.Cross(v1, v2)
    local u = Nyx.Math.ToVector3(v1)
    local w = Nyx.Math.ToVector3(v2)
    return vector3(
        u.y * w.z - u.z * w.y,
        u.z * w.x - u.x * w.z,
        u.x * w.y - u.y * w.x
    )
end

--- Computes the magnitude (length) of a vector.
--- @param vec any
--- @return number
function Nyx.Math.Magnitude(vec)
    local v = Nyx.Math.ToVector3(vec)
    return math_sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

--- Computes the squared magnitude of a vector.
--- @param vec any
--- @return number
function Nyx.Math.MagnitudeSquared(vec)
    local v = Nyx.Math.ToVector3(vec)
    return (v.x * v.x + v.y * v.y + v.z * v.z)
end

--- Computes the angle in degrees between two 3D vectors.
--- @param v1 any
--- @param v2 any
--- @return number Angle in degrees [0, 180].
function Nyx.Math.AngleBetween(v1, v2)
    local u = Nyx.Math.Normalize(v1)
    local w = Nyx.Math.Normalize(v2)
    local dot = Nyx.Math.Clamp(Nyx.Math.Dot(u, w), -1.0, 1.0)
    return math_deg(math_acos(dot))
end

--- Interpolates between two 3D vectors.
--- @param v1 any Start vector.
--- @param v2 any End vector.
--- @param t number Interpolation fraction [0.0, 1.0].
--- @return vector3
function Nyx.Math.VectorLerp(v1, v2, t)
    local u = Nyx.Math.ToVector3(v1)
    local w = Nyx.Math.ToVector3(v2)
    return vector3(
        Nyx.Math.Lerp(u.x, w.x, t),
        Nyx.Math.Lerp(u.y, w.y, t),
        Nyx.Math.Lerp(u.z, w.z, t)
    )
end

--------------------------------------------------------------------------------
-- 5. ROTATION, HEADING & DIRECTION TRANSFORMS
--------------------------------------------------------------------------------

--- Converts GTA gameplay camera Euler rotation (pitch, roll, yaw in degrees) to a 3D direction vector.
--- @param rot any Euler rotation {x = pitch, y = roll, z = yaw}.
--- @return vector3 Unit forward vector.
function Nyx.Math.RotationToDirection(rot)
    local r = Nyx.Math.ToVector3(rot)
    local z = math_rad(r.z)
    local x = math_rad(r.x)
    local num = math_abs(math_cos(x))
    return vector3(-math_sin(z) * num, math_cos(z) * num, math_sin(x))
end

--- Converts GTA entity heading (degrees clockwise from North) to a 2D/3D forward unit vector.
--- In GTA: 0 = North (+Y), 90 = West (-X), 180 = South (-Y), 270 = East (+X).
--- @param heading number Heading in degrees.
--- @return vector3 Forward direction vector.
function Nyx.Math.HeadingToDirection(heading)
    local rad = math_rad(tonumber(heading) or 0.0)
    return vector3(-math_sin(rad), math_cos(rad), 0.0)
end

--- Computes GTA entity heading (0 to 360 degrees) from a 2D or 3D direction vector.
--- @param dir any Direction vector.
--- @return number Heading in degrees [0.0, 360.0).
function Nyx.Math.DirectionToHeading(dir)
    local d = Nyx.Math.ToVector3(dir)
    local deg = math_deg(math_atan(-d.x, d.y))
    if deg < 0.0 then
        deg = deg + 360.0
    end
    return deg
end

--- Calculates the heading required to face from origin coords toward target coords.
--- @param fromCoords any Origin point.
--- @param toCoords any Target point.
--- @return number Heading in degrees [0.0, 360.0).
function Nyx.Math.GetHeadingBetween(fromCoords, toCoords)
    local f = Nyx.Math.ToVector3(fromCoords)
    local t = Nyx.Math.ToVector3(toCoords)
    local dx = t.x - f.x
    local dy = t.y - f.y
    local deg = math_deg(math_atan(-dx, dy))
    if deg < 0.0 then
        deg = deg + 360.0
    end
    return deg
end

--- Calculates the shortest angular difference between two headings/angles in degrees.
--- @param angle1 number First angle in degrees.
--- @param angle2 number Second angle in degrees.
--- @return number Absolute angular difference in degrees [0.0, 180.0].
function Nyx.Math.GetAngleDifference(angle1, angle2)
    local a1 = tonumber(angle1) or 0.0
    local a2 = tonumber(angle2) or 0.0
    local diff = (a1 - a2 + 180.0) % 360.0 - 180.0
    if diff < -180.0 then
        diff = diff + 360.0
    end
    return math_abs(diff)
end

--------------------------------------------------------------------------------
-- 6. GEOMETRIC CONTAINMENT & BOUNDS
--------------------------------------------------------------------------------

--- Tests if a 3D point is inside a spherical volume.
--- @param point any Point to test.
--- @param center any Sphere center.
--- @param radius number Sphere radius.
--- @return boolean
function Nyx.Math.IsPointInSphere(point, center, radius)
    return Nyx.Math.IsWithinRange(point, center, radius)
end

--- Tests if a point is inside an oriented bounding box (OBB) with a given center, dimensions, and heading.
--- @param point any Point to test.
--- @param boxCenter any Center position of the box.
--- @param boxDimensions any Dimensions {x = length, y = width, z = height}.
--- @param boxHeading number? Rotation around Z axis in degrees (default 0.0).
--- @return boolean
function Nyx.Math.IsPointInBox(point, boxCenter, boxDimensions, boxHeading)
    local p = Nyx.Math.ToVector3(point)
    local c = Nyx.Math.ToVector3(boxCenter)
    local d = Nyx.Math.ToVector3(boxDimensions)
    local h = tonumber(boxHeading) or 0.0

    -- Translate point to box-local origin
    local dx = p.x - c.x
    local dy = p.y - c.y
    local dz = p.z - c.z

    -- Rotate point back by -heading around Z axis
    local rad = -math_rad(h)
    local cosH = math_cos(rad)
    local sinH = math_sin(rad)
    local localX = dx * cosH - dy * sinH
    local localY = dx * sinH + dy * cosH
    local localZ = dz

    local halfX = math_abs(d.x) * 0.5
    local halfY = math_abs(d.y) * 0.5
    local halfZ = math_abs(d.z) * 0.5

    return (math_abs(localX) <= halfX) and (math_abs(localY) <= halfY) and (math_abs(localZ) <= halfZ)
end

--- Tests if a 2D point is inside an arbitrary polygon using the ray-casting algorithm (even-odd rule).
--- @param point any Point to test (x, y).
--- @param polygonPoints table Array of vertices [{x, y}, ...].
--- @return boolean True if point is strictly inside polygon.
function Nyx.Math.IsPointInPolygon(point, polygonPoints)
    if not polygonPoints or #polygonPoints < 3 then return false end
    local pt = Nyx.Math.ToVector2(point)
    local px = pt.x
    local py = pt.y

    local inside = false
    local n = #polygonPoints
    local j = n

    for i = 1, n do
        local pi = Nyx.Math.ToVector2(polygonPoints[i])
        local pj = Nyx.Math.ToVector2(polygonPoints[j])

        if ((pi.y > py) ~= (pj.y > py)) and (px < (pj.x - pi.x) * (py - pi.y) / (pj.y - pi.y) + pi.x) then
            inside = not inside
        end
        j = i
    end

    return inside
end

--------------------------------------------------------------------------------
-- 7. SPATIAL GRID PARTITIONING & HASHING
--------------------------------------------------------------------------------

--- Converts 2D world coordinates to spatial grid integer cell indices.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param cellSize number? Size of grid cell in meters (default 64.0).
--- @return integer cellX, integer cellY
function Nyx.Math.CoordsToCell(x, y, cellSize)
    cellSize = tonumber(cellSize) or 64.0
    if cellSize <= 0.0 then cellSize = 64.0 end
    return math_floor((tonumber(x) or 0.0) / cellSize), math_floor((tonumber(y) or 0.0) / cellSize)
end

--- Generates a deterministic string key for a spatial cell and virtual routing bucket.
--- @param cellX integer Cell X index.
--- @param cellY integer Cell Y index.
--- @param bucket integer? Routing bucket ID (default 0).
--- @return string Formatted cell key "cellX:cellY:bucket".
function Nyx.Math.GetCellKey(cellX, cellY, bucket)
    return string.format("%d:%d:%d", math_floor(tonumber(cellX) or 0), math_floor(tonumber(cellY) or 0), math_floor(tonumber(bucket) or 0))
end

--- Resolves the cell key directly from coordinate table or vector.
--- @param coords any {x, y, z} or vector3.
--- @param cellSize number?
--- @param bucket integer?
--- @return string cellKey, integer cellX, integer cellY
function Nyx.Math.GetCellKeyFromCoords(coords, cellSize, bucket)
    local v = Nyx.Math.ToVector2(coords)
    local cx, cy = Nyx.Math.CoordsToCell(v.x, v.y, cellSize)
    return Nyx.Math.GetCellKey(cx, cy, bucket), cx, cy
end

--- Retrieves an array of neighbor cell keys within a given cell radius (Moore neighborhood).
--- For radiusCells = 1, returns 9 cell keys (center + 8 surrounding cells).
--- @param cellX integer Center cell X.
--- @param cellY integer Center cell Y.
--- @param bucket integer? Routing bucket.
--- @param radiusCells integer? Radius in cells (default 1).
--- @return table Array of string cell keys.
function Nyx.Math.GetNeighborCellKeys(cellX, cellY, bucket, radiusCells)
    local cx = math_floor(tonumber(cellX) or 0)
    local cy = math_floor(tonumber(cellY) or 0)
    bucket = math_floor(tonumber(bucket) or 0)
    radiusCells = math_max(0, math_floor(tonumber(radiusCells) or 1))

    local keys = {}
    for dx = -radiusCells, radiusCells do
        for dy = -radiusCells, radiusCells do
            keys[#keys + 1] = Nyx.Math.GetCellKey(cx + dx, cy + dy, bucket)
        end
    end
    return keys
end

--- Computes all cell keys covering a circular area of given radius around center coordinates.
--- @param centerX number Center X.
--- @param centerY number Center Y.
--- @param radius number Radius in meters.
--- @param cellSize number? Cell size (default 64.0).
--- @param bucket integer? Routing bucket (default 0).
--- @return table Array of string cell keys.
function Nyx.Math.GetCellsInRadius(centerX, centerY, radius, cellSize, bucket)
    cellSize = tonumber(cellSize) or 64.0
    if cellSize <= 0.0 then cellSize = 64.0 end
    radius = math_max(0.0, tonumber(radius) or 0.0)
    bucket = math_floor(tonumber(bucket) or 0)

    local minCx = math_floor((centerX - radius) / cellSize)
    local maxCx = math_floor((centerX + radius) / cellSize)
    local minCy = math_floor((centerY - radius) / cellSize)
    local maxCy = math_floor((centerY + radius) / cellSize)

    local keys = {}
    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            keys[#keys + 1] = Nyx.Math.GetCellKey(cx, cy, bucket)
        end
    end
    return keys
end

--- Returns world coordinate boundaries for a spatial grid cell.
--- @param cellX integer Cell X index.
--- @param cellY integer Cell Y index.
--- @param cellSize number? Cell size (default 64.0).
--- @return number minX, number maxX, number minY, number maxY
function Nyx.Math.GetCellBounds(cellX, cellY, cellSize)
    cellSize = tonumber(cellSize) or 64.0
    if cellSize <= 0.0 then cellSize = 64.0 end
    local cx = math_floor(tonumber(cellX) or 0)
    local cy = math_floor(tonumber(cellY) or 0)
    local minX = cx * cellSize
    local maxX = minX + cellSize
    local minY = cy * cellSize
    local maxY = minY + cellSize
    return minX, maxX, minY, maxY
end

--------------------------------------------------------------------------------
-- 8. PUBLIC RUNTIME EXPORTS
--------------------------------------------------------------------------------

exports("GetMath", function()
    return Nyx.Math
end)

exports("Clamp", function(v, mn, mx)
    return Nyx.Math.Clamp(v, mn, mx)
end)

exports("Round", function(v, dec)
    return Nyx.Math.Round(v, dec)
end)

exports("Distance", function(p1, p2)
    return Nyx.Math.Distance(p1, p2)
end)

exports("Distance2D", function(p1, p2)
    return Nyx.Math.Distance2D(p1, p2)
end)

exports("DistanceSquared", function(p1, p2)
    return Nyx.Math.DistanceSquared(p1, p2)
end)

exports("IsWithinRange", function(p1, p2, maxDist)
    return Nyx.Math.IsWithinRange(p1, p2, maxDist)
end)

exports("RotationToDirection", function(rot)
    return Nyx.Math.RotationToDirection(rot)
end)

exports("HeadingToDirection", function(h)
    return Nyx.Math.HeadingToDirection(h)
end)

exports("DirectionToHeading", function(dir)
    return Nyx.Math.DirectionToHeading(dir)
end)

exports("GetHeadingBetween", function(f, t)
    return Nyx.Math.GetHeadingBetween(f, t)
end)

exports("GetAngleDifference", function(a1, a2)
    return Nyx.Math.GetAngleDifference(a1, a2)
end)

exports("IsPointInPolygon", function(pt, poly)
    return Nyx.Math.IsPointInPolygon(pt, poly)
end)

exports("IsPointInBox", function(pt, center, dim, heading)
    return Nyx.Math.IsPointInBox(pt, center, dim, heading)
end)

exports("CoordsToCell", function(x, y, cellSize)
    return Nyx.Math.CoordsToCell(x, y, cellSize)
end)

exports("GetCellKey", function(cx, cy, bucket)
    return Nyx.Math.GetCellKey(cx, cy, bucket)
end)

exports("GetNeighborCellKeys", function(cx, cy, bucket, radius)
    return Nyx.Math.GetNeighborCellKeys(cx, cy, bucket, radius)
end)

exports("GetCellsInRadius", function(cx, cy, rad, cellSize, bucket)
    return Nyx.Math.GetCellsInRadius(cx, cy, rad, cellSize, bucket)
end)

exports("GetCellBounds", function(cx, cy, cellSize)
    return Nyx.Math.GetCellBounds(cx, cy, cellSize)
end)

