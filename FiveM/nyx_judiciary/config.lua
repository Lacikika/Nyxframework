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
    SummonsTimeoutSeconds = 180, -- 3 minutes to report to courthouse before auto-replacement
    CivicStipendAmount = 500.0, -- Civic duty stipend awarded upon trial conclusion from city treasury
    CooldownSeconds = 604800, -- 7 days minimum between jury duties for a citizen
    CourtroomBucketBase = 2100, -- Base virtual routing bucket for active courtroom trials
    CourtroomBucketRange = 800, -- Allocates buckets 2100 - 2899
    DeliberationBucketOffset = 2000, -- Isolates jury in private deliberation bucket (e.g., 4100 - 4899)
    DeliberationVoteRule = 'majority', -- 'majority' or 'unanimous'
    ExemptJobs = {
        ['police'] = true,
        ['state_police'] = true,
        ['sheriff'] = true,
        ['doj'] = true,
        ['judge'] = true,
        ['ems'] = true
    }
}

-- Judicial Warrants & Subpoenas Configuration
Config.Warrants = {
    DefaultExpirationHours = 72, -- 3 days baseline duration
    MaxExpirationHours = 336,    -- 14 days maximum
    AllowedTypes = {
        ['arrest'] = true,
        ['search_property'] = true,
        ['search_vehicle'] = true,
        ['subpoena'] = true,
        ['wiretap'] = true
    },
    SubpoenaScopes = {
        ['all'] = true,
        ['financial'] = true,
        ['property'] = true,
        ['telecom'] = true
    },
    Tracking = {
        IntervalSeconds = 20,           -- Live cellular triangulation ping sweep interval
        DefaultAccuracyRadius = 35.0,  -- Meters of uncertainty radius
        BlipDurationMs = 25000,        -- Client blip lifetime
        SoundAlert = true
    },
    AuthorizedPermissions = {
        ['judge'] = true,
        ['doj_lead'] = true,
        ['chief_magistrate'] = true,
        ['admin'] = true,
        ['root'] = true
    },
    AuthorizedPetitioners = {
        ['police'] = true,
        ['sheriff'] = true,
        ['state_police'] = true,
        ['doj'] = true,
        ['judge'] = true,
        ['admin'] = true
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
    ForensicSwabItem = 'forensic_swab',
    CameraItem = 'camera_forensic',
    AutoSweepInterval = 60,         -- Sweep expired crime scene evidence every 60 seconds

    -- Authorized law enforcement & judiciary roles
    AuthorizedJobs = {
        ['police'] = true,
        ['sheriff'] = true,
        ['state_police'] = true,
        ['doj'] = true,
        ['judge'] = true,
        ['forensics'] = true,
        ['admin'] = true
    },

    -- Valid chain-of-custody lifecycle state transitions
    AllowedActions = {
        ['COLLECTED'] = true,
        ['TRANSFERRED'] = true,
        ['SECURED_IN_LOCKER'] = true,
        ['CHECKED_OUT_LAB'] = true,
        ['LAB_ANALYZED'] = true,
        ['SUBMITTED_EXHIBIT'] = true,
        ['RELEASED_TO_OWNER'] = true,
        ['DESTROYED'] = true
    },

    -- Swab categories and parameters
    SwabTypes = {
        ['gsr'] = { label = 'Gunshot Residue (GSR) Swab', windowSeconds = 1800 },
        ['dna'] = { label = 'Epithelial DNA Surface Swab', windowSeconds = 7200 },
        ['narcotic'] = { label = 'Narcotic & Chemical Surface Swab', windowSeconds = 3600 }
    },

    -- Certified Laboratory Analytical Tests
    LabAnalysisTypes = {
        ['ballistics_match'] = { label = 'Ballistics Striation & Rifling Comparison', fee = 250.00 },
        ['dna_profile'] = { label = 'Short Tandem Repeat (STR) DNA Profile', fee = 400.00 },
        ['gsr_spectrometry'] = { label = 'Scanning Electron Microscopy (GSR-SEM)', fee = 150.00 },
        ['fingerprint_afis'] = { label = 'Automated Fingerprint Identification (AFIS)', fee = 200.00 },
        ['digital_forensics'] = { label = 'Cryptographic CCTV / Digital Forensics', fee = 100.00 }
    },

    -- Certified Physical Evidence Lockers & Depository Vaults
    Lockers = {
        ['locker_mrpd_01'] = {
            id = 'locker_mrpd_01',
            name = 'Mission Row Police Dept Evidence Locker #1',
            facilityType = 'police_locker',
            dept = 'police',
            coords = vector3(475.2, -998.4, 26.2)
        },
        ['locker_sandy_01'] = {
            id = 'locker_sandy_01',
            name = 'Sandy Shores Sheriff Substation Locker #1',
            facilityType = 'police_locker',
            dept = 'sheriff',
            coords = vector3(1853.1, 3683.4, 34.2)
        },
        ['locker_paleto_01'] = {
            id = 'locker_paleto_01',
            name = 'Paleto Bay Constable Depository #1',
            facilityType = 'police_locker',
            dept = 'sheriff',
            coords = vector3(-448.2, 6012.3, 31.7)
        },
        ['lab_davis_forensics'] = {
            id = 'lab_davis_forensics',
            name = 'Davis Regional Forensic Crime Laboratory',
            facilityType = 'forensics_lab',
            dept = 'forensics',
            coords = vector3(362.4, -1585.1, 29.2)
        },
        ['vault_court_district'] = {
            id = 'vault_court_district',
            name = 'San Andreas Superior Court Evidence Vault',
            facilityType = 'court_vault',
            dept = 'doj',
            coords = vector3(-540.8, -198.2, 38.2)
        }
    }
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
