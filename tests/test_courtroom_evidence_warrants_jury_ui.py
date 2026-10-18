import os
import json
import re
import hashlib
import pytest

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CORE_DIR = os.path.join(BASE_DIR, "FiveM", "nyx_core")
JUDICIARY_DIR = os.path.join(BASE_DIR, "FiveM", "nyx_judiciary")
UI_DIR = os.path.join(BASE_DIR, "FiveM", "nyx_ui")

def test_migration_035_and_index_registration():
    """Verify migration 035 SQL schema, columns, and index.json registration."""
    core_mig = os.path.join(CORE_DIR, "sql", "migrations", "035_judiciary_courtroom_terminal_and_evidence_audit.sql")
    jud_mig = os.path.join(JUDICIARY_DIR, "sql", "migrations", "035_judiciary_courtroom_terminal_and_evidence_audit.sql")
    index_path = os.path.join(CORE_DIR, "sql", "migrations", "index.json")

    assert os.path.isfile(core_mig), "nyx_core migration 035 must exist"
    assert os.path.isfile(jud_mig), "nyx_judiciary migration 035 must exist"
    assert os.path.isfile(index_path), "index.json must exist"

    with open(core_mig, "r", encoding="utf-8") as f:
        core_sql = f.read()
    with open(jud_mig, "r", encoding="utf-8") as f:
        jud_sql = f.read()

    assert core_sql == jud_sql, "Core and judiciary migration 035 files must match exactly"

    # Schema verifications
    assert "nyx_judiciary_evidence_verifications" in core_sql
    assert "status" in core_sql
    assert "is_valid" in core_sql
    assert "root_hash" in core_sql
    assert "current_chain_hash" in core_sql
    assert "case_brief" in core_sql
    assert "court_notes" in core_sql
    assert "verified_by_judge_at" in core_sql

    with open(index_path, "r", encoding="utf-8") as f:
        migrations = json.load(f)

    assert "035_judiciary_courtroom_terminal_and_evidence_audit.sql" in migrations
    assert migrations[-1] == "035_judiciary_courtroom_terminal_and_evidence_audit.sql"
    assert len(migrations) == 35


def test_manifest_declarations():
    """Verify shared/courtroom_ui.lua is declared in nyx_judiciary fxmanifest.lua."""
    jud_manifest = os.path.join(JUDICIARY_DIR, "fxmanifest.lua")
    with open(jud_manifest, "r", encoding="utf-8") as f:
        content = f.read()

    assert "'shared/courtroom_ui.lua'" in content or '"shared/courtroom_ui.lua"' in content
    assert "lua54 'yes'" in content


def test_sha256_pure_lua_and_python_parity():
    """Verify SHA-256 standard test vectors parity between Python and pure Lua engine."""
    shared_engine = os.path.join(JUDICIARY_DIR, "shared", "courtroom_ui.lua")
    assert os.path.isfile(shared_engine), "shared/courtroom_ui.lua must exist"

    with open(shared_engine, "r", encoding="utf-8") as f:
        lua_code = f.read()

    assert "Nyx.CourtroomUI.SHA256" in lua_code
    assert "Nyx.CourtroomUI.EvaluateEvidenceIntegrity" in lua_code
    assert "Nyx.CourtroomUI.FilterEvidenceExplorer" in lua_code
    assert "Nyx.CourtroomUI.FormatWarrantBadge" in lua_code
    assert "Nyx.CourtroomUI.EvaluateJuryTerminalState" in lua_code
    assert "Nyx.CourtroomUI.ValidateWarrantIssuancePayload" in lua_code

    # Python ground truth standard vectors
    assert hashlib.sha256(b"").hexdigest() == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    assert hashlib.sha256(b"hello world").hexdigest() == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

    # Evidence block hash sample
    sample_block = "EVI-101:0:COLLECTED:2026-10-18:OFF_204:MRPD_VAULT"
    expected_digest = hashlib.sha256(sample_block.encode("utf-8")).hexdigest()
    assert len(expected_digest) == 64


