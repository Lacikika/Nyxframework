Config = {}

-- Diagnostics & Debugging
Config.Debug = false

-- Dynamic Price Elasticity Parameters (Formula: P = Pbase * (1 + alpha * (Ctarget - Scurrent) / Ctarget))
Config.ElasticityCoefficient = 1.25  -- Shortage sensitivity coefficient (alpha)
Config.SurplusFloor = 0.50           -- Minimum price floor multiplier (0.50 * Pbase)
Config.ShortageCeiling = 2.25        -- Maximum shortage price ceiling multiplier (2.25 * Pbase)

-- Finite Extraction & Node Regeneration
Config.HarvestInteractDistance = 3.0 -- Maximum distance in meters to interact with harvest nodes
Config.HarvestRegenInterval = 900    -- 15 minutes between node reserve regeneration passes
Config.HarvestAmountPerAction = 3    -- Yield per extraction action
Config.ToolDurabilityLoss = 2.5      -- Durability percentage consumed per harvesting cycle

-- Industrial Facilities & Refining
Config.FacilityTickInterval = 5      -- Queue progress tick interval in seconds

-- Industrial Freight Pallets
Config.PalletModel = "prop_boxpile_06a"
Config.PalletMaxWeight = 1000000     -- 1,000 kg (1 metric ton) per freight pallet
Config.PalletMaxSlots = 20           -- Heavy slot capacity

-- Automated Shortage Contracts
Config.ShortageContractThreshold = 0.10  -- Generate freight contract when stock <= 10% of target capacity
Config.DefaultFreightPayoutMultiplier = 0.35 -- Payout per delivered unit = 35% of item base price
