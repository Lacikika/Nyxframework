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

-- High-Performance RPC Engine & Zero-Trust Security
Config.RPCTimeout = 5000       -- 5000 ms client/server promise timeout
Config.MaxPayloadSize = 65536  -- 64 KB maximum packet size

Config.RateLimit = {
    enabled = true,
    capacity = 50,           -- Max burst capacity of tokens
    refillRate = 50,         -- Tokens refilled per second (50 req/s)
    defaultCost = 1.0,       -- Default tokens consumed per RPC call
    actionOnExceed = "throttle", -- "throttle" (reject with RATE_LIMITED) or "kick"
    kickOnSustainedFlooding = true, -- Auto-kick if player continues flooding when rate-limited
    maxViolations = 10,      -- Sustained violations required to trigger automatic kick
    violationWindowMs = 5000, -- 5000 ms rolling window for violation decay
    kickReason = "[Nyx-Security] Socket exhaustion detected: RPC rate limit exceeded.",
    routeCosts = {},
    exemptRoutes = {}
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

-- Dynamic Inventory Weight Penalties & Heavy Freight Physics
Config.WeightPenalties = {
    enabled = true,
    defaultPlayerCapacity = 60000,          -- 60 kg baseline player carry capacity (50kg–60kg limit)
    heavyFreightThresholdGrams = 50000,     -- 50 kg threshold: industrial crates > 50kg cannot enter player backpack
    staminaTickIntervalMs = 250,            -- Evaluation interval for extra sprint/run stamina consumption
    tiers = {
        tier_0 = {
            id = 0,
            minRatio = 0.0,
            maxRatio = 0.70,        -- 0% - 70% capacity: unencumbered load
            moveRate = 1.0,         -- Normal movement, zero speed penalty
            sprintAllowed = true,   -- Sprinting permitted
            jumpAllowed = true,     -- Jumping permitted
            climbAllowed = true,    -- Mantling permitted
            staminaDrainMult = 1.0, -- Zero extra stamina drain
            label = "TIER_0"
        },
        tier_1 = {
            id = 1,
            minRatio = 0.70,
            maxRatio = 0.95,        -- 71% - 95% capacity: moderate load
            moveRate = 0.90,        -- -10% sprint speed and movement rate
            sprintAllowed = true,   -- Sprinting permitted with penalty
            jumpAllowed = true,     -- Jumping permitted
            climbAllowed = true,    -- Mantling permitted
            staminaDrainMult = 1.30, -- Slightly increased stamina drain
            label = "TIER_1"
        },
        tier_2 = {
            id = 2,
            minRatio = 0.95,
            maxRatio = math.huge,   -- 96% - 100%+ capacity: overencumbered
            moveRate = 0.80,        -- Fast walking allowed
            sprintAllowed = false,  -- Sprinting disabled
            jumpAllowed = false,    -- Jumping disabled
            climbAllowed = false,   -- Climbing disabled
            staminaDrainMult = 2.00, -- Overencumbered stamina drain
            label = "TIER_2"
        },
        tier_3 = {
            id = 3,
            isHeavyFreight = true,  -- Heavy Industrial Crates (> 50kg)
            moveRate = 0.65,        -- Physical two-handed carry / ground drag rate
            sprintAllowed = false,  -- Sprinting disabled
            jumpAllowed = false,    -- Jumping disabled
            climbAllowed = false,   -- Climbing disabled
            staminaDrainMult = 2.50, -- Heavy crate fatigue
            label = "TIER_3"
        },

        -- Backward compatibility aliases
        normal = {
            maxRatio = 0.70,
            moveRate = 1.0,
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.0,
            label = "TIER_0"
        },
        encumbered = {
            minRatio = 0.70,
            maxRatio = 0.95,
            moveRate = 0.90,
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.30,
            label = "TIER_1"
        },
        heavy = {
            minRatio = 0.70,
            maxRatio = 0.95,
            moveRate = 0.90,
            sprintAllowed = true,
            jumpAllowed = true,
            climbAllowed = true,
            staminaDrainMult = 1.30,
            label = "TIER_1"
        },
        overburdened = {
            minRatio = 0.95,
            maxRatio = math.huge,
            moveRate = 0.80,
            sprintAllowed = false,
            jumpAllowed = false,
            climbAllowed = false,
            staminaDrainMult = 2.00,
            label = "TIER_2"
        },
        critical = {
            minRatio = 0.95,
            maxRatio = math.huge,
            moveRate = 0.80,
            sprintAllowed = false,
            jumpAllowed = false,
            climbAllowed = false,
            staminaDrainMult = 2.00,
            label = "TIER_2"
        }
    }
}

-- Staggered Resource Bootloader Dispatch Configuration
Config.Bootloader = {
    enabled = true,
    staggerDelayMs = 50,         -- 50ms interval between sequential resource initializations
    autoDispatch = true,         -- Automatically begin staggered dispatch when migrations complete
    logToDatabase = true,        -- Persist boot cycle telemetry to nyx_bootloader_logs
    stages = nil                 -- nil uses Nyx.Bootloader.GetDefaultStages()
}

