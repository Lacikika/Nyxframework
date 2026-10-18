Config = {}

-- Core Environment & Diagnostics
Config.Debug = false
Config.ServerName = "Nyxframework Civil Server"

-- Routing & Virtual Buckets
Config.DefaultRoutingBucket = 0
Config.VirtualBucketOffset = 1000 -- Character select isolation: 1000 + source
Config.LimboCoords = vector4(0.0, 0.0, -50.0, 0.0)

-- Connection & Authentication Pipeline
Config.Identifiers = {
    requireLicense = true,
    requireHWID = true,
}

Config.BanCard = {
    title = "Nyxframework Access Revoked",
    appealMessage = "If you believe this ban is in error, submit an appeal via our civil registry.",
}

-- High-Performance RPC Engine
Config.RPCTimeout = 5000       -- 5000 ms client/server promise timeout
Config.MaxPayloadSize = 65536  -- 64 KB maximum packet size

Config.RateLimit = {
    capacity = 50,    -- Max burst capacity of tokens
    refillRate = 50,  -- Tokens refilled per second
    actionOnExceed = "kick", -- Action: "kick" or "drop"
    kickReason = "[Nyx-Security] Socket exhaustion detected: RPC rate limit exceeded."
}

-- Player State & Persistence
Config.AutoSaveInterval = 300  -- Debounced flush interval in seconds (5 minutes)
Config.AuditThreshold = 50000  -- Instant audit log & flush trigger for currency >= threshold

Config.DefaultWallets = {
    cash = 500,
    bank = 2500,
    crypto = 0
}

Config.DefaultMetadata = {
    health = 200,
    armor = 0,
    hunger = 100,
    thirst = 100
}

Config.DefaultPermissions = {
    "player"
}
