--[[
    Nyxframework: nyx_services
    File: config.lua
    Description: Configuration for civil infrastructure, power grid substations,
                 metered public utility billing, and healthcare dependencies.
]]

Config = {}

Config.Debug = false

-- Regional Power Grid & Substation Mechanics
Config.PowerGrid = {
    FuelConsumptionPerMinute = 0.50,      -- Fuel burned per real-time minute (0.50%)
    HealthDegradationPerMinute = 0.15,    -- Wear and tear per real-time minute (0.15%)
    BlackoutFuelThreshold = 0.00,         -- Level at which substation shuts down
    BlackoutHealthThreshold = 10.00,      -- Critical wear threshold triggering grid failure
    FuelDrumRefuelAmount = 25.00,         -- Fuel percentage restored by one industrial fuel drum
    RepairKitRestoreAmount = 30.00,       -- Generator health percentage restored by one repair kit
    Substations = {
        ['grid_central_ls'] = {
            label = "Central Los Santos Metro Substation",
            coords = vector3(711.5, -963.2, 30.4),
            radius = 1600.0,
            maintenancePoint = vector3(711.5, -963.2, 30.4)
        },
        ['grid_port_ls'] = {
            label = "Port of Los Santos & Cypress Industrial Grid",
            coords = vector3(1072.0, -2006.0, 31.5),
            radius = 1800.0,
            maintenancePoint = vector3(1072.0, -2006.0, 31.5)
        },
        ['grid_rockford'] = {
            label = "Rockford Hills & Del Perro Power Station",
            coords = vector3(-1440.0, -250.0, 48.0),
            radius = 2000.0,
            maintenancePoint = vector3(-1440.0, -250.0, 48.0)
        },
        ['grid_sandy_shores'] = {
            label = "Grand Senora Desert Substation",
            coords = vector3(2732.0, 1572.0, 24.5),
            radius = 2500.0,
            maintenancePoint = vector3(2732.0, 1572.0, 24.5)
        },
        ['grid_paleto'] = {
            label = "Paleto Bay & Mount Chiliad Regional Generator",
            coords = vector3(140.0, 6600.0, 31.8),
            radius = 2200.0,
            maintenancePoint = vector3(140.0, 6600.0, 31.8)
        }
    }
}

-- Metered Utility Billing Configuration
Config.Billing = {
    KwhTariff = 0.15,                     -- $0.15 per kilowatt-hour
    WaterTariff = 0.05,                   -- $0.05 per gallon
    BillingCycleInterval = 1800,          -- 30 minutes per automated meter billing cycle
    SuspensionThreshold = 2500.00,        -- Debt threshold at which property electricity/water cuts off
    PublicWorksAccount = "gov:dept:works",-- Municipal treasury account collecting utility revenues
    ConsumptionProfiles = {
        ['residential'] = { kwh = 120.0, water = 80.0 },
        ['commercial'] = { kwh = 450.0, water = 200.0 },
        ['industrial'] = { kwh = 1200.0, water = 650.0 }
    }
}

-- Healthcare & Medical Supply Dependence
Config.Healthcare = {
    ShortageThresholds = {
        Degraded = 15,    -- Respawn delay increased
        Critical = 5      -- High-end trauma treatments disabled, freight contract triggered
    },
    RespawnTimePenalties = {
        optimal = 0,               -- Baseline respawn time (0s delay)
        degraded = 30,             -- Moderate shortage (+30s delay)
        critical_shortage = 60     -- Severe shortage (+60s delay)
    },
    FreightRestockContract = {
        Quantity = 25,
        PayoutPerUnit = 120.00
    },
    Hospitals = {
        ['pillbox_hill'] = {
            label = "Pillbox Hill Medical Center",
            substationId = "grid_central_ls",
            coords = vector3(340.0, -1396.0, 32.5),
            revivalBedCoords = vector4(348.0, -1400.0, 32.5, 90.0)
        },
        ['sandy_shores_clinic'] = {
            label = "Mount Zonah Desert Clinic",
            substationId = "grid_sandy_shores",
            coords = vector3(1839.5, 3672.5, 34.3),
            revivalBedCoords = vector4(1839.5, 3672.5, 34.3, 210.0)
        },
        ['paleto_bay_hospital'] = {
            label = "Paleto Bay Emergency Care Center",
            substationId = "grid_paleto",
            coords = vector3(-247.0, 6331.0, 32.4),
            revivalBedCoords = vector4(-247.0, 6331.0, 32.4, 315.0)
        }
    }
}
