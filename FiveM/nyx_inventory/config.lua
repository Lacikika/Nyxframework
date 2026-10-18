Config = {}

-- Diagnostics & Debugging
Config.Debug = false

-- Default Container Constraints (Weights in grams: 1000g = 1kg)
Config.Containers = {
    ['player'] = {
        maxWeight = 60000, -- 60 kg expanded baseline carry capacity (50kg-60kg limit)
        maxSlots = 40,
    },
    ['drop'] = {
        maxWeight = 100000, -- 100 kg
        maxSlots = 50,
    },
    ['trunk'] = {
        maxWeight = 120000, -- 120 kg
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

-- Heavy Freight Threshold & Two-Handed Physical Carry Settings
Config.HeavyFreightThreshold = 50000 -- 50 kg: industrial crates > 50kg cannot enter player backpack
Config.HeavyCarry = {
    Enabled = true,
    AnimDict = "anim@heists@box_carry@",
    AnimName = "idle",
    BoneIndex = 60309,
    AttachOffset = { x = 0.0, y = 0.40, z = -0.15 },
    AttachRot = { x = 0.0, y = 0.0, z = 0.0 },
    InteractDistance = 2.5,
    DropPlaceDistance = 3.5,
    VehicleTrunkDistance = 4.0
}

-- Mutex Lock Manager
Config.MutexTimeout = 2000 -- 2000 ms lock duration before auto-expiry fail-safe

-- State Persistence & Debouncing
Config.AutoSaveInterval = 60 -- Sync dirty in-memory containers every 60 seconds

-- Spatial World Drops & Auto-Merge Engine
Config.DropCullDistance = 25.0     -- Maximum range to stream ground drop entities to client
Config.DropInteractDistance = 2.0  -- Interaction range to open or pickup ground loot
Config.DropModel = "prop_paper_bag_small"
Config.DropZOffset = -0.95         -- Vertical placement correction to sit flush on terrain
Config.DropAutoMergeDistance = 1.5 -- Maximum radius (meters) to auto-merge dropped items or containers

-- Weight-Tiered & Category-Aware Smart Fallback Models
Config.DropFallbackModels = {
    categories = {
        medical = {
            { maxWeight = 2000, model = "prop_ld_health_pack" },
            { maxWeight = math.huge, model = "prop_med_box_01b" }
        },
        ammo = {
            { maxWeight = 5000, model = "prop_box_ammo04a" },
            { maxWeight = math.huge, model = "prop_box_ammo03a" }
        },
        weapon = {
            { maxWeight = 5000, model = "prop_box_ammo03a" },
            { maxWeight = math.huge, model = "prop_box_wood02a" }
        },
        food = {
            { maxWeight = 2500, model = "prop_paper_bag_small" },
            { maxWeight = 10000, model = "prop_cs_cardbox_01" },
            { maxWeight = math.huge, model = "prop_box_wood02a" }
        },
        drink = {
            { maxWeight = 2500, model = "prop_paper_bag_small" },
            { maxWeight = 10000, model = "prop_cs_cardbox_01" },
            { maxWeight = math.huge, model = "prop_box_wood02a" }
        },
        freight = {
            { maxWeight = 25000, model = "prop_wooden_crate_01" },
            { maxWeight = math.huge, model = "prop_boxpile_06a" }
        }
    },
    tiers = {
        { maxWeight = 2500,  model = "prop_paper_bag_small" }, -- < 2.5 kg: small paper sack
        { maxWeight = 10000, model = "prop_cs_cardbox_01" },   -- 2.5 - 10 kg: small cardboard box
        { maxWeight = 35000, model = "prop_box_wood02a" },     -- 10 - 35 kg: wooden supply crate
        { maxWeight = 80000, model = "prop_wooden_crate_01" }, -- 35 - 80 kg: heavy wooden freight crate
        { maxWeight = math.huge, model = "prop_boxpile_06a" }  -- > 80 kg: industrial cargo stack
    }
}

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
