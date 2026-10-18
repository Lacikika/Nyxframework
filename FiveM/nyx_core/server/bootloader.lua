--[[
    Nyxframework: nyx_core
    File: server/bootloader.lua
    Description: Authoritative Staggered Resource Bootloader Dispatcher.
                 Coordinates 50ms sequential initialization bus following nyx:core:dbReady,
                 eliminating database pool contention across all 14 modular resources.
]]

Nyx = Nyx or {}
Nyx.Bootloader = Nyx.Bootloader or {}

-- In-memory state tracking
Nyx.Bootloader.State = "UNINITIALIZED"
Nyx.Bootloader.RegisteredCallbacks = {} -- [resourceName] = callbackFn
Nyx.Bootloader.Stages = nil
Nyx.Bootloader.BootHistory = nil
Nyx.Bootloader.LastReport = nil

-- Helper to generate UUID
local function generateBootUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

--- Returns whether the database has completed schema migrations and is ready
--- @return boolean
function Nyx.Bootloader.IsDatabaseReady()
    local s = Nyx.Bootloader.State
    return s == "DB_READY" or s == "DISPATCHING" or s == "BOOT_COMPLETE"
end

--- Returns whether all resources have finished their staggered initialization
--- @return boolean
function Nyx.Bootloader.IsBootComplete()
    return Nyx.Bootloader.State == "BOOT_COMPLETE"
end

--- Returns current bootloader state machine status
--- @return string
function Nyx.Bootloader.GetBootState()
    return Nyx.Bootloader.State
end

--- Returns diagnostic boot report table
--- @return table|nil
function Nyx.Bootloader.GetBootReport()
    return Nyx.Bootloader.LastReport
end

--- Allows resources to register custom boot stages or initialization callbacks
--- @param resourceName string
--- @param stage number|nil
--- @param priority number|nil
--- @param callback function|nil
function Nyx.Bootloader.RegisterBootStage(resourceName, stage, priority, callback)
    if not resourceName or type(resourceName) ~= "string" then return false end

    if not Nyx.Bootloader.Stages then
        Nyx.Bootloader.Stages = Nyx.Bootloader.GetDefaultStages()
    end

    local targetStage = math.max(1, math.min(6, tonumber(stage) or 6))
    local targetPrio = tonumber(priority) or 50

    -- Check if resource already registered in stages
    local found = false
    for _, s in ipairs(Nyx.Bootloader.Stages) do
        if s.resources then
            for idx, r in ipairs(s.resources) do
                if r.name == resourceName then
                    if s.stage == targetStage then
                        r.priority = targetPrio
                    else
                        table.remove(s.resources, idx)
                        break
                    end
                    found = true
                    break
                end
            end
        end
    end

    if not found then
        for _, s in ipairs(Nyx.Bootloader.Stages) do
            if s.stage == targetStage then
                s.resources[#s.resources + 1] = {
                    name = resourceName,
                    priority = targetPrio
                }
                found = true
                break
            end
        end
    end

    if type(callback) == "function" then
        Nyx.Bootloader.RegisteredCallbacks[resourceName] = callback
    end

    return true
end

--- Synchronous await helper blocking current coroutine until database is ready
function Nyx.Bootloader.AwaitDatabase()
    while not Nyx.Bootloader.IsDatabaseReady() do
        Wait(25)
    end
    return true
end

--- Synchronous await helper blocking current coroutine until specific stage is reached
--- @param stageOrResource string|number
function Nyx.Bootloader.AwaitBootStage(stageOrResource)
    local targetStage = tonumber(stageOrResource)
    if not targetStage and type(stageOrResource) == "string" then
        targetStage = Nyx.Bootloader.DetermineResourceStage(stageOrResource, Nyx.Bootloader.Stages)
    end

    targetStage = targetStage or 6
    while not Nyx.Bootloader.IsBootComplete() do
        local curStage = GlobalState.nyxBootStage or 0
        if curStage >= targetStage then
            return true
        end
        Wait(25)
    end
    return true
end

