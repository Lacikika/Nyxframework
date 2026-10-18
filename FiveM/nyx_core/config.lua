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

-- Dynamic Inventory Weight Penalties on Movement
Config.WeightPenalties = {
    enabled = true,
    staminaTickIntervalMs = 250,    -- Evaluation interval for extra sprint/run stamina consumption
    -- Tiers defined by weightRatio (currentWeight / maxWeight)
    tiers = {
        normal = {
            maxRatio = 0.70,        -- 0% - 70% capacity
            moveRate = 1.0,         -- 100% standard speed
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.0, -- Normal stamina consumption
            label = "NORMAL"
        },
        encumbered = {
            minRatio = 0.70,        -- 70% - 85% capacity
            maxRatio = 0.85,
            moveRate = 0.90,        -- 90% speed
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.35, -- 35% faster stamina burn
            label = "ENCUMBERED"
        },
        heavy = {
            minRatio = 0.85,        -- 85% - 100% capacity
            maxRatio = 1.00,
            moveRate = 0.78,        -- 78% speed
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.85, -- 85% faster stamina burn
            label = "HEAVY"
        },
        overburdened = {
            minRatio = 1.00,        -- 100% - 120% capacity (Exceeding max capacity)
            maxRatio = 1.20,
            moveRate = 0.60,        -- 60% speed
            sprintAllowed = false,  -- Sprinting disabled
            jumpAllowed = false,    -- Jumping disabled
            climbAllowed = true,
            staminaDrainMult = 2.50,
            label = "OVERBURDENED"
        },
        critical = {
            minRatio = 1.20,        -- > 120% capacity (Critical overload)
            moveRate = 0.40,        -- 40% speed (Slow crawl)
            sprintAllowed = false,  -- Sprinting disabled
            jumpAllowed = false,    -- Jumping disabled
            climbAllowed = false,   -- Mantle/climbing disabled
            staminaDrainMult = 3.50,
            cameraShake = true,     -- Heavy load screen sway
            label = "CRITICAL_OVERWEIGHT"
        }
    }
}
