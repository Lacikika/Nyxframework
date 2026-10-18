--[[
    Nyxframework: nyx_inventory
    File: shared/batch.lua
    Description: Pure Lua 5.4 query planning, chunking, deduplication, and relational
                 item grouping engine for batched container database operations.
]]

Nyx = Nyx or {}
Nyx.Inventory = Nyx.Inventory or {}
Nyx.Inventory.Batch = {}

--- Sanitize and deduplicate a list of container IDs.
--- Trims whitespace, removes non-strings and empty strings, and preserves first-seen order.
--- @param ids table List of raw container ID candidates
--- @return table deduplicatedList Clean list of unique container IDs
--- @return table idSet Lookup set [id] = true
function Nyx.Inventory.Batch.SanitizeContainerIds(ids)
    if type(ids) ~= "table" then
        return {}, {}
    end

    local cleanList = {}
    local idSet = {}

    for _, rawId in ipairs(ids) do
        if type(rawId) == "string" then
            local trimmed = rawId:match("^%s*(.-)%s*$")
            if trimmed and #trimmed > 0 and not idSet[trimmed] then
                idSet[trimmed] = true
                cleanList[#cleanList + 1] = trimmed
            end
        end
    end

    return cleanList, idSet
end

--- Partition container IDs into hot-cache hits (already in memory) and cold-cache misses.
--- @param ids table Clean list of container IDs
--- @param existingMap table Map of currently loaded containers, e.g. Nyx.Inventories
--- @return table hits List of IDs already present in memory
--- @return table misses List of IDs that must be queried from the database
function Nyx.Inventory.Batch.PartitionExisting(ids, existingMap)
    if type(ids) ~= "table" then
        return {}, {}
    end

    local existing = (type(existingMap) == "table") and existingMap or {}
    local hits = {}
    local misses = {}

    for _, id in ipairs(ids) do
        if existing[id] ~= nil then
            hits[#hits + 1] = id
        else
            misses[#misses + 1] = id
        end
    end

    return hits, misses
end

--- Chunk a list of IDs into bounded arrays of maximum size chunkSize.
--- @param ids table Array of IDs
--- @param chunkSize number Maximum items per chunk (default: 50)
--- @return table chunks Array of arrays
function Nyx.Inventory.Batch.ChunkIds(ids, chunkSize)
    if type(ids) ~= "table" then
        return {}
    end

    chunkSize = tonumber(chunkSize) or 50
    if chunkSize < 1 then chunkSize = 50 end

    local chunks = {}
    local currentChunk = {}

    for _, id in ipairs(ids) do
        currentChunk[#currentChunk + 1] = id
        if #currentChunk >= chunkSize then
            chunks[#chunks + 1] = currentChunk
            currentChunk = {}
        end
    end

    if #currentChunk > 0 then
        chunks[#chunks + 1] = currentChunk
    end

    return chunks
end

--- Build a parameterized SQL query plan for batched container and item loading.
--- @param misses table List of container IDs to fetch from database
--- @param chunkSize number Maximum IDs per SQL IN (...) clause (default: 50)
--- @return table plan Table containing chunk query specifications and performance savings
function Nyx.Inventory.Batch.BuildQueryPlan(misses, chunkSize)
    chunkSize = tonumber(chunkSize) or 50
    local chunks = Nyx.Inventory.Batch.ChunkIds(misses, chunkSize)
    local queryChunks = {}

    for i, chunk in ipairs(chunks) do
        local placeholders = {}
        for p = 1, #chunk do
            placeholders[p] = "?"
        end
        local inClause = table.concat(placeholders, ",")

        local headerQuery = string.format("SELECT * FROM `nyx_inventories` WHERE `id` IN (%s)", inClause)
        local itemQuery = string.format("SELECT * FROM `nyx_inventory_items` WHERE `inventory_id` IN (%s) ORDER BY `slot` ASC", inClause)

        queryChunks[i] = {
            chunkIndex = i,
            ids = chunk,
            idCount = #chunk,
            headerQuery = headerQuery,
            headerParams = chunk,
            itemQuery = itemQuery,
            itemParams = chunk
        }
    end

    local totalMisses = #misses
    local expectedSequentialQueries = totalMisses * 2
    local batchedQueries = #chunks * 2
    local queriesSaved = math.max(0, expectedSequentialQueries - batchedQueries)
    local efficiencyRatio = expectedSequentialQueries > 0 and (queriesSaved / expectedSequentialQueries) or 0.0

    return {
        chunks = queryChunks,
        chunkCount = #chunks,
        totalMisses = totalMisses,
        expectedSequentialQueries = expectedSequentialQueries,
        batchedQueries = batchedQueries,
        queriesSaved = queriesSaved,
        efficiencyRatio = math.floor(efficiencyRatio * 10000) / 10000
    }
end

--- Calculate theoretical query round-trip savings.
--- Sequential execution: 2 queries per container (header + items).
--- Batched execution: 2 queries per chunk.
--- @param containerCount number Number of containers to load
--- @param chunkSize number Chunk size (default: 50)
--- @return number sequentialQueries Total queries in sequential model
--- @return number batchedQueries Total queries in batched model
--- @return number queriesSaved Count of eliminated database queries
--- @return number reductionPercentage Percentage reduction in query round-trips
function Nyx.Inventory.Batch.CalculateQuerySavings(containerCount, chunkSize)
    containerCount = math.max(0, tonumber(containerCount) or 0)
    chunkSize = math.max(1, tonumber(chunkSize) or 50)

    if containerCount == 0 then
        return 0, 0, 0, 0.0
    end

    local sequentialQueries = containerCount * 2
    local chunks = math.ceil(containerCount / chunkSize)
    local batchedQueries = chunks * 2
    local queriesSaved = math.max(0, sequentialQueries - batchedQueries)
    local reduction = (queriesSaved / sequentialQueries) * 100.0
    reduction = math.floor(reduction * 100) / 100

    return sequentialQueries, batchedQueries, queriesSaved, reduction
end

--- Group flat relational item rows by their parent inventory ID.
--- @param itemRows table Array of nyx_inventory_items rows
--- @return table grouped [inventory_id] = { itemRow1, itemRow2, ... }
function Nyx.Inventory.Batch.GroupItemsByInventory(itemRows)
    local grouped = {}
    if type(itemRows) ~= "table" then
        return grouped
    end

    for _, row in ipairs(itemRows) do
        local invId = row.inventory_id
        if invId then
            local list = grouped[invId]
            if not list then
                list = {}
                grouped[invId] = list
            end
            list[#list + 1] = row
        end
    end

    return grouped
end

--- Determine whether a container ID represents a known persistent startup container.
--- Recognized prefixes: 'stash:*', 'property:*', or type == 'stash'.
--- @param invId string
--- @return boolean isStartup
function Nyx.Inventory.Batch.IsStartupContainer(invId)
    if type(invId) ~= "string" then
        return false
    end

    if invId:sub(1, 6) == "stash:" then
        return true
    end

    if invId:sub(1, 9) == "property:" then
        return true
    end

    return false
end