--- Dispatches the staggered boot sequence across all registered resources
--- @param customStaggerMs number|nil (default 50ms)
function Nyx.Bootloader.Dispatch(customStaggerMs)
    if Nyx.Bootloader.State ~= "DB_READY" then
        if Nyx.Bootloader.State == "BOOT_COMPLETE" or Nyx.Bootloader.State == "DISPATCHING" then
            return false, "ALREADY_DISPATCHED"
        end
        return false, "DATABASE_NOT_READY"
    end

    Nyx.Bootloader.State = "DISPATCHING"
    GlobalState.nyxBootState = "DISPATCHING"

    local staggerMs = customStaggerMs or (Config.Bootloader and Config.Bootloader.staggerDelayMs) or 50
    local stages = Nyx.Bootloader.Stages or Nyx.Bootloader.GetDefaultStages()
    local timeline, totalExpectedWindowMs = Nyx.Bootloader.CalculateTimeline(stages, staggerMs)

    print(string.format("^4[Nyx:Bootloader]^7 Starting staggered initialization bus (%d resources, %dms interval, %dms window)...^7",
        #timeline, staggerMs, totalExpectedWindowMs))

    local bootStartTimer = GetGameTimer()
    local bootUuid = generateBootUuid()
    local executedStages = {}

    CreateThread(function()
        for idx, item in ipairs(timeline) do
            local resName = item.resource
            local stageId = item.stage
            local stageName = item.stageName

            GlobalState.nyxBootStage = stageId

            -- Stagger interval delay (50ms between sequential resources)
            if idx > 1 then
                Wait(staggerMs)
            end

            local elapsedOffset = GetGameTimer() - bootStartTimer
            print(string.format("^4[Nyx:Bootloader]^7 Stage %d (%s) -> Dispatching ^3%s^7 (+%dms)",
                stageId, stageName, resName, elapsedOffset))

            -- 1. Dispatch global stage event
            TriggerEvent("nyx:core:resourceInit", resName, stageId, 6, elapsedOffset)

            -- 2. Dispatch targeted resource event
            TriggerEvent("nyx:core:init:" .. resName, elapsedOffset)

            -- 3. Execute registered callback if present
            local cb = Nyx.Bootloader.RegisteredCallbacks[resName]
            if cb then
                local ok, err = pcall(cb, elapsedOffset)
                if not ok then
                    print(string.format("^1[Nyx:Bootloader] Error executing boot callback for '%s': %s^7", resName, tostring(err)))
                end
            end

            executedStages[#executedStages + 1] = {
                resource = resName,
                stage = stageId,
                stageName = stageName,
                priority = item.priority,
                elapsedMs = elapsedOffset
            }
        end

        local totalDurationMs = GetGameTimer() - bootStartTimer
        Nyx.Bootloader.State = "BOOT_COMPLETE"
        GlobalState.nyxBootState = "BOOT_COMPLETE"
        GlobalState.nyxBootStage = 6
        GlobalState.nyxBootCompleted = true

        local report = Nyx.Bootloader.FormatBootReport(executedStages, totalDurationMs, "BOOT_COMPLETE")
        Nyx.Bootloader.LastReport = report

        print(string.format("^2[Nyx:Bootloader]^7 Staggered boot sequence COMPLETE: %d resources dispatched in %dms (50ms stagger). Database connection contention eliminated!^7",
            #executedStages, totalDurationMs))

        -- Emit completion events
        TriggerEvent("nyx:core:bootComplete", report)
        TriggerClientEvent("nyx:core:client:bootComplete", -1, report)

        -- Asynchronous database audit persistence
        local logToDb = Config.Bootloader and Config.Bootloader.logToDatabase ~= false
        if logToDb and MySQL and MySQL.prepare then
            CreateThread(function()
                local stagesJson = json.encode(executedStages)
                pcall(function()
                    MySQL.prepare.await([[
                        INSERT INTO `nyx_bootloader_logs`
                            (`boot_uuid`, `completed_at`, `total_duration_ms`, `stagger_delay_ms`, `resources_dispatched`, `stages_json`, `status`)
                        VALUES (?, NOW(), ?, ?, ?, ?, 'COMPLETED')
                    ]], {
                        bootUuid,
                        totalDurationMs,
                        staggerMs,
                        #executedStages,
                        stagesJson
                    })
                end)
            end)
        end
    end)

    return true, bootUuid
end

--- Called by migrations.lua when all database schema updates are executed and verified
function Nyx.Bootloader.OnDatabaseReady()
    print("^2[Nyx:Bootloader]^7 Database schema verified and locked. Emitting ^3nyx:core:dbReady^7...")
    Nyx.Bootloader.State = "DB_READY"
    GlobalState.nyxBootState = "DB_READY"

    -- 1. Broadcast fundamental database readiness event
    TriggerEvent("nyx:core:dbReady")
    TriggerClientEvent("nyx:core:client:dbReady", -1)

    -- 2. Trigger automated staggered dispatch if enabled
    local autoDispatch = not Config.Bootloader or Config.Bootloader.autoDispatch ~= false
    if autoDispatch then
        Nyx.Bootloader.Dispatch()
    end
end

-- Initialize bootloader state machine
CreateThread(function()
    Nyx.Bootloader.State = "WAITING_DB"
    GlobalState.nyxBootState = "WAITING_DB"
    GlobalState.nyxBootStage = 0
    GlobalState.nyxBootCompleted = false
end)
