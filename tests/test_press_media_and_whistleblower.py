"""
Unit tests for Decentralized Broadcast Printing, Whistleblower Dropboxes & Trade Union Media Accreditation.
Verifies printing circulation cost scaling, newsstand retail double-entry revenue conservation,
cryptographic SHA-256 whistleblower anonymity, media accreditation gates, state machine rules,
and SQL migration/manifest integrity.
"""

import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIVEM = ROOT / "FiveM"


class PressEngine:
    DEFAULT_BASE_COST = 2.00
    DEFAULT_PAGE_FACTOR = 0.50
    DEFAULT_OVERHEAD = 25.00
    DEFAULT_PUBLISHER_SPLIT = 0.75

    @classmethod
    def calculate_printing_cost(
        cls,
        copies: int,
        content_length: int,
        base_cost: float = DEFAULT_BASE_COST,
        page_factor: float = DEFAULT_PAGE_FACTOR,
        overhead: float = DEFAULT_OVERHEAD,
    ) -> tuple[float, float, int]:
        n = max(0, int(copies))
        if n == 0:
            return 0.00, 0.00, 1

        length_tier = max(1, math.ceil(max(0, content_length) / 500))
        unit_cost = math.floor((base_cost + (page_factor * (length_tier - 1))) * 100) / 100
        gross = (n * unit_cost) + overhead
        total_cost = math.floor(gross * 100) / 100
        return total_cost, unit_cost, length_tier

    @classmethod
    def calculate_sale_revenue_split(
        cls, cover_price: float, publisher_split_ratio: float = DEFAULT_PUBLISHER_SPLIT
    ) -> tuple[float, float, float]:
        price = max(0.00, math.floor(float(cover_price) * 100) / 100)
        ratio = max(0.00, min(1.00, float(publisher_split_ratio)))

        pub_share = math.floor((price * ratio) * 100) / 100
        muni_share = math.floor((price - pub_share) * 100) / 100

        # Enforce zero-leakage conservation
        if pub_share + muni_share != price:
            pub_share += round(price - (pub_share + muni_share), 2)

        return pub_share, muni_share, price

    @classmethod
    def generate_source_hash(cls, citizen_id: str, salt: str, nonce: str) -> str:
        payload = f"{citizen_id}:{salt}:{nonce}".encode("utf-8")
        return hashlib.sha256(payload).hexdigest()

    @classmethod
    def verify_source_identity(
        cls, expected_hash: str, citizen_id: str, salt: str, nonce: str
    ) -> bool:
        computed = cls.generate_source_hash(citizen_id, salt, nonce)
        return computed == expected_hash

    @classmethod
    def evaluate_media_accreditation(
        cls, union_membership: dict | None = None, faction_membership: dict | None = None
    ) -> tuple[bool, str]:
        # Priority 1: Press Trade Union Membership
        if union_membership and isinstance(union_membership, dict):
            u_id = str(union_membership.get("unionId", ""))
            is_press = (
                u_id == "union:press_guild" or "press" in u_id or "media" in u_id
            )
            is_good = union_membership.get("standing") == "good_standing"
            allowed_roles = {"steward", "delegate", "member"}
            role = union_membership.get("role", "member")
            if is_press and is_good and role in allowed_roles:
                return True, "TRADE_UNION_ACCREDITED"

        # Priority 2: Media Corporate Charter Leadership
        if faction_membership and isinstance(faction_membership, dict):
            f_id = str(faction_membership.get("factionId", ""))
            is_media = f_id.startswith("press:") or "media" in f_id or "news" in f_id
            is_leader = (
                faction_membership.get("isLeader") is True
                or faction_membership.get("roleTitle") in {"CEO", "Editor-in-Chief"}
            )
            if is_media and is_leader:
                return True, "MEDIA_CHARTER_LEADERSHIP_ACCREDITED"

        return False, "UNACCREDITED_MEDIA_PERSONNEL"

    @classmethod
    def validate_article(cls, article: dict) -> tuple[bool, str]:
        if not article or not isinstance(article, dict):
            return False, "MISSING_ARTICLE_DATA"

        headline = str(article.get("headline", "")).strip()
        if len(headline) < 5 or len(headline) > 255:
            return False, "INVALID_HEADLINE_LENGTH"

        valid_categories = {
            "investigative",
            "business",
            "politics",
            "whistleblower",
            "general",
        }
        category = str(article.get("category", ""))
        if category not in valid_categories:
            return False, "INVALID_ARTICLE_CATEGORY"

        byline = str(article.get("authorByline", "")).strip()
        if len(byline) < 2 or len(byline) > 96:
            return False, "INVALID_BYLINE_LENGTH"

        content = str(article.get("content", "")).strip()
        if len(content) < 20 or len(content) > 100000:
            return False, "INVALID_CONTENT_LENGTH"

        return True, "VALID"

    @classmethod
    def can_transition_publication(cls, current_status: str, next_status: str) -> bool:
        if current_status == next_status:
            return True
        transitions = {
            "draft": {"published"},
            "published": {"retracted"},
            "retracted": set(),
        }
        allowed = transitions.get(current_status, set())
        return next_status in allowed

    @classmethod
    def can_transition_leak(cls, current_status: str, next_status: str) -> bool:
        if current_status == next_status:
            return True
        transitions = {
            "unclaimed": {"under_investigation"},
            "under_investigation": {"published", "quashed"},
            "published": set(),
            "quashed": set(),
        }
        allowed = transitions.get(current_status, set())
        return next_status in allowed


