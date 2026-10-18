--[[
    Nyxframework: nyx_properties
    File: config.lua
    Description: Configuration constants, 5-tier access permissions,
                 progressive millage tax parameters, land footprint taxation,
                 and default property blueprints.
]]

Config = Config or {}
Config.Debug = true

Config.Millage = {
    BillingIntervalHours = 24,       -- Millage tax assessed every 24 game cycles
    DefaultMillageRate = 0.0150,     -- 1.5% baseline statutory municipal property tax
    TreasuryAccount = "gov:city:master", -- Municipal treasury target account
    DelinquencyThresholdDays = 7     -- Days until public forfeiture auction
}

Config.Taxation = {
    -- Progressive holding multiplier: 1.5 ^ (PropertiesOwned - 1)
    ProgressiveHoldingBase = 1.50,
    MaxHoldingMultiplier = 10.00,
    MaxEffectiveMillageRate = 0.1000, -- 10% statutory tax ceiling

    -- Base land maintenance rates per square meter ($/m^2 per billing cycle)
    LandMaintenanceRates = {
        ['residential'] = 1.20,
        ['commercial'] = 2.50,
        ['industrial'] = 3.20
    },

    -- Economic zone location tax surcharges
    ZoneSurcharges = {
        ['zone_ls_metro'] = 0.15,        -- +15% dense urban maintenance surcharge
        ['zone_port_industrial'] = 0.10, -- +10% heavy logistics port zone
        ['zone_sandy_shores'] = 0.00,    -- 0% rural Blaine County
        ['zone_paleto_bay'] = 0.00       -- 0% rural Paleto Bay
    },

    -- Delinquency penalty rates per overdue arrears tier
    Delinquency = {
        GraceCycles = 1,                 -- Tier 1: notice only, zero late penalty
        LatePenaltyRate = 0.10,          -- Tier 2 (2 missed cycles): 10% late surcharge
        ForeclosurePenaltyRate = 0.25,   -- Tier 3 (3 missed cycles): 25% surcharge + utility suspension + lock interlock
        ForfeitureCycleThreshold = 4     -- Tier 4 (4+ missed cycles): Forfeiture deed revocation -> blind auction
    },

    -- Blight condition surcharge: max +50% at 0% condition
    MaxBlightSurcharge = 0.50,

    -- Condition decay and repair parameters
    ConditionDecayHoursPerPercent = 24.0, -- 1% degradation per 24 hours of neglect
    MinConditionFloor = 10.0,             -- Condition cannot drop below 10%
    RepairCostPerSqmPoint = 0.05,         -- $0.05 per m^2 per 1% condition restored

    -- Double-entry closed-loop municipal distribution split (Tervek.md 1.1)
    RevenueSplits = {
        EmergencyServices = 0.40, -- 40% to Emergency Services (Police/EMS fleet & payroll)
        PublicWorks = 0.45,       -- 45% to Public Works & Infrastructure (Land maintenance & power grid)
        MasterReserve = 0.15      -- 15% to City Master Reserve / Social Dividend
    },

    -- Municipal foreclosure blind auction parameters
    Auction = {
        DurationHours = 48,
        MinBidDiscountRate = 0.50, -- Starting minimum bid is 50% of original property price
        TreasuryAccount = "gov:city:master"
    }
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
        landAreaSqm = 120.00,
        zoneId = "zone_ls_metro",
        initialCondition = 100.00,
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
        landAreaSqm = 320.00,
        zoneId = "zone_ls_metro",
        initialCondition = 100.00,
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
        landAreaSqm = 1250.00,
        zoneId = "zone_port_industrial",
        initialCondition = 100.00,
        entrance = { x = 145.2, y = -3105.8, z = 5.9, h = 90.0 },
        interior = { x = 150.5, y = -3110.2, z = -20.0, h = 0.0 },
        linkedSubstation = "substation_south"
    }
}
