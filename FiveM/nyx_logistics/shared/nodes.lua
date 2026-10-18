--[[
    Nyxframework: nyx_logistics
    File: shared/nodes.lua
    Description: Declarative harvesting node registry with coordinates, resource items, and tools.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Nodes = {}

-- Static Registry of Physical Extraction Nodes
Nyx.Logistics.Nodes.Registry = {
    ['mine_quarry_iron'] = {
        id = 'mine_quarry_iron',
        label = 'Davis Quartz Iron Quarry',
        resource = 'refined_iron',
        maxReserve = 500,
        regenRatePerHour = 50,
        requiredTool = nil, -- Any mining pick or baseline manual gathering
        coords = vector3(2950.1, 2780.4, 41.2),
        anim = {
            dict = 'amb@world_human_hammering@male@base',
            name = 'base'
        }
    },
    ['mine_copper_sandy'] = {
        id = 'mine_copper_sandy',
        label = 'Grand Senora Copper Vein',
        resource = 'refined_copper',
        maxReserve = 400,
        regenRatePerHour = 40,
        requiredTool = nil,
        coords = vector3(1845.2, 3782.1, 33.5),
        anim = {
            dict = 'amb@world_human_hammering@male@base',
            name = 'base'
        }
    },
    ['oil_well_sandy'] = {
        id = 'oil_well_sandy',
        label = 'RON Alternates Pumpjack #04',
        resource = 'crude_oil',
        maxReserve = 1000,
        regenRatePerHour = 100,
        requiredTool = nil,
        coords = vector3(605.3, 2898.6, 41.8),
        anim = {
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            name = 'machinic_loop_mechandplayer'
        }
    },
    ['farm_grapeseed_wheat'] = {
        id = 'farm_grapeseed_wheat',
        label = 'Grapeseed Golden Wheat Fields',
        resource = 'crop_wheat',
        maxReserve = 800,
        regenRatePerHour = 80,
        requiredTool = nil,
        coords = vector3(2320.5, 4890.2, 41.5),
        anim = {
            dict = 'amb@world_human_gardener_plant@male@base',
            name = 'base'
        }
    },
    ['farm_chaparral_corn'] = {
        id = 'farm_chaparral_corn',
        label = 'Great Chaparral Sun Corn Plantation',
        resource = 'crop_corn',
        maxReserve = 600,
        regenRatePerHour = 60,
        requiredTool = nil,
        coords = vector3(1055.2, 1420.4, 98.2),
        anim = {
            dict = 'amb@world_human_gardener_plant@male@base',
            name = 'base'
        }
    },
    ['farm_paleto_produce'] = {
        id = 'farm_paleto_produce',
        label = 'Paleto Bay Coastal Organic Orchard',
        resource = 'crop_produce',
        maxReserve = 500,
        regenRatePerHour = 50,
        requiredTool = nil,
        coords = vector3(-420.8, 6250.6, 30.5),
        anim = {
            dict = 'amb@world_human_gardener_plant@male@base',
            name = 'base'
        }
    },
    ['node_humane_botanicals'] = {
        id = 'node_humane_botanicals',
        label = 'Humane Research Botanical Conservatory',
        resource = 'organic_compounds',
        maxReserve = 600,
        regenRatePerHour = 60,
        requiredTool = nil,
        coords = vector3(3558.2, 3672.4, 28.1),
        anim = {
            dict = 'amb@world_human_gardener_plant@male@base',
            name = 'base'
        }
    },
    ['node_el_burro_petrochem'] = {
        id = 'node_el_burro_petrochem',
        label = 'El Burro Petrochemical Runoff Sump',
        resource = 'chemical_precursors',
        maxReserve = 800,
        regenRatePerHour = 80,
        requiredTool = nil,
        coords = vector3(1390.5, -2080.2, 52.0),
        anim = {
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            name = 'machinic_loop_mechandplayer'
        }
    },
    ['node_zancudo_brine'] = {
        id = 'node_zancudo_brine',
        label = 'Lago Zancudo Saline Mineral Aquifer',
        resource = 'raw_saline_brine',
        maxReserve = 1000,
        regenRatePerHour = 100,
        requiredTool = nil,
        coords = vector3(-2210.4, 2775.8, 2.8),
        anim = {
            dict = 'amb@world_human_bum_wash@male@high@base',
            name = 'base'
        }
    },
    ['node_paleto_forest_timber'] = {
        id = 'node_paleto_forest_timber',
        label = 'Paleto Forest Redwood Timber Tract',
        resource = 'raw_timber_logs',
        maxReserve = 600,
        regenRatePerHour = 60,
        requiredTool = nil,
        coords = vector3(-570.4, 5320.1, 70.2),
        anim = {
            dict = 'amb@world_human_hammering@male@base',
            name = 'base'
        }
    },
    ['node_chiliad_redwood'] = {
        id = 'node_chiliad_redwood',
        label = 'Mount Chiliad Ancient Pine Grove',
        resource = 'raw_timber_logs',
        maxReserve = 500,
        regenRatePerHour = 50,
        requiredTool = nil,
        coords = vector3(-790.6, 5450.4, 34.5),
        anim = {
            dict = 'amb@world_human_hammering@male@base',
            name = 'base'
        }
    },
    ['node_san_chianski_cotton'] = {
        id = 'node_san_chianski_cotton',
        label = 'San Chianski Coastal Cotton Plantation',
        resource = 'raw_cotton',
        maxReserve = 700,
        regenRatePerHour = 70,
        requiredTool = nil,
        coords = vector3(2580.4, 4690.2, 34.0),
        anim = {
            dict = 'amb@world_human_gardener_plant@male@base',
            name = 'base'
        }
    }
}

function Nyx.Logistics.GetNode(nodeId)
    return Nyx.Logistics.Nodes.Registry[nodeId]
end
