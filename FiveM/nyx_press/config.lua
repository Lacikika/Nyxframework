--[[
    Nyxframework: nyx_press
    File: config.lua
    Description: Configuration for decentralized media printing, whistleblower leak dropboxes,
                 and trade union press accreditation.
]]

Config = Config or {}

Config.Debug = false

-- 1. Printing Press Configuration
Config.Printing = {
    BaseCostPerCopy = 2.00,          -- Base material cost per physical newspaper copy
    PageFactor = 0.50,               -- Additional per-500 words or length factor
    MachineOverhead = 25.00,         -- Fixed setup and ink calibration cost per print run
    MinCirculation = 10,             -- Minimum copies per print run
    MaxCirculation = 2000,           -- Maximum copies per print run
    SupplyAccount = "gov:dept:works",-- Municipal supplier credited for paper/ink utilities
    PrintDurationMsPerCopy = 100,    -- Printing simulation delay per copy (capped at 5s)
}

-- 2. Retail Newsstand Configuration
Config.Newsstand = {
    DefaultCoverPrice = 10.00,       -- Default sale price for a newspaper
    MinCoverPrice = 1.00,
    MaxCoverPrice = 100.00,
    PublisherSplit = 0.75,           -- 75% credited to publisher/outlet account
    MunicipalTaxSplit = 0.25,        -- 25% credited to municipal treasury (gov:city:master)
    MaxKioskInventory = 100,         -- Maximum copies stored per public newsstand
    MunicipalAccount = "gov:city:master"
}

-- 3. Whistleblower Cryptographic Dropboxes
Config.Whistleblower = {
    AllowedCategories = {
        ['treasury_fraud'] = "Fiscal & Treasury Embezzlement",
        ['police_brutality'] = "Law Enforcement Misconduct & Brutality",
        ['corporate_bribery'] = "Corporate Bribery & Illegal Collusion",
        ['election_tampering'] = "Electoral Tampering & Fraud",
        ['general_corruption'] = "General Civil & Institutional Corruption"
    },
    SaltLength = 16,
    MinPayloadLength = 20,
    MaxPayloadLength = 65536,
}

-- 4. Trade Union Media Accreditation
Config.Accreditation = {
    RequiredUnionId = "union:press_guild",
    AllowedUnionRoles = {
        ['steward'] = true,
        ['delegate'] = true,
        ['member'] = true
    },
    EnforceUnionStanding = true,     -- Must be 'good_standing'
    AllowMediaFactionOwners = true,  -- Founders / CEOs of registered media charters also qualify
}

-- 5. Physical World Props & Models
Config.Models = {
    Newsstands = {
        `prop_news_disp_02a`,
        `prop_news_disp_01a`,
        `prop_news_disp_02b`,
        `prop_news_disp_02c`
    },
    PrintingPress = `prop_printer_01`,
    Dropboxes = `prop_postbox_01a`
}
