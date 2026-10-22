import pytest
import os
import json
import hashlib

def sha256(text: str) -> str:
    return hashlib.sha256(text.encode('utf-8')).hexdigest()

def get_caliber(weapon_model_or_hash: str) -> str:
    if not weapon_model_or_hash:
        return "9mm"
    s = str(weapon_model_or_hash).lower()
    if "pistol" in s or "smg" in s or "combatpistol" in s or s == "weapon_pistol" or s == "weapon_combatpistol":
        return "9mm"
    elif "appistol" in s or "vintagepistol" in s or "snspistol" in s:
        return ".45_ACP"
    elif "carbine" in s or "rifle" in s or "specialcarbine" in s or s == "weapon_carbinerifle":
        return "5.56x45mm"
    elif "mg" in s or "sniper" in s or "heavy" in s:
        return "7.62x51mm"
    elif "shotgun" in s or "pumpshotgun" in s:
        return "12-gauge"
    return "9mm"

def compute_rifling_hash(weapon_serial: str, weapon_model: str, caliber: str, salt: str) -> str:
    raw = f"RIFLING:{weapon_serial}:{weapon_model}:{caliber}:{salt}"
    return sha256(raw)

def compute_breech_pin_hash(weapon_serial: str, breech_face_type: str, firing_pin_type: str, salt: str) -> str:
    raw = f"MECHANICAL:{weapon_serial}:{breech_face_type}:{firing_pin_type}:{salt}"
    return sha256(raw)

def compute_casing_ejection_hash(weapon_serial: str, breech_pin_hash: str, ejection_angle: float, salt: str) -> str:
    raw = f"CASING_EJECT:{weapon_serial}:{breech_pin_hash}:{ejection_angle:.2f}:{salt}"
    return sha256(raw)

def evaluate_nibin_match(entry_a: dict, entry_b: dict):
    if not entry_a or not entry_b:
        return "UNMATCHED", 0.0

    if entry_a.get("weaponSerial") and entry_b.get("weaponSerial") and entry_a["weaponSerial"] == entry_b["weaponSerial"] and entry_a["weaponSerial"] != "NYX-UNKNOWN":
        return "CONFIRMED_MATCH", 1.0

    if entry_a.get("riflingHash") and entry_b.get("riflingHash") and entry_a["riflingHash"] == entry_b["riflingHash"]:
        return "CONFIRMED_MATCH", 0.98

    if entry_a.get("casingEjectionHash") and entry_b.get("casingEjectionHash") and entry_a["casingEjectionHash"] == entry_b["casingEjectionHash"]:
        return "CONFIRMED_MATCH", 0.95

    if entry_a.get("caliber") and entry_b.get("caliber") and entry_a["caliber"] == entry_b["caliber"]:
        if entry_a.get("casingEjectionHash") and entry_b.get("casingEjectionHash"):
            if entry_a["casingEjectionHash"][:16] == entry_b["casingEjectionHash"][:16]:
                return "CANDIDATE_MATCH", 0.75
        if entry_a.get("riflingHash") and entry_b.get("riflingHash"):
            if entry_a["riflingHash"][:16] == entry_b["riflingHash"][:16]:
                return "CANDIDATE_MATCH", 0.70

    return "UNMATCHED", 0.0


def test_migration_067_file_and_index():
    core_mig_path = "FiveM/nyx_core/sql/migrations/067_forensic_ballistics_rifling_and_nibin_integration.sql"
    judiciary_mig_path = "FiveM/nyx_judiciary/sql/migrations/067_forensic_ballistics_rifling_and_nibin_integration.sql"
    index_path = "FiveM/nyx_core/sql/migrations/index.json"

    assert os.path.isfile(core_mig_path)
    assert os.path.isfile(judiciary_mig_path)

    with open(core_mig_path, "r", encoding="utf-8") as f:
        content = f.read()
        assert "nyx_ballistics_rifling_profiles" in content
        assert "nyx_nibin_database" in content
        assert "breech_face_hash" in content
        assert "rifling_microstriation_hash" in content
        assert "casing_ejection_hash" in content

    with open(index_path, "r", encoding="utf-8") as f:
        index_data = json.load(f)
        assert "067_forensic_ballistics_rifling_and_nibin_integration.sql" in index_data


def test_deterministic_ballistics_formulas():
    serial = "NYX-W99001"
    model = "weapon_combatpistol"
    cal = get_caliber(model)
    assert cal == "9mm"

    salt_r = "SALT_RIFLE_1"
    rifling_hash1 = compute_rifling_hash(serial, model, cal, salt_r)
    rifling_hash2 = compute_rifling_hash(serial, model, cal, salt_r)
    assert rifling_hash1 == rifling_hash2
    assert len(rifling_hash1) == 64

    breech_pin_hash = compute_breech_pin_hash(serial, "STANDARD_RECTANGULAR", "HEMISPHERICAL_PIN", "SALT_BREECH_1")
    assert len(breech_pin_hash) == 64

    casing_hash1 = compute_casing_ejection_hash(serial, breech_pin_hash, 45.0, "SALT_EJECT_1")
    casing_hash2 = compute_casing_ejection_hash(serial, breech_pin_hash, 45.0, "SALT_EJECT_1")
    assert casing_hash1 == casing_hash2
    assert len(casing_hash1) == 64


def test_nibin_correlation_logic():
    entry_a = {
        "weaponSerial": "NYX-SERIAL-A",
        "riflingHash": "a1b2c3d4e5f67890123456789012345678901234567890123456789012345678",
        "casingEjectionHash": "1111222233334444555566667777888899990000aaaabbbbccccddddeeeeffff",
        "caliber": "9mm"
    }

    entry_b = {
        "weaponSerial": "NYX-SERIAL-A",
        "riflingHash": "different_rifling_hash",
        "casingEjectionHash": "different_casing_hash",
        "caliber": "9mm"
    }

    status, score = evaluate_nibin_match(entry_a, entry_b)
    assert status == "CONFIRMED_MATCH"
    assert score == 1.0

    entry_c = {
        "weaponSerial": "NYX-SERIAL-C",
        "riflingHash": "a1b2c3d4e5f67890123456789012345678901234567890123456789012345678",
        "casingEjectionHash": "9999888877776666555544443333222211110000ffffeeeeddccbbaa99887766",
        "caliber": "9mm"
    }

    status, score = evaluate_nibin_match(entry_a, entry_c)
    assert status == "CONFIRMED_MATCH"
    assert score == 0.98

    entry_d = {
        "weaponSerial": "NYX-SERIAL-D",
        "riflingHash": "a1b2c3d4e5f67890_different_tail_hash",
        "casingEjectionHash": "1111222233334444_different_tail_casing",
        "caliber": "9mm"
    }

    status, score = evaluate_nibin_match(entry_a, entry_d)
    assert status == "CANDIDATE_MATCH"
    assert score == 0.75

    entry_unmatched = {
        "weaponSerial": "NYX-SERIAL-E",
        "riflingHash": "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
        "casingEjectionHash": "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
        "caliber": ".45_ACP"
    }

    status, score = evaluate_nibin_match(entry_a, entry_unmatched)
    assert status == "UNMATCHED"
    assert score == 0.0
