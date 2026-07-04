// LmZa_Chat · html/chat.js
'use strict';

// ── Config (overridden by ON_CONFIG from Lua) ─────────────────────────────────
let MAX_MESSAGES  = 50;
let FADE_TIMEOUT  = 8000;
let HISTORY_SIZE  = 20;

const msgList   = document.getElementById('chat-messages');
const chatPanel = document.getElementById('chat-panel');
const inputBar  = document.getElementById('input-container');
const chatInput = document.getElementById('chat-input');
const charCount = document.getElementById('char-count');
const sugList   = document.getElementById('suggestions');

let fadeTimers   = [];
let focusTimer   = null;
let suggestions  = [];
let activeIndex  = -1;
let isOpen       = false;

// ── Scroll history ────────────────────────────────────────────────────────────
let history     = [];   // sent messages, oldest first
let historyIdx  = -1;   // -1 = not browsing; 0 = oldest
let draftSave   = '';   // stash the current draft when browsing starts

// ── Resource name ─────────────────────────────────────────────────────────────
const RESOURCE_NAME = (typeof window.GetParentResourceName === 'function')
    ? window.GetParentResourceName()
    : 'LmZa_Chat';

function post(endpoint, payload) {
    return fetch('https://' + RESOURCE_NAME + '/' + endpoint, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(payload || {})
    });
}

// ── Signal ready ──────────────────────────────────────────────────────────────
window.addEventListener('load', () => { post('loaded', {}); });

// ── Message types ─────────────────────────────────────────────────────────────
// msgType from server: 'global' | 'me'
// internal NUI types: 'self' | 'other' | 'system' | 'me'

function addMessage(name, text, timestamp, isSelf, isSystem) {
    const cssType = isSystem ? 'system' : (isSelf ? 'self' : 'other');

    const el = document.createElement('div');
    el.classList.add('msg', 'type-' + cssType);

    const nameEl = document.createElement('span');
    nameEl.classList.add('msg-name');

    const textEl = document.createElement('span');
    textEl.classList.add('msg-text');

    const timeEl = document.createElement('span');
    timeEl.classList.add('msg-time');
    timeEl.textContent = timestamp;

    nameEl.textContent = name;
    textEl.textContent = text;

    el.appendChild(nameEl);
    el.appendChild(textEl);
    el.appendChild(timeEl);
    msgList.appendChild(el);

    while (msgList.children.length > MAX_MESSAGES)
        msgList.removeChild(msgList.firstChild);

    msgList.scrollTop = msgList.scrollHeight;
    showPanel();
    // Only start the fade timer when the chat is closed. While the input is
    // open we keep everything visible; rescheduleFades() restarts the timers
    // fresh on close so messages don't vanish mid-read.
    if (!isOpen) scheduleFade(el);
}

// ── Panel visibility ─────────────────────────────────────────────────────────
// #chat-panel (the wood backing board) stays hidden whenever there's nothing
// to show it for — otherwise its border/background sit on screen as an empty
// bar even with no messages and the input closed.
function showPanel() {
    chatPanel.classList.remove('hidden');
}

function updatePanelVisibility() {
    if (!isOpen && msgList.children.length === 0) {
        chatPanel.classList.add('hidden');
    }
}

// ── Fades ─────────────────────────────────────────────────────────────────────
function scheduleFade(el) {
    const t = setTimeout(() => {
        el.classList.add('removing');
        setTimeout(() => {
            if (el.parentNode) el.parentNode.removeChild(el);
            updatePanelVisibility();
        }, 200);
    }, FADE_TIMEOUT);
    fadeTimers.push({ el, t });
}

function cancelAllFades() {
    fadeTimers.forEach(({ t }) => clearTimeout(t));
    fadeTimers = [];
    Array.from(msgList.children).forEach(el => {
        el.classList.remove('removing');
        el.style.opacity = '1';
    });
}

