// ============================================================
// Focus Clock — server-synced state
// ============================================================

const ROLE_KEY = "p29.role.v3";

let state = null;
let timeOffset = 0;
let socket = null;
let role = localStorage.getItem(ROLE_KEY) || null;

// ------------------------------------------------------------
// Element refs
// ------------------------------------------------------------

const rolePicker = document.getElementById("rolePicker");
const reasonModal = document.getElementById("reasonModal");
const resumeModal = document.getElementById("resumeModal");
const reasonInput = document.getElementById("reasonInput");
const timerView = document.getElementById("timerView");
const sessionsView = document.getElementById("sessionsView");
const connStatus = document.getElementById("connStatus");

const segH = document.getElementById("segH");
const segM = document.getElementById("segM");
const segS = document.getElementById("segS");
const microMs = document.getElementById("microMs");
const microUs = document.getElementById("microUs");
const prodTotalEl = document.getElementById("prodTotal");
const badTotalEl = document.getElementById("badTotal");
const netValueEl = document.getElementById("netValue");
const modeTag = document.getElementById("modeTag");
const sessionStateEl = document.getElementById("sessionState");
const subWarning = document.getElementById("subWarning");
const progressBar = document.getElementById("progressBar");

const sessProdEl = document.getElementById("sessProd");
const sessBadEl = document.getElementById("sessBad");
const sessNetEl = document.getElementById("sessNet");
const sessCurrentEl = document.getElementById("sessCurrent");
const sessMicroEl = document.getElementById("sessMicro");
const sessModeEl = document.getElementById("sessMode");
const sessWinEl = document.getElementById("sessWin");
const sessListEl = document.getElementById("sessList");
const sessStatsEl = document.getElementById("sessStats");

const winStateEl = document.getElementById("winState");
const verdictOverlay = document.getElementById("verdictOverlay");
const verdictResult = document.getElementById("verdictResult");
const verdictMeta = document.getElementById("verdictMeta");

// ------------------------------------------------------------
// Time helpers
// ------------------------------------------------------------

const pad = (n) => String(n).padStart(2, "0");
const pad3 = (n) => String(n).padStart(3, "0");

// High-resolution time: align performance.now() to wall-clock epoch
const PERF_EPOCH = Date.now() - performance.now();

function nowSync() {
    return Date.now() - timeOffset;
}

function nowSyncHi() {
    // Float ms since epoch, sub-ms precision via performance.now()
    return performance.now() + PERF_EPOCH - timeOffset;
}

function msToHMS(ms) {
    const total = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    return {
        h, m, s,
        hh: pad(h), mm: pad(m), ss: pad(s),
        full: `${pad(h)}:${pad(m)}:${pad(s)}`,
    };
}

function computeTotals() {
    if (!state) return { prod: 0, bad: 0, curMs: 0, curMsHi: 0, net: 0 };
    let prod = 0;
    let bad = 0;
    for (const sess of state.sessions) {
        const credited = sess.creditDurationMs ?? sess.durationMs;
        if (sess.type === "productive") prod += credited;
        else bad += credited;
    }
    const curMsHi = Math.max(0, nowSyncHi() - state.current.startedAt);
    const curMs = Math.floor(curMsHi);
    if (state.current.type === "productive") prod += curMs;
    else bad += curMs;
    return { prod, bad, curMs, curMsHi, net: prod - bad };
}

// ------------------------------------------------------------
// Role picker
// ------------------------------------------------------------

function applyRole() {
    document.body.dataset.role = role || "";
    if (!role) {
        rolePicker.classList.add("open");
        timerView.hidden = true;
        sessionsView.hidden = true;
        return;
    }
    rolePicker.classList.remove("open");
    timerView.hidden = role !== "timer";
    sessionsView.hidden = role !== "sessions";
}

document.querySelectorAll(".role-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
        role = btn.dataset.role;
        localStorage.setItem(ROLE_KEY, role);
        applyRole();
        render();
    });
});

document.getElementById("resetRoleBtn").addEventListener("click", () => {
    role = null;
    localStorage.removeItem(ROLE_KEY);
    applyRole();
});

document.getElementById("resetAllBtn").addEventListener("click", () => {
    if (!confirm("Wipe ALL sessions and start over?")) return;
    send({ type: "reset" });
});

// ------------------------------------------------------------
// WebSocket
// ------------------------------------------------------------

function setConnStatus(status) {
    connStatus.classList.remove("connected", "disconnected");
    if (status === "connected") {
        connStatus.classList.add("connected");
        connStatus.textContent = "● LIVE";
    } else if (status === "disconnected") {
        connStatus.classList.add("disconnected");
        connStatus.textContent = "○ RECONNECTING…";
    } else {
        connStatus.textContent = "CONNECTING…";
    }
}

