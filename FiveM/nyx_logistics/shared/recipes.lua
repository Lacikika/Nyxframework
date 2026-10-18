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
    }
}

function Nyx.Logistics.GetRecipe(recipeKey)
    return Nyx.Logistics.Recipes.Registry[recipeKey]
end
