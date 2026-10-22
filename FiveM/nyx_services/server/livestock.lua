--[[
    Nyxframework: nyx_services
    File: server/livestock.lua
    Description: Authoritative state management, database queries, slaughterhouse
                 processing, cattle husbandry, and cold-chain telemetry logging.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.Ranches = Nyx.Services.Ranches or {}
Nyx.Services.Slaughterhouses = Nyx.Services.Slaughterhouses or {}

--- Initialize ranches and slaughterhouses from DB
local function loadLivestockFacilities()
    local ranchRows = MySQL.query.await("SELECT * FROM `nyx_livestock_ranches`", {})
    if ranchRows then
        for _, r in ipairs(ranchRows) do
            Nyx.Services.Ranches[r.ranch_id] = {
                ranch_id = r.ranch_id,
                ranch_name = r.ranch_name,
                zone_name = r.zone_name,
                cattle_head = tonumber(r.cattle_head) or 50,
                max_capacity = tonumber(r.max_capacity) or 200,
                feed_level = tonumber(r.feed_level) or 100.0,
                health_index = tonumber(r.health_index) or 100.0,
                last_updated = os.time()
            }
        end
        print(string.format("^2[Nyx:Services] Loaded %d livestock ranches.^7", #ranchRows))
    end

    local slaughterRows = MySQL.query.await("SELECT * FROM `nyx_slaughterhouses`", {})
    if slaughterRows then
        for _, s in ipairs(slaughterRows) do
            Nyx.Services.Slaughterhouses[s.facility_id] = {
                facility_id = s.facility_id,
                facility_name = s.facility_name,
                cold_chain_temp_c = tonumber(s.cold_chain_temp_c) or 2.0,
                cold_storage_capacity = tonumber(s.cold_storage_capacity) or 500,
                cleanliness_index = tonumber(s.cleanliness_index) or 100.0,
                total_carcasses_processed = tonumber(s.total_carcasses_processed) or 0
            }
        end
        print(string.format("^2[Nyx:Services] Loaded %d slaughterhouses.^7", #slaughterRows))
    end
end

MySQL.ready(function()
    loadLivestockFacilities()
end)

--- Query authoritative ranch state
function Nyx.Services.GetRanchState(ranchId)
    local ranch = Nyx.Services.Ranches[ranchId]
    if not ranch then return nil end

    local now = os.time()
    local elapsed = now - (ranch.last_updated or now)
    if elapsed > 60 then
        local newFeed, newHealth, gained = Nyx.Services.Livestock.CalculateCattleGrowth(
            ranch.cattle_head, ranch.max_capacity, ranch.feed_level, ranch.health_index, elapsed
        )
        ranch.feed_level = newFeed
        ranch.health_index = newHealth
        ranch.cattle_head = math.min(ranch.max_capacity, ranch.cattle_head + gained)
        ranch.last_updated = now

        MySQL.update("UPDATE `nyx_livestock_ranches` SET `cattle_head` = ?, `feed_level` = ?, `health_index` = ? WHERE `ranch_id` = ?", {
            ranch.cattle_head, ranch.feed_level, ranch.health_index, ranchId
        })
    end

    return ranch
end

--- Feed a cattle ranch to replenish feed level
function Nyx.Services.FeedRanch(ranchId, amount)
    local ranch = Nyx.Services.Ranches[ranchId]
    if not ranch then return false end

    ranch.feed_level = math.min(100.0, ranch.feed_level + (tonumber(amount) or 25.0))
    ranch.last_updated = os.time()

    MySQL.update("UPDATE `nyx_livestock_ranches` SET `feed_level` = ? WHERE `ranch_id` = ?", {
        ranch.feed_level, ranchId
    })
    return true
end

--- Harvest live cattle head from ranch
function Nyx.Services.HarvestCattle(ranchId, count)
    local ranch = Nyx.Services.GetRanchState(ranchId)
    if not ranch then return false, 0 end

    count = math.max(1, math.floor(tonumber(count) or 1))
    if ranch.cattle_head < count then
        return false, 0
    end

    ranch.cattle_head = ranch.cattle_head - count
    ranch.last_updated = os.time()

    MySQL.update("UPDATE `nyx_livestock_ranches` SET `cattle_head` = ? WHERE `ranch_id` = ?", {
        ranch.cattle_head, ranchId
    })

    return true, count
end

--- Query authoritative slaughterhouse state
function Nyx.Services.GetSlaughterhouseState(facilityId)
    return Nyx.Services.Slaughterhouses[facilityId]
end

--- Authoritatively slaughter cattle into carcasses
function Nyx.Services.SlaughterCattle(facilityId, cattleAmount)
    local facility = Nyx.Services.Slaughterhouses[facilityId]
    if not facility then return false, "FACILITY_NOT_FOUND", 0 end

    cattleAmount = math.max(1, math.floor(tonumber(cattleAmount) or 1))
    facility.total_carcasses_processed = facility.total_carcasses_processed + (cattleAmount * 2)

    MySQL.update("UPDATE `nyx_slaughterhouses` SET `total_carcasses_processed` = ? WHERE `facility_id` = ?", {
        facility.total_carcasses_processed, facilityId
    })

    return true, "SUCCESS", cattleAmount * 2
end

--- Authoritatively butcher raw carcass into packaged meat cuts and cold-chain pallets
function Nyx.Services.ButcherCarcass(facilityId, carcassDurability)
    local facility = Nyx.Services.Slaughterhouses[facilityId]
    if not facility then return false, 0, 0, "SPOILED" end

    local cuts, pallets, grade = Nyx.Services.Livestock.CalculateButcheringYield(carcassDurability, facility.cleanliness_index)
    return true, cuts, pallets, grade
end

--- Log cold-chain telemetry record to database
function Nyx.Services.LogRefrigeratedTelemetry(containerId, itemName, durability, isReeferActive, temperatureC)
    local status, _, _ = Nyx.Services.Livestock.EvaluateColdChainStatus(temperatureC, isReeferActive)

    MySQL.insert("INSERT INTO `nyx_refrigerated_logs` (`container_id`, `item_name`, `durability`, `is_reefer_active`, `temperature_c`, `inspection_status`) VALUES (?, ?, ?, ?, ?, ?)", {
        containerId, itemName, durability, isReeferActive and 1 or 0, temperatureC, status
    })

    return status
end

-- Server Event Registrations
RegisterNetEvent("nyx_services:server:feedRanch", function(ranchId)
    local src = source
    if not ranchId then return end
    local success = Nyx.Services.FeedRanch(ranchId, 25.0)
    if success then
        TriggerClientEvent("nyx_ui:showNotification", src, "Feed delivered to ranch successfully.", "success")
    end
end)

RegisterNetEvent("nyx_services:server:slaughterCattle", function(facilityId)
    local src = source
    if not facilityId then return end
    local success, msg, carcassCount = Nyx.Services.SlaughterCattle(facilityId, 1)
    if success then
        TriggerClientEvent("nyx_ui:showNotification", src, string.format("Slaughtered 1 cattle head into %d raw carcasses.", carcassCount), "success")
    end
end)
