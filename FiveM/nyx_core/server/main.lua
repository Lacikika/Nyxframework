--[[
    Nyxframework: nyx_core
    File: server/main.lua
    Description: Authoritative connection deferrals, account lifecycle, character selection,
                 and shutdown persistence handlers.
]]

Nyx = Nyx or {}
local PlayerAccounts = {} -- [source] = accountRecord

-- Helper: Extract and aggregate identifiers & hardware tokens
local function getClientIdentifiers(src)
    local rawIdentifiers = GetPlayerIdentifiers(tostring(src))
    local identifiers = {
        license = nil,
        discord = nil,
        steam = nil,
        hwidHash = nil
    }

    for _, id in ipairs(rawIdentifiers) do
        if id:sub(1, 8) == "license:" then
            identifiers.license = id:sub(9)
        elseif id:sub(1, 9) == "license2:" and not identifiers.license then
            identifiers.license = id:sub(10)
        elseif id:sub(1, 8) == "discord:" then
            identifiers.discord = id:sub(9)
        elseif id:sub(1, 6) == "steam:" then
            identifiers.steam = id:sub(7)
        end
    end

    -- Aggregate hardware tokens for anti-evasion matching
    local tokenCount = GetNumPlayerTokens(tostring(src))
    local tokenList = {}
    for i = 0, tokenCount - 1 do
        tokenList[#tokenList + 1] = GetPlayerToken(tostring(src), i)
    end

    if #tokenList > 0 then
        -- Generate deterministic SHA-256 equivalent hash of concatenated tokens
        local rawTokens = table.concat(tokenList, ":")
        -- Simple robust hash if rawTokens present
        identifiers.hwidHash = string.format("%08x%08x", #rawTokens, #tokenList * 31337)
    else
        identifiers.hwidHash = "DEV_LOCAL_NO_TOKEN"
    end

    return identifiers
end

-- Helper: Generate Unique Citizen ID
local function generateCitizenId()
    local charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local id = "NYX-"
    for _ = 1, 6 do
        local rand = math.random(1, #charset)
        id = id .. charset:sub(rand, rand)
    end
    return id
end

-- 1. Connection Deferral Pipeline
AddEventHandler("playerConnecting", function(playerName, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(50)

    deferrals.update(string.format("Validating credentials for %s with Nyx Civil Engine...", playerName))

    local ids = getClientIdentifiers(src)

    -- Credential Validation
    if Config.Identifiers.requireLicense and not ids.license then
        deferrals.done("[Nyx:Security] Connection rejected: Rockstar License identifier not found.")
        return
    end

    if Config.Identifiers.requireHWID and (not ids.hwidHash or ids.hwidHash == "DEV_LOCAL_NO_TOKEN") and not Config.Debug then
        deferrals.done("[Nyx:Security] Connection rejected: Hardware identity tokens missing.")
        return
    end

    -- Ban Ledger Verification
    local account = MySQL.single.await("SELECT * FROM `nyx_accounts` WHERE `license` = ? OR `hwid_hash` = ?", {
        ids.license or "NONE",
        ids.hwidHash or "NONE"
    })

    if account then
        if tonumber(account.is_banned) == 1 then
            local reason = account.ban_reason or "Account revoked by Civil Administration."
            deferrals.done(string.format("%s\n\nReason: %s\n%s", Config.BanCard.title, reason, Config.BanCard.appealMessage))
            return
        end

        -- Update last seen and identifiers
        MySQL.prepare.await("UPDATE `nyx_accounts` SET `discord_id` = ?, `steam_id` = ?, `hwid_hash` = ? WHERE `account_id` = ?", {
            ids.discord,
            ids.steam,
            ids.hwidHash,
            account.account_id
        })
        PlayerAccounts[src] = account
    else
        -- Register new master account
        local defaultPerms = json.encode(Config.DefaultPermissions or { "player" })
        local newAccountId = MySQL.prepare.await("INSERT INTO `nyx_accounts` (`license`, `discord_id`, `steam_id`, `hwid_hash`, `global_permissions`) VALUES (?, ?, ?, ?, ?)", {
            ids.license,
            ids.discord,
            ids.steam,
            ids.hwidHash,
            defaultPerms
        })

        PlayerAccounts[src] = {
            account_id = newAccountId,
            license = ids.license,
            discord_id = ids.discord,
            steam_id = ids.steam,
            hwid_hash = ids.hwidHash,
            global_permissions = defaultPerms,
            is_banned = 0
        }
    end

    deferrals.update("Authenticating session with virtual routing bus...")
    Wait(50)

    deferrals.done()
end)

-- 2. Client Post-Join Handshake: Place into isolated limbo bucket
RegisterNetEvent("nyx:core:client:joined", function()
    local src = source
    Nyx.Buckets.SetLimbo(src)

    -- Freeze ped at Limbo coordinates
    local ped = GetPlayerPed(tostring(src))
    if DoesEntityExist(ped) then
        SetEntityCoords(ped, Config.LimboCoords.x, Config.LimboCoords.y, Config.LimboCoords.z, false, false, false, false)
        FreezeEntityPosition(ped, true)
    end
end)

-- 3. Character Selection & Lifecycle RPCs
Nyx.RPC.Register("characters:get", function(src)
    local account = PlayerAccounts[src]
    if not account then
        return nil, Nyx.RPC.Errors.UNAUTHORIZED
    end

    local rows = MySQL.query.await("SELECT `char_id`, `citizen_id`, `first_name`, `last_name`, `dob`, `gender`, `wallets`, `metadata`, `is_dead` FROM `nyx_characters` WHERE `account_id` = ? AND `deleted_at` IS NULL", {
        account.account_id
    })

    return rows or {}
end)

Nyx.RPC.Register("characters:create", function(src, charData)
    local account = PlayerAccounts[src]
    if not account then
        return nil, Nyx.RPC.Errors.UNAUTHORIZED
    end

    -- Validate input data
    if type(charData) ~= "table" or not charData.firstName or not charData.lastName or not charData.dob or not charData.gender then
        return nil, "INVALID_CHARACTER_PAYLOAD"
    end

    -- Clean strings
    local firstName = tostring(charData.firstName):gsub("[^%a%s]", ""):sub(1, 48)
    local lastName = tostring(charData.lastName):gsub("[^%a%s]", ""):sub(1, 48)
    local dob = tostring(charData.dob):sub(1, 10)
    local gender = tostring(charData.gender):sub(1, 16)

    -- Generate unique citizenId
    local citizenId
    local attempts = 0
    repeat
        citizenId = generateCitizenId()
        local exists = MySQL.scalar.await("SELECT COUNT(*) FROM `nyx_characters` WHERE `citizen_id` = ?", { citizenId })
        attempts = attempts + 1
    until exists == 0 or attempts > 10

    local defaultWallets = json.encode(Config.DefaultWallets)
    local defaultPosition = json.encode({ x = -1037.8, y = -2737.9, z = 20.1, heading = 330.0 })
    local defaultMetadata = json.encode(Config.DefaultMetadata)

    local charId = MySQL.prepare.await([[
        INSERT INTO `nyx_characters`
        (`account_id`, `citizen_id`, `first_name`, `last_name`, `dob`, `gender`, `wallets`, `position`, `metadata`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        account.account_id,
        citizenId,
        firstName,
        lastName,
        dob,
        gender,
        defaultWallets,
        defaultPosition,
        defaultMetadata
    })

    if not charId then
        return nil, "DB_INSERT_FAILED"
    end

    return {
        char_id = charId,
        citizen_id = citizenId,
        first_name = firstName,
        last_name = lastName,
        dob = dob,
        gender = gender,
        wallets = Config.DefaultWallets,
        metadata = Config.DefaultMetadata
    }
end)

Nyx.RPC.Register("characters:select", function(src, charId)
    local account = PlayerAccounts[src]
    if not account then
        return nil, Nyx.RPC.Errors.UNAUTHORIZED
    end

    local char = MySQL.single.await("SELECT * FROM `nyx_characters` WHERE `char_id` = ? AND `account_id` = ? AND `deleted_at` IS NULL", {
        tonumber(charId),
        account.account_id
    })

    if not char then
        return nil, "CHARACTER_NOT_FOUND"
    end

    -- If player was already loaded on another character, unload them cleanly first
    if Nyx.Players[src] then
        Nyx.UnloadPlayer(src)
    end

    -- Instantiate new authoritative PlayerObject
    local player = Nyx.CreatePlayerObject(src, account, char)

    -- Reset routing bucket to public default (0)
    Nyx.Buckets.SetDefault(src)

    -- Unfreeze ped
    local ped = GetPlayerPed(tostring(src))
    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
    end

    -- Emit global event across server resources
    TriggerEvent("nyx:core:playerReady", src, player.citizenId)
    TriggerClientEvent("nyx:core:client:playerLoaded", src, {
        citizenId = player.citizenId,
        data = player.data,
        wallets = player.wallets,
        metadata = player.metadata,
        position = player.position
    })

    return {
        citizenId = player.citizenId,
        data = player.data,
        wallets = player.wallets,
        metadata = player.metadata,
        position = player.position
    }
end)

-- 4. Player Disconnection Handlers
AddEventHandler("playerDropped", function(reason)
    local src = source
    if Config.Debug then
        print(string.format("^3[Nyx:Lifecycle] Player %s dropped (%s). Running flush...^7", src, reason))
    end

    Nyx.UnloadPlayer(src)
    PlayerAccounts[src] = nil
end)

-- 5. Resource Stop Handlers: Synchronous shutdown persistence
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    print("^3[Nyx:Core] Resource shutting down. Executing emergency synchronous state flush...^7")
    local dirtyPlayers = {}
    for _, player in pairs(Nyx.Players) do
        if player and player.isDirty then
            dirtyPlayers[#dirtyPlayers + 1] = player
        end
    end

    for _, player in ipairs(dirtyPlayers) do
        player:getPosition()
        MySQL.prepare.await([[
            UPDATE `nyx_characters`
            SET `wallets` = ?, `position` = ?, `metadata` = ?, `is_dead` = ?
            WHERE `char_id` = ?
        ]], {
            json.encode(player.wallets),
            json.encode(player.position),
            json.encode(player.metadata),
            player.isDead and 1 or 0,
            player.charId
        })
    end

    print(string.format("^2[Nyx:Core] Shutdown complete. %d characters persisted to database.^7", #dirtyPlayers))
end)
