--[[
    Nyxframework: nyx_core
    File: server/migrations.lua
    Description: Automated database schema migration engine with checksum validation.
]]

Nyx = Nyx or {}
Nyx.Database = Nyx.Database or {}

-- Pure Lua 5.4 SHA-256 Implementation (Zero-dependency cryptographic hasher)
local function sha256(str)
    local band, bor, bxor, bnot = function(a, b) return a & b end, function(a, b) return a | b end, function(a, b) return a ~ b end, function(a) return ~a & 0xFFFFFFFF end
    local rshift, lshift = function(a, b) return (a & 0xFFFFFFFF) >> b end, function(a, b) return (a << b) & 0xFFFFFFFF end

    local function ror(x, n)
        return (rshift(x, n) | lshift(x, 32 - n)) & 0xFFFFFFFF
    end

    local K = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    }

    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }

    local len = #str
    local bit_len = len * 8
    local pad = { str:byte(1, len) }
    pad[#pad + 1] = 0x80
    while (#pad % 64) ~= 56 do
        pad[#pad + 1] = 0x00
    end

    for i = 7, 0, -1 do
        pad[#pad + 1] = (bit_len >> (i * 8)) & 0xFF
    end

    local W = {}
    for chunk = 1, #pad, 64 do
        for t = 0, 15 do
            local idx = chunk + t * 4
            W[t] = (lshift(pad[idx], 24) | lshift(pad[idx + 1], 16) | lshift(pad[idx + 2], 8) | pad[idx + 3]) & 0xFFFFFFFF
        end
        for t = 16, 63 do
            local s0 = bxor(bxor(ror(W[t - 15], 7), ror(W[t - 15], 18)), rshift(W[t - 15], 3))
            local s1 = bxor(bxor(ror(W[t - 2], 17), ror(W[t - 2], 19)), rshift(W[t - 2], 10))
            W[t] = (W[t - 16] + s0 + W[t - 7] + s1) & 0xFFFFFFFF
        end

        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

        for t = 0, 63 do
            local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[t + 1] + W[t]) & 0xFFFFFFFF
            local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) & 0xFFFFFFFF

            h = g
            g = f
            f = e
            e = (d + temp1) & 0xFFFFFFFF
            d = c
            c = b
            b = a
            a = (temp1 + temp2) & 0xFFFFFFFF
        end

        H[1] = (H[1] + a) & 0xFFFFFFFF
        H[2] = (H[2] + b) & 0xFFFFFFFF
        H[3] = (H[3] + c) & 0xFFFFFFFF
        H[4] = (H[4] + d) & 0xFFFFFFFF
        H[5] = (H[5] + e) & 0xFFFFFFFF
        H[6] = (H[6] + f) & 0xFFFFFFFF
        H[7] = (H[7] + g) & 0xFFFFFFFF
        H[8] = (H[8] + h) & 0xFFFFFFFF
    end

    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

-- Helper: Split multi-statement SQL strings cleanly by semicolon
local function parseStatements(sql)
    local statements = {}
    local current = {}
    local inString = false
    local stringChar = nil
    local inLineComment = false
    local inBlockComment = false
    local inLuaBlockComment = false

    local i = 1
    local len = #sql
    while i <= len do
        local c = sql:sub(i, i)
        local next_c = sql:sub(i + 1, i + 1)

        if inLineComment then
            if c == "\n" then
                inLineComment = false
            end
        elseif inBlockComment then
            if c == "*" and next_c == "/" then
                inBlockComment = false
                i = i + 1
            end
        elseif inLuaBlockComment then
            if c == "]" and next_c == "]" then
                inLuaBlockComment = false
                i = i + 1
            end
        elseif inString then
            current[#current + 1] = c
            if c == "\\" then
                i = i + 1
                if i <= len then
                    current[#current + 1] = sql:sub(i, i)
                end
            elseif c == stringChar then
                inString = false
                stringChar = nil
            end
        else
            if c == "-" and next_c == "-" then
                if sql:sub(i + 2, i + 3) == "[[" then
                    inLuaBlockComment = true
                    i = i + 3
                else
                    inLineComment = true
                    i = i + 1
                end
            elseif c == "#" then
                inLineComment = true
            elseif c == "/" and next_c == "*" then
                inBlockComment = true
                i = i + 1
            elseif c == "'" or c == '"' or c == "`" then
                inString = true
                stringChar = c
                current[#current + 1] = c
            elseif c == ";" then
                local stmt = table.concat(current):match("^%s*(.-)%s*$")
                if stmt and #stmt > 0 then
                    statements[#statements + 1] = stmt
                end
                current = {}
            else
                current[#current + 1] = c
            end
        end
        i = i + 1
    end

    local lastStmt = table.concat(current):match("^%s*(.-)%s*$")
    if lastStmt and #lastStmt > 0 then
        statements[#statements + 1] = lastStmt
    end

    return statements
end

-- Migration Runner Core
local function runMigrations()
    print("^4[Nyx:Migration]^7 Initializing automated schema engine...")

    -- Ensure tracking table exists
    local trackingSchema = [[
        CREATE TABLE IF NOT EXISTS `nyx_migrations` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `filename` VARCHAR(255) NOT NULL UNIQUE,
            `checksum` VARCHAR(64) NOT NULL,
            `executed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
    MySQL.query.await(trackingSchema)

    -- Load migration manifest index
    local resourceName = GetCurrentResourceName()
    local indexRaw = LoadResourceFile(resourceName, "sql/migrations/index.json")
    local migrationList = {}

    if indexRaw then
        local ok, parsed = pcall(json.decode, indexRaw)
        if ok and type(parsed) == "table" then
            migrationList = parsed
        end
    end

    -- Fallback list if index.json is empty or unparseable
    if #migrationList == 0 then
        migrationList = {
            "001_initial_kernel.sql"
        }
    end

    -- Fetch already executed migrations
    local executedRows = MySQL.query.await("SELECT `filename`, `checksum` FROM `nyx_migrations`")
    local executedMap = {}
    if executedRows then
        for _, row in ipairs(executedRows) do
            executedMap[row.filename] = row.checksum
        end
    end

    local appliedCount = 0

    for _, filename in ipairs(migrationList) do
        local filePath = "sql/migrations/" .. filename
        local fileContent = LoadResourceFile(resourceName, filePath)

        if not fileContent then
            print(string.format("^1[Nyx:Migration] ERROR: Migration file '%s' not found!^7", filePath))
        else
            local fileChecksum = sha256(fileContent)
            local existingChecksum = executedMap[filename]

            if existingChecksum then
                if existingChecksum ~= fileChecksum then
                    print(string.format("^3[Nyx:Migration] WARNING: Checksum mismatch in executed migration '%s'! (DB: %s | File: %s)^7", filename, existingChecksum, fileChecksum))
                end
            else
                print(string.format("^4[Nyx:Migration]^7 Applying migration: ^3%s^7 [hash: %s]...", filename, fileChecksum:sub(1, 8)))
                local statements = parseStatements(fileContent)
                local queries = {}

                for _, stmt in ipairs(statements) do
                    queries[#queries + 1] = {
                        query = stmt
                    }
                end

                queries[#queries + 1] = {
                    query = "INSERT INTO `nyx_migrations` (`filename`, `checksum`) VALUES (?, ?)",
                    values = { filename, fileChecksum }
                }

                local success = MySQL.transaction.await(queries)
                if success then
                    print(string.format("^2[Nyx:Migration] Successfully applied migration: %s^7", filename))
                    appliedCount = appliedCount + 1
                    executedMap[filename] = fileChecksum
                else
                    error(string.format("[Nyx:Migration] FATAL: Failed to apply migration transaction '%s'! Halting boot.", filename))
                end
            end
        end
    end

    print(string.format("^2[Nyx:Migration]^7 Schema verification complete. (%d applied, %d verified)^7", appliedCount, #migrationList - appliedCount))
end

-- Hook into oxmysql readiness
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    MySQL.ready(function()
        local ok, err = pcall(runMigrations)
        if not ok then
            print(string.format("^1[Nyx:Migration] Fatal exception during migrations: %s^7", tostring(err)))
        else
            if Nyx.Bootloader and Nyx.Bootloader.OnDatabaseReady then
                Nyx.Bootloader.OnDatabaseReady()
            else
                TriggerEvent("nyx:core:dbReady")
                TriggerClientEvent("nyx:core:client:dbReady", -1)
            end
        end
    end)
end)
