--[[
    Nyxframework: nyx_vehicles
    File: shared/fuel.lua
    Description: Pure Lua 5.4 domain logic engine for underground gas station
                 reservoirs, dynamic scarcity pricing, vehicle tank refueling,
                 and bulk fuel hauler logistics math.
]]

Nyx = Nyx or {}
Nyx.VehicleFuel = Nyx.VehicleFuel or {}

-- Standard gas pump model hashes in GTA V
Nyx.VehicleFuel.PumpModels = {
    [`prop_gas_pump_1a`] = true,
    [`prop_gas_pump_1b`] = true,
    [`prop_gas_pump_1c`] = true,
    [`prop_gas_pump_1d`] = true,
    [`prop_vintage_pump`] = true,
    [`prop_gas_pump_old2`] = true,
    [`prop_gas_pump_old3`] = true
}

-- Default fuel tanks and reservoir thresholds
Nyx.VehicleFuel.Defaults = {
    DefaultVehicleTank = 65.0,    -- Liters
    DefaultReservoirCap = 10000.0, -- Liters
    DefaultPricePerLiter = 1.85,  -- USD / Liter
    RefuelRatePerSecond = 5.0,    -- Liters pumped per second
    CriticalRatio = 0.10,         -- 10% capacity
    DegradedRatio = 0.25,         -- 25% capacity
    RefineryCoords = { x = 2736.0, y = 1420.0, z = 24.5 },
    RefineryStashId = "stash:refinery_fuel"
}

-- ----------------------------------------------------------------------------
-- 1. Refuel Amount Calculation & Zero-Stock Protection
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.CalculateRefuelAmount(currentTank, tankCapacity, reservoirStock, requestedLiters)
    currentTank = tonumber(currentTank) or 0.0
    tankCapacity = tonumber(tankCapacity) or Nyx.VehicleFuel.Defaults.DefaultVehicleTank
    reservoirStock = tonumber(reservoirStock) or 0.0

    -- Invariant: Zero fuel in underground reservoir strictly blocks refueling
    if reservoirStock <= 0.0 then
        return 0.0, "RESERVOIR_DEPLETED"
    end

    local spaceInTank = math.max(0.0, tankCapacity - currentTank)
    if spaceInTank <= 0.0 then
        return 0.0, "TANK_ALREADY_FULL"
    end

    local needed = spaceInTank
    if requestedLiters and tonumber(requestedLiters) and tonumber(requestedLiters) > 0.0 then
        needed = math.min(spaceInTank, tonumber(requestedLiters))
    end

    local actual = math.min(needed, reservoirStock)
    actual = math.floor(actual * 100.0 + 0.5) / 100.0

    return actual, "OK"
end

-- ----------------------------------------------------------------------------
-- 2. Dynamic Scarcity Price Scaling
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.CalculateDynamicPrice(basePrice, currentStock, maxCapacity)
    basePrice = tonumber(basePrice) or Nyx.VehicleFuel.Defaults.DefaultPricePerLiter
    currentStock = tonumber(currentStock) or 0.0
    maxCapacity = tonumber(maxCapacity) or Nyx.VehicleFuel.Defaults.DefaultReservoirCap

    if maxCapacity <= 0.0 then
        return math.floor(basePrice * 100.0 + 0.5) / 100.0
    end

    local ratio = math.max(0.0, math.min(1.0, currentStock / maxCapacity))

    -- Full base price when capacity >= 50%. Below 50%, scales linearly up to 2.0x base price at 0%
    if ratio >= 0.50 then
        return math.floor(basePrice * 100.0 + 0.5) / 100.0
    else
        local scarcity = (0.50 - ratio) / 0.50
        local multiplier = 1.0 + (scarcity * 1.0)
        return math.floor((basePrice * multiplier) * 100.0 + 0.5) / 100.0
    end
end

-- ----------------------------------------------------------------------------
-- 3. Reservoir Multi-Tier Status Evaluation
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.EvaluateReservoirStatus(currentStock, maxCapacity, criticalThreshold, degradedThreshold)
    currentStock = tonumber(currentStock) or 0.0
    maxCapacity = tonumber(maxCapacity) or Nyx.VehicleFuel.Defaults.DefaultReservoirCap
    criticalThreshold = tonumber(criticalThreshold) or (maxCapacity * Nyx.VehicleFuel.Defaults.CriticalRatio)
    degradedThreshold = tonumber(degradedThreshold) or (maxCapacity * Nyx.VehicleFuel.Defaults.DegradedRatio)

    if currentStock <= 0.0 then
        return "depleted"
    elseif currentStock <= criticalThreshold then
        return "critical_shortage"
    elseif currentStock <= degradedThreshold then
        return "degraded"
    else
        return "optimal"
    end