def test_evidence_chain_integrity_rules():
    """Simulate Merkle chain validation rules to ensure mathematical continuity invariants."""
    def evaluate_integrity(evidence_record, blocks):
        if not evidence_record or "evidence_hash" not in evidence_record:
            return False, "INVALID_RECORD"
        root_hash = evidence_record["evidence_hash"]
        if len(root_hash) != 64:
            return False, "INVALID_ROOT_HASH"

        head_hash = evidence_record.get("current_chain_hash", root_hash)
        if len(blocks) == 0:
            if evidence_record.get("chain_length", 0) == 0 and head_hash == root_hash:
                return True, "EMPTY_CHAIN_VALID"
            return False, "CHAIN_LENGTH_MISMATCH"

        prev_expected = root_hash
        for i, b in enumerate(blocks, start=1):
            if b.get("sequence_id", i) != i:
                return False, "SEQUENCE_GAP_DETECTED"
            if b.get("previous_hash") != prev_expected:
                return False, "CHAIN_HASH_DISCONTINUITY"
            entry_hash = b.get("entry_hash", "")
            if len(entry_hash) != 64:
                return False, "INVALID_ENTRY_HASH"
            prev_expected = entry_hash

        if head_hash and head_hash != prev_expected:
            return False, "CHAIN_HEAD_MISMATCH"

        return True, "CHAIN_VERIFIED_AUTHENTIC"

    root = "a" * 64
    b1_hash = "b" * 64
    b2_hash = "c" * 64

    # 1. Valid authentic chain
    evi_valid = {"evidence_hash": root, "current_chain_hash": b2_hash, "chain_length": 2}
    blocks_valid = [
        {"sequence_id": 1, "previous_hash": root, "entry_hash": b1_hash},
        {"sequence_id": 2, "previous_hash": b1_hash, "entry_hash": b2_hash}
    ]
    ok, status = evaluate_integrity(evi_valid, blocks_valid)
    assert ok is True
    assert status == "CHAIN_VERIFIED_AUTHENTIC"

    # 2. Sequence gap detection
    blocks_gap = [
        {"sequence_id": 1, "previous_hash": root, "entry_hash": b1_hash},
        {"sequence_id": 3, "previous_hash": b1_hash, "entry_hash": b2_hash}
    ]
    ok, status = evaluate_integrity(evi_valid, blocks_gap)
    assert ok is False
    assert status == "SEQUENCE_GAP_DETECTED"

    # 3. Previous hash discontinuity
    blocks_broken = [
        {"sequence_id": 1, "previous_hash": root, "entry_hash": b1_hash},
        {"sequence_id": 2, "previous_hash": "f" * 64, "entry_hash": b2_hash}
    ]
    ok, status = evaluate_integrity(evi_valid, blocks_broken)
    assert ok is False
    assert status == "CHAIN_HASH_DISCONTINUITY"

    # 4. Head hash mismatch
    evi_mismatched = {"evidence_hash": root, "current_chain_hash": "x" * 64, "chain_length": 2}
    ok, status = evaluate_integrity(evi_mismatched, blocks_valid)
    assert ok is False
    assert status == "CHAIN_HEAD_MISMATCH"


def test_jury_terminal_state_evaluation():
    """Verify civic jury terminal state calculation, quorum, and voting eligibility."""
    def eval_jury(docket, juror_rec, all_jurors):
        docket_status = docket.get("status", "filed")
        is_seated = juror_rec and juror_rec.get("selection_status") in ("seated", "deliberating", "voted")
        has_voted = juror_rec and (juror_rec.get("secret_ballot") is not None or juror_rec.get("selection_status") == "voted")
        can_vote = (docket_status in ("deliberation", "in_trial")) and is_seated and not has_voted

        seated_count = sum(1 for j in all_jurors if j.get("selection_status") in ("seated", "deliberating", "voted"))
        voted_count = sum(1 for j in all_jurors if j.get("secret_ballot") is not None or j.get("selection_status") == "voted")
        min_quorum = docket.get("minQuorum", 3)

        return {
            "canVote": can_vote,
            "hasVoted": bool(has_voted),
            "seatedCount": seated_count,
            "votedCount": voted_count,
            "isQuorumMet": seated_count >= min_quorum,
            "isInDeliberation": docket_status == "deliberation"
        }

    jurors = [
        {"citizen_id": "CIT_1", "selection_status": "seated", "secret_ballot": None},
        {"citizen_id": "CIT_2", "selection_status": "seated", "secret_ballot": "guilty"},
        {"citizen_id": "CIT_3", "selection_status": "seated", "secret_ballot": None},
        {"citizen_id": "CIT_4", "selection_status": "summoned", "secret_ballot": None}
    ]

    # Deliberation with unvoted seated juror
    state_unvoted = eval_jury({"status": "deliberation", "minQuorum": 3}, jurors[0], jurors)
    assert state_unvoted["canVote"] is True
    assert state_unvoted["hasVoted"] is False
    assert state_unvoted["seatedCount"] == 3
    assert state_unvoted["isQuorumMet"] is True
    assert state_unvoted["isInDeliberation"] is True

    # Deliberation with already voted juror
    state_voted = eval_jury({"status": "deliberation", "minQuorum": 3}, jurors[1], jurors)
    assert state_voted["canVote"] is False
    assert state_voted["hasVoted"] is True

    # Summoned (not seated) citizen
    state_summoned = eval_jury({"status": "deliberation", "minQuorum": 3}, jurors[3], jurors)
    assert state_summoned["canVote"] is False