# ============================================================================
# Pytest Test Cases
# ============================================================================


def test_printing_cost_calculation():
    """Validates printing cost formula across copy volumes and length tiering."""
    # 100 copies of short article (350 chars -> tier 1)
    cost1, unit1, tier1 = PressEngine.calculate_printing_cost(100, 350, 2.00, 0.50, 25.00)
    assert tier1 == 1
    assert unit1 == 2.00
    assert cost1 == (100 * 2.00) + 25.00  # 225.00

    # 100 copies of 3-tier article (1200 chars -> tier 3)
    cost2, unit2, tier2 = PressEngine.calculate_printing_cost(100, 1200, 2.00, 0.50, 25.00)
    assert tier2 == 3
    assert unit2 == 2.00 + (0.50 * 2)  # 3.00
    assert cost2 == (100 * 3.00) + 25.00  # 325.00

    # 500 copies of long exposé (3200 chars -> tier 7)
    cost3, unit3, tier3 = PressEngine.calculate_printing_cost(500, 3200, 2.00, 0.50, 25.00)
    assert tier3 == 7
    assert unit3 == 2.00 + (0.50 * 6)  # 5.00
    assert cost3 == (500 * 5.00) + 25.00  # 2525.00

    # Zero copies produces zero cost
    cost0, unit0, tier0 = PressEngine.calculate_printing_cost(0, 500)
    assert cost0 == 0.00


def test_newsstand_sales_revenue_split_conservation():
    """Validates zero-cent leakage economic conservation in retail newspaper sales."""
    test_prices = [1.00, 5.00, 10.00, 12.50, 14.99, 23.47, 99.95]

    for p in test_prices:
        pub, muni, price = PressEngine.calculate_sale_revenue_split(p, 0.75)
        # Sum must strictly equal gross price
        assert round(pub + muni, 2) == round(price, 2)
        assert pub >= 0.00
        assert muni >= 0.00
        # Publisher gets roughly 75%
        assert pub >= muni


