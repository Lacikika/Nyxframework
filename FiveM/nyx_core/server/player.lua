--[[
    Nyxframework: nyx_core
    File: server/player.lua
    Description: In-memory PlayerObject state registry with debounced dirty-state DB flush.
]]

Nyx = Nyx or {}
Nyx.Players = {}         -- Keyed by source: [source] = PlayerObject
Nyx.CitizenLookup = {}   -- Keyed by citizen_id: [citizen_id] = source
Nyx.DirtyCharacters = {} -- Keyed by charId: [charId] = PlayerObject

local PlayerObject = {}
PlayerObject.__index = PlayerObject

-- Log an action to the persistent nyx_audit_log table
local function recordAuditLog(citizenId, action, payload, ipAddress)
    CreateThread(function()
        local ok, encoded = pcall(json.encode, payload or {})
        local safePayload = ok and encoded or "{}"
        MySQL.prepare("INSERT INTO `nyx_audit_log` (`citizen_id`, `action`, `payload`, `ip_address`) VALUES (?, ?, ?, ?)", {
            citizenId,
            action,
            safePayload,
            ipAddress or "127.0.0.1"
        })
    end)
end

-- Constructor: Instantiate a PlayerObject
function Nyx.CreatePlayerObject(src, accountData, charData)
    local self = setmetatable({}, PlayerObject)

    self.source = tonumber(src)
    self.accountId = tonumber(accountData.account_id)
    self.charId = tonumber(charData.char_id)
    self.citizenId = tostring(charData.citizen_id)

    self.data = {
        firstName = charData.first_name or "Unknown",
        lastName = charData.last_name or "Citizen",
        dob = charData.dob or "2000-01-01",
        gender = charData.gender or "unspecified"
    }

    -- Parse JSON fields safely
    local function parseJson(input, default)
        if type(input) == "table" then return input end
        if type(input) == "string" and #input > 0 then
            local ok, res = pcall(json.decode, input)
            if ok and type(res) == "table" then return res end
        end
        return default
    end

    self.wallets = parseJson(charData.wallets, {
        cash = Config.DefaultWallets.cash or 500,
        bank = Config.DefaultWallets.bank or 2500,
        crypto = Config.DefaultWallets.crypto or 0
    })

    self.position = parseJson(charData.position, {
        x = 0.0, y = 0.0, z = 70.0, heading = 0.0
    })

    self.metadata = parseJson(charData.metadata, {
        health = Config.DefaultMetadata.health or 200,
        armor = Config.DefaultMetadata.armor or 0,
        hunger = Config.DefaultMetadata.hunger or 100,
        thirst = Config.DefaultMetadata.thirst or 100
    })

    local permissionsList = parseJson(accountData.global_permissions, Config.DefaultPermissions or { "player" })
    self.permissions = {}
    for _, node in ipairs(permissionsList) do
        self.permissions[node] = true
    end

    self.isDead = (tonumber(charData.is_dead) == 1)
    self.isDirty = false

    -- Register in global fast-lookup tables
    Nyx.Players[self.source] = self
    Nyx.CitizenLookup[self.citizenId] = self.source

    return self
end

-- Mark character as dirty to schedule DB sync
function PlayerObject:markDirty()
    self.isDirty = true
    Nyx.DirtyCharacters[self.charId] = self
end

-- Currency Operations: Authoritative with underflow & race-condition protection
function PlayerObject:getWallet(walletType)
    return self.wallets[walletType] or 0
end