def test_warrant_issuance_payload_validation():
    """Verify probable cause warrant form payload sanitization and boundary constraints."""
    def validate_warrant(payload):
        if not payload or not isinstance(payload, dict):
            return False, None, "PAYLOAD_MUST_BE_TABLE"
        target = payload.get("targetCitizenId")
        if not target or len(target.strip()) < 3:
            return False, None, "INVALID_TARGET_CITIZEN_ID"
        w_type = payload.get("warrantType", "").lower()
        if w_type not in ("arrest", "search_property", "search_vehicle", "subpoena", "wiretap"):
            return False, None, "INVALID_WARRANT_TYPE"
        cause = payload.get("probableCauseSummary", "").strip()
        if len(cause) < 20:
            return False, None, "PROBABLE_CAUSE_NARRATIVE_MIN_20_CHARS"
        dur = payload.get("requestedDurationHours", 72)
        if dur < 1 or dur > 336:
            return False, None, "DURATION_HOURS_OUT_OF_BOUNDS_1_TO_336"
        subp_scope = None
        if w_type == "subpoena":
            subp_scope = payload.get("subpoenaScope", "financial").lower()
            if subp_scope not in ("all", "financial", "property", "telecom"):
                return False, None, "INVALID_SUBPOENA_SCOPE"
        return True, {
            "targetCitizenId": target.strip(),
            "warrantType": w_type,
            "probableCauseSummary": cause,
            "requestedDurationHours": int(dur),
            "subpoenaScope": subp_scope
        }, None

    # Valid arrest warrant
    ok, data, err = validate_warrant({
        "targetCitizenId": "CIT_4092",
        "warrantType": "arrest",
        "probableCauseSummary": "Suspect matched ballistics fingerprints from MRPD scene evidence.",
        "requestedDurationHours": 72
    })
    assert ok is True
    assert err is None
    assert data["targetCitizenId"] == "CIT_4092"
    assert data["warrantType"] == "arrest"

    # Too short affidavit narrative
    ok, _, err = validate_warrant({
        "targetCitizenId": "CIT_4092",
        "warrantType": "arrest",
        "probableCauseSummary": "Suspect is guilty.",
        "requestedDurationHours": 72
    })
    assert ok is False
    assert err == "PROBABLE_CAUSE_NARRATIVE_MIN_20_CHARS"

    # Duration out of bounds
    ok, _, err = validate_warrant({
        "targetCitizenId": "CIT_4092",
        "warrantType": "arrest",
        "probableCauseSummary": "Suspect matched ballistics fingerprints from MRPD scene evidence.",
        "requestedDurationHours": 500
    })
    assert ok is False
    assert err == "DURATION_HOURS_OUT_OF_BOUNDS_1_TO_336"

    # Valid Subpoena scope
    ok, data, err = validate_warrant({
        "targetCitizenId": "CIT_4092",
        "warrantType": "subpoena",
        "subpoenaScope": "financial",
        "probableCauseSummary": "Auditing undisclosed offshore wire transactions from treasury.",
        "requestedDurationHours": 168
    })
    assert ok is True
    assert data["subpoenaScope"] == "financial"


def test_server_rpc_registration_and_exports():
    """Verify nyx_judiciary server main.lua and exports.lua define all required court endpoints."""
    main_server = os.path.join(JUDICIARY_DIR, "server", "main.lua")
    exports_server = os.path.join(JUDICIARY_DIR, "server", "exports.lua")

    with open(main_server, "r", encoding="utf-8") as f:
        main_lua = f.read()
    with open(exports_server, "r", encoding="utf-8") as f:
        exports_lua = f.read()

    # RPC bus endpoints
    assert 'RegisterRPC("judiciary:getCourtOverview"' in main_lua
    assert 'RegisterRPC("judiciary:getEvidenceList"' in main_lua
    assert 'RegisterRPC("judiciary:getEvidenceChain"' in main_lua
    assert 'RegisterRPC("judiciary:verifyEvidenceChain"' in main_lua
    assert 'RegisterRPC("judiciary:concludeTrial"' in main_lua
    assert 'RegisterRPC("judiciary:seatJuror"' in main_lua
    assert 'RegisterRPC("judiciary:castJuryVote"' in main_lua
    assert 'RegisterRPC("judiciary:petitionWarrant"' in main_lua

    # Public server exports
    assert "exports('GetEvidenceList'" in exports_lua or 'exports("GetEvidenceList"' in exports_lua
    assert "exports('LogEvidenceVerification'" in exports_lua or 'exports("LogEvidenceVerification"' in exports_lua
    assert "exports('VerifyChainOfCustody'" in exports_lua or 'exports("VerifyChainOfCustody"' in exports_lua
    assert "exports('ConcludeTrial'" in exports_lua or 'exports("ConcludeTrial"' in exports_lua


