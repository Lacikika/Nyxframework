/**
 * Nyxframework Master Single Page Application (app.js)
 * High-performance state management, NUI envelope router, and CEF budget visual renderers.
 * Features:
 * - Dynamic resource endpoint resolution & desktop browser dev mode fallback
 * - Keyboard Escape & Backspace modal hierarchy failsafes
 * - Zero-trust intent payload validation & isPending double-click locking
 * - WCAG AA+ ergonomics, auto-focused search inputs, and 100+ item list virtualization
 */

// 1. FiveM NUI Transport Bridge & Dynamic Endpoint Resolver
const getResourceEndpoint = (action) => {
    const resourceName = (typeof window.GetParentResourceName === 'function')
        ? window.GetParentResourceName()
        : 'nui-dev';
    return `https://${resourceName}/${action}`;
};

const isBrowserDev = (typeof window.invokeNative === 'undefined');

// Button intent locking helper to prevent double-submit exploits
async function lockButtonAction(buttonEl, actionFn) {
    if (!buttonEl || buttonEl.disabled || buttonEl.dataset.pending === 'true') {
        return;
    }
    buttonEl.disabled = true;
    buttonEl.dataset.pending = 'true';
    buttonEl.classList.add('is-pending');
    try {
        await actionFn();
    } finally {
        setTimeout(() => {
            if (buttonEl) {
                buttonEl.disabled = false;
                delete buttonEl.dataset.pending;
                buttonEl.classList.remove('is-pending');
            }
        }, 150);
    }
}

// Editable element detector to protect user typing from escape/backspace navigation
function isEditableElement(el) {
    if (!el) return false;
    const tagName = el.tagName ? el.tagName.toUpperCase() : '';
    return tagName === 'INPUT' || tagName === 'TEXTAREA' || el.isContentEditable;
}

// Desktop Browser Dev Mode Mock Handlers
function handleDevMockNui(action, data) {
    if (action === 'uiReady') return { success: true };
    if (action.startsWith('close')) return { success: true };
    if (action === 'hotbar:useSlot') {
        showNotification({ type: 'info', title: 'HOTBAR', message: `Used Hotbar Slot #${data.slot}` });
        return { success: true };
    }
    if (action === 'inventory:useItem') {
        showNotification({ type: 'success', title: 'ITEM USED', message: `Used slot #${data.slot}` });
        return { success: true };
    }
    if (action === 'inventory:dropItem') {
        showNotification({ type: 'warning', title: 'ITEM DROPPED', message: `Dropped ${data.amount || 1}x from slot #${data.slot}` });
        return { success: true };
    }
    if (action === 'inventory:giveItem') {
        showNotification({ type: 'info', title: 'GIVE ITEM', message: `Offered item from slot #${data.slot}` });
        return { success: true };
    }
    if (action === 'interact:selectOption') {
        showNotification({ type: 'info', title: 'INTERACT', message: `Triggered: ${data.label || 'Action'}` });
        return { success: true };
    }
    if (action === 'mdt:respondCall') {
        showNotification({ type: 'info', title: 'DISPATCH', message: `Route set to Call #${data.callId}` });
        return { success: true };
    }
    if (action === 'claimFreightContract') {
        showNotification({ type: 'success', title: 'FREIGHT CLAIMED', message: `Contract #${data.contractId} accepted.` });
        return { success: true };
    }
    if (action === 'loadFreightPallet') {
        showNotification({ type: 'info', title: 'FREIGHT', message: `Pallet loaded into nearest cargo vehicle.` });
        return { success: true };
    }
    if (action === 'deliverFreightContract') {
        showNotification({ type: 'success', title: 'FREIGHT COMPLETED', message: `Delivery verified & payout transferred!` });
        return { success: true };
    }
    if (action === 'faction:distributeDividends') {
        showNotification({ type: 'success', title: 'OSZTALÉK KIFIZETVE', message: `$${(data.netProfit * data.rate).toFixed(2)} osztalék szétosztva a tagok között.` });
        return { success: true };
    }
    if (action === 'faction:addMember') {
        showNotification({ type: 'success', title: 'TAG FELVÉVE', message: `${data.targetCitizenId} hozzáadva ${data.roleTitle} pozícióban.` });
        return { success: true };
    }
    if (action === 'faction:updateMember') {
        showNotification({ type: 'success', title: 'RBAC FRISSÍTVE', message: `${data.targetCitizenId} jogosultságai sikeresen frissítve.` });
        return { success: true };
    }
    if (action === 'faction:removeMember') {
        showNotification({ type: 'warning', title: 'TAG ELTÁVOLÍTVA', message: `${data.targetCitizenId} munkaviszonya megszűnt.` });
        return { success: true };
    }
    if (action === 'faction:signMultiSig') {
        showNotification({ type: 'success', title: 'MULTI-SIG ALÁÍRVA', message: `Jóváhagyva a #${data.requestId} letéti kifizetés.` });
        return { success: true };
    }
    if (action === 'faction:rejectMultiSig') {
        showNotification({ type: 'error', title: 'MULTI-SIG ELUTASÍTVA', message: `Megtagadva a #${data.requestId} letét.` });
        return { success: true };
    }
    if (action === 'faction:cancelMultiSig') {
        showNotification({ type: 'warning', title: 'MULTI-SIG TÖRÖLVE', message: `Visszavonva a #${data.requestId} letét.` });
        return { success: true };
    }
    if (action === 'faction:executeTimelocked') {
        showNotification({ type: 'success', title: 'LETÉT VÉGREHAJTVA', message: `Kifizetés #${data.requestId} teljesítve a célfiókra!` });
        return { success: true };
    }
    if (action === 'faction:proposeCBA') {
        showNotification({ type: 'info', title: 'CBA JAVASLAT', message: `"${data.title}" javaslat benyújtva az igazgatótanácsnak.` });
        return { success: true };
    }
    if (action === 'faction:ratifyCBA') {
        showNotification({ type: 'success', title: 'CBA RATIFIKÁLVA', message: `A kollektív szerződés hatályba lépett!` });
        return { success: true };
    }
    if (action === 'faction:claimStrikeRelief') {
        showNotification({ type: 'success', title: 'SZTRÁJKSEGÉLY', message: `Napi $150.00 sztrájksegély jóváírva!` });
        return { success: true };
    }
    if (action === 'faction:getOverview') {
        return {
            success: true,
            overview: {
                faction: {
                    faction_id: data.factionId || 'corp_los_santos_logistics',
                    legal_name: 'Los Santos Freight & Logistics Corp.',
                    charter_type: 'corporation',
                    treasury_account_id: 'CORP_VAULT_901',
                    inactivity_status: 'active'
                },
                treasuryBalance: 245000.00,
                fleetCount: 14,
                members: [
                    { citizenId: 'CIT_001', roleTitle: 'Chief Executive Officer', wageHourly: 120.00, equityShares: 45.00, permissionNodes: ['*'], isLeader: true, joinedAt: '2026-01-15' },
                    { citizenId: 'CIT_002', roleTitle: 'Chief Financial Officer', wageHourly: 95.00, equityShares: 30.00, permissionNodes: ['treasury:*', 'roster:view'], isLeader: false, joinedAt: '2026-01-18' },
                    { citizenId: 'CIT_003', roleTitle: 'Operations Director', wageHourly: 75.00, equityShares: 25.00, permissionNodes: ['roster:*', 'fleet:*', 'cba:ratify'], isLeader: false, joinedAt: '2026-02-01' }
                ],
                vaults: [
                    { vault_id: 'master_vault', vault_label: 'Fő Széf (Treasury Master)', account_id: 'CORP_VAULT_901', daily_limit: 100000, is_frozen: false },
                    { vault_id: 'payroll_vault', vault_label: 'Bérszámfejtési Széf', account_id: 'CORP_VAULT_902', daily_limit: 25000, is_frozen: false }
                ],
                signoffRules: [
                    { rule_id: 1, min_amount: 10000, max_amount: 50000, required_signatures: 2, timelock_minutes: 0 },
                    { rule_id: 2, min_amount: 50000, max_amount: null, required_signatures: 3, timelock_minutes: 60 }
                ],
                pendingMultiSig: [
                    { request_id: 801, vault_id: 'master_vault', target_account: 'CIT_VEND_99', amount: 18500.00, reason: 'Új kamionflotta beszerzési előleg', current_signatures: 1, required_signatures: 2, hasSigned: false }
                ],
                timelockedMultiSig: [
                    { request_id: 792, vault_id: 'master_vault', target_account: 'CORP_PROP_44', amount: 65000.00, reason: 'Paleto telephely bérleti díj', timelock_until: 'READY' }
                ],
                unions: [
                    { union_id: 'union_teamsters', union_name: 'Nemzetközi Fuvarozók Szakszervezete', sector: 'logistics', strike_fund_balance: 85000, runwayDays: 24 }
                ],
                cba: {
                    cba_id: 301,
                    cba_title: '2026. Évi Logisztikai Kollektív Szerződés',
                    status: 'ratified',
                    guaranteed_min_wage: 42.00,
                    overtime_multiplier: 1.50,
                    hazard_pay_bonus: 10.00
                },
                rbacAudit: [
                    { createdAt: '2026-10-18 09:30', actionType: 'EQUITY_GRANT', actorCitizenId: 'CIT_001', targetCitizenId: 'CIT_002', notes: 'Granted 30% equity' }
                ]
            }
        };
    }
    if (action === 'faction:getCitizenFactions') {
        return {
            success: true,
            factions: [
                { factionId: 'corp_los_santos_logistics', legalName: 'Los Santos Freight & Logistics Corp.', charterType: 'corporation' }
            ]
        };
    }
    if (action === 'closeCourtTerminal') {
        return { success: true };
    }
    if (action === 'court:getOverview') {
        return {
            success: true,
            overview: {
                citizenId: 'CIT_001',
                job: 'judge',
                isJudge: true,
                isLawEnforcement: true,
                dockets: [
                    {
                        docketId: 101,
                        docket_id: 101,
                        caseNumber: 'CR-2026-0042',
                        case_number: 'CR-2026-0042',
                        title: 'San Andreas Állam kontra Tyler Cross',
                        caseType: 'criminal',
                        case_type: 'criminal',
                        status: 'deliberation',
                        plaintiffName: 'San Andreas Állam Ügyészsége',
                        plaintiff_name: 'San Andreas Állam Ügyészsége',
                        defendantName: 'Tyler Cross (CIT_0921)',
                        defendant_name: 'Tyler Cross (CIT_0921)',
                        presidingJudgeName: 'Hon. Elena Rostova',
                        presiding_judge_name: 'Hon. Elena Rostova',
                        juryRequired: true,
                        jury_required: 1,
                        caseBrief: 'Fegyveres rablás és bűnszervezetben elkövetett pénzmosás vádja.',
                        case_brief: 'Fegyveres rablás és bűnszervezetben elkövetett pénzmosás vádja.'
                    }
                ],
                jurorRecord: {
                    jury_id: 1,
                    docket_id: 101,
                    citizen_id: 'CIT_001',
                    seat_index: 1,
                    selection_status: 'seated'
                },
                activeDocketForJuror: 101,
                juryDetails: {
                    docketId: 101,
                    status: 'deliberation',
                    isSummoned: true,
                    isSeated: true,
                    hasVoted: false,
                    jurors: [
                        { seat: 1, citizenId: 'CIT_001', name: 'Marcus Bell', status: 'seated', checkedInAt: '10:05' },
                        { seat: 2, citizenId: 'CIT_0488', name: 'Devon Lee', status: 'seated', checkedInAt: '10:07' },
                        { seat: 3, citizenId: 'CIT_0991', name: 'Sarah Connor', status: 'seated', checkedInAt: '10:12' },
                        { seat: 4, citizenId: 'CIT_1204', name: 'Alex Hunter', status: 'summoned', checkedInAt: null },
                        { seat: 5, citizenId: 'CIT_1420', name: 'David Vance', status: 'summoned', checkedInAt: null },
                        { seat: 6, citizenId: 'CIT_1880', name: 'Rachel Zane', status: 'summoned', checkedInAt: null }
                    ],
                    activeCount: 3,
                    requiredQuorum: 3,
                    quorumMet: true,
                    ballotOpen: true
                },
                evidence: [
                    {
                        evidence_id: 'EVI-2026-001',
                        docket_id: 101,
                        exhibit_label: 'EX-01',
                        type: 'casing',
                        evidence_type: 'casing',
                        label: '9mm hüvely (Legion Square)',
                        current_custodian_id: 'OFF_204',
                        current_facility: 'MRPD Vault 1',
                        is_sealed: 1,
                        is_contaminated: 0,
                        chain_length: 3,
                        created_at: '2026-10-18 09:15:00',
                        collector_citizen_id: 'OFF_102',
                        evidence_hash: '3f79666e679116e0ba6ea35e5345d7d981d806ff8278f66e85ffc610d40537f5',
                        current_chain_hash: '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b'
                    },
                    {
                        evidence_id: 'EVI-2026-002',
                        docket_id: 101,
                        exhibit_label: 'EX-02',
                        type: 'ballistics',
                        evidence_type: 'ballistics',
                        label: 'Combat Pistol (Serial: W-98214)',
                        current_custodian_id: 'LAB_TECH_01',
                        current_facility: 'Forensics Lab A',
                        is_sealed: 1,
                        is_contaminated: 0,
                        chain_length: 2,
                        created_at: '2026-10-18 09:30:00',
                        collector_citizen_id: 'OFF_102',
                        evidence_hash: 'a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0',
                        current_chain_hash: 'b2c3d4e5f6a17890123456789abcdef0123456789abcdef0123456789abcdef0'
                    },
                    {
                        evidence_id: 'EVI-2026-003',
                        docket_id: null,
                        exhibit_label: null,
                        type: 'swab',
                        evidence_type: 'swab',
                        label: 'GSR Kézkenet minta',
                        current_custodian_id: 'OFF_204',
                        current_facility: 'MRPD Vault 1',
                        is_sealed: 0,
                        is_contaminated: 0,
                        chain_length: 1,
                        created_at: '2026-10-18 10:00:00',
                        collector_citizen_id: 'OFF_204',
                        evidence_hash: 'c3d4e5f6a1b27890123456789abcdef0123456789abcdef0123456789abcdef0',
                        current_chain_hash: 'c3d4e5f6a1b27890123456789abcdef0123456789abcdef0123456789abcdef0'
                    }
                ],
                pendingPetitions: [
                    {
                        petition_id: 101,
                        target_citizen_id: 'CIT_0921',
                        warrant_type: 'search_property',
                        probable_cause_summary: 'Helyszíni ujjlenyomat és térfigyelő kamera alapján a gyanúsított a bűncselekményhez használt illegális lőfegyvert az ingatlanában rejtegeti.',
                        target_entity_id: 'PROP-402',
                        requested_duration_hours: 48,
                        petitioner_citizen_id: 'OFF_204',
                        created_at: '2026-10-18 09:45:00'
                    }
                ],
                activeWarrants: [
                    {
                        warrant_id: 'WAR-2026-0042',
                        target_citizen_id: 'CIT_0921',
                        type: 'subpoena',
                        subpoena_scope: 'all',
                        cause_summary: 'Bűnszervezeti pénzmosás és vagyonkimentés gyanúja miatt a bíróság azonnali főkönyvi zárolást és teljes pénzügyi feltárást rendel el.',
                        target_entity_id: 'BANK_RECORDS',
                        expires_at: '2026-10-21 10:00:00',
                        issued_by_citizen_id: 'CIT_001',
                        status: 'active'
                    },
                    {
                        warrant_id: 'WAR-2026-0041',
                        target_citizen_id: 'CIT_0884',
                        type: 'arrest',
                        cause_summary: 'Közvetlen szökésben lévő fegyveres rabló azonosítva a helyszínen.',
                        target_entity_id: null,
                        expires_at: '2026-10-20 18:30:00',
                        issued_by_citizen_id: 'CIT_001',
                        status: 'active'
                    }
                ]
            }
        };
    }
    if (action === 'court:getEvidenceList') {
        return {
            success: true,
            evidence: [
                {
                    evidence_id: 'EVI-2026-001',
                    docket_id: 101,
                    exhibit_label: 'EX-01',
                    type: 'casing',
                    evidence_type: 'casing',
                    current_custodian_id: 'OFF_204',
                    current_facility: 'MRPD Vault 1',
                    is_sealed: 1,
                    is_contaminated: 0,
                    chain_length: 3,
                    created_at: '2026-10-18 09:15:00',
                    collector_citizen_id: 'OFF_102',
                    evidence_hash: '3f79666e679116e0ba6ea35e5345d7d981d806ff8278f66e85ffc610d40537f5',
                    current_chain_hash: '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b'
                },
                {
                    evidence_id: 'EVI-2026-002',
                    docket_id: 101,
                    exhibit_label: 'EX-02',
                    type: 'ballistics',
                    evidence_type: 'ballistics',
                    current_custodian_id: 'LAB_TECH_01',
                    current_facility: 'Forensics Lab A',
                    is_sealed: 1,
                    is_contaminated: 0,
                    chain_length: 2,
                    created_at: '2026-10-18 09:30:00',
                    collector_citizen_id: 'OFF_102',
                    evidence_hash: 'a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0',
                    current_chain_hash: 'b2c3d4e5f6a17890123456789abcdef0123456789abcdef0123456789abcdef0'
                },
                {
                    evidence_id: 'EVI-2026-003',
                    docket_id: null,
                    exhibit_label: null,
                    type: 'swab',
                    evidence_type: 'swab',
                    current_custodian_id: 'OFF_204',
                    current_facility: 'MRPD Vault 1',
                    is_sealed: 0,
                    is_contaminated: 0,
                    chain_length: 1,
                    created_at: '2026-10-18 10:00:00',
                    collector_citizen_id: 'OFF_204',
                    evidence_hash: 'c3d4e5f6a1b27890123456789abcdef0123456789abcdef0123456789abcdef0',
                    current_chain_hash: 'c3d4e5f6a1b27890123456789abcdef0123456789abcdef0123456789abcdef0'
                }
            ]
        };
    }
    if (action === 'court:getEvidenceChain') {
        return {
            success: true,
            evidence: {
                evidence_id: data.evidenceId || 'EVI-2026-001',
                docket_id: 101,
                exhibit_label: 'EX-01',
                type: 'casing',
                current_custodian_id: 'OFF_204',
                current_facility: 'MRPD Vault 1',
                is_sealed: 1,
                is_contaminated: 0,
                created_at: '2026-10-18 09:15:00',
                collector_citizen_id: 'OFF_102',
                evidence_hash: '3f79666e679116e0ba6ea35e5345d7d981d806ff8278f66e85ffc610d40537f5',
                current_chain_hash: '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b'
            },
            chain: [
                {
                    sequence_index: 0,
                    action_type: 'COLLECTED',
                    custodian_id: 'OFF_102',
                    facility: 'Crime Scene (Legion Square)',
                    notes: 'Helyszínen rögzített hüvely, sterile tasakban elhelyezve.',
                    timestamp: '2026-10-18 09:15:00',
                    prev_hash: 'GENESIS',
                    block_hash: '3f79666e679116e0ba6ea35e5345d7d981d806ff8278f66e85ffc610d40537f5'
                },
                {
                    sequence_index: 1,
                    action_type: 'TRANSFERRED',
                    custodian_id: 'LAB_TECH_01',
                    facility: 'Forensics Lab A',
                    notes: 'Ballisztikai összehasonlító mikroszkóp vizsgálatra átadva.',
                    timestamp: '2026-10-18 09:40:00',
                    prev_hash: '3f79666e679116e0ba6ea35e5345d7d981d806ff8278f66e85ffc610d40537f5',
                    block_hash: '5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e'
                },
                {
                    sequence_index: 2,
                    action_type: 'VAULT_STORED',
                    custodian_id: 'OFF_204',
                    facility: 'MRPD Vault 1',
                    notes: 'Bírósági tárgyalásra letétbe helyezve a főszéfben.',
                    timestamp: '2026-10-18 10:10:00',
                    prev_hash: '5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e',
                    block_hash: '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b'
                }
            ]
        };
    }
    if (action === 'court:verifyEvidenceChain') {
        showNotification({ type: 'success', title: 'SHA-256 HITELESÍTVE', message: `Bűnjel ${data.evidenceId} Merkle lánca 100%-ban érvényes és sértetlen!` });
        return {
            success: true,
            status: 'VALID',
            data: {
                verified: true,
                evidenceId: data.evidenceId,
                chainLength: 3,
                blockCount: 3,
                rootHash: '3f79666e679116e0ba6ea35e5345d7d981d806ff8278f66e85ffc610d40537f5',
                currentChainHash: '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b'
            }
        };
    }
    if (action === 'court:castJuryVote') {
        showNotification({ type: 'success', title: 'SZAVAZAT LEADVA', message: `Titkos szavazatod (${data.vote}) beérkezett az esküdtszéki urnába!` });
        return { success: true };
    }
    if (action === 'court:seatJuror') {
        showNotification({ type: 'success', title: 'HELY ELFOGLALVA', message: 'Sikeresen elfoglaltad a kijelölt esküdtszéki széket!' });
        return { success: true };
    }
    if (action === 'court:summonJury') {
        showNotification({ type: 'info', title: 'ÜLNÖKÖK BEHÍVVA', message: 'Hivatalos esküdtszéki idézés kiküldve 6 polgárnak!' });
        return { success: true };
    }
    if (action === 'court:startTrial') {
        showNotification({ type: 'info', title: 'TÁRGYALÁS MEGNYITVA', message: 'A bírósági tárgyalási szakasz elindult.' });
        return { success: true };
    }
    if (action === 'court:startDeliberation') {
        showNotification({ type: 'warning', title: 'TANÁCSKOZÁS MEGNYITVA', message: 'Az esküdtszék elvonult a zárt tanácskozóterembe.' });
        return { success: true };
    }
    if (action === 'court:concludeTrial') {
        showNotification({ type: 'success', title: 'ÍTÉLET KIHIRDETVE', message: `A per lezárult: ${data.verdictRuling || 'Ítélet'}` });
        return { success: true };
    }
    if (action === 'court:petitionWarrant') {
        showNotification({ type: 'success', title: 'KÉRVÉNY BENYÚJTVA', message: 'Parancskérelmed rögzítve az elnöklő bírónak.' });
        return { success: true };
    }
    if (action === 'court:reviewPetition') {
        showNotification({ type: 'info', title: 'KÉRVÉNY ELBÍRÁLVA', message: `Döntés rögzítve: ${data.decision} (#${data.petitionId})` });
        return { success: true };
    }
    if (action === 'court:rescindWarrant') {
        showNotification({ type: 'warning', title: 'PARANCS VISSZAVONVA', message: `A(z) ${data.warrantId} számú parancs visszavonva.` });
        return { success: true };
    }
    if (action === 'court:getSubpoenaRecords') {
        return {
            success: true,
            records: {
                citizenId: data.targetCitizenId || 'CIT_0921',
                bankBalance: 84500.00,
                cashBalance: 12400.00,
                accounts: [
                    { id: 'CHK-9021', type: 'Folyószámla', balance: 45000.00, status: 'Aktív' },
                    { id: 'SAV-4410', type: 'Megtakarítási Letét', balance: 39500.00, status: 'Aktív' }
                ],
                properties: [
                    { id: 'PROP-402', address: '302 Alta St, Apt 14', value: 250000.00 },
                    { id: 'GAR-109', address: 'Popular St Raktár #4', value: 180000.00 }
                ],
                corporateShares: [
                    { factionId: 'corp_los_santos_logistics', name: 'Los Santos Freight & Logistics Corp.', sharesPercent: 12.5 }
                ],
                transactions: [
                    { date: '2026-10-17 18:22', amount: -15000.00, memo: 'Nemzetközi Átutalás ACCT_OFFSHORE_88 felé' },
                    { date: '2026-10-18 08:45', amount: 50000.00, memo: 'Ismeretlen Eredetű Készpénz Befizetés' }
                ]
            }
        };
    }
    // Parliamentary Mock Handlers for Desktop Dev Mode
    if (action === 'closeParliamentUI') {
        return { success: true };
    }
    if (action === 'parliament:getOverview' || action === 'parliament:getActiveSessions') {
        const mockSessions = [
            { session_id: 101, title: '2026. Évi Általános Parlamenti Választás', session_type: 'ELECTION', status: 'ACTIVE', quorum_target: 5, current_votes: 12, starts_at: '2026-10-15 08:00', ends_at: '2026-10-25 20:00' },
            { session_id: 102, title: '2026. Gazdasági Reform & Adópolitikai Népszavazás', session_type: 'REFERENDUM', status: 'ACTIVE', quorum_target: 10, current_votes: 7, starts_at: '2026-10-10 00:00', ends_at: '2026-10-20 23:59' },
            { session_id: 103, title: '2026. Őszi Időközi Képviselőválasztás', session_type: 'ELECTION', status: 'CONCLUDED', quorum_target: 5, current_votes: 18, starts_at: '2026-09-01 08:00', ends_at: '2026-09-10 20:00' }
        ];
        const mockCandidates = [
            { candidate_id: 1, session_id: 101, citizen_id: 'CIT_0144', display_name: 'Elena Vance', party: 'Polgári Szövetség a Jövőért', campaign_slogan: 'Átlátható önkormányzat, biztonságos utcák mindenkinek!', platform: 'Teljes közigazgatási digitalizáció, a kisvállalkozások adóterheinek csökkentése és a rendvédelmi erők belső felülvizsgálata.', endorsements_count: 7, is_verified: 1 },
            { candidate_id: 2, session_id: 101, citizen_id: 'CIT_0891', display_name: 'Marcus Brody', party: 'Munkás és Iparosok Pártja', campaign_slogan: 'Méltó bérek, erős szakszervezetek, tiszta ipar.', platform: 'A kollektív szerződések kiterjesztése, veszélyességi pótlékok emelése és a logisztikai dolgozók védelme a kizsákmányolás ellen.', endorsements_count: 5, is_verified: 1 },
            { candidate_id: 3, session_id: 101, citizen_id: 'CIT_0320', display_name: 'Sarah Connor', party: 'Független Reformmozgalom', campaign_slogan: 'Közbiztonság és zéró tolerancia a korrupcióval szemben.', platform: 'A büntető törvénykönyv szigorítása szervezett bűnözési tényállások esetén és a bírósági esküdtszékek digitalizációja.', endorsements_count: 3, is_verified: 0 },
            { candidate_id: 4, session_id: 101, citizen_id: 'CIT_0665', display_name: 'Julian Sterling', party: 'Szabadpiaci Koalíció', campaign_slogan: 'Dereguláció, alacsony adók, virágzó vállalkozások.', platform: 'Közteherviselési reform, az önkormányzati transzferadók 1%-ra csökkentése és a kikötői szabadkereskedelmi övezet bővítése.', endorsements_count: 2, is_verified: 0 }
        ];
        const mockLaws = [
            { law_id: 'PC-101', name: 'Fegyveres Rablás (Armed Robbery)', category: 'penal_felony', fine_default: 15000, fine_min: 5000, fine_max: 30000, prison_months_default: 24, prison_months_min: 12, prison_months_max: 60, updated_at: '2026-10-01 12:00' },
            { law_id: 'PC-102', name: 'Kábítószer-kereskedelem (Drug Trafficking)', category: 'penal_felony', fine_default: 25000, fine_min: 10000, fine_max: 50000, prison_months_default: 36, prison_months_min: 18, prison_months_max: 72, updated_at: '2026-09-18 15:30' },
            { law_id: 'PC-201', name: 'Garázdaság és Rendbontás (Disorderly Conduct)', category: 'penal_misdemeanor', fine_default: 2500, fine_min: 500, fine_max: 8000, prison_months_default: 6, prison_months_min: 0, prison_months_max: 12, updated_at: '2026-08-14 09:20' },
            { law_id: 'PC-301', name: 'Közúti Gyorshajtás (Severe Speeding)', category: 'penal_infraction', fine_default: 1200, fine_min: 200, fine_max: 3000, prison_months_default: 0, prison_months_min: 0, prison_months_max: 0, updated_at: '2026-07-22 11:10' },
            { law_id: 'TX-401', name: 'Általános Kiskereskedelmi Adó (Retail Sales Tax)', category: 'fiscal_policy', tax_rate_default: 0.08, tax_rate_min: 0.01, tax_rate_max: 0.15, fine_default: 0, prison_months_default: 0, updated_at: '2026-10-12 18:00' },
            { law_id: 'TX-402', name: 'Társasági Vagyontranszfer Adó (Asset Transfer Tax)', category: 'fiscal_policy', tax_rate_default: 0.02, tax_rate_min: 0.00, tax_rate_max: 0.10, fine_default: 0, prison_months_default: 0, updated_at: '2026-06-05 14:00' }
        ];
        const mockAmendments = [
            { audit_id: 1, session_id: 103, law_id: 'PC-101', field: 'fine', old_value: '10000', new_value: '15000', enacted_by_session_title: '2026. Őszi Rendvédelmi Módosító Csomag', enacted_at: '2026-10-01 12:00' },
            { audit_id: 2, session_id: 103, law_id: 'TX-401', field: 'rate', old_value: '0.07', new_value: '0.08', enacted_by_session_title: 'Költségvetési Stabilitási Törvény', enacted_at: '2026-10-12 18:00' }
        ];
        const mockPetitions = [
            { petition_id: 501, office_id: 'district_commissioner', sponsor_citizen_id: 'CIT_0144', reason: 'A választási ígéretek súlyos megszegése és az ipari körzet elhanyagolása.', signatures_count: 5, threshold: 5, status: 'THRESHOLD_MET', created_at: '2026-10-14 09:30' },
            { petition_id: 502, office_id: 'mayor', sponsor_citizen_id: 'CIT_0891', reason: 'A kikötői sztrájktörő intézkedések miatti bizalomvesztés.', signatures_count: 3, threshold: 5, status: 'COLLECTING', created_at: '2026-10-16 11:20' }
        ];
        const mockOfficials = [
            { office_id: 'mayor', title: 'City Mayor', holder_citizen_id: 'CIT_0010', holder_name: 'Arthur Pendelton', term_start: '2025-01-01', term_end: '2027-01-01' },
            { office_id: 'chief_magistrate', title: 'Chief Magistrate', holder_citizen_id: 'CIT_0012', holder_name: 'Helena Cross', term_start: '2024-06-01', term_end: '2028-06-01' },
            { office_id: 'district_commissioner', title: 'District Commissioner', holder_citizen_id: 'CIT_0055', holder_name: 'Roger Sterling', term_start: '2025-06-01', term_end: '2026-12-31' }
        ];
        return {
            success: true,
            sessions: mockSessions,
            candidates: mockCandidates,
            laws: mockLaws,
            amendments: mockAmendments,
            petitions: mockPetitions,
            officials: mockOfficials
        };
    }
    if (action === 'parliament:getCandidates') {
        return [
            { candidate_id: 1, session_id: data.sessionId || 101, citizen_id: 'CIT_0144', display_name: 'Elena Vance', party: 'Polgári Szövetség a Jövőért', campaign_slogan: 'Átlátható önkormányzat, biztonságos utcák mindenkinek!', platform: 'Teljes közigazgatási digitalizáció, a kisvállalkozások adóterheinek csökkentése és a rendvédelmi erők belső felülvizsgálata.', endorsements_count: 7, is_verified: 1 },
            { candidate_id: 2, session_id: data.sessionId || 101, citizen_id: 'CIT_0891', display_name: 'Marcus Brody', party: 'Munkás és Iparosok Pártja', campaign_slogan: 'Méltó bérek, erős szakszervezetek, tiszta ipar.', platform: 'A kollektív szerződések kiterjesztése, veszélyességi pótlékok emelése és a logisztikai dolgozók védelme a kizsákmányolás ellen.', endorsements_count: 5, is_verified: 1 },
            { candidate_id: 3, session_id: data.sessionId || 101, citizen_id: 'CIT_0320', display_name: 'Sarah Connor', party: 'Független Reformmozgalom', campaign_slogan: 'Közbiztonság és zéró tolerancia a korrupcióval szemben.', platform: 'A büntető törvénykönyv szigorítása szervezett bűnözési tényállások esetén és a bírósági esküdtszékek digitalizációja.', endorsements_count: 3, is_verified: 0 },
            { candidate_id: 4, session_id: data.sessionId || 101, citizen_id: 'CIT_0665', display_name: 'Julian Sterling', party: 'Szabadpiaci Koalíció', campaign_slogan: 'Dereguláció, alacsony adók, virágzó vállalkozások.', platform: 'Közteherviselési reform, az önkormányzati transzferadók 1%-ra csökkentése és a kikötői szabadkereskedelmi övezet bővítése.', endorsements_count: 2, is_verified: 0 }
        ];
    }
    if (action === 'parliament:castBallot') {
        const hash = 'NYX-BALLOT-' + Math.random().toString(36).substring(2, 7).toUpperCase() + '-2026';
        showNotification({ type: 'success', title: 'SZAVAZAT HITELÍTVE', message: `Preferenciás szavazatod rögzítve az urnában. Nyugtakód: ${hash}` });
        return { success: true, receiptHash: hash, sessionId: data.sessionId };
    }
    if (action === 'parliament:verifyReceipt') {
        const hash = data.receiptHash || '';
        if (hash.startsWith('NYX-BALLOT-')) {
            return {
                verified: true,
                session: '2026. Évi Általános Parlamenti Választás',
                timestamp: '2026-10-18 10:24:12',
                rankedCount: 3,
                preferences: ['Elena Vance', 'Marcus Brody', 'Sarah Connor'],
                hash: hash
            };
        }
        return { verified: false, error: 'A megadott nyugtakód nem található az auditált főkönyvben.' };
    }
    if (action === 'parliament:registerCandidate') {
        showNotification({ type: 'success', title: 'JELÖLTSÉG BEJEGYEZVE', message: `${data.displayName} hivatalosan nyilvántartásba véve.` });
        return { success: true, candidateId: Math.floor(Math.random() * 1000) + 10 };
    }
    if (action === 'parliament:endorseCandidate') {
        showNotification({ type: 'success', title: 'TÁMOGATÁS RÖGZÍTVE', message: 'Támogatói aláírásod rögzítésre került.' });
        return { success: true, endorsements: 6, verified: true };
    }
    if (action === 'parliament:getPenalCode' || action === 'parliament:getLawBook') {
        return [
            { law_id: 'PC-101', name: 'Fegyveres Rablás (Armed Robbery)', category: 'penal_felony', fine_default: 15000, fine_min: 5000, fine_max: 30000, prison_months_default: 24, prison_months_min: 12, prison_months_max: 60, updated_at: '2026-10-01 12:00' },
            { law_id: 'PC-102', name: 'Kábítószer-kereskedelem (Drug Trafficking)', category: 'penal_felony', fine_default: 25000, fine_min: 10000, fine_max: 50000, prison_months_default: 36, prison_months_min: 18, prison_months_max: 72, updated_at: '2026-09-18 15:30' },
            { law_id: 'PC-201', name: 'Garázdaság és Rendbontás (Disorderly Conduct)', category: 'penal_misdemeanor', fine_default: 2500, fine_min: 500, fine_max: 8000, prison_months_default: 6, prison_months_min: 0, prison_months_max: 12, updated_at: '2026-08-14 09:20' },
            { law_id: 'PC-301', name: 'Közúti Gyorshajtás (Severe Speeding)', category: 'penal_infraction', fine_default: 1200, fine_min: 200, fine_max: 3000, prison_months_default: 0, prison_months_min: 0, prison_months_max: 0, updated_at: '2026-07-22 11:10' },
            { law_id: 'TX-401', name: 'Általános Kiskereskedelmi Adó (Retail Sales Tax)', category: 'fiscal_policy', tax_rate_default: 0.08, tax_rate_min: 0.01, tax_rate_max: 0.15, fine_default: 0, prison_months_default: 0, updated_at: '2026-10-12 18:00' },
            { law_id: 'TX-402', name: 'Társasági Vagyontranszfer Adó (Asset Transfer Tax)', category: 'fiscal_policy', tax_rate_default: 0.02, tax_rate_min: 0.00, tax_rate_max: 0.10, fine_default: 0, prison_months_default: 0, updated_at: '2026-06-05 14:00' }
        ];
    }
    if (action === 'parliament:getTabulationAudit') {
        return {
            status: 'CONCLUDED',
            winnerId: 2,
            rounds: [
                {
                    round: 1,
                    tallies: { '1': 4, '2': 4, '3': 3, '4': 1 },
                    percentages: { '1': 33.3, '2': 33.3, '3': 25.0, '4': 8.3 },
                    eliminated: 4,
                    elected: null,
                    exhaustedBallots: 0
                },
                {
                    round: 2,
                    tallies: { '1': 5, '2': 5, '3': 2 },
                    percentages: { '1': 41.7, '2': 41.7, '3': 16.7 },
                    eliminated: 3,
                    elected: null,
                    exhaustedBallots: 0
                },
                {
                    round: 3,
                    tallies: { '1': 5, '2': 7 },
                    percentages: { '1': 41.7, '2': 58.3 },
                    eliminated: 1,
                    elected: 2,
                    exhaustedBallots: 0
                }
            ]
        };
    }
    if (action === 'parliament:proposeBill') {
        showNotification({ type: 'success', title: 'TÖRVÉNYJAVASLAT BENYÚJTVA', message: 'Törvényjavaslatod rögzítésre került és szavazásra lesz bocsátva.' });
        return { success: true, sessionId: 105 };
    }
    if (action === 'parliament:fileRecallPetition') {
        showNotification({ type: 'warning', title: 'VISSZAHÍVÁSI PETÍCIÓ MEGNYITVA', message: 'A petíció aláírásgyűjtése megkezdődött.' });
        return { success: true, petitionId: 503 };
    }
    if (action === 'parliament:signRecallPetition') {
        showNotification({ type: 'info', title: 'ALÁÍRÁS RÖGZÍTVE', message: 'Aláírásoddal hitelesítetted a visszahívási petíciót.' });
        return { success: true, signaturesCount: 4, threshold: 5 };
    }
    if (action === 'parliament:getAmendmentAudit') {
        return [
            { audit_id: 1, session_id: 103, law_id: 'PC-101', field: 'fine', old_value: '10000', new_value: '15000', enacted_by_session_title: '2026. Őszi Rendvédelmi Módosító Csomag', enacted_at: '2026-10-01 12:00' },
            { audit_id: 2, session_id: 103, law_id: 'TX-401', field: 'rate', old_value: '0.07', new_value: '0.08', enacted_by_session_title: 'Költségvetési Stabilitási Törvény', enacted_at: '2026-10-12 18:00' }
        ];
    }
    if (action === 'parliament:withdrawCandidacy') {
        showNotification({ type: 'info', title: 'JELÖLTSÉG VISSZAVONVA', message: 'Jelöltségedet visszavontad, kaució visszafizetve.' });
        return { success: true, candidateId: data.candidateId, collateralRefunded: 2500.00 };
    }
    if (action === 'parliament:getBoothTerminals') {
        return [
            { booth_id: 'booth:city_hall', label: 'City Hall Council Voting Booth', location_zone: 'Downtown Los Santos', total_ballots_cast: 42, is_active: 1 },
            { booth_id: 'booth:sandy_shores', label: 'Sandy Shores Regional Ballot Station', location_zone: 'Sandy Shores', total_ballots_cast: 18, is_active: 1 },
            { booth_id: 'booth:paleto_bay', label: 'Paleto Bay Justice Center Ballot Station', location_zone: 'Paleto Bay', total_ballots_cast: 12, is_active: 1 }
        ];
    }
    if (action === 'parliament:getTermAudits') {
        return [
            { audit_id: 1, office_id: 'mayor', citizen_id: 'CIT_0144', display_name: 'Elena Vance', event_type: 'instated', reason: 'Electoral victory certified by Instant-Runoff Voting', created_at: '2026-10-18 10:00:00' }
        ];
    }
    // Property Blind-Auction & Stewardship Portal Mock Handlers
    if (action === 'closePropertyPortal') {
        return { success: true };
    }
    if (action === 'property:getOverview') {
        return {
            success: true,
            citizenId: 'NYX-1001',
            citizenName: 'Alexander Vance',
            citizenBalance: 85400.00,
            auctions: [
                {
                    auctionId: 1,
                    propertyId: 101,
                    propertyLabel: 'Integrity Way Apt 101',
                    propertyCode: 'apt_integrity_101',
                    propertyType: 'residential',
                    zoneId: 'zone_ls_metro',
                    landAreaSqm: 120.00,
                    valuationPrice: 150000.00,
                    minimumBid: 75000.00,
                    totalBidsPlaced: 3,
                    isBlind: true,
                    endsAt: new Date(Date.now() + 86400000 * 1.5).toISOString(),
                    status: 'active',
                    hasPlacedBid: true,
                    mySealedBid: 82000.00,
                    isLeading: false
                },
                {
                    auctionId: 2,
                    propertyId: 103,
                    propertyLabel: 'Elysian Island Warehouse #4',
                    propertyCode: 'wh_elysian_04',
                    propertyType: 'industrial',
                    zoneId: 'zone_port_industrial',
                    landAreaSqm: 1250.00,
                    valuationPrice: 450000.00,
                    minimumBid: 225000.00,
                    totalBidsPlaced: 1,
                    isBlind: true,
                    endsAt: new Date(Date.now() + 86400000 * 2.8).toISOString(),
                    status: 'active',
                    hasPlacedBid: false,
                    mySealedBid: 0.00,
                    isLeading: false
                }
            ],
            ownedProperties: [
                {
                    id: 201,
                    code: 'store_vinewood_24',
                    label: 'Vinewood 24/7 Storefront',
                    type: 'commercial',
                    price: 280000.00,
                    landAreaSqm: 320.00,
                    maintenanceCondition: 78.50,
                    repairCost: 3440.00,
                    repairPointsNeeded: 21.5,
                    delinquencyTier: 1,
                    delinquentAmount: 2450.00,
                    consecutiveMissedCycles: 1,
                    zoneId: 'zone_ls_metro',
                    reclaimedForAuction: false,
                    stewardDelegateCitizenId: 'NYX-9941',
                    inactivityStatus: 'delegated',
                    isLocked: false,
                    assessment: {
                        price: 280000.00,
                        baseMillageRate: 0.0150,
                        effectiveMillageRate: 0.0225,
                        holdingMultiplier: 1.50,
                        propertiesOwned: 2,
                        landAreaSqm: 320.00,
                        millageTax: 2100.00,
                        maintenanceTax: 350.00,
                        penalty: 367.50,
                        totalTaxDue: 2817.50
                    },
                    badge: {
                        tier: 1,
                        badgeClass: 'badge-warning',
                        statusLabel: '1. FOKÚ FIGYELMEZTETÉS',
                        description: 'Késedelmes adófizetés. Kérjük rendezze tartozását.'
                    }
                },
                {
                    id: 202,
                    code: 'apt_delperro_302',
                    label: 'Del Perro Heights Luxury Apt',
                    type: 'residential',
                    price: 320000.00,
                    landAreaSqm: 180.00,
                    maintenanceCondition: 100.00,
                    repairCost: 0.00,
                    repairPointsNeeded: 0.0,
                    delinquencyTier: 0,
                    delinquentAmount: 0.00,
                    consecutiveMissedCycles: 0,
                    zoneId: 'zone_ls_metro',
                    reclaimedForAuction: false,
                    stewardDelegateCitizenId: null,
                    inactivityStatus: 'active',
                    isLocked: true,
                    assessment: {
                        price: 320000.00,
                        baseMillageRate: 0.0150,
                        effectiveMillageRate: 0.0225,
                        holdingMultiplier: 1.50,
                        propertiesOwned: 2,
                        landAreaSqm: 180.00,
                        millageTax: 2400.00,
                        maintenanceTax: 200.00,
                        penalty: 0.00,
                        totalTaxDue: 2600.00
                    },
                    badge: {
                        tier: 0,
                        badgeClass: 'badge-success',
                        statusLabel: 'RENDEZETT',
                        description: 'Nincs hátralék, az ingatlan jogi státusza tiszta.'
                    }
                }
            ],
            stewardship: {
                delegates: [
                    {
                        delegate_id: 1,
                        owner_citizen_id: 'NYX-1001',
                        delegate_citizen_id: 'NYX-9941',
                        scope: 'all',
                        first_name: 'Marcus',
                        last_name: 'Holloway',
                        is_active: 1,
                        authorized_at: '2026-10-15 14:00',
                        notes: 'Vezető jogi megbízott'
                    }
                ],
                managedProperties: [
                    {
                        property_id: 301,
                        property_code: 'wh_cypress_12',
                        label: 'Cypress Flats Storage Depot',
                        type: 'industrial',
                        price: 190000.00,
                        owner_citizen_id: 'NYX-4011',
                        inactivity_status: 'delegated'
                    }
                ],
                ownedProperties: []
            },
            reclamationLogs: [
                {
                    log_id: 101,
                    asset_type: 'property',
                    asset_id: 'wh_elysian_04',
                    previous_owner_citizen_id: 'NYX-0042',
                    delegate_citizen_id: null,
                    action: 'forfeited_to_auction',
                    auction_id: 2,
                    liquidated_funds: 0.00,
                    notes: '72 órás türelmi idő lejárt, nyilvános vakárverésre bocsátva.',
                    timestamp: Math.floor(Date.now() / 1000) - 7200
                },
                {
                    log_id: 98,
                    asset_type: 'property',
                    asset_id: 'store_vinewood_24',
                    previous_owner_citizen_id: 'NYX-1001',
                    delegate_citizen_id: 'NYX-9941',
                    action: 'warning_cleared',
                    auction_id: null,
                    liquidated_funds: 0.00,
                    notes: 'Gondnoki belépés hitelesítve, zárlati figyelmeztetés törölve.',
                    timestamp: Math.floor(Date.now() / 1000) - 43200
                }
            ]
        };
    }
    if (action === 'property:placeBid') {
        showNotification({ type: 'success', title: 'ZÁRT LICIT LETÉTBE HELYEZVE', message: `$${data.bidAmount || 0} összegű titkos licit rögzítve az árverésre (#${data.auctionId}).` });
        return { success: true, totalBidsPlaced: 4 };
    }
    if (action === 'property:payArrears') {
        showNotification({ type: 'success', title: 'ADÓHÁTRALÉK RENDEZVE', message: 'Az ingatlan adótartozása sikeresen befizetve a városi kincstárba!' });
        return { success: true };
    }
    if (action === 'property:repairCondition') {
        showNotification({ type: 'success', title: 'SZERKEZETI FELÚJÍTÁS', message: 'Karbantartási díj átutalva, az ingatlan szerkezeti állapota 100%-ra visszaállítva.' });
        return { success: true };
    }
    if (action === 'property:registerDelegate') {
        showNotification({ type: 'success', title: 'MEGBÍZÁS RÖGZÍTVE', message: `Állampolgári gondnoki megbízás rögzítve: ${data.delegateCitizenId}` });
        return { success: true };
    }
    if (action === 'property:revokeDelegate') {
        showNotification({ type: 'info', title: 'MEGBÍZÁS VISSZAVONVA', message: `Gondnoki meghatalmazás visszavonva (${data.delegateCitizenId}).` });
        return { success: true };
    }
    if (action === 'property:assignSteward') {
        showNotification({ type: 'success', title: 'GONDNOK KIJELÖLVE', message: 'Ingatlan gondnoki kijelölése sikeresen frissítve.' });
        return { success: true };
    }
    // Logistics Matrix & Elastic Market Monitor Dev Mocks
    if (action === 'closeMarketMonitor') {
        return { success: true };
    }
    if (action === 'logistics:getMatrixOverview') {
        const mockWarehouses = [
            { id: 'wh_dock_ls_01', name: 'Port of Los Santos Terminal Warehouse 4', zoneId: 'zone_port_industrial', routingBucket: 3001, shelfCount: 2, totalSlots: 18, occupiedSlots: 7, availableSlots: 11 },
            { id: 'wh_sandy_dist_01', name: 'Sandy Shores Industrial Freight Depot', zoneId: 'zone_sandy_shores', routingBucket: 3002, shelfCount: 2, totalSlots: 18, occupiedSlots: 4, availableSlots: 14 }
        ];
        const targetWhId = data.warehouseId || 'wh_dock_ls_01';
        const mockShelves = [
            { id: 'wh_dock_shelf_01', warehouseId: targetWhId, label: 'Bay A - Heavy Pallet Rack', tiers: 3, slotsPerTier: 3 },
            { id: 'wh_dock_shelf_02', warehouseId: targetWhId, label: 'Bay B - Parts & Tools Rack', tiers: 3, slotsPerTier: 3 }
        ];
        const mockNodes = [];
        for (let t = 1; t <= 3; t++) {
            for (let s = 1; s <= 3; s++) {
                const isOccupied = (t === 1 || (t === 2 && s <= 2));
                const nodeId = `wh_dock_shelf_01:t${t}_s${s}`;
                const isoX = (s - 2) * 50;
                const isoY = (3 - t) * 65 - ((s - 2) * 6);
                mockNodes.push({
                    id: nodeId,
                    shelfId: 'wh_dock_shelf_01',
                    warehouseId: targetWhId,
                    shelfLabel: 'Bay A - Heavy Pallet Rack',
                    tier: t,
                    slot: s,
                    isoX: isoX,
                    isoY: isoY,
                    layer: (3 - t) * 10 + s,
                    status: isOccupied ? 'occupied' : 'available',
                    temperatureZone: (t === 3) ? 'cold_storage' : 'ambient',
                    occupiedDropId: isOccupied ? `drop_${nodeId}` : null,
                    item: isOccupied ? {
                        itemId: (t === 1) ? 'steel_ingot' : 'repairkit',
                        label: (t === 1) ? 'Industrial Steel Ingot' : 'Vehicle Repair Kit',
                        count: (t === 1) ? 25 : 5,
                        weight: (t === 1) ? 50.0 : 15.0,
                        durability: 100
                    } : null,
                    worldCoords: { x: 1052.0 + (s * 0.5), y: -3096.0, z: -39.0 + (t * 0.5) },
                    localOffset: { x: (s - 2) * 0.55, y: 0.05, z: (t - 1) * 0.50 }
                });
            }
        }
        return {
            success: true,
            selectedWarehouseId: targetWhId,
            warehouses: mockWarehouses,
            shelves: mockShelves,
            nodes: mockNodes
        };
    }
    if (action === 'logistics:getMarketOverview') {
        const mockZones = [
            { zoneId: 'zone_ls_metro', zoneName: 'Los Santos Metro', cpi: 1.18, stockToDemandRatio: 0.55, healthStatus: 'MODERATE_SHORTAGE', shelfCount: 12, totalStock: 340, effectiveDemand: 620, baseDemandMultiplier: 1.35, taxSurcharge: 0.015, badge: { status: 'MODERATE_SHORTAGE', label: 'MÉRSÉKELT HIÁNY', badgeClass: 'badge-warning', color: '#F59E0B' } },
            { zoneId: 'zone_sandy_shores', zoneName: 'Blaine County Central', cpi: 0.95, stockToDemandRatio: 1.10, healthStatus: 'EQUILIBRIUM', shelfCount: 6, totalStock: 220, effectiveDemand: 200, baseDemandMultiplier: 0.85, taxSurcharge: 0.0, badge: { status: 'EQUILIBRIUM', label: 'PIACI EGYENSÚLY', badgeClass: 'badge-success', color: '#10B981' } },
            { zoneId: 'zone_paleto_bay', zoneName: 'Paleto Bay Enclave', cpi: 1.35, stockToDemandRatio: 0.22, healthStatus: 'CRITICAL_DEFICIT', shelfCount: 4, totalStock: 45, effectiveDemand: 205, baseDemandMultiplier: 0.75, taxSurcharge: 0.0, badge: { status: 'CRITICAL_DEFICIT', label: 'KRITIKUS HIÁNY', badgeClass: 'badge-danger', color: '#EF4444' } },
            { zoneId: 'zone_port_industrial', zoneName: 'Port Logistics Basin', cpi: 0.82, stockToDemandRatio: 1.65, healthStatus: 'SURPLUS', shelfCount: 8, totalStock: 580, effectiveDemand: 350, baseDemandMultiplier: 1.15, taxSurcharge: 0.005, badge: { status: 'SURPLUS', label: 'TÚLKÍNÁLAT / TÖBBLET', badgeClass: 'badge-info', color: '#06B6D4' } }
        ];
        const mockCommodities = [
            { shelfId: 'shelf_vinewood_tools', zoneId: 'zone_ls_metro', zoneName: 'Los Santos Metro', itemId: 'repairkit', name: 'Standard Repair Kit', category: 'tools', basePrice: 65.0, currentPrice: 88.0, priceMultiplier: 1.3538, currentStock: 18, targetCapacity: 60, effectiveDemand: 81, stockToDemandRatio: 0.2222, deficitUnits: 63, healthBadge: { status: 'CRITICAL_DEFICIT', label: 'KRITIKUS HIÁNY', badgeClass: 'badge-danger', color: '#EF4444' } },
            { shelfId: 'shelf_pillbox_meds', zoneId: 'zone_ls_metro', zoneName: 'Los Santos Metro', itemId: 'bandage_sterile', name: 'Sterile Field Bandage', category: 'medical', basePrice: 15.0, currentPrice: 22.5, priceMultiplier: 1.5, currentStock: 35, targetCapacity: 120, effectiveDemand: 162, stockToDemandRatio: 0.216, deficitUnits: 127, healthBadge: { status: 'CRITICAL_DEFICIT', label: 'KRITIKUS HIÁNY', badgeClass: 'badge-danger', color: '#EF4444' } },
            { shelfId: 'shelf_sandy_parts', zoneId: 'zone_sandy_shores', zoneName: 'Blaine County Central', itemId: 'refined_copper', name: 'Refined Copper Wire Spool', category: 'refining', basePrice: 45.0, currentPrice: 42.5, priceMultiplier: 0.9444, currentStock: 95, targetCapacity: 100, effectiveDemand: 85, stockToDemandRatio: 1.1176, deficitUnits: 0, healthBadge: { status: 'EQUILIBRIUM', label: 'PIACI EGYENSÚLY', badgeClass: 'badge-success', color: '#10B981' } },
            { shelfId: 'shelf_paleto_food', zoneId: 'zone_paleto_bay', zoneName: 'Paleto Bay Enclave', itemId: 'canned_food', name: 'Preserved Rations Box', category: 'food', basePrice: 20.0, currentPrice: 34.0, priceMultiplier: 1.7, currentStock: 12, targetCapacity: 80, effectiveDemand: 60, stockToDemandRatio: 0.20, deficitUnits: 48, healthBadge: { status: 'CRITICAL_DEFICIT', label: 'KRITIKUS HIÁNY', badgeClass: 'badge-danger', color: '#EF4444' } },
            { shelfId: 'shelf_port_bulk_ore', zoneId: 'zone_port_industrial', zoneName: 'Port Logistics Basin', itemId: 'iron_ore_bulk', name: 'Bulk Iron Ore Pallet', category: 'refining', basePrice: 35.0, currentPrice: 26.0, priceMultiplier: 0.7428, currentStock: 240, targetCapacity: 150, effectiveDemand: 172.5, stockToDemandRatio: 1.3913, deficitUnits: 0, healthBadge: { status: 'SURPLUS', label: 'TÚLKÍNÁLAT / TÖBBLET', badgeClass: 'badge-info', color: '#06B6D4' } }
        ];
        return {
            success: true,
            zones: mockZones,
            commodities: mockCommodities,
            citywideCpi: 1.08,
            totalShelves: 30,
            activeDeficitZones: 2,
            activeSurplusZones: 1
        };
    }
    if (action === 'logistics:getArbitrageRoutes') {
        return {
            success: true,
            routes: [
                { routeId: 'route_port_metro_tools', originWarehouseId: 'wh_dock_ls_01', originName: 'Port Terminal 4 Depot', destinationZoneId: 'zone_ls_metro', destinationName: 'Los Santos Metro', itemId: 'repairkit', itemName: 'Standard Repair Kit', recommendedUnits: 25, unitCost: 45.0, targetPrice: 88.0, unitSpread: 43.0, grossProfit: 1075.0, fuelCost: 22.75, projectedProfit: 1052.25, roiPct: 93.53, rating: 'EXCELLENT', distanceKm: 6.5 },
                { routeId: 'route_dock_paleto_meds', originWarehouseId: 'wh_dock_ls_01', originName: 'Port Terminal 4 Depot', destinationZoneId: 'zone_paleto_bay', destinationName: 'Paleto Bay Enclave', itemId: 'bandage_sterile', itemName: 'Sterile Field Bandage', recommendedUnits: 50, unitCost: 10.0, targetPrice: 22.5, unitSpread: 12.5, grossProfit: 625.0, fuelCost: 77.0, projectedProfit: 548.0, roiPct: 109.6, rating: 'PROFITABLE', distanceKm: 22.0 },
                { routeId: 'route_sandy_port_copper', originWarehouseId: 'wh_sandy_dist_01', originName: 'Sandy Shores Freight Depot', destinationZoneId: 'zone_port_industrial', destinationName: 'Port Logistics Basin', itemId: 'refined_copper', itemName: 'Refined Copper Wire Spool', recommendedUnits: 30, unitCost: 35.0, targetPrice: 52.0, unitSpread: 17.0, grossProfit: 510.0, fuelCost: 56.0, projectedProfit: 454.0, roiPct: 43.24, rating: 'PROFITABLE', distanceKm: 16.0 }
            ],
            myDispatches: [
                { dispatchId: 104, originWarehouseId: 'wh_dock_ls_01', destinationZoneId: 'zone_ls_metro', itemId: 'repairkit', units: 25, unitCost: 45.0, targetPrice: 88.0, projectedProfit: 1052.25, status: 'claimed', claimedAt: '2026-10-18 10:15' }
            ]
        };
    }
    if (action === 'logistics:bookDispatch') {
        showNotification({ type: 'success', title: 'FUVAR RÖGZÍTVE', message: `${data.units || 1} db ${data.itemId || 'áru'} fuvarmegbízás sikeresen lefoglalva!` });
        return { success: true, dispatchId: 105 };
    }
    if (action === 'logistics:cancelDispatch') {
        showNotification({ type: 'warning', title: 'FUVAR LEMONDVA', message: `Fuvarmegbízás (#${data.dispatchId}) feladva.` });
        return { success: true };
    }
    if (action === 'logistics:reserveNode') {
        showNotification({ type: 'success', title: 'REKESZ FENNTARTVA', message: `Rekesz (#${data.nodeId}) lezárva a következő ${data.durationMinutes || 60} percre.` });
        return { success: true };
    }
    // Vehicle Diagnostics & Civic Impound Terminal Mock Handlers
    if (action === 'closeVehicleTerminal') {
        return { success: true };
    }
    if (action === 'vehicle:getOverview') {
        const mockTelemetry = {
            vin: '1G1YY22U565100099',
            plate: 'LS-9428',
            modelName: 'Vapid Dominator GT',
            mileage: 1420.5,
            tripOdometer: 112.4,
            engineHealth: 920.0,
            oilQuality: 82.5,
            brakePadWear: 76.0,
            transmissionWear: 88.0,
            suspensionWear: 79.5,
            overallGrade: 'good',
            compositeScore: 84.8,
            isRoadworthy: true,
            dtcCodes: [],
            registration: {
                plate: 'LS-9428',
                vin: '1G1YY22U565100099',
                modelName: 'Vapid Dominator GT',
                status: 'valid',
                expiresAt: Math.floor(Date.now() / 1000) + (86400 * 9),
                fee: { baseFee: 250.00, latePenalty: 0.00, totalFee: 250.00 }
            },
            serviceLogs: [
                { service_type: 'oil_change', mileage_at_service: 1000.0, cost: 150.00, created_at: '2026-10-10 14:22' }
            ],
            diagnosticScans: [
                { scan_uuid: 'scan_20261010_101', mileage: 1000.0, engine_health: 980.0, overall_grade: 'good', scanned_at: '2026-10-10 14:20' }
            ],
            lastServiceMileage: 1000.0,
            serviceNotes: 'Rendszeres olajcsere elvégezve'
        };
        const mockOwned = [
            { vin: '1G1YY22U565100099', plate: 'LS-9428', modelName: 'Vapid Dominator GT', storageState: 'stored', garageId: 'legion_square', registrationStatus: 'valid', registrationExpiresAt: Math.floor(Date.now() / 1000) + (86400 * 9) },
            { vin: '2C3CDXBG8FH881122', plate: 'BC-5510', modelName: 'Bravado Buffalo STX', storageState: 'out', garageId: 'pillbox_hill', registrationStatus: 'valid', registrationExpiresAt: Math.floor(Date.now() / 1000) + (86400 * 12) }
        ];
        const mockImpounded = [
            {
                vin: '3N1AB7AP6HY334455',
                plate: 'LS-1092',
                modelName: 'Declasse Granger 3600LX',
                impoundLotId: 'impound_lot_ls',
                lotLabel: 'Los Santos Municipal Impound',
                impoundReason: 'Tilosban parkolás & lejárt forgalmi',
                impoundedAt: Math.floor(Date.now() / 1000) - (86400 * 2),
                cost: { baseFee: 500.00, storageDays: 2, dailyRate: 150.00, storageFee: 300.00, subtotal: 800.00, fiscalTier: 'solvent', surchargeRate: 0.00, emergencySurcharge: 0.00, totalFee: 800.00 }
            }
        ];
        return {
            success: true,
            telemetry: mockTelemetry,
            ownedVehicles: mockOwned,
            impoundedVehicles: mockImpounded,
            fiscalTier: 'solvent',
            impoundLots: {
                impound_lot_ls: { id: 'impound_lot_ls', label: 'Los Santos Municipal Auto Impound', baseFee: 500.00, dailyRate: 150.00 },
                impound_lot_sandy: { id: 'impound_lot_sandy', label: 'Blaine County Sheriff Impound Compound', baseFee: 350.00, dailyRate: 100.00 }
            },
            serviceCatalog: {
                oil_change: { label: 'Motorolaj Csere & Szűrő', baseCost: 150.00, component: 'oilQuality', targetRestore: 100.0, description: 'Szintetikus kenőanyag frissítése.' },
                brake_replacement: { label: 'Fékbetét & Féktárcsa Csere', baseCost: 350.00, component: 'brakePadWear', targetRestore: 100.0, description: 'Kerámia fékbetétek beszerelése.' },
                transmission_overhaul: { label: 'Sebességváltó Generál', baseCost: 850.00, component: 'transmissionWear', targetRestore: 100.0, description: 'Fogaskerekek és kuplung felújítása.' },
                suspension_tune: { label: 'Futómű Beállítás & Lengéscsillapító', baseCost: 400.00, component: 'suspensionWear', targetRestore: 100.0, description: 'Lengéscsillapítók és szilentek cseréje.' },
                full_service: { label: 'Teljes Műszaki Generál', baseCost: 1600.00, component: 'all', targetRestore: 100.0, description: 'Minden fődarab gyári felújítása.' }
            }
        };
    }
    if (action === 'vehicle:scanOBD') {
        showNotification({ type: 'success', title: 'OBD-II DIAGNOSZTIKA', message: 'Műszeres vizsgálat befejeződött. Hibakódok ellenőrizve.' });
        return {
            success: true,
            scanUuid: `scan_${Date.now()}_99`,
            overallGrade: 'good',
            compositeScore: 84.8,
            isRoadworthy: true,
            inspectionStatus: 'passed',
            dtcCodes: []
        };
    }
    if (action === 'vehicle:performService') {
        showNotification({ type: 'success', title: 'SZERVIZ ELVÉGEZVE', message: `A(z) ${data.serviceType} beavatkozás sikeresen teljesítve!` });
        return { success: true };
    }
    if (action === 'vehicle:resetTrip') {
        showNotification({ type: 'info', title: 'NAPI SZÁMLÁLÓ', message: 'Napi kilométerszámláló nullázva (0.0 km).' });
        return { success: true };
    }
    if (action === 'vehicle:releaseImpound') {
        showNotification({ type: 'success', title: 'JÁRMŰ KIVÁLTVA', message: 'Kiváltási díj kiegyenlítve a városi kincstár javára. Jármű átvehető!' });
        return { success: true, totalPaid: 800.00 };
    }
    if (action === 'vehicle:renewRegistration') {
        showNotification({ type: 'success', title: 'FORGALMI MEGÚJÍTVA', message: 'Forgalmi engedély érvényessége 14 nappal meghosszabbítva!' });
        return { success: true, totalPaid: 250.00 };
    }
    if (action === 'vehicle:getImpoundLots') {
        return {
            success: true,
            lots: {
                impound_lot_ls: { id: 'impound_lot_ls', label: 'Los Santos Municipal Auto Impound', baseFee: 500.00, dailyRate: 150.00 },
                impound_lot_sandy: { id: 'impound_lot_sandy', label: 'Blaine County Sheriff Impound Compound', baseFee: 350.00, dailyRate: 100.00 }
            }
        };
    }
    // Citizen OS Smartphone Mock Handlers
    if (action === 'closePhone') {
        return { success: true };
    }
    if (action === 'phone:getOverview') {
        return {
            success: true,
            citizen: {
                citizenId: 'NYX1024',
                fullName: 'Kovács István',
                job: 'Futár & Logisztikus',
                phoneNumber: '555-0428'
            },
            settings: {
                wallpaper: 'default_dark',
                darkMode: true,
                airplaneMode: false,
                notificationsEnabled: true
            },
            banking: {
                accountId: 'char:NYX1024:bank',
                balance: 14250.75,
                formattedBalance: '$14,250.75',
                fiscalState: 'SOLVENT',
                transferTaxRate: 0.02,
                transactions: [
                    { txUuid: 'tx_pay_01', isDebit: false, amount: 2400.0, formattedAmount: '+ $2,400.00', category: 'payroll', memo: 'Kincstári Munkabér', createdAt: '2026-10-18 09:30' },
                    { txUuid: 'tx_wire_02', isDebit: true, amount: 350.0, formattedAmount: '- $350.00', category: 'p2p_wire', memo: 'Alkatrész vásárlás', createdAt: '2026-10-17 18:12' }
                ]
            },
            logistics: {
                activeHaul: {
                    id: 104,
                    uuid: 'haul_mock_104',
                    itemId: 'Ipari Acéllemez',
                    quantity: 40,
                    totalPayout: 1850.0,
                    escrowDeposit: 277.5,
                    formattedPayout: '$1,850.00',
                    formattedEscrow: '$277.50',
                    status: 'in_transit',
                    statusBadge: 'badge-warning',
                    statusLabel: 'FOLYAMATBAN'
                },
                availableHaulsCount: 3
            },
            alerts: [
                {
                    id: 1,
                    uuid: 'alert_mock_1',
                    caller: 'KÖZÉRDEKŰ KÖZLÉNY',
                    category: 'traffic',
                    message: 'Karambol az Olympic Freeway déli lehajtójánál. Sávlezárás érvényben.',
                    location: 'Olympic Freeway',
                    priority: 'high',
                    createdAt: Date.now() - 3600000,
                    badge: { priorityBadgeClass: 'badge-danger', priorityLabel: 'SÜRGŐS', priorityIcon: 'fa-solid fa-triangle-exclamation', categoryLabel: 'Közlekedés', categoryIcon: 'fa-solid fa-car-burst', categoryColor: '#F59E0B' }
                }
            ]
        };
    }
    if (action === 'phone:transferMoney') {
        showNotification({ type: 'success', title: 'CIVICPAY ÁTUTALÁS', message: `Sikeresen átutaltál $${data.amount} összeget ${data.recipientCitizenId} részére!` });
        return { success: true, amount: data.amount, fee: Math.round(data.amount * 0.02 * 100) / 100, newBalance: 13800.00 };
    }
    if (action === 'phone:getFreightBoard') {
        return {
            success: true,
            contracts: [
                { id: 105, uuid: 'haul_105', itemId: 'Orvosi Fertőtlenítő', quantity: 25, totalPayout: 1200.0, escrowDeposit: 180.0, formattedPayout: '$1,200.00', formattedEscrow: '$180.00', status: 'available', statusBadge: 'badge-info', statusLabel: 'ELÉRHETŐ' },
                { id: 106, uuid: 'haul_106', itemId: 'Finomított Rézhuzal', quantity: 60, totalPayout: 2450.0, escrowDeposit: 367.5, formattedPayout: '$2,450.00', formattedEscrow: '$367.50', status: 'available', statusBadge: 'badge-info', statusLabel: 'ELÉRHETŐ' }
            ]
        };
    }
    if (action === 'phone:claimContract') {
        showNotification({ type: 'success', title: 'HAULEXPRESS', message: `Fuvarmegbízás #${data.contractId} sikeresen felvéve!` });
        return { success: true };
    }
    if (action === 'phone:sendEmergencyAlert') {
        showNotification({ type: 'success', title: '911 SEGÉLYHÍVÓ', message: 'Segélykérésed továbbítva a hatóságok felé!' });
        return { success: true, alertId: 99 };
    }
    if (action === 'phone:updateSettings') {
        showNotification({ type: 'info', title: 'BEÁLLÍTÁSOK', message: 'Okostelefon beállításaid sikeresen elmentve.' });
        return { success: true };
    }
    return { success: true, devMode: true };
}

async function postNui(action, data = {}) {
    if (isBrowserDev) {
        // Desktop browser developer debugging
        await new Promise(resolve => setTimeout(resolve, 50));
        return handleDevMockNui(action, data);
    }
    try {
        const resp = await fetch(getResourceEndpoint(action), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data)
        });
        return await resp.json();
    } catch (err) {
        return { success: false, error: err.message };
    }
}

// 2. Global UI State Store
const NyxState = {
    interact: {
        active: false,
        hasTarget: false,
        options: [],
        currentTarget: null,
        mode: 'radial'
    },
    hud: {
        visible: true,
        inVehicle: false,
        vitals: {}
    },
    inventory: {
        isOpen: false,
        selectedSlot: null,
        selectedContainer: null,
        playerData: null,
        targetData: null
    },
    hotbar: {
        activeSlot: 1,
        slots: {}
    },
    treasury: {
        isOpen: false,
        activeTab: 'balance_sheet',
        data: null,
        ledgerPage: 1,
        ledgerPageSize: 20,
        ledgerCategory: 'ALL',
        ledgerSearch: '',
        ledgerTotalEntries: 0,
        ledgerTotalPages: 1
    },
    mdt: {
        isOpen: false,
        activeTab: 'dispatch',
        calls: [],
        activeCallId: null
    },
    faction: {
        isOpen: false,
        activeTab: 'overview',
        currentFactionId: null,
        factionsList: [],
        data: null,
        selectedMemberCitId: null
    },
    court: {
        isOpen: false,
        activeTab: 'evidence',
        isJudge: false,
        dockets: [],
        currentDocket: null,
        evidenceList: [],
        selectedEvidenceId: null,
        chainBlocks: [],
        verificationResult: null,
        juryTerminal: null,
        hasVoted: false,
        pendingPetitions: [],
        activeWarrants: [],
        subpoenaRecords: null
    },
    parliament: {
        isOpen: false,
        activeTab: 'ballot',
        sessions: [],
        selectedSessionId: null,
        candidates: [],
        rankedCandidateIds: [],
        laws: [],
        amendments: [],
        petitions: [],
        officials: [],
        citizenVotes: {}
    },
    property: {
        isOpen: false,
        activeTab: 'auctions',
        citizenId: null,
        citizenName: 'Állampolgár',
        citizenBalance: 0,
        auctions: [],
        ownedProperties: [],
        stewardship: {
            delegates: [],
            managedProperties: [],
            ownedProperties: []
        },
        reclamationLogs: [],
        selectedAuction: null,
        selectedProperty: null,
        searchQuery: '',
        typeFilter: 'all',
        statusFilter: 'all'
    },
    logistics: {
        isOpen: false,
        activeTab: 'matrix',
        selectedWarehouseId: 'wh_dock_ls_01',
        selectedShelfId: null,
        selectedNodeId: null,
        selectedNode: null,
        warehouses: [],
        shelves: [],
        nodes: [],
        zones: [],
        commodities: [],
        arbitrageRoutes: [],
        myDispatches: [],
        searchQuery: '',
        marketSearchQuery: '',
        zoneFilter: 'all',
        categoryFilter: 'all',
        citywideCpi: 1.00
    },
    vehicle: {
        isOpen: false,
        activeTab: 'diagnostics',
        telemetry: null,
        ownedVehicles: [],
        impoundedVehicles: [],
        fiscalTier: 'solvent',
        impoundLots: {},
        serviceCatalog: {},
        selectedVehicleVin: null,
        impoundSearchQuery: '',
        impoundLotFilter: 'all',
        selectedService: null,
        selectedImpound: null
    },
    phone: {
        isOpen: false,
        activeApp: 'home',
        citizen: {
            citizenId: 'NYX1000',
            fullName: 'Állampolgár',
            job: 'Polgár',
            phoneNumber: '555-0100'
        },
        settings: {
            wallpaper: 'default_dark',
            darkMode: true,
            airplaneMode: false,
            notificationsEnabled: true
        },
        banking: {
            accountId: 'char:NYX:bank',
            balance: 0.00,
            formattedBalance: '$0.00',
            fiscalState: 'SOLVENT',
            transferTaxRate: 0.02,
            transactions: []
        },
        logistics: {
            activeHaul: null,
            availableHaulsCount: 0,
            availableContracts: [],
            searchQuery: ''
        },
        alerts: {
            feed: [],
            badgeCount: 0
        }
    },
    activeDialog: null
};

// 3. Centralized Audio Synthesizer (Web Audio API)
const AudioCtxClass = window.AudioContext || window.webkitAudioContext;
let audioCtx = null;

function playWebBeep(frequency = 880, type = 'sine', duration = 0.08) {
    try {
        if (!audioCtx) audioCtx = new AudioCtxClass();
        if (audioCtx.state === 'suspended') audioCtx.resume();
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = type;
        osc.frequency.setValueAtTime(frequency, audioCtx.currentTime);
        gain.gain.setValueAtTime(0.05, audioCtx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + duration);
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start();
        osc.stop(audioCtx.currentTime + duration);
    } catch (e) {
        // Audio policy or uninitialized context
    }
}

// 4. Notification Toast Renderer
function showNotification({ id, type, title, message, duration = 4500 }) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast-card ${type || 'info'}`;
    toast.id = id || `toast_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

    let iconClass = 'fa-solid fa-circle-info';
    if (type === 'success') iconClass = 'fa-solid fa-circle-check';
    else if (type === 'error') iconClass = 'fa-solid fa-circle-exclamation';
    else if (type === 'warning') iconClass = 'fa-solid fa-triangle-exclamation';

    toast.innerHTML = `
        <i class="${iconClass} toast-icon"></i>
        <div class="toast-content truncate">
            <div class="toast-title truncate">${title || 'NOTICE'}</div>
            <div class="toast-msg">${message || ''}</div>
        </div>
        <div class="toast-bar"><div class="toast-progress" style="transition: transform ${duration}ms linear; transform: scaleX(1);"></div></div>
    `;

    container.appendChild(toast);

    if (type === 'error') playWebBeep(320, 'square', 0.12);
    else if (type === 'success') playWebBeep(980, 'sine', 0.06);

    requestAnimationFrame(() => {
        const pBar = toast.querySelector('.toast-progress');
        if (pBar) pBar.style.transform = 'scaleX(0)';
    });

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(20px)';
        setTimeout(() => toast.remove(), 250);
    }, duration);
}

// 5. Spatial Raycast Reticle & Context Radial Menu
function setInteractActive(active) {
    NyxState.interact.active = active;
    const overlay = document.getElementById('interact-overlay');
    if (overlay) {
        overlay.classList.toggle('hidden', !active);
    }
    if (!active) {
        clearInteractTarget();
    }
}

function setPlacementActive(active, label) {
    const overlay = document.getElementById('placement-overlay');
    const labelEl = document.getElementById('placement-item-name');
    if (overlay) {
        overlay.classList.toggle('hidden', !active);
    }
    if (labelEl && label) {
        labelEl.textContent = label.toUpperCase();
    }
}

function setInteractTarget(targetData) {
    if (!targetData) return clearInteractTarget();

    NyxState.interact.hasTarget = true;
    NyxState.interact.options = targetData.options || [];
    NyxState.interact.currentTarget = targetData;

    const reticle = document.getElementById('reticle');
    if (reticle) reticle.classList.add('active');

    const radialWheel = document.getElementById('radial-container');
    const radialItems = document.getElementById('radial-items');
    const radialCenterTitle = document.getElementById('radial-center-title');

    if (radialWheel && radialItems) {
        radialItems.innerHTML = '';
        radialWheel.classList.remove('hidden');

        if (radialCenterTitle) {
            radialCenterTitle.textContent = (targetData.title || 'INTERACT').toUpperCase();
        }

        const count = targetData.options.length;
        const radius = 100; // px distance from center

        targetData.options.forEach((opt, idx) => {
            const angle = (idx / count) * 2 * Math.PI - Math.PI / 2;
            const x = Math.round(113 + radius * Math.cos(angle));
            const y = Math.round(113 + radius * Math.sin(angle));

            const btn = document.createElement('button');
            btn.className = 'radial-item-btn';
            btn.style.left = `${x}px`;
            btn.style.top = `${y}px`;
            btn.title = opt.label || 'Action';
            btn.innerHTML = `<i class="${opt.icon || 'fa-solid fa-hand'}"></i>`;

            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                lockButtonAction(btn, () => selectInteractOption(opt));
            });

            radialItems.appendChild(btn);
        });
    }

    playWebBeep(640, 'triangle', 0.04);
}

function clearInteractTarget() {
    NyxState.interact.hasTarget = false;
    NyxState.interact.options = [];
    const reticle = document.getElementById('reticle');
    const radialWheel = document.getElementById('radial-container');
    const menu = document.getElementById('target-menu');

    if (reticle) reticle.classList.remove('active');
    if (radialWheel) radialWheel.classList.add('hidden');
    if (menu) menu.classList.add('hidden');
}

function selectInteractOption(option) {
    playWebBeep(880, 'sine', 0.05);
    // Transmit player intent only
    postNui('interact:selectOption', {
        id: option.id,
        action: option.action,
        label: option.label
    });
    clearInteractTarget();
}

// 6. Minimalist Adaptive HUD & Vehicular Telemetry
function updateHudStatus(payload) {
    if (!payload) return;

    // Vitals
    if (payload.vitals) {
        const v = payload.vitals;
        NyxState.hud.vitals = v;

        const updateVital = (fillId, pillId, val) => {
            const fill = document.getElementById(fillId);
            const pill = document.getElementById(pillId);
            if (fill) fill.style.width = `${Math.max(0, Math.min(100, val))}%`;
            if (pill) {
                pill.classList.toggle('pulse-warn', val < 20);
            }
        };

        if (v.health !== undefined) updateVital('vital-health', 'vital-pill-health', v.health);
        if (v.armor !== undefined) updateVital('vital-armor', 'vital-pill-armor', v.armor);
        if (v.hunger !== undefined) updateVital('vital-hunger', 'vital-pill-hunger', v.hunger);
        if (v.thirst !== undefined) updateVital('vital-thirst', 'vital-pill-thirst', v.thirst);
        if (v.stamina !== undefined) updateVital('vital-stamina', 'vital-pill-stamina', v.stamina);

        if (v.voiceRange !== undefined) {
            const vFill = document.getElementById('vital-voice');
            if (vFill) vFill.style.width = `${Math.min(100, (v.voiceRange / 3) * 100)}%`;
        }

        const oPill = document.getElementById('vital-oxygen-pill');
        const oFill = document.getElementById('vital-oxygen');
        if (oPill && oFill) {
            if (v.isUnderwater) {
                oPill.classList.remove('hidden');
                oFill.style.width = `${v.oxygen || 100}%`;
            } else {
                oPill.classList.add('hidden');
            }
        }
    }

    // Vehicle Digital Cluster
    const vehHud = document.getElementById('hud-vehicle');
    if (vehHud && payload.vehicle) {
        if (payload.vehicle.inVehicle) {
            vehHud.classList.remove('hidden');
            const spd = document.getElementById('hud-speed');
            const fuelVal = document.getElementById('hud-fuel-val');
            const rpmFill = document.getElementById('hud-rpm-fill');
            const gear = document.getElementById('hud-gear');
            const warnEng = document.getElementById('veh-warn-engine');
            const warnFuel = document.getElementById('veh-warn-fuel');

            if (spd) spd.textContent = payload.vehicle.speed || 0;
            if (fuelVal) fuelVal.textContent = `${Math.round(payload.vehicle.fuel || 0)}%`;
            if (rpmFill) rpmFill.style.width = `${Math.round((payload.vehicle.rpm || 0) * 100)}%`;
            if (gear) gear.textContent = payload.vehicle.gear > 0 ? payload.vehicle.gear : 'R';

            if (warnEng) warnEng.classList.toggle('off', (payload.vehicle.engineHealth || 1000) > 350);
            if (warnFuel) warnFuel.classList.toggle('off', (payload.vehicle.fuel || 100) > 15);
        } else {
            vehHud.classList.add('hidden');
        }
    }

    // Finances
    if (payload.finances) {
        const cash = document.getElementById('hud-cash');
        const bank = document.getElementById('hud-bank');
        if (cash) cash.textContent = `$${Number(payload.finances.cash || 0).toLocaleString()}`;
        if (bank) bank.textContent = `$${Number(payload.finances.bank || 0).toLocaleString()}`;
    }
}

// 7. Dynamic Weight-Based Slot-Grid Inventory (with List Virtualization Support)
function renderSlots(containerId, invData) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = '';

    if (!invData) {
        container.innerHTML = '<div class="empty-state" style="grid-column: 1 / -1; padding: 40px; text-align: center; color: var(--text-dim);">No Container Connected</div>';
        return;
    }

    const totalSlots = invData.slots || 40;
    const items = invData.items || {};

    // Standard Grid Render for normal size
    for (let i = 1; i <= totalSlots; i++) {
        const slotEl = document.createElement('div');
        slotEl.className = 'slot-card';
        slotEl.dataset.slot = i;
        slotEl.dataset.container = containerId === 'player-slots' ? 'player' : 'target';

        const item = items[i];
        if (item) {
            slotEl.dataset.itemId = item.id || item.name;

            const maxDura = item.maxDurability || 100;
            const curDura = item.durability !== undefined ? item.durability : 100;
            const duraPercent = Math.max(0, Math.min(100, Math.round((curDura / maxDura) * 100)));

            let duraClass = '';
            if (duraPercent < 25) duraClass = 'crit';
            else if (duraPercent < 55) duraClass = 'low';

            const isSpoiled = item.isSpoiled || (item.decay && item.decay >= 1.0);

            slotEl.innerHTML = `
                <span class="slot-num">${i}</span>
                <i class="${item.icon || 'fa-solid fa-box'} slot-icon"></i>
                <span class="slot-label truncate">${item.label || item.name}</span>
                <span class="slot-count">${item.count > 1 ? item.count : ''}</span>
                <div class="slot-durability-track">
                    <div class="slot-durability-fill ${duraClass}" style="width: ${duraPercent}%;"></div>
                </div>
            `;

            if (isSpoiled) {
                slotEl.style.borderColor = 'var(--accent-crimson)';
            }
        } else {
            slotEl.innerHTML = `<span class="slot-num">${i}</span>`;
        }

        slotEl.addEventListener('click', () => {
            selectSlot(slotEl, item, containerId === 'player-slots' ? 'player' : 'target', i);
        });

        container.appendChild(slotEl);
    }
}

function selectSlot(element, item, containerType, slotIndex) {
    document.querySelectorAll('.slot-card').forEach(s => s.classList.remove('selected'));
    element.classList.add('selected');

    NyxState.inventory.selectedSlot = slotIndex;
    NyxState.inventory.selectedContainer = containerType;

    const inspectPopover = document.getElementById('inspect-popover');

    if (item && inspectPopover) {
        inspectPopover.classList.remove('hidden');
        document.getElementById('inspect-name').textContent = item.label || item.name;
        document.getElementById('inspect-rarity').textContent = (item.type || 'ITEM').toUpperCase();

        const maxDura = item.maxDurability || 100;
        const curDura = item.durability !== undefined ? item.durability : 100;
        const duraPercent = Math.max(0, Math.min(100, Math.round((curDura / maxDura) * 100)));

        document.getElementById('inspect-durability-text').textContent = `${duraPercent}%`;
        const duraBar = document.getElementById('inspect-durability-bar');
        if (duraBar) {
            duraBar.style.width = `${duraPercent}%`;
            duraBar.style.background = duraPercent < 25 ? 'var(--accent-crimson)' : (duraPercent < 55 ? 'var(--accent-amber)' : 'var(--accent-emerald)');
        }

        const spoiledFlag = document.getElementById('inspect-spoiled-flag');
        if (spoiledFlag) {
            spoiledFlag.classList.toggle('hidden', !(item.isSpoiled || (item.decay && item.decay >= 1.0)));
        }

        const metaGrid = document.getElementById('inspect-meta-details');
        if (metaGrid) {
            metaGrid.innerHTML = '';
            const meta = item.metadata || {};
            for (const [k, v] of Object.entries(meta)) {
                const row = document.createElement('div');
                row.className = 'meta-row';
                row.innerHTML = `<span class="meta-key">${k}:</span><span class="meta-val truncate">${v}</span>`;
                metaGrid.appendChild(row);
            }
        }
    } else if (inspectPopover) {
        inspectPopover.classList.add('hidden');
    }

    playWebBeep(520, 'sine', 0.03);
}

function updateWeightMeter(labelId, fillId, invData) {
    const lbl = document.getElementById(labelId);
    const fill = document.getElementById(fillId);
    if (!lbl || !fill) return;

    if (!invData) {
        lbl.textContent = '0.0 / 0.0 kg';
        fill.style.width = '0%';
        return;
    }

    const cur = (invData.weight || 0) / 1000;
    const max = (invData.maxWeight || 30000) / 1000;
    const pct = Math.min(100, (cur / max) * 100);

    lbl.textContent = `${cur.toFixed(1)} / ${max.toFixed(1)} kg`;
    fill.style.width = `${pct}%`;
    fill.style.background = pct > 95 ? 'var(--accent-crimson)' : (pct > 70 ? 'var(--accent-amber)' : 'var(--accent-cyan)');
}

function openInventory(data) {
    NyxState.inventory.isOpen = true;
    NyxState.inventory.playerData = data.player || { items: {}, weight: 0, maxWeight: 60000, slots: 50 };
    NyxState.inventory.targetData = data.target || null;

    const overlay = document.getElementById('inventory-overlay');
    if (overlay) overlay.classList.remove('hidden');

    renderSlots('player-slots', NyxState.inventory.playerData);
    renderSlots('target-slots', NyxState.inventory.targetData);

    updateWeightMeter('player-weight-label', 'player-weight-fill', NyxState.inventory.playerData);
    updateWeightMeter('target-weight-label', 'target-weight-fill', NyxState.inventory.targetData);

    const targetLabel = document.getElementById('target-inv-label');
    const targetIcon = document.getElementById('target-inv-icon');
    if (targetLabel && data.target) targetLabel.textContent = data.target.label || 'Target Container';
    if (targetIcon && data.target) targetIcon.className = data.target.icon || 'fa-solid fa-box-open';
}

function closeInventory() {
    NyxState.inventory.isOpen = false;
    NyxState.inventory.selectedSlot = null;
    const overlay = document.getElementById('inventory-overlay');
    const inspectPopover = document.getElementById('inspect-popover');
    if (overlay) overlay.classList.add('hidden');
    if (inspectPopover) inspectPopover.classList.add('hidden');
    postNui('close', { app: 'inventory' });
}

// 8. 5-Slot Bottom Hotbar
function updateHotbar(slotsData) {
    NyxState.hotbar.slots = slotsData || {};
    for (let i = 1; i <= 5; i++) {
        const item = slotsData && slotsData[i];
        const iconEl = document.getElementById(`hotbar-icon-${i}`);
        const labelEl = document.getElementById(`hotbar-label-${i}`);

        if (iconEl) {
            iconEl.innerHTML = item ? `<i class="${item.icon || 'fa-solid fa-box'}"></i>` : '';
        }
        if (labelEl) {
            labelEl.textContent = item ? (item.label || item.name) : `Slot ${i}`;
        }
    }
}

// 9. Civic Treasury Open Ledger Dashboard (`nyx_treasury`)
function openTreasuryDashboard(data) {
    if (!data) data = {};
    NyxState.treasury.isOpen = true;
    NyxState.treasury.data = data;

    const overlay = document.getElementById('treasury-overlay');
    if (overlay) overlay.classList.remove('hidden');

    // 1. Top Fiscal Badge & Crisis Banner
    const fiscalBadge = document.getElementById('treasury-fiscal-badge');
    const crisisBanner = document.getElementById('treasury-crisis-banner');
    const crisisTitle = document.getElementById('treasury-crisis-title');
    const crisisDesc = document.getElementById('treasury-crisis-desc');
    const wageScalePill = document.getElementById('treasury-wage-scale-pill');

    const state = data.fiscalState || (data.fiscalTelemetry && data.fiscalTelemetry.fiscalState) || 'SOLVENT';
    const wageMultiplier = (data.fiscalTelemetry && data.fiscalTelemetry.wageMultiplier !== undefined) 
        ? data.fiscalTelemetry.wageMultiplier 
        : (data.wageMultiplier !== undefined ? data.wageMultiplier : 1.0);
    const wagePct = (wageMultiplier * 100).toFixed(1);

    if (fiscalBadge) {
        fiscalBadge.className = 'badge';
        if (state === 'SOLVENT') {
            fiscalBadge.classList.add('badge-emerald');
            fiscalBadge.textContent = `SOLVENT (${wagePct}% WAGE)`;
        } else if (state === 'THROTTLED') {
            fiscalBadge.classList.add('badge-blue');
            fiscalBadge.textContent = `THROTTLED (${wagePct}% WAGE)`;
        } else if (state === 'AUSTERITY') {
            fiscalBadge.classList.add('badge-amber');
            fiscalBadge.textContent = `AUSTERITY (${wagePct}% WAGE)`;
        } else if (state === 'CRITICAL_DEFICIT') {
            fiscalBadge.classList.add('badge-red');
            fiscalBadge.textContent = 'CRITICAL DEFICIT (FROZEN)';
        } else if (state === 'CIRCUIT_TRIPPED') {
            fiscalBadge.classList.add('badge-red');
            fiscalBadge.textContent = 'CIRCUIT TRIPPED (LOCKED)';
        }
    }

    if (crisisBanner) {
        if (state === 'SOLVENT') {
            crisisBanner.classList.add('hidden');
        } else {
            crisisBanner.classList.remove('hidden');
            crisisBanner.className = 'treasury-crisis-banner ' + state.toLowerCase();
            if (wageScalePill) wageScalePill.textContent = `BÉRSKÁLA: ${wagePct}%`;

            if (state === 'THROTTLED') {
                if (crisisTitle) crisisTitle.textContent = 'MÉRSÉKELT FISKÁLIS KORLÁTOZÁS (THROTTLED)';
                if (crisisDesc) crisisDesc.textContent = 'A városi tartalék $5M alá csökkent. A közszolgálati bérek logaritmikus skálázás alatt állnak.';
            } else if (state === 'AUSTERITY') {
                if (crisisTitle) crisisTitle.textContent = 'MEGSZORÍTÁSI ÁLLAPOT (AUSTERITY)';
                if (crisisDesc) crisisDesc.textContent = 'Tartalék < $2.5M. Szigorú kiadási fékek, elszállítási felár és csökkentett bérek aktívak.';
            } else if (state === 'CRITICAL_DEFICIT') {
                if (crisisTitle) crisisTitle.textContent = 'KRITIKUS FISKÁLIS DEFICIT (CRITICAL DEFICIT)';
                if (crisisDesc) crisisDesc.textContent = 'Tartalék <= $500,000. Közszolgálati bérek befagyasztva (0%), önkormányzati infrastruktúra leállt.';
            } else if (state === 'CIRCUIT_TRIPPED') {
                if (crisisTitle) crisisTitle.textContent = 'FISKÁLIS ÁRAMKÖRVÉDELEM AKTIVÁLVA (CIRCUIT TRIPPED)';
                if (crisisDesc) crisisDesc.textContent = 'Hirtelen tőkekiáramlás vagy anomális tranzakció miatt a városi kifizetések automatikusan zárolva!';
            }
        }
    }

    // 2. Tab 1: Balance Sheet & Liquidity Overview
    const kpiReserve = document.getElementById('treasury-kpi-reserve');
    const kpiTarget = document.getElementById('treasury-kpi-target');
    const kpiTotalLiquidity = document.getElementById('treasury-kpi-total-liquidity');
    const kpiTaxes = document.getElementById('treasury-kpi-taxes');
    const kpiBal = document.getElementById('treasury-kpi-balance');

    const masterReserve = Number(data.masterReserve || data.reserveBalance || 0);
    const targetReserve = Number(data.targetReserve || 5000000.0);
    const reserveRatio = targetReserve > 0 ? ((masterReserve / targetReserve) * 100).toFixed(1) : '0.0';

    if (kpiReserve) kpiReserve.textContent = `$${masterReserve.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    if (kpiTarget) kpiTarget.textContent = `Céltartalék: $${targetReserve.toLocaleString()} (${reserveRatio}%)`;

    const sheet = data.balanceSheet || {};
    const totalLiquidity = Number(sheet.totalLiquidity || masterReserve);
    if (kpiTotalLiquidity) kpiTotalLiquidity.textContent = `$${totalLiquidity.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

    const salesTax = Number(data.salesTaxRate || data.salesTax || 0.08) * 100;
    const transferTax = Number(data.transferTaxRate || data.transferTax || 0.02) * 100;
    if (kpiTaxes) kpiTaxes.textContent = `ÁFA ${salesTax.toFixed(1)}% | P2P ${transferTax.toFixed(1)}%`;

    if (kpiBal) {
        const isBalanced = data.isBalanced !== false && (sheet.isBalanced !== false);
        kpiBal.textContent = isBalanced ? 'BALANCED' : 'IMBALANCE ALERT';
        kpiBal.classList.toggle('status-ok', isBalanced);
        kpiBal.classList.toggle('status-danger', !isBalanced);
    }

    renderTreasuryAccountsTable(sheet.accounts || data.accounts || []);

    // 3. Tab 2: Ledger Table
    renderTreasuryLedgerTable(data.recentTransactions || [], data.totalEntries || (data.recentTransactions ? data.recentTransactions.length : 0), 1, 1);

    // 4. Tab 3: Allocations & Sweeps
    renderTreasuryAllocations(data.allocations || []);
    renderTreasurySweeps(data.lastSweep ? [data.lastSweep] : (data.sweeps || []));

    // 5. Tab 4: Telemetry
    renderTreasuryTelemetry(data.fiscalTelemetry, data.circuitBreaker);
}

function renderTreasuryAccountsTable(accounts) {
    const tbody = document.getElementById('treasury-accounts-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (!accounts || accounts.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center text-dim" style="padding: 20px;">Nincs rögzített önkormányzati számla.</td></tr>';
        return;
    }

    accounts.forEach(acc => {
        const tr = document.createElement('tr');
        const bal = Number(acc.balance || 0);
        const cap = acc.capLimit ? `$${Number(acc.capLimit).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` : 'N/A';
        const share = Number(acc.sharePercentage || 0).toFixed(1);

        let solvencyBadge = '<span class="badge badge-emerald">SOLVENT</span>';
        if (acc.solvencyStatus === 'DEPLETED') solvencyBadge = '<span class="badge badge-red">DEPLETED</span>';
        else if (acc.solvencyStatus === 'DEFICIT_WARNING') solvencyBadge = '<span class="badge badge-red">DEFICIT WARNING</span>';
        else if (acc.solvencyStatus === 'LOW_RESERVE') solvencyBadge = '<span class="badge badge-amber">LOW RESERVE</span>';

        let typeBadge = `<span class="badge">${acc.type || 'department'}</span>`;
        if (acc.type === 'public_master') typeBadge = '<span class="badge badge-emerald">MASTER</span>';
        else if (acc.type === 'tax_pool') typeBadge = '<span class="badge badge-amber">TAX POOL</span>';
        else if (acc.type === 'grant_pool') typeBadge = '<span class="badge badge-blue">GRANT POOL</span>';

        tr.innerHTML = `
            <td><code>${acc.accountId || acc.id || '-'}</code></td>
            <td><strong>${acc.label || '-'}</strong></td>
            <td>${typeBadge}</td>
            <td><strong>$${bal.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
            <td>${share}%</td>
            <td>${cap}</td>
            <td>${solvencyBadge}</td>
        `;
        tbody.appendChild(tr);
    });
}

function renderTreasuryLedgerTable(entries, totalEntries, page, totalPages) {
    const tbody = document.getElementById('treasury-ledger-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (!entries || entries.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center text-dim" style="padding: 24px;">Nem található tranzakció a megadott szűrési feltételekkel.</td></tr>';
    } else {
        entries.forEach(tx => {
            const tr = document.createElement('tr');
            const amt = Number(tx.amount || 0);
            const ts = tx.created_at || tx.timestamp || 'NOW';
            const cat = tx.category || 'TRANSFER';
            const uuid = tx.transaction_uuid || tx.txUuid || '-';
            const debit = tx.debit_account || tx.debitAccount || '-';
            const credit = tx.credit_account || tx.creditAccount || '-';
            const auth = tx.authorized_by || tx.authorizedBy || '-';
            const memo = tx.memo || '-';

            let catBadge = `<span class="badge">${cat}</span>`;
            if (cat.includes('tax') || cat.includes('duty') || cat.includes('fee')) catBadge = `<span class="badge badge-emerald">${cat}</span>`;
            else if (cat.includes('payroll')) catBadge = `<span class="badge badge-blue">${cat}</span>`;
            else if (cat.includes('allocation') || cat.includes('subvention')) catBadge = `<span class="badge badge-amber">${cat}</span>`;
            else if (cat.includes('laundering')) catBadge = `<span class="badge badge-red">${cat}</span>`;

            tr.innerHTML = `
                <td style="font-size: 11px;">${ts}</td>
                <td>${catBadge}</td>
                <td><code>${debit}</code></td>
                <td><code>${credit}</code></td>
                <td><strong>$${amt.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
                <td style="font-size: 11px;"><code>${auth}</code></td>
                <td class="truncate" style="max-width: 220px;" title="${memo}">${memo}</td>
            `;
            tbody.appendChild(tr);
        });
    }

    NyxState.treasury.ledgerTotalEntries = totalEntries || 0;
    NyxState.treasury.ledgerTotalPages = totalPages || 1;
    NyxState.treasury.ledgerPage = page || 1;

    const pageInfo = document.getElementById('treasury-ledger-page-info');
    if (pageInfo) {
        pageInfo.textContent = `Oldal ${page} / ${totalPages} (Összesen ${totalEntries} tétel)`;
    }

    const prevBtn = document.getElementById('treasury-ledger-prev-btn');
    const nextBtn = document.getElementById('treasury-ledger-next-btn');
    if (prevBtn) prevBtn.disabled = (page <= 1);
    if (nextBtn) nextBtn.disabled = (page >= totalPages);
}

function renderTreasuryAllocations(allocations) {
    const tbody = document.getElementById('treasury-allocations-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (!allocations || allocations.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center text-dim" style="padding: 20px;">Nincs konfigurált költségvetési elosztás.</td></tr>';
        return;
    }

    allocations.forEach(alloc => {
        const tr = document.createElement('tr');
        const dept = alloc.departmentLabel || alloc.label || alloc.targetDepartment;
        const cat = alloc.allocationCategory || 'general';
        const splitPct = Number(alloc.percentageSplit || 0).toFixed(1);
        const curBal = Number(alloc.currentBalance || 0);
        const cap = alloc.capLimit ? `$${Number(alloc.capLimit).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` : 'NINCS KORLÁT';
        const progress = Math.min(100.0, Number(alloc.progressPercentage || 0));

        let catBadge = `<span class="badge">${cat}</span>`;
        if (cat === 'emergency_services') catBadge = '<span class="badge badge-blue">KÉSZENLÉTI SZERVEK</span>';
        else if (cat === 'infrastructure') catBadge = '<span class="badge badge-amber">INFRASTRUKTÚRA</span>';
        else if (cat === 'social_dividend') catBadge = '<span class="badge badge-emerald">TÁRSADALMI OSZTALÉK</span>';

        let progressClass = '';
        if (progress >= 90) progressClass = 'danger';
        else if (progress >= 70) progressClass = 'warning';

        const lastAlloc = alloc.lastAllocatedAmount ? `$${Number(alloc.lastAllocatedAmount).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` : '-';
        const lastDate = alloc.lastAllocatedAt || '-';

        tr.innerHTML = `
            <td><strong>${dept}</strong><br><code style="font-size: 10px;">${alloc.targetDepartment}</code></td>
            <td>${catBadge}</td>
            <td><strong>${splitPct}%</strong></td>
            <td><strong>$${curBal.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
            <td>${cap}</td>
            <td style="min-width: 130px;">
                <div style="display: flex; justify-content: space-between; font-size: 10px; margin-bottom: 2px;">
                    <span>${progress.toFixed(1)}%</span>
                </div>
                <div class="cap-progress">
                    <div class="cap-progress-fill ${progressClass}" style="width: ${progress}%;"></div>
                </div>
            </td>
            <td style="font-size: 11px;">${lastAlloc}<br><span class="text-dim" style="font-size: 9px;">${lastDate}</span></td>
        `;
        tbody.appendChild(tr);
    });
}

function renderTreasurySweeps(sweeps) {
    const tbody = document.getElementById('treasury-sweeps-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (!sweeps || sweeps.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center text-dim" style="padding: 16px;">Még nem futott automatikus adóelszámolási ciklus.</td></tr>';
        return;
    }

    sweeps.forEach(s => {
        const tr = document.createElement('tr');
        const uuid = (s.sweep_uuid || s.sweepUuid || '-').substring(0, 18);
        const ts = s.created_at || s.timestamp || 'NOW';
        const before = Number(s.tax_pool_balance_before || s.collected || 0);
        const swept = Number(s.total_swept || s.totalSwept || 0);
        const retained = Number(s.master_surplus_retained || s.masterSurplusRetained || 0);
        const count = s.allocations_count || (s.splits ? s.splits.length : 0);
        const state = s.fiscal_state || s.fiscalState || 'SOLVENT';

        let stateBadge = `<span class="badge badge-emerald">${state}</span>`;
        if (state !== 'SOLVENT') stateBadge = `<span class="badge badge-amber">${state}</span>`;

        tr.innerHTML = `
            <td><code>${uuid}...</code></td>
            <td style="font-size: 11px;">${ts}</td>
            <td><strong>$${before.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
            <td><strong>$${swept.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
            <td>$${retained.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
            <td>${count} számla</td>
            <td>${stateBadge}</td>
        `;
        tbody.appendChild(tr);
    });
}

function renderTreasuryTelemetry(telemetry, circuit) {
    telemetry = telemetry || {};
    circuit = circuit || {};

    const wageMult = Number(telemetry.wageMultiplier !== undefined ? telemetry.wageMultiplier : 1.0);
    const multEl = document.getElementById('telemetry-wage-mult');
    const pctEl = document.getElementById('telemetry-wage-pct');
    if (multEl) multEl.textContent = `${wageMult.toFixed(2)}x`;
    if (pctEl) pctEl.textContent = `${(wageMult * 100).toFixed(1)}% Közszolgálati Bérkifizetés`;

    const drainEl = document.getElementById('telemetry-drain-hr');
    const runwayEl = document.getElementById('telemetry-runway-hours');
    const drainVal = Number(telemetry.drainVelocityPerHour || 0);
    if (drainEl) drainEl.textContent = `$${drainVal.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} / óra`;

    if (runwayEl) {
        if (telemetry.runwayHours !== null && telemetry.runwayHours !== undefined) {
            runwayEl.textContent = `Becsült tartalékidő: ${telemetry.runwayHours} óra`;
        } else {
            runwayEl.textContent = 'Becsült tartalékidő: STABIL (Kritikus küszöb felett)';
        }
    }

    const rollingEl = document.getElementById('telemetry-rolling-outflow');
    const rollingVal = Number(circuit.drainVelocity?.totalOutflow || 0);
    if (rollingEl) rollingEl.textContent = `$${rollingVal.toLocaleString()} / $750,000`;

    const circuitStatusEl = document.getElementById('telemetry-circuit-status');
    const tripReasonEl = document.getElementById('telemetry-trip-reason');
    const isTripped = Boolean(circuit.tripped || telemetry.circuitTripped);

    if (circuitStatusEl) {
        circuitStatusEl.textContent = isTripped ? 'LEOLDVA (TRIPPED)' : 'NORMAL (ZÁRT)';
        circuitStatusEl.className = 'badge ' + (isTripped ? 'badge-red' : 'badge-emerald');
    }
    if (tripReasonEl) tripReasonEl.textContent = circuit.tripReason || 'Nincs aktív leoldás';

    const autoRepairEl = document.getElementById('telemetry-autorepair-status');
    const impoundEl = document.getElementById('telemetry-impound-status');
    const dispatchEl = document.getElementById('telemetry-dispatch-status');
    const infra = telemetry.infrastructure || {};

    if (autoRepairEl) {
        const isOffline = infra.autoRepair === 'OFFLINE';
        autoRepairEl.textContent = isOffline ? 'LEÁLLVA (OFFLINE)' : 'ÜZEMEL';
        autoRepairEl.className = 'badge ' + (isOffline ? 'badge-red' : 'badge-emerald');
    }
    if (impoundEl) {
        const hasSurcharge = Boolean(infra.impoundSurchargeActive);
        impoundEl.textContent = hasSurcharge ? '+50% VÁLSÁG DÍJ' : 'NORMÁL DÍJAK';
        impoundEl.className = 'badge ' + (hasSurcharge ? 'badge-amber' : 'badge-emerald');
    }
    if (dispatchEl) {
        const isDegraded = infra.aiDispatch === 'DEGRADED';
        dispatchEl.textContent = isDegraded ? 'CSÖKKENTETT KÉSZENLÉT' : 'OPTIMÁLIS';
        dispatchEl.className = 'badge ' + (isDegraded ? 'badge-red' : 'badge-emerald');
    }
}

function fetchTreasuryLedgerPage(page) {
    NyxState.treasury.ledgerPage = page;
    postNui('treasury:getLedgerPage', {
        page: page,
        pageSize: NyxState.treasury.ledgerPageSize,
        category: NyxState.treasury.ledgerCategory,
        search: NyxState.treasury.ledgerSearch
    }, function(res) {
        if (res && res.success) {
            renderTreasuryLedgerTable(res.entries || [], res.totalEntries || 0, res.page || 1, res.totalPages || 1);
        }
    });
}

function prependTreasuryLedgerRow(tx) {
    if (!tx || !NyxState.treasury.isOpen) return;
    const tbody = document.getElementById('treasury-ledger-rows');
    if (!tbody) return;

    const tr = document.createElement('tr');
    tr.style.animation = 'flash-in 0.8s ease';
    const amt = Number(tx.amount || 0);
    const ts = tx.created_at || tx.timestamp || 'ÉPP MOST';
    const cat = tx.category || 'TRANSFER';
    const debit = tx.debit_account || tx.debitAccount || '-';
    const credit = tx.credit_account || tx.creditAccount || '-';
    const auth = tx.authorized_by || tx.authorizedBy || '-';
    const memo = tx.memo || '-';

    tr.innerHTML = `
        <td style="font-size: 11px;">${ts}</td>
        <td><span class="badge badge-emerald">${cat}</span></td>
        <td><code>${debit}</code></td>
        <td><code>${credit}</code></td>
        <td><strong>$${amt.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
        <td style="font-size: 11px;"><code>${auth}</code></td>
        <td class="truncate" style="max-width: 220px;">${memo}</td>
    `;
    if (tbody.firstChild) tbody.insertBefore(tr, tbody.firstChild);
    else tbody.appendChild(tr);
}

function prependTreasurySweepRow(sweep) {
    if (!sweep || !NyxState.treasury.isOpen) return;
    const tbody = document.getElementById('treasury-sweeps-rows');
    if (!tbody) return;

    const tr = document.createElement('tr');
    tr.style.animation = 'flash-in 0.8s ease';
    const uuid = (sweep.sweepUuid || sweep.sweep_uuid || '-').substring(0, 18);
    const before = Number(sweep.collected || 0);
    const swept = Number(sweep.totalSwept || 0);
    const count = sweep.splits ? sweep.splits.length : 0;
    const state = sweep.fiscalState || 'SOLVENT';

    tr.innerHTML = `
        <td><code>${uuid}...</code></td>
        <td style="font-size: 11px;">ÉPP MOST</td>
        <td><strong>$${before.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
        <td><strong>$${swept.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
        <td>$0.00</td>
        <td>${count} számla</td>
        <td><span class="badge badge-emerald">${state}</span></td>
    `;
    if (tbody.firstChild) tbody.insertBefore(tr, tbody.firstChild);
    else tbody.appendChild(tr);
}

function closeTreasuryDashboard() {
    NyxState.treasury.isOpen = false;
    const overlay = document.getElementById('treasury-overlay');
    if (overlay) overlay.classList.add('hidden');
    postNui('closeTreasury', {});
}

// 10. Mobile Data Terminal CAD & Warrants (`nyx_mdt`)
function openMdt(data) {
    NyxState.mdt.isOpen = true;
    NyxState.mdt.calls = data.calls || [];

    const overlay = document.getElementById('mdt-overlay');
    if (overlay) overlay.classList.remove('hidden');

    renderMdtCalls(data.calls || []);
}

function closeMdt() {
    NyxState.mdt.isOpen = false;
    const overlay = document.getElementById('mdt-overlay');
    if (overlay) overlay.classList.add('hidden');
    postNui('closeMdt', {});
}

function renderMdtCalls(calls) {
    const list = document.getElementById('mdt-dispatch-list');
    if (!list) return;
    list.innerHTML = '';

    if (calls.length === 0) {
        list.innerHTML = '<div class="empty-state" style="padding: 30px; text-align: center; color: var(--text-dim);">Nincs aktív 911 vészhívás a rendszerben.</div>';
        return;
    }

    calls.forEach(call => {
        const item = document.createElement('div');
        item.className = 'dispatch-item';
        item.innerHTML = `
            <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
                <strong style="color: var(--accent-cyan);" class="truncate">#${call.id} - ${call.title}</strong>
                <span style="font-size: 10px; color: var(--text-dim);">${call.time || 'NOW'}</span>
            </div>
            <div style="font-size: 11px; color: var(--text-secondary);" class="truncate">${call.location || 'Unknown Location'}</div>
        `;
        item.addEventListener('click', () => {
            document.querySelectorAll('.dispatch-item').forEach(i => i.classList.remove('active'));
            item.classList.add('active');
            showCallDetails(call);
        });
        list.appendChild(item);
    });
}

function showCallDetails(call) {
    const panel = document.getElementById('mdt-dispatch-details');
    if (!panel) return;

    panel.innerHTML = `
        <h4 style="font-family: var(--font-display); margin-bottom: 8px; color: var(--text-main);">${call.title}</h4>
        <div style="font-size: 12px; line-height: 1.5; color: var(--text-secondary); margin-bottom: 12px;">
            ${call.description || 'Nincs további megjegyzés.'}
        </div>
        <div style="font-family: var(--font-mono); font-size: 11px; margin-bottom: 14px; color: var(--text-muted);">
            <div>Helyszín: ${call.location}</div>
            <div>Bejelentő: ${call.caller || 'Anonymus'}</div>
        </div>
        <button class="btn btn-primary" id="mdt-respond-btn" style="width: 100%;"><i class="fa-solid fa-location-arrow"></i> GPS Útvonal Beállítása</button>
    `;

    const respondBtn = document.getElementById('mdt-respond-btn');
    if (respondBtn) {
        respondBtn.addEventListener('click', () => {
            lockButtonAction(respondBtn, () => postNui('mdt:respondCall', { callId: call.id }));
        });
    }
}

// 11. Freight Hauling Board Renderer
function renderFreightContracts(contracts, activeContract) {
    const list = document.getElementById('freight-contracts-list');
    const activeBanner = document.getElementById('freight-active-banner');
    const activeDetails = document.getElementById('freight-active-details');

    if (activeContract && activeBanner && activeDetails) {
        activeBanner.classList.remove('hidden');
        activeDetails.innerHTML = `
            <strong>${activeContract.title}</strong><br>
            Célállomás: <code>${activeContract.destInv || 'Store Shelf'}</code> | Mennyiség: <strong>${activeContract.quantity}x</strong><br>
            Fuvardíj jóváírás: <strong style="color: var(--accent-emerald);">+$${activeContract.totalPayout.toFixed(2)}</strong> | Zárolt Letét: <strong style="color: var(--accent-amber);">$${activeContract.escrowDeposit.toFixed(2)}</strong>
        `;
    } else if (activeBanner) {
        activeBanner.classList.add('hidden');
    }

    if (list) {
        list.innerHTML = '';
        if (!contracts || contracts.length === 0) {
            list.innerHTML = '<div class="empty-state" style="padding: 30px; text-align: center; color: var(--text-dim);">Jelenleg nincs aktív hiánymegbízás a tőzsdén.</div>';
            return;
        }

        contracts.forEach(c => {
            if (c.status !== 'available') return;
            const item = document.createElement('div');
            item.className = 'freight-item';
            item.innerHTML = `
                <div>
                    <div style="font-weight: 600; font-size: 13px; color: var(--text-main);">${c.title}</div>
                    <div style="font-size: 11px; color: var(--text-secondary);">Rakomány: ${c.quantity}x ${c.itemId} | Határidő: ${Math.round((c.deadlineSeconds || 1800) / 60)} perc</div>
                </div>
                <div style="display: flex; align-items: center; gap: 14px;">
                    <div style="text-align: right;">
                        <div style="color: var(--accent-emerald); font-weight: 700;">+$${c.totalPayout.toFixed(2)}</div>
                        <div style="font-size: 10px; color: var(--accent-amber);">Kaució: $${c.escrowDeposit.toFixed(2)}</div>
                    </div>
                    <button class="btn btn-primary freight-claim-btn" data-id="${c.contractId}"><i class="fa-solid fa-file-signature"></i> Elvállal</button>
                </div>
            `;
            const claimBtn = item.querySelector('.freight-claim-btn');
            claimBtn.addEventListener('click', () => {
                lockButtonAction(claimBtn, () => postNui('claimFreightContract', { contractId: c.contractId }));
            });
            list.appendChild(item);
        });
    }
}

// 12. Confirmation Dialog Helper
function openDialog({ title, message, hasInput, inputValue, onConfirm, onCancel }) {
    NyxState.activeDialog = { onConfirm, onCancel };
    const overlay = document.getElementById('dialog-overlay');
    if (!overlay) return;

    document.getElementById('dialog-title').textContent = title || 'Confirmation';
    document.getElementById('dialog-message').textContent = message || '';

    const inputCont = document.getElementById('dialog-input-container');
    const inputEl = document.getElementById('dialog-input');
    if (inputCont && inputEl) {
        inputCont.classList.toggle('hidden', !hasInput);
        inputEl.value = inputValue || '';
        if (hasInput) {
            setTimeout(() => inputEl.focus(), 50);
        }
    }

    overlay.classList.remove('hidden');
}

function closeDialog(confirmed = false) {
    const overlay = document.getElementById('dialog-overlay');
    if (overlay) overlay.classList.add('hidden');

    if (NyxState.activeDialog) {
        const inputVal = document.getElementById('dialog-input')?.value;
        if (confirmed && NyxState.activeDialog.onConfirm) {
            NyxState.activeDialog.onConfirm(inputVal);
        } else if (!confirmed && NyxState.activeDialog.onCancel) {
            NyxState.activeDialog.onCancel();
        }
        NyxState.activeDialog = null;
    }
}

// 12B. Corporate Multi-Sig, RBAC & Union Management Subsystem (`nyx_factions`)
function openFactionDashboard(payload = {}) {
    NyxState.faction.isOpen = true;
    if (isBrowserDev && (!payload.overview && !payload.faction)) {
        const mock = handleDevMockNui('faction:getOverview', {});
        payload = { overview: mock.overview, factions: [{ factionId: 'corp_los_santos_logistics', legalName: 'Los Santos Freight & Logistics Corp.', charterType: 'corporation' }] };
    }
    NyxState.faction.data = payload.overview || payload;
    NyxState.faction.factionsList = payload.factions || [];
    NyxState.faction.currentFactionId = (payload.overview && payload.overview.faction && payload.overview.faction.faction_id)
        || (payload.factions && payload.factions[0] && payload.factions[0].factionId)
        || null;

    const overlay = document.getElementById('faction-overlay');
    if (overlay) overlay.classList.remove('hidden');

    // Organization selector dropdown
    const selectEl = document.getElementById('faction-select');
    if (selectEl) {
        if (NyxState.faction.factionsList && NyxState.faction.factionsList.length > 1) {
            selectEl.innerHTML = '';
            NyxState.faction.factionsList.forEach(f => {
                const opt = document.createElement('option');
                opt.value = f.factionId;
                opt.textContent = `${f.legalName} (${f.charterType || 'corp'})`;
                if (f.factionId === NyxState.faction.currentFactionId) opt.selected = true;
                selectEl.appendChild(opt);
            });
            selectEl.classList.remove('hidden');
            selectEl.onchange = () => {
                const targetId = selectEl.value;
                if (targetId && targetId !== NyxState.faction.currentFactionId) {
                    NyxState.faction.currentFactionId = targetId;
                    refreshFactionOverview(targetId);
                }
            };
        } else {
            selectEl.classList.add('hidden');
        }
    }

    setFactionTab(payload.activeTab || 'overview');
    renderFactionState(NyxState.faction.data);
}

function closeFactionDashboard() {
    NyxState.faction.isOpen = false;
    const overlay = document.getElementById('faction-overlay');
    if (overlay) overlay.classList.add('hidden');
    document.getElementById('faction-submodal-member')?.classList.add('hidden');
    document.getElementById('faction-submodal-withdraw')?.classList.add('hidden');
    postNui('closeFactionDashboard', {});
}

function setFactionTab(tabName) {
    NyxState.faction.activeTab = tabName;
    document.querySelectorAll('.faction-tab').forEach(t => {
        t.classList.toggle('active', t.dataset.tab === tabName);
    });
    document.querySelectorAll('.faction-tab-pane').forEach(p => {
        p.classList.toggle('hidden', p.id !== `faction-tab-${tabName}`);
    });
}

async function refreshFactionOverview(factionId = null) {
    const fid = factionId || NyxState.faction.currentFactionId;
    const res = await postNui('faction:getOverview', { factionId: fid });
    if (res && res.success && res.overview) {
        NyxState.faction.data = res.overview;
        renderFactionState(res.overview);
    }
}

function renderFactionState(overview) {
    if (!overview) return;
    const faction = overview.faction || {};

    // Header updates
    const titleEl = document.getElementById('faction-legal-name');
    if (titleEl) titleEl.textContent = faction.legal_name || 'Vállalati Vezérlőpult';

    const badgeEl = document.getElementById('faction-charter-badge');
    if (badgeEl) badgeEl.textContent = (faction.charter_type || 'CORPORATION').toUpperCase();

    const headerTreasury = document.getElementById('faction-header-treasury');
    if (headerTreasury) headerTreasury.textContent = `$${(overview.treasuryBalance || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

    // Tab 1: Overview KPIs
    const kpiBal = document.getElementById('faction-kpi-balance');
    if (kpiBal) kpiBal.textContent = `$${(overview.treasuryBalance || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

    const kpiAcct = document.getElementById('faction-kpi-account');
    if (kpiAcct) kpiAcct.textContent = `Számlaszám: ${faction.treasury_account_id || '-'}`;

    const members = overview.members || [];
    let totalEquity = 0.0;
    members.forEach(m => totalEquity += (m.equityShares || 0.0));

    const kpiEq = document.getElementById('faction-kpi-equity');
    if (kpiEq) kpiEq.textContent = `${totalEquity.toFixed(2)}% / 100.00%`;

    const fillEq = document.getElementById('faction-equity-fill');
    if (fillEq) fillEq.style.width = `${Math.min(100, Math.max(0, totalEquity))}%`;

    const kpiMbr = document.getElementById('faction-kpi-members');
    if (kpiMbr) kpiMbr.textContent = `${members.length} fő`;

    const kpiInact = document.getElementById('faction-kpi-inactivity');
    if (kpiInact) kpiInact.textContent = `Státusz: ${(faction.inactivity_status || 'AKTÍV').toUpperCase()}`;

    const kpiFleet = document.getElementById('faction-kpi-fleet');
    if (kpiFleet) kpiFleet.textContent = `${overview.fleetCount || 0} db`;

    // Render Sub-components
    renderFactionRBAC(members);
    renderFactionMultiSig(overview.pendingMultiSig || [], overview.timelockedMultiSig || [], overview.vaults || [], overview.signoffRules || []);
    renderFactionUnions(overview.unions || [], overview.cba, overview.userUnion);
    renderFactionAudit(overview.rbacAudit || []);
}

function renderFactionRBAC(members) {
    const tbody = document.getElementById('faction-roster-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (!members || members.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-muted); padding: 20px;">Nincs regisztrált munkavállaló a vállalati névjegyzékben.</td></tr>';
        return;
    }

    members.forEach(member => {
        const tr = document.createElement('tr');
        const nodes = member.permissionNodes || [];
        const badgesHtml = nodes.map(node => {
            let cat = 'general';
            if (node === '*') cat = 'root';
            else if (node.startsWith('treasury')) cat = 'treasury';
            else if (node.startsWith('roster')) cat = 'roster';
            else if (node.startsWith('fleet')) cat = 'fleet';
            else if (node.startsWith('cba')) cat = 'cba';
            return `<span class="node-badge ${cat}">${node}</span>`;
        }).join('');

        tr.innerHTML = `
            <td><code>${member.citizenId}</code></td>
            <td><strong>${member.roleTitle || 'Associate'}</strong></td>
            <td>$${(member.wageHourly || 0).toFixed(2)}/h</td>
            <td><strong style="color: var(--accent-cyan);">${(member.equityShares || 0).toFixed(2)}%</strong></td>
            <td><div class="node-pill-stack">${badgesHtml || '<span class="node-badge">none</span>'}</div></td>
            <td>
                <div style="display: flex; gap: 6px;">
                    <button class="btn btn-secondary btn-sm rbac-edit-btn" data-citid="${member.citizenId}"><i class="fa-solid fa-pen"></i></button>
                    <button class="btn btn-danger btn-sm rbac-del-btn" data-citid="${member.citizenId}"><i class="fa-solid fa-user-xmark"></i></button>
                </div>
            </td>
        `;

        tr.querySelector('.rbac-edit-btn')?.addEventListener('click', () => openMemberModal(member));
        tr.querySelector('.rbac-del-btn')?.addEventListener('click', () => {
            openDialog({
                title: 'Munkaviszony Megszüntetése',
                message: `Biztosan elbocsátod a(z) ${member.citizenId} azonosítójú munkatársat?`,
                onConfirm: async () => {
                    const res = await postNui('faction:removeMember', {
                        factionId: NyxState.faction.currentFactionId,
                        targetCitizenId: member.citizenId
                    });
                    if (res && res.success) {
                        showNotification({ type: 'warning', title: 'ELBOCSÁTVA', message: `${member.citizenId} munkaviszonya megszűnt.` });
                        refreshFactionOverview();
                    } else {
                        showNotification({ type: 'error', title: 'HIBA', message: res?.error || 'Művelet sikertelen.' });
                    }
                }
            });
        });

        tbody.appendChild(tr);
    });
}

function openMemberModal(member = null) {
    const modal = document.getElementById('faction-submodal-member');
    if (!modal) return;
    NyxState.faction.selectedMemberCitId = member ? member.citizenId : null;

    const titleEl = document.getElementById('faction-member-modal-title');
    if (titleEl) {
        titleEl.innerHTML = member ? `<i class="fa-solid fa-user-gear"></i> Munkatárs Módosítása: ${member.citizenId}` : `<i class="fa-solid fa-user-plus"></i> Új Munkatárs Hozzáadása`;
    }

    const citInput = document.getElementById('faction-input-member-citid');
    if (citInput) {
        citInput.value = member ? member.citizenId : '';
        citInput.disabled = !!member;
    }

    const roleInput = document.getElementById('faction-input-member-role');
    if (roleInput) roleInput.value = member ? member.roleTitle : 'Associate';

    const wageInput = document.getElementById('faction-input-member-wage');
    if (wageInput) wageInput.value = member ? (member.wageHourly || 0) : 35.00;

    const eqInput = document.getElementById('faction-input-member-equity');
    if (eqInput) eqInput.value = member ? (member.equityShares || 0) : 0.00;

    const currentNodes = member ? (member.permissionNodes || []) : ['treasury:view_ledger', 'inventory:view'];
    document.querySelectorAll('#faction-submodal-member input[type="checkbox"]').forEach(cb => {
        cb.checked = currentNodes.includes(cb.value);
    });

    modal.classList.remove('hidden');
}

function renderFactionMultiSig(pendingQueue, timelockedQueue, vaults, signoffRules) {
    // 1. Pending Queue
    const pendingList = document.getElementById('faction-multisig-pending-list');
    if (pendingList) {
        pendingList.innerHTML = '';
        if (!pendingQueue || pendingQueue.length === 0) {
            pendingList.innerHTML = '<div class="empty-state" style="padding: 20px; text-align: center; color: var(--text-dim); grid-column: 1 / -1;">Jelenleg nincs jóváhagyásra váró multi-sig kifizetési kérelem.</div>';
        } else {
            pendingQueue.forEach(req => {
                const reqId = req.request_id || req.requestId;
                const amt = Number(req.amount || 0);
                const currentSigs = Number(req.current_signatures || req.currentSignatures || 0);
                const reqSigs = Number(req.required_signatures || req.requiredSignatures || 2);
                const card = document.createElement('div');
                card.className = 'multisig-card';
                card.innerHTML = `
                    <div class="multisig-card-header">
                        <span class="badge warning">PENDING ESCROW</span>
                        <span class="multisig-amount">$${amt.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
                    </div>
                    <div>
                        <div style="font-size: 13px; font-weight: 600; color: var(--text-main);">${req.reason || 'Kifizetési kérelem'}</div>
                        <div style="font-size: 11px; color: var(--text-muted); margin-top: 2px;">Cél: <code>${req.target_account || req.targetAccount}</code> | Széf: <code>${req.vault_id || req.vaultId || 'Master'}</code></div>
                    </div>
                    <div style="background: rgba(0,0,0,0.3); border-radius: 6px; padding: 8px;">
                        <div style="display: flex; justify-content: space-between; font-size: 11px; margin-bottom: 4px;">
                            <span>Aláírások: <strong>${currentSigs} / ${reqSigs}</strong></span>
                            <span style="color: var(--accent-amber);">${Math.round((currentSigs / reqSigs) * 100)}%</span>
                        </div>
                        <div class="progress-bar"><div class="fill" style="width: ${(currentSigs / reqSigs) * 100}%;"></div></div>
                    </div>
                    <div style="display: flex; gap: 8px; margin-top: 6px;">
                        <button class="btn btn-success btn-sm msig-sign-btn" style="flex: 1;"><i class="fa-solid fa-signature"></i> Aláírás</button>
                        <button class="btn btn-danger btn-sm msig-reject-btn"><i class="fa-solid fa-ban"></i></button>
                        <button class="btn btn-secondary btn-sm msig-cancel-btn"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                `;

                const signBtn = card.querySelector('.msig-sign-btn');
                signBtn?.addEventListener('click', () => {
                    lockButtonAction(signBtn, async () => {
                        const res = await postNui('faction:signMultiSig', { requestId: reqId });
                        if (res && res.success) {
                            showNotification({ type: 'success', title: 'ALÁÍRVA', message: `Kérelem #${reqId} sikeresen hitelesítve!` });
                            refreshFactionOverview();
                        } else {
                            showNotification({ type: 'error', title: 'ALÁÍRÁS MEGTAGADVA', message: res?.error || 'Jogosultság hiányzik.' });
                        }
                    });
                });

                const rejectBtn = card.querySelector('.msig-reject-btn');
                rejectBtn?.addEventListener('click', () => {
                    lockButtonAction(rejectBtn, async () => {
                        const res = await postNui('faction:rejectMultiSig', { requestId: reqId, reason: 'Elutasítva az elnökség által.' });
                        if (res && res.success) {
                            showNotification({ type: 'warning', title: 'ELUTASÍTVA', message: `Kérelem #${reqId} elutasításra került.` });
                            refreshFactionOverview();
                        }
                    });
                });

                const cancelBtn = card.querySelector('.msig-cancel-btn');
                cancelBtn?.addEventListener('click', () => {
                    lockButtonAction(cancelBtn, async () => {
                        const res = await postNui('faction:cancelMultiSig', { requestId: reqId, reason: 'Visszavonva.' });
                        if (res && res.success) {
                            showNotification({ type: 'info', title: 'TÖRÖLVE', message: `Kérelem #${reqId} visszavonva.` });
                            refreshFactionOverview();
                        }
                    });
                });

                pendingList.appendChild(card);
            });
        }
    }

    // 2. Timelocked Queue
    const timelockedList = document.getElementById('faction-multisig-timelocked-list');
    if (timelockedList) {
        timelockedList.innerHTML = '';
        if (!timelockedQueue || timelockedQueue.length === 0) {
            timelockedList.innerHTML = '<div class="empty-state" style="padding: 20px; text-align: center; color: var(--text-dim); grid-column: 1 / -1;">Nincs időzár alatt álló letét.</div>';
        } else {
            timelockedQueue.forEach(item => {
                const reqId = item.request_id || item.requestId;
                const amt = Number(item.amount || 0);
                const card = document.createElement('div');
                card.className = 'multisig-card timelocked';
                card.innerHTML = `
                    <div class="multisig-card-header">
                        <span class="badge warning"><i class="fa-solid fa-lock"></i> TIMELOCKED</span>
                        <span class="multisig-amount" style="color: var(--accent-cyan);">$${amt.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
                    </div>
                    <div>
                        <div style="font-size: 13px; font-weight: 600; color: var(--text-main);">${item.reason || 'Zárolt tranzakció'}</div>
                        <div style="font-size: 11px; color: var(--text-muted); margin-top: 2px;">Cél: <code>${item.target_account || item.targetAccount}</code></div>
                    </div>
                    <div style="display: flex; justify-content: space-between; align-items: center; background: rgba(0,0,0,0.3); border-radius: 6px; padding: 8px 12px;">
                        <span style="font-size: 11px; color: var(--text-secondary);"><i class="fa-solid fa-hourglass-start"></i> Időzár lejárta:</span>
                        <strong style="font-family: var(--font-mono); font-size: 12px; color: var(--accent-amber);">${item.timelock_until || 'READY'}</strong>
                    </div>
                    <button class="btn btn-primary btn-sm msig-exec-btn" style="margin-top: 4px;"><i class="fa-solid fa-play"></i> Tranzakció Végrehajtása (Execute)</button>
                `;

                const execBtn = card.querySelector('.msig-exec-btn');
                execBtn?.addEventListener('click', () => {
                    lockButtonAction(execBtn, async () => {
                        const res = await postNui('faction:executeTimelocked', { requestId: reqId });
                        if (res && res.success) {
                            showNotification({ type: 'success', title: 'LETÉT TELJESÍTVE', message: `Átutalás #${reqId} elszámolva a kincstári főkönyvben!` });
                            refreshFactionOverview();
                        } else {
                            showNotification({ type: 'error', title: 'VÉGREHAJTÁS SIKERTELEN', message: res?.error || 'Időzár még nem járt le.' });
                        }
                    });
                });

                timelockedList.appendChild(card);
            });
        }
    }

    // 3. Vaults & Signoff Rules
    const vaultsList = document.getElementById('faction-vaults-list');
    if (vaultsList) {
        vaultsList.innerHTML = '';
        (vaults || []).forEach(v => {
            const card = document.createElement('div');
            card.className = 'mini-card';
            card.innerHTML = `
                <div>
                    <div style="font-weight: 600; font-size: 12px; color: var(--text-main);">${v.vault_label || v.vaultLabel}</div>
                    <div style="font-size: 10px; color: var(--text-muted);">Számla: <code>${v.account_id || v.accountId}</code></div>
                </div>
                <div style="text-align: right;">
                    <div style="font-family: var(--font-mono); font-size: 12px; color: var(--accent-emerald);">Limit: $${Number(v.daily_limit || v.dailyLimit || 0).toLocaleString()}</div>
                    <span class="badge ${v.is_frozen || v.isFrozen ? 'danger' : 'online'}">${v.is_frozen || v.isFrozen ? 'BEFAGYASZTVA' : 'AKTÍV'}</span>
                </div>
            `;
            vaultsList.appendChild(card);
        });
    }

    const rulesList = document.getElementById('faction-signoff-rules-list');
    if (rulesList) {
        rulesList.innerHTML = '';
        (signoffRules || []).forEach(r => {
            const card = document.createElement('div');
            card.className = 'mini-card';
            const maxLabel = r.maxAmount ? `$${Number(r.maxAmount).toLocaleString()}` : 'Korlátlan';
            card.innerHTML = `
                <div>
                    <div style="font-weight: 600; font-size: 12px; color: var(--text-main);">${r.ruleName || r.rule_name}</div>
                    <div style="font-size: 10px; color: var(--text-muted);">$${Number(r.minAmount || r.min_amount || 0).toLocaleString()} - ${maxLabel}</div>
                </div>
                <div style="text-align: right;">
                    <strong style="color: var(--accent-amber); font-size: 12px;">${r.requiredSignatures || r.required_signatures} Aláíró</strong>
                    <div style="font-size: 10px; color: var(--text-muted);">${r.timelockSeconds || r.timelock_seconds || 0}s Időzár</div>
                </div>
            `;
            rulesList.appendChild(card);
        });
    }

    // Populate Vault select in withdrawal modal
    const vaultSelect = document.getElementById('faction-withdraw-vault');
    if (vaultSelect && vaults) {
        vaultSelect.innerHTML = '';
        vaults.forEach(v => {
            const opt = document.createElement('option');
            opt.value = v.vault_id || v.vaultId;
            opt.textContent = `${v.vault_label || v.vaultLabel} (${v.account_id || v.accountId})`;
            vaultSelect.appendChild(opt);
        });
    }
}

function renderFactionUnions(unions, activeCBA) {
    // 1. Active CBA Card
    const cbaCard = document.getElementById('faction-active-cba-card');
    if (cbaCard) {
        if (!activeCBA || (!activeCBA.cba_id && !activeCBA.cbaId)) {
            cbaCard.innerHTML = `
                <div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 16px;">
                    <i class="fa-solid fa-circle-info" style="font-size: 20px; color: var(--accent-cyan); display: block; margin-bottom: 8px;"></i>
                    Jelenleg nincs érvényben lévő Kollektív Szerződés (CBA).<br>
                    Használd a jobb oldali szerződéstervezőt új megállapodás benyújtásához.
                </div>
            `;
        } else {
            const cbaId = activeCBA.cba_id || activeCBA.cbaId;
            const status = activeCBA.status || 'proposed';
            const wage = Number(activeCBA.wage_floor || activeCBA.wageFloor || 0).toFixed(2);
            const ot = Number(activeCBA.overtime_multiplier || activeCBA.overtimeMultiplier || 1.5).toFixed(2);
            const hazard = Number(activeCBA.hazard_pay_bonus || activeCBA.hazardBonus || 0).toFixed(2);

            let statusBadge = '<span class="badge online">RATIFIKÁLT CBA</span>';
            if (status === 'proposed') statusBadge = '<span class="badge warning">JAVASLAT ALATT</span>';
            else if (status === 'breached') statusBadge = '<span class="badge danger">MEGSZEGVE</span>';

            cbaCard.innerHTML = `
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <h5 style="font-family: var(--font-display); font-size: 15px; color: var(--text-main); margin: 0;">${activeCBA.cba_title || activeCBA.title || 'Kollektív Szerződés'}</h5>
                    ${statusBadge}
                </div>
                <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-top: 10px; background: rgba(0,0,0,0.25); border-radius: 8px; padding: 10px;">
                    <div>
                        <span style="font-size: 10px; color: var(--text-muted); display: block;">GARANTÁLT BÉRALAP</span>
                        <strong style="color: var(--accent-emerald); font-family: var(--font-mono); font-size: 14px;">$${wage}/h</strong>
                    </div>
                    <div>
                        <span style="font-size: 10px; color: var(--text-muted); display: block;">TÚLÓRA SZORZÓ</span>
                        <strong style="color: var(--accent-cyan); font-family: var(--font-mono); font-size: 14px;">${ot}x</strong>
                    </div>
                    <div>
                        <span style="font-size: 10px; color: var(--text-muted); display: block;">VESZÉLYESSÉGI PÓTLÉK</span>
                        <strong style="color: var(--accent-amber); font-family: var(--font-mono); font-size: 14px;">+$${hazard}/h</strong>
                    </div>
                </div>
                ${status === 'proposed' ? `
                    <button class="btn btn-success btn-block cba-ratify-btn" style="margin-top: 10px;"><i class="fa-solid fa-check-double"></i> Kollektív Szerződés Ratifizálása (Vállalati Jóváhagyás)</button>
                ` : ''}
            `;

            cbaCard.querySelector('.cba-ratify-btn')?.addEventListener('click', (e) => {
                const btn = e.currentTarget;
                lockButtonAction(btn, async () => {
                    const res = await postNui('faction:ratifyCBA', { cbaId: cbaId });
                    if (res && res.success) {
                        showNotification({ type: 'success', title: 'CBA RATIFIKÁLVA', message: 'A kollektív szerződés jogerőre emelkedett!' });
                        refreshFactionOverview();
                    } else {
                        showNotification({ type: 'error', title: 'SIKERTELEN RATIFIKÁCIÓ', message: res?.error || 'Csak cégvezető ratifikálhat.' });
                    }
                });
            });
        }
    }

    // 2. Unions Grid
    const unionsList = document.getElementById('faction-unions-list');
    const unionSelect = document.getElementById('cba-builder-union');
    if (unionSelect) unionSelect.innerHTML = '';

    if (unionsList) {
        unionsList.innerHTML = '';
        (unions || []).forEach(u => {
            const uid = u.union_id || u.unionId;
            const bal = Number(u.strike_fund_balance || u.strikeFundBalance || 0);
            const runway = u.runwayDays || 999;
            const card = document.createElement('div');
            card.className = 'union-card';
            card.innerHTML = `
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <strong style="color: var(--text-main); font-size: 13px;">${u.union_name || u.legal_name || uid}</strong>
                    <span class="badge info">${(u.sector || 'general').toUpperCase()}</span>
                </div>
                <div style="display: flex; justify-content: space-between; font-size: 11px; background: rgba(0,0,0,0.2); padding: 6px 10px; border-radius: 6px;">
                    <span style="color: var(--text-muted);">Sztrájkalap:</span>
                    <strong style="color: var(--accent-emerald); font-family: var(--font-mono);">$${bal.toLocaleString()}</strong>
                </div>
                <div style="display: flex; justify-content: space-between; font-size: 11px;">
                    <span style="color: var(--text-muted);">Tartalék Időtartam:</span>
                    <strong style="color: ${runway <= 5 ? 'var(--accent-red)' : 'var(--accent-cyan)'};">${runway} nap</strong>
                </div>
                <button class="btn btn-secondary btn-sm union-claim-btn" style="margin-top: 4px;"><i class="fa-solid fa-hand-holding-dollar"></i> Napi Sztrájksegély</button>
            `;

            const claimBtn = card.querySelector('.union-claim-btn');
            claimBtn?.addEventListener('click', () => {
                lockButtonAction(claimBtn, async () => {
                    const res = await postNui('faction:claimStrikeRelief', { unionId: uid });
                    if (res && res.success) {
                        showNotification({ type: 'success', title: 'SZTRÁJKSEGÉLY SIKERES', message: 'Napi segélyed jóváírásra került a bankszámládon!' });
                    } else {
                        showNotification({ type: 'error', title: 'KÖVETELÉS MEGTAGADVA', message: res?.error || 'Nem vagy jogosult vagy aktív a 24h cooldown.' });
                    }
                });
            });

            unionsList.appendChild(card);

            if (unionSelect) {
                const opt = document.createElement('option');
                opt.value = uid;
                opt.textContent = `${u.union_name || u.legal_name || uid} (${(u.sector || 'general').toUpperCase()})`;
                unionSelect.appendChild(opt);
            }
        });
    }
}

function renderFactionAudit(auditLogs) {
    const tbody = document.getElementById('faction-audit-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (!auditLogs || auditLogs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-muted); padding: 20px;">Nincs rögzített audit bejegyzés.</td></tr>';
        return;
    }

    auditLogs.forEach(entry => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td style="font-family: var(--font-mono); font-size: 11px;">${entry.createdAt || 'RECENT'}</td>
            <td><span class="badge info">${entry.actionType || 'UPDATE'}</span></td>
            <td><code>${entry.actorCitizenId || 'SYSTEM'}</code></td>
            <td><code>${entry.targetCitizenId || '-'}</code></td>
            <td style="font-size: 12px; color: var(--text-secondary);">${entry.notes || '-'}</td>
        `;
        tbody.appendChild(tr);
    });
}

// 12C. Courtroom Terminal & Forensic Explorer (nyx_judiciary)
function openCourtTerminal(payload = {}) {
    NyxState.court.isOpen = true;
    const overlay = document.getElementById('court-overlay');
    if (!overlay) return;

    overlay.classList.remove('hidden');

    if (payload.isJudge !== undefined) {
        NyxState.court.isJudge = !!payload.isJudge;
    }
    const roleBadge = document.getElementById('court-role-badge');
    if (roleBadge) {
        if (NyxState.court.isJudge) {
            roleBadge.textContent = 'ELNÖKLŐ BÍRÓ';
            roleBadge.className = 'badge badge-warning';
        } else {
            roleBadge.textContent = 'POLGÁR / ÜLNÖK';
            roleBadge.className = 'badge';
        }
    }

    const initialTab = payload.activeTab || 'evidence';
    setCourtTab(initialTab);

    refreshCourtOverview();
    refreshCourtEvidenceList();
}

function closeCourtTerminal() {
    NyxState.court.isOpen = false;
    const overlay = document.getElementById('court-overlay');
    if (overlay) overlay.classList.add('hidden');

    const subpDisclosure = document.getElementById('court-subpoena-disclosure');
    if (subpDisclosure) subpDisclosure.classList.add('hidden');

    postNui('closeCourtTerminal', {});
}

function setCourtTab(tabName) {
    NyxState.court.activeTab = tabName;

    document.querySelectorAll('.court-tab').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.tab === tabName);
    });

    document.querySelectorAll('.court-tab-pane').forEach(pane => {
        pane.classList.add('hidden');
    });

    const targetPane = document.getElementById(`court-tab-${tabName}`);
    if (targetPane) {
        targetPane.classList.remove('hidden');
    }

    if (tabName === 'evidence') {
        setTimeout(() => document.getElementById('court-evidence-search')?.focus(), 50);
    }
}

async function refreshCourtOverview() {
    const res = await postNui('court:getOverview', {});
    if (!res || !res.success || !res.overview) return;

    const data = res.overview;
    NyxState.court.isJudge = !!data.isJudge;

    // Header role badge update
    const roleBadge = document.getElementById('court-role-badge');
    if (roleBadge) {
        if (data.isJudge) {
            roleBadge.textContent = 'ELNÖKLŐ BÍRÓ';
            roleBadge.className = 'badge badge-warning';
        } else if (data.jurorRecord) {
            roleBadge.textContent = `ESKÜDT (SZÉK #${data.jurorRecord.seat_index || '?'})`;
            roleBadge.className = 'badge badge-success';
        } else if (data.isLawEnforcement) {
            roleBadge.textContent = 'RENDVÉDELEM (LEO)';
            roleBadge.className = 'badge badge-info';
        } else {
            roleBadge.textContent = 'POLGÁR';
            roleBadge.className = 'badge';
        }
    }

    // Active Docket & Case badge
    NyxState.court.dockets = data.dockets || [];
    const activeDocket = (NyxState.court.dockets.length > 0) ? NyxState.court.dockets[0] : null;
    NyxState.court.currentDocket = activeDocket;

    const caseBadge = document.getElementById('court-case-badge');
    if (caseBadge) {
        if (activeDocket) {
            caseBadge.textContent = activeDocket.case_number || activeDocket.caseNumber || `DOCKET #${activeDocket.docket_id || activeDocket.docketId}`;
            caseBadge.className = 'badge badge-outline';
        } else {
            caseBadge.textContent = 'NINCS AKTÍV TÁRGYALÁS';
            caseBadge.className = 'badge badge-outline';
        }
    }

    // Render Jury Tab
    renderJuryDashboard(data.juryDetails, activeDocket, data.jurorRecord);

    // Render Warrants & Petitions
    NyxState.court.pendingPetitions = data.pendingPetitions || [];
    NyxState.court.activeWarrants = data.activeWarrants || [];
    renderWarrantsDashboard(NyxState.court.pendingPetitions, NyxState.court.activeWarrants);
}

async function refreshCourtEvidenceList() {
    const search = document.getElementById('court-evidence-search')?.value?.trim() || '';
    const typeFilter = document.getElementById('court-evidence-type-filter')?.value || 'all';
    const sealedOnly = !!document.getElementById('court-evidence-sealed-check')?.checked;

    const res = await postNui('court:getEvidenceList', {
        search: search || undefined,
        type: typeFilter !== 'all' ? typeFilter : undefined,
        isSealedOnly: sealedOnly,
        limit: 50,
        offset: 0
    });

    if (res && res.success && Array.isArray(res.evidence)) {
        NyxState.court.evidenceList = res.evidence;
        renderCourtEvidenceList(res.evidence);
    }
}

function renderCourtEvidenceList(items) {
    const tbody = document.getElementById('court-evidence-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (!items || items.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-muted); padding: 24px;">Nem található a szűrésnek megfelelő bűnjel.</td></tr>';
        return;
    }

    items.forEach(item => {
        const tr = document.createElement('tr');
        tr.className = 'evidence-row-item';
        tr.dataset.evidenceId = item.evidence_id;
        if (NyxState.court.selectedEvidenceId === item.evidence_id) {
            tr.classList.add('selected');
        }

        const typeLabel = (item.type || item.evidence_type || 'unknown').toUpperCase();
        let statusBadge = '<span class="badge badge-outline">AKTÍV</span>';
        if (item.is_contaminated == 1) {
            statusBadge = '<span class="badge badge-danger">SZENNYEZETT</span>';
        } else if (item.is_sealed == 1) {
            statusBadge = '<span class="badge badge-success">LEPECSETELVE</span>';
        }

        const chainLen = item.chain_length || item.block_count || 1;

        tr.innerHTML = `
            <td style="font-family: var(--font-mono); font-weight: 600; color: var(--accent-amber);">${item.evidence_id}</td>
            <td><span class="badge">${typeLabel}</span></td>
            <td><span class="badge info">${chainLen} blokk</span></td>
            <td>${statusBadge}</td>
            <td><code>${item.current_custodian_id || '-'}</code></td>
        `;

        tr.addEventListener('click', () => {
            document.querySelectorAll('#court-evidence-rows tr').forEach(r => r.classList.remove('selected'));
            tr.classList.add('selected');
            selectEvidenceItem(item.evidence_id);
        });

        tbody.appendChild(tr);
    });
}

async function selectEvidenceItem(evidenceId) {
    NyxState.court.selectedEvidenceId = evidenceId;
    const res = await postNui('court:getEvidenceChain', { evidenceId: evidenceId });
    if (!res || !res.success || !res.evidence) return;

    const evidence = res.evidence;
    const chain = res.chain || [];
    NyxState.court.chainBlocks = chain;

    // Unhide detail card, hide empty hint
    const emptyHint = document.getElementById('court-evidence-empty-hint');
    const detailCard = document.getElementById('court-evidence-detail-card');
    if (emptyHint) emptyHint.classList.add('hidden');
    if (detailCard) detailCard.classList.remove('hidden');

    // Header info
    const idEl = document.getElementById('court-detail-id');
    if (idEl) idEl.textContent = evidence.evidence_id;

    const typeBadge = document.getElementById('court-detail-type-badge');
    if (typeBadge) typeBadge.textContent = (evidence.type || evidence.evidence_type || 'UNKNOWN').toUpperCase();

    const sealedBadge = document.getElementById('court-detail-sealed-badge');
    if (sealedBadge) sealedBadge.classList.toggle('hidden', evidence.is_sealed != 1);

    const contamBadge = document.getElementById('court-detail-contam-badge');
    if (contamBadge) contamBadge.classList.toggle('hidden', evidence.is_contaminated != 1);

    const createdEl = document.getElementById('court-detail-created');
    if (createdEl) {
        createdEl.textContent = `Rögzítve: ${evidence.created_at || 'ISMERETLEN'} | Gyűjtő: ${evidence.collector_citizen_id || '-'}`;
    }

    // Hashes
    const rootHashEl = document.getElementById('court-detail-root-hash');
    if (rootHashEl) rootHashEl.textContent = evidence.evidence_hash || evidence.origin_hash || '--';

    const headHashEl = document.getElementById('court-detail-head-hash');
    if (headHashEl) headHashEl.textContent = evidence.current_chain_hash || evidence.current_head_hash || '--';

    // Metadata pills
    const custodianEl = document.getElementById('court-detail-custodian');
    if (custodianEl) custodianEl.textContent = evidence.current_custodian_id || '-';

    const facilityEl = document.getElementById('court-detail-facility');
    if (facilityEl) facilityEl.textContent = evidence.current_facility || '-';

    const docketEl = document.getElementById('court-detail-docket');
    if (docketEl) docketEl.textContent = evidence.docket_id ? `#${evidence.docket_id}` : 'Nincs Iktatva';

    const exhibitEl = document.getElementById('court-detail-exhibit');
    if (exhibitEl) exhibitEl.textContent = evidence.exhibit_label || 'Nem Bírósági Tárgy';

    // Reset verification result banner
    const verifBanner = document.getElementById('court-verification-result');
    if (verifBanner) {
        verifBanner.className = 'verification-banner hidden';
        verifBanner.innerHTML = '';
    }

    // Render timeline
    renderEvidenceChainTimeline(chain);
}

function renderEvidenceChainTimeline(blocks) {
    const container = document.getElementById('court-evidence-chain-timeline');
    if (!container) return;
    container.innerHTML = '';

    if (!blocks || blocks.length === 0) {
        container.innerHTML = '<div class="empty-state" style="padding: 16px;"><p>Nincsenek elérhető birtoklási blokkok.</p></div>';
        return;
    }

    blocks.forEach((b, index) => {
        const item = document.createElement('div');
        item.className = 'timeline-block-card';

        const actionType = b.action_type || 'TRANSFER';
        let actionBadgeClass = 'info';
        if (actionType === 'COLLECTED') actionBadgeClass = 'badge-success';
        else if (actionType === 'VAULT_STORED') actionBadgeClass = 'badge-warning';
        else if (actionType === 'COURT_PRESENTED') actionBadgeClass = 'badge-primary';

        item.innerHTML = `
            <div class="block-header-row">
                <div class="block-title-info">
                    <span class="block-index">#${b.sequence_index ?? index}</span>
                    <span class="badge ${actionBadgeClass}">${actionType}</span>
                    <span class="block-time">${b.timestamp || ''}</span>
                </div>
                <span class="block-actor">Őrző: <code>${b.custodian_id || '-'}</code></span>
            </div>
            <div class="block-meta-row">
                <span class="block-facility"><i class="fa-solid fa-location-dot"></i> ${b.facility || 'Ismeretlen helyszín'}</span>
                <span class="block-notes">${b.notes || ''}</span>
            </div>
            <div class="block-hash-chain">
                <div class="hash-row"><span>PREV:</span> <code>${b.prev_hash || 'GENESIS'}</code></div>
                <div class="hash-row"><span>HASH:</span> <code class="head-code">${b.block_hash || '--'}</code></div>
            </div>
        `;
        container.appendChild(item);
    });
}

async function verifyCurrentEvidenceChain() {
    const evidenceId = NyxState.court.selectedEvidenceId;
    if (!evidenceId) {
        showNotification({ type: 'warning', title: 'NINCS KIVÁLASZTVA', message: 'Kérlek válassz ki egy bűnjelet a hitelesítéshez!' });
        return;
    }

    const verifyBtn = document.getElementById('court-verify-chain-btn');
    lockButtonAction(verifyBtn, async () => {
        const res = await postNui('court:verifyEvidenceChain', { evidenceId: evidenceId });
        const banner = document.getElementById('court-verification-result');
        if (!banner) return;

        banner.classList.remove('hidden');

        if (res && res.success && (res.status === 'VALID' || res.status === 'OK' || res.verified)) {
            const data = res.data || res;
            const blockCount = data.blockCount || data.chainLength || NyxState.court.chainBlocks.length || 1;
            const headHash = data.currentChainHash || data.headHash || '';
            banner.className = 'verification-banner valid';
            banner.innerHTML = `
                <i class="fa-solid fa-circle-check icon-status"></i>
                <div class="banner-body">
                    <strong>KRIPTOGRÁFIAILAG HITELESÍTETT BŰNJEL (SÉRTETLEN)</strong>
                    <div class="sub-line">SHA-256 Merkle folytonosság ellenőrizve. ${blockCount} láncblokk és fejhash kriptográfiailag érvényes.</div>
                    <code class="hash-preview">HEAD: ${headHash}</code>
                </div>
            `;
            showNotification({ type: 'success', title: 'SHA-256 IGAZOLVA', message: `Bűnjel ${evidenceId} integritása sértetlen.` });
        } else {
            banner.className = 'verification-banner invalid';
            const reason = res?.status || res?.error || 'A hash integritási ellenőrzés meghiúsult.';
            banner.innerHTML = `
                <i class="fa-solid fa-triangle-exclamation icon-status"></i>
                <div class="banner-body">
                    <strong>INTEGRITÁSI HIBA / MÓDOSÍTOTT LÁNC</strong>
                    <div class="sub-line">A lánc folytonossága megszakadt vagy utólag módosításra került: ${reason}</div>
                </div>
            `;
            showNotification({ type: 'error', title: 'INTEGRITÁSI HIBA', message: reason });
        }
    });
}

function renderJuryDashboard(juryData, currentDocket, jurorRecord) {
    // 1. Docket overview banner
    const caseTypeEl = document.getElementById('court-jury-case-type');
    const docketTitleEl = document.getElementById('court-jury-docket-title');
    const partiesEl = document.getElementById('court-jury-parties');
    const statusEl = document.getElementById('court-jury-docket-status');

    if (currentDocket) {
        if (caseTypeEl) caseTypeEl.textContent = (currentDocket.case_type || currentDocket.caseType || 'BÜNTETŐPER').toUpperCase();
        if (docketTitleEl) docketTitleEl.textContent = `${currentDocket.case_number || currentDocket.caseNumber || ''}: ${currentDocket.title}`;
        if (partiesEl) partiesEl.textContent = `Felperes: ${currentDocket.plaintiff_name || currentDocket.plaintiffName || 'Állam'} | Vádlott: ${currentDocket.defendant_name || currentDocket.defendantName || '-'}`;
        if (statusEl) {
            const st = (currentDocket.status || 'SCHEDULED').toUpperCase();
            statusEl.textContent = st;
            if (st === 'DELIBERATION') statusEl.className = 'badge badge-warning';
            else if (st === 'IN_TRIAL') statusEl.className = 'badge badge-primary';
            else if (st === 'CONCLUDED') statusEl.className = 'badge badge-success';
            else statusEl.className = 'badge badge-outline';
        }
    } else {
        if (docketTitleEl) docketTitleEl.textContent = 'Nincs folyamatban lévő bírósági tárgyalás';
        if (partiesEl) partiesEl.textContent = 'A tárgyalóterem jelenleg szabad.';
        if (statusEl) {
            statusEl.textContent = 'SZABAD';
            statusEl.className = 'badge badge-outline';
        }
    }

    // 2. Seats and Quorum
    const seatsContainer = document.getElementById('court-juror-seats');
    const quorumBadge = document.getElementById('court-jury-quorum-badge');
    if (seatsContainer) seatsContainer.innerHTML = '';

    const jurors = (juryData && juryData.jurors) ? juryData.jurors : [];
    const activeCount = juryData?.activeCount ?? jurors.filter(j => (j.status === 'seated' || j.selection_status === 'seated')).length;
    const requiredQuorum = juryData?.requiredQuorum ?? 3;

    if (quorumBadge) {
        quorumBadge.textContent = `Kvórum: ${activeCount}/${requiredQuorum}`;
        quorumBadge.className = activeCount >= requiredQuorum ? 'badge badge-success' : 'badge badge-warning';
    }

    for (let seat = 1; seat <= 6; seat++) {
        const juror = jurors.find(j => (j.seat === seat || j.seat_index === seat));
        const seatCard = document.createElement('div');
        seatCard.className = 'juror-seat-card';

        if (juror && (juror.status === 'seated' || juror.selection_status === 'seated')) {
            seatCard.classList.add('seated');
            seatCard.innerHTML = `
                <div class="seat-top"><span class="seat-num">#${seat}</span><span class="badge badge-success">HELYÉN</span></div>
                <div class="seat-name truncate">${juror.name || juror.citizenId || juror.citizen_id}</div>
                <div class="seat-status">Bejelentkezve</div>
            `;
        } else if (juror && (juror.status === 'summoned' || juror.selection_status === 'summoned')) {
            seatCard.classList.add('summoned');
            seatCard.innerHTML = `
                <div class="seat-top"><span class="seat-num">#${seat}</span><span class="badge badge-warning">IDÉZVE</span></div>
                <div class="seat-name truncate">${juror.name || juror.citizenId || juror.citizen_id}</div>
                <div class="seat-status">Érkezésre vár...</div>
            `;
        } else {
            seatCard.classList.add('vacant');
            seatCard.innerHTML = `
                <div class="seat-top"><span class="seat-num">#${seat}</span><span class="badge badge-outline">ÜRES</span></div>
                <div class="seat-name">Szabad Szék</div>
                <div class="seat-status">-</div>
            `;
        }
        seatsContainer?.appendChild(seatCard);
    }

    // Check-in bar for summoned citizens
    const checkinBar = document.getElementById('court-juror-checkin-bar');
    if (checkinBar) {
        const isSummonedNotSeated = jurorRecord && (jurorRecord.selection_status === 'summoned');
        checkinBar.classList.toggle('hidden', !isSummonedNotSeated);
    }

    // 3. Secret Ballot Box
    const ballotBadge = document.getElementById('court-ballot-open-badge');
    const isDeliberation = (currentDocket?.status === 'deliberation');
    const ballotOpen = !!(isDeliberation && (juryData?.ballotOpen ?? true));

    if (ballotBadge) {
        if (ballotOpen) {
            ballotBadge.textContent = 'SZAVAZÁS NYITVA';
            ballotBadge.className = 'badge badge-success';
        } else {
            ballotBadge.textContent = 'SZAVAZÁS ZÁRVA';
            ballotBadge.className = 'badge badge-warning';
        }
    }

    const hasVoted = !!(jurorRecord?.secret_ballot || juryData?.hasVoted || NyxState.court.hasVoted);
    const voteStatusBanner = document.getElementById('court-vote-status-banner');
    const voteStatusText = document.getElementById('court-vote-status-text');

    const ballotBtns = [
        document.getElementById('court-vote-guilty-btn'),
        document.getElementById('court-vote-notguilty-btn'),
        document.getElementById('court-vote-abstain-btn')
    ];

    ballotBtns.forEach(btn => {
        if (btn) btn.disabled = !ballotOpen || hasVoted;
    });

    if (voteStatusBanner) {
        if (hasVoted) {
            voteStatusBanner.classList.remove('hidden');
            if (voteStatusText) voteStatusText.textContent = 'Titkos szavazatod biztonságosan rögzítve az urnában.';
        } else {
            voteStatusBanner.classList.add('hidden');
        }
    }

    // 4. Judge Controls
    const judgeControls = document.getElementById('court-judge-controls');
    if (judgeControls) {
        judgeControls.classList.toggle('hidden', !NyxState.court.isJudge);
    }
}

async function castJuryBallot(vote) {
    const docket = NyxState.court.currentDocket;
    if (!docket) {
        showNotification({ type: 'warning', title: 'NINCS ÜGY', message: 'Nincs aktív ügy a szavazáshoz.' });
        return;
    }

    const docketId = docket.docket_id || docket.docketId;
    const btn = document.querySelector(`.ballot-choice-btn[data-vote="${vote}"]`);

    lockButtonAction(btn, async () => {
        const res = await postNui('court:castJuryVote', {
            docketId: docketId,
            vote: vote
        });

        if (res && res.success) {
            NyxState.court.hasVoted = true;
            showNotification({ type: 'success', title: 'SZAVAZAT LEADVA', message: 'A titkos szavazatod az urnába került!' });
            refreshCourtOverview();
        } else {
            showNotification({ type: 'error', title: 'SZAVAZÁS SIKERTELEN', message: res?.error || 'Nem adható le szavazat.' });
        }
    });
}

async function checkInJuror() {
    const docket = NyxState.court.currentDocket;
    if (!docket) return;

    const checkinBtn = document.getElementById('court-juror-checkin-btn');
    lockButtonAction(checkinBtn, async () => {
        const res = await postNui('court:seatJuror', {
            docketId: docket.docket_id || docket.docketId
        });

        if (res && res.success) {
            showNotification({ type: 'success', title: 'HELY ELFOGLALVA', message: 'Sikeresen elfoglaltad a helyed az esküdtszékben!' });
            refreshCourtOverview();
        } else {
            showNotification({ type: 'error', title: 'BEJELENTKEZÉS SIKERTELEN', message: res?.error || 'Hiba történt.' });
        }
    });
}

function renderWarrantsDashboard(petitions, activeWarrants) {
    // 1. Pending Petitions
    const petCountBadge = document.getElementById('court-petitions-count');
    if (petCountBadge) petCountBadge.textContent = `${petitions.length} kérvény`;

    const petList = document.getElementById('court-petitions-list');
    if (petList) {
        petList.innerHTML = '';
        if (petitions.length === 0) {
            petList.innerHTML = '<div class="empty-state" style="padding: 18px;"><p>Nincsenek elbírálásra váró rendvédelmi kérvények.</p></div>';
        } else {
            petitions.forEach(p => {
                const card = document.createElement('div');
                card.className = 'petition-item-card';

                const targetCit = p.target_citizen_id || p.targetCitizenId;
                const petId = p.petition_id || p.petitionId;
                const typeLabel = (p.warrant_type || p.warrantType || 'arrest').toUpperCase();
                const hours = p.requested_duration_hours || p.requestedDurationHours || 72;
                const cause = p.probable_cause_summary || p.probableCauseSummary || '-';
                const entity = p.target_entity_id || p.targetEntityId || '';

                let judgeActions = '';
                if (NyxState.court.isJudge) {
                    judgeActions = `
                        <div class="petition-actions-row">
                            <button class="btn btn-success btn-sm btn-approve" data-id="${petId}"><i class="fa-solid fa-stamp"></i> Jóváhagyás</button>
                            <button class="btn btn-danger btn-sm btn-reject" data-id="${petId}"><i class="fa-solid fa-xmark"></i> Elutasítás</button>
                        </div>
                    `;
                }

                card.innerHTML = `
                    <div class="petition-card-header">
                        <div class="title-col">
                            <span class="badge badge-warning">${typeLabel}</span>
                            <strong class="target-name">Cél: <code>${targetCit}</code></strong>
                        </div>
                        <span class="duration-label"><i class="fa-regular fa-clock"></i> ${hours} óra</span>
                    </div>
                    ${entity ? `<div class="target-entity"><i class="fa-solid fa-crosshairs"></i> Objektum / Rendszám: <strong>${entity}</strong></div>` : ''}
                    <p class="affidavit-text">${cause}</p>
                    <div class="petitioner-foot">Kérelmező: <code>${p.petitioner_citizen_id || p.petitionerCitizenId || 'LEO'}</code></div>
                    ${judgeActions}
                `;

                if (NyxState.court.isJudge) {
                    card.querySelector('.btn-approve')?.addEventListener('click', () => {
                        reviewWarrantPetition(petId, 'approved');
                    });
                    card.querySelector('.btn-reject')?.addEventListener('click', () => {
                        reviewWarrantPetition(petId, 'rejected');
                    });
                }

                petList.appendChild(card);
            });
        }
    }

    // 2. Active Warrants
    const warCountBadge = document.getElementById('court-active-warrants-count');
    if (warCountBadge) warCountBadge.textContent = `${activeWarrants.length} aktív`;

    const warList = document.getElementById('court-active-warrants-list');
    if (warList) {
        warList.innerHTML = '';
        if (activeWarrants.length === 0) {
            warList.innerHTML = '<div class="empty-state" style="padding: 18px;"><p>Nincsenek aktív bírói parancsok érvényben.</p></div>';
        } else {
            activeWarrants.forEach(w => {
                const card = document.createElement('div');
                card.className = 'warrant-item-card';

                const warId = w.warrant_id || w.warrantId;
                const targetCit = w.target_citizen_id || w.targetCitizenId;
                const type = w.type || w.warrantType || 'arrest';
                const typeLabel = type.toUpperCase();
                const expires = w.expires_at || w.expiresAt || 'Aktív';
                const cause = w.cause_summary || w.causeSummary || '';

                let extraActions = '';
                if (type === 'subpoena') {
                    extraActions += `<button class="btn btn-secondary btn-sm btn-subpoena" data-cit="${targetCit}"><i class="fa-solid fa-vault"></i> Főkönyvi Feltárás</button>`;
                }
                if (NyxState.court.isJudge) {
                    extraActions += `<button class="btn btn-danger btn-sm btn-rescind" data-id="${warId}"><i class="fa-solid fa-ban"></i> Visszavonás</button>`;
                }

                card.innerHTML = `
                    <div class="warrant-card-header">
                        <div>
                            <span class="badge badge-success">${typeLabel}</span>
                            <span class="warrant-id"><code>${warId}</code></span>
                        </div>
                        <span class="badge badge-outline"><i class="fa-solid fa-fingerprint"></i> HITELESÍTVE</span>
                    </div>
                    <div class="warrant-target">Célszemély: <strong>${targetCit}</strong></div>
                    <p class="warrant-cause truncate-2">${cause}</p>
                    <div class="warrant-footer">
                        <span class="exp-date"><i class="fa-regular fa-calendar"></i> Lejár: ${expires}</span>
                        <div class="warrant-btns">${extraActions}</div>
                    </div>
                `;

                card.querySelector('.btn-subpoena')?.addEventListener('click', () => {
                    openSubpoenaDisclosure(targetCit);
                });

                card.querySelector('.btn-rescind')?.addEventListener('click', () => {
                    rescindWarrant(warId);
                });

                warList.appendChild(card);
            });
        }
    }
}

async function submitWarrantPetition() {
    const targetCit = document.getElementById('court-input-target-citid')?.value?.trim();
    const warrantType = document.getElementById('court-select-warrant-type')?.value;
    const duration = parseInt(document.getElementById('court-input-duration')?.value || '72', 10);
    const scope = document.getElementById('court-select-subpoena-scope')?.value || 'all';
    const entity = document.getElementById('court-input-target-entity')?.value?.trim();
    const cause = document.getElementById('court-input-cause-summary')?.value?.trim();

    if (!targetCit || targetCit.length < 3) {
        showNotification({ type: 'error', title: 'HIÁNYZÓ ADAT', message: 'Kérlek add meg a célszemély állampolgári azonosítóját!' });
        return;
    }

    if (!cause || cause.length < 20) {
        showNotification({ type: 'error', title: 'ELÉGTELEN INDOKLÁS', message: 'A bírói parancs kérelemnek legalább 20 karakter részletes megalapozott indoklást kell tartalmaznia!' });
        return;
    }

    const submitBtn = document.getElementById('court-submit-petition-btn');
    lockButtonAction(submitBtn, async () => {
        const res = await postNui('court:petitionWarrant', {
            targetCitizenId: targetCit,
            warrantType: warrantType,
            requestedDurationHours: duration,
            subpoenaScope: warrantType === 'subpoena' ? scope : undefined,
            targetEntityId: entity || undefined,
            probableCauseSummary: cause
        });

        if (res && res.success) {
            showNotification({ type: 'success', title: 'KÉRVÉNY BENYÚJTVA', message: 'A hivatalos parancskérelmed továbbítva a bíróság felé.' });
            // Reset inputs
            document.getElementById('court-input-target-citid').value = '';
            document.getElementById('court-input-target-entity').value = '';
            document.getElementById('court-input-cause-summary').value = '';
            refreshCourtOverview();
        } else {
            showNotification({ type: 'error', title: 'BENYÚJTÁS SIKERTELEN', message: res?.error || 'Nem rendelkezel rendvédelmi felhatalmazással.' });
        }
    });
}

async function reviewWarrantPetition(petitionId, decision) {
    const res = await postNui('court:reviewPetition', {
        petitionId: petitionId,
        decision: decision
    });

    if (res && res.success) {
        showNotification({ type: 'info', title: 'KÉRVÉNY ELBÍRÁLVA', message: `Kérvény #${petitionId} sikeresen elbírálva (${decision})!` });
        refreshCourtOverview();
    } else {
        showNotification({ type: 'error', title: 'ELBÍRÁLÁS SIKERTELEN', message: res?.error || 'Hiba a kérvény feldolgozásakor.' });
    }
}

async function rescindWarrant(warrantId) {
    openDialog({
        title: 'Bírói Parancs Visszavonása',
        message: `Biztosan megsemmisíted és hatályon kívül helyezed a(z) ${warrantId} számú parancsot?`,
        onConfirm: async () => {
            const res = await postNui('court:rescindWarrant', { warrantId: warrantId, reason: 'Judicial order to quash' });
            if (res && res.success) {
                showNotification({ type: 'warning', title: 'PARANCS VISSZAVONVA', message: `Parancs #${warrantId} visszavonásra került.` });
                refreshCourtOverview();
            } else {
                showNotification({ type: 'error', title: 'VISSZAVONÁS SIKERTELEN', message: res?.error || 'Nem sikerült visszavonni a parancsot.' });
            }
        }
    });
}

async function openSubpoenaDisclosure(citizenId) {
    const disclosureEl = document.getElementById('court-subpoena-disclosure');
    const targetLabel = document.getElementById('court-subpoena-target-label');
    const content = document.getElementById('court-subpoena-content');
    if (!disclosureEl || !content) return;

    disclosureEl.classList.remove('hidden');
    if (targetLabel) targetLabel.textContent = `Célszemély: ${citizenId}`;
    content.innerHTML = '<div class="empty-state" style="padding: 20px;"><i class="fa-solid fa-spinner fa-spin"></i> Főkönyvi adatok lekérése...</div>';

    const res = await postNui('court:getSubpoenaRecords', { targetCitizenId: citizenId });
    if (!res || !res.success || !res.records) {
        content.innerHTML = '<div class="empty-state" style="padding: 20px; color: var(--accent-red);"><p>A főkönyvi adatok lekérdezése sikertelen vagy nincs érvényes idézés.</p></div>';
        return;
    }

    const rec = res.records;
    const bank = (rec.bankBalance || rec.bank || 0).toLocaleString();
    const cash = (rec.cashBalance || rec.cash || 0).toLocaleString();

    let accountsHtml = '';
    (rec.accounts || []).forEach(a => {
        accountsHtml += `
            <div class="subp-item">
                <span><code>${a.id}</code> (${a.type})</span>
                <strong style="color: var(--accent-emerald);">$${(a.balance || 0).toLocaleString()}</strong>
            </div>
        `;
    });

    let propsHtml = '';
    (rec.properties || []).forEach(p => {
        propsHtml += `
            <div class="subp-item">
                <span><code>${p.id}</code>: ${p.address}</span>
                <span style="color: var(--accent-cyan);">$${(p.value || 0).toLocaleString()}</span>
            </div>
        `;
    });

    let sharesHtml = '';
    (rec.corporateShares || []).forEach(s => {
        sharesHtml += `
            <div class="subp-item">
                <span>${s.name || s.factionId}</span>
                <strong style="color: var(--accent-amber);">${s.sharesPercent || s.equity}%</strong>
            </div>
        `;
    });

    let txHtml = '';
    (rec.transactions || []).forEach(t => {
        const amt = Number(t.amount || 0);
        txHtml += `
            <div class="subp-item tx">
                <div><span class="time">${t.date || ''}</span> <span class="memo">${t.memo || ''}</span></div>
                <strong style="color: ${amt >= 0 ? 'var(--accent-emerald)' : 'var(--accent-red)'}; font-family: var(--font-mono);">${amt >= 0 ? '+' : ''}$${amt.toLocaleString()}</strong>
            </div>
        `;
    });

    content.innerHTML = `
        <div class="subp-kpis">
            <div class="subp-kpi"><span>Főkönyvi Bankszámla:</span> <strong>$${bank}</strong></div>
            <div class="subp-kpi"><span>Készpénzállomány:</span> <strong>$${cash}</strong></div>
        </div>
        <div class="subp-section">
            <h5><i class="fa-solid fa-credit-card"></i> Pénzintézeti Fiókok & Számlák</h5>
            ${accountsHtml || '<div class="subp-empty">Nincs rögzített folyószámla.</div>'}
        </div>
        <div class="subp-section">
            <h5><i class="fa-solid fa-building"></i> Nyilvántartott Ingatlanvagyon</h5>
            ${propsHtml || '<div class="subp-empty">Nincs bejegyzett ingatlan.</div>'}
        </div>
        <div class="subp-section">
            <h5><i class="fa-solid fa-chart-pie"></i> Vállalati Tulajdonrészek & Részvények</h5>
            ${sharesHtml || '<div class="subp-empty">Nincs társasági tulajdonrész.</div>'}
        </div>
        <div class="subp-section">
            <h5><i class="fa-solid fa-receipt"></i> Főkönyvi Tranzakciók</h5>
            ${txHtml || '<div class="subp-empty">Nincsenek rögzített tranzakciók.</div>'}
        </div>
    `;
}

// 12D. Parliamentary Ranked-Choice Voting & Legislation Terminal
function openParliamentUI(payload) {
    NyxState.parliament.isOpen = true;
    NyxState.parliament.boothId = payload && payload.boothId ? payload.boothId : null;
    NyxState.parliament.boothLabel = payload && payload.boothLabel ? payload.boothLabel : null;
    const overlay = document.getElementById('parliament-overlay');
    if (overlay) overlay.classList.remove('hidden');

    if (payload && payload.activeTab) {
        NyxState.parliament.activeTab = payload.activeTab;
    }

    setParliamentTab(NyxState.parliament.activeTab || 'ballot');

    if (payload && payload.sessions) {
        NyxState.parliament.sessions = payload.sessions || [];
        NyxState.parliament.candidates = payload.candidates || [];
        NyxState.parliament.laws = payload.laws || [];
        NyxState.parliament.amendments = payload.amendments || [];
        NyxState.parliament.petitions = payload.petitions || [];
        NyxState.parliament.officials = payload.officials || [];
        NyxState.parliament.booths = payload.booths || [];
        NyxState.parliament.termAudits = payload.termAudits || [];
        renderParliamentOverviewData();
    } else {
        refreshParliamentOverview();
    }
}

function closeParliamentUI() {
    NyxState.parliament.isOpen = false;
    const overlay = document.getElementById('parliament-overlay');
    if (overlay) overlay.classList.add('hidden');

    const recallModal = document.getElementById('parliament-submodal-recall');
    if (recallModal) recallModal.classList.add('hidden');

    postNui('closeParliamentUI', {});
}

function setParliamentTab(tabName) {
    NyxState.parliament.activeTab = tabName;

    // Update Tab Buttons
    document.querySelectorAll('.parliament-tab').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-tab') === tabName);
    });

    // Update Tab Panes
    const ballotPane = document.getElementById('parliament-tab-ballot');
    const candPane = document.getElementById('parliament-tab-candidates');
    const lawsPane = document.getElementById('parliament-tab-laws');

    if (ballotPane) ballotPane.classList.toggle('hidden', tabName !== 'ballot');
    if (candPane) candPane.classList.toggle('hidden', tabName !== 'candidates');
    if (lawsPane) lawsPane.classList.toggle('hidden', tabName !== 'laws');

    playWebBeep(640, 'sine', 0.04);

    if (tabName === 'ballot') {
        renderParliamentBallot();
    } else if (tabName === 'candidates') {
        renderParliamentCandidates();
    } else if (tabName === 'laws') {
        renderParliamentLaws();
    }
}

async function refreshParliamentOverview() {
    const res = await postNui('parliament:getOverview', {});
    if (res && res.success) {
        NyxState.parliament.sessions = res.sessions || [];
        NyxState.parliament.candidates = res.candidates || [];
        NyxState.parliament.laws = res.laws || [];
        NyxState.parliament.amendments = res.amendments || [];
        NyxState.parliament.petitions = res.petitions || [];
        NyxState.parliament.officials = res.officials || [];
        NyxState.parliament.booths = res.booths || [];
        NyxState.parliament.termAudits = res.termAudits || [];
        renderParliamentOverviewData();
    }
}

function renderParliamentOverviewData() {
    const sessionSelect = document.getElementById('parliament-session-select');
    const nomSessionSelect = document.getElementById('parliament-nomination-session-select');

    if (sessionSelect) {
        sessionSelect.innerHTML = '';
        NyxState.parliament.sessions.forEach(s => {
            const opt = document.createElement('option');
            opt.value = s.session_id;
            opt.textContent = `${s.title} (${s.session_type || 'ELECTION'})`;
            sessionSelect.appendChild(opt);
        });

        if (NyxState.parliament.sessions.length > 0) {
            if (!NyxState.parliament.selectedSessionId || !NyxState.parliament.sessions.some(s => s.session_id === NyxState.parliament.selectedSessionId)) {
                // Pick first active session or first session
                const active = NyxState.parliament.sessions.find(s => (s.status || '').toUpperCase() === 'ACTIVE') || NyxState.parliament.sessions[0];
                NyxState.parliament.selectedSessionId = active.session_id;
            }
            sessionSelect.value = NyxState.parliament.selectedSessionId;
        }
    }

    if (nomSessionSelect) {
        nomSessionSelect.innerHTML = '';
        NyxState.parliament.sessions.filter(s => (s.status || '').toUpperCase() === 'ACTIVE').forEach(s => {
            const opt = document.createElement('option');
            opt.value = s.session_id;
            opt.textContent = `${s.title} [#${s.session_id}]`;
            nomSessionSelect.appendChild(opt);
        });
    }

    // Header status
    const headerStatus = document.getElementById('parliament-header-status');
    if (headerStatus) {
        const cur = NyxState.parliament.sessions.find(s => s.session_id === NyxState.parliament.selectedSessionId);
        headerStatus.textContent = cur ? (cur.status || 'AKTÍV').toUpperCase() : 'ÜLÉSSZAK';
    }

    renderParliamentBallot();
    renderParliamentCandidates();
    renderParliamentLaws();
    renderParliamentAmendments();
    renderParliamentPetitions();
}

function renderParliamentBallot() {
    const currentSession = NyxState.parliament.sessions.find(s => s.session_id === NyxState.parliament.selectedSessionId);
    const typeBadge = document.getElementById('parliament-session-type-badge');
    const quorumBadge = document.getElementById('parliament-session-quorum-badge');

    if (currentSession) {
        if (typeBadge) typeBadge.textContent = (currentSession.session_type || 'ELECTION').toUpperCase();
        if (quorumBadge) quorumBadge.textContent = `Kvórum: ${currentSession.current_votes || 0}/${currentSession.quorum_target || 5}`;
    }

    const sessionCandidates = NyxState.parliament.candidates.filter(c => c.session_id === NyxState.parliament.selectedSessionId);

    // Synchronize rankedCandidateIds: keep current order if valid, append new, remove missing
    const existing = NyxState.parliament.rankedCandidateIds.filter(id => sessionCandidates.some(c => c.candidate_id === id));
    sessionCandidates.forEach(c => {
        if (!existing.includes(c.candidate_id)) {
            existing.push(c.candidate_id);
        }
    });
    NyxState.parliament.rankedCandidateIds = existing;

    const countBadge = document.getElementById('parliament-ballot-count-badge');
    if (countBadge) countBadge.textContent = `${NyxState.parliament.rankedCandidateIds.length} rangsorolva`;

    const container = document.getElementById('parliament-ballot-candidate-list');
    if (!container) return;
    container.innerHTML = '';

    if (NyxState.parliament.rankedCandidateIds.length === 0) {
        container.innerHTML = '<div class="empty-state"><i class="fa-solid fa-users-slash empty-icon"></i><p>Ehhez az ülésszakhoz még nincsenek jóváhagyott jelöltek.</p></div>';
        return;
    }

    NyxState.parliament.rankedCandidateIds.forEach((candId, idx) => {
        const cand = sessionCandidates.find(c => c.candidate_id === candId);
        if (!cand) return;

        const rankNum = idx + 1;
        const item = document.createElement('div');
        item.className = 'ballot-candidate-row';
        item.innerHTML = `
            <div class="candidate-rank-badge">#${rankNum}</div>
            <div class="candidate-info-block">
                <div class="candidate-primary-line">
                    <strong class="cand-name">${cand.display_name}</strong>
                    <span class="cand-party-pill">${cand.party || 'Független'}</span>
                </div>
                <div class="cand-slogan">${cand.campaign_slogan || cand.platform || 'Állampolgári program elérhető.'}</div>
            </div>
            <div class="candidate-reorder-actions">
                <button class="rank-btn up-btn" data-id="${candId}" data-dir="-1" title="Előrébb rangsorolás" ${idx === 0 ? 'disabled' : ''}>
                    <i class="fa-solid fa-chevron-up"></i>
                </button>
                <button class="rank-btn down-btn" data-id="${candId}" data-dir="1" title="Hátrébb rangsorolás" ${idx === NyxState.parliament.rankedCandidateIds.length - 1 ? 'disabled' : ''}>
                    <i class="fa-solid fa-chevron-down"></i>
                </button>
            </div>
        `;

        item.querySelector('.up-btn')?.addEventListener('click', () => shiftParliamentCandidate(candId, -1));
        item.querySelector('.down-btn')?.addEventListener('click', () => shiftParliamentCandidate(candId, 1));

        container.appendChild(item);
    });
}

function shiftParliamentCandidate(candId, delta) {
    const list = NyxState.parliament.rankedCandidateIds;
    const curIdx = list.indexOf(candId);
    if (curIdx === -1) return;
    const targetIdx = curIdx + delta;
    if (targetIdx < 0 || targetIdx >= list.length) return;

    const temp = list[curIdx];
    list[curIdx] = list[targetIdx];
    list[targetIdx] = temp;

    playWebBeep(780, 'sine', 0.03);
    renderParliamentBallot();
}

async function castParliamentBallot() {
    const sessionId = NyxState.parliament.selectedSessionId;
    if (!sessionId) {
        showNotification({ type: 'warning', title: 'NINCS ÜLÉSSZAK', message: 'Válassz ki egy aktív választási ülésszakot!' });
        return;
    }

    const preferences = NyxState.parliament.rankedCandidateIds;
    if (!preferences || preferences.length === 0) {
        showNotification({ type: 'warning', title: 'ÜRES SZAVAZÓLAP', message: 'Kérlek rangsorolj legalább egy jelöltet a szavazat leadásához!' });
        return;
    }

    const castBtn = document.getElementById('parliament-cast-ballot-btn');
    lockButtonAction(castBtn, async () => {
        const res = await postNui('parliament:castBallot', {
            sessionId: sessionId,
            preferences: preferences,
            boothId: NyxState.parliament.boothId || null,
            boothLabel: NyxState.parliament.boothLabel || null
        });

        if (res && res.success) {
            playWebBeep(920, 'triangle', 0.12);
            const proofBanner = document.getElementById('parliament-cast-proof-banner');
            const proofHashEl = document.getElementById('parliament-proof-hash');
            if (proofBanner && proofHashEl) {
                proofHashEl.textContent = res.receiptHash || 'NYX-BALLOT-VALIDATED';
                proofBanner.classList.remove('hidden');
            }

            const receiptInput = document.getElementById('parliament-receipt-input');
            if (receiptInput && res.receiptHash) {
                receiptInput.value = res.receiptHash;
            }

            showNotification({
                type: 'success',
                title: 'SZAVAZAT HITELÍTVE',
                message: `Titkos preferenciás szavazatod sikeresen rögzítve az urnában. Nyugtakód mentve.`
            });
        } else {
            showNotification({
                type: 'error',
                title: 'SZAVAZÁS SIKERTELEN',
                message: res?.error || 'A szavazat leadása meghiúsult. Kérlek ellenőrizd az ülésszak státuszát!'
            });
        }
    });
}

async function verifyParliamentReceipt() {
    const receiptInput = document.getElementById('parliament-receipt-input');
    const hash = receiptInput ? receiptInput.value.trim() : '';

    if (!hash) {
        showNotification({ type: 'warning', title: 'HIÁNYZÓ NYUGTAKÓD', message: 'Kérlek add meg az ellenőrizni kívánt NYX-BALLOT-... nyugtakódot!' });
        return;
    }

    const verifyBtn = document.getElementById('parliament-verify-receipt-btn');
    lockButtonAction(verifyBtn, async () => {
        const res = await postNui('parliament:verifyReceipt', {
            sessionId: NyxState.parliament.selectedSessionId,
            receiptHash: hash
        });

        const banner = document.getElementById('parliament-receipt-verify-banner');
        if (!banner) return;
        banner.classList.remove('hidden');

        if (res && (res.verified || res.success)) {
            playWebBeep(880, 'sine', 0.08);
            banner.className = 'verification-banner valid';
            const prefStr = Array.isArray(res.preferences) ? res.preferences.join(' → ') : 'Rangsorolt Preferenciák Rögzítve';
            banner.innerHTML = `
                <i class="fa-solid fa-circle-check icon-status"></i>
                <div class="banner-body">
                    <strong>HITELÍTETT BÁMULATOS SZAVAZATI NYUGTA (ÉRVÉNYES)</strong>
                    <div class="sub-line">Ülésszak: ${res.session || 'Aktuális Választás'} | Időbélyeg: ${res.timestamp || '2026'}</div>
                    <div class="sub-line">Rangsorolt jelöltek: <code>${prefStr}</code></div>
                    <code class="hash-preview">HASH: ${hash}</code>
                </div>
            `;
            showNotification({ type: 'success', title: 'NYUGTA IGAZOLVA', message: 'A szavazólap sértetlenül szerepel az auditált urnában.' });
        } else {
            banner.className = 'verification-banner invalid';
            banner.innerHTML = `
                <i class="fa-solid fa-triangle-exclamation icon-status"></i>
                <div class="banner-body">
                    <strong>ÉRVÉNYTELEN VAGY NEM LÉTEZŐ NYUGTA</strong>
                    <div class="sub-line">A megadott hash kód (${hash}) nem szerepel a kiválasztott ülésszak választási főkönyvében.</div>
                </div>
            `;
            showNotification({ type: 'error', title: 'NYUGTA HIBA', message: res?.error || 'A nyugtakód nem található.' });
        }
    });
}

async function refreshParliamentTabulation() {
    const refreshBtn = document.getElementById('parliament-refresh-tabulation-btn');
    lockButtonAction(refreshBtn, async () => {
        const res = await postNui('parliament:getTabulationAudit', {
            sessionId: NyxState.parliament.selectedSessionId
        });

        const emptyHint = document.getElementById('parliament-tabulation-empty-hint');
        const roundsContainer = document.getElementById('parliament-tabulation-rounds-container');
        if (!roundsContainer) return;

        if (res && res.rounds && res.rounds.length > 0) {
            if (emptyHint) emptyHint.classList.add('hidden');
            roundsContainer.classList.remove('hidden');
            roundsContainer.innerHTML = '';

            res.rounds.forEach(r => {
                const roundCard = document.createElement('div');
                roundCard.className = 'tabulation-round-card';

                let talliesHtml = '';
                const sortedCands = Object.keys(r.tallies || {}).sort((a, b) => (r.tallies[b] || 0) - (r.tallies[a] || 0));

                sortedCands.forEach(cid => {
                    const candObj = NyxState.parliament.candidates.find(c => String(c.candidate_id) === String(cid));
                    const name = candObj ? candObj.display_name : `Jelölt #${cid}`;
                    const votes = r.tallies[cid] || 0;
                    const pct = r.percentages ? (r.percentages[cid] || 0) : 0;
                    const isEliminated = String(r.eliminated) === String(cid);
                    const isElected = String(r.elected) === String(cid);

                    let statusTag = '';
                    if (isElected) statusTag = '<span class="badge badge-success">MEGVÁLASZTVA (GYŐZTES)</span>';
                    else if (isEliminated) statusTag = '<span class="badge badge-danger">KIESETT</span>';

                    talliesHtml += `
                        <div class="tally-row">
                            <div class="tally-cand-info">
                                <span>${name}</span>
                                <div>${statusTag} <strong class="tally-num">${votes} szavazat (${pct}%)</strong></div>
                            </div>
                            <div class="tally-bar-track">
                                <div class="tally-bar-fill ${isElected ? 'winner' : ''} ${isEliminated ? 'eliminated' : ''}" style="width: ${Math.min(100, pct)}%;"></div>
                            </div>
                        </div>
                    `;
                });

                roundCard.innerHTML = `
                    <div class="round-card-header">
                        <h5><i class="fa-solid fa-rotate"></i> ${r.round}. Számlálási Forduló</h5>
                        <span class="sub-text">Elhasznált szavazatok: ${r.exhaustedBallots || 0}</span>
                    </div>
                    <div class="round-tallies-body">
                        ${talliesHtml}
                    </div>
                `;
                roundsContainer.appendChild(roundCard);
            });
        } else {
            if (emptyHint) emptyHint.classList.remove('hidden');
            roundsContainer.classList.add('hidden');
            showNotification({ type: 'info', title: 'TABULÁCIÓ FOLYAMATBAN', message: 'Az urnazárás még nem történt meg, nincs véglegesített IRV jegyzőkönyv.' });
        }
    });
}

function renderParliamentCandidates() {
    const grid = document.getElementById('parliament-candidates-grid');
    const badge = document.getElementById('parliament-candidates-count-badge');
    if (!grid) return;

    grid.innerHTML = '';
    const candidates = NyxState.parliament.candidates || [];
    if (badge) badge.textContent = `${candidates.length} jelölt`;

    if (candidates.length === 0) {
        grid.innerHTML = '<div class="empty-state"><i class="fa-solid fa-users-viewfinder empty-icon"></i><p>Jelenleg nincsenek regisztrált jelöltek.</p></div>';
        return;
    }

    candidates.forEach(c => {
        const card = document.createElement('div');
        card.className = 'candidate-card card-surface';

        const endorsements = c.endorsements_count || 0;
        const threshold = 5;
        const pct = Math.min(100, Math.round((endorsements / threshold) * 100));
        const isVerified = (c.is_verified === 1 || c.is_verified === true || endorsements >= threshold);

        card.innerHTML = `
            <div class="cand-card-header">
                <div>
                    <h5 class="cand-name">${c.display_name}</h5>
                    <span class="cand-party-tag">${c.party || 'Független'}</span>
                </div>
                ${isVerified ? '<span class="badge badge-success"><i class="fa-solid fa-certificate"></i> HITELESÍTVE</span>' : '<span class="badge badge-warning"><i class="fa-solid fa-clock"></i> ALÁÍRÁSGYŰJTÉS</span>'}
            </div>
            <p class="cand-slogan-text">"${c.campaign_slogan || 'Egy élhetőbb és átláthatóbb városért!'}"</p>
            <div class="cand-platform-box">
                <span class="platform-label">Választási Program:</span>
                <p class="platform-text">${c.platform || 'Nincs részletes platform rögzítve.'}</p>
            </div>
            <div class="cand-endorsement-status">
                <div class="endorse-meta">
                    <span>Támogatói Aláírások:</span>
                    <strong>${endorsements} / ${threshold}</strong>
                </div>
                <div class="endorse-bar-track">
                    <div class="endorse-bar-fill" style="width: ${pct}%;"></div>
                </div>
            </div>
            <div class="cand-card-footer">
                <button class="btn btn-secondary btn-sm btn-block cand-endorse-btn" data-id="${c.candidate_id}" ${isVerified ? 'disabled' : ''}>
                    <i class="fa-solid fa-handshake"></i> ${isVerified ? 'Kvórum Elérve' : 'Jelölt Támogatása (Endorse)'}
                </button>
            </div>
        `;

        card.querySelector('.cand-endorse-btn')?.addEventListener('click', () => endorseParliamentCandidate(c.candidate_id));
        grid.appendChild(card);
    });
}

async function endorseParliamentCandidate(candidateId) {
    const res = await postNui('parliament:endorseCandidate', { candidateId: candidateId });
    if (res && res.success) {
        playWebBeep(740, 'sine', 0.06);
        const cand = NyxState.parliament.candidates.find(c => c.candidate_id === candidateId);
        if (cand) {
            cand.endorsements_count = res.endorsements || ((cand.endorsements_count || 0) + 1);
            if (res.verified) cand.is_verified = 1;
        }
        renderParliamentCandidates();
        showNotification({ type: 'success', title: 'TÁMOGATÁS RÖGZÍTVE', message: 'Támogatói aláírásod rögzítésre került az állampolgári névjegyzékben.' });
    } else {
        showNotification({ type: 'error', title: 'TÁMOGATÁS MEGSZAKADT', message: res?.error || 'Nem sikerült támogatni a jelöltet (esetleg már aláírtad vagy nincs érvényes személyid).' });
    }
}

async function submitParliamentCandidacy() {
    const sessionSelect = document.getElementById('parliament-nomination-session-select');
    const sessionId = sessionSelect ? parseInt(sessionSelect.value, 10) : null;
    const nameInput = document.getElementById('parliament-input-cand-name');
    const partyInput = document.getElementById('parliament-input-cand-party');
    const sloganInput = document.getElementById('parliament-input-cand-slogan');
    const platformInput = document.getElementById('parliament-input-cand-platform');

    const name = nameInput ? nameInput.value.trim() : '';
    const party = partyInput ? partyInput.value.trim() : '';
    const slogan = sloganInput ? sloganInput.value.trim() : '';
    const platform = platformInput ? platformInput.value.trim() : '';

    if (!sessionId) {
        showNotification({ type: 'warning', title: 'HIÁNYZÓ ÜLÉSSZAK', message: 'Válassz ki egy aktív ülésszakot a jelöltséghez!' });
        return;
    }
    if (name.length < 3) {
        showNotification({ type: 'warning', title: 'ÉRVÉNYTELEN NÉV', message: 'A jelölt neve legalább 3 karakter kell legyen!' });
        return;
    }
    if (party.length < 2) {
        showNotification({ type: 'warning', title: 'ÉRVÉNYTELEN PÁRT', message: 'Add meg a jelölő párt vagy független státusz megnevezését!' });
        return;
    }
    if (platform.length < 10) {
        showNotification({ type: 'warning', title: 'RÖVID PLATFORM', message: 'Kérlek fejtsd ki a választási programodat legalább 10 karakterben!' });
        return;
    }

    const submitBtn = document.getElementById('parliament-submit-candidacy-btn');
    lockButtonAction(submitBtn, async () => {
        const res = await postNui('parliament:registerCandidate', {
            sessionId: sessionId,
            displayName: name,
            party: party,
            slogan: slogan,
            platform: platform
        });

        if (res && res.success) {
            playWebBeep(880, 'sine', 0.08);
            if (nameInput) nameInput.value = '';
            if (partyInput) partyInput.value = '';
            if (sloganInput) sloganInput.value = '';
            if (platformInput) platformInput.value = '';

            showNotification({ type: 'success', title: 'JELÖLTSÉG BEJEGYEZVE', message: 'Választási jelöltséged sikeresen regisztrálva. Az aláírásgyűjtés megkezdődött.' });
            refreshParliamentOverview();
        } else {
            showNotification({ type: 'error', title: 'JELÖLÉS MEGSZAKÍTVA', message: res?.error || 'A kaució levonása vagy a regisztráció meghiúsult.' });
        }
    });
}

function renderParliamentLaws() {
    const searchInput = document.getElementById('parliament-laws-search');
    const catSelect = document.getElementById('parliament-laws-cat-filter');
    const searchVal = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const catVal = catSelect ? catSelect.value : 'all';

    const laws = NyxState.parliament.laws || [];

    // Filter
    const filtered = laws.filter(l => {
        const matchesCat = (catVal === 'all') || (l.category === catVal);
        const matchesSearch = !searchVal ||
            (l.law_id || '').toLowerCase().includes(searchVal) ||
            (l.name || '').toLowerCase().includes(searchVal) ||
            (l.description || '').toLowerCase().includes(searchVal);
        return matchesCat && matchesSearch;
    });

    // Update KPI counters
    const kpiTotal = document.getElementById('parliament-kpi-total');
    const kpiFelonies = document.getElementById('parliament-kpi-felonies');
    const kpiMisdemeanors = document.getElementById('parliament-kpi-misdemeanors');
    const kpiInfractions = document.getElementById('parliament-kpi-infractions');
    const kpiFiscal = document.getElementById('parliament-kpi-fiscal');

    if (kpiTotal) kpiTotal.textContent = laws.length;
    if (kpiFelonies) kpiFelonies.textContent = laws.filter(l => l.category === 'penal_felony').length;
    if (kpiMisdemeanors) kpiMisdemeanors.textContent = laws.filter(l => l.category === 'penal_misdemeanor').length;
    if (kpiInfractions) kpiInfractions.textContent = laws.filter(l => l.category === 'penal_infraction').length;
    if (kpiFiscal) kpiFiscal.textContent = laws.filter(l => l.category === 'fiscal_policy').length;

    // Table rows
    const tbody = document.getElementById('parliament-laws-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (filtered.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center sub-text">Nem található egyező jogszabály a megadott szűrők alapján.</td></tr>';
    } else {
        filtered.forEach(l => {
            const tr = document.createElement('tr');

            let badgeHtml = '<span class="badge badge-outline">EGYÉB</span>';
            if (l.category === 'penal_felony') badgeHtml = '<span class="badge badge-danger">BŰNTETT</span>';
            else if (l.category === 'penal_misdemeanor') badgeHtml = '<span class="badge badge-warning">VÉTSÉG</span>';
            else if (l.category === 'penal_infraction') badgeHtml = '<span class="badge badge-info">SZABÁLYSÉRTÉS</span>';
            else if (l.category === 'fiscal_policy') badgeHtml = '<span class="badge badge-primary">PÉNZÜGY</span>';

            const fineStr = l.tax_rate_default !== undefined
                ? `${((l.tax_rate_default || 0) * 100).toFixed(1)}% Adókulcs`
                : `$${Number(l.fine_default || 0).toLocaleString()}`;

            const prisonStr = l.prison_months_default !== undefined ? `${l.prison_months_default} hó` : '-';

            let boundsStr = '-';
            if (l.fine_min !== undefined && l.fine_max !== undefined) {
                boundsStr = `$${l.fine_min.toLocaleString()} - $${l.fine_max.toLocaleString()}`;
            } else if (l.tax_rate_min !== undefined && l.tax_rate_max !== undefined) {
                boundsStr = `${(l.tax_rate_min * 100).toFixed(1)}% - ${(l.tax_rate_max * 100).toFixed(1)}%`;
            }

            tr.innerHTML = `
                <td><code>${l.law_id}</code></td>
                <td><strong>${l.name}</strong></td>
                <td>${badgeHtml}</td>
                <td style="font-family: var(--font-mono); color: var(--accent-amber);">${fineStr}</td>
                <td style="font-family: var(--font-mono); color: var(--accent-red);">${prisonStr}</td>
                <td class="sub-text">${boundsStr}</td>
                <td class="sub-text">${l.updated_at || 'Hatályos'}</td>
            `;
            tbody.appendChild(tr);
        });
    }

    // Populate bill proposal law dropdown
    const billLawSelect = document.getElementById('parliament-select-bill-law');
    if (billLawSelect && billLawSelect.children.length === 0) {
        laws.forEach(l => {
            const opt = document.createElement('option');
            opt.value = l.law_id;
            opt.textContent = `${l.law_id} - ${l.name}`;
            billLawSelect.appendChild(opt);
        });
        updateParliamentBillBoundsHint();
    }
}

function updateParliamentBillBoundsHint() {
    const billLawSelect = document.getElementById('parliament-select-bill-law');
    const billFieldSelect = document.getElementById('parliament-select-bill-field');
    const hintEl = document.getElementById('parliament-bill-bounds-hint');
    if (!billLawSelect || !billFieldSelect || !hintEl) return;

    const lawId = billLawSelect.value;
    const field = billFieldSelect.value;
    const law = (NyxState.parliament.laws || []).find(l => l.law_id === lawId);

    if (!law) {
        hintEl.textContent = 'Törvényes határ: -';
        return;
    }

    if (field === 'fine') {
        const min = law.fine_min ?? 0;
        const max = law.fine_max ?? 100000;
        hintEl.textContent = `Törvényes határ (Bírság): $${min.toLocaleString()} - $${max.toLocaleString()} (Jelenleg: $${(law.fine_default || 0).toLocaleString()})`;
    } else if (field === 'months') {
        const min = law.prison_months_min ?? 0;
        const max = law.prison_months_max ?? 120;
        hintEl.textContent = `Törvényes határ (Elzárás): ${min} - ${max} hónap (Jelenleg: ${law.prison_months_default || 0} hó)`;
    } else if (field === 'rate') {
        const min = law.tax_rate_min ?? 0.00;
        const max = law.tax_rate_max ?? 0.15;
        hintEl.textContent = `Törvényes határ (Adókulcs): ${(min * 100).toFixed(1)}% - ${(max * 100).toFixed(1)}% (Jelenleg: ${((law.tax_rate_default || 0) * 100).toFixed(1)}%)`;
    }
}

async function submitParliamentBill() {
    const title = document.getElementById('parliament-input-bill-title')?.value.trim() || '';
    const desc = document.getElementById('parliament-input-bill-desc')?.value.trim() || '';
    const lawId = document.getElementById('parliament-select-bill-law')?.value || '';
    const field = document.getElementById('parliament-select-bill-field')?.value || 'fine';
    const rawVal = document.getElementById('parliament-input-bill-newval')?.value;
    const newVal = parseFloat(rawVal);

    if (title.length < 5) {
        showNotification({ type: 'warning', title: 'HIÁNYZÓ CÍM', message: 'Adj meg egy értelmes törvényjavaslati címet (min 5 karakter)!' });
        return;
    }
    if (desc.length < 10) {
        showNotification({ type: 'warning', title: 'HIÁNYZÓ INDOKLÁS', message: 'Kérlek részletesen indokold a javaslatot legalább 10 karakterben!' });
        return;
    }
    if (isNaN(newVal)) {
        showNotification({ type: 'warning', title: 'ÉRVÉNYTELEN ÉRTÉK', message: 'Kérlek adj meg egy érvényes számértéket az új törvényes határhoz!' });
        return;
    }

    const submitBtn = document.getElementById('parliament-submit-bill-btn');
    lockButtonAction(submitBtn, async () => {
        const res = await postNui('parliament:proposeBill', {
            billPayload: {
                title: title,
                description: desc,
                category: 'LEGISLATION',
                field: field,
                proposedValue: newVal,
                lawId: lawId
            }
        });

        if (res && res.success) {
            playWebBeep(920, 'sine', 0.1);
            showNotification({ type: 'success', title: 'TÖRVÉNYJAVASLAT BENYÚJTVA', message: 'A javaslat sikeresen rögzítve és szavazásra bocsátva.' });
            document.getElementById('parliament-input-bill-title').value = '';
            document.getElementById('parliament-input-bill-desc').value = '';
            document.getElementById('parliament-input-bill-newval').value = '';
            refreshParliamentOverview();
        } else {
            showNotification({ type: 'error', title: 'BENYÚJTÁS SIKERTELEN', message: res?.error || 'A javaslat elutasítva. Ellenőrizd a letétet és a törvényes határokat!' });
        }
    });
}

function renderParliamentAmendments() {
    const container = document.getElementById('parliament-recent-amendments-list');
    if (!container) return;
    container.innerHTML = '';

    const amendments = NyxState.parliament.amendments || [];
    if (amendments.length === 0) {
        container.innerHTML = '<div class="empty-state-mini sub-text">Nincsenek friss módosítások rögzítve.</div>';
        return;
    }

    amendments.slice(0, 5).forEach(a => {
        const item = document.createElement('div');
        item.className = 'amendment-log-item';
        item.innerHTML = `
            <div class="amendment-header-line">
                <span class="amendment-law-id"><code>${a.law_id}</code></span>
                <span class="amendment-date sub-text">${a.enacted_at || ''}</span>
            </div>
            <div class="amendment-title"><strong>${a.enacted_by_session_title || 'Parlamenti Törvénycsomag'}</strong></div>
            <div class="amendment-diff-line">
                <span>${a.field.toUpperCase()}:</span>
                <del>${a.old_value}</del> <i class="fa-solid fa-arrow-right-long"></i> <ins>${a.new_value}</ins>
            </div>
        `;
        container.appendChild(item);
    });
}

function renderParliamentPetitions() {
    const container = document.getElementById('parliament-petitions-list');
    if (!container) return;
    container.innerHTML = '';

    const petitions = NyxState.parliament.petitions || [];
    if (petitions.length === 0) {
        container.innerHTML = '<div class="empty-state-mini sub-text">Jelenleg nincs aktív visszahívási kezdeményezés.</div>';
        return;
    }

    petitions.forEach(p => {
        const item = document.createElement('div');
        item.className = 'petition-card';

        const sigs = p.signatures_count || 0;
        const thresh = p.threshold || 5;
        const isMet = sigs >= thresh;

        item.innerHTML = `
            <div class="petition-header-row">
                <span class="petition-office-title"><strong>${(p.office_id || 'TISZTSÉG').toUpperCase()}</strong></span>
                <span class="badge ${isMet ? 'badge-danger' : 'badge-warning'}">${isMet ? 'KÜSZÖB ELÉRVE' : `${sigs}/${thresh} ALÁÍRÁS`}</span>
            </div>
            <p class="petition-reason-text">"${p.reason || 'Nincs részletes indoklás.'}"</p>
            <div class="petition-footer-row">
                <span class="sub-text">Kezdeményező: <code>${p.sponsor_citizen_id || '-'}</code></span>
                <button class="btn btn-secondary btn-sm petition-sign-btn" data-id="${p.petition_id}" ${isMet ? 'disabled' : ''}>
                    <i class="fa-solid fa-file-signature"></i> ${isMet ? 'Népszavazás Kiírva' : 'Aláírás'}
                </button>
            </div>
        `;

        item.querySelector('.petition-sign-btn')?.addEventListener('click', () => signParliamentPetition(p.petition_id));
        container.appendChild(item);
    });
}

async function signParliamentPetition(petitionId) {
    const res = await postNui('parliament:signRecallPetition', { petitionId: petitionId });
    if (res && res.success) {
        playWebBeep(780, 'sine', 0.05);
        showNotification({ type: 'success', title: 'ALÁÍRÁS SIKERES', message: 'Támogattad a tisztviselő visszahívására irányuló kezdeményezést.' });
        refreshParliamentOverview();
    } else {
        showNotification({ type: 'error', title: 'ALÁÍRÁS SIKERTELEN', message: res?.error || 'Már aláírtad ezt a petíciót vagy érvénytelen állampolgár státusz.' });
    }
}

function openParliamentRecallModal() {
    const modal = document.getElementById('parliament-submodal-recall');
    if (modal) modal.classList.remove('hidden');
}

function closeParliamentRecallModal() {
    const modal = document.getElementById('parliament-submodal-recall');
    if (modal) modal.classList.add('hidden');
}

async function submitParliamentRecall() {
    const officeSelect = document.getElementById('parliament-recall-office-select');
    const reasonInput = document.getElementById('parliament-recall-reason-input');

    const office = officeSelect ? officeSelect.value : 'mayor';
    const reason = reasonInput ? reasonInput.value.trim() : '';

    if (reason.length < 10) {
        showNotification({ type: 'warning', title: 'RÖVID INDOKLÁS', message: 'Kérlek indokold a visszahívást legalább 10 karakterben!' });
        return;
    }

    const submitBtn = document.getElementById('parliament-recall-submit-btn');
    lockButtonAction(submitBtn, async () => {
        const res = await postNui('parliament:fileRecallPetition', {
            officeId: office,
            reason: reason
        });

        if (res && res.success) {
            playWebBeep(920, 'sine', 0.1);
            showNotification({ type: 'success', title: 'PETÍCIÓ MEGNYITVA', message: 'Visszahívási petíció hivatalosan bejegyezve az aláírásgyűjtéshez.' });
            if (reasonInput) reasonInput.value = '';
            closeParliamentRecallModal();
            refreshParliamentOverview();
        } else {
            showNotification({ type: 'error', title: 'PETÍCIÓ SIKERTELEN', message: res?.error || 'Nem sikerült elindítani a petíciót.' });
        }
    });
}

// 12E. Real Estate Blind-Auction & Stewardship Portal Controller
function openPropertyPortal(payload) {
    NyxState.property.isOpen = true;
    const overlay = document.getElementById('property-portal-overlay');
    if (overlay) overlay.classList.remove('hidden');

    if (payload && payload.activeTab) {
        NyxState.property.activeTab = payload.activeTab;
    }

    setPropertyTab(NyxState.property.activeTab || 'auctions');

    if (payload && payload.data) {
        applyPropertyOverviewData(payload.data);
    } else {
        refreshPropertyPortalOverview();
    }
}

function closePropertyPortal() {
    NyxState.property.isOpen = false;
    const overlay = document.getElementById('property-portal-overlay');
    if (overlay) overlay.classList.add('hidden');

    closeAuctionBidModal();
    closeAssignStewardModal();

    postNui('closePropertyPortal', {});
}

function setPropertyTab(tabName) {
    NyxState.property.activeTab = tabName;

    // Update Tab Buttons
    document.querySelectorAll('#property-portal-overlay .tab-btn').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-tab') === tabName);
    });

    // Update Tab Panes
    const auctionsPane = document.getElementById('prop-tab-auctions');
    const taxPane = document.getElementById('prop-tab-taxation');
    const stewardPane = document.getElementById('prop-tab-stewardship');

    if (auctionsPane) auctionsPane.classList.toggle('hidden', tabName !== 'auctions');
    if (taxPane) taxPane.classList.toggle('hidden', tabName !== 'taxation');
    if (stewardPane) stewardPane.classList.toggle('hidden', tabName !== 'stewardship');

    playWebBeep(640, 'sine', 0.04);

    if (tabName === 'auctions') {
        renderPropertyAuctions();
    } else if (tabName === 'taxation') {
        renderOwnedProperties();
    } else if (tabName === 'stewardship') {
        renderPropertyStewardship();
    }
}

async function refreshPropertyPortalOverview() {
    const res = await postNui('property:getOverview', {});
    if (res && res.success) {
        applyPropertyOverviewData(res);
    }
}

function applyPropertyOverviewData(data) {
    NyxState.property.citizenId = data.citizenId || null;
    NyxState.property.citizenName = data.citizenName || 'Állampolgár';
    NyxState.property.citizenBalance = Number(data.citizenBalance) || 0;
    NyxState.property.auctions = data.auctions || [];
    NyxState.property.ownedProperties = data.ownedProperties || [];
    NyxState.property.stewardship = data.stewardship || { delegates: [], managedProperties: [], ownedProperties: [] };
    NyxState.property.reclamationLogs = data.reclamationLogs || [];

    // Header badge updates
    const nameEl = document.getElementById('prop-citizen-name');
    if (nameEl) nameEl.textContent = NyxState.property.citizenName;

    const balEl = document.getElementById('prop-citizen-balance');
    if (balEl) balEl.textContent = formatCurrency(NyxState.property.citizenBalance);

    // Refresh active tab view
    if (NyxState.property.activeTab === 'auctions') {
        renderPropertyAuctions();
    } else if (NyxState.property.activeTab === 'taxation') {
        renderOwnedProperties();
    } else if (NyxState.property.activeTab === 'stewardship') {
        renderPropertyStewardship();
    }
}

function renderPropertyAuctions() {
    const grid = document.getElementById('prop-auctions-grid');
    if (!grid) return;

    grid.innerHTML = '';
    const query = (NyxState.property.searchQuery || '').toLowerCase();
    const typeFilter = NyxState.property.typeFilter || 'all';

    const filtered = (NyxState.property.auctions || []).filter(a => {
        const matchesQuery = !query || 
            (a.propertyLabel && a.propertyLabel.toLowerCase().includes(query)) ||
            (a.propertyCode && a.propertyCode.toLowerCase().includes(query)) ||
            (a.zoneId && a.zoneId.toLowerCase().includes(query));
        const matchesType = typeFilter === 'all' || (a.propertyType && a.propertyType.toLowerCase() === typeFilter);
        return matchesQuery && matchesType;
    });

    if (filtered.length === 0) {
        grid.innerHTML = `<div class="table-empty-notice"><i class="fa-solid fa-gavel"></i> Jelenleg nincs aktív önkormányzati ingatlanárverés a megadott szűrési feltételekkel.</div>`;
        return;
    }

    filtered.forEach(a => {
        const card = document.createElement('div');
        card.className = `auction-item-card ${a.hasPlacedBid ? 'has-bid' : ''}`;

        const endsAtMs = new Date(a.endsAt).getTime();
        const nowMs = Date.now();
        const diffSec = Math.max(0, Math.floor((endsAtMs - nowMs) / 1000));
        const hours = Math.floor(diffSec / 3600);
        const mins = Math.floor((diffSec % 3600) / 60);
        const timeStr = diffSec <= 0 ? 'LEJÁRT' : `${hours}ó ${mins}p`;

        card.innerHTML = `
            <div class="auction-card-header">
                <div class="auction-title-block">
                    <span class="auction-prop-label">${escapeHtml(a.propertyLabel || 'Ingatlan')}</span>
                    <span class="auction-prop-sub"><i class="fa-solid fa-map-pin"></i> ${escapeHtml(a.zoneId || 'LS Metro')} &bull; <code>${escapeHtml(a.propertyCode || '')}</code></span>
                </div>
                <span class="badge ${a.hasPlacedBid ? 'badge-success' : 'badge-primary'}">${a.hasPlacedBid ? 'Licitáltál' : 'Vakárverés'}</span>
            </div>

            <div class="auction-specs-grid">
                <div class="spec-cell">
                    <span class="spec-cell-label">Becsült Érték</span>
                    <span class="spec-cell-val">${formatCurrency(a.valuationPrice || 0)}</span>
                </div>
                <div class="spec-cell">
                    <span class="spec-cell-label">Kikiáltási Ár</span>
                    <span class="spec-cell-val text-cyan">${formatCurrency(a.minimumBid || 0)}</span>
                </div>
                <div class="spec-cell">
                    <span class="spec-cell-label">Telekterület</span>
                    <span class="spec-cell-val">${Math.floor(a.landAreaSqm || 150)} m²</span>
                </div>
                <div class="spec-cell">
                    <span class="spec-cell-label">Titkos Licitek</span>
                    <span class="spec-cell-val">${a.totalBidsPlaced || 0} letét</span>
                </div>
            </div>

            <div class="auction-sealed-status-row">
                <span><i class="fa-solid fa-user-shield"></i> Saját titkos letét:</span>
                <strong class="${a.hasPlacedBid ? 'text-success' : 'text-muted'}">${a.hasPlacedBid ? formatCurrency(a.mySealedBid || 0) : 'Nincs licit'}</strong>
            </div>

            <div class="auction-timer-row">
                <span><i class="fa-solid fa-clock"></i> Hátralévő idő:</span>
                <span class="auction-timer-val">${timeStr}</span>
            </div>

            <button class="btn btn-primary btn-block prop-place-bid-btn" data-auction-id="${a.auctionId}">
                <i class="fa-solid fa-coins"></i> ${a.hasPlacedBid ? 'Licit Emelése' : 'Zárt Licit Letétbe Helyezése'}
            </button>
        `;

        const bidBtn = card.querySelector('.prop-place-bid-btn');
        if (bidBtn) {
            bidBtn.addEventListener('click', () => openAuctionBidModal(a));
        }

        grid.appendChild(card);
    });
}

function renderOwnedProperties() {
    const list = document.getElementById('prop-owned-list');
    if (!list) return;

    list.innerHTML = '';
    const owned = NyxState.property.ownedProperties || [];

    // Update KPI Ribbon
    const ownedCountEl = document.getElementById('prop-kpi-owned-count');
    if (ownedCountEl) ownedCountEl.textContent = owned.length;

    let totalArrears = 0;
    let holdingMult = 1.0;
    if (owned.length > 1) {
        holdingMult = Math.pow(1.5, owned.length - 1);
    }
    owned.forEach(p => {
        totalArrears += (Number(p.delinquentAmount) || 0);
    });

    const holdingEl = document.getElementById('prop-kpi-holding-mult');
    if (holdingEl) holdingEl.textContent = holdingMult.toFixed(2) + 'x';

    const arrearsEl = document.getElementById('prop-kpi-total-arrears');
    if (arrearsEl) arrearsEl.textContent = formatCurrency(totalArrears);

    const query = (NyxState.property.searchQuery || '').toLowerCase();
    const statusFilter = NyxState.property.statusFilter || 'all';

    const filtered = owned.filter(p => {
        const matchesQuery = !query || 
            (p.label && p.label.toLowerCase().includes(query)) ||
            (p.code && p.code.toLowerCase().includes(query)) ||
            (p.zoneId && p.zoneId.toLowerCase().includes(query));
        
        let matchesStatus = true;
        if (statusFilter === 'pristine') {
            matchesStatus = (Number(p.maintenanceCondition || 100) >= 95 && Number(p.delinquencyTier || 0) === 0);
        } else if (statusFilter === 'delinquent') {
            matchesStatus = (Number(p.delinquencyTier || 0) > 0 || Number(p.delinquentAmount || 0) > 0);
        } else if (statusFilter === 'auctioned') {
            matchesStatus = (p.reclaimedForAuction === true);
        }

        return matchesQuery && matchesStatus;
    });

    if (filtered.length === 0) {
        list.innerHTML = `<div class="table-empty-notice"><i class="fa-solid fa-house-chimney"></i> Nincs a szűrésnek megfelelő saját ingatlan a nyilvántartásban.</div>`;
        return;
    }

    filtered.forEach(p => {
        const card = document.createElement('div');
        const tier = Number(p.delinquencyTier) || 0;
        const arrears = Number(p.delinquentAmount) || 0;
        const cond = Math.min(100, Math.max(0, Number(p.maintenanceCondition) || 100));

        let tierClass = 'delinquent-clean';
        if (tier >= 3) tierClass = 'delinquent-danger';
        else if (tier > 0) tierClass = 'delinquent-warning';

        card.className = `owned-prop-card ${tierClass}`;

        let condFillClass = 'good';
        if (cond < 50) condFillClass = 'bad';
        else if (cond < 80) condFillClass = 'medium';

        card.innerHTML = `
            <div class="owned-prop-info">
                <span class="owned-prop-label">${escapeHtml(p.label || 'Ingatlan')}</span>
                <span class="owned-prop-sub"><code>${escapeHtml(p.code || '')}</code> &bull; ${escapeHtml(p.zoneId || '')} &bull; ${Math.floor(p.landAreaSqm || 150)} m²</span>
            </div>

            <div class="condition-progress-block">
                <div class="spec-cell-label">Szerkezet: ${cond.toFixed(1)}%</div>
                <div class="condition-track">
                    <div class="condition-fill ${condFillClass}" style="width: ${cond}%;"></div>
                </div>
            </div>

            <div>
                <span class="badge ${p.badge ? p.badge.badgeClass : (tier > 0 ? 'badge-danger' : 'badge-success')}">
                    ${p.badge ? p.badge.statusLabel : (tier > 0 ? `Fokozat ${tier}` : 'Rendezett')}
                </span>
                ${arrears > 0 ? `<div class="text-danger" style="font-size: 11px; margin-top: 3px;">Hátralék: ${formatCurrency(arrears)}</div>` : ''}
            </div>

            <div>
                <span class="spec-cell-label">Gondnok</span>
                <div style="font-size: 12px; font-weight: 600; color: var(--color-text-primary);">
                    ${p.stewardDelegateCitizenId ? `<i class="fa-solid fa-user-shield text-cyan"></i> ${escapeHtml(p.stewardDelegateCitizenId)}` : '<span class="text-muted">Nincs kijelölve</span>'}
                </div>
            </div>

            <div class="owned-actions-group">
                ${arrears > 0 ? `<button class="btn btn-danger btn-sm prop-pay-arrears-btn" data-id="${p.id}"><i class="fa-solid fa-receipt"></i> Befizetés</button>` : ''}
                ${cond < 100 ? `<button class="btn btn-warning btn-sm prop-repair-btn" data-id="${p.id}"><i class="fa-solid fa-hammer"></i> Felújítás</button>` : ''}
                <button class="btn btn-secondary btn-sm prop-assign-btn" data-id="${p.id}"><i class="fa-solid fa-user-gear"></i> Gondnok</button>
            </div>
        `;

        const payBtn = card.querySelector('.prop-pay-arrears-btn');
        if (payBtn) payBtn.addEventListener('click', () => handlePayArrears(p.id));

        const repairBtn = card.querySelector('.prop-repair-btn');
        if (repairBtn) repairBtn.addEventListener('click', () => handleRepairCondition(p.id));

        const assignBtn = card.querySelector('.prop-assign-btn');
        if (assignBtn) assignBtn.addEventListener('click', () => openAssignStewardModal(p));

        list.appendChild(card);
    });
}

function renderPropertyStewardship() {
    const delegatesList = document.getElementById('prop-delegates-list');
    const managedList = document.getElementById('prop-managed-properties-list');
    const logsList = document.getElementById('prop-reclamation-logs-list');

    const stewardship = NyxState.property.stewardship || { delegates: [], managedProperties: [] };
    const delegates = stewardship.delegates || [];
    const managed = stewardship.managedProperties || [];
    const logs = NyxState.property.reclamationLogs || [];

    // Delegates badge
    const delBadge = document.getElementById('prop-delegates-count-badge');
    if (delBadge) delBadge.textContent = `${delegates.length} megbízott`;

    const manBadge = document.getElementById('prop-managed-count-badge');
    if (manBadge) manBadge.textContent = `${managed.length} ingatlan`;

    if (delegatesList) {
        delegatesList.innerHTML = '';
        if (delegates.length === 0) {
            delegatesList.innerHTML = `<div class="table-empty-notice"><i class="fa-solid fa-users"></i> Nincs kijelölt megbízottad.</div>`;
        } else {
            delegates.forEach(d => {
                const item = document.createElement('div');
                item.className = 'delegate-card-item';
                item.innerHTML = `
                    <div>
                        <div style="font-weight: 700; color: var(--color-text-primary);"><i class="fa-solid fa-user-shield text-cyan"></i> ${escapeHtml(d.delegate_citizen_id)} (${escapeHtml((d.first_name || '') + ' ' + (d.last_name || ''))})</div>
                        <div style="font-size: 11px; color: var(--color-text-secondary);">Hatókör: <code>${escapeHtml(d.scope || 'all')}</code> &bull; ${escapeHtml(d.notes || 'Meghatalmazva')}</div>
                    </div>
                    <button class="btn btn-danger btn-sm prop-revoke-delegate-btn" data-citid="${d.delegate_citizen_id}"><i class="fa-solid fa-user-xmark"></i> Visszavonás</button>
                `;
                const revBtn = item.querySelector('.prop-revoke-delegate-btn');
                if (revBtn) revBtn.addEventListener('click', () => handleRevokeDelegate(d.delegate_citizen_id));
                delegatesList.appendChild(item);
            });
        }
    }

    if (managedList) {
        managedList.innerHTML = '';
        if (managed.length === 0) {
            managedList.innerHTML = `<div class="table-empty-notice"><i class="fa-solid fa-shield-halved"></i> Jelenleg nem vagy kijelölt gondnok más állampolgár ingatlanán.</div>`;
        } else {
            managed.forEach(m => {
                const item = document.createElement('div');
                item.className = 'managed-card-item';
                item.innerHTML = `
                    <div>
                        <div style="font-weight: 700; color: var(--color-text-primary);"><i class="fa-solid fa-building text-success"></i> ${escapeHtml(m.label || m.property_code)}</div>
                        <div style="font-size: 11px; color: var(--color-text-secondary);">Tulajdonos: <code>${escapeHtml(m.owner_citizen_id || 'Ismeretlen')}</code> &bull; Státusz: <span class="badge badge-success">${escapeHtml(m.inactivity_status || 'delegated')}</span></div>
                    </div>
                    <span class="badge badge-outline"><i class="fa-solid fa-shield"></i> Védett</span>
                `;
                managedList.appendChild(item);
            });
        }
    }

    if (logsList) {
        logsList.innerHTML = '';
        if (logs.length === 0) {
            logsList.innerHTML = `<div class="table-empty-notice"><i class="fa-solid fa-clock-rotate-left"></i> Nincs rögzített inaktivitási bejegyzés.</div>`;
        } else {
            logs.forEach(l => {
                const item = document.createElement('div');
                let actClass = '';
                if (l.action === 'forfeited_to_auction') actClass = 'forfeited';
                else if (l.action === 'warning_cleared') actClass = 'cleared';
                item.className = `reclamation-log-item ${actClass}`;
                item.innerHTML = `
                    <div>
                        <strong style="color: var(--color-text-primary); text-transform: uppercase;">${escapeHtml(l.action || '')}</strong>
                        <div style="color: var(--color-text-secondary); font-size: 11px;">Eszköz: <code>${escapeHtml(l.asset_id || '')}</code> (${escapeHtml(l.asset_type || '')}) &bull; ${escapeHtml(l.notes || '')}</div>
                    </div>
                    <span class="badge badge-outline">${l.timestamp ? new Date(l.timestamp * 1000).toLocaleDateString() : 'Nemrég'}</span>
                `;
                logsList.appendChild(item);
            });
        }
    }
}

// Modal: Place Sealed Blind Auction Bid
function openAuctionBidModal(auction) {
    NyxState.property.selectedAuction = auction;
    const modal = document.getElementById('property-submodal-bid');
    if (!modal) return;

    const titleEl = document.getElementById('prop-bid-target-title');
    if (titleEl) titleEl.textContent = `${auction.propertyLabel} (${auction.propertyCode})`;

    const floorEl = document.getElementById('prop-bid-min-floor');
    if (floorEl) floorEl.textContent = formatCurrency(auction.minimumBid || 0);

    const mineEl = document.getElementById('prop-bid-current-mine');
    if (mineEl) mineEl.textContent = auction.hasPlacedBid ? formatCurrency(auction.mySealedBid || 0) : '$0.00';

    const availEl = document.getElementById('prop-bid-bank-avail');
    if (availEl) availEl.textContent = formatCurrency(NyxState.property.citizenBalance || 0);

    const inputEl = document.getElementById('property-bid-input');
    if (inputEl) {
        inputEl.value = Math.max(Number(auction.minimumBid) || 0, Number(auction.mySealedBid) || 0) + 500;
    }

    const hintEl = document.getElementById('prop-bid-error-hint');
    if (hintEl) hintEl.classList.add('hidden');

    modal.classList.remove('hidden');
    playWebBeep(720, 'sine', 0.05);
}

function closeAuctionBidModal() {
    NyxState.property.selectedAuction = null;
    const modal = document.getElementById('property-submodal-bid');
    if (modal) modal.classList.add('hidden');
}

async function submitAuctionBid() {
    const auction = NyxState.property.selectedAuction;
    if (!auction) return;

    const inputEl = document.getElementById('property-bid-input');
    const bidAmount = Number(inputEl ? inputEl.value : 0);

    if (bidAmount < (Number(auction.minimumBid) || 0)) {
        const hintEl = document.getElementById('prop-bid-error-hint');
        if (hintEl) {
            hintEl.textContent = `A licitnek el kell érnie a kikiáltási árat (${formatCurrency(auction.minimumBid)})!`;
            hintEl.classList.remove('hidden');
        }
        return;
    }

    const submitBtn = document.getElementById('property-bid-submit-btn');
    lockButtonAction(submitBtn, async () => {
        const res = await postNui('property:placeBid', {
            auctionId: auction.auctionId,
            bidAmount: bidAmount
        });

        if (res && res.success) {
            playWebBeep(980, 'sine', 0.1);
            showNotification({ type: 'success', title: 'ZÁRT LICIT ELFOGADVA', message: `Sikeresen elhelyezted a(z) ${formatCurrency(bidAmount)} összegű zárt letétet!` });
            closeAuctionBidModal();
            refreshPropertyPortalOverview();
        } else {
            showNotification({ type: 'error', title: 'LICIT SIKERTELEN', message: res?.error || 'Nem sikerült letétbe helyezni a licitet.' });
        }
    });
}

// Modal: Assign Property Steward
function openAssignStewardModal(prop) {
    NyxState.property.selectedProperty = prop;
    const modal = document.getElementById('property-submodal-assign');
    if (!modal) return;

    const labelEl = document.getElementById('prop-assign-prop-label');
    if (labelEl) labelEl.value = `${prop.label} (${prop.code})`;

    const selectEl = document.getElementById('property-assign-delegate-select');
    if (selectEl) {
        selectEl.innerHTML = '<option value="">-- Nincs gondnok (Kijelölés törlése) --</option>';
        const delegates = (NyxState.property.stewardship && NyxState.property.stewardship.delegates) || [];
        delegates.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.delegate_citizen_id;
            opt.textContent = `${d.delegate_citizen_id} - ${d.first_name || ''} ${d.last_name || ''} (${d.scope || 'all'})`;
            if (prop.stewardDelegateCitizenId === d.delegate_citizen_id) {
                opt.selected = true;
            }
            selectEl.appendChild(opt);
        });
    }

    modal.classList.remove('hidden');
    playWebBeep(720, 'sine', 0.05);
}

function closeAssignStewardModal() {
    NyxState.property.selectedProperty = null;
    const modal = document.getElementById('property-submodal-assign');
    if (modal) modal.classList.add('hidden');
}

async function submitAssignSteward() {
    const prop = NyxState.property.selectedProperty;
    if (!prop) return;

    const selectEl = document.getElementById('property-assign-delegate-select');
    const delegateId = selectEl ? selectEl.value : null;

    const submitBtn = document.getElementById('property-assign-submit-btn');
    lockButtonAction(submitBtn, async () => {
        const res = await postNui('property:assignSteward', {
            propertyId: prop.id,
            delegateCitizenId: delegateId || null
        });

        if (res && res.success) {
            playWebBeep(880, 'sine', 0.08);
            showNotification({ type: 'success', title: 'GONDNOK FRISSÍTVE', message: 'Az ingatlan gondnoki megbízása rögzítésre került.' });
            closeAssignStewardModal();
            refreshPropertyPortalOverview();
        } else {
            showNotification({ type: 'error', title: 'SIKERTELEN KIJELÖLÉS', message: res?.error || 'Nem sikerült kijelölni a gondnokot.' });
        }
    });
}

async function handlePayArrears(propertyId) {
    openDialog({
        title: 'Adóhátralék Rendezése',
        message: 'Biztosan befizeted az esedékes ingatlanadó hátralékot a városi kincstárnak?',
        onConfirm: async () => {
            const res = await postNui('property:payArrears', { propertyId: propertyId });
            if (res && res.success) {
                playWebBeep(980, 'sine', 0.1);
                showNotification({ type: 'success', title: 'HÁTRALÉK RENDEZVE', message: 'Az adóhátralék sikeresen kiegyenlítve!' });
                refreshPropertyPortalOverview();
            } else {
                showNotification({ type: 'error', title: 'BEFIZETÉS SIKERTELEN', message: res?.error || 'Nincs fedezet vagy hiba történt.' });
            }
        }
    });
}

async function handleRepairCondition(propertyId) {
    openDialog({
        title: 'Szerkezeti Felújítás',
        message: 'Megrendeled az ingatlan azonnali szerkezeti felújítását (100% állapot) a Közművektől?',
        onConfirm: async () => {
            const res = await postNui('property:repairCondition', { propertyId: propertyId });
            if (res && res.success) {
                playWebBeep(980, 'sine', 0.1);
                showNotification({ type: 'success', title: 'FELÚJÍTÁS SIKERES', message: 'Az ingatlan szerkezeti állapota 100%-ra visszaállítva!' });
                refreshPropertyPortalOverview();
            } else {
                showNotification({ type: 'error', title: 'FELÚJÍTÁS SIKERTELEN', message: res?.error || 'Nincs fedezet vagy nem vagy tulajdonos.' });
            }
        }
    });
}

async function handleAppointDelegate() {
    const citIdInput = document.getElementById('prop-input-delegate-citid');
    const scopeSelect = document.getElementById('prop-select-delegate-scope');
    const notesInput = document.getElementById('prop-input-delegate-notes');

    const delegateCitizenId = citIdInput ? citIdInput.value.trim() : '';
    const scope = scopeSelect ? scopeSelect.value : 'all';
    const notes = notesInput ? notesInput.value.trim() : '';

    if (!delegateCitizenId || delegateCitizenId.length < 3) {
        showNotification({ type: 'warning', title: 'ÉRVÉNYTELEN AZONOSÍTÓ', message: 'Kérlek adj meg egy érvényes Citizen ID-t!' });
        return;
    }

    const btn = document.getElementById('prop-btn-appoint-delegate');
    lockButtonAction(btn, async () => {
        const res = await postNui('property:registerDelegate', {
            delegateCitizenId: delegateCitizenId,
            scope: scope,
            notes: notes
        });

        if (res && res.success) {
            playWebBeep(920, 'sine', 0.1);
            showNotification({ type: 'success', title: 'MEGHATALMAZÁS RÖGZÍTVE', message: `Gondnoki megbízás bejegyezve (${delegateCitizenId}).` });
            if (citIdInput) citIdInput.value = '';
            if (notesInput) notesInput.value = '';
            refreshPropertyPortalOverview();
        } else {
            showNotification({ type: 'error', title: 'MEGBÍZÁS SIKERTELEN', message: res?.error || 'Nem sikerült bejegyezni a megbízást.' });
        }
    });
}

async function handleRevokeDelegate(delegateCitizenId) {
    openDialog({
        title: 'Meghatalmazás Visszavonása',
        message: `Biztosan visszavonod a(z) ${delegateCitizenId} polgár gondnoki meghatalmazását?`,
        onConfirm: async () => {
            const res = await postNui('property:revokeDelegate', {
                delegateCitizenId: delegateCitizenId
            });
            if (res && res.success) {
                playWebBeep(880, 'sine', 0.08);
                showNotification({ type: 'info', title: 'MEGHATALMAZÁS VISSZAVONVA', message: 'A gondnoki megbízás sikeresen törölve.' });
                refreshPropertyPortalOverview();
            } else {
                showNotification({ type: 'error', title: 'HIBA', message: res?.error || 'Nem sikerült visszavonni.' });
            }
        }
    });
}

// ================================================================
// 12E. 3D WAREHOUSE MATRIX & ELASTIC MARKET MONITOR (`nyx_logistics`)
// ================================================================

function openMarketMonitor(payload = {}) {
    NyxState.logistics.isOpen = true;
    const overlay = document.getElementById('logistics-matrix-overlay');
    if (overlay) {
        overlay.classList.remove('hidden');
    }

    if (payload.warehouseId) {
        NyxState.logistics.selectedWarehouseId = payload.warehouseId;
    }
    const targetTab = payload.activeTab || 'matrix';
    setLogisticsTab(targetTab);

    refreshLogisticsMatrixOverview(NyxState.logistics.selectedWarehouseId);
    refreshLogisticsMarketOverview();
    refreshLogisticsArbitrageRoutes();
}

function closeMarketMonitor() {
    NyxState.logistics.isOpen = false;
    const overlay = document.getElementById('logistics-matrix-overlay');
    if (overlay) {
        overlay.classList.add('hidden');
    }
    closeReserveSlotModal();
    postNui('closeMarketMonitor', {});
}

function setLogisticsTab(tabName) {
    NyxState.logistics.activeTab = tabName;

    document.querySelectorAll('#logistics-matrix-overlay .modal-tabs .tab-btn').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-tab') === tabName);
    });

    const panes = {
        matrix: document.getElementById('logistics-tab-matrix'),
        market: document.getElementById('logistics-tab-market'),
        arbitrage: document.getElementById('logistics-tab-arbitrage')
    };

    Object.entries(panes).forEach(([name, pane]) => {
        if (pane) pane.classList.toggle('hidden', name !== tabName);
    });

    if (tabName === 'matrix') {
        renderLogistics3DShelfMatrix();
    } else if (tabName === 'market') {
        renderLogisticsMarketOverview();
    } else if (tabName === 'arbitrage') {
        renderLogisticsArbitrageRoutes();
        renderLogisticsMyDispatches();
    }
}

async function refreshLogisticsMatrixOverview(warehouseId) {
    const res = await postNui('logistics:getMatrixOverview', { warehouseId: warehouseId || NyxState.logistics.selectedWarehouseId });
    if (res && res.success) {
        NyxState.logistics.warehouses = res.warehouses || [];
        NyxState.logistics.shelves = res.shelves || [];
        NyxState.logistics.nodes = res.nodes || [];
        NyxState.logistics.selectedWarehouseId = res.selectedWarehouseId || warehouseId;

        // Populate Warehouse Select
        const whSelect = document.getElementById('logistics-wh-select');
        if (whSelect) {
            whSelect.innerHTML = '';
            NyxState.logistics.warehouses.forEach(wh => {
                const opt = document.createElement('option');
                opt.value = wh.id;
                opt.textContent = `${wh.name} (${wh.occupiedSlots}/${wh.totalSlots} rekesz)`;
                if (wh.id === NyxState.logistics.selectedWarehouseId) opt.selected = true;
                whSelect.appendChild(opt);
            });
        }

        // Header Warehouse Badge
        const currentWhObj = NyxState.logistics.warehouses.find(w => w.id === NyxState.logistics.selectedWarehouseId);
        const whNameEl = document.getElementById('logistics-header-wh-name');
        if (whNameEl && currentWhObj) {
            whNameEl.textContent = currentWhObj.name;
        }

        // Populate Shelf Select
        const shelfSelect = document.getElementById('logistics-shelf-select');
        if (shelfSelect) {
            shelfSelect.innerHTML = '';
            NyxState.logistics.shelves.forEach(sh => {
                const opt = document.createElement('option');
                opt.value = sh.id;
                opt.textContent = sh.label || sh.id;
                shelfSelect.appendChild(opt);
            });
            if (NyxState.logistics.shelves.length > 0 && !NyxState.logistics.selectedShelfId) {
                NyxState.logistics.selectedShelfId = NyxState.logistics.shelves[0].id;
            }
        }

        renderLogistics3DShelfMatrix();
    }
}

function renderLogistics3DShelfMatrix() {
    const stage = document.getElementById('logistics-3d-viewport');
    if (!stage) return;
    stage.innerHTML = '';

    const currentShelfId = NyxState.logistics.selectedShelfId || (NyxState.logistics.shelves[0] && NyxState.logistics.shelves[0].id);
    const shelfNodes = NyxState.logistics.nodes.filter(n => !currentShelfId || n.shelfId === currentShelfId);

    const container = document.createElement('div');
    container.className = 'shelf-isometric-container';

    // Rack metal upright frames
    const uprightL = document.createElement('div');
    uprightL.className = 'rack-frame-upright left';
    const uprightR = document.createElement('div');
    uprightR.className = 'rack-frame-upright right';
    container.appendChild(uprightL);
    container.appendChild(uprightR);

    // Beams for tiers (3 tiers default)
    [1, 2, 3].forEach(t => {
        const beam = document.createElement('div');
        beam.className = 'rack-tier-beam';
        beam.style.top = `${(3 - t) * 65 + 60}px`;
        container.appendChild(beam);
    });

    // Render Slots
    const centerX = 180;
    const centerY = 140;

    shelfNodes.forEach(node => {
        const slotEl = document.createElement('div');
        const isSelected = NyxState.logistics.selectedNodeId === node.id;
        const statusClass = node.status || 'available';
        const tempClass = node.temperatureZone === 'cold_storage' ? 'cold' : '';

        slotEl.className = `matrix-slot-box ${statusClass} ${tempClass} ${isSelected ? 'selected' : ''}`;
        slotEl.dataset.nodeId = node.id;

        // Positioning from isoX, isoY
        const posX = centerX + (node.isoX || 0);
        const posY = centerY + (node.isoY || 0);
        slotEl.style.left = `${posX}px`;
        slotEl.style.top = `${posY}px`;
        slotEl.style.zIndex = node.layer || 10;

        let iconClass = 'fa-solid fa-box-open';
        if (node.status === 'occupied') iconClass = 'fa-solid fa-box-archive';
        else if (node.status === 'reserved') iconClass = 'fa-solid fa-lock';
        else if (node.temperatureZone === 'cold_storage') iconClass = 'fa-solid fa-snowflake';

        slotEl.innerHTML = `
            <i class="${iconClass} slot-icon"></i>
            <span class="slot-code">T${node.tier}-S${node.slot}</span>
        `;

        slotEl.addEventListener('click', () => {
            selectLogisticsShelfSlot(node.id);
        });

        container.appendChild(slotEl);
    });

    stage.appendChild(container);

    // Auto-select first or previously selected node
    if (!NyxState.logistics.selectedNodeId && shelfNodes.length > 0) {
        selectLogisticsShelfSlot(shelfNodes[0].id);
    } else if (NyxState.logistics.selectedNodeId) {
        selectLogisticsShelfSlot(NyxState.logistics.selectedNodeId);
    }
}

function selectLogisticsShelfSlot(nodeId) {
    NyxState.logistics.selectedNodeId = nodeId;
    const node = NyxState.logistics.nodes.find(n => n.id === nodeId);
    NyxState.logistics.selectedNode = node;

    // Visual selection highlighting
    document.querySelectorAll('.matrix-slot-box').forEach(el => {
        el.classList.toggle('selected', el.dataset.nodeId === nodeId);
    });

    if (!node) return;

    // Update Telemetry Panel
    const statusBadge = document.getElementById('logistics-slot-status-badge');
    if (statusBadge) {
        let badgeClass = 'badge-success';
        let label = 'SZABAD';
        if (node.status === 'occupied') {
            badgeClass = 'badge-warning';
            label = 'FOGLALT';
        } else if (node.status === 'reserved') {
            badgeClass = 'badge-primary';
            label = 'FENNTARTVA';
        }
        statusBadge.className = `badge ${badgeClass}`;
        statusBadge.textContent = label;
    }

    const nodeEl = document.getElementById('logistics-tel-node-id');
    if (nodeEl) nodeEl.textContent = node.id || '--';

    const shelfEl = document.getElementById('logistics-tel-shelf-label');
    if (shelfEl) shelfEl.textContent = node.shelfLabel || 'Shelf Unit';

    const tierSlotEl = document.getElementById('logistics-tel-tier-slot');
    if (tierSlotEl) tierSlotEl.textContent = `T${node.tier} / S${node.slot}`;

    const tempEl = document.getElementById('logistics-tel-temp-zone');
    if (tempEl) tempEl.textContent = node.temperatureZone || 'ambient';

    const coordsEl = document.getElementById('logistics-tel-world-coords');
    if (coordsEl && node.worldCoords) {
        coordsEl.textContent = `X: ${node.worldCoords.x.toFixed(2)} | Y: ${node.worldCoords.y.toFixed(2)} | Z: ${node.worldCoords.z.toFixed(2)}`;
    }

    // Stored item display
    const emptyState = document.getElementById('logistics-slot-empty-state');
    const itemDetails = document.getElementById('logistics-slot-item-details');

    if (node.item && node.status === 'occupied') {
        if (emptyState) emptyState.classList.add('hidden');
        if (itemDetails) {
            itemDetails.classList.remove('hidden');
            const lbl = document.getElementById('logistics-item-label');
            if (lbl) lbl.textContent = node.item.label || node.item.itemId || 'Csomag';
            const idEl = document.getElementById('logistics-item-id');
            if (idEl) idEl.textContent = node.item.itemId || 'item_id';
            const countEl = document.getElementById('logistics-item-count');
            if (countEl) countEl.textContent = `${node.item.count || 1} db`;
            const weightEl = document.getElementById('logistics-item-weight');
            if (weightEl) weightEl.textContent = `${(node.item.weight || 10.0).toFixed(1)} kg`;
            const durEl = document.getElementById('logistics-item-durability');
            if (durEl) durEl.textContent = `${node.item.durability || 100}%`;
        }
    } else {
        if (emptyState) emptyState.classList.remove('hidden');
        if (itemDetails) itemDetails.classList.add('hidden');
    }
}

async function refreshLogisticsMarketOverview() {
    const res = await postNui('logistics:getMarketOverview', {
        zoneId: NyxState.logistics.zoneFilter
    });
    if (res && res.success) {
        NyxState.logistics.zones = res.zones || [];
        NyxState.logistics.commodities = res.commodities || [];
        NyxState.logistics.citywideCpi = res.citywideCpi || 1.00;

        const cpiBadge = document.getElementById('logistics-header-cpi');
        if (cpiBadge) {
            cpiBadge.innerHTML = `<i class="fa-solid fa-chart-line"></i> CPI: ${NyxState.logistics.citywideCpi.toFixed(2)}`;
        }

        renderLogisticsMarketOverview();
    }
}

function renderLogisticsMarketOverview() {
    // Zones KPI Grid
    const zonesGrid = document.getElementById('logistics-zones-kpi-grid');
    if (zonesGrid) {
        zonesGrid.innerHTML = '';
        NyxState.logistics.zones.forEach(z => {
            const card = document.createElement('div');
            card.className = 'zone-kpi-card';
            const badgeClass = z.badge ? z.badge.badgeClass : 'badge-success';
            const badgeLabel = z.badge ? z.badge.label : (z.healthStatus || 'EQUILIBRIUM');

            card.innerHTML = `
                <div class="zone-kpi-title">${escapeHtml(z.zoneName || z.zoneId)}</div>
                <div class="zone-kpi-metrics">
                    <span>CPI: <strong>${(z.cpi || 1.0).toFixed(2)}</strong></span>
                    <span>S/D: <strong>${(z.stockToDemandRatio || 1.0).toFixed(2)}</strong></span>
                </div>
                <div style="margin-top: 4px;">
                    <span class="badge ${badgeClass}" style="font-size: 10px;">${badgeLabel}</span>
                </div>
            `;
            zonesGrid.appendChild(card);
        });
    }

    renderLogisticsCommodityTable();
}

function renderLogisticsCommodityTable() {
    const tbody = document.getElementById('logistics-pricing-rows');
    if (!tbody) return;
    tbody.innerHTML = '';

    const query = (NyxState.logistics.marketSearchQuery || '').toLowerCase();
    const zoneFilter = NyxState.logistics.zoneFilter || 'all';
    const catFilter = NyxState.logistics.categoryFilter || 'all';

    const filtered = (NyxState.logistics.commodities || []).filter(item => {
        const matchQ = !query || (item.name || '').toLowerCase().includes(query) || (item.itemId || '').toLowerCase().includes(query);
        const matchZ = zoneFilter === 'all' || item.zoneId === zoneFilter;
        const matchC = catFilter === 'all' || item.category === catFilter;
        return matchQ && matchZ && matchC;
    });

    if (filtered.length === 0) {
        tbody.innerHTML = `<tr><td colspan="8" class="table-empty-notice"><i class="fa-solid fa-circle-exclamation"></i> Nincs a megadott szűrésnek megfelelő kereskedelmi árucikk.</td></tr>`;
        return;
    }

    filtered.forEach(c => {
        const tr = document.createElement('tr');
        const mult = c.priceMultiplier || 1.0;
        let multColor = 'var(--accent-emerald)';
        if (mult > 1.2) multColor = 'var(--accent-amber)';
        if (mult > 1.5) multColor = 'var(--accent-rose)';
        if (mult < 0.9) multColor = 'var(--accent-cyan)';

        const badgeClass = c.healthBadge ? c.healthBadge.badgeClass : 'badge-success';
        const badgeLabel = c.healthBadge ? c.healthBadge.label : 'EGYENSÚLY';

        tr.innerHTML = `
            <td><strong>${escapeHtml(c.name || c.itemId)}</strong><br><small class="text-muted"><code>${escapeHtml(c.itemId)}</code></small></td>
            <td>${escapeHtml(c.zoneName || c.zoneId)}</td>
            <td><span class="badge badge-outline">${escapeHtml(c.category || 'goods')}</span></td>
            <td>$${(c.basePrice || 0).toFixed(2)}</td>
            <td><strong style="color: ${multColor};">$${(c.currentPrice || 0).toFixed(2)}</strong></td>
            <td><span style="color: ${multColor}; font-weight: 700;">${mult.toFixed(2)}x</span></td>
            <td>${c.currentStock || 0} / ${Math.floor(c.effectiveDemand || 100)} db (${(c.stockToDemandRatio || 1.0).toFixed(2)})</td>
            <td><span class="badge ${badgeClass}">${badgeLabel}</span></td>
        `;
        tbody.appendChild(tr);
    });
}

async function refreshLogisticsArbitrageRoutes() {
    const res = await postNui('logistics:getArbitrageRoutes', {});
    if (res && res.success) {
        NyxState.logistics.arbitrageRoutes = res.routes || [];
        NyxState.logistics.myDispatches = res.myDispatches || [];
        renderLogisticsArbitrageRoutes();
        renderLogisticsMyDispatches();
    }
}

function renderLogisticsArbitrageRoutes() {
    const container = document.getElementById('logistics-arbitrage-cards');
    if (!container) return;
    container.innerHTML = '';

    const routes = NyxState.logistics.arbitrageRoutes || [];
    if (routes.length === 0) {
        container.innerHTML = `<div class="table-empty-notice"><i class="fa-solid fa-truck"></i> Jelenleg nincs aktív regionális arbitrázs lehetőség a piacon.</div>`;
        return;
    }

    routes.forEach(r => {
        const card = document.createElement('div');
        card.className = 'arbitrage-card';

        let ratingClass = 'badge-success';
        if (r.rating === 'EXCELLENT') ratingClass = 'badge-primary';
        else if (r.rating === 'MARGINAL') ratingClass = 'badge-warning';
        else if (r.rating === 'UNPROFITABLE') ratingClass = 'badge-danger';

        card.innerHTML = `
            <div class="arb-route-header">
                <div>
                    <div class="arb-route-path">
                        <span>${escapeHtml(r.originName || r.originWarehouseId)}</span>
                        <i class="fa-solid fa-arrow-right text-cyan"></i>
                        <span>${escapeHtml(r.destinationName || r.destinationZoneId)}</span>
                    </div>
                    <div class="arb-item-name">${escapeHtml(r.itemName || r.itemId)} (${r.recommendedUnits} db)</div>
                </div>
                <span class="badge ${ratingClass}">${escapeHtml(r.rating || 'PROFITABLE')}</span>
            </div>

            <div class="arb-numbers-grid">
                <div class="arb-num-col">
                    <span class="tel-label">Árrés / db:</span>
                    <span class="val text-cyan">+$${(r.unitSpread || 0).toFixed(2)}</span>
                </div>
                <div class="arb-num-col">
                    <span class="tel-label">Üzemanyag költség:</span>
                    <span class="val text-danger">-$${(r.fuelCost || 0).toFixed(2)}</span>
                </div>
                <div class="arb-num-col">
                    <span class="tel-label">Várható Tiszta Haszon:</span>
                    <span class="val text-success">+$${(r.projectedProfit || 0).toFixed(2)}</span>
                </div>
            </div>

            <button class="btn btn-primary btn-block btn-sm arb-claim-btn" data-route-id="${r.routeId}">
                <i class="fa-solid fa-truck-ramp-box"></i> Fuvarmegbízás Lefoglalása
            </button>
        `;

        const claimBtn = card.querySelector('.arb-claim-btn');
        if (claimBtn) {
            claimBtn.addEventListener('click', () => {
                lockButtonAction(claimBtn, async () => {
                    const res = await postNui('logistics:bookDispatch', {
                        originWarehouseId: r.originWarehouseId,
                        destinationZoneId: r.destinationZoneId,
                        itemId: r.itemId,
                        units: r.recommendedUnits,
                        unitCost: r.unitCost,
                        targetPrice: r.targetPrice,
                        projectedProfit: r.projectedProfit,
                        fuelSurcharge: r.fuelCost
                    });
                    if (res && res.success) {
                        playWebBeep(980, 'sine', 0.1);
                        showNotification({
                            type: 'success',
                            title: 'FUVAR LEFOGLALVA',
                            message: `${r.recommendedUnits} db ${r.itemName} fuvarmegbízás rögzítve!`
                        });
                        refreshLogisticsArbitrageRoutes();
                    } else {
                        showNotification({
                            type: 'error',
                            title: 'LEFOGLALÁS SIKERTELEN',
                            message: res?.error || 'Nem sikerült lefoglalni a fuvart.'
                        });
                    }
                });
            });
        }

        container.appendChild(card);
    });
}

function renderLogisticsMyDispatches() {
    const list = document.getElementById('logistics-my-dispatches-list');
    if (!list) return;
    list.innerHTML = '';

    const dispatches = NyxState.logistics.myDispatches || [];
    if (dispatches.length === 0) {
        list.innerHTML = `<div class="table-empty-notice" style="padding: 10px;"><i class="fa-solid fa-clipboard-list"></i> Nincs folyamatban lévő saját fuvarmegbízásod.</div>`;
        return;
    }

    dispatches.forEach(d => {
        const item = document.createElement('div');
        item.className = 'dispatch-row-item';
        item.innerHTML = `
            <div>
                <strong>Fuvar #${d.dispatchId} &bull; ${d.units} db <code>${escapeHtml(d.itemId)}</code></strong>
                <div style="font-size: 11px; color: var(--color-text-secondary);">
                    Honnan: ${escapeHtml(d.originWarehouseId)} &bull; Hová: ${escapeHtml(d.destinationZoneId)} &bull; Várható haszon: <span class="text-success">+$${(d.projectedProfit || 0).toFixed(2)}</span>
                </div>
            </div>
            <div style="display: flex; gap: 8px; align-items: center;">
                <span class="badge badge-success">${escapeHtml((d.status || 'claimed').toUpperCase())}</span>
                <button class="btn btn-danger btn-sm cancel-dispatch-btn" data-dispatch-id="${d.dispatchId}"><i class="fa-solid fa-ban"></i> Lemondás</button>
            </div>
        `;

        const cancelBtn = item.querySelector('.cancel-dispatch-btn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => {
                openDialog({
                    title: 'Fuvarmegbízás Lemondása',
                    message: `Biztosan feladod a #${d.dispatchId} fuvarozási megbízást?`,
                    onConfirm: async () => {
                        const res = await postNui('logistics:cancelDispatch', { dispatchId: d.dispatchId });
                        if (res && res.success) {
                            showNotification({ type: 'warning', title: 'FUVAR LEMONDVA', message: 'A fuvarmegbízás törölve.' });
                            refreshLogisticsArbitrageRoutes();
                        }
                    }
                });
            });
        }

        list.appendChild(item);
    });
}

function openReserveSlotModal(nodeId) {
    const node = NyxState.logistics.nodes.find(n => n.id === nodeId) || NyxState.logistics.selectedNode;
    if (!node) return;

    const labelInput = document.getElementById('logistics-reserve-node-label');
    if (labelInput) {
        labelInput.value = `${node.shelfLabel || 'Polc'} [T${node.tier}-S${node.slot}] (${node.id})`;
    }

    const submodal = document.getElementById('logistics-submodal-reserve');
    if (submodal) submodal.classList.remove('hidden');
}

function closeReserveSlotModal() {
    const submodal = document.getElementById('logistics-submodal-reserve');
    if (submodal) submodal.classList.add('hidden');
}

async function submitReserveSlot() {
    const node = NyxState.logistics.selectedNode;
    if (!node) return;

    const durSelect = document.getElementById('logistics-reserve-duration-select');
    const durationMinutes = parseInt(durSelect ? durSelect.value : '60', 10);

    const btn = document.getElementById('logistics-reserve-confirm-btn');
    lockButtonAction(btn, async () => {
        const res = await postNui('logistics:reserveNode', {
            nodeId: node.id,
            durationMinutes: durationMinutes
        });
        if (res && res.success) {
            playWebBeep(980, 'sine', 0.1);
            showNotification({
                type: 'success',
                title: 'REKESZ ZÁROLVA',
                message: `A(z) ${node.id} rekesz sikeresen fenntartva ${durationMinutes} percre!`
            });
            closeReserveSlotModal();
            refreshLogisticsMatrixOverview(NyxState.logistics.selectedWarehouseId);
        } else {
            showNotification({
                type: 'error',
                title: 'ZÁROLÁS SIKERTELEN',
                message: res?.error || 'A rekesz nem zárolható.'
            });
        }
    });
}

// ============================================================================
// 12. VEHICLE MECHANICAL DIAGNOSTICS & CIVIC IMPOUND TERMINAL LOGIC
// ============================================================================

async function openVehicleTerminal(payload = {}) {
    const overlay = document.getElementById('vehicle-terminal-overlay');
    if (!overlay) return;

    NyxState.vehicle.isOpen = true;
    overlay.classList.remove('hidden');

    if (payload.activeTab) {
        switchVehicleTab(payload.activeTab);
    } else {
        switchVehicleTab('diagnostics');
    }

    const targetVin = payload.vin || payload.plate || NyxState.vehicle.selectedVehicleVin;
    await refreshVehicleTerminalOverview(targetVin);
}

function closeVehicleTerminal() {
    const overlay = document.getElementById('vehicle-terminal-overlay');
    if (overlay) overlay.classList.add('hidden');

    closeVehicleServiceModal();
    closeVehicleReleaseModal();

    NyxState.vehicle.isOpen = false;
    postNui('closeVehicleTerminal', {});
}

function switchVehicleTab(tabName) {
    NyxState.vehicle.activeTab = tabName;

    document.querySelectorAll('#vehicle-terminal-overlay .modal-tabs .tab-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.vehicleTab === tabName);
    });

    const panes = {
        diagnostics: document.getElementById('vehicle-tab-diagnostics'),
        impound: document.getElementById('vehicle-tab-impound'),
        compliance: document.getElementById('vehicle-tab-compliance')
    };

    Object.entries(panes).forEach(([k, el]) => {
        if (el) el.classList.toggle('hidden', k !== tabName);
    });

    if (tabName === 'impound') {
        renderVehicleImpounds();
    } else if (tabName === 'compliance') {
        renderVehicleCompliance();
    }
}

async function refreshVehicleTerminalOverview(vin) {
    const res = await postNui('vehicle:getOverview', { vin: vin });
    if (!res || !res.success) {
        showNotification({
            type: 'error',
            title: 'DIAGNOSZTIKA HIBA',
            message: res?.error || 'A járműadatok lekérdezése meghiúsult.'
        });
        return;
    }

    NyxState.vehicle.telemetry = res.telemetry || null;
    NyxState.vehicle.ownedVehicles = res.ownedVehicles || [];
    NyxState.vehicle.impoundedVehicles = res.impoundedVehicles || [];
    NyxState.vehicle.fiscalTier = res.fiscalTier || 'solvent';
    NyxState.vehicle.impoundLots = res.impoundLots || {};
    NyxState.vehicle.serviceCatalog = res.serviceCatalog || {};

    if (res.telemetry && res.telemetry.vin) {
        NyxState.vehicle.selectedVehicleVin = res.telemetry.vin;
    }

    const fiscalBadge = document.getElementById('vehicle-fiscal-badge');
    if (fiscalBadge) {
        const tierLabels = {
            solvent: 'Városi Kincstár: Fizetőképes',
            fiscal_stress: 'Városi Kincstár: Költségvetési Nyomás (+15%)',
            degraded: 'Városi Kincstár: Krízishelyzet (+35%)',
            bankrupt: 'Városi Kincstár: Csőd / Max Felár (+60%)'
        };
        const tierClasses = {
            solvent: 'badge-emerald',
            fiscal_stress: 'badge-amber',
            degraded: 'badge-orange',
            bankrupt: 'badge-rose'
        };
        fiscalBadge.className = `badge ${tierClasses[NyxState.vehicle.fiscalTier] || 'badge-emerald'}`;
        fiscalBadge.innerHTML = `<i class="fa-solid fa-building-columns"></i> ${tierLabels[NyxState.vehicle.fiscalTier] || 'Fizetőképes'}`;
    }

    renderVehicleTelemetry(NyxState.vehicle.telemetry);
    renderVehicleImpounds();
    renderVehicleCompliance();
}

function getFillColorClass(pct) {
    if (pct >= 75) return 'emerald';
    if (pct >= 40) return 'amber';
    if (pct >= 15) return 'orange';
    return 'rose';
}

function renderVehicleTelemetry(t) {
    if (!t) {
        const label = document.getElementById('vehicle-active-label');
        if (label) label.textContent = 'Nincs kiválasztott jármű';
        return;
    }

    const label = document.getElementById('vehicle-active-label');
    if (label) label.textContent = `${t.modelName || 'Jármű'} [${t.plate || '---'}]`;

    const sub = document.getElementById('vehicle-active-sub');
    if (sub) sub.textContent = `Alvázszám: ${t.vin || '---'} | Futásteljesítmény: ${(t.mileage || 0).toFixed(1)} km (Napi: ${(t.tripOdometer || 0).toFixed(1)} km)`;

    const roadworthyBadge = document.getElementById('vehicle-roadworthy-badge');
    if (roadworthyBadge) {
        if (t.isRoadworthy) {
            roadworthyBadge.className = 'badge badge-emerald';
            roadworthyBadge.innerHTML = '<i class="fa-solid fa-shield-check"></i> Műszaki: Érvényes';
        } else {
            roadworthyBadge.className = 'badge badge-rose';
            roadworthyBadge.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Balesetveszélyes / Kizárva';
        }
    }

    const engHealth = t.engineHealth !== undefined ? t.engineHealth : 1000.0;
    const engPct = Math.max(0, Math.min(100, engHealth / 10.0));
    updateGauge('engine', `${Math.round(engHealth)} HP`, engPct, `${Math.round(engHealth)} / 1000`);

    const oilPct = Math.max(0, Math.min(100, t.oilQuality !== undefined ? t.oilQuality : 100.0));
    updateGauge('oil', `${oilPct.toFixed(0)}%`, oilPct, `${oilPct.toFixed(1)}%`);

    const brkPct = Math.max(0, Math.min(100, t.brakePadWear !== undefined ? t.brakePadWear : 100.0));
    updateGauge('brakes', `${brkPct.toFixed(0)}%`, brkPct, `${brkPct.toFixed(1)}%`);

    const trnPct = Math.max(0, Math.min(100, t.transmissionWear !== undefined ? t.transmissionWear : 100.0));
    updateGauge('transmission', `${trnPct.toFixed(0)}%`, trnPct, `${trnPct.toFixed(1)}%`);

    const susPct = Math.max(0, Math.min(100, t.suspensionWear !== undefined ? t.suspensionWear : 100.0));
    updateGauge('suspension', `${susPct.toFixed(0)}%`, susPct, `${susPct.toFixed(1)}%`);

    const dtcContainer = document.getElementById('vehicle-dtc-container');
    const dtcCountLabel = document.getElementById('vehicle-dtc-count-label');
    const codes = t.dtcCodes || [];

    if (dtcCountLabel) {
        dtcCountLabel.textContent = `${codes.length} aktív hibakód észlelve`;
    }

    if (dtcContainer) {
        if (codes.length === 0) {
            dtcContainer.innerHTML = `
                <div class="empty-state">
                    <i class="fa-solid fa-circle-check empty-icon text-emerald"></i>
                    <p>A fedélzeti diagnosztikai rendszer (OBD-II) nem talált aktív mechanikai hibakódot. Minden fődarab üzemi paramétereken belül üzemel.</p>
                </div>`;
        } else {
            dtcContainer.innerHTML = codes.map(c => `
                <div class="dtc-chip ${c.severity === 'critical' ? 'critical' : 'warning'}">
                    <span class="dtc-chip-code">${escapeHtml(c.code)}</span>
                    <div class="dtc-chip-info">
                        <span class="dtc-chip-title">${escapeHtml(c.title || c.description)}</span>
                        <span class="dtc-chip-desc">${escapeHtml(c.description || '')}</span>
                    </div>
                </div>
            `).join('');
        }
    }

    const serviceGrid = document.getElementById('vehicle-service-grid');
    if (serviceGrid) {
        const catalog = NyxState.vehicle.serviceCatalog || {};
        const serviceKeys = ['oil_change', 'brake_replacement', 'transmission_overhaul', 'suspension_tune', 'full_service'];

        serviceGrid.innerHTML = serviceKeys.map(k => {
            const item = catalog[k] || { label: k, baseCost: 150.0, description: 'Szerviz' };
            return `
                <div class="service-card-item">
                    <div class="service-card-header">
                        <span class="service-card-title">${escapeHtml(item.label)}</span>
                        <span class="service-card-cost">$${(item.baseCost || 0).toFixed(2)}</span>
                    </div>
                    <p class="service-card-desc">${escapeHtml(item.description)}</p>
                    <div class="service-card-meta">
                        <i class="fa-solid fa-screwdriver-wrench text-amber"></i> Szükséges: <code>tool_repairkit</code> vagy Készpénz
                    </div>
                    <button class="btn btn-primary btn-block btn-apply-service" data-service-type="${k}">
                        <i class="fa-solid fa-wrench"></i> Szerviz Igénylése
                    </button>
                </div>
            `;
        }).join('');

        serviceGrid.querySelectorAll('.btn-apply-service').forEach(btn => {
            btn.addEventListener('click', () => {
                const sType = btn.dataset.serviceType;
                openVehicleServiceModal(sType);
            });
        });
    }
}

function updateGauge(name, badgeText, pct, valText) {
    const badge = document.getElementById(`vehicle-gauge-badge-${name}`);
    if (badge) {
        badge.textContent = badgeText;
        const color = getFillColorClass(pct);
        badge.className = `badge badge-${color}`;
    }

    const fill = document.getElementById(`vehicle-gauge-fill-${name}`);
    if (fill) {
        fill.style.width = `${pct}%`;
        fill.className = `gauge-bar-fill ${getFillColorClass(pct)}`;
    }

    const val = document.getElementById(`vehicle-gauge-val-${name}`);
    if (val) {
        val.textContent = valText;
    }
}

function renderVehicleImpounds() {
    const container = document.getElementById('vehicle-impound-cards');
    if (!container) return;

    let items = NyxState.vehicle.impoundedVehicles || [];
    const q = (NyxState.vehicle.impoundSearchQuery || '').toLowerCase();
    const lotFilter = NyxState.vehicle.impoundLotFilter || 'all';

    if (q) {
        items = items.filter(v =>
            (v.plate && v.plate.toLowerCase().includes(q)) ||
            (v.vin && v.vin.toLowerCase().includes(q)) ||
            (v.modelName && v.modelName.toLowerCase().includes(q)) ||
            (v.impoundReason && v.impoundReason.toLowerCase().includes(q))
        );
    }

    if (lotFilter !== 'all') {
        items = items.filter(v => v.impoundLotId === lotFilter);
    }

    if (items.length === 0) {
        container.innerHTML = `
            <div class="empty-state" style="grid-column: 1 / -1;">
                <i class="fa-solid fa-truck-pickup empty-icon"></i>
                <p>Nincs lefoglalt jármű a megadott szűrési feltételek mellett.</p>
            </div>`;
        return;
    }

    container.innerHTML = items.map(v => {
        const cost = v.cost || { baseFee: 500, storageDays: 0, dailyRate: 150, storageFee: 0, emergencySurcharge: 0, totalFee: 500 };
        return `
            <div class="impound-card">
                <div class="impound-card-header">
                    <span class="impound-veh-plate">${escapeHtml(v.plate || 'UNKNOWN')}</span>
                    <span class="badge badge-rose"><i class="fa-solid fa-lock"></i> LEFOGLALVA</span>
                </div>
                <div class="impound-veh-model">${escapeHtml(v.modelName || 'Gépjármű')} &bull; <small class="text-muted">VIN: ${escapeHtml(v.vin || '')}</small></div>
                <div class="impound-breakdown-box">
                    <div class="impound-breakdown-row">
                        <span>Telephely:</span>
                        <strong>${escapeHtml(v.lotLabel || 'Városi Telep')}</strong>
                    </div>
                    <div class="impound-breakdown-row">
                        <span>Lefoglalási indok:</span>
                        <span>${escapeHtml(v.impoundReason || 'Szabálysértés')}</span>
                    </div>
                    <div class="impound-breakdown-row">
                        <span>Alap lefoglalási bírság:</span>
                        <span>$${cost.baseFee.toFixed(2)}</span>
                    </div>
                    <div class="impound-breakdown-row">
                        <span>Tárolási díj (${cost.storageDays} nap &times; $${cost.dailyRate.toFixed(2)}):</span>
                        <span>$${cost.storageFee.toFixed(2)}</span>
                    </div>
                    ${cost.emergencySurcharge > 0 ? `
                        <div class="impound-breakdown-row">
                            <span class="text-rose"><i class="fa-solid fa-triangle-exclamation"></i> Kincstári felár (${cost.fiscalTier}):</span>
                            <span class="text-rose">+$${cost.emergencySurcharge.toFixed(2)}</span>
                        </div>
                    ` : ''}
                    <div class="impound-breakdown-row total-row">
                        <span>Fizetendő összeg:</span>
                        <span class="impound-total-fee">$${cost.totalFee.toFixed(2)}</span>
                    </div>
                </div>
                <button class="btn btn-primary btn-block btn-release-veh" data-vin="${escapeHtml(v.vin)}" data-plate="${escapeHtml(v.plate)}" data-cost="${cost.totalFee}">
                    <i class="fa-solid fa-dollar-sign"></i> Kiváltás & Kincstári Kiegyenlítés
                </button>
            </div>
        `;
    }).join('');

    container.querySelectorAll('.btn-release-veh').forEach(btn => {
        btn.addEventListener('click', () => {
            const vin = btn.dataset.vin;
            const plate = btn.dataset.plate;
            const cost = btn.dataset.cost;
            openVehicleReleaseModal({ vin, plate, totalFee: cost });
        });
    });
}

function renderVehicleCompliance() {
    const t = NyxState.vehicle.telemetry;
    const reg = t ? t.registration : null;

    const plateEl = document.getElementById('vehicle-comp-plate');
    if (plateEl) plateEl.textContent = reg?.plate || t?.plate || '---';

    const vinEl = document.getElementById('vehicle-comp-vin');
    if (vinEl) vinEl.textContent = reg?.vin || t?.vin || '---';

    const modelEl = document.getElementById('vehicle-comp-model');
    if (modelEl) modelEl.textContent = reg?.modelName || t?.modelName || '---';

    const expiryEl = document.getElementById('vehicle-comp-expiry');
    if (expiryEl) {
        if (reg && reg.expiresAt) {
            const d = new Date(reg.expiresAt * 1000);
            expiryEl.textContent = d.toLocaleString();
        } else {
            expiryEl.textContent = 'Nincs regisztrálva / Ismeretlen';
        }
    }

    const baseFeeEl = document.getElementById('vehicle-comp-base-fee');
    if (baseFeeEl) baseFeeEl.textContent = `$${(reg?.fee?.baseFee || 250.0).toFixed(2)}`;

    const lateFeeEl = document.getElementById('vehicle-comp-late-fee');
    if (lateFeeEl) lateFeeEl.textContent = `$${(reg?.fee?.latePenalty || 0.0).toFixed(2)}`;

    const statusBadge = document.getElementById('vehicle-compliance-status-badge');
    if (statusBadge) {
        const isExp = reg?.isExpired || (reg?.status === 'expired');
        if (isExp) {
            statusBadge.className = 'badge badge-rose';
            statusBadge.textContent = 'LEJÁRT';
        } else if (reg?.status === 'suspended') {
            statusBadge.className = 'badge badge-orange';
            statusBadge.textContent = 'FELFÜGGESZTVE';
        } else {
            statusBadge.className = 'badge badge-emerald';
            statusBadge.textContent = 'ÉRVÉNYES';
        }
    }

    const scoreEl = document.getElementById('vehicle-comp-score');
    if (scoreEl) scoreEl.textContent = `${(t?.compositeScore || 100).toFixed(1)} / 100`;

    const gradeBadge = document.getElementById('vehicle-comp-grade-badge');
    if (gradeBadge) {
        const g = t?.overallGrade || 'pristine';
        const labels = { pristine: 'KIVÁLÓ', good: 'JÓ', fair: 'KÖZEPES', critical: 'KRITIKUS', hazardous: 'VESZÉLYES' };
        const cls = { pristine: 'badge-emerald', good: 'badge-emerald', fair: 'badge-amber', critical: 'badge-orange', hazardous: 'badge-rose' };
        gradeBadge.className = `badge ${cls[g] || 'badge-emerald'}`;
        gradeBadge.textContent = labels[g] || g.toUpperCase();
    }

    const roadworthyEl = document.getElementById('vehicle-comp-roadworthy');
    if (roadworthyEl) {
        if (t?.isRoadworthy) {
            roadworthyEl.className = 'text-emerald';
            roadworthyEl.textContent = 'Igen (Megfelelt)';
        } else {
            roadworthyEl.className = 'text-rose';
            roadworthyEl.textContent = 'Nem (Közúti Kizárás)';
        }
    }

    const notesEl = document.getElementById('vehicle-comp-notes');
    if (notesEl) notesEl.textContent = t?.serviceNotes || 'Gyári állapot';

    const fleetTable = document.getElementById('vehicle-fleet-rows');
    if (fleetTable) {
        const owned = NyxState.vehicle.ownedVehicles || [];
        if (owned.length === 0) {
            fleetTable.innerHTML = `<tr><td colspan="6" class="text-center text-muted">Nincsenek nyilvántartott járművek a flottádban.</td></tr>`;
        } else {
            fleetTable.innerHTML = owned.map(v => `
                <tr>
                    <td><strong>${escapeHtml(v.plate || '')}</strong></td>
                    <td><code>${escapeHtml(v.vin || '')}</code></td>
                    <td>${escapeHtml(v.modelName || 'Jármű')}</td>
                    <td>${escapeHtml(v.garageId || v.storageState || 'stored')}</td>
                    <td><span class="badge ${v.registrationStatus === 'valid' ? 'badge-emerald' : 'badge-rose'}">${escapeHtml(v.registrationStatus || 'valid')}</span></td>
                    <td>
                        <button class="btn btn-secondary btn-sm btn-select-fleet-veh" data-vin="${escapeHtml(v.vin)}">
                            <i class="fa-solid fa-magnifying-glass"></i> Diagnosztika
                        </button>
                    </td>
                </tr>
            `).join('');

            fleetTable.querySelectorAll('.btn-select-fleet-veh').forEach(btn => {
                btn.addEventListener('click', () => {
                    const vin = btn.dataset.vin;
                    refreshVehicleTerminalOverview(vin);
                    switchVehicleTab('diagnostics');
                });
            });
        }
    }
}

function openVehicleServiceModal(serviceType) {
    const submodal = document.getElementById('vehicle-submodal-service');
    if (!submodal) return;

    NyxState.vehicle.selectedService = serviceType;
    const catalog = NyxState.vehicle.serviceCatalog || {};
    const item = catalog[serviceType] || { label: serviceType, baseCost: 150.0 };

    const titleInput = document.getElementById('vehicle-service-title-input');
    if (titleInput) titleInput.value = item.label || serviceType;

    const costInput = document.getElementById('vehicle-service-cost-input');
    if (costInput) costInput.value = `$${(item.baseCost || 0).toFixed(2)}`;

    const notesInput = document.getElementById('vehicle-service-notes-input');
    if (notesInput) notesInput.value = '';

    submodal.classList.remove('hidden');
}

function closeVehicleServiceModal() {
    const submodal = document.getElementById('vehicle-submodal-service');
    if (submodal) submodal.classList.add('hidden');
    NyxState.vehicle.selectedService = null;
}

async function submitVehicleService() {
    const serviceType = NyxState.vehicle.selectedService;
    const vin = NyxState.vehicle.selectedVehicleVin;
    if (!serviceType || !vin) return;

    const notesInput = document.getElementById('vehicle-service-notes-input');
    const notes = notesInput ? notesInput.value : '';

    const btn = document.getElementById('vehicle-service-confirm-btn');
    lockButtonAction(btn, async () => {
        const res = await postNui('vehicle:performService', {
            vin: vin,
            serviceType: serviceType,
            notes: notes
        });

        if (res && res.success) {
            playWebBeep(980, 'sine', 0.12);
            showNotification({
                type: 'success',
                title: 'SZERVIZ ELVÉGEZVE',
                message: 'A jármű alkatrésze gyári szintre (100%) lett felújítva!'
            });
            closeVehicleServiceModal();
            refreshVehicleTerminalOverview(vin);
        } else {
            showNotification({
                type: 'error',
                title: 'SZERVIZ SIKERTELEN',
                message: res?.error || 'A javítás meghiúsult. Ellenőrizd a szerszámokat és a fedezetet!'
            });
        }
    });
}

function openVehicleReleaseModal(data) {
    const submodal = document.getElementById('vehicle-submodal-release');
    if (!submodal) return;

    NyxState.vehicle.selectedImpound = data;

    const plateInput = document.getElementById('vehicle-release-plate-input');
    if (plateInput) plateInput.value = `${data.plate} (${data.vin})`;

    const totalInput = document.getElementById('vehicle-release-total-input');
    if (totalInput) totalInput.value = `$${parseFloat(data.totalFee || 0).toFixed(2)}`;

    submodal.classList.remove('hidden');
}

function closeVehicleReleaseModal() {
    const submodal = document.getElementById('vehicle-submodal-release');
    if (submodal) submodal.classList.add('hidden');
    NyxState.vehicle.selectedImpound = null;
}

async function submitVehicleRelease() {
    const item = NyxState.vehicle.selectedImpound;
    if (!item || !item.vin) return;

    const btn = document.getElementById('vehicle-release-confirm-btn');
    lockButtonAction(btn, async () => {
        const res = await postNui('vehicle:releaseImpound', { vin: item.vin });
        if (res && res.success) {
            playWebBeep(1100, 'triangle', 0.15);
            showNotification({
                type: 'success',
                title: 'JÁRMŰ KIVÁLTVA',
                message: `Jármű [${item.plate}] sikeresen kiváltva! Kifizetve: $${(res.totalPaid || item.totalFee || 0).toFixed(2)}.`
            });
            closeVehicleReleaseModal();
            refreshVehicleTerminalOverview(item.vin);
        } else {
            showNotification({
                type: 'error',
                title: 'KIVÁLTÁS SIKERTELEN',
                message: res?.error || 'A kiváltás meghiúsult. Ellenőrizd a számlaegyenleged!'
            });
        }
    });
}

async function renewVehicleRegistration() {
    const vin = NyxState.vehicle.selectedVehicleVin;
    if (!vin) return;

    const btn = document.getElementById('vehicle-btn-renew-reg');
    lockButtonAction(btn, async () => {
        const res = await postNui('vehicle:renewRegistration', { vin: vin });
        if (res && res.success) {
            playWebBeep(1050, 'sine', 0.12);
            showNotification({
                type: 'success',
                title: 'FORGALMI MEGÚJÍTVA',
                message: `A forgalmi engedély érvényessége 14 nappal meghosszabbítva! Kifizetve: $${(res.totalPaid || 250).toFixed(2)}.`
            });
            refreshVehicleTerminalOverview(vin);
        } else {
            showNotification({
                type: 'error',
                title: 'MEGÚJÍTÁS SIKERTELEN',
                message: res?.error || 'A forgalmi megújítása meghiúsult.'
            });
        }
    });
}

async function scanVehicleOBD() {
    const vin = NyxState.vehicle.selectedVehicleVin;
    if (!vin) return;

    const btn = document.getElementById('vehicle-btn-scan-obd');
    lockButtonAction(btn, async () => {
        const res = await postNui('vehicle:scanOBD', { vin: vin });
        if (res && res.success) {
            playWebBeep(880, 'sine', 0.1);
            showNotification({
                type: 'success',
                title: 'OBD-II SCAN BEFEJEZVE',
                message: `Vizsgálati jegyzőkönyv rögzítve (#${res.scanUuid}). Minősítés: ${(res.overallGrade || 'pristine').toUpperCase()}.`
            });
            refreshVehicleTerminalOverview(vin);
        } else {
            showNotification({
                type: 'error',
                title: 'VIZSGÁLAT SIKERTELEN',
                message: res?.error || 'Az OBD-II kapcsolat meghiúsult.'
            });
        }
    });
}

async function resetVehicleTripOdometer() {
    const vin = NyxState.vehicle.selectedVehicleVin;
    if (!vin) return;

    const btn = document.getElementById('vehicle-btn-reset-trip');
    lockButtonAction(btn, async () => {
        const res = await postNui('vehicle:resetTrip', { vin: vin });
        if (res && res.success) {
            showNotification({
                type: 'info',
                title: 'NAPI SZÁMLÁLÓ NULLÁZVA',
                message: 'A napi kilométerszámláló sikeresen visszaállítva 0.0 km-re.'
            });
            refreshVehicleTerminalOverview(vin);
        } else {
            showNotification({
                type: 'error',
                title: 'MŰVELET SIKERTELEN',
                message: res?.error || 'A nullázás nem sikerült.'
            });
        }
    });
}

// ============================================================================
// 12C. CITIZEN OS MASTER SMARTPHONE FRAMEWORK (`nyx_ui`)
// ============================================================================

async function openPhone(payload = {}) {
    const overlay = document.getElementById('phone-overlay');
    if (!overlay) return;

    NyxState.phone.isOpen = true;
    overlay.classList.remove('hidden');

    // Update real-time status clock
    updatePhoneClock();

    const targetApp = payload.initialApp || 'home';
    switchPhoneApp(targetApp);

    await refreshPhoneOverview();
}

function closePhone() {
    const overlay = document.getElementById('phone-overlay');
    if (overlay) overlay.classList.add('hidden');
    NyxState.phone.isOpen = false;
    postNui('closePhone', {});
}

function updatePhoneClock() {
    const timeEl = document.getElementById('phone-status-time');
    if (timeEl) {
        const now = new Date();
        const hrs = String(now.getHours()).padStart(2, '0');
        const mins = String(now.getMinutes()).padStart(2, '0');
        timeEl.textContent = `${hrs}:${mins}`;
    }
}

function switchPhoneApp(appId) {
    NyxState.phone.activeApp = appId;

    const screenHome = document.getElementById('phone-screen-home');
    const screenApp = document.getElementById('phone-screen-app');
    const titleEl = document.getElementById('phone-app-title');

    if (appId === 'home') {
        if (screenHome) screenHome.classList.remove('hidden');
        if (screenApp) screenApp.classList.add('hidden');
        return;
    }

    if (screenHome) screenHome.classList.add('hidden');
    if (screenApp) screenApp.classList.remove('hidden');

    // Hide all panes
    document.querySelectorAll('.phone-app-pane').forEach(p => p.classList.add('hidden'));

    const titles = {
        banking: 'CivicPay Bank',
        logistics: 'HaulExpress Tőzsde',
        alerts: 'CivicAlert (911)',
        profile: 'CivicID Igazolvány',
        settings: 'Beállítások'
    };

    if (titleEl) titleEl.textContent = titles[appId] || 'Alkalmazás';

    const targetPane = document.getElementById(`phone-app-${appId}`);
    if (targetPane) targetPane.classList.remove('hidden');

    if (appId === 'banking') {
        renderPhoneBanking();
    } else if (appId === 'logistics') {
        renderPhoneLogistics();
        fetchPhoneFreightBoard();
    } else if (appId === 'alerts') {
        renderPhoneAlerts();
    } else if (appId === 'profile') {
        renderPhoneProfile();
    } else if (appId === 'settings') {
        renderPhoneSettings();
    }
}

async function refreshPhoneOverview() {
    updatePhoneClock();
    const res = await postNui('phone:getOverview', {});
    if (res && res.success) {
        if (res.citizen) NyxState.phone.citizen = res.citizen;
        if (res.settings) NyxState.phone.settings = res.settings;
        if (res.banking) NyxState.phone.banking = res.banking;
        if (res.logistics) NyxState.phone.logistics = res.logistics;
        if (res.alerts) NyxState.phone.alerts.feed = res.alerts;

        renderPhoneHome();

        if (NyxState.phone.activeApp !== 'home') {
            switchPhoneApp(NyxState.phone.activeApp);
        }
    }
}

function renderPhoneHome() {
    const greetingEl = document.getElementById('phone-home-greeting');
    const ownerEl = document.getElementById('phone-home-owner');
    const dateEl = document.getElementById('phone-home-date');
    const badgeLogistics = document.getElementById('phone-badge-logistics');
    const badgeAlerts = document.getElementById('phone-badge-alerts');

    if (greetingEl) greetingEl.textContent = `Üdvözlünk, ${escapeHtml(NyxState.phone.citizen.fullName || 'Polgár')}!`;
    if (ownerEl) ownerEl.textContent = `ID: ${escapeHtml(NyxState.phone.citizen.citizenId || 'NYX')} | Tel: ${escapeHtml(NyxState.phone.citizen.phoneNumber || '555-0100')}`;

    if (dateEl) {
        const now = new Date();
        const days = ['VASÁRNAP', 'HÉTFŐ', 'KEDD', 'SZERDA', 'CSÜTÖRTÖK', 'PÉNTEK', 'SZOMBAT'];
        const months = ['JANUÁR', 'FEBRUÁR', 'MÁRCIUS', 'ÁPRILIS', 'MÁJUS', 'JÚNIUS', 'JÚLIUS', 'AUGUSZTUS', 'SZEPTEMBER', 'OKTÓBER', 'NOVEMBER', 'DECEMBER'];
        dateEl.textContent = `${days[now.getDay()]}, ${months[now.getMonth()]} ${now.getDate()}`;
    }

    if (badgeLogistics) {
        const count = NyxState.phone.logistics.availableHaulsCount || 0;
        if (count > 0) {
            badgeLogistics.textContent = count;
            badgeLogistics.classList.remove('hidden');
        } else {
            badgeLogistics.classList.add('hidden');
        }
    }

    if (badgeAlerts) {
        const count = NyxState.phone.alerts.feed ? NyxState.phone.alerts.feed.length : 0;
        if (count > 0) {
            badgeAlerts.classList.remove('hidden');
        } else {
            badgeAlerts.classList.add('hidden');
        }
    }
}

function renderPhoneBanking() {
    const balEl = document.getElementById('phone-bank-balance');
    const accEl = document.getElementById('phone-bank-account');
    const pillEl = document.getElementById('phone-bank-fiscal-pill');
    const txCont = document.getElementById('phone-bank-transactions');

    const b = NyxState.phone.banking;
    if (balEl) balEl.textContent = b.formattedBalance || `$${(b.balance || 0).toFixed(2)}`;
    if (accEl) accEl.textContent = b.accountId || `char:${NyxState.phone.citizen.citizenId}:bank`;

    if (pillEl) {
        const state = b.fiscalState || 'SOLVENT';
        pillEl.textContent = state;
        pillEl.className = 'badge ' + (state === 'SOLVENT' ? 'badge-success' : 'badge-danger');
    }

    if (txCont) {
        const txs = b.transactions || [];
        if (txs.length === 0) {
            txCont.innerHTML = '<div class="empty-state" style="padding: 10px; font-size: 11px;">Nincs rögzített számlatörténet.</div>';
        } else {
            txCont.innerHTML = txs.map(tx => `
                <div class="phone-tx-row">
                    <div class="phone-tx-meta">
                        <span class="phone-tx-memo">${escapeHtml(tx.memo || 'Átutalás')}</span>
                        <span class="phone-tx-sub">${escapeHtml(tx.category || 'general')} &bull; ${escapeHtml(String(tx.createdAt || ''))}</span>
                    </div>
                    <span class="phone-tx-val ${tx.isDebit ? 'debit' : 'credit'}">${escapeHtml(tx.formattedAmount || (tx.isDebit ? '-$' : '+$') + tx.amount)}</span>
                </div>
            `).join('');
        }
    }
}

async function handlePhoneTransferSubmit() {
    const recipientInput = document.getElementById('phone-transfer-recipient');
    const amountInput = document.getElementById('phone-transfer-amount');
    const memoInput = document.getElementById('phone-transfer-memo');

    const recipient = recipientInput ? recipientInput.value.trim() : '';
    const amount = amountInput ? parseFloat(amountInput.value) : 0;
    const memo = memoInput ? memoInput.value.trim() : '';

    if (!recipient) {
        showNotification({ type: 'warning', title: 'HIÁNYZÓ ADAT', message: 'Kérlek add meg a kedvezményezett Citizen ID-t!' });
        return;
    }
    if (isNaN(amount) || amount <= 0) {
        showNotification({ type: 'warning', title: 'ÉRVÉNYTELEN ÖSSZEG', message: 'Kérlek adj meg egy érvényes összeget!' });
        return;
    }

    const btn = document.getElementById('phone-transfer-submit-btn');
    lockButtonAction(btn, async () => {
        const res = await postNui('phone:transferMoney', {
            recipientCitizenId: recipient,
            amount: amount,
            memo: memo
        });

        if (res && res.success) {
            playWebBeep(1000, 'sine', 0.12);
            showNotification({
                type: 'success',
                title: 'ÁTUTALÁS SIKERES',
                message: `$${amount.toFixed(2)} sikeresen átutalva (${recipient}) részére! Tranzakciós illeték: $${(res.fee || 0).toFixed(2)}.`
            });
            if (recipientInput) recipientInput.value = '';
            if (amountInput) amountInput.value = '';
            if (memoInput) memoInput.value = '';
            const feePreview = document.getElementById('phone-transfer-fee-preview');
            if (feePreview) feePreview.textContent = '$0.00';
            await refreshPhoneOverview();
        } else {
            showNotification({
                type: 'error',
                title: 'ÁTUTALÁS MEGSZAKADT',
                message: res?.error || 'A tranzakció elutasításra került.'
            });
        }
    });
}

function renderPhoneLogistics() {
    const banner = document.getElementById('phone-haul-active-banner');
    const haul = NyxState.phone.logistics.activeHaul;

    if (banner) {
        if (haul && haul.status === 'in_transit') {
            banner.classList.remove('hidden');
            const itemEl = document.getElementById('phone-haul-active-item');
            const payoutEl = document.getElementById('phone-haul-active-payout');
            const escrowEl = document.getElementById('phone-haul-active-escrow');

            if (itemEl) itemEl.textContent = `${escapeHtml(haul.itemId || 'Fuvar')} (${haul.quantity || 1} db)`;
            if (payoutEl) payoutEl.textContent = haul.formattedPayout || `$${haul.totalPayout || 0}`;
            if (escrowEl) escrowEl.textContent = haul.formattedEscrow || `$${haul.escrowDeposit || 0}`;
        } else {
            banner.classList.add('hidden');
        }
    }
}

async function fetchPhoneFreightBoard() {
    const searchInput = document.getElementById('phone-haul-search-input');
    const search = searchInput ? searchInput.value.trim() : '';

    const res = await postNui('phone:getFreightBoard', { filterType: 'all', search: search });
    const listCont = document.getElementById('phone-haul-available-list');
    if (!listCont) return;

    if (res && res.contracts && res.contracts.length > 0) {
        listCont.innerHTML = res.contracts.map(c => `
            <div class="phone-contract-item">
                <div class="phone-contract-header">
                    <strong>${escapeHtml(c.itemId || 'Szállítmány')} &times; ${c.quantity || 1}</strong>
                    <span class="badge ${c.statusBadge || 'badge-info'}">${c.statusLabel || 'ELÉRHETŐ'}</span>
                </div>
                <div class="phone-haul-specs">
                    <div><span class="sub">Díj:</span> <b>${c.formattedPayout || '$' + c.totalPayout}</b></div>
                    <div><span class="sub">Kaució:</span> <b>${c.formattedEscrow || '$' + c.escrowDeposit}</b></div>
                </div>
                <button class="phone-btn phone-btn-secondary btn-claim-phone-haul" data-contract-id="${c.id}">
                    <i class="fa-solid fa-hand-holding-dollar"></i> Megbízás Elfogadása
                </button>
            </div>
        `).join('');

        listCont.querySelectorAll('.btn-claim-phone-haul').forEach(btn => {
            btn.addEventListener('click', async () => {
                const cid = btn.dataset.contractId;
                lockButtonAction(btn, async () => {
                    const cRes = await postNui('phone:claimContract', { contractId: cid });
                    if (cRes && cRes.success) {
                        playWebBeep(920, 'sine', 0.1);
                        showNotification({
                            type: 'success',
                            title: 'FUVAR FELVÉVE',
                            message: `Megbízás #${cid} aktiválva! A rakomány átvehető a logisztikai telephelyen.`
                        });
                        await refreshPhoneOverview();
                        fetchPhoneFreightBoard();
                    } else {
                        showNotification({
                            type: 'error',
                            title: 'SIKERTELEN FELVÉTEL',
                            message: cRes?.error || 'A megbízást nem sikerült zárolni.'
                        });
                    }
                });
            });
        });
    } else {
        listCont.innerHTML = '<div class="empty-state" style="padding: 12px; font-size: 11px;">Jelenleg nincs elérhető fuvarmegbízás a tőzsdén.</div>';
    }
}

function renderPhoneAlerts() {
    const listCont = document.getElementById('phone-alerts-feed');
    if (!listCont) return;

    const alerts = NyxState.phone.alerts.feed || [];
    if (alerts.length === 0) {
        listCont.innerHTML = '<div class="empty-state" style="padding: 12px; font-size: 11px;">Nincs aktív közérdekű riasztás a városban.</div>';
        return;
    }

    listCont.innerHTML = alerts.map(a => {
        const badge = a.badge || { priorityBadgeClass: 'badge-danger', priorityLabel: 'RIASZTÁS', categoryLabel: '911', categoryIcon: 'fa-solid fa-triangle-exclamation' };
        return `
            <div class="phone-alert-card">
                <div class="phone-alert-header">
                    <span><i class="${badge.categoryIcon || 'fa-solid fa-bullhorn'}"></i> ${escapeHtml(badge.categoryLabel || a.category || '911')}</span>
                    <span class="badge ${badge.priorityBadgeClass || 'badge-danger'}">${escapeHtml(badge.priorityLabel || a.priority || 'RIASZTÁS')}</span>
                </div>
                <div class="phone-alert-msg">${escapeHtml(a.message || '')}</div>
                <div class="phone-tx-sub"><i class="fa-solid fa-location-dot"></i> ${escapeHtml(a.location || 'Los Santos')} &bull; ${escapeHtml(a.caller || 'Állampolgár')}</div>
            </div>
        `;
    }).join('');
}

async function handlePhoneAlertSubmit() {
    const catEl = document.getElementById('phone-alert-category');
    const priEl = document.getElementById('phone-alert-priority');
    const locEl = document.getElementById('phone-alert-location');
    const msgEl = document.getElementById('phone-alert-message');

    const cat = catEl ? catEl.value : 'police';
    const pri = priEl ? priEl.value : 'medium';
    const loc = locEl ? locEl.value.trim() : 'Los Santos';
    const msg = msgEl ? msgEl.value.trim() : '';

    if (!msg || msg.length < 5) {
        showNotification({ type: 'warning', title: 'TÚL RÖVID LEÍRÁS', message: 'Kérlek adj meg legalább 5 karakteres leírást a vészhelyzetről!' });
        return;
    }

    const btn = document.getElementById('phone-alert-submit-btn');
    lockButtonAction(btn, async () => {
        const res = await postNui('phone:sendEmergencyAlert', {
            category: cat,
            priority: pri,
            locationLabel: loc,
            message: msg
        });

        if (res && res.success) {
            playWebBeep(1200, 'square', 0.15);
            showNotification({
                type: 'success',
                title: '911 SEGÉLYKÉRÉS RÖGZÍTVE',
                message: 'A diszpécserközpont továbbította a bejelentésedet a járőregységeknek!'
            });
            if (msgEl) msgEl.value = '';
            await refreshPhoneOverview();
        } else {
            showNotification({
                type: 'error',
                title: 'BEJELENTÉS ELUTASÍTVA',
                message: res?.error || 'A segélykérés leadása meghiúsult.'
            });
        }
    });
}

function renderPhoneProfile() {
    const c = NyxState.phone.citizen;
    const nameEl = document.getElementById('phone-profile-name');
    const cidEl = document.getElementById('phone-profile-cid');
    const phoneEl = document.getElementById('phone-profile-phone');
    const jobEl = document.getElementById('phone-profile-job');

    if (nameEl) nameEl.textContent = c.fullName || 'Állampolgár';
    if (cidEl) cidEl.textContent = `ID: ${c.citizenId || 'NYX1000'}`;
    if (phoneEl) phoneEl.textContent = c.phoneNumber || '555-0100';
    if (jobEl) jobEl.textContent = c.job || 'Polgár';
}

function renderPhoneSettings() {
    const s = NyxState.phone.settings;
    const dmEl = document.getElementById('phone-setting-darkmode');
    const amEl = document.getElementById('phone-setting-airplanemode');
    const wpEl = document.getElementById('phone-setting-wallpaper');

    if (dmEl) dmEl.checked = (s.darkMode !== false);
    if (amEl) amEl.checked = (s.airplaneMode === true);
    if (wpEl && s.wallpaper) wpEl.value = s.wallpaper;
}

async function handlePhoneSettingsSave() {
    const dmEl = document.getElementById('phone-setting-darkmode');
    const amEl = document.getElementById('phone-setting-airplanemode');
    const wpEl = document.getElementById('phone-setting-wallpaper');

    const darkMode = dmEl ? dmEl.checked : true;
    const airplaneMode = amEl ? amEl.checked : false;
    const wallpaper = wpEl ? wpEl.value : 'default_dark';

    const btn = document.getElementById('phone-settings-save-btn');
    lockButtonAction(btn, async () => {
        const res = await postNui('phone:updateSettings', {
            darkMode,
            airplaneMode,
            wallpaper
        });

        if (res && res.success) {
            playWebBeep(880, 'sine', 0.08);
            showNotification({
                type: 'info',
                title: 'BEÁLLÍTÁSOK MENTVE',
                message: 'Okostelefon konfiguráció sikeresen elmentve.'
            });
            NyxState.phone.settings.darkMode = darkMode;
            NyxState.phone.settings.airplaneMode = airplaneMode;
            NyxState.phone.settings.wallpaper = wallpaper;
        } else {
            showNotification({
                type: 'error',
                title: 'MENTÉS SIKERTELEN',
                message: res?.error || 'A beállítások mentése meghiúsult.'
            });
        }
    });
}

function handleIncomingPhoneNotification(alertData) {
    if (!alertData) return;
    if (NyxState.phone.settings.airplaneMode) return;

    if (!NyxState.phone.alerts.feed) NyxState.phone.alerts.feed = [];
    NyxState.phone.alerts.feed.unshift(alertData);

    const badge = document.getElementById('phone-badge-alerts');
    if (badge) badge.classList.remove('hidden');

    if (NyxState.phone.isOpen && NyxState.phone.activeApp === 'alerts') {
        renderPhoneAlerts();
    }
}

// 13. Global NUI Envelope Dispatcher
window.addEventListener('message', (event) => {
    const packet = event.data;
    if (!packet) return;

    const action = packet.action;

    // Reticle & Raycasting (nyx_interact)
    if (action === 'INTERACT_SET_ACTIVE' || (packet.app === 'interact' && action === 'ACTIVATE')) {
        setInteractActive(packet.active ?? packet.payload?.active ?? true);
    } else if (action === 'INTERACT_SET_TARGET' || (packet.app === 'interact' && action === 'SET_TARGET')) {
        setInteractTarget(packet.target ?? packet.payload);
    } else if (action === 'INTERACT_CLEAR_TARGET' || (packet.app === 'interact' && (action === 'DEACTIVATE' || action === 'CLEAR_TARGET'))) {
        clearInteractTarget();
    } else if (packet.app === 'placement' && action === 'START') {
        setPlacementActive(true, packet.payload?.label);
    } else if (packet.app === 'placement' && action === 'STOP') {
        setPlacementActive(false);
    }

    // Highway Road Condition Telemetry
    else if (action === 'updateHighwayRoadCondition' || action === 'HIGHWAY_ROAD_UPDATE') {
        if (packet.data) {
            NyxState.highwayRoadCondition = packet.data;
        }
    }

    // HUD Telemetry
    else if (action === 'HUD_UPDATE' || action === 'UPDATE_STATUS') {
        updateHudStatus(packet.payload);
    } else if (action === 'SET_VISIBILITY') {
        const hudCont = document.getElementById('hud-container');
        if (hudCont && packet.payload && packet.payload.visible !== undefined) {
            hudCont.classList.toggle('hidden', !packet.payload.visible);
        }
    }

    // Dynamic Inventory
    else if (action === 'INVENTORY_OPEN') {
        openInventory(packet.payload);
    } else if (action === 'INVENTORY_CLOSE') {
        closeInventory();
    } else if (action === 'HOTBAR_UPDATE') {
        updateHotbar(packet.payload);
    }

    // Notifications
    else if (action === 'NOTIFY' || action === 'ADD_NOTIFICATION') {
        showNotification(packet.payload);
    }

    // Freight Hauling Board
    else if (action === 'FREIGHT_BOARD_OPEN') {
        const freightOverlay = document.getElementById('freight-overlay');
        if (freightOverlay) freightOverlay.classList.remove('hidden');
        renderFreightContracts(packet.contracts || [], packet.activeContract);
    } else if (action === 'FREIGHT_BOARD_CLOSE') {
        const freightOverlay = document.getElementById('freight-overlay');
        if (freightOverlay) freightOverlay.classList.add('hidden');
    }

    // Treasury Transparency Board
    else if (action === 'TREASURY_DASHBOARD_OPEN' || action === 'OPEN_TREASURY_DASHBOARD') {
        openTreasuryDashboard(packet.payload || packet.data);
    } else if (action === 'TREASURY_DASHBOARD_CLOSE' || action === 'CLOSE_TREASURY_DASHBOARD') {
        closeTreasuryDashboard();
    } else if (action === 'TREASURY_TICKER_UPDATE') {
        prependTreasuryLedgerRow(packet.payload || packet.data);
    } else if (action === 'TREASURY_SWEEP_UPDATE') {
        prependTreasurySweepRow(packet.payload || packet.data);
    }

    // MDT CAD Terminal
    else if (action === 'MDT_OPEN') {
        openMdt(packet.payload);
    } else if (action === 'MDT_CLOSE') {
        closeMdt();
    }

    // Corporate & Union Management Terminal
    else if (action === 'FACTION_DASHBOARD_OPEN') {
        openFactionDashboard(packet.payload);
    } else if (action === 'FACTION_DASHBOARD_CLOSE') {
        closeFactionDashboard();
    }

    // Courtroom Terminal & Forensic Explorer
    else if (action === 'COURT_TERMINAL_OPEN') {
        openCourtTerminal(packet.payload);
    } else if (action === 'COURT_TERMINAL_CLOSE') {
        closeCourtTerminal();
    }

    // Parliamentary Ranked-Choice Voting & Legislation Terminal
    else if (action === 'PARLIAMENT_UI_OPEN') {
        openParliamentUI(packet.payload);
    } else if (action === 'PARLIAMENT_UI_CLOSE') {
        closeParliamentUI();
    }

    // Real Estate Blind-Auction & Stewardship Portal
    else if (action === 'PROPERTY_PORTAL_OPEN') {
        openPropertyPortal(packet.payload);
    } else if (action === 'PROPERTY_PORTAL_CLOSE') {
        closePropertyPortal();
    }

    // 3D Warehouse Matrix & Elastic Market Monitor
    else if (action === 'LOGISTICS_MATRIX_OPEN') {
        openMarketMonitor(packet.payload);
    } else if (action === 'LOGISTICS_MATRIX_CLOSE') {
        closeMarketMonitor();
    }

    // Mechanical Diagnostics & Civic Impound Terminal
    else if (action === 'VEHICLE_TERMINAL_OPEN') {
        openVehicleTerminal(packet.payload);
    } else if (action === 'VEHICLE_TERMINAL_CLOSE') {
        closeVehicleTerminal();
    }

    // Citizen OS Master Smartphone Framework
    else if (action === 'PHONE_OPEN') {
        openPhone(packet.payload);
    } else if (action === 'PHONE_CLOSE') {
        closePhone();
    } else if (action === 'PHONE_NOTIFICATION') {
        handleIncomingPhoneNotification(packet.payload);
    }
});

// 14. Event Listeners, Failsafe Escapes & Dev Tools Initialization
document.addEventListener('DOMContentLoaded', () => {
    // Inventory Actions with isPending Locking
    const invCloseBtn = document.getElementById('inv-close-btn');
    if (invCloseBtn) invCloseBtn.addEventListener('click', closeInventory);

    const invUseBtn = document.getElementById('inv-use-btn');
    if (invUseBtn) {
        invUseBtn.addEventListener('click', () => {
            if (NyxState.inventory.selectedSlot) {
                lockButtonAction(invUseBtn, () => postNui('inventory:useItem', { slot: NyxState.inventory.selectedSlot }));
            }
        });
    }

    const invGiveBtn = document.getElementById('inv-give-btn');
    if (invGiveBtn) {
        invGiveBtn.addEventListener('click', () => {
            if (NyxState.inventory.selectedSlot) {
                lockButtonAction(invGiveBtn, () => postNui('inventory:giveItem', { slot: NyxState.inventory.selectedSlot }));
            }
        });
    }

    const invDropBtn = document.getElementById('inv-drop-btn');
    if (invDropBtn) {
        invDropBtn.addEventListener('click', () => {
            if (NyxState.inventory.selectedSlot) {
                const splitCount = parseInt(document.getElementById('inv-split-input')?.value || '1', 10);
                lockButtonAction(invDropBtn, () => postNui('inventory:dropItem', {
                    slot: NyxState.inventory.selectedSlot,
                    amount: Math.max(1, Math.min(1000, splitCount || 1))
                }));
            }
        });
    }

    // Freight Actions with isPending Locking
    const freightCloseBtn = document.getElementById('freight-close-btn');
    if (freightCloseBtn) {
        freightCloseBtn.addEventListener('click', () => {
            document.getElementById('freight-overlay')?.classList.add('hidden');
            postNui('closeFreightBoard', {});
        });
    }

    const freightLoadBtn = document.getElementById('freight-load-btn');
    if (freightLoadBtn) {
        freightLoadBtn.addEventListener('click', () => {
            lockButtonAction(freightLoadBtn, () => postNui('loadFreightPallet', {}));
        });
    }

    const freightDeliverBtn = document.getElementById('freight-deliver-btn');
    if (freightDeliverBtn) {
        freightDeliverBtn.addEventListener('click', () => {
            lockButtonAction(freightDeliverBtn, () => postNui('deliverFreightContract', {}));
        });
    }

    const freightAbandonBtn = document.getElementById('freight-abandon-btn');
    if (freightAbandonBtn) {
        freightAbandonBtn.addEventListener('click', () => {
            openDialog({
                title: 'Megbízás Feladása',
                message: 'Biztosan feladod az aktív fuvarodat? A zárolt kaució azonnal elveszik.',
                onConfirm: () => {
                    document.getElementById('freight-active-banner')?.classList.add('hidden');
                    postNui('abandonFreightContract', {});
                }
            });
        });
    }

    // Treasury Actions
    const treasuryCloseBtn = document.getElementById('treasury-close-btn');
    if (treasuryCloseBtn) treasuryCloseBtn.addEventListener('click', closeTreasuryDashboard);

    document.querySelectorAll('.treasury-tab').forEach(tab => {
        tab.addEventListener('click', () => {
            document.querySelectorAll('.treasury-tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.treasury-tab-pane').forEach(p => p.classList.add('hidden'));

            tab.classList.add('active');
            const targetPaneId = `treasury-tab-${tab.dataset.tab}`;
            const targetPane = document.getElementById(targetPaneId);
            if (targetPane) targetPane.classList.remove('hidden');
        });
    });

    const treasuryCatSelect = document.getElementById('treasury-ledger-category-select');
    if (treasuryCatSelect) {
        treasuryCatSelect.addEventListener('change', (e) => {
            NyxState.treasury.ledgerCategory = e.target.value;
            NyxState.treasury.ledgerPage = 1;
            fetchTreasuryLedgerPage(1);
        });
    }

    const treasurySearchInput = document.getElementById('treasury-ledger-search');
    let treasurySearchDebounce = null;
    if (treasurySearchInput) {
        treasurySearchInput.addEventListener('input', (e) => {
            clearTimeout(treasurySearchDebounce);
            treasurySearchDebounce = setTimeout(() => {
                NyxState.treasury.ledgerSearch = e.target.value.trim();
                NyxState.treasury.ledgerPage = 1;
                fetchTreasuryLedgerPage(1);
            }, 250);
        });
    }

    const treasuryPrevBtn = document.getElementById('treasury-ledger-prev-btn');
    if (treasuryPrevBtn) {
        treasuryPrevBtn.addEventListener('click', () => {
            if (NyxState.treasury.ledgerPage > 1) {
                fetchTreasuryLedgerPage(NyxState.treasury.ledgerPage - 1);
            }
        });
    }

    const treasuryNextBtn = document.getElementById('treasury-ledger-next-btn');
    if (treasuryNextBtn) {
        treasuryNextBtn.addEventListener('click', () => {
            if (NyxState.treasury.ledgerPage < NyxState.treasury.ledgerTotalPages) {
                fetchTreasuryLedgerPage(NyxState.treasury.ledgerPage + 1);
            }
        });
    }

    // MDT Actions & Auto-Focused Search Inputs
    const mdtCloseBtn = document.getElementById('mdt-close-btn');
    if (mdtCloseBtn) mdtCloseBtn.addEventListener('click', closeMdt);

    document.querySelectorAll('.mdt-tab').forEach(tab => {
        tab.addEventListener('click', () => {
            document.querySelectorAll('.mdt-tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.mdt-tab-pane').forEach(p => p.classList.add('hidden'));

            tab.classList.add('active');
            const targetPaneId = `mdt-tab-${tab.dataset.tab}`;
            const targetPane = document.getElementById(targetPaneId);
            if (targetPane) targetPane.classList.remove('hidden');

            // Ergonomics: Auto-focus corresponding search input
            if (tab.dataset.tab === 'citizens') {
                setTimeout(() => document.getElementById('mdt-citizen-search-input')?.focus(), 50);
            } else if (tab.dataset.tab === 'vehicles') {
                setTimeout(() => document.getElementById('mdt-vehicle-search-input')?.focus(), 50);
            }
        });
    });

    // Faction / Corporate & Union Actions
    const factionCloseBtn = document.getElementById('faction-close-btn');
    if (factionCloseBtn) factionCloseBtn.addEventListener('click', closeFactionDashboard);

    document.querySelectorAll('.faction-tab').forEach(tab => {
        tab.addEventListener('click', () => {
            setFactionTab(tab.dataset.tab);
        });
    });

    const factionDividendBtn = document.getElementById('faction-dividend-btn');
    if (factionDividendBtn) {
        factionDividendBtn.addEventListener('click', () => {
            const amount = parseFloat(document.getElementById('faction-dividend-amount')?.value || '0');
            const rate = parseFloat(document.getElementById('faction-dividend-rate')?.value || '0.5');
            if (amount <= 0) {
                showNotification({ type: 'error', title: 'ÉRVÉNYTELEN ÖSSZEG', message: 'Kérlek adj meg egy pozitív nyereség összeget!' });
                return;
            }
            openDialog({
                title: 'Osztalékkifizetés Jóváhagyása',
                message: `Biztosan felosztasz $${amount.toLocaleString()} nyereséget a tulajdonosok között (${(rate * 100).toFixed(0)}% arányban)?`,
                onConfirm: () => {
                    lockButtonAction(factionDividendBtn, async () => {
                        const res = await postNui('faction:distributeDividends', {
                            factionId: NyxState.faction.currentFactionId,
                            netProfit: amount,
                            distributionRate: rate
                        });
                        if (res && res.success) {
                            showNotification({ type: 'success', title: 'OSZTALÉK KIFIZETVE', message: 'Az osztalékok sikeresen jóváírva a tagok számláin!' });
                            refreshFactionOverview();
                        } else {
                            showNotification({ type: 'error', title: 'SIKERTELEN KIFIZETÉS', message: res?.error || 'Nincs elegendő fedezet vagy hiányzó jogosultság.' });
                        }
                    });
                }
            });
        });
    }

    const factionOpenAddMemberBtn = document.getElementById('faction-open-add-member-btn');
    if (factionOpenAddMemberBtn) {
        factionOpenAddMemberBtn.addEventListener('click', () => openMemberModal(null));
    }
    const factionMemberModalClose = document.getElementById('faction-member-modal-close');
    if (factionMemberModalClose) {
        factionMemberModalClose.addEventListener('click', () => {
            document.getElementById('faction-submodal-member')?.classList.add('hidden');
        });
    }
    const factionMemberModalCancel = document.getElementById('faction-member-modal-cancel');
    if (factionMemberModalCancel) {
        factionMemberModalCancel.addEventListener('click', () => {
            document.getElementById('faction-submodal-member')?.classList.add('hidden');
        });
    }
    const factionMemberModalSave = document.getElementById('faction-member-modal-save');
    if (factionMemberModalSave) {
        factionMemberModalSave.addEventListener('click', () => {
            const citId = document.getElementById('faction-input-member-citid')?.value?.trim();
            const role = document.getElementById('faction-input-member-role')?.value?.trim() || 'Employee';
            const wage = parseFloat(document.getElementById('faction-input-member-wage')?.value || '0');
            const equity = parseFloat(document.getElementById('faction-input-member-equity')?.value || '0');

            if (!citId) {
                showNotification({ type: 'error', title: 'HIÁNYZÓ ADAT', message: 'Kérlek add meg az állampolgár Citizen ID-jét!' });
                return;
            }

            const nodes = [];
            document.querySelectorAll('#faction-submodal-member input[type="checkbox"]:checked').forEach(cb => {
                nodes.push(cb.value);
            });

            const isEdit = !!NyxState.faction.selectedMemberCitId;
            const endpoint = isEdit ? 'faction:updateMember' : 'faction:addMember';

            lockButtonAction(factionMemberModalSave, async () => {
                const res = await postNui(endpoint, {
                    factionId: NyxState.faction.currentFactionId,
                    citizenId: citId,
                    roleTitle: role,
                    wageHourly: wage,
                    equityShares: equity,
                    permissionNodes: nodes
                });

                if (res && res.success) {
                    showNotification({ type: 'success', title: 'TAG SIKERESEN FRISSÍTVE', message: `${citId} adatai elmentve!` });
                    document.getElementById('faction-submodal-member')?.classList.add('hidden');
                    refreshFactionOverview();
                } else {
                    showNotification({ type: 'error', title: 'SIKERTELEN MŰVELET', message: res?.error || 'Nem sikerült menteni.' });
                }
            });
        });
    }

    const factionOpenWithdrawBtn = document.getElementById('faction-open-withdraw-btn');
    if (factionOpenWithdrawBtn) {
        factionOpenWithdrawBtn.addEventListener('click', () => {
            const modal = document.getElementById('faction-submodal-withdraw');
            if (!modal) return;
            const vaultSelect = document.getElementById('faction-withdraw-vault');
            if (vaultSelect) {
                vaultSelect.innerHTML = '';
                const vaults = NyxState.faction.data?.vaults || [{ vault_id: 'master_vault', vault_label: 'Fő Széf (Treasury Master)' }];
                vaults.forEach(v => {
                    const opt = document.createElement('option');
                    opt.value = v.vault_id || v.vaultId;
                    opt.textContent = `${v.vault_label || v.vaultLabel} (${v.vault_id || v.vaultId})`;
                    vaultSelect.appendChild(opt);
                });
            }
            modal.classList.remove('hidden');
        });
    }
    const factionWithdrawModalClose = document.getElementById('faction-withdraw-modal-close');
    if (factionWithdrawModalClose) {
        factionWithdrawModalClose.addEventListener('click', () => {
            document.getElementById('faction-submodal-withdraw')?.classList.add('hidden');
        });
    }
    const factionWithdrawModalCancel = document.getElementById('faction-withdraw-modal-cancel');
    if (factionWithdrawModalCancel) {
        factionWithdrawModalCancel.addEventListener('click', () => {
            document.getElementById('faction-submodal-withdraw')?.classList.add('hidden');
        });
    }
    const factionWithdrawModalSubmit = document.getElementById('faction-withdraw-modal-submit');
    if (factionWithdrawModalSubmit) {
        factionWithdrawModalSubmit.addEventListener('click', () => {
            const vaultId = document.getElementById('faction-withdraw-vault')?.value;
            const target = document.getElementById('faction-withdraw-target')?.value?.trim();
            const amount = parseFloat(document.getElementById('faction-withdraw-amount')?.value || '0');
            const reason = document.getElementById('faction-withdraw-reason')?.value?.trim() || 'Multi-sig withdrawal';

            if (!target || amount <= 0) {
                showNotification({ type: 'error', title: 'HIÁNYOS KÉRELEM', message: 'Kérlek adj meg érvényes célszámlát és összeget!' });
                return;
            }

            lockButtonAction(factionWithdrawModalSubmit, async () => {
                const res = await postNui('faction:initiateWithdrawal', {
                    factionId: NyxState.faction.currentFactionId,
                    vaultId: vaultId,
                    targetAccount: target,
                    amount: amount,
                    reason: reason
                });

                if (res && res.success) {
                    showNotification({ type: 'success', title: 'LETÉT KEZDEMÉNYEZVE', message: `Kérelem #${res.requestId || ''} benyújtva!` });
                    document.getElementById('faction-submodal-withdraw')?.classList.add('hidden');
                    refreshFactionOverview();
                } else {
                    showNotification({ type: 'error', title: 'KEZDEMÉNYEZÉS SIKERTELEN', message: res?.error || 'Nincs jogosultságod vagy túllépted a limitet.' });
                }
            });
        });
    }

    const cbaBuilderSubmitBtn = document.getElementById('cba-builder-submit-btn');
    if (cbaBuilderSubmitBtn) {
        cbaBuilderSubmitBtn.addEventListener('click', () => {
            const title = document.getElementById('cba-builder-title')?.value?.trim();
            const unionId = document.getElementById('cba-builder-union')?.value;
            const wage = parseFloat(document.getElementById('cba-builder-wage')?.value || '0');
            const overtime = parseFloat(document.getElementById('cba-builder-overtime')?.value || '1.5');
            const hazard = parseFloat(document.getElementById('cba-builder-hazard')?.value || '0');
            const notes = document.getElementById('cba-builder-notes')?.value?.trim() || '';

            if (!title || !unionId) {
                showNotification({ type: 'error', title: 'HIÁNYOS CBA ADATOK', message: 'Kérlek add meg a szerződés nevét és a kijelölt szakszervezetet!' });
                return;
            }

            lockButtonAction(cbaBuilderSubmitBtn, async () => {
                const res = await postNui('faction:proposeCBA', {
                    factionId: NyxState.faction.currentFactionId,
                    unionId: unionId,
                    cbaTitle: title,
                    guaranteedMinWage: wage,
                    overtimeMultiplier: overtime,
                    hazardPayBonus: hazard,
                    notes: notes
                });

                if (res && res.success) {
                    showNotification({ type: 'success', title: 'CBA JAVASLAT BEKÜLDVE', message: 'A kollektív szerződés tervezet beküldve!' });
                    refreshFactionOverview();
                } else {
                    showNotification({ type: 'error', title: 'JAVASLAT SIKERTELEN', message: res?.error || 'Hiba a CBA benyújtásakor.' });
                }
            });
        });
    }

    // Courtroom Terminal & Forensic Explorer UI Listeners
    document.getElementById('court-close-btn')?.addEventListener('click', closeCourtTerminal);

    document.querySelectorAll('.court-tab').forEach(btn => {
        btn.addEventListener('click', () => setCourtTab(btn.dataset.tab));
    });

    document.getElementById('court-evidence-search')?.addEventListener('input', () => {
        refreshCourtEvidenceList();
    });

    document.getElementById('court-evidence-type-filter')?.addEventListener('change', () => {
        refreshCourtEvidenceList();
    });

    document.getElementById('court-evidence-sealed-check')?.addEventListener('change', () => {
        refreshCourtEvidenceList();
    });

    document.getElementById('court-evidence-refresh-btn')?.addEventListener('click', () => {
        refreshCourtEvidenceList();
    });

    document.getElementById('court-verify-chain-btn')?.addEventListener('click', verifyCurrentEvidenceChain);

    document.getElementById('court-juror-checkin-btn')?.addEventListener('click', checkInJuror);

    document.getElementById('court-vote-guilty-btn')?.addEventListener('click', () => castJuryBallot('guilty'));
    document.getElementById('court-vote-notguilty-btn')?.addEventListener('click', () => castJuryBallot('not_guilty'));
    document.getElementById('court-vote-abstain-btn')?.addEventListener('click', () => castJuryBallot('abstain'));

    document.getElementById('court-summon-jury-btn')?.addEventListener('click', async () => {
        const docket = NyxState.court.currentDocket;
        if (!docket) return;
        const btn = document.getElementById('court-summon-jury-btn');
        lockButtonAction(btn, async () => {
            const res = await postNui('court:summonJury', { docketId: docket.docket_id || docket.docketId });
            if (res && res.success) {
                showNotification({ type: 'info', title: 'ÜLNÖKÖK BEHÍVVA', message: 'Hivatalos esküdtszéki idézés kiküldve 6 polgárnak!' });
                refreshCourtOverview();
            }
        });
    });

    document.getElementById('court-start-trial-btn')?.addEventListener('click', async () => {
        const docket = NyxState.court.currentDocket;
        if (!docket) return;
        const btn = document.getElementById('court-start-trial-btn');
        lockButtonAction(btn, async () => {
            const res = await postNui('court:startTrial', { docketId: docket.docket_id || docket.docketId });
            if (res && res.success) {
                showNotification({ type: 'success', title: 'TÁRGYALÁS MEGNYITVA', message: 'A bírósági tárgyalás hivatalosan elkezdődött!' });
                refreshCourtOverview();
            }
        });
    });

    document.getElementById('court-start-deliberation-btn')?.addEventListener('click', async () => {
        const docket = NyxState.court.currentDocket;
        if (!docket) return;
        const btn = document.getElementById('court-start-deliberation-btn');
        lockButtonAction(btn, async () => {
            const res = await postNui('court:startDeliberation', { docketId: docket.docket_id || docket.docketId });
            if (res && res.success) {
                showNotification({ type: 'warning', title: 'TANÁCSKOZÁS MEGNYITVA', message: 'Az esküdtszék elvonult titkos tanácskozásra.' });
                refreshCourtOverview();
            }
        });
    });

    document.getElementById('court-conclude-trial-btn')?.addEventListener('click', async () => {
        const docket = NyxState.court.currentDocket;
        if (!docket) return;
        const verdict = document.getElementById('court-verdict-select')?.value || 'guilty';
        openDialog({
            title: 'Ítélet Kihirdetése & Per Lezárása',
            message: `Biztosan lezárod az ügyet és kihirdeted a(z) "${verdict.toUpperCase()}" bírói határozatot?`,
            onConfirm: async () => {
                const res = await postNui('court:concludeTrial', {
                    docketId: docket.docket_id || docket.docketId,
                    verdictRuling: verdict
                });
                if (res && res.success) {
                    showNotification({ type: 'success', title: 'PER LEZÁRVA', message: 'Az ítélet rögzítve az állami archívumban.' });
                    refreshCourtOverview();
                } else {
                    showNotification({ type: 'error', title: 'SIKERTELEN LEZÁRÁS', message: res?.error || 'Hiba történt.' });
                }
            }
        });
    });

    document.getElementById('court-select-warrant-type')?.addEventListener('change', (e) => {
        const scopeGroup = document.getElementById('court-group-subpoena-scope');
        if (scopeGroup) {
            scopeGroup.classList.toggle('hidden', e.target.value !== 'subpoena');
        }
    });

    document.getElementById('court-submit-petition-btn')?.addEventListener('click', submitWarrantPetition);

    document.getElementById('court-subpoena-close-btn')?.addEventListener('click', () => {
        document.getElementById('court-subpoena-disclosure')?.classList.add('hidden');
    });

    // Parliamentary Voting & Legislation Listeners
    document.getElementById('parliament-close-btn')?.addEventListener('click', closeParliamentUI);

    document.querySelectorAll('.parliament-tab').forEach(btn => {
        btn.addEventListener('click', () => {
            const tab = btn.getAttribute('data-tab');
            if (tab) setParliamentTab(tab);
        });
    });

    document.getElementById('parliament-session-select')?.addEventListener('change', (e) => {
        NyxState.parliament.selectedSessionId = parseInt(e.target.value, 10);
        NyxState.parliament.rankedCandidateIds = [];
        const proofBanner = document.getElementById('parliament-cast-proof-banner');
        if (proofBanner) proofBanner.classList.add('hidden');
        renderParliamentOverviewData();
    });

    document.getElementById('parliament-cast-ballot-btn')?.addEventListener('click', castParliamentBallot);
    document.getElementById('parliament-verify-receipt-btn')?.addEventListener('click', verifyParliamentReceipt);
    document.getElementById('parliament-refresh-tabulation-btn')?.addEventListener('click', refreshParliamentTabulation);

    document.getElementById('parliament-submit-candidacy-btn')?.addEventListener('click', submitParliamentCandidacy);
    document.getElementById('parliament-btn-open-recall')?.addEventListener('click', openParliamentRecallModal);
    document.getElementById('parliament-submodal-recall-close')?.addEventListener('click', closeParliamentRecallModal);
    document.getElementById('parliament-recall-cancel-btn')?.addEventListener('click', closeParliamentRecallModal);
    document.getElementById('parliament-recall-submit-btn')?.addEventListener('click', submitParliamentRecall);

    document.getElementById('parliament-laws-search')?.addEventListener('input', renderParliamentLaws);
    document.getElementById('parliament-laws-cat-filter')?.addEventListener('change', renderParliamentLaws);

    document.getElementById('parliament-select-bill-law')?.addEventListener('change', updateParliamentBillBoundsHint);
    document.getElementById('parliament-select-bill-field')?.addEventListener('change', updateParliamentBillBoundsHint);
    document.getElementById('parliament-submit-bill-btn')?.addEventListener('click', submitParliamentBill);

    // Real Estate Blind-Auction & Stewardship Portal Listeners
    document.getElementById('property-portal-close-btn')?.addEventListener('click', closePropertyPortal);

    document.querySelectorAll('#property-portal-overlay .tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const tab = btn.getAttribute('data-tab');
            if (tab) setPropertyTab(tab);
        });
    });

    document.getElementById('prop-auctions-search')?.addEventListener('input', renderPropertyAuctions);
    document.getElementById('prop-auctions-type-filter')?.addEventListener('change', renderPropertyAuctions);
    document.getElementById('prop-owned-search')?.addEventListener('input', renderOwnedProperties);
    document.getElementById('prop-owned-status-filter')?.addEventListener('change', renderOwnedProperties);

    document.getElementById('property-submodal-bid-close')?.addEventListener('click', closeAuctionBidModal);
    document.getElementById('property-bid-cancel-btn')?.addEventListener('click', closeAuctionBidModal);
    document.getElementById('property-bid-submit-btn')?.addEventListener('click', submitAuctionBid);

    document.getElementById('property-submodal-assign-close')?.addEventListener('click', closeAssignStewardModal);
    document.getElementById('property-assign-cancel-btn')?.addEventListener('click', closeAssignStewardModal);
    document.getElementById('property-assign-submit-btn')?.addEventListener('click', submitAssignSteward);
    document.getElementById('prop-btn-appoint-delegate')?.addEventListener('click', () => openAssignStewardModal(null));

    // 3D Warehouse Matrix & Elastic Market Monitor Listeners
    document.getElementById('logistics-matrix-close-btn')?.addEventListener('click', closeMarketMonitor);

    document.querySelectorAll('#logistics-matrix-overlay .tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const tab = btn.getAttribute('data-tab');
            if (tab) setLogisticsTab(tab);
        });
    });

    document.getElementById('logistics-wh-select')?.addEventListener('change', (e) => {
        NyxState.logistics.selectedWarehouseId = e.target.value;
        refreshLogisticsMatrixOverview();
    });

    document.getElementById('logistics-shelf-select')?.addEventListener('change', (e) => {
        NyxState.logistics.selectedShelfId = e.target.value;
        renderLogistics3DShelfMatrix();
    });

    document.getElementById('logistics-matrix-search')?.addEventListener('input', () => {
        renderLogistics3DShelfMatrix();
    });

    document.getElementById('logistics-matrix-refresh-btn')?.addEventListener('click', refreshLogisticsMatrixOverview);

    document.getElementById('logistics-market-search')?.addEventListener('input', (e) => {
        NyxState.logistics.marketSearchQuery = e.target.value;
        renderLogisticsCommodityTable();
    });

    document.getElementById('logistics-market-zone-filter')?.addEventListener('change', (e) => {
        NyxState.logistics.zoneFilter = e.target.value;
        renderLogisticsCommodityTable();
    });

    document.getElementById('logistics-market-cat-filter')?.addEventListener('change', (e) => {
        NyxState.logistics.categoryFilter = e.target.value;
        renderLogisticsCommodityTable();
    });

    document.getElementById('logistics-market-refresh-btn')?.addEventListener('click', refreshLogisticsMarketOverview);

    document.getElementById('logistics-arbitrage-refresh-btn')?.addEventListener('click', refreshLogisticsArbitrageRoutes);

    document.getElementById('logistics-btn-reserve-slot')?.addEventListener('click', () => {
        if (NyxState.logistics.selectedNodeId) {
            openReserveSlotModal(NyxState.logistics.selectedNodeId);
        } else {
            showNotification({ type: 'warning', title: 'NINCS KIVÁLASZTVA', message: 'Kérlek válassz ki egy polchelyet a rácsból a foglaláshoz!' });
        }
    });

    document.getElementById('logistics-submodal-reserve-close')?.addEventListener('click', closeReserveSlotModal);
    document.getElementById('logistics-reserve-cancel-btn')?.addEventListener('click', closeReserveSlotModal);
    document.getElementById('logistics-reserve-confirm-btn')?.addEventListener('click', submitReserveSlot);

    // Mechanical Diagnostics & Civic Impound Terminal Listeners
    document.getElementById('vehicle-terminal-close')?.addEventListener('click', closeVehicleTerminal);

    document.querySelectorAll('#vehicle-terminal-overlay .tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const tab = btn.getAttribute('data-vehicle-tab');
            if (tab) switchVehicleTab(tab);
        });
    });

    document.getElementById('vehicle-btn-scan-obd')?.addEventListener('click', scanVehicleOBD);
    document.getElementById('vehicle-btn-reset-trip')?.addEventListener('click', resetVehicleTripOdometer);
    document.getElementById('vehicle-btn-renew-reg')?.addEventListener('click', renewVehicleRegistration);

    document.getElementById('vehicle-submodal-service-close')?.addEventListener('click', closeVehicleServiceModal);
    document.getElementById('vehicle-service-cancel-btn')?.addEventListener('click', closeVehicleServiceModal);
    document.getElementById('vehicle-service-confirm-btn')?.addEventListener('click', submitVehicleService);

    document.getElementById('vehicle-submodal-release-close')?.addEventListener('click', closeVehicleReleaseModal);
    document.getElementById('vehicle-release-cancel-btn')?.addEventListener('click', closeVehicleReleaseModal);
    document.getElementById('vehicle-release-confirm-btn')?.addEventListener('click', submitVehicleRelease);

    document.getElementById('vehicle-impound-search')?.addEventListener('input', renderVehicleImpounds);
    document.getElementById('vehicle-impound-lot-filter')?.addEventListener('change', renderVehicleImpounds);

    // Citizen OS Master Smartphone Listeners
    document.querySelectorAll('.phone-app-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const app = btn.getAttribute('data-app');
            if (app) switchPhoneApp(app);
        });
    });

    document.getElementById('phone-home-bar')?.addEventListener('click', () => {
        switchPhoneApp('home');
    });

    document.getElementById('phone-back-btn')?.addEventListener('click', () => {
        switchPhoneApp('home');
    });

    document.getElementById('phone-refresh-btn')?.addEventListener('click', refreshPhoneOverview);

    // Banking wire transfer listeners
    document.getElementById('phone-transfer-amount')?.addEventListener('input', (e) => {
        const val = parseFloat(e.target.value) || 0;
        const rate = (NyxState.phone && NyxState.phone.banking && NyxState.phone.banking.transferTaxRate) || 0.02;
        const fee = Math.round(val * rate * 100) / 100;
        const feeEl = document.getElementById('phone-transfer-fee-preview');
        if (feeEl) feeEl.textContent = `$${fee.toFixed(2)} (Összesen: $${(val + fee).toFixed(2)})`;
    });

    document.getElementById('phone-transfer-submit-btn')?.addEventListener('click', handlePhoneTransferSubmit);

    // Logistics freight board listeners
    document.getElementById('phone-haul-search-input')?.addEventListener('input', fetchPhoneFreightBoard);

    document.getElementById('phone-haul-load-btn')?.addEventListener('click', async () => {
        const haul = NyxState.phone.logistics.activeHaul;
        if (!haul) return;
        const btn = document.getElementById('phone-haul-load-btn');
        lockButtonAction(btn, async () => {
            const res = await postNui('phone:loadFreightPallet', { contractId: haul.id });
            if (res && res.success) {
                playWebBeep(920, 'sine', 0.1);
                showNotification({ type: 'success', title: 'RAKOMÁNY BERAKODVA', message: 'A rakomány sikeresen felrakodva a járműre!' });
            } else {
                showNotification({ type: 'error', title: 'BERAKODÁS SIKERTELEN', message: res?.error || 'A rakodás sikertelen.' });
            }
        });
    });

    document.getElementById('phone-haul-deliver-btn')?.addEventListener('click', async () => {
        const haul = NyxState.phone.logistics.activeHaul;
        if (!haul) return;
        const btn = document.getElementById('phone-haul-deliver-btn');
        lockButtonAction(btn, async () => {
            const res = await postNui('phone:deliverContract', { contractId: haul.id });
            if (res && res.success) {
                playWebBeep(1100, 'sine', 0.15);
                showNotification({ type: 'success', title: 'FUVAR TELJESÍTVE', message: 'A rakomány sikeresen leadva a rendeltetési helyen! Kifizetés jóváírva.' });
                await refreshPhoneOverview();
            } else {
                showNotification({ type: 'error', title: 'ÁTADÁS SIKERTELEN', message: res?.error || 'A célállomáson nem sikerült az átadás.' });
            }
        });
    });

    document.getElementById('phone-haul-abandon-btn')?.addEventListener('click', async () => {
        const haul = NyxState.phone.logistics.activeHaul;
        if (!haul) return;
        const btn = document.getElementById('phone-haul-abandon-btn');
        lockButtonAction(btn, async () => {
            const res = await postNui('phone:abandonContract', { contractId: haul.id });
            if (res && res.success) {
                showNotification({ type: 'warning', title: 'FUVAR MEGSZAKÍTVA', message: 'Fuvarmegbízás feladva. A kaució elveszett.' });
                await refreshPhoneOverview();
            } else {
                showNotification({ type: 'error', title: 'HIBA', message: res?.error || 'Nem sikerült megszakítani.' });
            }
        });
    });

    // 911 SOS Alert authoring listener
    document.getElementById('phone-alert-submit-btn')?.addEventListener('click', handlePhoneAlertSubmit);

    // Settings save listener
    document.getElementById('phone-settings-save-btn')?.addEventListener('click', handlePhoneSettingsSave);

    // Dialog Confirm & Cancel
    document.getElementById('dialog-confirm-btn')?.addEventListener('click', () => closeDialog(true));
    document.getElementById('dialog-cancel-btn')?.addEventListener('click', () => closeDialog(false));
    document.getElementById('dialog-close-btn')?.addEventListener('click', () => closeDialog(false));

    // Focus & Lifecycle Failsafes: Keyboard Escape & Backspace Hierarchy
    document.addEventListener('keydown', (e) => {
        const activeEl = document.activeElement;
        const isEditing = isEditableElement(activeEl);

        // Protect text input: do not intercept Backspace when typing
        if (e.key === 'Backspace' && isEditing) {
            return;
        }

        // Trigger hierarchical escape on Escape or Backspace (when not editing)
        if (e.key === 'Escape' || (e.key === 'Backspace' && !isEditing)) {
            // 1. If editing an input, blur it first on Escape
            if (isEditing && e.key === 'Escape') {
                activeEl.blur();
            }

            // 2. Sub-modals / popovers / tooltips / confirmation dialogs first
            const inspectPopover = document.getElementById('inspect-popover');
            if (inspectPopover && !inspectPopover.classList.contains('hidden')) {
                inspectPopover.classList.add('hidden');
                NyxState.inventory.selectedSlot = null;
                document.querySelectorAll('.slot-card.selected').forEach(s => s.classList.remove('selected'));
                return;
            }

            const factionSubMember = document.getElementById('faction-submodal-member');
            if (factionSubMember && !factionSubMember.classList.contains('hidden')) {
                factionSubMember.classList.add('hidden');
                return;
            }

            const factionSubWithdraw = document.getElementById('faction-submodal-withdraw');
            if (factionSubWithdraw && !factionSubWithdraw.classList.contains('hidden')) {
                factionSubWithdraw.classList.add('hidden');
                return;
            }

            const parliamentRecallSubmodal = document.getElementById('parliament-submodal-recall');
            if (parliamentRecallSubmodal && !parliamentRecallSubmodal.classList.contains('hidden')) {
                parliamentRecallSubmodal.classList.add('hidden');
                return;
            }

            const propBidSubmodal = document.getElementById('property-submodal-bid');
            if (propBidSubmodal && !propBidSubmodal.classList.contains('hidden')) {
                closeAuctionBidModal();
                return;
            }

            const propAssignSubmodal = document.getElementById('property-submodal-assign');
            if (propAssignSubmodal && !propAssignSubmodal.classList.contains('hidden')) {
                closeAssignStewardModal();
                return;
            }

            const logisticsReserveSubmodal = document.getElementById('logistics-submodal-reserve');
            if (logisticsReserveSubmodal && !logisticsReserveSubmodal.classList.contains('hidden')) {
                closeReserveSlotModal();
                return;
            }

            const vehicleServiceSubmodal = document.getElementById('vehicle-submodal-service');
            if (vehicleServiceSubmodal && !vehicleServiceSubmodal.classList.contains('hidden')) {
                closeVehicleServiceModal();
                return;
            }

            const vehicleReleaseSubmodal = document.getElementById('vehicle-submodal-release');
            if (vehicleReleaseSubmodal && !vehicleReleaseSubmodal.classList.contains('hidden')) {
                closeVehicleReleaseModal();
                return;
            }

            const dialogOverlay = document.getElementById('dialog-overlay');
            if (dialogOverlay && !dialogOverlay.classList.contains('hidden')) {
                closeDialog(false);
                return;
            }

            // 3. Main screens
            if (NyxState.inventory.isOpen) {
                closeInventory();
                return;
            }
            if (NyxState.treasury.isOpen) {
                closeTreasuryDashboard();
                return;
            }
            if (NyxState.faction.isOpen) {
                closeFactionDashboard();
                return;
            }
            if (NyxState.court.isOpen) {
                const subpDisclosure = document.getElementById('court-subpoena-disclosure');
                if (subpDisclosure && !subpDisclosure.classList.contains('hidden')) {
                    subpDisclosure.classList.add('hidden');
                    return;
                }
                closeCourtTerminal();
                return;
            }
            if (NyxState.parliament.isOpen) {
                closeParliamentUI();
                return;
            }
            if (NyxState.property.isOpen) {
                closePropertyPortal();
                return;
            }
            if (NyxState.logistics.isOpen) {
                closeMarketMonitor();
                return;
            }
            if (NyxState.vehicle && NyxState.vehicle.isOpen) {
                closeVehicleTerminal();
                return;
            }
            if (NyxState.phone && NyxState.phone.isOpen) {
                if (NyxState.phone.activeApp !== 'home') {
                    switchPhoneApp('home');
                } else {
                    closePhone();
                }
                return;
            }
            if (NyxState.mdt.isOpen) {
                closeMdt();
                return;
            }
            const freightOverlay = document.getElementById('freight-overlay');
            if (freightOverlay && !freightOverlay.classList.contains('hidden')) {
                freightOverlay.classList.add('hidden');
                postNui('closeFreightBoard', {});
                return;
            }
            if (NyxState.interact.hasTarget || NyxState.interact.active) {
                clearInteractTarget();
                setInteractActive(false);
                postNui('close', { app: 'interact' });
                return;
            }

            // Fallback: release NUI focus
            postNui('close', { app: 'generic' });
        } else if (['1', '2', '3', '4', '5'].includes(e.key) && !isEditing && !NyxState.inventory.isOpen) {
            const slotNum = parseInt(e.key, 10);
            postNui('hotbar:useSlot', { slot: slotNum });
            document.querySelectorAll('.hotbar-slot').forEach(s => s.classList.remove('active'));
            const activeSlot = document.querySelector(`.hotbar-slot[data-slot="${slotNum}"]`);
            if (activeSlot) {
                activeSlot.classList.add('active');
                setTimeout(() => activeSlot.classList.remove('active'), 250);
            }
        }
    });

    // Announce SPA mounted handshake to native client
    postNui('uiReady', {});

    // Desktop Browser Dev Mode Setup
    if (isBrowserDev) {
        initBrowserDevMode();
    }
});

// 15. Desktop Browser Dev Mode Fallbacks & Dev Toolbar
function initBrowserDevMode() {
    const devBar = document.getElementById('dev-mode-bar');
    if (devBar) devBar.classList.remove('hidden');

    // Populate mock HUD
    updateHudStatus({
        visible: true,
        vitals: {
            health: 88,
            armor: 50,
            hunger: 72,
            thirst: 85,
            stamina: 95,
            voiceRange: 2,
            isUnderwater: false,
            isDead: false
        },
        vehicle: {
            inVehicle: true,
            speed: 68,
            rpm: 0.74,
            engineHealth: 950,
            fuel: 82,
            gear: 4
        },
        finances: {
            cash: 4250,
            bank: 148500
        }
    });

    // Populate mock Hotbar
    updateHotbar({
        1: { name: 'phone', label: 'Smartphone', icon: 'fa-solid fa-mobile-screen-button' },
        2: { name: 'bandage', label: 'Sterile Bandage', icon: 'fa-solid fa-bandage' },
        3: { name: 'repairkit', label: 'Toolbox', icon: 'fa-solid fa-wrench' },
        4: { name: 'water', label: 'Spring Water', icon: 'fa-solid fa-bottle-water' },
        5: { name: 'weapon_pistol', label: 'Combat Pistol', icon: 'fa-solid fa-gun' }
    });

    // Sample inventory mock items
    const sampleItems = {
        1: { id: 'weapon_pistol', name: 'weapon_pistol', label: 'Combat Pistol', icon: 'fa-solid fa-gun', count: 1, type: 'weapon', durability: 94, maxDurability: 100, metadata: { Serial: 'W-98214', Ballistics: '9x19mm' } },
        2: { id: 'ammo_pistol', name: 'ammo_pistol', label: '9mm Rounds', icon: 'fa-solid fa-bullseye', count: 48, type: 'ammo' },
        3: { id: 'sandwich', name: 'sandwich', label: 'Club Sandwich', icon: 'fa-solid fa-burger', count: 2, type: 'food', decay: 0.15 },
        4: { id: 'water', name: 'water', label: 'Spring Water', icon: 'fa-solid fa-bottle-water', count: 3, type: 'drink' },
        5: { id: 'repairkit', name: 'repairkit', label: 'Heavy Tool Set', icon: 'fa-solid fa-toolbox', count: 1, type: 'tool', durability: 42, maxDurability: 100, metadata: { Quality: 'Grade A' } },
        6: { id: 'spoiled_meat', name: 'spoiled_meat', label: 'Raw Steak', icon: 'fa-solid fa-drumstick-bite', count: 1, type: 'food', isSpoiled: true, decay: 1.0 }
    };

    const sampleTargetItems = {
        1: { id: 'evidence_box', name: 'evidence_box', label: 'Forensic Evidence Box', icon: 'fa-solid fa-fingerprint', count: 1, type: 'evidence', metadata: { ChainHash: 'a7f3e8...', Exhibit: 'EX-01' } },
        2: { id: 'lockpick', name: 'lockpick', label: 'Steel Lockpick', icon: 'fa-solid fa-key', count: 5, type: 'tool' },
        3: { id: 'gold_bar', name: 'gold_bar', label: 'Bullion Ingot', icon: 'fa-solid fa-coins', count: 2, type: 'valuable', metadata: { Purity: '99.9%' } }
    };

    // Dev Toolbar Button Handlers
    document.getElementById('dev-btn-hud')?.addEventListener('click', () => {
        const hud = document.getElementById('hud-container');
        if (hud) hud.classList.toggle('hidden');
    });

    document.getElementById('dev-btn-inv')?.addEventListener('click', () => {
        if (NyxState.inventory.isOpen) {
            closeInventory();
        } else {
            openInventory({
                player: { items: sampleItems, weight: 14200, maxWeight: 60000, slots: 50 },
                target: { label: 'Vehicle Trunk (Declasse Granger)', icon: 'fa-solid fa-car', items: sampleTargetItems, weight: 8500, maxWeight: 80000, slots: 60 }
            });
        }
    });

    document.getElementById('dev-btn-mdt')?.addEventListener('click', () => {
        if (NyxState.mdt.isOpen) {
            closeMdt();
        } else {
            openMdt({
                calls: [
                    { id: 101, title: '10-31 Shots Fired MRPD Vicinity', location: 'Legion Square, Mission Row', caller: 'Officer Davies', time: '14:22', description: 'Automatic gunfire reported near central bank parking.' },
                    { id: 102, title: '10-99 Officer Down / Panic Alarm', location: 'Strawberry Ave / Olympic Fwy', caller: 'Dispatch CAD', time: '14:28', description: 'Unit 2-Lincoln requesting immediate Code 3 backup.' }
                ]
            });
        }
    });

    document.getElementById('dev-btn-treasury')?.addEventListener('click', () => {
        if (NyxState.treasury.isOpen) {
            closeTreasuryDashboard();
        } else {
            openTreasuryDashboard({
                fiscalState: 'THROTTLED',
                masterReserve: 3850000.0,
                targetReserve: 5000000.0,
                criticalReserve: 500000.0,
                cautionReserve: 2500000.0,
                salesTaxRate: 0.08,
                transferTaxRate: 0.02,
                balanceSheet: {
                    totalLiquidity: 5250000.0,
                    masterReserve: 3850000.0,
                    isBalanced: true,
                    accounts: [
                        { accountId: 'gov:city:master', label: 'Los Santos City Master Reserve', type: 'public_master', balance: 3850000.0, sharePercentage: 73.3, capLimit: null, solvencyStatus: 'SOLVENT' },
                        { accountId: 'gov:tax:pool', label: 'Municipal Tax Accumulation Pool', type: 'tax_pool', balance: 150000.0, sharePercentage: 2.9, capLimit: null, solvencyStatus: 'SOLVENT' },
                        { accountId: 'gov:dept:police', label: 'Los Santos Police Department', type: 'department', balance: 450000.0, sharePercentage: 8.6, capLimit: 1500000.0, solvencyStatus: 'SOLVENT' },
                        { accountId: 'gov:dept:ems', label: 'San Andreas Emergency Medical Services', type: 'department', balance: 320000.0, sharePercentage: 6.1, capLimit: 1000000.0, solvencyStatus: 'SOLVENT' },
                        { accountId: 'gov:dept:works', label: 'Department of Public Works & Transit', type: 'department', balance: 280000.0, sharePercentage: 5.3, capLimit: 1000000.0, solvencyStatus: 'SOLVENT' },
                        { accountId: 'gov:dept:dividend', label: 'Citizen Universal Dividend Pool', type: 'grant_pool', balance: 200000.0, sharePercentage: 3.8, capLimit: null, solvencyStatus: 'SOLVENT' }
                    ]
                },
                allocations: [
                    { departmentLabel: 'Los Santos Police Department', targetDepartment: 'gov:dept:police', allocationCategory: 'emergency_services', percentageSplit: 35.0, currentBalance: 450000.0, capLimit: 1500000.0, progressPercentage: 30.0, lastAllocatedAmount: 52500.0, lastAllocatedAt: '2026-10-18 14:00' },
                    { departmentLabel: 'San Andreas Emergency Medical Services', targetDepartment: 'gov:dept:ems', allocationCategory: 'emergency_services', percentageSplit: 25.0, currentBalance: 320000.0, capLimit: 1000000.0, progressPercentage: 32.0, lastAllocatedAmount: 37500.0, lastAllocatedAt: '2026-10-18 14:00' },
                    { departmentLabel: 'Department of Public Works & Transit', targetDepartment: 'gov:dept:works', allocationCategory: 'infrastructure', percentageSplit: 25.0, currentBalance: 280000.0, capLimit: 1000000.0, progressPercentage: 28.0, lastAllocatedAmount: 37500.0, lastAllocatedAt: '2026-10-18 14:00' },
                    { departmentLabel: 'Citizen Universal Dividend Pool', targetDepartment: 'gov:dept:dividend', allocationCategory: 'social_dividend', percentageSplit: 15.0, currentBalance: 200000.0, capLimit: null, progressPercentage: 0.0, lastAllocatedAmount: 22500.0, lastAllocatedAt: '2026-10-18 14:00' }
                ],
                lastSweep: {
                    sweepUuid: 'swp-20261018-mock-01',
                    collected: 150000.0,
                    totalSwept: 150000.0,
                    masterSurplusRetained: 0.0,
                    allocationsCount: 4,
                    fiscalState: 'THROTTLED',
                    timestamp: '2026-10-18 14:00'
                },
                recentTransactions: [
                    { timestamp: '14:20:05', category: 'pos_tax', debitAccount: 'char:1002:bank', creditAccount: 'gov:tax:pool', amount: 120.50, memo: 'Point-of-sale tax split', authorizedBy: 'system:tax_engine' },
                    { timestamp: '14:21:12', category: 'payroll', debitAccount: 'gov:dept:police', creditAccount: 'char:1005:bank', amount: 850.00, memo: 'Public sector wage disbursement', authorizedBy: 'system:payroll' },
                    { timestamp: '14:25:30', category: 'allocation', debitAccount: 'gov:tax:pool', creditAccount: 'gov:dept:police', amount: 52500.00, memo: 'Statutory Revenue Sweep Split (35%)', authorizedBy: 'cron:tax_sweep' }
                ],
                fiscalTelemetry: {
                    fiscalState: 'THROTTLED',
                    wageMultiplier: 0.88,
                    drainVelocityPerHour: 14500.0,
                    runwayHours: 265.5,
                    circuitTripped: false,
                    infrastructure: { autoRepair: 'ONLINE', impoundSurchargeActive: false, aiDispatch: 'OPTIMAL' }
                },
                circuitBreaker: {
                    tripped: false,
                    tripReason: 'Nincs aktív leoldás',
                    drainVelocity: { totalOutflow: 43500.0 }
                }
            });
        }
    });

    document.getElementById('dev-btn-faction')?.addEventListener('click', () => {
        if (NyxState.faction.isOpen) {
            closeFactionDashboard();
        } else {
            openFactionDashboard();
        }
    });

    document.getElementById('dev-btn-court')?.addEventListener('click', () => {
        if (NyxState.court.isOpen) {
            closeCourtTerminal();
        } else {
            openCourtTerminal({ isJudge: true, activeTab: 'evidence' });
        }
    });

    document.getElementById('dev-btn-parliament')?.addEventListener('click', () => {
        if (NyxState.parliament.isOpen) {
            closeParliamentUI();
        } else {
            openParliamentUI({ activeTab: 'ballot' });
        }
    });

    document.getElementById('dev-btn-property')?.addEventListener('click', () => {
        if (NyxState.property.isOpen) {
            closePropertyPortal();
        } else {
            openPropertyPortal({ activeTab: 'auctions' });
        }
    });

    document.getElementById('dev-btn-logistics')?.addEventListener('click', () => {
        if (NyxState.logistics.isOpen) {
            closeMarketMonitor();
        } else {
            openMarketMonitor({ activeTab: 'matrix' });
        }
    });

    document.getElementById('dev-btn-vehicle')?.addEventListener('click', () => {
        if (NyxState.vehicle && NyxState.vehicle.isOpen) {
            closeVehicleTerminal();
        } else {
            openVehicleTerminal({ activeTab: 'diagnostics' });
        }
    });

    document.getElementById('dev-btn-phone')?.addEventListener('click', () => {
        if (NyxState.phone && NyxState.phone.isOpen) {
            closePhone();
        } else {
            openPhone({ initialApp: 'home' });
        }
    });

    document.getElementById('dev-btn-freight')?.addEventListener('click', () => {
        const overlay = document.getElementById('freight-overlay');
        if (overlay && !overlay.classList.contains('hidden')) {
            overlay.classList.add('hidden');
        } else if (overlay) {
            overlay.classList.remove('hidden');
            renderFreightContracts([
                { contractId: 501, title: 'Metro Medical Supply Haul', itemId: 'medkit', quantity: 25, totalPayout: 3200.00, escrowDeposit: 400.00, deadlineSeconds: 1200, status: 'available' },
                { contractId: 502, title: 'Industrial Parts to Paleto Depot', itemId: 'steel_ingot', quantity: 60, totalPayout: 5800.00, escrowDeposit: 750.00, deadlineSeconds: 2400, status: 'available' }
            ], null);
        }
    });

    document.getElementById('dev-btn-interact')?.addEventListener('click', () => {
        if (NyxState.interact.hasTarget) {
            clearInteractTarget();
            setInteractActive(false);
        } else {
            setInteractActive(true);
            setInteractTarget({
                title: 'Police Armory Stash',
                options: [
                    { id: 1, label: 'Open Storage', icon: 'fa-solid fa-box-open', action: 'open_storage' },
                    { id: 2, label: 'Locker Log', icon: 'fa-solid fa-clipboard-list', action: 'view_log' },
                    { id: 3, label: 'Lock Vault', icon: 'fa-solid fa-lock', action: 'lock_vault' }
                ]
            });
        }
    });

    document.getElementById('dev-btn-place')?.addEventListener('click', () => {
        const overlay = document.getElementById('placement-overlay');
        const isHidden = overlay?.classList.contains('hidden');
        setPlacementActive(isHidden, 'Heavy Freight Crate');
    });

    document.getElementById('dev-btn-toast')?.addEventListener('click', () => {
        showNotification({
            type: 'success',
            title: 'DEV SIMULATION',
            message: 'Master SPA shell verified with strict CEF budget and zero blur!'
        });
    });

    showNotification({
        type: 'info',
        title: 'NUI DEV MODE',
        message: 'Master SPA mounted in desktop browser dev mode. Use dev toolbar at top to inspect states.'
    });
}
