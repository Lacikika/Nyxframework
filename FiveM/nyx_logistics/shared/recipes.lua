--[[
    Nyxframework: nyx_logistics
    File: shared/recipes.lua
    Description: Declarative manufacturing, refining, and assembly blueprints.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Recipes = {}

-- Industrial Production Recipes
Nyx.Logistics.Recipes.Registry = {
    ['repair_kit'] = {
        key = 'repair_kit',
        label = 'Standard Vehicle Repair Kit',
        facilityType = 'assembly',
        processingTime = 30, -- seconds per batch
        powerRequirementKw = 15,
        inputs = {
            { item = 'refined_iron', amount = 2 },
            { item = 'plastic_polymer', amount = 2 }
        },
        outputs = {
            {
                item = 'tool_repairkit',
                amount = 1,
                metadata = {
                    quality = 1.00,
                    durability = 100.0
                }
            }
        }
    },
    ['first_aid_pack'] = {
        key = 'first_aid_pack',
        label = 'Trauma First Aid Kit',
        facilityType = 'chemical',
        processingTime = 20,
        powerRequirementKw = 8,
        inputs = {
            { item = 'med_bandage', amount = 3 }
        },
        outputs = {
            {
                item = 'med_firstaid',
                amount = 1,
                metadata = {
                    sterile = true,
                    durability = 100.0
                }
            }
        }
    },
    ['polymer_refining'] = {
        key = 'polymer_refining',
        label = 'Crude Oil Polymer Refining',
        facilityType = 'refinery',
        processingTime = 25,
        powerRequirementKw = 20,
        inputs = {
            { item = 'crude_oil', amount = 2 }
        },
        outputs = {
            {
                item = 'plastic_polymer',
                amount = 4
            }
        }
    },
    ['ammo_9mm_batch'] = {
        key = 'ammo_9mm_batch',
        label = '9mm Cartridge Fabrication',
        facilityType = 'assembly',
        processingTime = 20,
        powerRequirementKw = 12,
        inputs = {
            { item = 'refined_copper', amount = 1 },
            { item = 'refined_iron', amount = 1 }
        },
        outputs = {
            {
                item = 'ammo_9mm',
                amount = 50
            }
        }
    },
    ['machinery_parts_fabrication'] = {
        key = 'machinery_parts_fabrication',
        label = 'Heavy Machinery & Turbine Parts',
        facilityType = 'assembly',
        processingTime = 35,
        powerRequirementKw = 25,
        inputs = {
            { item = 'refined_iron', amount = 4 },
            { item = 'refined_copper', amount = 2 },
            { item = 'plastic_polymer', amount = 2 }
        },
        outputs = {
            {
                item = 'crate_machinery_parts',
                amount = 1,
                metadata = {
                    quality = 1.00,
                    durability = 100.0
                }
            }
        }
    },
    ['industrial_fuel_refining'] = {
        key = 'industrial_fuel_refining',
        label = 'High-Grade Industrial Generator Fuel',
        facilityType = 'refinery',
        processingTime = 40,
        powerRequirementKw = 30,
        inputs = {
            { item = 'crude_oil', amount = 5 },
            { item = 'refined_iron', amount = 1 }
        },
        outputs = {
            {
                item = 'industrial_fuel',
                amount = 1,
                metadata = {
                    octaneRating = 95,
                    durability = 100.0
                }
            }
        }
    },
    ['steel_freight_pallet'] = {
        key = 'steel_freight_pallet',
        label = 'Structural Steel Freight Pallet Casting',
        facilityType = 'smelter',
        processingTime = 45,
        powerRequirementKw = 35,
        inputs = {
            { item = 'refined_iron', amount = 8 }
        },
        outputs = {
            {
                item = 'pallet_freight_steel',
                amount = 1,
                metadata = {
                    reinforced = true,
                    durability = 100.0
                }
            }
        }
    },
    ['civic_license_plates'] = {
        key = 'civic_license_plates',
        label = 'State Vehicle Registration License Plates',
        facilityType = 'penal_workshop',
        processingTime = 15,
        powerRequirementKw = 5,
        inputs = {
            { item = 'refined_iron', amount = 1 }
        },
        outputs = {
            {
                item = 'civic_license_plate',
                amount = 2,
                metadata = {
                    facility = 'bolingbroke_penitentiary',
                    durability = 100.0
                }
            }
        }
    },
    ['civic_road_barrier'] = {
        key = 'civic_road_barrier',
        label = 'Welded Steel Road Hazard Barrier',
        facilityType = 'penal_workshop',
        processingTime = 25,
        powerRequirementKw = 8,
        inputs = {
            { item = 'refined_iron', amount = 2 },
            { item = 'plastic_polymer', amount = 1 }
        },
        outputs = {
            {
                item = 'civic_road_barrier',
                amount = 1,
                metadata = {
                    facility = 'bolingbroke_penitentiary',
                    durability = 100.0
                }
            }
        }
    },
    ['civic_emergency_cot'] = {
        key = 'civic_emergency_cot',
        label = 'Collapsible Field Hospital Emergency Cot',
        facilityType = 'penal_workshop',
        processingTime = 30,
        powerRequirementKw = 6,
        inputs = {
            { item = 'refined_iron', amount = 1 },
            { item = 'raw_fabric', amount = 1 },
            { item = 'raw_timber', amount = 1 }
        },
        outputs = {
            {
                item = 'civic_emergency_cot',
                amount = 1,
                metadata = {
                    facility = 'bolingbroke_penitentiary',
                    durability = 100.0
                }
            }
        }
    },
    ['civic_wooden_pallet'] = {
        key = 'civic_wooden_pallet',
        label = 'Standard Milled Lumber Freight Pallet',
        facilityType = 'penal_workshop',
        processingTime = 20,
        powerRequirementKw = 6,
        inputs = {
            { item = 'raw_timber', amount = 2 },
            { item = 'refined_iron', amount = 1 }
        },
        outputs = {
            {
                item = 'civic_wooden_pallet',
                amount = 1,
                metadata = {
                    facility = 'bolingbroke_penitentiary',
                    durability = 100.0
                }
            }
        }
    }
}

function Nyx.Logistics.GetRecipe(recipeKey)
    return Nyx.Logistics.Recipes.Registry[recipeKey]
end

function Nyx.Logistics.GetAllRecipes()
    return Nyx.Logistics.Recipes.Registry
end
