--[[
    Nyxframework: nyx_press
    File: server/main.lua
    Description: Resource lifecycle, database synchronization, in-memory caches,
                 and RPC registration bridge.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

Nyx.Press.OutletsCache = {}
Nyx.Press.DropboxesCache = {}
Nyx.Press.NewsstandsCache = {}

-- Standardized RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
            exports['nyx_core']:RegisterRPC(route, handler)
        end
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- Hydrate Media Outlets, Dropboxes, and Newsstands from Database
function Nyx.Press.HydrateWorldData()
    -- 1. Media Outlets
    local outlets = MySQL.query.await("SELECT * FROM `nyx_press_outlets`")
    if outlets then
        for _, o in ipairs(outlets) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(o.press_coords) == "string" then
                local ok, parsed = pcall(json.decode, o.press_coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(o.press_coords) == "table" then
                coords = o.press_coords
            end

            Nyx.Press.OutletsCache[o.outlet_id] = {
                id = o.outlet_id,
                factionId = o.faction_id,
                name = o.name,
                licenseStatus = o.license_status,
                accreditedUnionId = o.accredited_union_id,
                coords = vector3(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0),
                printCostPerCopy = tonumber(o.print_cost_per_copy) or 2.50,
                coverPriceDefault = tonumber(o.cover_price_default) or 10.00,
                revenueBalance = tonumber(o.revenue_balance) or 0.00
            }
        end
    end

    -- 2. Whistleblower Dropboxes
    local dropboxes = MySQL.query.await("SELECT * FROM `nyx_press_whistleblower_dropboxes` WHERE `is_active` = 1")
    if dropboxes then
        for _, d in ipairs(dropboxes) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(d.coords) == "string" then
                local ok, parsed = pcall(json.decode, d.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(d.coords) == "table" then
                coords = d.coords
            end

            Nyx.Press.DropboxesCache[d.dropbox_id] = {
                id = d.dropbox_id,
                label = d.label,
                coords = vector3(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0),
                pgpFingerprint = d.public_pgp_fingerprint,
                isActive = (tonumber(d.is_active) == 1)
            }
        end
    end

    -- 3. Public Newsstands
    local stands = MySQL.query.await("SELECT * FROM `nyx_press_newsstands`")
    if stands then
        for _, s in ipairs(stands) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(s.coords) == "string" then
                local ok, parsed = pcall(json.decode, s.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(s.coords) == "table" then
                coords = s.coords
            end

            Nyx.Press.NewsstandsCache[s.stand_id] = {
                id = s.stand_id,
                label = s.label,
                coords = vector3(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0),
                heading = tonumber(s.heading) or 0.0,
                currentPublicationId = s.current_publication_id,
                copiesInventory = tonumber(s.copies_inventory) or 0,
                totalSold = tonumber(s.total_sold) or 0
            }
        end
    end

    print(string.format("^2[Nyx:Press] Hydrated %d media outlets, %d dropboxes, and %d newsstands.^7",
        outlets and #outlets or 0, dropboxes and #dropboxes or 0, stands and #stands or 0))
end

MySQL.ready(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    Nyx.Press.HydrateWorldData()
end)
