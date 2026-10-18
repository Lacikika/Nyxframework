--[[
    Nyxframework: nyx_judiciary
    File: config.lua
    Description: Configuration for the decentralized judiciary, forensic tracking, and jury systems.
]]

Config = {}

Config.Debug = false

-- Civic Jury & Summons Configuration
Config.Jury = {
    DefaultRequiredCount = 5,
    MinimumQuorum = 3,
    DeliberationTimeout = 900, -- 15 minutes to reach a verdict before mistrial flag
    ExemptJobs = {
        ['police'] = true,
        ['state_police'] = true,
        ['sheriff'] = true,
        ['doj'] = true,
        ['judge'] = true,
        ['ems'] = true
    },
    DeliberationBucketOffset = 2000 -- Isolates jury in private instance during voting
}

-- Judicial Warrants Configuration
Config.Warrants = {
    DefaultExpirationHours = 72, -- 3 days baseline duration
    MaxExpirationHours = 336,    -- 14 days maximum
    AllowedTypes = {
        ['arrest'] = true,
        ['search_property'] = true,
        ['search_vehicle'] = true
    },
    AuthorizedPermissions = {
        ['judge'] = true,
        ['doj_lead'] = true,
        ['admin'] = true,
        ['root'] = true
    }
}

-- Forensic Chain-of-Custody & Evidence Configuration
Config.Forensics = {
    TransientDecaySeconds = 3600,   -- Crime scene evidence vanishes after 1 hour if not bagged
    MaxCollectionDistance = 2.5,    -- Meters from evidence drop to allow pickup
    DetectionRadius = 15.0,         -- Distance within which forensic gear detects drops
    SaltLength = 8,                 -- Bytes of entropy for deterministic hash generation
    GloveItems = {
        ['latex_gloves'] = true,
        ['nitrile_gloves'] = true
    },
    EvidenceBagItem = 'evidence_bag',
    ForensicKitItem = 'forensic_kit',
    AutoSweepInterval = 60          -- Sweep expired crime scene evidence every 60 seconds
}

-- Courtroom Spatial Anchors (San Andreas Superior District Court)
Config.Courtroom = {
    InteriorCenter = vector3(-545.2, -203.8, 38.2),
    JudgeBench = vector4(-545.2, -203.8, 38.2, 210.0),
    WitnessStand = vector4(-542.5, -204.5, 38.2, 120.0),
    ProsecutionBench = vector4(-548.5, -200.5, 38.2, 30.0),
    DefenseBench = vector4(-542.0, -200.5, 38.2, 30.0),
    JuryBox = {
        vector4(-551.5, -204.0, 38.2, 120.0),
        vector4(-551.5, -205.5, 38.2, 120.0),
        vector4(-551.5, -207.0, 38.2, 120.0),
        vector4(-553.0, -204.0, 38.2, 120.0),
        vector4(-553.0, -205.5, 38.2, 120.0),
        vector4(-553.0, -207.0, 38.2, 120.0)
    },
    PublicGallery = vector4(-545.0, -195.0, 38.2, 0.0),
    DeliberationChamber = vector4(-530.0, -190.0, 38.2, 0.0)
}

-- Bolingbroke State Penitentiary Custodial Routing
Config.Penitentiary = {
    RoutingBucket = 5000,
    CellCoords = vector4(1679.0, 2513.5, 45.5, 220.0),
    ReleaseCoords = vector4(1848.0, 2586.0, 45.6, 270.0),
    SentenceMinuteSeconds = 60 -- 1 in-game month = 60 seconds (or configurable)
}
