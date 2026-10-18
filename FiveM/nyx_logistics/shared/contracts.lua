--[[
    Nyxframework: nyx_logistics
    File: shared/contracts.lua
    Description: Shared specifications, terminal coordinates, vehicle classes,
                 and constants for the Freight Hauling Board system.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}

Nyx.Logistics.FreightConfig = {
    -- Escrow Collateral
    EscrowBondPercent = 0.15,       -- 15% bond collateral required to claim freight
    MaxConcurrentContracts = 1,     -- Max active in-transit contracts per citizen
    MaxLoadingDistance = 8.0,       -- Max distance in meters between ped/vehicle and loading dock
    DefaultDeadlineSeconds = 1800,  -- 30 minutes baseline deadline

    -- Authorized Freight Hauler Commercial Vehicles
    CommercialVehicles = {
        [`mule`] = true,
        [`mule2`] = true,
        [`mule3`] = true,
        [`mule4`] = true,
        [`pounder`] = true,
        [`pounder2`] = true,
        [`flatbed`] = true,
        [`benson`] = true,
        [`phantom`] = true,
        [`phantom3`] = true,
        [`hauler`] = true,
        [`packer`] = true,
        [`boxville`] = true,
        [`boxville2`] = true,
        [`boxville3`] = true,
        [`tanker`] = true,
        [`tanker2`] = true,
        [`armytanker`] = true
    },

    -- Public Dispatch Terminals (nyx_interact targets)
    DispatchTerminals = {
        {
            id = "terminal_port_ls",
            name = "Port of Los Santos Logistics Terminal",
            coords = vector3(152.4, -3205.2, 5.9),
            model = `prop_terminal_01`,
            heading = 270.0
        },
        {
            id = "terminal_davis_hub",
            name = "Davis Industrial Distribution Yard",
            coords = vector3(153.2, -1802.4, 28.0),
            model = `prop_terminal_01`,
            heading = 180.0
        },
        {
            id = "terminal_sandy_depot",
            name = "Sandy Shores Regional Freight Depot",
            coords = vector3(1702.3, 3775.1, 34.5),
            model = `prop_terminal_01`,
            heading = 90.0
        },
        {
            id = "terminal_paleto_outpost",
            name = "Paleto Bay Supply Station",
            coords = vector3(-168.4, 6315.8, 31.5),
            model = `prop_terminal_01`,
            heading = 0.0
        },
        {
            id = "terminal_bolingbroke_penal",
            name = "Bolingbroke Penitentiary Civic Freight Dock",
            coords = vector3(1705.0, 2577.5, 45.5),
            model = `prop_terminal_01`,
            heading = 180.0
        },
        {
            id = "terminal_grapeseed_mill",
            name = "Grapeseed Grain Mill & Agricultural Depot",
            coords = vector3(2438.0, 4964.0, 46.0),
            model = `prop_terminal_01`,
            heading = 180.0
        }
    }
}