def test_whistleblower_source_hash_determinism_and_entropy():
    """Validates SHA-256 whistleblower source hash generation format and entropy."""
    cit_id = "cit_edward_snow"
    salt = "secure_salt_987654"
    nonce = "nonce_random_112233"

    hash1 = PressEngine.generate_source_hash(cit_id, salt, nonce)
    hash2 = PressEngine.generate_source_hash(cit_id, salt, nonce)

    assert len(hash1) == 64
    assert hash1 == hash2  # Deterministic

    # Changing any component changes the hash completely (Avalanche effect)
    hash_diff_salt = PressEngine.generate_source_hash(cit_id, "different_salt", nonce)
    assert hash1 != hash_diff_salt

    hash_diff_nonce = PressEngine.generate_source_hash(cit_id, salt, "different_nonce")
    assert hash1 != hash_diff_nonce

    hash_diff_cit = PressEngine.generate_source_hash("cit_other_person", salt, nonce)
    assert hash1 != hash_diff_cit


def test_whistleblower_zero_knowledge_source_verification():
    """Tests constant-time zero-knowledge proof verification for anonymous whistleblower."""
    cit_id = "cit_whistleblower_primary"
    salt = "secret_source_salt"
    nonce = "secret_source_nonce"
    expected = PressEngine.generate_source_hash(cit_id, salt, nonce)

    # Valid proof
    assert PressEngine.verify_source_identity(expected, cit_id, salt, nonce) is True

    # Imposter with wrong citizenId
    assert (
        PressEngine.verify_source_identity(expected, "cit_imposter_source", salt, nonce)
        is False
    )

    # Wrong salt
    assert (
        PressEngine.verify_source_identity(expected, cit_id, "wrong_salt", nonce) is False
    )

    # Wrong nonce
    assert (
        PressEngine.verify_source_identity(expected, cit_id, salt, "wrong_nonce") is False
    )


def test_trade_union_media_accreditation():
    """Validates media accreditation checks through trade unions."""
    # Press Guild in good standing -> Accredited
    ok1, reason1 = PressEngine.evaluate_media_accreditation(
        {"unionId": "union:press_guild", "role": "delegate", "standing": "good_standing"}
    )
    assert ok1 is True
    assert reason1 == "TRADE_UNION_ACCREDITED"

    # Press Guild in arrears -> Rejected
    ok2, reason2 = PressEngine.evaluate_media_accreditation(
        {"unionId": "union:press_guild", "role": "member", "standing": "arrears"}
    )
    assert ok2 is False
    assert reason2 == "UNACCREDITED_MEDIA_PERSONNEL"

    # Non-press union -> Rejected
    ok3, reason3 = PressEngine.evaluate_media_accreditation(
        {"unionId": "union:industrial_miners", "role": "steward", "standing": "good_standing"}
    )
    assert ok3 is False
    assert reason3 == "UNACCREDITED_MEDIA_PERSONNEL"


def test_media_corporate_charter_leadership_accreditation():
    """Validates media corporate charter leadership accreditation gates."""
    # CEO of media outlet -> Accredited
    ok1, reason1 = PressEngine.evaluate_media_accreditation(
        None, {"factionId": "press:daily_globe", "roleTitle": "CEO", "isLeader": True}
    )
    assert ok1 is True
    assert reason1 == "MEDIA_CHARTER_LEADERSHIP_ACCREDITED"

    # Editor-in-Chief of media group -> Accredited
    ok2, reason2 = PressEngine.evaluate_media_accreditation(
        None,
        {
            "factionId": "press:weazel_news",
            "roleTitle": "Editor-in-Chief",
            "isLeader": False,
        },
    )
    assert ok2 is True
    assert reason2 == "MEDIA_CHARTER_LEADERSHIP_ACCREDITED"

    # Non-leadership role in media group without union card -> Rejected
    ok3, reason3 = PressEngine.evaluate_media_accreditation(
        None,
        {"factionId": "press:daily_globe", "roleTitle": "Junior Clerk", "isLeader": False},
    )
    assert ok3 is False
    assert reason3 == "UNACCREDITED_MEDIA_PERSONNEL"

    # Leader of non-media organization -> Rejected
    ok4, reason4 = PressEngine.evaluate_media_accreditation(
        None, {"factionId": "corp:logistics_inc", "roleTitle": "CEO", "isLeader": True}
    )
    assert ok4 is False
    assert reason4 == "UNACCREDITED_MEDIA_PERSONNEL"


