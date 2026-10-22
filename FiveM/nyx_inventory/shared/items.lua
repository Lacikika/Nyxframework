--[[
    Nyxframework: nyx_inventory
    File: shared/items.lua
    Description: Declarative item schema registry with weights, types, decay rates, and metadata generators.
]]

Nyx = Nyx or {}
Nyx.Items = {}

-- Comprehensive Item Registry
Nyx.Items.Registry = {
    -- Firearms & Weapons
    ['weapon_pistol'] = {
        name = 'weapon_pistol',
        label = 'Standard Pistol',
        weight = 1000,
        stackable = false,
        maxSlots = 1,
        type = 'weapon',
        decayRate = 0.01,
        description = 'A standard 9mm service pistol.',
        client = {
            model = `w_pi_pistol`,
            animDict = 'reaction@intimidation@1h',
            anim = 'intro'
        }
    },
    ['weapon_combatpistol'] = {
        name = 'weapon_combatpistol',
        label = 'Combat Pistol',
        weight = 1200,
        stackable = false,
        maxSlots = 1,
        type = 'weapon',
        decayRate = 0.015,
        description = 'A high-grade tactical sidearm with low recoil.',
        client = {
            model = `w_pi_combatpistol`,
            animDict = 'reaction@intimidation@1h',
            anim = 'intro'
        }
    },
    ['weapon_smg'] = {
        name = 'weapon_smg',
        label = 'Submachine Gun',
        weight = 2500,
        stackable = false,
        maxSlots = 1,
        type = 'weapon',
        decayRate = 0.02,
        description = 'Compact submachine gun firing 9mm rounds at high velocity.',
        client = {
            model = `w_sb_smg`
        }
    },
    ['weapon_carbinerifle'] = {
        name = 'weapon_carbinerifle',
        label = 'Carbine Rifle',
        weight = 3400,
        stackable = false,
        maxSlots = 1,
        type = 'weapon',
        decayRate = 0.025,
        description = 'Military-specification carbine for medium to long-range encounters.',
        client = {
            model = `w_ar_carbinerifle`
        }
    },
    ['weapon_pumpshotgun'] = {
        name = 'weapon_pumpshotgun',
        label = 'Pump Shotgun',
        weight = 3600,
        stackable = false,
        maxSlots = 1,
        type = 'weapon',
        decayRate = 0.02,
        description = '12-gauge close-quarters breaching and defense firearm.',
        client = {
            model = `w_sg_pumpshotgun`
        }
    },

    -- Ammunition
    ['ammo_9mm'] = {
        name = 'ammo_9mm',
        label = '9mm Ammunition',
        weight = 20,
        stackable = true,
        maxStack = 100,
        type = 'ammo',
        description = 'Box of standard full-metal jacket 9mm cartridges.'
    },
    ['ammo_rifle'] = {
        name = 'ammo_rifle',
        label = '5.56mm Ammunition',
        weight = 30,
        stackable = true,
        maxStack = 60,
        type = 'ammo',
        description = 'High-velocity 5.56x45mm intermediate rifle cartridges.'
    },
    ['ammo_shotgun'] = {
        name = 'ammo_shotgun',
        label = '12 Gauge Shells',
        weight = 45,
        stackable = true,
        maxStack = 30,
        type = 'ammo',
        description = 'Heavy 12-gauge buckshot rounds.'
    },

    -- Consumables & Perishables
    ['food_ration'] = {
        name = 'food_ration',
        label = 'Civil Defense Ration',
        weight = 400,
        stackable = true,
        maxStack = 10,
        type = 'food',
        decayRate = 0.03,
        nutrition = 45,
        description = 'Preserved high-protein civil emergency meal packet.'
    },
    ['food_sandwich'] = {
        name = 'food_sandwich',
        label = 'Fresh Sandwich',
        weight = 250,
        stackable = true,
        maxStack = 10,
        type = 'food',
        decayRate = 0.10,
        nutrition = 25,
        description = 'Handcrafted deli sandwich. Perishable.'
    },
    ['food_bread'] = {
        name = 'food_bread',
        label = 'Fresh Artisan Bread Loaf',
        weight = 500,
        stackable = true,
        maxStack = 10,
        type = 'food',
        decayRate = 0.08,
        nutrition = 35,
        description = 'Freshly baked crusty artisan bread loaf. Perishable staple.'
    },
    ['crop_produce'] = {
        name = 'crop_produce',
        label = 'Fresh Farm Produce Basket',
        weight = 1200,
        stackable = true,
        maxStack = 20,
        type = 'food',
        decayRate = 0.06,
        nutrition = 20,
        description = 'Assorted fresh harvest fruits and garden vegetables. Highly perishable without cold storage.'
    },
    ['drink_water'] = {
        name = 'drink_water',
        label = 'Purified Water',
        weight = 500,
        stackable = true,
        maxStack = 10,
        type = 'drink',
        decayRate = 0.01,
        hydration = 35,
        description = 'Clean 500ml bottle of municipal spring water.'
    },
    ['drink_coffee'] = {
        name = 'drink_coffee',
        label = 'Hot Espresso',
        weight = 200,
        stackable = true,
        maxStack = 5,
        type = 'drink',
        decayRate = 0.08,
        hydration = 20,
        description = 'Dark roast espresso shot providing a quick energy boost.'
    },

    -- Medical Supplies
    ['med_bandage'] = {
        name = 'med_bandage',
        label = 'Sterile Bandage',
        weight = 100,
        stackable = true,
        maxStack = 15,
        type = 'medical',
        healAmount = 25,
        description = 'Compressed sterile gauze for superficial wound treatment.'
    },
    ['med_firstaid'] = {
        name = 'med_firstaid',
        label = 'Trauma First Aid Kit',
        weight = 1200,
        stackable = true,
        maxStack = 5,
        type = 'medical',
        healAmount = 75,
        description = 'Comprehensive surgical kit for stabilization of severe trauma.'
    },
    ['med_plasma'] = {
        name = 'med_plasma',
        label = 'Sterile Blood Plasma',
        weight = 500,
        stackable = true,
        maxStack = 10,
        type = 'medical',
        description = 'Refrigerated IV unit of synthetic sterile plasma for resuscitation.'
    },
    ['med_surgical_pack'] = {
        name = 'med_surgical_pack',
        label = 'Sterile Surgical Pack',
        weight = 1500,
        stackable = true,
        maxStack = 5,
        type = 'medical',
        description = 'Autoclaved surgical pack with hemostats, scalpel, and suturing gear.'
    },
    ['saline_solution'] = {
        name = 'saline_solution',
        label = 'Purified Isotonic Saline IV',
        weight = 500,
        stackable = true,
        maxStack = 10,
        type = 'medical',
        description = 'Sterile 0.9% sodium chloride isotonic solution for intravenous resuscitation and medication delivery.'
    },
    ['item_disinfectant'] = {
        name = 'item_disinfectant',
        label = 'Clinical Hospital Disinfectant',
        weight = 800,
        stackable = true,
        maxStack = 10,
        type = 'medical',
        description = 'Hospital-grade bactericidal and virucidal surface sanitizer for medical beds and surgical suites.'
    },
    ['clean_linens'] = {
        name = 'clean_linens',
        label = 'Sterilized Hospital Bed Linens',
        weight = 1200,
        stackable = true,
        maxStack = 5,
        type = 'medical',
        description = 'Autoclaved hypoallergenic cotton bed linens for maintaining clinical triage recovery beds.'
    },
    ['bleach'] = {
        name = 'bleach',
        label = 'Industrial Chemical Bleach (5L)',
        weight = 2500,
        stackable = true,
        maxStack = 5,
        type = 'utility',
        description = 'High-strength sodium hypochlorite solution for industrial sterilization and deep disinfection.'
    },
    ['bandage_sterile'] = {
        name = 'bandage_sterile',
        label = 'Sterile Pressure Bandage',
        weight = 100,
        stackable = true,
        maxStack = 20,
        type = 'medical',
        healAmount = 25,
        bleedReduction = 0.5,
        description = 'Compressed sterile pressure bandage for field dressing of lacerations and bleeding control.'
    },
    ['first_aid_pack'] = {
        name = 'first_aid_pack',
        label = 'Tactical First Aid Pack',
        weight = 1200,
        stackable = true,
        maxStack = 5,
        type = 'medical',
        healAmount = 60,
        fractureStabilization = true,
        description = 'Tactical trauma first aid pack containing hemostatic gauze, pressure dressing, and bone splints.'
    },
    ['tourniquet'] = {
        name = 'tourniquet',
        label = 'Combat Application Tourniquet',
        weight = 150,
        stackable = true,
        maxStack = 10,
        type = 'medical',
        arrestsArterial = true,
        description = 'Combat application tourniquet designed for rapid extremity arterial occlusion.'
    },
    ['splint'] = {
        name = 'splint',
        label = 'Malleable Structural Splint',
        weight = 300,
        stackable = true,
        maxStack = 5,
        type = 'medical',
        treatsFracture = true,
        description = 'Malleable structural aluminum splint for immobilizing fractured limb bones.'
    },
    ['morphine_ampoule'] = {
        name = 'morphine_ampoule',
        label = 'Morphine Sulfate Ampoule (10mg)',
        weight = 50,
        stackable = true,
        maxStack = 10,
        type = 'medical',
        painRelief = 100,
        description = 'Injectable opioid analgesic for acute traumatic shock and severe pain suppression.'
    },
    ['industrial_fuel'] = {
        name = 'industrial_fuel',
        label = 'Industrial Generator Fuel (50L)',
        weight = 25000,
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        description = 'Heavy sealed drum of refined diesel fuel for substation turbine generators.'
    },
    ['bulk_fuel_tank'] = {
        name = 'bulk_fuel_tank',
        label = 'Commercial Bulk Fuel Pod (500L)',
        weight = 75000,
        stackable = true,
        maxStack = 10,
        type = 'freight',
        description = 'Standardized commercial tanker pod carrying 500 liters of refined fuel for station reservoirs.'
    },
    ['fuel_canister'] = {
        name = 'fuel_canister',
        label = 'Emergency Fuel Jerrycan (20L)',
        weight = 15000,
        stackable = false,
        maxSlots = 1,
        type = 'utility',
        description = 'Portable heavy-duty jerrycan with 20 liters of emergency fuel for roadside refueling.'
    },

    -- Industrial Materials & Logistics
    ['refined_iron'] = {
        name = 'refined_iron',
        label = 'Refined Iron Ingot',
        weight = 2500,
        stackable = true,
        maxStack = 20,
        type = 'material',
        description = 'Standard smelted industrial iron bar for fabrication.'
    },
    ['refined_copper'] = {
        name = 'refined_copper',
        label = 'Copper Plate',
        weight = 1800,
        stackable = true,
        maxStack = 25,
        type = 'material',
        description = 'High-conductivity rolled copper plate.'
    },
    ['plastic_polymer'] = {
        name = 'plastic_polymer',
        label = 'Industrial Polymer',
        weight = 500,
        stackable = true,
        maxStack = 50,
        type = 'material',
        description = 'Pelletized thermal plastic for injection molding.'
    },
    ['raw_fabric'] = {
        name = 'raw_fabric',
        label = 'Industrial Cotton/Fabric Roll',
        weight = 1200,
        stackable = true,
        maxStack = 30,
        type = 'material',
        description = 'Raw bolt of heavy industrial cotton and synthetic fabric for garment and uniform production.'
    },
    ['raw_timber'] = {
        name = 'raw_timber',
        label = 'Industrial Lumber Bundle',
        weight = 4000,
        stackable = true,
        maxStack = 20,
        type = 'material',
        description = 'Heavy-grade milled timber planks and lumber studs for civic and industrial assembly.'
    },
    ['raw_timber_logs'] = {
        name = 'raw_timber_logs',
        label = 'Felled Timber Raw Logs',
        weight = 5000,
        stackable = true,
        maxStack = 10,
        type = 'material',
        description = 'Heavy unhewn pine and redwood logs harvested from regional forestry tracts, ready for sawmill processing.'
    },
    ['raw_cotton'] = {
        name = 'raw_cotton',
        label = 'Raw Harvested Cotton Bolls',
        weight = 400,
        stackable = true,
        maxStack = 50,
        type = 'material',
        description = 'Uncarded raw agricultural cotton bolls harvested from coastal plantations for textile spinning.'
    },
    ['wood_cellulose'] = {
        name = 'wood_cellulose',
        label = 'Purified Wood Pulp Cellulose',
        weight = 800,
        stackable = true,
        maxStack = 40,
        type = 'material',
        description = 'Processed wood fibers and chemical cellulose pulp used in paper printing, cardboard packaging, and composite materials.'
    },
    ['sheet_metal'] = {
        name = 'sheet_metal',
        label = 'Rolled Structural Sheet Metal',
        weight = 3500,
        stackable = true,
        maxStack = 20,
        type = 'material',
        description = 'High-strength cold-rolled structural steel sheet plate for precision metal stamping, tool fabrication, and vehicle chassis repairs.'
    },
    ['copper_wire'] = {
        name = 'copper_wire',
        label = 'Industrial Copper Wire Spool',
        weight = 1200,
        stackable = true,
        maxStack = 25,
        type = 'material',
        description = 'Continuous spool of insulated high-conductivity electrical copper wiring for circuitry, motors, and grid repairs.'
    },
    ['circuit_substrate'] = {
        name = 'circuit_substrate',
        label = 'Phenolic Circuit Board Substrate',
        weight = 300,
        stackable = true,
        maxStack = 50,
        type = 'material',
        description = 'Resin-bonded flame-retardant fiberglass substrate ready for conductive etching and electronic soldering.'
    },
    ['electronic_circuit'] = {
        name = 'electronic_circuit',
        label = 'Microcontroller Logic Circuit Board',
        weight = 500,
        stackable = true,
        maxStack = 30,
        type = 'material',
        description = 'Assembled solid-state microcontroller and printed logic circuit board for telemetry systems, radios, and diagnostics.'
    },
    ['item_weapon_parts'] = {
        name = 'item_weapon_parts',
        label = 'Precision Firearm Mechanical Parts',
        weight = 1500,
        stackable = true,
        maxStack = 10,
        type = 'material',
        description = 'Milled steel slide, trigger assembly, and precision recoil springs for assembly into functional ballistic firearms.'
    },
    ['raw_saline_brine'] = {
        name = 'raw_saline_brine',
        label = 'Raw Saline Mineral Brine',
        weight = 1000,
        stackable = true,
        maxStack = 20,
        type = 'material',
        description = 'Concentrated mineral salt water harvested from coastal estuaries and subterranean saline aquifers.'
    },
    ['organic_compounds'] = {
        name = 'organic_compounds',
        label = 'Medicinal Organic Compounds',
        weight = 400,
        stackable = true,
        maxStack = 50,
        type = 'material',
        description = 'Extracted botanical alkaloids and active organic biological compounds for pharmaceutical synthesis.'
    },
    ['chemical_precursors'] = {
        name = 'chemical_precursors',
        label = 'Petrochemical & Sulfur Precursors',
        weight = 600,
        stackable = true,
        maxStack = 50,
        type = 'material',
        description = 'Purified chemical reagents and petrochemical feedstocks required for synthetic drug compounding.'
    },
    ['civic_license_plate'] = {
        name = 'civic_license_plate',
        label = 'Stamped State License Plate',
        weight = 500,
        stackable = true,
        maxStack = 20,
        type = 'utility',
        description = 'Official stamped aluminum vehicle registration plate produced via correctional penal labor.'
    },
    ['civic_road_barrier'] = {
        name = 'civic_road_barrier',
        label = 'Welded Steel Road Barrier',
        weight = 15000,
        stackable = true,
        maxStack = 5,
        type = 'utility',
        description = 'High-visibility welded steel road barrier for municipal traffic redirection and public works.'
    },
    ['civic_inmate_uniform'] = {
        name = 'civic_inmate_uniform',
        label = 'Penal Workwear Jumpsuit',
        weight = 800,
        stackable = true,
        maxStack = 10,
        type = 'utility',
        description = 'Standard-issue high-visibility durable denim/canvas correctional jumpsuit manufactured by inmates.'
    },
    ['civic_emergency_cot'] = {
        name = 'civic_emergency_cot',
        label = 'Emergency Field Cot',
        weight = 10000,
        stackable = true,
        maxStack = 5,
        type = 'utility',
        description = 'Collapsible reinforced canvas and tubular steel field bed for municipal emergency shelters and field clinics.'
    },
    ['civic_wooden_pallet'] = {
        name = 'civic_wooden_pallet',
        label = 'Standard Freight Wooden Pallet',
        weight = 12000,
        stackable = true,
        maxStack = 5,
        type = 'freight',
        description = 'Standardized heavy lumber freight pallet for forklift logistics and warehouse storage.'
    },
    ['pallet_sheet_metal'] = {
        name = 'pallet_sheet_metal',
        label = 'Sheet Metal Pallet',
        weight = 15000,
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        description = 'Heavy industrial shipment crate containing pressed structural steel.'
    },
    ['crop_wheat'] = {
        name = 'crop_wheat',
        label = 'Raw Harvested Wheat Sheaf',
        weight = 800,
        stackable = true,
        maxStack = 50,
        type = 'material',
        decayRate = 0.015,
        description = 'Harvested golden wheat sheaf from regional agricultural farmland, ready for industrial milling into flour.'
    },
    ['crop_corn'] = {
        name = 'crop_corn',
        label = 'Field Harvest Corn Ears',
        weight = 600,
        stackable = true,
        maxStack = 50,
        type = 'material',
        decayRate = 0.02,
        description = 'Freshly harvested yellow field corn ears for milling and animal feed.'
    },
    ['bulk_flour'] = {
        name = 'bulk_flour',
        label = 'Commercial Milled Flour Sack',
        weight = 25000,
        stackable = true,
        maxStack = 10,
        type = 'freight',
        decayRate = 0.002,
        description = 'Heavy 25kg commercial sack of fine milled wheat flour. Shelf-stable industrial bulk baking staple.'
    },
    ['bulk_cornmeal'] = {
        name = 'bulk_cornmeal',
        label = 'Industrial Cornmeal Sack',
        weight = 25000,
        stackable = true,
        maxStack = 10,
        type = 'freight',
        decayRate = 0.002,
        description = 'Heavy 25kg sack of milled yellow cornmeal for industrial food manufacturing and livestock feed.'
    },
    ['pallet_agricultural_produce'] = {
        name = 'pallet_agricultural_produce',
        label = 'Agricultural Bulk Produce Pallet',
        weight = 75000,
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        isHeavyFreight = true,
        decayRate = 0.00,
        description = 'Heavy freight wooden pallet loaded with crates of fresh regional farm harvest and milled grains.',
        client = {
            model = `prop_boxpile_06a`,
            animDict = 'anim@heists@box_carry@',
            anim = 'idle',
            attachOffset = { x = 0.0, y = 0.48, z = -0.20 },
            attachRot = { x = 0.0, y = 0.0, z = 0.0 }
        }
    },
    ['livestock_cattle'] = {
        name = 'livestock_cattle',
        label = 'Live Cattle Head',
        weight = 100000,
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        isHeavyFreight = true,
        decayRate = 0.00,
        description = 'Live cattle livestock head harvested from regional ranches for transit and slaughterhouse processing.',
        client = {
            model = `a_c_cow`,
            animDict = 'anim@heists@box_carry@',
            anim = 'idle'
        }
    },
    ['carcass_beef_raw'] = {
        name = 'carcass_beef_raw',
        label = 'Whole Raw Beef Carcass',
        weight = 45000,
        stackable = false,
        maxSlots = 1,
        type = 'food',
        isHeavyFreight = true,
        decayRate = 0.12,
        description = 'Whole dressed beef carcass. Highly perishable; requires refrigerated storage or rapid butchering.',
        client = {
            model = `prop_box_wood02a`
        }
    },
    ['packaged_meat_cuts'] = {
        name = 'packaged_meat_cuts',
        label = 'Vacuum-Packed Premium Beef Cuts',
        weight = 1000,
        stackable = true,
        maxStack = 20,
        type = 'food',
        decayRate = 0.05,
        nutrition = 50,
        description = 'Butchered and vacuum-sealed choice beef cuts for restaurants, supermarkets, and civil pantries.'
    },
    ['pallet_refrigerated_beef'] = {
        name = 'pallet_refrigerated_beef',
        label = 'Chilled Beef Freight Pallet',
        weight = 80000,
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        isHeavyFreight = true,
        decayRate = 0.01,
        description = 'Cold-chain insured freight pallet of chilled beef cuts. Requires refrigerated freight transport.',
        client = {
            model = `prop_boxpile_06a`,
            animDict = 'anim@heists@box_carry@',
            anim = 'idle',
            attachOffset = { x = 0.0, y = 0.48, z = -0.20 },
            attachRot = { x = 0.0, y = 0.0, z = 0.0 }
        }
    },
    ['livestock_feed_sack'] = {
        name = 'livestock_feed_sack',
        label = 'Nutritional Livestock Feed Sack (25kg)',
        weight = 25000,
        stackable = true,
        maxStack = 10,
        type = 'freight',
        decayRate = 0.00,
        description = 'Enriched grain and cornmeal livestock feed sack for cattle ranch husbandry.'
    },

    -- Tools & Valuables
    ['tool_lockpick'] = {
        name = 'tool_lockpick',
        label = 'Precision Lockpick',
        weight = 150,
        stackable = true,
        maxStack = 5,
        type = 'tool',
        decayRate = 0.25,
        description = 'Hardened steel pick set for tumbler bypass operations.'
    },
    ['tool_repairkit'] = {
        name = 'tool_repairkit',
        label = 'Vehicle Repair Kit',
        weight = 5000,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        description = 'Mechanical toolkit with pneumatic wrenches and diagnostic meters.'
    },
    ['tool_radio'] = {
        name = 'tool_radio',
        label = 'Encrypted Handheld Radio',
        weight = 600,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        description = 'Military-grade handheld transceiver with frequency encryption.'
    },
    ['wire_cutters'] = {
        name = 'wire_cutters',
        label = 'Insulated Wire Cutters',
        weight = 800,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        decayRate = 0.05,
        description = 'High-voltage rated insulated wire and cable cutters capable of severing industrial conduits.'
    },
    ['thermite_charge'] = {
        name = 'thermite_charge',
        label = 'Thermite Incendiary Charge',
        weight = 1500,
        stackable = true,
        maxStack = 5,
        type = 'utility',
        decayRate = 0.00,
        description = 'Pyrotechnic chemical incendiary compound capable of melting through reinforced steel and electrical transformers.'
    },
    ['tool_crowbar'] = {
        name = 'tool_crowbar',
        label = 'Heavy Forged Crowbar',
        weight = 2500,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        decayRate = 0.04,
        description = 'Hardened high-carbon steel wrecking bar used for prying open sealed freight pallets, crates, and security bandings.'
    },
    ['tool_angle_grinder'] = {
        name = 'tool_angle_grinder',
        label = 'High-Speed Cordless Angle Grinder',
        weight = 3200,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        decayRate = 0.03,
        description = 'Industrial cordless rotary angle grinder equipped with a metal cutting and abrading arbor.'
    },
    ['grinding_disk'] = {
        name = 'grinding_disk',
        label = 'Abrasive Metal Grinding Disk (4.5in)',
        weight = 200,
        stackable = true,
        maxStack = 10,
        type = 'utility',
        decayRate = 0.00,
        description = 'Reinforced aluminum-oxide abrasive grinding disk for grinding down welds and firearm serial stamps.'
    },
    ['acid_etch_kit'] = {
        name = 'acid_etch_kit',
        label = 'Forensic Acid-Etch Chemical Kit',
        weight = 1200,
        stackable = true,
        maxStack = 5,
        type = 'tool',
        decayRate = 0.00,
        description = 'Forensic metallurgical restoration kit containing Fry\'s reagent (acidic cupric chloride) and nitric etching acid.'
    },
    ['tamper_seal'] = {
        name = 'tamper_seal',
        label = 'Serialized Tamper Seal',
        weight = 50,
        stackable = true,
        maxStack = 20,
        type = 'utility',
        decayRate = 0.00,
        description = 'Heavy-duty numbered bolt & steel cable seal with tamper-evident indicator for securing freight pallets.'
    },
    ['id_card'] = {
        name = 'id_card',
        label = 'Civil Identity Card',
        weight = 10,
        stackable = false,
        maxSlots = 1,
        type = 'valuable',
        description = 'Official state-issued biometric identity card.'
    },
    ['equity_shares'] = {
        name = 'equity_shares',
        label = 'Corporate Equity Share Certificate',
        weight = 50,
        stackable = false,
        maxSlots = 1,
        type = 'document',
        decayRate = 0.0,
        description = 'Certified bearer share certificate representing fractional equity ownership in a registered corporation.'
    },
    ['evidence_bag'] = {
        name = 'evidence_bag',
        label = 'Forensic Evidence Bag',
        weight = 100,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        description = 'Tamper-evident sealed bag storing physical evidence with cryptographic metadata.'
    },
    ['latex_gloves'] = {
        name = 'latex_gloves',
        label = 'Latex Examination Gloves',
        weight = 50,
        stackable = true,
        maxStack = 20,
        type = 'tool',
        description = 'Disposable powder-free latex gloves to prevent crime scene contamination.'
    },
    ['nitrile_gloves'] = {
        name = 'nitrile_gloves',
        label = 'Nitrile Forensic Gloves',
        weight = 50,
        stackable = true,
        maxStack = 20,
        type = 'tool',
        description = 'Heavy-duty nitrile examination gloves for forensic evidence handling.'
    },
    ['forensic_kit'] = {
        name = 'forensic_kit',
        label = 'Forensic Field Kit',
        weight = 2500,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        description = 'Comprehensive forensic field toolkit with UV luminol, swabs, and tweezers.'
    },
    ['forensic_swab'] = {
        name = 'forensic_swab',
        label = 'Sterile Forensic Swab',
        weight = 20,
        stackable = true,
        maxStack = 20,
        type = 'tool',
        description = 'Sterile cotton applicator for biological DNA, gunshot residue, and chemical sampling.'
    },
    ['camera_forensic'] = {
        name = 'camera_forensic',
        label = 'High-Resolution Forensic Camera',
        weight = 850,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        description = 'Calibrated digital camera embedding cryptographic timestamp & EXIF sensor telemetry.'
    },
    ['car_keys'] = {
        name = 'car_keys',
        label = 'Vehicle Key Fob',
        weight = 50,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        description = 'Electronic proximity key fob encoding encrypted vehicle VIN & plate data.'
    },
    ['item_vehicle_key'] = {
        name = 'item_vehicle_key',
        label = 'Physical Vehicle Key',
        weight = 30,
        stackable = false,
        maxSlots = 1,
        type = 'tool',
        description = 'Physical laser-cut ignition key and transponder chip bound to vehicle VIN and license plate.'
    },
    ['rfid_fleet_card'] = {
        name = 'rfid_fleet_card',
        label = 'Corporate Fleet RFID Pass',
        weight = 15,
        stackable = false,
        maxSlots = 1,
        type = 'valuable',
        description = 'Encrypted high-frequency NFC/RFID transponder card granting proximity access to corporate fleet vehicles.'
    },

    -- Heavy Freight & Industrial Crates (> 50kg, cannot be stored in player backpack)
    ['crate_industrial_heavy'] = {
        name = 'crate_industrial_heavy',
        label = 'Heavy Industrial Freight Crate',
        weight = 65000, -- 65 kg > 50kg limit
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        isHeavyFreight = true,
        decayRate = 0.00,
        description = 'Reinforced heavy industrial cargo crate. Prohibited from personal backpacks; requires two-handed carry or freight transport.',
        client = {
            model = `prop_box_wood02a`,
            animDict = 'anim@heists@box_carry@',
            anim = 'idle',
            attachOffset = { x = 0.0, y = 0.40, z = -0.15 },
            attachRot = { x = 0.0, y = 0.0, z = 0.0 }
        }
    },
    ['pallet_freight_steel'] = {
        name = 'pallet_freight_steel',
        label = 'Heavy Steel Structural Pallet',
        weight = 85000, -- 85 kg > 50kg limit
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        isHeavyFreight = true,
        decayRate = 0.00,
        description = 'Industrial structural steel freight pallet. Requires two-handed carry, ground dragging, or forklift transport.',
        client = {
            model = `prop_boxpile_06a`,
            animDict = 'anim@heists@box_carry@',
            anim = 'idle',
            attachOffset = { x = 0.0, y = 0.48, z = -0.20 },
            attachRot = { x = 0.0, y = 0.0, z = 0.0 }
        }
    },
    ['crate_machinery_parts'] = {
        name = 'crate_machinery_parts',
        label = 'Machinery Spare Parts Crate',
        weight = 55000, -- 55 kg > 50kg limit
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        isHeavyFreight = true,
        decayRate = 0.00,
        description = 'Dense crate carrying heavy mechanical machinery replacement parts.',
        client = {
            model = `prop_wooden_crate_01`,
            animDict = 'anim@heists@box_carry@',
            anim = 'idle',
            attachOffset = { x = 0.0, y = 0.42, z = -0.15 },
            attachRot = { x = 0.0, y = 0.0, z = 0.0 }
        }
    },

    -- Illicit Financial & Laundering Currency
    ['dirty_money'] = {
        name = 'dirty_money',
        label = 'Illicit Cash Stack',
        weight = 100,
        stackable = true,
        maxStack = 100,
        type = 'currency',
        decayRate = 0.00,
        description = 'Banded stacks of untaxed, unregistered cash from illicit commerce. Must be laundered through commercial fronts.',
        client = {
            model = `prop_cash_pile_02`
        }
    },
    ['marked_bills'] = {
        name = 'marked_bills',
        label = 'Dye-Pack Marked Bills',
        weight = 150,
        stackable = true,
        maxStack = 50,
        type = 'contraband',
        decayRate = 0.00,
        description = 'Bundles of bank cash contaminated with forensic security dye. High forensic anomaly profile.',
        client = {
            model = `prop_anim_cash_pile_01`
        }
    },

    -- Armored Banking & High-Value Cash Transit
    ['armored_cash_box'] = {
        name = 'armored_cash_box',
        label = 'Armored High-Value Cash Box',
        weight = 12000, -- 12 kg
        stackable = false,
        maxSlots = 1,
        type = 'freight',
        isHeavyFreight = true,
        decayRate = 0.00,
        description = 'Reinforced titanium-alloy cash transit box with biometric tamper seals and GPS telemetry.',
        client = {
            model = `prop_security_case_01`,
            animDict = 'anim@heists@box_carry@',
            anim = 'idle',
            attachOffset = { x = 0.0, y = 0.45, z = -0.18 },
            attachRot = { x = 0.0, y = 0.0, z = 0.0 }
        }
    },
    ['cash_transit_manifest'] = {
        name = 'cash_transit_manifest',
        label = 'Cash-In-Transit Security Manifest',
        weight = 50,
        stackable = false,
        maxSlots = 1,
        type = 'document',
        decayRate = 0.00,
        description = 'Certified bill of lading for armored commercial cash collection and municipal vault deposit.',
        client = {
            model = `prop_cs_clipboard`
        }
    }
}

