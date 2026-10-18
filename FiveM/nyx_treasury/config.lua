Config = {}

-- Diagnostics & Debugging
Config.Debug = false

-- Closed-Loop Reserve Thresholds
Config.TargetReserve = 5000000.00   -- Target operating reserve for 100% full wage payouts
Config.CautionReserve = 2500000.00  -- Warning threshold (50% target) where austerity measures begin
Config.RecoveryReserve = 1000000.00 -- Solvency threshold required to automatically reset a tripped circuit breaker
Config.CriticalReserve = 500000.00  -- Emergency threshold below which public payrolls freeze

-- Fiscal Circuit Protection Parameters
Config.Circuit = {
    Enabled = true,
    RollingWindowSeconds = 600,       -- 10-minute rolling outflow velocity observation window
    MaxRollingOutflow = 750000.00,    -- Max permissible municipal outflow within rolling window ($750k)
    MaxSingleTransaction = 500000.00, -- Max single transaction cap on municipal debits without emergency flag
    AusterityWageFloor = 0.10,        -- 10% minimum safety-net wage scale while above CriticalReserve
    CriticalWageMultiplier = 0.00,    -- 0% wage scale when reserves are at or below CriticalReserve
    AutoResetCooldown = 300,          -- Minimum 5 minutes after tripping before automated reset can occur
    HysteresisRecoveryMargin = 0.75,  -- Outflow must drop below 75% of max threshold for automated reset
    ExemptCategories = {              -- Transaction categories exempt from circuit trip blocks
        ["payroll"] = true,
        ["emergency_subvention"] = true,
        ["tax_sweep"] = true
    }
}

-- Designated Municipal Account Identifiers
Config.Accounts = {
    Master = "gov:city:master",
    Tax = "gov:city:tax",
    Police = "gov:dept:police",
    EMS = "gov:dept:ems",
    Works = "gov:dept:works"
}

-- Point-of-Sale & P2P Tax Rates
Config.SalesTaxRate = 0.08       -- 8% baseline sales tax
Config.TransferTaxRate = 0.02    -- 2% wire transfer tax
Config.MaxTaxRate = 0.15         -- 15% constitutional tax rate ceiling
Config.TaxSweepInterval = 1800   -- 30 minutes per automated revenue redistribution sweep

-- Localized Economic Zone Tax Surcharges (Added to base sales tax, subject to MaxTaxRate)
Config.ZoneTaxSurcharges = {
    ['zone_ls_metro'] = 0.0150,        -- +1.5% municipal surcharge in dense urban core
    ['zone_sandy_shores'] = 0.0000,    -- 0.0% in Blaine County rural zone
    ['zone_paleto_bay'] = 0.0000,      -- 0.0% in Paleto Bay
    ['zone_port_industrial'] = 0.0050  -- +0.5% in Port industrial basin
}

-- Public Service Payroll Configuration
Config.PayrollInterval = 900     -- 15 minutes between public duty paycheck cycles

-- Baseline departmental pay grades (before logarithmic fiscal crisis scaling)
Config.DefaultWages = {
    ['police'] = {
        [0] = 750.00,   -- Cadet
        [1] = 950.00,   -- Officer
        [2] = 1200.00,  -- Senior Officer / Detective
        [3] = 1500.00,  -- Lieutenant
        [4] = 2000.00   -- Chief of Police
    },
    ['ems'] = {
        [0] = 700.00,   -- EMT Trainee
        [1] = 900.00,   -- Paramedic
        [2] = 1150.00,  -- Senior Paramedic
        [3] = 1450.00,  -- Doctor / Supervisor
        [4] = 1900.00   -- Hospital Director
    },
    ['works'] = {
        [0] = 600.00,   -- Apprentice
        [1] = 800.00,   -- Technician
        [2] = 1000.00,  -- Engineer
        [3] = 1350.00   -- Director of Public Works
    }
}

-- Public Transparency Terminals (Town Halls, Stations, Civic Centers)
Config.Terminals = {
    {
        label = "City Hall Public Finance Terminal",
        coords = vector3(-545.1, -204.4, 38.2)
    },
    {
        label = "Mission Row Civic Ledger Terminal",
        coords = vector3(441.2, -981.8, 30.7)
    },
    {
        label = "Pillbox Hill Medical Reserve Terminal",
        coords = vector3(311.5, -593.6, 43.3)
    }
}

Config.TerminalInteractDistance = 2.0