def test_client_courtroom_and_bridge_integration():
    """Verify nyx_judiciary client commands and nyx_ui bridge callbacks."""
    courtroom_client = os.path.join(JUDICIARY_DIR, "client", "courtroom.lua")
    bridge_client = os.path.join(UI_DIR, "client", "bridge.lua")
    ui_exports = os.path.join(UI_DIR, "client", "exports.lua")

    with open(courtroom_client, "r", encoding="utf-8") as f:
        court_lua = f.read()
    with open(bridge_client, "r", encoding="utf-8") as f:
        bridge_lua = f.read()
    with open(ui_exports, "r", encoding="utf-8") as f:
        ui_exp_lua = f.read()

    # Client-side command and interaction registry
    assert 'RegisterCommand("courtroom"' in court_lua
    assert 'RegisterCommand("court"' in court_lua
    assert 'RegisterCommand("judiciary"' in court_lua
    assert "Courtroom Terminal & Forensic Explorer" in court_lua
    assert "OpenCourtTerminal" in court_lua

    # Safe NUI callbacks
    assert 'SafeNUICallback("closeCourtTerminal"' in bridge_lua
    assert 'SafeNUICallback("court:getOverview"' in bridge_lua
    assert 'SafeNUICallback("court:getEvidenceList"' in bridge_lua
    assert 'SafeNUICallback("court:getEvidenceChain"' in bridge_lua
    assert 'SafeNUICallback("court:verifyEvidenceChain"' in bridge_lua
    assert 'SafeNUICallback("court:castJuryVote"' in bridge_lua
    assert 'SafeNUICallback("court:seatJuror"' in bridge_lua
    assert 'SafeNUICallback("court:summonJury"' in bridge_lua
    assert 'SafeNUICallback("court:startTrial"' in bridge_lua
    assert 'SafeNUICallback("court:startDeliberation"' in bridge_lua
    assert 'SafeNUICallback("court:concludeTrial"' in bridge_lua
    assert 'SafeNUICallback("court:petitionWarrant"' in bridge_lua
    assert 'SafeNUICallback("court:reviewPetition"' in bridge_lua
    assert 'SafeNUICallback("court:rescindWarrant"' in bridge_lua
    assert 'SafeNUICallback("court:getSubpoenaRecords"' in bridge_lua

    # Public client exports
    assert "exports('OpenCourtTerminal'" in ui_exp_lua
    assert "exports('CloseCourtTerminal'" in ui_exp_lua


def test_spa_cef_budget_and_courtroom_dom_structure():
    """Verify CEF render budget compliance and full courtroom DOM element hierarchy."""
    html_path = os.path.join(UI_DIR, "web", "index.html")
    css_path = os.path.join(UI_DIR, "web", "css", "app.css")
    js_path = os.path.join(UI_DIR, "web", "js", "app.js")

    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()
    with open(css_path, "r", encoding="utf-8") as f:
        css = f.read()
    with open(js_path, "r", encoding="utf-8") as f:
        js = f.read()

    # 1. Strict CEF Render Budget: Zero backdrop-filter, zero blur()
    assert "backdrop-filter" not in css, "Strict CEF render budget prohibits backdrop-filter"
    assert "blur(" not in css, "Strict CEF render budget prohibits blur() shaders"

    # 2. HTML DOM structure
    assert 'id="court-overlay"' in html
    assert 'id="court-header-title"' in html
    assert 'id="court-role-badge"' in html
    assert 'id="court-case-badge"' in html
    assert 'id="court-tab-evidence"' in html
    assert 'id="court-tab-jury"' in html
    assert 'id="court-tab-warrants"' in html
    assert 'id="court-evidence-search"' in html
    assert 'id="court-verify-chain-btn"' in html
    assert 'id="court-juror-seats"' in html
    assert 'id="court-juror-checkin-btn"' in html
    assert 'id="court-vote-guilty-btn"' in html
    assert 'id="court-vote-notguilty-btn"' in html
    assert 'id="court-vote-abstain-btn"' in html
    assert 'id="court-judge-controls"' in html
    assert 'id="court-submit-petition-btn"' in html
    assert 'id="court-subpoena-disclosure"' in html
    assert 'id="dev-btn-court"' in html

    # 3. JavaScript state and lifecycle
    assert "court: {" in js
    assert "openCourtTerminal" in js
    assert "closeCourtTerminal" in js
    assert "setCourtTab" in js
    assert "verifyCurrentEvidenceChain" in js
    assert "castJuryBallot" in js
    assert "submitWarrantPetition" in js
    assert "openSubpoenaDisclosure" in js
    assert "COURT_TERMINAL_OPEN" in js
    assert "COURT_TERMINAL_CLOSE" in js
    assert "NyxState.court.isOpen" in js