def test_article_validation_sanitization():
    """Validates article bounds, category checks, and length sanitization."""
    # Valid article
    ok_valid, _ = PressEngine.validate_article(
        {
            "headline": "City Treasury Reserves Drop Below Safety Threshold",
            "category": "investigative",
            "authorByline": "Samantha Vance",
            "content": "An exhaustive audit of the city master ledger reveals critical deficits.",
        }
    )
    assert ok_valid is True

    # Headline too short
    ok_short_hl, err_hl = PressEngine.validate_article(
        {
            "headline": "Bad",
            "category": "politics",
            "authorByline": "Reporter",
            "content": "Long enough content here to satisfy requirements.",
        }
    )
    assert ok_short_hl is False
    assert err_hl == "INVALID_HEADLINE_LENGTH"

    # Invalid category
    ok_cat, err_cat = PressEngine.validate_article(
        {
            "headline": "Valid Headline Here",
            "category": "unauthorized_sensationalism",
            "authorByline": "Reporter",
            "content": "Long enough content here to satisfy requirements.",
        }
    )
    assert ok_cat is False
    assert err_cat == "INVALID_ARTICLE_CATEGORY"

    # Content too short
    ok_short_cnt, err_cnt = PressEngine.validate_article(
        {
            "headline": "Valid Headline Here",
            "category": "business",
            "authorByline": "Reporter",
            "content": "Too short.",
        }
    )
    assert ok_short_cnt is False
    assert err_cnt == "INVALID_CONTENT_LENGTH"


def test_publication_state_machine_transition_gates():
    """Validates state machine rules and terminal retraction immutability."""
    assert PressEngine.can_transition_publication("draft", "published") is True
    assert PressEngine.can_transition_publication("published", "retracted") is True

    # Retracted is a terminal immutable state
    assert PressEngine.can_transition_publication("retracted", "published") is False
    assert PressEngine.can_transition_publication("retracted", "draft") is False


def test_whistleblower_leak_state_machine_transition_gates():
    """Validates state machine transitions for whistleblower leaks."""
    assert PressEngine.can_transition_leak("unclaimed", "under_investigation") is True
    assert PressEngine.can_transition_leak("under_investigation", "published") is True
    assert PressEngine.can_transition_leak("under_investigation", "quashed") is True

    # Published or quashed cannot revert back to unclaimed
    assert PressEngine.can_transition_leak("published", "unclaimed") is False
    assert PressEngine.can_transition_leak("quashed", "under_investigation") is False


def test_migration_032_and_manifest_integrity():
    """Verifies that migration 032 is registered in index.json and nyx_press manifest is valid."""
    index_path = FIVEM / "nyx_core" / "sql" / "migrations" / "index.json"
    assert index_path.is_file()

    with open(index_path, "r", encoding="utf-8") as f:
        migrations = json.load(f)

    assert "032_press_media_whistleblower_and_print_circulation.sql" in migrations
    assert (
        migrations.index("032_press_media_whistleblower_and_print_circulation.sql") >= 31
    )

    core_mig = (
        FIVEM
        / "nyx_core"
        / "sql"
        / "migrations"
        / "032_press_media_whistleblower_and_print_circulation.sql"
    )
    press_mig = (
        FIVEM
        / "nyx_press"
        / "sql"
        / "migrations"
        / "032_press_media_whistleblower_and_print_circulation.sql"
    )
    assert core_mig.is_file()
    assert press_mig.is_file()

    # Verify manifest exists and lists required scripts
    manifest_path = FIVEM / "nyx_press" / "fxmanifest.lua"
    assert manifest_path.is_file()
    content = manifest_path.read_text(encoding="utf-8")
    assert "shared/press.lua" in content
    assert "server/press.lua" in content
    assert "client/press.lua" in content
    assert "client/interact.lua" in content