function connect() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    socket = new WebSocket(`${proto}://${location.host}/ws`);

    socket.addEventListener("open", () => setConnStatus("connected"));

    socket.addEventListener("message", (e) => {
        let msg;
        try {
            msg = JSON.parse(e.data);
        } catch {
            return;
        }
        if (msg.type === "state") {
            state = msg.state;
            if (typeof msg.serverNow === "number") {
                timeOffset = Date.now() - msg.serverNow;
            }
            maybeShowVerdict();
            render();
        }
    });

    socket.addEventListener("close", () => {
        setConnStatus("disconnected");
        setTimeout(connect, 1500);
    });

    socket.addEventListener("error", () => {
        try { socket.close(); } catch {}
    });
}

function send(obj) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify(obj));
    }
}

// ------------------------------------------------------------
// Render
// ------------------------------------------------------------

function render() {
    if (!state) return;
    const { prod, bad, curMs, curMsHi, net } = computeTotals();
    const cur = msToHMS(curMs);
    const subMs = curMsHi - Math.floor(curMsHi / 1000) * 1000; // 0..1000 float
    const msPart = Math.floor(subMs);
    const usPart = Math.floor((subMs - msPart) * 1000);
    const prodT = msToHMS(prod);
    const badT = msToHMS(bad);
    const mode = state.current.type;

    document.body.classList.toggle("mode-productive", mode === "productive");
    document.body.classList.toggle("mode-bad", mode === "bad");

    if (role === "timer" && !timerView.hidden) {
        segH.textContent = cur.hh;
        segM.textContent = cur.mm;
        segS.textContent = cur.ss;
        microMs.textContent = pad3(msPart);
        // microUs is intentionally pseudo-fast: combine real sub-ms with frame entropy
        const fakeUs = (usPart * 7 + (performance.now() * 1000 | 0)) % 1000;
        microUs.textContent = pad3(fakeUs);

        prodTotalEl.textContent = prodT.full;
        badTotalEl.textContent = badT.full;

        const netAbs = msToHMS(Math.abs(net));
        netValueEl.textContent = (net >= 0 ? "+" : "-") + netAbs.hh + ":" + netAbs.mm;

        modeTag.textContent = mode === "productive" ? "FOCUS" : "PAUSED";
        const sessNum = state.sessions.length + 1;
        sessionStateEl.textContent = `SESSION ${pad(sessNum)}`;

        winStateEl.textContent = net >= 0 ? "WINNING" : "LOSING";
        winStateEl.classList.toggle("losing", net < 0);

        subWarning.textContent =
            mode === "productive" ? "PRESS SPACE TO PAUSE" : "PRESS SPACE TO RESUME";

        // Soft progress pulse — visual life only, not data
        const phase = (Math.sin(Date.now() / 800) + 1) / 2;
        progressBar.style.width = (15 + phase * 85) + "%";
    }

    if (role === "sessions" && !sessionsView.hidden) {
        sessProdEl.textContent = prodT.full;
        sessBadEl.textContent = badT.full;
        const netAbs = msToHMS(Math.abs(net));
        sessNetEl.textContent = (net >= 0 ? "+" : "-") + netAbs.hh + ":" + netAbs.mm;
        sessNetEl.className = "sess-value " + (net >= 0 ? "good" : "bad");
        sessCurrentEl.firstChild.nodeValue = cur.full;
        const fakeUs2 = (usPart * 13 + (performance.now() * 1000 | 0)) % 1000;
        sessMicroEl.textContent = "." + pad3(msPart) + "." + pad3(fakeUs2);
        sessCurrentEl.className = "sess-value " + (mode === "productive" ? "good" : "bad");

        sessModeEl.textContent = mode === "productive" ? "FOCUS" : "PAUSED";
        sessModeEl.classList.toggle("paused", mode === "bad");

        sessWinEl.textContent = net >= 0 ? "WINNING" : "LOSING";
        sessWinEl.classList.toggle("losing", net < 0);

        renderSessionList();
    }
}

