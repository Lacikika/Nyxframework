--[[
    Nyxframework: nyx_factions
    File: config.lua
    Description: Configuration for autonomous player organizations, corporate charters,
                 multi-sig vaults, and commercial fleet depots.
]]

Config = {}

Config.Debug = false

-- Legal Charter Formation Parameters
Config.Charter = {
    FilingFee = 15000.00,       -- Municipal filing fee auto-debited to city treasury
    MinSeedCapital = 10000.00,  -- Minimum initial capital to fund company accounts
    MunicipalAccount = "gov:city:master",
    AllowedTypes = {
        ['corporation'] = { label = "C-Corporation", maxEquityHolders = 50 },
        ['cooperative'] = { label = "Worker Cooperative", equalEquity = true },
        ['trade_union'] = { label = "Labor Union", collectiveBargaining = true },
        ['private_enterprise'] = { label = "Sole Proprietorship / Partnership", maxEquityHolders = 5 },
        ['syndicate'] = { label = "Commercial Syndicate", unrestricted = true }
    }
}

-- Multi-Signature Vault Configuration
Config.MultiSig = {
    DefaultThresholdAmount = 50000.00, -- Withdrawals above this require multi-sig quorum
    DefaultRequiredSignatures = 2,     -- Minimum signatories required to disburse high-tier transfers
    RequestExpirationHours = 48,       -- Time window before pending multi-sig request expires
    AutoSweepInterval = 600            -- Check for expired multi-sig requests every 10 minutes
}

-- Automated Retained Earnings & Dividends
Config.Dividends = {
    DefaultReinvestmentRate = 0.20, -- 20% retained for company operating liquidity
    MinReinvestmentRate = 0.10,     -- Constitutional floor
    MaxReinvestmentRate = 0.50      -- Constitutional ceiling
}

-- Corporate Treasury Vaults & Sub-Accounts Configuration
Config.Vaults = {
    DefaultDailyLimit = 100000.00, -- Default 24h rolling withdrawal limit per vault
    MaxSubVaults = 10,             -- Maximum designated sub-vaults per organization
    DailyResetSeconds = 86400      -- Rolling window reset threshold (24 hours)
}

-- Standard Granular RBAC Permission Nodes
Config.PermissionNodes = {
    "treasury:view_ledger",
    "treasury:deposit",
    "treasury:withdraw_low",
    "treasury:withdraw_high",
    "treasury:sign_tx",
    "treasury:manage_vaults",
    "treasury:manage_rules",
    "treasury:freeze_vault",
    "inventory:view",
    "inventory:deposit",
    "inventory:withdraw",
    "fleet:spawn",
    "fleet:manage",
    "property:manage",
    "roster:invite",
    "roster:promote",
    "roster:terminate",
    "governance:call_vote"
}

-- City Hall & Commercial Terminals
Config.Terminals = {
    {
        id = "city_hall_commerce",
        label = "Los Santos Department of Commerce & Charters",
        coords = vector4(-545.0, -204.0, 38.2, 210.0),
        type = "charter_and_management"
    },
    {
        id = "paleto_civic_commerce",
        label = "Paleto Bay Civic Commerce Terminal",
        coords = vector4(-139.2, 6300.5, 31.5, 45.0),
        type = "charter_and_management"
    }
}

-- Commercial Fleet Parking Depots
Config.FleetDepots = {
    ['depot_port_ls'] = {
        label = "Port of Los Santos Commercial Freight Depot",
        coords = vector3(-153.8, -2392.2, 6.0),
        spawnPoint = vector4(-161.4, -2397.5, 6.0, 180.0)
    },
    ['depot_cypress_flats'] = {
        label = "Cypress Flats Industrial Fleet Yard",
        coords = vector3(822.4, -2145.0, 29.5),
        spawnPoint = vector4(815.2, -2150.8, 29.5, 350.0)
    }
}

-- Trade Unions & Collective Bargaining Configuration
Config.Unions = {
    DefaultDuesFlat = 50.00,
    DefaultDuesRate = 0.025,
    DefaultStrikePayRate = 150.00,
    MinFoundingSignatures = 3,
    StrikeVoteDurationHours = 24,
    StrikeVoteQuorumPct = 0.50,
    StrikeVoteMajorityPct = 0.50,
    ArbitrationStatutoryPenaltyRate = 0.10,
    StrikePayCooldownSeconds = 86400,
    Sectors = {
        ['logistics'] = "Logistics, Hauling & Transportation",
        ['manufacturing'] = "Heavy Industry, Assembly & Manufacturing",
        ['mining'] = "Raw Resource Extraction & Mining",
        ['services'] = "Public Utilities, Maintenance & Services",
        ['healthcare'] = "Medical, Pharmaceutical & Health",
        ['civil'] = "Civil Administration & Municipal Staff"
    }
}
