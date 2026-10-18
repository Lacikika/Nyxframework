--[[
    Nyxframework: nyx_properties
    File: client/taxation.lua
    Description: Client-side taxation and auction interface, assessment displays,
                 structural repair requests, and delinquency resolution.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- 1. View Detailed Property Tax & Maintenance Telemetry
function Nyx.Properties.ViewTaxAssessment(propertyId)
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then
        return
    end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:getTaxAssessment", propertyId)
    if not res or not res.success then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "ADÓADATOK LEKÉRÉSE SIKERTELEN",
            message = res and res.error or "Hálózati vagy jogosultsági hiba."
        })
        return
    end

    local a = res.assessment
    local repairText = (res.pointsNeeded > 0)
        and string.format("Felújítási költség: $%.2f (+%.1f%%)", res.repairCost, res.pointsNeeded)
        or "Szerkezet: 100% Kiváló"

    local holdingText = (a.holdingMultiplier > 1.0)
        and string.format(" (Halmozási szorzó: %.2fx, %d ingatlan)", a.holdingMultiplier, a.propertiesOwned)
        or " (Egyetlen ingatlan)"

    local penaltyText = (a.penalty > 0)
        and string.format(" | Hátralék pótdíj: $%.2f (Fokozat %d)", a.penalty, a.delinquencyTier)
        or ""

    TriggerEvent("nyx:ui:notify", {
        type = (a.delinquencyTier >= 2) and "warning" or "info",
        title = string.format("ADÓKIMUTATÁS: %s", res.label),
        message = string.format(
            "Telek: %dm² | Állapot: %.1f%%\nÉpítményadó: $%.2f%s\nTelekfenntartás: $%.2f (%s)\nÖsszesen esedékes: $%.2f%s\n%s",
            math.floor(a.landAreaSqm),
            a.condition,
            a.millageTax,
            holdingText,
            a.maintenanceTax,
            a.zoneId,
            a.totalTaxDue,
            penaltyText,
            repairText
        )
    })
end

-- 2. Request Structural Repair of Property Condition
function Nyx.Properties.RepairCondition(propertyId)
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then
        return
    end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:repairCondition", propertyId)
    if res and res.success then
        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "FELÚJÍTÁS BEFEJEZVE",
            message = string.format("Az ingatlan szerkezeti állapota 100%%-ra visszaállítva. Levonva: $%.2f.", res.costPaid)
        })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "FELÚJÍTÁS SIKERTELEN",
            message = res and res.error or "Nincs fedezet vagy nem vagy tulajdonos."
        })
    end
end

-- 3. Pay Delinquent Tax Arrears
function Nyx.Properties.PayArrears(propertyId)
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then
        return
    end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:payDelinquentTaxes", propertyId)
    if res and res.success then
        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "HÁTRALÉK RENDEZVE",
            message = string.format("Sikeresen befizettél $%.2f adóhátralékot! Zárlat feloldva.", res.amountPaid)
        })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "BEFIZETÉS SIKERTELEN",
            message = res and res.error or "Nincs fedezet vagy nincs aktív hátralék."
        })
    end
end

-- 4. Client Exports
exports('ViewTaxAssessment', Nyx.Properties.ViewTaxAssessment)
exports('RepairCondition', Nyx.Properties.RepairCondition)
exports('PayArrears', Nyx.Properties.PayArrears)