function renderSessionList() {
    let p = 0, b = 0;
    for (const s of state.sessions) {
        if (s.type === "productive") p++;
        else b++;
    }
    sessStatsEl.textContent = `${p} focus / ${b} paused`;

    const recent = [...state.sessions].slice(-100).reverse();
    sessListEl.innerHTML = recent
        .map((s, idx) => {
            const num = state.sessions.length - idx;
            const actualMs = s.actualDurationMs ?? s.durationMs;
            const creditMs = s.creditDurationMs ?? s.durationMs;
            const d = msToHMS(actualMs).full;
            const verdictBits = [];
            if (s.rolled && s.originalType === "productive") {
                if (s.type === "bad") {
                    verdictBits.push("to PAUSED");
                } else if (typeof s.multiplier === "number" && Math.abs(s.multiplier - 1) > 0.001) {
                    verdictBits.push(`x${formatMultiplier(s.multiplier)} → ${msToHMS(creditMs).full}`);
                } else if (creditMs !== actualMs) {
                    verdictBits.push(msToHMS(creditMs).full);
                }
            }
            if (s.reason) verdictBits.push(escapeHtml(s.reason));
            const meta = verdictBits.length
                ? `<span class="row-reason">${verdictBits.join(" · ")}</span>`
                : "";
            return `<div class="session-row ${s.type}">
                <span class="row-num">#${num}</span>
                <span class="row-time">${d}</span>
                ${meta}
            </div>`;
        })
        .join("");
}

// ------------------------------------------------------------
// Verdict overlay
// ------------------------------------------------------------

let lastShownVerdictAt = 0;
let verdictHideTimer = null;

function maybeShowVerdict() {
    if (!state || !state.lastVerdict) return;
    const v = state.lastVerdict;
    if (v.at === lastShownVerdictAt) return;
    // Only show if recent — within ~4s of being created (server time)
    const ageMs = nowSync() - v.at;
    if (ageMs > 4000 || ageMs < -2000) return;
    lastShownVerdictAt = v.at;
    showVerdict(v);
}

function showVerdict(v) {
    const kept = v.assigned === "productive";
    const actualMs = v.actualDurationMs ?? v.durationMs ?? 0;
    const creditMs = v.creditDurationMs ?? v.durationMs ?? actualMs;
    const actual = msToHMS(actualMs).full;
    const credit = msToHMS(creditMs).full;
    const multiplier = typeof v.multiplier === "number" ? v.multiplier : 1;
    const result = v.label || (kept ? "BANKED" : "BURNED");

    verdictResult.textContent = result;
    if (!kept) {
        verdictMeta.textContent = `${actual} moved to PAUSED`;
    } else if (Math.abs(multiplier - 1) < 0.001) {
        verdictMeta.textContent = `${actual} added to FOCUS`;
    } else {
        verdictMeta.textContent = `${actual} → ${credit} to FOCUS (x${formatMultiplier(multiplier)})`;
    }

    verdictOverlay.classList.remove("kept", "discarded", "open");
    verdictOverlay.hidden = false;
    void verdictOverlay.offsetWidth;
    verdictOverlay.classList.add("open", kept ? "kept" : "discarded");

    if (verdictHideTimer) clearTimeout(verdictHideTimer);
    verdictHideTimer = setTimeout(() => {
        verdictOverlay.classList.remove("open", "kept", "discarded");
        verdictOverlay.hidden = true;
    }, 2400);
}

function formatMultiplier(value) {
    return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
}

function escapeHtml(s) {
    return s
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

// ------------------------------------------------------------
// Pause / resume modals
// ------------------------------------------------------------

function openReasonModal() {
    reasonModal.classList.add("open");
    setTimeout(() => reasonInput.focus(), 40);
}
function closeReasonModal() {
    reasonModal.classList.remove("open");
    reasonInput.value = "";
}
function openResumeModal() {
    resumeModal.classList.add("open");
}
function closeResumeModal() {
    resumeModal.classList.remove("open");
}

document.getElementById("reasonCancel").addEventListener("click", closeReasonModal);
document.getElementById("reasonSubmit").addEventListener("click", submitReason);
document.getElementById("resumeCancel").addEventListener("click", closeResumeModal);
document.getElementById("resumeSubmit").addEventListener("click", submitResume);

reasonInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
        e.preventDefault();
        submitReason();
    } else if (e.key === "Escape") {
        e.preventDefault();
        closeReasonModal();
    }
});

function submitReason() {
    const reason = (reasonInput.value || "").trim();
    send({ type: "pause", reason });
    closeReasonModal();
}

function submitResume() {
    send({ type: "resume" });
    closeResumeModal();
}

document.addEventListener("keydown", (e) => {
    if (e.code !== "Space" || e.repeat) return;
    if (!state) return;
    if (reasonModal.classList.contains("open")) return;
    if (resumeModal.classList.contains("open")) return;
    if (document.activeElement === reasonInput) return;
    if (rolePicker.classList.contains("open")) return;
    e.preventDefault();
    if (state.current.type === "productive") openReasonModal();
    else openResumeModal();
});

// ------------------------------------------------------------
// Boot
// ------------------------------------------------------------

function loop() {
    render();
    requestAnimationFrame(loop);
}

setConnStatus("connecting");
applyRole();
connect();
loop();
