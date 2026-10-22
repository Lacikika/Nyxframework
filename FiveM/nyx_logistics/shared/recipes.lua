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
    ['cattle_slaughtering'] = {
        key = 'cattle_slaughtering',
        label = 'Livestock Cattle Slaughtering & Dressing',
        facilityType = 'slaughterhouse',
        processingTime = 30,
        powerRequirementKw = 15,
        inputs = {
            { item = 'livestock_cattle', amount = 1 }
        },
        outputs = {
            {
                item = 'carcass_beef_raw',
                amount = 2,
                metadata = {
                    durability = 100.0,
                    isSpoiled = false
                }
            }
        }
    },
    ['carcass_butchering'] = {
        key = 'carcass_butchering',
        label = 'Cold-Chain Carcass Butchering & Palletizing',
        facilityType = 'slaughterhouse',
        processingTime = 25,
        powerRequirementKw = 20,
        inputs = {
            { item = 'carcass_beef_raw', amount = 1 }
        },
        outputs = {
            {
                item = 'packaged_meat_cuts',
                amount = 10,
                metadata = {
                    durability = 100.0,
                    isSpoiled = false,
                    nutrition = 50
                }
            },
            {
                item = 'pallet_refrigerated_beef',
                amount = 1,
                metadata = {
                    durability = 100.0,
                    temperatureC = 2.0
                }
            }
        }
    },
    ['livestock_feed_mixing'] = {
        key = 'livestock_feed_mixing',
        label = 'Industrial Livestock Feed Compounding',
        facilityType = 'refinery',
        processingTime = 20,
        powerRequirementKw = 10,
        inputs = {
            { item = 'bulk_cornmeal', amount = 2 }
        },
        outputs = {
            {
                item = 'livestock_feed_sack',
                amount = 1
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
    },
    ['wheat_milling'] = {
        key = 'wheat_milling',
        label = 'Industrial Wheat Milling (Flour)',
        facilityType = 'refinery',
        processingTime = 20,
        powerRequirementKw = 10,
        inputs = {
            { item = 'crop_wheat', amount = 4 }
        },
        outputs = {
            {
                item = 'bulk_flour',
                amount = 1,
                metadata = {
                    quality = 1.00,
                    durability = 100.0
                }
            }
        }
    },
    ['corn_milling'] = {
        key = 'corn_milling',
        label = 'Industrial Corn Milling (Cornmeal)',
        facilityType = 'refinery',
        processingTime = 20,
        powerRequirementKw = 10,
        inputs = {
            { item = 'crop_corn', amount = 4 }
        },
        outputs = {
            {
                item = 'bulk_cornmeal',
                amount = 1,
                metadata = {
                    quality = 1.00,
                    durability = 100.0
                }
            }
        }
    },
    ['bakery_bread'] = {
        key = 'bakery_bread',
        label = 'Commercial Artisan Bread Loaf Baking',
        facilityType = 'assembly',
        processingTime = 15,
        powerRequirementKw = 8,
        inputs = {
            { item = 'bulk_flour', amount = 1 },
            { item = 'drink_water', amount = 2 }
        },
        outputs = {
            {
                item = 'food_bread',
                amount = 4,
                metadata = {
                    durability = 100.0,
                    isSpoiled = false,
                    nutrition = 35
                }
            }
        }
    },
    ['produce_pallet_packaging'] = {
        key = 'produce_pallet_packaging',
        label = 'Agricultural Fresh Produce Palletizing',
        facilityType = 'assembly',
        processingTime = 25,
        powerRequirementKw = 6,
        inputs = {
            { item = 'crop_produce', amount = 10 },
            { item = 'civic_wooden_pallet', amount = 1 }
        },
        outputs = {
            {
                item = 'pallet_agricultural_produce',
                amount = 1,
                metadata = {
                    durability = 100.0
                }
            }
        }
    },
    ['saline_purification'] = {
        key = 'saline_purification',
        label = 'Isotonic Saline Solution Purification',
        facilityType = 'chemical',
        processingTime = 12,
        powerRequirementKw = 8,
        inputs = {
            { item = 'raw_saline_brine', amount = 2 },
            { item = 'drink_water', amount = 1 }
        },
        outputs = {
            {
                item = 'saline_solution',
                amount = 2,
                metadata = {
                    sterile = true,
                    osmolarity = 308
                }
            }
        }
    },
    ['synthetic_plasma_synthesis'] = {
        key = 'synthetic_plasma_synthesis',
        label = 'Sterile Blood Plasma Bio-Synthesis',
        facilityType = 'chemical',
        processingTime = 25,
        powerRequirementKw = 18,
        inputs = {
            { item = 'organic_compounds', amount = 2 },
            { item = 'saline_solution', amount = 1 },
            { item = 'plastic_polymer', amount = 1 }
        },
        outputs = {
            {
                item = 'med_plasma',
                amount = 1,
                metadata = {
                    sterile = true,
                    bloodType = 'O-Universal'
                }
            }
        }
    },
    ['disinfectant_compounding'] = {
        key = 'disinfectant_compounding',
        label = 'Clinical Disinfectant Compounding',
        facilityType = 'chemical',
        processingTime = 15,
        powerRequirementKw = 10,
        inputs = {
            { item = 'chemical_precursors', amount = 2 },
            { item = 'drink_water', amount = 1 }
        },
        outputs = {
            {
                item = 'item_disinfectant',
                amount = 2,
                metadata = {
                    sterility = 100.0
                }
            }
        }
    },
    ['timber_sawmill_milling'] = {
        key = 'timber_sawmill_milling',
        label = 'Heavy Redwood Timber Sawmill Milling',
        facilityType = 'sawmill',
        processingTime = 25,
        powerRequirementKw = 15,
        inputs = {
            { item = 'raw_timber_logs', amount = 4 }
        },
        outputs = {
            {
                item = 'raw_timber',
                amount = 2,
                metadata = {
                    durability = 100.0,
                    milled = true
                }
            },
            {
                item = 'wood_cellulose',
                amount = 2,
                metadata = {
                    pulpPurity = 0.98
                }
            }
        }
    },
    ['structural_sheet_rolling'] = {
        key = 'structural_sheet_rolling',
        label = 'Structural Steel Sheet Rolling & Leveling',
        facilityType = 'foundry',
        processingTime = 30,
        powerRequirementKw = 25,
        inputs = {
            { item = 'refined_iron', amount = 3 }
        },
        outputs = {
            {
                item = 'sheet_metal',
                amount = 2,
                metadata = {
                    alloyGrade = 'A36-Structural-Steel',
                    thicknessMm = 3.2
                }
            }
        }
    },
    ['copper_wire_drawing'] = {
        key = 'copper_wire_drawing',
        label = 'Electrical Copper Wire Extrusion & Drawing',
        facilityType = 'foundry',
        processingTime = 20,
        powerRequirementKw = 20,
        inputs = {
            { item = 'refined_copper', amount = 2 },
            { item = 'plastic_polymer', amount = 1 }
        },
        outputs = {
            {
                item = 'copper_wire',
                amount = 3,
                metadata = {
                    gauge = '12-AWG',
                    conductivityRating = 0.99
                }
            }
        }
    },
    ['textile_cotton_carding'] = {
        key = 'textile_cotton_carding',
        label = 'Cotton Carding & Industrial Textile Weaving',
        facilityType = 'textile',
        processingTime = 20,
        powerRequirementKw = 12,
        inputs = {
            { item = 'raw_cotton', amount = 4 }
        },
        outputs = {
            {
                item = 'raw_fabric',
                amount = 2,
                metadata = {
                    threadCount = 200,
                    weave = 'twill'
                }
            }
        }
    },
    ['circuit_board_fabrication'] = {
        key = 'circuit_board_fabrication',
        label = 'Phenolic Resin Circuit Board Substrate Bonding',
        facilityType = 'chemical',
        processingTime = 25,
        powerRequirementKw = 15,
        inputs = {
            { item = 'plastic_polymer', amount = 2 },
            { item = 'chemical_precursors', amount = 1 }
        },
        outputs = {
            {
                item = 'circuit_substrate',
                amount = 2,
                metadata = {
                    dielectricStrength = '15kV/mm'
                }
            }
        }
    },
    ['electronics_assembly'] = {
        key = 'electronics_assembly',
        label = 'Microcontroller Soldering & Electronic Assembly',
        facilityType = 'assembly',
        processingTime = 20,
        powerRequirementKw = 10,
        inputs = {
            { item = 'copper_wire', amount = 2 },
            { item = 'circuit_substrate', amount = 1 }
        },
        outputs = {
            {
                item = 'electronic_circuit',
                amount = 2,
                metadata = {
                    firmwareVersion = 'v2.4-Civil'
                }
            }
        }
    },
    ['precision_weapon_parts_machining'] = {
        key = 'precision_weapon_parts_machining',
        label = 'Precision Firearm Receiver & Barrel Machining',
        facilityType = 'assembly',
        processingTime = 30,
        powerRequirementKw = 18,
        inputs = {
            { item = 'sheet_metal', amount = 2 },
            { item = 'refined_iron', amount = 1 }
        },
        outputs = {
            {
                item = 'item_weapon_parts',
                amount = 1,
                metadata = {
                    tolerance = '0.005mm'
                }
            }
        }
    },
    ['wire_cutters_assembly'] = {
        key = 'wire_cutters_assembly',
        label = 'Insulated Wire Cutters Forging & Assembly',
        facilityType = 'assembly',
        processingTime = 15,
        powerRequirementKw = 8,
        inputs = {
            { item = 'refined_iron', amount = 1 },
            { item = 'plastic_polymer', amount = 1 }
        },
        outputs = {
            {
                item = 'wire_cutters',
                amount = 1,
                metadata = {
                    durability = 100.0,
                    insulated = true
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