-- Lookup item definition
function Nyx.Items.Get(name)
    return Nyx.Items.Registry[name]
end

-- Check if item or stack constitutes heavy freight (> 50kg or isHeavyFreight flag)
function Nyx.Items.IsHeavyFreight(name, amount)
    local item = Nyx.Items.Registry[name]
    if not item then return false end
    if item.isHeavyFreight then return true end

    local totalWeight = (item.weight or 0) * (tonumber(amount) or 1)
    local threshold = (Config and Config.HeavyFreightThreshold) or 50000
    return totalWeight > threshold
end

-- Calculate cumulative weight in grams
function Nyx.Items.GetWeight(name, amount)
    local item = Nyx.Items.Registry[name]
    if not item then return 0 end
    return (item.weight or 0) * (tonumber(amount) or 1)
end

-- Generate standardized default metadata based on item archetype
function Nyx.Items.CreateDefaultMetadata(name, extra)
    local item = Nyx.Items.Registry[name]
    local meta = {
        createdAt = os.time(),
        durability = 100.0,
        maxDurability = 100.0,
        decayRate = item and item.decayRate or 0.0
    }

    if item then
        if item.type == 'weapon' then
            meta.serialNumber = string.format("NYX-%06d", math.random(100000, 999999))
            meta.components = {}
            meta.loadedAmmo = 0
            meta.scratched = false
        elseif item.type == 'food' or item.type == 'drink' then
            meta.isSpoiled = false
            meta.nutrition = item.nutrition or item.hydration or 0
        elseif item.name == 'item_vehicle_key' or item.name == 'car_keys' then
            meta.vin = (type(extra) == "table" and extra.vin) or "NYX-UNKNOWN"
            meta.plate = (type(extra) == "table" and extra.plate) or "NYX-000"
            meta.keyType = (type(extra) == "table" and extra.keyType) or "master"
            meta.issuedAt = os.time()
        elseif item.name == 'rfid_fleet_card' then
            meta.tokenUuid = (type(extra) == "table" and extra.tokenUuid) or ("rfid-" .. tostring(os.time()))
            meta.factionId = (type(extra) == "table" and extra.factionId) or "corp_logistics"
            meta.accessLevel = (type(extra) == "table" and extra.accessLevel) or "driver"
            meta.isRevoked = false
            meta.issuedAt = os.time()
        elseif item.name == 'civic_license_plate' then
            meta.plate = (type(extra) == "table" and extra.plate) or string.format("SA%04d", math.random(1000, 9999))
            meta.stampedAt = os.time()
            meta.facility = "bolingbroke_penitentiary"
        elseif item.name == 'civic_inmate_uniform' then
            meta.inmateNumber = (type(extra) == "table" and extra.inmateNumber) or string.format("INM-%05d", math.random(10000, 99999))
            meta.facility = "bolingbroke_penitentiary"
        elseif item.name == 'food_bread' or item.name == 'crop_produce' then
            meta.isSpoiled = false
            meta.farmOrigin = (type(extra) == "table" and extra.farmOrigin) or "grapeseed"
            meta.harvestedAt = (type(extra) == "table" and extra.harvestedAt) or os.time()
        elseif item.name == 'bulk_flour' or item.name == 'bulk_cornmeal' then
            meta.milledAt = os.time()
            meta.facility = (type(extra) == "table" and extra.facility) or "fac_grapeseed_mill"
        elseif item.name == 'tool_crowbar' then
            meta.toolSerial = (type(extra) == "table" and extra.toolSerial) or string.format("CRW-%06d", math.random(100000, 999999))
            meta.striations = (type(extra) == "table" and extra.striations) or string.format("STR-%04d", math.random(1000, 9999))
        elseif item.name == 'tool_angle_grinder' then
            meta.toolSerial = (type(extra) == "table" and extra.toolSerial) or string.format("GRD-%06d", math.random(100000, 999999))
            meta.striations = (type(extra) == "table" and extra.striations) or string.format("STR-GRD-%04d", math.random(1000, 9999))
            meta.grinderModel = "DeWalt Industrial 20V Max"
        elseif item.name == 'acid_etch_kit' then
            meta.lotNumber = (type(extra) == "table" and extra.lotNumber) or string.format("ETCH-LOT-%05d", math.random(10000, 99999))
            meta.reagentGrade = "Analytical Reagent (AR) 99.8%"
            meta.usesRemaining = (type(extra) == "table" and extra.usesRemaining) or 5
        elseif item.name == 'tamper_seal' then
            meta.sealSerial = (type(extra) == "table" and extra.sealSerial) or string.format("SEAL-%07d", math.random(1000000, 9999999))
            meta.sealedAt = os.time()
        elseif item.name == 'dirty_money' then
            meta.bundleValue = (type(extra) == "table" and extra.bundleValue) or 1000.00
            meta.taintRatio = (type(extra) == "table" and extra.taintRatio) or 1.00
            meta.origin = (type(extra) == "table" and extra.origin) or "unregistered"
        elseif item.name == 'marked_bills' then
            meta.bundleValue = (type(extra) == "table" and extra.bundleValue) or 5000.00
            meta.dyeColor = (type(extra) == "table" and extra.dyeColor) or "chemical_red"
            meta.forensicRisk = (type(extra) == "table" and extra.forensicRisk) or 0.85
        elseif item.name == 'equity_shares' then
            meta.factionId = (type(extra) == "table" and extra.factionId) or "corp_vanilla_unicorn"
            meta.companyName = (type(extra) == "table" and extra.companyName) or "Vanilla Unicorn Entertainment Corp"
            meta.shares = (type(extra) == "table" and extra.shares) or 1.00
            meta.sharePrice = (type(extra) == "table" and extra.sharePrice) or 2000.00
            meta.offeringId = (type(extra) == "table" and extra.offeringId) or "offering_unicorn_ipo"
            meta.issuedAt = os.time()
            meta.certificateUuid = (type(extra) == "table" and extra.certificateUuid) or string.format("EQ-%s-%06d", string.upper(string.sub(meta.factionId, 1, 4)), math.random(100000, 999999))
        elseif item.name == 'armored_cash_box' then
            meta.boxUuid = (type(extra) == "table" and extra.boxUuid) or string.format("BOX-CIT-%06d", math.random(100000, 999999))
            meta.registerId = (type(extra) == "table" and extra.registerId) or "reg_unicorn_main"
            meta.factionId = (type(extra) == "table" and extra.factionId) or "corp_vanilla_unicorn"
            meta.cashAmount = (type(extra) == "table" and extra.cashAmount) or 10000.00
            meta.amount = meta.cashAmount
            meta.sealSerial = (type(extra) == "table" and extra.sealSerial) or string.format("SEAL-CIT-%07d", math.random(1000000, 9999999))
            meta.destinationVault = (type(extra) == "table" and extra.destinationVault) or "vault:pacific_standard"
            meta.tamperState = (type(extra) == "table" and extra.tamperState) or "sealed"
            meta.dispatchedAt = os.time()
        elseif item.name == 'saline_solution' then
            meta.sterile = true
            meta.osmolarity = 308
            meta.batchNumber = (type(extra) == "table" and extra.batchNumber) or string.format("SAL-%05d", math.random(10000, 99999))
            meta.synthesizedAt = os.time()
        elseif item.name == 'med_plasma' then
            meta.sterile = true
            meta.bloodType = (type(extra) == "table" and extra.bloodType) or "O-Universal"
            meta.batchNumber = (type(extra) == "table" and extra.batchNumber) or string.format("PLZ-%05d", math.random(10000, 99999))
            meta.synthesizedAt = os.time()
        elseif item.name == 'med_surgical_pack' then
            meta.sterile = true
            meta.autoclavedAt = os.time()
            meta.facility = (type(extra) == "table" and extra.facility) or "chemlab_humane_biotech"
        elseif item.name == 'item_disinfectant' then
            meta.sterility = 100.0
            meta.concentration = "0.5% Chlorhexidine"
            meta.batchNumber = (type(extra) == "table" and extra.batchNumber) or string.format("DSF-%05d", math.random(10000, 99999))
        elseif item.name == 'clean_linens' then
            meta.sanitizedAt = os.time()
            meta.threadCount = 300
        elseif item.name == 'cash_transit_manifest' then
            meta.manifestUuid = (type(extra) == "table" and extra.manifestUuid) or string.format("MNF-CIT-%06d", math.random(100000, 999999))
            meta.boxUuid = (type(extra) == "table" and extra.boxUuid) or "BOX-CIT-000000"
            meta.registerId = (type(extra) == "table" and extra.registerId) or "reg_unicorn_main"
            meta.factionId = (type(extra) == "table" and extra.factionId) or "corp_vanilla_unicorn"
            meta.carrierCitizenId = (type(extra) == "table" and extra.carrierCitizenId) or "CIT-AGENT"
            meta.amount = (type(extra) == "table" and extra.amount) or 10000.00
            meta.issuedAt = os.time()
        elseif item.name == 'sheet_metal' then
            meta.alloyGrade = (type(extra) == "table" and extra.alloyGrade) or "A36-Structural-Steel"
            meta.thicknessMm = (type(extra) == "table" and extra.thicknessMm) or 3.2
            meta.rolledAt = os.time()
        elseif item.name == 'copper_wire' then
            meta.gauge = (type(extra) == "table" and extra.gauge) or "12-AWG"
            meta.conductivityRating = 0.99
            meta.drawnAt = os.time()
        elseif item.name == 'circuit_substrate' then
            meta.dielectricStrength = "15kV/mm"
            meta.bondedAt = os.time()
        elseif item.name == 'electronic_circuit' then
            meta.firmwareVersion = "v2.4-Civil"
            meta.assembledAt = os.time()
            meta.circuitUuid = (type(extra) == "table" and extra.circuitUuid) or string.format("PCB-%06d", math.random(100000, 999999))
        elseif item.name == 'item_weapon_parts' then
            meta.tolerance = "0.005mm"
            meta.machinedAt = os.time()
            meta.machinedFacility = (type(extra) == "table" and extra.machinedFacility) or "fac_davis_assembly"
        elseif item.name == 'raw_timber_logs' then
            meta.treeSpecies = (type(extra) == "table" and extra.treeSpecies) or "pacific_redwood"
            meta.felledAt = os.time()
        elseif item.name == 'wood_cellulose' then
            meta.pulpPurity = 0.98
            meta.milledAt = os.time()
        end
    end

    if type(extra) == "table" then
        for k, v in pairs(extra) do
            meta[k] = v
        end
    end

    return meta
end