function PlayerObject:addMoney(walletType, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    self.wallets[walletType] = (self.wallets[walletType] or 0) + amount
    self:markDirty()

    -- Trigger client UI wallet refresh
    TriggerClientEvent("nyx:core:client:walletUpdated", self.source, walletType, self.wallets[walletType], amount, reason)

    -- Audit high-value transactions immediately
    if amount >= (Config.AuditThreshold or 50000) then
        local ip = GetPlayerEndpoint(tostring(self.source)) or "0.0.0.0"
        recordAuditLog(self.citizenId, "MONEY_CREDIT_HIGH", {
            wallet = walletType,
            amount = amount,
            balance = self.wallets[walletType],
            reason = reason
        }, ip)
        self:save()
    end

    return true
end

function PlayerObject:removeMoney(walletType, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local currentBalance = self.wallets[walletType] or 0
    if currentBalance < amount then
        return false -- Insufficient funds: balance never permitted below zero
    end

    self.wallets[walletType] = currentBalance - amount
    self:markDirty()

    -- Trigger client UI wallet refresh
    TriggerClientEvent("nyx:core:client:walletUpdated", self.source, walletType, self.wallets[walletType], -amount, reason)

    -- Audit high-value transactions immediately
    if amount >= (Config.AuditThreshold or 50000) then
        local ip = GetPlayerEndpoint(tostring(self.source)) or "0.0.0.0"
        recordAuditLog(self.citizenId, "MONEY_DEBIT_HIGH", {
            wallet = walletType,
            amount = amount,
            balance = self.wallets[walletType],
            reason = reason
        }, ip)
        self:save()
    end

    return true
end

-- Metadata Operations
function PlayerObject:getMetadata(key)
    if not key then return self.metadata end
    return self.metadata[key]
end

function PlayerObject:setMetadata(key, value)
    if type(key) ~= "string" then return end
    self.metadata[key] = value
    self:markDirty()

    TriggerClientEvent("nyx:core:client:metadataUpdated", self.source, key, value)
end

-- Position & Coordinates
function PlayerObject:getPosition()
    local ped = GetPlayerPed(tostring(self.source))
    if DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        self.position = { x = coords.x, y = coords.y, z = coords.z, heading = heading }
    end
    return self.position
end

function PlayerObject:setPosition(coords)
    if type(coords) == "vector3" or type(coords) == "vector4" then
        self.position = { x = coords.x, y = coords.y, z = coords.z, heading = coords.w or 0.0 }
    elseif type(coords) == "table" then
        self.position = coords
    end
    self:markDirty()
end

-- Permissions & RBAC
function PlayerObject:hasPermission(node)
    if self.permissions["root"] or self.permissions["admin"] then
        return true
    end
    return self.permissions[node] == true
end

function PlayerObject:addPermission(node)
    self.permissions[node] = true
    self:markDirty()
end

function PlayerObject:removePermission(node)
    self.permissions[node] = nil
    self:markDirty()
end

-- Single Player Save (Prepared asynchronous DB update)
function PlayerObject:save()
    self:getPosition() -- Update current ped coords before persisting

    local walletsJson = json.encode(self.wallets)
    local positionJson = json.encode(self.position)
    local metadataJson = json.encode(self.metadata)
    local isDeadInt = self.isDead and 1 or 0

    local query = [[
        UPDATE `nyx_characters`
        SET `wallets` = ?,
            `position` = ?,
            `metadata` = ?,
            `is_dead` = ?
        WHERE `char_id` = ?
    ]]

    local p = promise.new()
    MySQL.prepare(query, {
        walletsJson,
        positionJson,
        metadataJson,
        isDeadInt,
        self.charId
    }, function(affectedRows)
        self.isDirty = false
        Nyx.DirtyCharacters[self.charId] = nil
        p:resolve(affectedRows > 0)
    end)

    return p
end

-- Unload player from memory
function Nyx.UnloadPlayer(src)
    local player = Nyx.Players[src]
    if not player then return end

    -- Save dirty state immediately
    if player.isDirty then
        player:save()
    end

    Nyx.CitizenLookup[player.citizenId] = nil
    Nyx.DirtyCharacters[player.charId] = nil
    Nyx.Players[src] = nil
end

-- Global Helper Getters
function Nyx.GetPlayer(src)
    return Nyx.Players[tonumber(src)]
end

function Nyx.GetPlayerByCitizenId(citizenId)
    local src = Nyx.CitizenLookup[tostring(citizenId)]
    if src then
        return Nyx.Players[src]
    end
    return nil
end

function Nyx.GetPlayers()
    return Nyx.Players
end

-- Debounced Batch Flush Engine (Detached thread every Config.AutoSaveInterval seconds)
CreateThread(function()
    local intervalMs = (Config.AutoSaveInterval or 300) * 1000
    while true do
        Wait(intervalMs)

        local dirtyList = {}
        for charId, player in pairs(Nyx.DirtyCharacters) do
            if player and player.isDirty then
                dirtyList[#dirtyList + 1] = player
            end
        end

        if #dirtyList > 0 then
            if Config.Debug then
                print(string.format("^4[Nyx:State]^7 Flushing %d dirty characters to persistent storage...", #dirtyList))
            end

            local queries = {}
            for _, player in ipairs(dirtyList) do
                player:getPosition()
                queries[#queries + 1] = {
                    query = "UPDATE `nyx_characters` SET `wallets` = ?, `position` = ?, `metadata` = ?, `is_dead` = ? WHERE `char_id` = ?",
                    values = {
                        json.encode(player.wallets),
                        json.encode(player.position),
                        json.encode(player.metadata),
                        player.isDead and 1 or 0,
                        player.charId
                    }
                }
            end

            MySQL.transaction(queries, function(success)
                if success then
                    for _, player in ipairs(dirtyList) do
                        player.isDirty = false
                        Nyx.DirtyCharacters[player.charId] = nil
                    end
                    if Config.Debug then
                        print(string.format("^2[Nyx:State] Debounced flush successful (%d records updated).^7", #dirtyList))
                    end
                else
                    print("^1[Nyx:State] ERROR: Debounced transaction flush failed!^7")
                end
            end)
        end
    end
end)