function rescheduleFades() {
    // Clear any stale timers first so a message can never carry two timers
    // (one from arrival-while-open, one from here) and fade early.
    cancelAllFades();
    setTimeout(() => {
        Array.from(msgList.children).forEach(el => scheduleFade(el));
    }, 2000);
}

// ── Clear ─────────────────────────────────────────────────────────────────────
function clearChat() {
    cancelAllFades();
    while (msgList.firstChild) msgList.removeChild(msgList.firstChild);
    updatePanelVisibility();
}

// ── Suggestions ───────────────────────────────────────────────────────────────
function renderSuggestions(filter) {
    sugList.innerHTML = '';
    activeIndex = -1;

    if (!filter || filter === '') {
        sugList.classList.add('hidden');
        return;
    }

    const query   = filter.toLowerCase();
    const matches = suggestions.filter(s => s.name.toLowerCase().startsWith(query));

    if (matches.length === 0) {
        sugList.classList.add('hidden');
        return;
    }

    sugList.classList.remove('hidden');

    matches.slice(0, 8).forEach((s) => {
        const li = document.createElement('li');

        const nameEl = document.createElement('span');
        nameEl.classList.add('sug-name');
        nameEl.textContent = s.name;

        const helpEl = document.createElement('span');
        helpEl.classList.add('sug-help');
        helpEl.textContent = s.help || '';

        li.appendChild(nameEl);
        li.appendChild(helpEl);

        li.addEventListener('mousedown', e => {
            e.preventDefault();
            chatInput.value = s.name + ' ';
            renderSuggestions('');
            chatInput.focus();
        });

        sugList.appendChild(li);
    });
}

function setActiveIndex(idx) {
    const items = sugList.querySelectorAll('li');
    items.forEach(li => li.classList.remove('active'));
    if (idx >= 0 && idx < items.length) {
        items[idx].classList.add('active');
        activeIndex = idx;
    } else {
        activeIndex = -1;
    }
}

// ── Input open / close ────────────────────────────────────────────────────────
function openInput() {
    isOpen = true;
    showPanel();
    cancelAllFades();

    // Reading mode: full message panel, no top fade, scrolled to newest.
    document.body.classList.add('chat-open');
    msgList.scrollTop = msgList.scrollHeight;

    inputBar.classList.remove('hidden');
    // Replay the reveal animation each time the input opens
    inputBar.style.animation = 'none';
    void inputBar.offsetWidth;
    inputBar.style.animation = 'inputReveal 0.24s cubic-bezier(0.22,1,0.36,1) forwards';

    chatInput.value       = '';
    charCount.textContent = '200';
    charCount.className   = '';
    historyIdx            = -1;
    draftSave             = '';
    renderSuggestions('');

    focusTimer = setTimeout(() => chatInput.focus(), 30);
}

function submitAndClose(msg, canceled) {
    isOpen = false;
    clearTimeout(focusTimer);
    renderSuggestions('');
    document.body.classList.remove('chat-open');
    inputBar.classList.add('hidden');
    chatInput.blur();

    if (!canceled && msg && msg.trim() !== '') {
        pushHistory(msg.trim());
    }

    post('chatResult', { canceled: canceled || false, message: msg || '' });
    chatInput.value = '';
    historyIdx      = -1;
    draftSave       = '';
    rescheduleFades();
    updatePanelVisibility();
}

// ── Scroll history ────────────────────────────────────────────────────────────
function pushHistory(msg) {
    // Avoid duplicate consecutive entries
    if (history.length > 0 && history[history.length - 1] === msg) return;
    history.push(msg);
    if (history.length > HISTORY_SIZE) history.shift();
}

function historyUp() {
    if (history.length === 0) return;
    if (historyIdx === -1) {
        draftSave  = chatInput.value;
        historyIdx = history.length - 1;
    } else if (historyIdx > 0) {
        historyIdx--;
    }
    chatInput.value = history[historyIdx];
    syncCharCount();
    renderSuggestions(chatInput.value.startsWith('/') ? chatInput.value : '');
}

