Config = {}

-- Diagnostics & Debugging
Config.Debug = false

-- Default Container Constraints (Weights in grams: 1000g = 1kg)
Config.Containers = {
    ['player'] = {
        maxWeight = 30000, -- 30 kg
        maxSlots = 40,
    },
    ['drop'] = {
        maxWeight = 100000, -- 100 kg
        maxSlots = 50,
    },
    ['trunk'] = {
        maxWeight = 60000, -- 60 kg
        maxSlots = 50,
    },
    ['glovebox'] = {
        maxWeight = 5000, -- 5 kg
        maxSlots = 10,
    },
    ['stash'] = {
        maxWeight = 250000, -- 250 kg
        maxSlots = 100,
    }
}

-- Mutex Lock Manager
Config.MutexTimeout = 2000 -- 2000 ms lock duration before auto-expiry fail-safe

-- State Persistence & Debouncing
Config.AutoSaveInterval = 60 -- Sync dirty in-memory containers every 60 seconds

-- Spatial World Drops
Config.DropCullDistance = 25.0     -- Maximum range to stream ground drop entities to client
Config.DropInteractDistance = 2.0  -- Interaction range to open or pickup ground loot
Config.DropModel = "prop_paper_bag_small"
Config.DropZOffset = -0.95         -- Vertical placement correction to sit flush on terrain

-- Degradation & Decay Engine
Config.DecayInterval = 300 -- 5 minutes per decay evaluation tick

-- World Item Hologram Placement
Config.Placement = {
    MaxDistance = 6.0,          -- Max placement raycast distance in meters
    MinDistance = 0.5,          -- Minimum placement distance
    RotationStep = 5.0,         -- Rotation delta in degrees per scroll wheel notch
    FineRotationStep = 1.0,     -- Fine rotation delta with Shift held
    HologramAlpha = 180,        -- Ghost entity translucency alpha (0-255)
    GroundSnapZ = -0.95         -- Vertical placement correction to sit flush on terrain
}

-- Keybinds & Interaction
Config.OpenInventoryKey = "TAB"
Config.OpenInventoryCommand = "inventory"
Config.HotbarSlots = 5
