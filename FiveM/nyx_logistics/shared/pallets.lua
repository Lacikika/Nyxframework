--[[
    Nyxframework: nyx_logistics
    File: shared/pallets.lua
    Description: Pure Lua 5.4 physical heavy freight pallet formulas, vehicle slot matrices,
                 dynamic prop resolution, and capacity invariants.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Pallets = {}

-- Constant Constraints
Nyx.Pallets.MaxWeight = (Config and Config.PalletMaxWeight) or 1000000 -- 1,000,000 grams = 1,000 kg
Nyx.Pallets.MaxSlots = (Config and Config.PalletMaxSlots) or 20         -- 20 heavy cargo slots

-- Prop Models by Load Bracket
Nyx.Pallets.Models = {
    Empty = "prop_pallet_01a",
    Light = "prop_boxpile_02b",
    Medium = "prop_boxpile_05a",
    Heavy = "prop_boxpile_06a"
}

-- Commercial Vehicle Slot Matrices
local function joaatSafe(key)
    if type(key) == "number" then return key end
    if type(joaat) == "function" then return joaat(key) end
    if type(GetHashKey) == "function" then return GetHashKey(key) end
    -- Fallback simple string hash for pure Lua test runner environments
    local hash = 0
    for i = 1, #key do
        hash = (hash + string.byte(key, i)) % 2147483647
    end
    return hash
end

Nyx.Pallets.VehicleProfiles = {
    ['flatbed'] = {
        name = "flatbed",
        maxSlots = 3,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.20, z = 0.45 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -2.80, z = 0.45 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = 0.0, y = -4.40, z = 0.45 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule'] = {
        name = "mule",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule2'] = {
        name = "mule2",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule3'] = {
        name = "mule3",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule4'] = {
        name = "mule4",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['benson'] = {
        name = "benson",
        maxSlots = 4,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.00, z = 0.30 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -2.40, z = 0.30 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = 0.0, y = -3.80, z = 0.30 }, heading = 0.0, bone = 0 },
            [4] = { offset = { x = 0.0, y = -5.20, z = 0.30 }, heading = 0.0, bone = 0 }
        }
    },
    ['pounder'] = {
        name = "pounder",
        maxSlots = 6,
        slots = {
            [1] = { offset = { x = -0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = -0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [4] = { offset = { x = 0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [5] = { offset = { x = -0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 },
            [6] = { offset = { x = 0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 }
        }
    },
    ['pounder2'] = {
        name = "pounder2",
        maxSlots = 6,
        slots = {
            [1] = { offset = { x = -0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = -0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [4] = { offset = { x = 0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [5] = { offset = { x = -0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 },
            [6] = { offset = { x = 0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 }
        }
    },
    ['forklift'] = {
        name = "forklift",
        maxSlots = 1,
        slots = {
            [1] = { offset = { x = 0.0, y = 1.40, z = -0.20 }, heading = 0.0, bone = 0 }
        }
    }
}

--- Resolves the vehicle pallet carrier profile by model name or hash
--- @param model string|number
--- @return table|nil
function Nyx.Pallets.GetVehicleProfile(model)
    if not model then return nil end
    if type(model) == "string" then
        local lower = string.lower(model)
        if Nyx.Pallets.VehicleProfiles[lower] then
            return Nyx.Pallets.VehicleProfiles[lower]
        end
        local h = joaatSafe(lower)
        for _, prof in pairs(Nyx.Pallets.VehicleProfiles) do
            if joaatSafe(prof.name) == h then
                return prof
            end
        end
    elseif type(model) == "number" then
        for _, prof in pairs(Nyx.Pallets.VehicleProfiles) do
            if joaatSafe(prof.name) == model then
                return prof
            end
        end
    end
    return nil
end

--- Resolves the 3D attachment offset for a given vehicle model and slot index
--- @param model string|number
--- @param slotIndex number
--- @return table|nil
function Nyx.Pallets.GetVehicleSlotOffset(model, slotIndex)
    local prof = Nyx.Pallets.GetVehicleProfile(model)
    if not prof or not prof.slots then return nil end
    slotIndex = tonumber(slotIndex) or 1
    return prof.slots[slotIndex]
end

--- Finds the lowest unoccupied pallet slot for a vehicle
--- @param model string|number
--- @param occupiedSlots table<number, boolean>
--- @return number|nil slotIndex, string|nil error
function Nyx.Pallets.FindAvailableSlot(model, occupiedSlots)
    local prof = Nyx.Pallets.GetVehicleProfile(model)
    if not prof then
        return nil, "VEHICLE_NOT_PALLET_CARRIER"
    end

    occupiedSlots = occupiedSlots or {}
    for i = 1, prof.maxSlots do
        if not occupiedSlots[i] then
            return i, nil
        end
    end

    return nil, "VEHICLE_PALLET_SLOTS_FULL"
end

--- Determines the appropriate visual 3D prop model based on cumulative weight and item count
--- @param totalWeight number
--- @param itemCount number
--- @return string
function Nyx.Pallets.ResolvePalletModel(totalWeight, itemCount)
    local count = tonumber(itemCount) or 0
    local weight = math.max(0, tonumber(totalWeight) or 0)

    if count <= 0 or weight <= 0 then
        return Nyx.Pallets.Models.Empty
    elseif weight <= 300000 then -- <= 300 kg
        return Nyx.Pallets.Models.Light
    elseif weight <= 700000 then -- <= 700 kg
        return Nyx.Pallets.Models.Medium
    else
        return Nyx.Pallets.Models.Heavy
    end
end

--- Checks if a pallet can hold additional weight without exceeding the 1,000 kg cap
--- @param currentWeight number
--- @param addedWeight number
--- @return boolean
function Nyx.Pallets.CanHoldWeight(currentWeight, addedWeight)
    local cur = math.max(0, tonumber(currentWeight) or 0)
    local add = math.max(0, tonumber(addedWeight) or 0)
    return (cur + add) <= Nyx.Pallets.MaxWeight
end

--- Checks if a pallet can accept another slot item
--- @param currentSlotCount number
--- @return boolean
function Nyx.Pallets.CanHoldSlot(currentSlotCount)
    local cur = math.max(0, tonumber(currentSlotCount) or 0)
    return cur < Nyx.Pallets.MaxSlots
end

--- Validates if a pallet is eligible to be sealed for secure transit
--- @param itemCount number
--- @param totalWeight number
--- @return boolean, string|nil
function Nyx.Pallets.CanSealPallet(itemCount, totalWeight)
    local count = tonumber(itemCount) or 0
    local weight = tonumber(totalWeight) or 0

    if count <= 0 then
        return false, "CANNOT_SEAL_EMPTY_PALLET"
    end
    if weight <= 0 then
        return false, "INVALID_WEIGHT"
    end
    return true, nil
end