function historyDown() {
    if (historyIdx === -1) return;
    if (historyIdx < history.length - 1) {
        historyIdx++;
        chatInput.value = history[historyIdx];
    } else {
        historyIdx      = -1;
        chatInput.value = draftSave;
    }
    syncCharCount();
    renderSuggestions(chatInput.value.startsWith('/') ? chatInput.value : '');
}

function syncCharCount() {
    const remaining = 200 - chatInput.value.length;
    charCount.textContent = remaining;
    charCount.className   = remaining <= 20 ? 'danger' : remaining <= 50 ? 'warn' : '';
}

// ── Input events ──────────────────────────────────────────────────────────────
chatInput.addEventListener('input', () => {
    // Any manual input cancels history browsing
    historyIdx = -1;
    syncCharCount();
    const val = chatInput.value;
    if (val.startsWith('/')) {
        renderSuggestions(val);
    } else {
        renderSuggestions('');
    }
});

chatInput.addEventListener('keydown', e => {
    const items      = sugList.querySelectorAll('li');
    const sugVisible  = items.length > 0 && !sugList.classList.contains('hidden');

    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault();
        // The suggestion dropdown only owns the arrows while you're actively
        // typing a command (historyIdx === -1). Once you're browsing history,
        // arrows always keep walking history — even if recalling a "/command"
        // pops the suggestion box open.
        if (sugVisible && historyIdx === -1) {
            let next = activeIndex + (e.key === 'ArrowDown' ? 1 : -1);
            next = Math.max(-1, Math.min(next, items.length - 1));
            setActiveIndex(next);
        } else if (e.key === 'ArrowUp') {
            historyUp();
        } else {
            historyDown();
        }
        return;
    }

    // Tab autocompletes top suggestion
    if (e.key === 'Tab') {
        e.preventDefault();
        const pick = activeIndex >= 0 ? items[activeIndex] : items[0];
        if (pick) {
            chatInput.value = pick.querySelector('.sug-name').textContent + ' ';
            renderSuggestions('');
            syncCharCount();
        }
        return;
    }

    if (e.key === 'Enter') {
        e.preventDefault();
        if (activeIndex >= 0 && items[activeIndex]) {
            chatInput.value = items[activeIndex].querySelector('.sug-name').textContent + ' ';
            renderSuggestions('');
            syncCharCount();
            return;
        }
        const msg = chatInput.value.trim();
        submitAndClose(msg, msg === '');
        return;
    }

    if (e.key === 'Escape') {
        e.preventDefault();
        submitAndClose('', true);
    }
});

// ── NUI message handler ───────────────────────────────────────────────────────
window.addEventListener('message', e => {
    const data = e.data;
    if (!data || !data.type) return;

    switch (data.type) {

        case 'ON_CONFIG':
            if (data.fadeTimeout) FADE_TIMEOUT  = data.fadeTimeout;
            if (data.maxMessages) MAX_MESSAGES  = data.maxMessages;
            if (data.historySize) HISTORY_SIZE  = data.historySize;
            break;

        case 'ON_OPEN':
            openInput();
            break;

        case 'ON_MESSAGE':
            addMessage(data.name, data.message, data.timestamp, data.isSelf, false);
            break;

        case 'ON_SYSTEM':
            addMessage('SYSTEM', data.message, data.timestamp, false, true);
            break;

        case 'ON_CLEAR':
            clearChat();
            break;

        case 'ON_SUGGESTIONS':
            suggestions = data.suggestions || [];
            break;

        case 'ON_SUGGESTION_ADD':
            if (data.suggestion) {
                const exists = suggestions.find(s => s.name === data.suggestion.name);
                if (!exists) suggestions.push(data.suggestion);
            }
            break;

        case 'ON_SUGGESTION_REMOVE':
            if (data.name) {
                suggestions = suggestions.filter(s => s.name !== data.name);
            }
            break;
    }
});
