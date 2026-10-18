--[[
    Nyxframework: nyx_inventory
    File: server/state.lua
    Description: Authoritative in-memory container state registry, dynamic metadata degradation,
                 and debounced persistence engine.
]]

Nyx = Nyx or {}
Nyx.Inventory = Nyx.Inventory or {}
Nyx.Inventories = {}       -- [invId] = ContainerObject
Nyx.DirtyInventories = {}  -- [invId] = ContainerObject

local Container = {}
Container.__index = Container

-- Constructor: Instantiate Container
function Nyx.Inventory.NewContainer(id, invType, maxWeight, maxSlots, coords)
    local self = setmetatable({}, Container)

    self.id = tostring(id)
    self.type = tostring(invType or "player")

    local defaults = Config.Containers[self.type] or Config.Containers['player']
    self.maxWeight = tonumber(maxWeight) or defaults.maxWeight or 30000
    self.maxSlots = tonumber(maxSlots) or defaults.maxSlots or 40
    self.coords = coords or nil
    self.items = {}      -- [slotNumber] = itemData
    self.listeners = {}  -- [source] = true
    self.isDirty = false

    Nyx.Inventories[self.id] = self
    return self
end

-- Calculate cumulative weight of all items in container
function Container:getWeight()
    local total = 0
    for _, item in pairs(self.items) do
        if item and item.item_id then
            total = total + Nyx.Items.GetWeight(item.item_id, item.amount or 1)
        end
    end
    return total
end

-- Check if container can accommodate additional weight in grams
function Container:canHoldWeight(additionalWeight)
    return (self:getWeight() + (tonumber(additionalWeight) or 0)) <= self.maxWeight
end

-- Retrieve item at specified slot
function Container:getItem(slot)
    return self.items[tonumber(slot)]
end

-- Set or update item at slot
function Container:setItem(slot, itemData)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > self.maxSlots then return false end

    if itemData then
        itemData.slot = slot
        itemData.inventory_id = self.id
        self.items[slot] = itemData
    else
        self.items[slot] = nil
    end

    self:markDirty()
    self:broadcastDelta("SLOT_UPDATE", { slot = slot, item = self.items[slot] })
    return true
end

-- Remove item from slot
function Container:removeItem(slot)
    return self:setItem(slot, nil)
end

-- Find lowest unused slot index (1 .. maxSlots)
function Container:findFirstEmptySlot()
    for s = 1, self.maxSlots do
        if not self.items[s] then
            return s
        end
    end
    return nil
end

-- Listener tracking for active inventory viewers
function Container:addListener(src)
    self.listeners[tonumber(src)] = true
end

function Container:removeListener(src)
    self.listeners[tonumber(src)] = nil
end

-- Broadcast state delta to all actively open clients
function Container:broadcastDelta(eventType, payload)
    for src, _ in pairs(self.listeners) do
        TriggerClientEvent("nyx:inventory:client:delta", src, self.id, eventType, payload)
    end
end

-- Mark container as modified to queue async DB write
function Container:markDirty()
    self.isDirty = true
    Nyx.DirtyInventories[self.id] = self
end

