--[[
    Nyxframework: nyx_properties
    File: config.lua
    Description: Configuration constants, 5-tier access permissions,
                 millage tax parameters, and property blueprints.
]]

Config = Config or {}
Config.Debug = true

Config.Millage = {
    BillingIntervalHours = 24,       -- Millage tax assessed every 24 game cycles
    DefaultMillageRate = 0.0150,     -- 1.5% statutory municipal property tax
    TreasuryAccount = "gov:city:master", -- Municipal treasury target account
    DelinquencyThresholdDays = 7     -- Days until public forfeiture auction
}

Config.Keys = {
    Tiers = {
        GUEST = 1,          -- Read-only entry when door is unlocked or buzzed
        RESIDENT = 2,       -- Can lock/unlock door, basic entry access
        MANAGER = 3,        -- Can issue Tier 1-2 keys, view utility meters
        OWNER = 4,          -- Full ownership deed, issue Tier 1-3 keys, sell/transfer
        ENFORCEMENT = 5     -- Emergency judicial warrant breach (Police / Fire)
    }
}

Config.DefaultProperties = {
    {
        code = "apt_integrity_101",
        label = "Integrity Way Apartment 101",
        type = "residential",
        price = 125000.00,
        millageRate = 0.0150,
        entrance = { x = -269.4, y = -955.3, z = 31.2, h = 205.0 },
        interior = { x = -266.3, y = -960.2, z = -20.0, h = 0.0 }, -- Virtual Shell / MLO coords
        linkedSubstation = "substation_central"
    },
    {
        code = "store_vinewood_24",
        label = "Vinewood Boulevard Retail Storefront",
        type = "commercial",
        price = 350000.00,
        millageRate = 0.0200,
        entrance = { x = 373.8, y = 325.8, z = 103.5, h = 255.0 },
        interior = { x = 378.1, y = 330.2, z = -20.0, h = 0.0 },
        linkedSubstation = "substation_north"
    },
    {
        code = "wh_elysian_04",
        label = "Elysian Island Secure Logistics Warehouse",
        type = "industrial",
        price = 780000.00,
        millageRate = 0.0125,
        entrance = { x = 145.2, y = -3105.8, z = 5.9, h = 90.0 },
        interior = { x = 150.5, y = -3110.2, z = -20.0, h = 0.0 },
        linkedSubstation = "substation_south"
    }
}
