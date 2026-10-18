--[[
    Nyxframework: nyx_core
    File: shared/bootloader.lua
    Description: Pure Lua 5.4 Staggered Resource Bootloader Dispatch Planner.
                 Defines canonical initialization stages, timeline staggering math (50ms intervals),
                 state machine validations, and database contention reduction modeling.
]]

Nyx = Nyx or {}
Nyx.Bootloader = Nyx.Bootloader or {}

-- Canonical 6-stage boot architecture mapping all 14 modular resources
local CANONICAL_STAGES = {
    {
        stage = 1,
        name = "kernel",
        label = "Core Kernel & Ledgers",
        resources = {
            { name = "nyx_core", priority = 10 },
            { name = "nyx_treasury", priority = 20 }
        }
    },
    {
        stage = 2,
        name = "inventory",
        label = "Inventory & Logistics Foundation",
        resources = {
            { name = "nyx_inventory", priority = 10 },
            { name = "nyx_logistics", priority = 20 }
        }
    },
    {
        stage = 3,
        name = "civil",
        label = "Civic Services & Infrastructure",
        resources = {
            { name = "nyx_services", priority = 10 },
            { name = "nyx_properties", priority = 20 },
            { name = "nyx_vehicles", priority = 30 }
        }
    },
    {
        stage = 4,
        name = "governance",
        label = "Organizations & Governance",
        resources = {
            { name = "nyx_factions", priority = 10 },
            { name = "nyx_parliament", priority = 20 }
        }
    },
    {
        stage = 5,
        name = "justice",
        label = "Justice, Enforcement & Press",
        resources = {
            { name = "nyx_judiciary", priority = 10 },
            { name = "nyx_mdt", priority = 20 },
            { name = "nyx_press", priority = 30 }
        }
    },
    {
        stage = 6,
        name = "interface",
        label = "Client Interface & Interactions",
        resources = {
            { name = "nyx_interact", priority = 10 },
            { name = "nyx_ui", priority = 20 }
        }
    }
}

-- Valid unidirectional state transitions
local VALID_STATE_TRANSITIONS = {
    ["UNINITIALIZED"] = { ["WAITING_DB"] = true },
    ["WAITING_DB"]    = { ["DB_READY"] = true },
    ["DB_READY"]      = { ["DISPATCHING"] = true },
    ["DISPATCHING"]   = { ["BOOT_COMPLETE"] = true },
    ["BOOT_COMPLETE"] = {}
}

-- Deep copy helper
local function deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepCopy(orig_key)] = deepCopy(orig_value)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

--- Returns a fresh deep copy of the canonical 6-stage boot architecture
--- @return table
function Nyx.Bootloader.GetDefaultStages()
    return deepCopy(CANONICAL_STAGES)
end

--- Determines designated stage and priority for a specific resource
--- @param resourceName string
--- @param stages table|nil
--- @return number stageId, string stageName, number priority
function Nyx.Bootloader.DetermineResourceStage(resourceName, stages)
    local activeStages = stages or CANONICAL_STAGES
    for _, s in ipairs(activeStages) do
        if s.resources then
            for _, r in ipairs(s.resources) do
                if r.name == resourceName then
                    return s.stage, s.name, r.priority or 50
                end
            end
        end
    end
    -- Fallback: Stage 6 (interface/addons) with low priority
    return 6, "interface", 99
end

--- Sorts stages by stage ID, and within each stage sorts resources by priority ascending
--- @param stages table
--- @return table sortedStages
function Nyx.Bootloader.SortStages(stages)
    local cloned = deepCopy(stages or CANONICAL_STAGES)
    table.sort(cloned, function(a, b)
        return (a.stage or 0) < (b.stage or 0)
    end)

    for _, s in ipairs(cloned) do
        if s.resources then
            table.sort(s.resources, function(a, b)
                return (a.priority or 50) < (b.priority or 50)
            end)
        end
    end

    return cloned
end

--- Calculates linear scheduled offset timings for sequential execution
--- @param stages table|nil
--- @param staggerMs number|nil (default: 50)
--- @return table timeline, number totalWindowMs
function Nyx.Bootloader.CalculateTimeline(stages, staggerMs)
    local interval = math.max(1, tonumber(staggerMs) or 50)
    local sorted = Nyx.Bootloader.SortStages(stages or CANONICAL_STAGES)
    local timeline = {}
    local currentOffset = 0

    for _, stageInfo in ipairs(sorted) do
        if stageInfo.resources then
            for _, res in ipairs(stageInfo.resources) do
                timeline[#timeline + 1] = {
                    resource = res.name,
                    stage = stageInfo.stage,
                    stageName = stageInfo.name,
                    priority = res.priority or 50,
                    scheduledOffsetMs = currentOffset
                }
                currentOffset = currentOffset + interval
            end
        end
    end

    local totalWindowMs = #timeline > 0 and (currentOffset - interval) or 0
    return timeline, totalWindowMs
end

--- Validates whether a state machine transition is legally permitted
--- @param currentState string
--- @param nextState string
--- @return boolean isValid
function Nyx.Bootloader.ValidateTransition(currentState, nextState)
    local allowed = VALID_STATE_TRANSITIONS[currentState]
    if not allowed then return false end
    return allowed[nextState] == true
end

--- Mathematical model proving database connection pool contention reduction
--- @param resourceCount number (e.g. 14)
--- @param staggerMs number (e.g. 50ms)
--- @param avgQueryDurationMs number|nil (e.g. 30ms)
--- @return table contentionMetrics
function Nyx.Bootloader.CalculateContentionSavings(resourceCount, staggerMs, avgQueryDurationMs)
    local count = math.max(1, tonumber(resourceCount) or 14)
    local stagger = math.max(1, tonumber(staggerMs) or 50)
    local queryDuration = tonumber(avgQueryDurationMs) or 30.0

    local unmitigatedBurst = count
    local maxConcurrentStaggered = math.max(1.0, queryDuration / stagger)
    local reductionPercent = ((unmitigatedBurst - maxConcurrentStaggered) / unmitigatedBurst) * 100.0

    return {
        unmitigatedBurst = unmitigatedBurst,
        staggeredMaxConcurrent = maxConcurrentStaggered,
        reductionPercent = reductionPercent
    }
end

--- Generates human-readable diagnostic report table
--- @param timeline table
--- @param totalDurationMs number
--- @param status string
--- @return table report
function Nyx.Bootloader.FormatBootReport(timeline, totalDurationMs, status)
    local stagesSummary = {}
    for _, item in ipairs(timeline or {}) do
        stagesSummary[#stagesSummary + 1] = string.format("[%dms] Stage %d (%s): %s",
            item.scheduledOffsetMs or 0,
            item.stage or 0,
            item.stageName or "unknown",
            item.resource or "unknown"
        )
    end

    return {
        status = status or "BOOT_COMPLETE",
        totalResources = #(timeline or {}),
        totalDurationMs = totalDurationMs or 0,
        timeline = timeline or {},
        summary = table.concat(stagesSummary, "\n")
    }
end
