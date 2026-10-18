/**
 * Nyxframework Master Single Page Application (app.js)
 * High-performance state management, NUI envelope router, and visual renderers.
 */

// 1. FiveM NUI Transport Bridge
async function postNui(action, data = {}) {
    try {
        const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'nyx_ui';
        const resp = await fetch(`https://${resourceName}/${action}`, {
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
        mode: 'radial' // 'radial' or 'list'
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
    toast.id = id || `toast_${Date.now()}`;

    let iconClass = 'fa-solid fa-circle-info';
    if (type === 'success') iconClass = 'fa-solid fa-circle-check';
    else if (type === 'error') iconClass = 'fa-solid fa-circle-exclamation';
    else if (type === 'warning') iconClass = 'fa-solid fa-triangle-exclamation';

    toast.innerHTML = `
        <i class="${iconClass} toast-icon"></i>
        <div class="toast-content">
            <div class="toast-title">${title || 'NOTICE'}</div>
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

function setInteractTarget(targetData) {
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
            btn.title = opt.label;
            btn.innerHTML = `<i class="${opt.icon || 'fa-solid fa-hand'}"></i>`;

            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                selectInteractOption(opt);
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
    postNui('interact:selectOption', option);
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
                // Pulse warning when drain below 20%
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
            if (vFill) vFill.style.width = `${(v.voiceRange / 3) * 100}%`;
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

// 7. Dynamic Weight-Based Slot-Grid Inventory (40-120 Slots)
function renderSlots(containerId, invData) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = '';

    if (!invData) {
        container.innerHTML = '<div class="empty-state" style="grid-column: 1 / -1; padding: 40px; text-align: center; color: #64748b;">No Container Connected</div>';
        return;
    }

    const totalSlots = invData.slots || 40;
    const items = invData.items || {};

    for (let i = 1; i <= totalSlots; i++) {
        const slotEl = document.createElement('div');
        slotEl.className = 'slot-card';
        slotEl.dataset.slot = i;
        slotEl.dataset.container = containerId === 'player-slots' ? 'player' : 'target';

        const item = items[i];

        if (item) {
            slotEl.dataset.itemId = item.id || item.name;

            // Durability calculation
            const maxDura = item.maxDurability || 100;
            const curDura = item.durability !== undefined ? item.durability : 100;
            const duraPercent = Math.max(0, Math.min(100, Math.round((curDura / maxDura) * 100)));

            let duraClass = '';
            if (duraPercent < 25) duraClass = 'crit';
            else if (duraPercent < 55) duraClass = 'low';

            // Spoiled / Rotten food detection
            const isSpoiled = item.isSpoiled || (item.decay && item.decay >= 1.0);

            slotEl.innerHTML = `
                <span class="slot-num">${i}</span>
                <i class="${item.icon || 'fa-solid fa-box'} slot-icon"></i>
                <span class="slot-label">${item.label || item.name}</span>
                <span class="slot-count">${item.count > 1 ? item.count : ''}</span>
                <div class="slot-durability-track">
                    <div class="slot-durability-fill ${duraClass}" style="width: ${duraPercent}%;"></div>
                </div>
            `;

            if (isSpoiled) {
                slotEl.style.borderColor = '#ef4444';
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
        // Populate inspect popover
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
            duraBar.style.background = duraPercent < 25 ? '#ef4444' : (duraPercent < 55 ? '#f59e0b' : '#10b981');
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
                row.innerHTML = `<span class="meta-key">${k}:</span><span class="meta-val">${v}</span>`;
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
    fill.style.background = pct > 90 ? 'var(--accent-crimson)' : 'var(--accent-cyan)';
}

function openInventory(data) {
    NyxState.inventory.isOpen = true;
    NyxState.inventory.playerData = data.player || { items: {}, weight: 0, maxWeight: 30000, slots: 40 };
    NyxState.inventory.targetData = data.target || null;

    const overlay = document.getElementById('inventory-overlay');
    if (overlay) overlay.classList.remove('hidden');

    renderSlots('player-slots', NyxState.inventory.playerData);
    renderSlots('target-slots', NyxState.inventory.targetData);

    updateWeightMeter('player-weight-label', 'player-weight-fill', NyxState.inventory.playerData);
    updateWeightMeter('target-weight-label', 'target-weight-fill', NyxState.inventory.targetData);

    // Update target container title/icon
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

// 9. Civic Treasury Open Ledger Transparency Dashboard (`nyx_treasury`)
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
    if (kpiBal) kpiBal.textContent = data.isBalanced ? 'BALANCED' : 'IMBALANCE ALERT';

    // Table rows
    const tbody = document.getElementById('treasury-ledger-rows');
    if (tbody) {
        tbody.innerHTML = '';
        (data.recentTransactions || []).forEach(tx => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${tx.timestamp || 'N/A'}</td>
                <td><span class="badge">${tx.category || 'TRANSFER'}</span></td>
                <td><code>${tx.debitAccount}</code></td>
                <td><code>${tx.creditAccount}</code></td>
                <td><strong>$${Number(tx.amount || 0).toFixed(2)}</strong></td>
                <td>${tx.memo || '-'}</td>
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
        list.innerHTML = '<div class="empty-state">Nincs aktív 911 vészhívás a rendszerben.</div>';
        return;
    }

    calls.forEach(call => {
        const item = document.createElement('div');
        item.className = 'dispatch-item';
        item.innerHTML = `
            <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
                <strong style="color: var(--accent-cyan);">#${call.id} - ${call.title}</strong>
                <span style="font-size: 10px; color: var(--text-dim);">${call.time || 'NOW'}</span>
            </div>
            <div style="font-size: 11px; color: var(--text-muted);">${call.location || 'Unknown Location'}</div>
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
        <h4 style="font-family: var(--font-display); margin-bottom: 8px;">${call.title}</h4>
        <div style="font-size: 12px; line-height: 1.5; color: var(--text-muted); margin-bottom: 12px;">
            ${call.description || 'Nincs további megjegyzés.'}
        </div>
        <div style="font-family: var(--font-mono); font-size: 11px; margin-bottom: 14px;">
            <div>Helyszín: ${call.location}</div>
            <div>Bejelentő: ${call.caller || 'Anonymus'}</div>
        </div>
        <button class="btn btn-primary" id="mdt-respond-btn" style="width: 100%;"><i class="fa-solid fa-location-arrow"></i> GPS Útvonal Beállítása</button>
    `;

    document.getElementById('mdt-respond-btn').addEventListener('click', () => {
        postNui('mdt:respondCall', { callId: call.id });
    });
}

// 11. Global NUI Envelope Dispatcher
window.addEventListener('message', (event) => {
    const packet = event.data;
    if (!packet) return;

    const action = packet.action;

    // Reticle & Raycasting
    if (action === 'INTERACT_SET_ACTIVE') {
        setInteractActive(packet.active);
    } else if (action === 'INTERACT_SET_TARGET') {
        setInteractTarget(packet.target);
    } else if (action === 'INTERACT_CLEAR_TARGET') {
        clearInteractTarget();
    }

    // HUD Telemetry
    else if (action === 'HUD_UPDATE') {
        updateHudStatus(packet.payload);
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
    else if (action === 'NOTIFY') {
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
});

// 12. Freight Hauling Board Renderer
function renderFreightContracts(contracts, activeContract) {
    const list = document.getElementById('freight-contracts-list');
    const activeBanner = document.getElementById('freight-active-banner');
    const activeDetails = document.getElementById('freight-active-details');

    if (activeContract && activeBanner && activeDetails) {
        activeBanner.classList.remove('hidden');
        activeDetails.innerHTML = `
            <strong>${activeContract.title}</strong><br>
            Célállomás: <code>${activeContract.destInv || 'Store Shelf'}</code> | Mennyiség: <strong>${activeContract.quantity}x</strong><br>
            Fuvardíj jóváírás: <strong style="color: #10b981;">+$${activeContract.totalPayout.toFixed(2)}</strong> | Zárolt Letét: <strong style="color: #f59e0b;">$${activeContract.escrowDeposit.toFixed(2)}</strong>
        `;
    } else if (activeBanner) {
        activeBanner.classList.add('hidden');
    }

    if (list) {
        list.innerHTML = '';
        if (contracts.length === 0) {
            list.innerHTML = '<div class="empty-state">Jelenleg nincs aktív hiánymegbízás a tőzsdén.</div>';
            return;
        }

        contracts.forEach(c => {
            if (c.status !== 'available') return;
            const item = document.createElement('div');
            item.className = 'freight-item';
            item.innerHTML = `
                <div>
                    <div style="font-weight: 600; font-size: 13px; color: #f8fafc;">${c.title}</div>
                    <div style="font-size: 11px; color: #94a3b8;">Rakomány: ${c.quantity}x ${c.itemId} | Határidő: ${Math.round((c.deadlineSeconds || 1800) / 60)} perc</div>
                </div>
                <div style="display: flex; align-items: center; gap: 14px;">
                    <div style="text-align: right;">
                        <div style="color: #10b981; font-weight: 700;">+$${c.totalPayout.toFixed(2)}</div>
                        <div style="font-size: 10px; color: #f59e0b;">Kaució: $${c.escrowDeposit.toFixed(2)}</div>
                    </div>
                    <button class="btn btn-primary" onclick="claimFreightContract(${c.contractId})"><i class="fa-solid fa-file-signature"></i> Elvállal</button>
                </div>
            `;
            list.appendChild(item);
        });
    }
}

function claimFreightContract(contractId) {
    postNui('claimFreightContract', { contractId });
}

// 13. Event Listeners & Keyboard Escape Handling
document.addEventListener('DOMContentLoaded', () => {
    // Inventory Actions
    document.getElementById('inv-close-btn')?.addEventListener('click', closeInventory);
    document.getElementById('inv-use-btn')?.addEventListener('click', () => {
        if (NyxState.inventory.selectedSlot) {
            postNui('inventory:useItem', { slot: NyxState.inventory.selectedSlot });
        }
    });
    document.getElementById('inv-drop-btn')?.addEventListener('click', () => {
        if (NyxState.inventory.selectedSlot) {
            const splitCount = parseInt(document.getElementById('inv-split-input')?.value || '1', 10);
            postNui('inventory:dropItem', { slot: NyxState.inventory.selectedSlot, amount: splitCount });
        }
    });

    // Freight Actions
    document.getElementById('freight-close-btn')?.addEventListener('click', () => {
        document.getElementById('freight-overlay')?.classList.add('hidden');
        postNui('closeFreightBoard', {});
    });
    document.getElementById('freight-load-btn')?.addEventListener('click', () => {
        postNui('loadFreightPallet', {});
    });
    document.getElementById('freight-deliver-btn')?.addEventListener('click', () => {
        postNui('deliverFreightContract', {});
    });

    // Treasury Actions
    document.getElementById('treasury-close-btn')?.addEventListener('click', closeTreasuryDashboard);

    // MDT Actions & Tabs
    document.getElementById('mdt-close-btn')?.addEventListener('click', closeMdt);
    document.querySelectorAll('.mdt-tab').forEach(tab => {
        tab.addEventListener('click', () => {
            document.querySelectorAll('.mdt-tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.mdt-tab-pane').forEach(p => p.classList.add('hidden'));

            tab.classList.add('active');
            const targetPane = document.getElementById(`mdt-tab-${tab.dataset.tab}`);
            if (targetPane) targetPane.classList.remove('hidden');
        });
    });

    // Global Key Listener (ESC & Hotbar 1-5)
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (NyxState.inventory.isOpen) closeInventory();
            if (NyxState.treasury.isOpen) closeTreasuryDashboard();
            if (NyxState.mdt.isOpen) closeMdt();
            const freightOverlay = document.getElementById('freight-overlay');
            if (freightOverlay && !freightOverlay.classList.contains('hidden')) {
                freightOverlay.classList.add('hidden');
                postNui('closeFreightBoard', {});
            }
        } else if (['1', '2', '3', '4', '5'].includes(e.key) && !NyxState.inventory.isOpen) {
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
});