end

-- ----------------------------------------------------------------------------
-- 4. Bulk Tanker Freight Logistics Contract Math
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.CalculateBulkDeliveryContract(currentStock, maxCapacity)
    currentStock = tonumber(currentStock) or 0.0
    maxCapacity = tonumber(maxCapacity) or Nyx.VehicleFuel.Defaults.DefaultReservoirCap

    local neededLiters = math.max(0.0, maxCapacity - currentStock)
    local pods = math.max(1, math.floor((neededLiters / 500.0) + 0.5))

    local basePayoutPerPod = 350.00
    local deficitRatio = math.max(0.0, math.min(1.0, (maxCapacity - currentStock) / maxCapacity))
    local multiplier = 1.25 + (deficitRatio * 0.75) -- 1.25x to 2.0x

    local payoutPerUnit = math.floor((basePayoutPerPod * multiplier) * 100.0 + 0.5) / 100.0
    local totalPayout = math.floor((payoutPerUnit * pods) * 100.0 + 0.5) / 100.0
    local escrow = math.floor((totalPayout * 0.15) * 100.0 + 0.5) / 100.0

    return pods, payoutPerUnit, totalPayout, escrow
end

-- ----------------------------------------------------------------------------
-- 5. Zero-Trust Payload Validation
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.ValidateRefuelPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local stationId = payload.stationId
    if not stationId or type(stationId) ~= "string" or stationId == "" then
        return false, "INVALID_STATION_ID"
    end

    local vehicleNetId = payload.vehicleNetId
    if not vehicleNetId or type(vehicleNetId) ~= "number" then
        return false, "INVALID_VEHICLE"
    end

    local liters = payload.liters
    if liters ~= nil then
        if type(liters) ~= "number" or liters <= 0.0 or liters > 200.0 then
            return false, "INVALID_LITERS"
        end
    end

    local paymentType = payload.paymentType or "bank"
    if paymentType ~= "bank" and paymentType ~= "cash" then
        return false, "INVALID_PAYMENT_TYPE"
    end

    return true, "OK"
end

function Nyx.VehicleFuel.ValidateRestockPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local stationId = payload.stationId
    if not stationId or type(stationId) ~= "string" or stationId == "" then
        return false, "INVALID_STATION_ID"
    end

    local itemId = payload.itemId
    local validItems = {
        ['industrial_fuel'] = 50.0,   -- 50 Liters per drum
        ['bulk_fuel_tank'] = 500.0,  -- 500 Liters per pod
        ['fuel_canister'] = 20.0     -- 20 Liters per jerrycan
    }

    if not itemId or not validItems[itemId] then
        return false, "INVALID_FUEL_ITEM"
    end

    local quantity = tonumber(payload.quantity)
    if not quantity or quantity <= 0 or math.floor(quantity) ~= quantity then
        return false, "INVALID_QUANTITY"
    end

    local litersAdded = validItems[itemId] * quantity
    return true, "OK", litersAdded
end

-- ----------------------------------------------------------------------------
-- 6. Spatial Resolution & UI Helpers
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.GetNearestGasStation(coords, stations)
    if not coords or not stations then return nil, nil end
    local cx, cy, cz = coords.x, coords.y, coords.z
    local nearest = nil
    local minDistance = 999999.0

    for id, s in pairs(stations) do
        local sc = s.coords
        if type(sc) == "string" then
            sc = json and json.decode and json.decode(sc) or nil
        end
        if sc and sc.x and sc.y and sc.z then
            local dx = cx - sc.x
            local dy = cy - sc.y
            local dz = cz - sc.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist < minDistance then
                minDistance = dist
                nearest = s
            end
        end
    end

    return nearest, minDistance
end

function Nyx.VehicleFuel.FormatFuelBadge(status)
    local badges = {
        optimal = { text = "KÉSZLETEN (OPTIMÁLIS)", class = "badge-success", color = "#10B981" },
        degraded = { text = "ALACSONY TARTÁLYSZINT", class = "badge-warning", color = "#F59E0B" },
        critical_shortage = { text = "KRITIKUS HIÁNY", class = "badge-danger", color = "#EF4444" },
        depleted = { text = "KIAPADT / ÜRES", class = "badge-blackout", color = "#6B7280" }
    }
    return badges[status] or badges.optimal
end

function Nyx.VehicleFuel.FormatCurrency(amount)
    amount = tonumber(amount) or 0.0
    return string.format("$%.2f", amount)
end