-- Package snapshot for client NUI transmission
function Container:getSnapshot()
    local itemsList = {}
    for slot, item in pairs(self.items) do
        itemsList[#itemsList + 1] = item
    end

    return {
        id = self.id,
        type = self.type,
        maxWeight = self.maxWeight,
        maxSlots = self.maxSlots,
        currentWeight = self:getWeight(),
        items = itemsList,
        coords = self.coords
    }
end

-- Apply time-based item degradation
function Container:applyDecay(deltaSeconds)
    local hasDecayed = false
    local now = os.time()

    for slot, item in pairs(self.items) do
        if item and type(item.metadata) == "table" and item.metadata.durability then
            local decayRate = tonumber(item.metadata.decayRate) or 0.0
            if decayRate > 0 and item.metadata.durability > 0 then
                local loss = (deltaSeconds / 3600.0) * decayRate * 100.0
                local newDurability = math.max(0.0, math.floor((item.metadata.durability - loss) * 10) / 10)

                if newDurability ~= item.metadata.durability then
                    item.metadata.durability = newDurability
                    hasDecayed = true

                    -- Check spoilage for food/drink
                    local itemDef = Nyx.Items.Get(item.item_id)
                    if itemDef and (itemDef.type == "food" or itemDef.type == "drink") and newDurability <= 0.0 then
                        item.metadata.isSpoiled = true
                    end
                end
            end
        end
    end

    if hasDecayed then
        self:markDirty()
        self:broadcastDelta("DECAY_UPDATE", self:getSnapshot())
    end
end

-- Persist container and items to MySQL asynchronously
function Container:save()
    local queries = {}

    -- 1. Update container header
    queries[#queries + 1] = {
        query = [[
            INSERT INTO `nyx_inventories` (`id`, `type`, `max_weight`, `max_slots`, `coords`)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE `max_weight` = VALUES(`max_weight`), `max_slots` = VALUES(`max_slots`), `coords` = VALUES(`coords`)
        ]],
        values = {
            self.id,
            self.type,
            self.maxWeight,
            self.maxSlots,
            self.coords and json.encode(self.coords) or nil
        }
    }

    -- 2. Clear old item slots and write current state
    queries[#queries + 1] = {
        query = "DELETE FROM `nyx_inventory_items` WHERE `inventory_id` = ?",
        values = { self.id }
    }

    for slot, item in pairs(self.items) do
        if item then
            queries[#queries + 1] = {
                query = [[
                    INSERT INTO `nyx_inventory_items` (`item_uuid`, `inventory_id`, `item_id`, `slot`, `amount`, `metadata`)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]],
                values = {
                    item.item_uuid or Nyx.RPC.GenerateNonce(),
                    self.id,
                    item.item_id,
                    slot,
                    tonumber(item.amount) or 1,
                    type(item.metadata) == "table" and json.encode(item.metadata) or "{}"
                }
            }
        end
    end

    local p = promise.new()
    MySQL.transaction(queries, function(success)
        if success then
            self.isDirty = false
            Nyx.DirtyInventories[self.id] = nil
            p:resolve(true)
        else
            print(string.format("^1[Nyx:Inventory] Failed to persist container '%s'!^7", self.id))
            p:resolve(false)
        end
    end)

    return p
end

-- Helper: Load or Get Container from Memory / DB
function Nyx.Inventory.Get(invId, autoCreateType, defaultCoords)
    if not invId then return nil end

    if Nyx.Inventories[invId] then
        return Nyx.Inventories[invId]
    end

    -- Query Database
    local record = MySQL.single.await("SELECT * FROM `nyx_inventories` WHERE `id` = ?", { invId })

    if not record then
        if not autoCreateType then
            return nil
        end

        local def = Config.Containers[autoCreateType] or Config.Containers['player']
        local newContainer = Nyx.Inventory.NewContainer(invId, autoCreateType, def.maxWeight, def.maxSlots, defaultCoords)
        newContainer:save()
        return newContainer
    end

    -- Parse DB Record
    local coords = nil
    if record.coords and #record.coords > 0 then
        local ok, parsed = pcall(json.decode, record.coords)
        if ok then coords = parsed end
    end

    local container = Nyx.Inventory.NewContainer(record.id, record.type, record.max_weight, record.max_slots, coords)

    -- Load Items
    local itemRows = MySQL.query.await("SELECT * FROM `nyx_inventory_items` WHERE `inventory_id` = ? ORDER BY `slot` ASC", { invId })
    if itemRows then
        for _, row in ipairs(itemRows) do
            local meta = {}
            if row.metadata and #row.metadata > 0 then
                local ok, parsed = pcall(json.decode, row.metadata)
                if ok and type(parsed) == "table" then meta = parsed end
            end

            container.items[tonumber(row.slot)] = {
                item_uuid = row.item_uuid,
                inventory_id = invId,
                item_id = row.item_id,
                slot = tonumber(row.slot),
                amount = tonumber(row.amount) or 1,
                metadata = meta
            }
        end
    end

    return container
end

-- Debounced Batch Flush Thread
CreateThread(function()
    local intervalMs = (Config.AutoSaveInterval or 60) * 1000
    while true do
        Wait(intervalMs)

        local dirty = {}
        for invId, container in pairs(Nyx.DirtyInventories) do
            if container and container.isDirty then
                dirty[#dirty + 1] = container
            end
        end

        if #dirty > 0 then
            if Config.Debug then
                print(string.format("^4[Nyx:Inventory]^7 Syncing %d dirty containers to database...", #dirty))
            end
            for _, container in ipairs(dirty) do
                container:save()
            end
        end
    end
end)

-- Periodic Item Degradation Thread (Active & Online Containers Only)
CreateThread(function()
    local decayMs = (Config.DecayInterval or 300) * 1000
    while true do
        Wait(decayMs)

        for _, container in pairs(Nyx.Inventories) do
            if container then
                -- Only process decay for active world containers or containers with active listeners
                local hasListeners = next(container.listeners) ~= nil
                if container.type ~= "player" or hasListeners then
                    container:applyDecay(Config.DecayInterval or 300)
                end
            end
        end
    end
end)
