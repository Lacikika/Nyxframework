--[[
    Nyxframework: nyx_vehicles
    File: config.lua
    Description: Configuration for persistent vehicle lifecycle, trunk/glovebox capacities,
                 fuel profiles, and physical access rules.
]]

Config = {}

Config.Debug = false

-- Storage Capacities by Vehicle Class (Weight in grams, 1000g = 1kg)
Config.StorageByClass = {
    [0]  = { label = "Compacts",        trunkWeight = 45000,  trunkSlots = 35,  gloveWeight = 5000, gloveSlots = 10 },
    [1]  = { label = "Sedans",          trunkWeight = 55000,  trunkSlots = 40,  gloveWeight = 5000, gloveSlots = 10 },
    [2]  = { label = "SUVs",            trunkWeight = 85000,  trunkSlots = 50,  gloveWeight = 6000, gloveSlots = 12 },
    [3]  = { label = "Coupes",          trunkWeight = 40000,  trunkSlots = 30,  gloveWeight = 5000, gloveSlots = 8 },
    [4]  = { label = "Muscle",          trunkWeight = 45000,  trunkSlots = 35,  gloveWeight = 5000, gloveSlots = 8 },
    [5]  = { label = "Sports Classics", trunkWeight = 35000,  trunkSlots = 25,  gloveWeight = 4000, gloveSlots = 8 },
    [6]  = { label = "Sports",          trunkWeight = 30000,  trunkSlots = 25,  gloveWeight = 4000, gloveSlots = 8 },
    [7]  = { label = "Super",           trunkWeight = 20000,  trunkSlots = 15,  gloveWeight = 3000, gloveSlots = 6 },
    [8]  = { label = "Motorcycles",     trunkWeight = 15000,  trunkSlots = 10,  gloveWeight = 2000, gloveSlots = 4 },
    [9]  = { label = "Off-road",        trunkWeight = 75000,  trunkSlots = 45,  gloveWeight = 5000, gloveSlots = 10 },
    [10] = { label = "Industrial",      trunkWeight = 300000, trunkSlots = 80,  gloveWeight = 10000, gloveSlots = 15 },
    [11] = { label = "Utility",         trunkWeight = 150000, trunkSlots = 60,  gloveWeight = 8000, gloveSlots = 12 },
    [12] = { label = "Vans",            trunkWeight = 180000, trunkSlots = 70,  gloveWeight = 7000, gloveSlots = 12 },
    [20] = { label = "Commercial",      trunkWeight = 500000, trunkSlots = 100, gloveWeight = 10000, gloveSlots = 20 }
}

-- Default Fallback Storage
Config.DefaultStorage = {
    trunkWeight = 50000,
    trunkSlots = 40,
    gloveWeight = 5000,
    gloveSlots = 10
}

-- Fuel Consumption Mechanics
Config.Fuel = {
    DefaultTankCapacity = 65.0,  -- Liters
    IdleBurnPerMinute = 0.02,    -- Liters per minute idling
    DriveBurnMultiplier = 0.12,  -- Liters consumed per acceleration unit
    SyncIntervalSeconds = 15     -- Synchronize fuel to server every 15s when active
}

-- Physical Access & Lock Controls
Config.Access = {
    KeyFobRange = 8.0,           -- Maximum distance for remote digital key fob
    TrunkBoneDistance = 2.0,     -- Distance to rear boot bone to open trunk
    GloveboxDistance = 1.6,      -- Distance to dashboard / front seat
    KeyItem = "car_keys",        -- Physical key item identifier in nyx_inventory
    KeyBones = {
        trunk = { "boot", "trunk", "rearbump" },
        glovebox = { "dash", "seat_dside_f", "seat_pside_f" }
    }
}

-- State Persistence & Debouncing
Config.Persistence = {
    DamageFlushInterval = 30,    -- Debounced DB write batch interval in seconds
    AutoDespawnAbandoned = 3600  -- Despawn empty untouched vehicles after 1 hour
}

-- Public Municipal Garages
Config.Garages = {
    ['legion_square'] = {
        label = "Legion Square Public Garage",
        coords = vector3(215.5, -805.0, 30.8),
        spawnPoint = vector4(228.0, -800.0, 30.5, 65.0)
    },
    ['pillbox_hill'] = {
        label = "Pillbox Hill Parking Complex",
        coords = vector3(336.0, -565.0, 28.7),
        spawnPoint = vector4(342.0, -570.0, 28.7, 250.0)
    },
    ['sandy_shores'] = {
        label = "Sandy Shores Civic Lot",
        coords = vector3(1878.0, 3752.0, 33.0),
        spawnPoint = vector4(1870.0, 3755.0, 33.0, 120.0)
    },
    ['paleto_bay'] = {
        label = "Paleto Bay Boulevard Garage",
        coords = vector3(-118.0, 6520.0, 31.8),
        spawnPoint = vector4(-125.0, 6525.0, 31.8, 45.0)
    }
}

-- Vehicle Mileage & Component Wear System
Config.Wear = {
    SyncIntervalSeconds = 15,          -- Telemetry push interval in seconds
    MaxSpeedKmhSanity = 450.0,         -- Maximum plausibility threshold to prevent teleport spoofing
    
    -- Consumption & Degradation Rates
    OilDegradationPerKm = 0.04,        -- Oil quality drops ~4% per 100 km under normal driving
    OilRpmMultiplier = 2.5,            -- Multiplier when redlining (>0.85 engine RPM)
    BrakeWearPerBrakeSecond = 0.006,   -- Brake pad loss per second of active braking
    BrakeHardStopMultiplier = 1.8,     -- Multiplier for emergency/hard braking (>80 km/h)
    TransmissionWearPerShift = 0.002,  -- Wear on transmission gears per gear shift
    TransmissionBurnoutPenalty = 0.015,-- Instant wear on aggressive burnouts
    SuspensionWearPerKm = 0.025,       -- Normal road suspension wear per km
    SuspensionOffroadMultiplier = 3.5, -- Extra wear multiplier on dirt/gravel/offroad surfaces

    -- Warning & Failure Thresholds (Percentages 0.0 - 100.0)
    WarningThreshold = 20.0,           -- Triggers HUD check engine / maintenance warning
    CriticalThreshold = 10.0,          -- Triggers severe mechanical degradation symptoms

    -- Physical Degradation Penalties
    Degradation = {
        EnableEngineSmokeOnCriticalOil = true,
        EngineDamageRateCriticalOil = 0.75,     -- Damage per tick applied to engine health when oil <= 5.0%
        ReducedBrakeForceMultiplier = 0.45,     -- Brake multiplier when brake pads <= 10.0%
        TransmissionSlipChance = 0.15,          -- Chance per second for gear slipping when transmission <= 15.0%
        SuspensionInstability = true            -- Adds slight body wobble / instability when suspension <= 15.0%
    },

    -- Maintenance & Servicing
    ServiceCosts = {
        oil_change = 150.00,
        brake_replacement = 350.00,
        transmission_overhaul = 850.00,
        suspension_tune = 400.00,
        full_inspection = 100.00
    },
    ServiceRequiredItem = "tool_repairkit" -- Required item if performing manual field repairs
}

