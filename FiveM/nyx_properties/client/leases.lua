--[[
    Nyxframework: nyx_properties
    File: client/leases.lua
    Description: Client-side commercial real estate leasing interface,
                 storefront status inspection, arrears payment triggers,
                 and Third-Eye spatial interaction targets.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- ----------------------------------------------------------------------------
-- 1. View Detailed Commercial Lease Information
-- ----------------------------------------------------------------------------
function Nyx.Properties.ViewLeaseInfo(propertyId)
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then
        return
    end

    propertyId = tonumber(propertyId)
    if not propertyId then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HIÁNYZÓ INGATLAN AZONOSÍTÓ",
            message = "Használat: /leaseinfo [propertyId]"
        })
        return
    end

    local prop = exports['nyx_properties'] and exports['nyx_properties']:GetProperty(propertyId)
    local leaseId = prop and prop.activeLeaseId

    if not leaseId then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "NINCS AKTÍV BÉRLETI SZERZŐDÉS",
            message = "Ez az ingatlan jelenleg nincs bérbe adva vagy bérelhető állapotban van."
        })
        return
    end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:getLeaseDetails", leaseId)
    if not res or not res.success then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "BÉRLETI ADATOK LEKÉRÉSE SIKERTELEN",
            message = res and res.error or "Hálózati vagy jogosultsági hiba."
        })
        return
    end

    local l = res.lease
    local badge = Nyx.CommercialLeases.FormatStatusBadge(l.leaseStatus)

    TriggerEvent("nyx:ui:notify", {
        type = (l.leaseStatus == "active") and "info" or ((l.leaseStatus == "grace_period") and "warning" or "error"),
        title = string.format("KERESKEDELMI BÉRLET: %s", l.propertyLabel or string.format("#%d", propertyId)),
        message = string.format(
            "Státusz: %s\nBérlő: %s (%s)\nCiklusdíj: $%.2f | Kaució: $%.2f\nHátralék: $%.2f\nÖsszesen teljesítve: %d/%d ciklus",
            badge.label,
            l.lesseeId,
            l.lesseeType,
            l.cycleRent,
            l.securityDepositHeld,
            l.arrearsBalance,
            l.cyclesCompleted or 0,
            l.leaseTermCycles or 4
        )
    })
end

-- ----------------------------------------------------------------------------
-- 2. Pay Commercial Lease Rent / Settle Arrears
-- ----------------------------------------------------------------------------
function Nyx.Properties.PayLeaseRent(leaseId)
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then
        return
    end

    if not leaseId or leaseId == "" then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HIÁNYZÓ BÉRLETI AZONOSÍTÓ",
            message = "Használat: /paylease [leaseId]"
        })
        return
    end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:payLeaseRent", leaseId)
    if not res or not res.success then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "BÉRLETI DÍJ RENDEZÉSE SIKERTELEN",
            message = res and res.error or "Hálózati hiba vagy elégtelen fedezet."
        })
        return
    end

    local r = res.result
    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "BÉRLETI DÍJ RENDEZVE",
        message = string.format("Sikeresen befizetve: $%.2f (Hátralék: $%.2f, Pótdíj: $%.2f). A zárszerkezet újra működőképes!",
            r.amountPaid, r.arrearsSettled, r.penaltyPaid)
    })
end

-- ----------------------------------------------------------------------------
-- 3. Player Chat Commands
-- ----------------------------------------------------------------------------
RegisterCommand("leaseinfo", function(_, args)
    local propId = tonumber(args[1])
    if not propId then
        -- Attempt to find nearest property entrance
        local pPed = PlayerPedId()
        local pCoords = GetEntityCoords(pPed)
        local props = exports['nyx_properties'] and exports['nyx_properties']:GetProperties and exports['nyx_properties']:GetProperties()

        if props then
            for _, p in pairs(props) do
                if p.entrance then
                    local eVec = vector3(p.entrance.x, p.entrance.y, p.entrance.z)
                    if #(pCoords - eVec) <= 4.0 then
                        propId = p.id
                        break
                    end
                end
            end
        end
    end

    if propId then
        Nyx.Properties.ViewLeaseInfo(propId)
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "KERESKEDELMI BÉRLET",
            message = "Nem állsz üzlethelyiség bejáratánál. Használat: /leaseinfo [propertyId]"
        })
    end
end, false)

RegisterCommand("paylease", function(_, args)
    local leaseId = args[1]
    if leaseId then
        Nyx.Properties.PayLeaseRent(leaseId)
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "BÉRLETI DÍJ BEFIZETÉS",
            message = "Használat: /paylease [leaseId]"
        })
    end
end, false)

RegisterCommand("availableleases", function()
    local res = exports['nyx_core']:TriggerRPCAwait("properties:getAvailableStorefronts")
    if not res or not res.success or not res.properties then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "BÉRELHETŐ INGATLANOK",
            message = "Nem sikerült lekérni a szabad üzlethelyiségek listáját."
        })
        return
    end

    local count = #res.properties
    print(string.format("^2--- Szabad Kereskedelmi Üzlethelyiségek és Raktárak (%d db) ---^7", count))
    for _, p in ipairs(res.properties) do
        print(string.format("  [ID: %d] %s (%s) - Bérleti díj: $%.2f/ciklus - Zóna: %s",
            p.propertyId, p.label, p.commercialZoning, p.baseRentalRate, p.zoneId))
    end

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "SZABAD ÜZLETHELYISÉGEK",
        message = string.format("%d szabad kereskedelmi ingatlan elérhető. Részletek megtekintéséhez nézd meg az F8 konzolt!", count)
    })
end, false)

-- ----------------------------------------------------------------------------
-- 4. Network Event Listeners
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:properties:client:leaseUpdated", function(payload)
    if not payload then return end
    if payload.leaseStatus == "lease_lapsed" then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "BÉRLETI JOG ZÁROLVA",
            message = "A kereskedelmi ingatlan zárszerkezete és kasszája díjhátralék miatt le lett zárva!"
        })
    elseif payload.leaseStatus == "leased_active" then
        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "BÉRLET AKTÍV",
            message = "A kereskedelmi bérleti jogviszony aktív és érvényes."
        })
    elseif payload.leaseStatus == "available_for_lease" then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "ÜZLETHELYISÉG FELSZABADULT",
            message = "Egy kereskedelmi ingatlan újra szabadon bérelhetővé vált a városban."
        })
    end
end)

-- ----------------------------------------------------------------------------
-- 5. Public Client Exports
-- ----------------------------------------------------------------------------
exports('ViewCommercialLeaseInfo', function(propertyId)
    Nyx.Properties.ViewLeaseInfo(propertyId)
end)

exports('PayCommercialLeaseRent', function(leaseId)
    Nyx.Properties.PayLeaseRent(leaseId)
end)

exports('GetAvailableStorefronts', function()
    return exports['nyx_core']:TriggerRPCAwait("properties:getAvailableStorefronts")
end)
