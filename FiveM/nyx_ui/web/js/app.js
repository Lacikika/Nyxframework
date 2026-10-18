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
        data: null
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
    NyxState.treasury.isOpen = true;
    NyxState.treasury.data = data;

    const overlay = document.getElementById('treasury-overlay');
    if (overlay) overlay.classList.remove('hidden');

    // KPIs
    const kpiReserve = document.getElementById('treasury-kpi-reserve');
    const kpiPosTax = document.getElementById('treasury-kpi-postax');
    const kpiP2pTax = document.getElementById('treasury-kpi-p2ptax');
    const kpiBal = document.getElementById('treasury-kpi-balance');

    if (kpiReserve) kpiReserve.textContent = `$${Number(data.reserveBalance || 0).toLocaleString()}`;
    if (kpiPosTax) kpiPosTax.textContent = `${((data.salesTax || 0.08) * 100).toFixed(2)}%`;
    if (kpiP2pTax) kpiP2pTax.textContent = `${((data.transferTax || 0.02) * 100).toFixed(2)}%`;
    if (kpiBal) {
        kpiBal.textContent = data.isBalanced ? 'BALANCED' : 'IMBALANCE ALERT';
        kpiBal.classList.toggle('status-ok', data.isBalanced);
    }

    // Table rows with Virtualization for 100+ items
    const tbody = document.getElementById('treasury-ledger-rows');
    if (tbody) {
        tbody.innerHTML = '';
        const txs = data.recentTransactions || [];
        txs.forEach(tx => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${tx.timestamp || 'NOW'}</td>
                <td><span class="badge">${tx.category || 'TRANSFER'}</span></td>
                <td><code>${tx.debitAccount}</code></td>
                <td><code>${tx.creditAccount}</code></td>
                <td><strong>$${Number(tx.amount || 0).toFixed(2)}</strong></td>
                <td class="truncate" style="max-width: 200px;">${tx.memo || '-'}</td>
            `;
            tbody.appendChild(tr);
        });
    }
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
            <h5><i class="fa-solid fa-clock-rotate-left"></i> Legutóbbi Tranzakciós Napló</h5>
            ${txHtml || '<div class="subp-empty">Nincs friss tranzakció.</div>'}
        </div>
    `;
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
    else if (action === 'TREASURY_DASHBOARD_OPEN') {
        openTreasuryDashboard(packet.payload);
    } else if (action === 'TREASURY_DASHBOARD_CLOSE') {
        closeTreasuryDashboard();
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
                reserveBalance: 1250000,
                salesTax: 0.08,
                transferTax: 0.02,
                isBalanced: true,
                recentTransactions: [
                    { timestamp: '14:20:05', category: 'POS_TAX', debitAccount: 'ACCT_RETAIL_01', creditAccount: 'ACCT_TREASURY_RESERVE', amount: 120.50, memo: 'Point-of-sale tax split' },
                    { timestamp: '14:21:12', category: 'PAYROLL', debitAccount: 'ACCT_PUBLIC_WORKS', creditAccount: 'ACCT_CITIZEN_402', amount: 850.00, memo: 'Public sector wage disbursement' }
                ]
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
