/** @file Advisor page — unified build input, character stats, prompt-driven optimization. */

import { post } from './api.js';
import { fmtNum, fmtChaos, fmtDPS, fmtPct, el, escHtml, showToast, trendClass, createSortableTable } from './utils.js';

const SLOTS = [
  'Body Armour', 'Helmet', 'Gloves', 'Boots',
  'Weapon 1', 'Weapon 2', 'Ring 1', 'Ring 2',
  'Amulet', 'Belt',
];

const PROMPT_EXAMPLES = [
  { text: 'Show item upgrades', query: 'item upgrade' },
  { text: 'Optimize support gems', query: 'gem optimize' },
  { text: 'Show my stats', query: 'stats' },
  { text: 'Decode build XML', query: 'decode' },
];

/** Shared advisor state. */
const state = {
  account: '',
  character: '',
  buildCode: '',
  simResult: null,
  responses: [],
};

/** True when we have build data (either build code or character import). */
function hasBuild() {
  return !!(state.buildCode || state.simResult);
}

/** True when we have a build code (needed for optimize/decode). */
function hasBuildCode() {
  return !!state.buildCode;
}

/** Top-level DOM refs set during init. */
let dom = {};

export async function init(container) {
  container.innerHTML = '';

  // -- Build Input card --
  const buildInput = el('div', { className: 'card' },
    el('h2', { textContent: 'Build Input' }),
    el('div', { className: 'input-row' },
      el('div', { className: 'input-group' },
        el('label', { textContent: 'Account' }),
        el('input', { id: 'adv-account', placeholder: 'Account Name' }),
      ),
      el('div', { className: 'input-group' },
        el('label', { textContent: 'Character' }),
        el('input', { id: 'adv-character', placeholder: 'Character Name' }),
      ),
      el('button', { id: 'adv-import-btn', className: 'btn btn-primary', textContent: 'Import' }),
    ),
    el('div', { className: 'input-row' },
      el('div', { className: 'input-group', style: 'flex:1' },
        el('label', { textContent: 'Build Code' }),
        el('textarea', { id: 'adv-build-code', rows: '2', placeholder: 'eNrt... paste build code' }),
      ),
      el('button', { id: 'adv-load-btn', className: 'btn btn-primary', textContent: 'Load' }),
    ),
  );

  // -- Character panel (left) --
  const charPanel = el('div', { className: 'card', id: 'adv-char-panel' });
  charPanel.innerHTML = '<p class="loading-msg">Import a character or load a build code to begin.</p>';

  // -- Prompt panel (right) --
  const promptTextarea = el('textarea', { id: 'adv-prompt', rows: '3', placeholder: 'Ask about your build...' });
  const askBtn = el('button', { id: 'adv-ask-btn', className: 'btn btn-primary', textContent: 'Ask' });
  const examplesEl = el('div', { className: 'prompt-examples' });
  for (const ex of PROMPT_EXAMPLES) {
    const item = el('div', { className: 'prompt-example', textContent: ex.text });
    item.addEventListener('click', () => {
      promptTextarea.value = ex.query;
      handlePrompt();
    });
    examplesEl.appendChild(item);
  }

  const promptPanel = el('div', { className: 'card advisor-prompt' },
    el('h2', { textContent: 'Prompt' }),
    promptTextarea,
    askBtn,
    examplesEl,
  );

  // -- Split layout --
  const split = el('div', { className: 'advisor-split' }, charPanel, promptPanel);

  // -- Response area --
  const responseArea = el('div', { id: 'adv-responses' });

  container.appendChild(buildInput);
  container.appendChild(split);
  container.appendChild(responseArea);

  // Cache DOM refs
  dom = {
    account: document.getElementById('adv-account'),
    character: document.getElementById('adv-character'),
    importBtn: document.getElementById('adv-import-btn'),
    buildCode: document.getElementById('adv-build-code'),
    loadBtn: document.getElementById('adv-load-btn'),
    charPanel: document.getElementById('adv-char-panel'),
    prompt: document.getElementById('adv-prompt'),
    askBtn: document.getElementById('adv-ask-btn'),
    responses: document.getElementById('adv-responses'),
  };

  // -- Event listeners --
  dom.importBtn.addEventListener('click', handleImport);
  dom.loadBtn.addEventListener('click', handleLoad);
  dom.askBtn.addEventListener('click', handlePrompt);
  dom.prompt.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handlePrompt();
    }
  });
}

/* ============================================================
   Build Input Handlers
   ============================================================ */

async function handleImport() {
  const account = dom.account.value.trim();
  const character = dom.character.value.trim();
  if (!account || !character) {
    showToast('Enter both account and character name.', 'error');
    return;
  }

  state.account = account;
  state.character = character;

  setAllButtons(true);
  renderCharLoading('Importing... (~5s)');

  try {
    const data = await post('/simulate/character', { account, character });
    const unwrapped = data.result ?? data;
    state.simResult = unwrapped.simulation ?? unwrapped;
    if (unwrapped.build_code) {
      state.buildCode = unwrapped.build_code;
    }
    renderCharPanel(state.simResult, unwrapped.character ?? null);
  } catch (err) {
    showToast(err.message, 'error');
    renderCharError(err.message);
  } finally {
    setAllButtons(false);
  }
}

async function handleLoad() {
  const code = dom.buildCode.value.trim();
  if (!code) {
    showToast('Paste a build code.', 'error');
    return;
  }

  state.buildCode = code;
  setAllButtons(true);
  renderCharLoading('Simulating... (~3s)');

  try {
    const data = await post('/simulate', { build_code: code });
    const unwrapped = data.result ?? data;
    state.simResult = unwrapped.simulation ?? unwrapped;
    renderCharPanel(state.simResult, unwrapped.character ?? null);
  } catch (err) {
    showToast(err.message, 'error');
    renderCharError(err.message);
  } finally {
    setAllButtons(false);
  }
}

/* ============================================================
   Prompt Handler — keyword routing
   ============================================================ */

async function handlePrompt() {
  const query = dom.prompt.value.trim();
  if (!query) return;
  dom.prompt.value = '';

  const q = query.toLowerCase();

  if (/아이템|item|upgrade/.test(q)) {
    await runItemOptimize(query);
  } else if (/젬|gem|support/.test(q)) {
    await runGemOptimize(query);
  } else if (/스탯|stat|dps|시뮬/.test(q)) {
    if (state.simResult) {
      addResponse(query, renderStatsCard(state.simResult));
    } else {
      addResponse(query, el('p', { textContent: 'Import a character or load a build first.' }));
    }
  } else if (/decode|xml|디코드/.test(q)) {
    await runDecode(query);
  } else if (hasBuild()) {
    if (state.buildCode) {
      await runResimulate(query);
    } else {
      // Character import — show stats instead of re-simulating
      addResponse(query, renderStatsCard(state.simResult));
    }
  } else {
    addResponse(query, el('p', { textContent: 'Import a character or load a build code first.' }));
  }
}

/* ============================================================
   Prompt Actions
   ============================================================ */

async function runItemOptimize(query) {
  if (!hasBuildCode()) {
    const msg = state.simResult
      ? 'Optimization requires a build code. Paste one in the Build Code field above and click Load.'
      : 'Import a character or load a build code first.';
    addResponse(query, el('p', { textContent: msg }));
    return;
  }

  // Build a slot picker inline
  const wrapper = el('div');
  const row = el('div', { className: 'input-row' });
  const slotSelect = el('select');
  SLOTS.forEach(s => {
    const opt = document.createElement('option');
    opt.value = s;
    opt.textContent = s;
    slotSelect.appendChild(opt);
  });
  const skillInput = el('input', { placeholder: 'Skill (optional)' });
  const budgetInput = el('input', { type: 'number', placeholder: 'Budget (divine)' });
  const runBtn = el('button', { className: 'btn btn-primary', textContent: 'Find Upgrades' });

  row.append(
    el('div', { className: 'input-group' }, el('label', { textContent: 'Slot' }), slotSelect),
    el('div', { className: 'input-group' }, el('label', { textContent: 'Skill' }), skillInput),
    el('div', { className: 'input-group' }, el('label', { textContent: 'Budget (divine)' }), budgetInput),
    runBtn,
  );
  wrapper.appendChild(row);

  const resultArea = el('div');
  wrapper.appendChild(resultArea);

  addResponse(query, wrapper);

  runBtn.addEventListener('click', async () => {
    const slot = slotSelect.value;
    const skill = skillInput.value.trim() || undefined;
    const budgetStr = budgetInput.value.trim();
    const budget = budgetStr ? parseFloat(budgetStr) : undefined;

    runBtn.disabled = true;
    resultArea.innerHTML = '';
    resultArea.appendChild(el('div', { className: 'loading-msg' },
      el('span', { className: 'spinner' }), 'Optimizing... (up to 2 min)',
    ));

    try {
      const data = await post('/optimize/items', {
        build_code: state.buildCode, slot, skill, budget_divine: budget,
      });
      resultArea.innerHTML = '';
      renderItemResult(resultArea, data);
    } catch (err) {
      showToast(err.message, 'error');
      resultArea.innerHTML = '';
      resultArea.appendChild(el('p', { textContent: err.message }));
    } finally {
      runBtn.disabled = false;
    }
  });
}

async function runGemOptimize(query) {
  if (!hasBuildCode()) {
    const msg = state.simResult
      ? 'Optimization requires a build code. Paste one in the Build Code field above and click Load.'
      : 'Import a character or load a build code first.';
    addResponse(query, el('p', { textContent: msg }));
    return;
  }

  const wrapper = el('div');
  const row = el('div', { className: 'input-row' });
  const skillInput = el('input', { placeholder: 'Skill name (e.g. Fire Trap)' });
  const runBtn = el('button', { className: 'btn btn-primary', textContent: 'Optimize Supports' });
  row.append(
    el('div', { className: 'input-group' }, el('label', { textContent: 'Skill' }), skillInput),
    runBtn,
  );
  wrapper.appendChild(row);

  const resultArea = el('div');
  wrapper.appendChild(resultArea);

  addResponse(query, wrapper);

  runBtn.addEventListener('click', async () => {
    const skill = skillInput.value.trim();
    if (!skill) {
      showToast('Enter a skill name.', 'error');
      return;
    }

    runBtn.disabled = true;
    resultArea.innerHTML = '';
    resultArea.appendChild(el('div', { className: 'loading-msg' },
      el('span', { className: 'spinner' }), 'Optimizing... (up to 2 min)',
    ));

    try {
      const data = await post('/optimize/gems', { build_code: state.buildCode, skill });
      resultArea.innerHTML = '';
      renderGemResult(resultArea, data);
    } catch (err) {
      showToast(err.message, 'error');
      resultArea.innerHTML = '';
      resultArea.appendChild(el('p', { textContent: err.message }));
    } finally {
      runBtn.disabled = false;
    }
  });
}

async function runDecode(query) {
  if (!hasBuildCode()) {
    const msg = state.simResult
      ? 'Decode requires a build code. Paste one in the Build Code field above and click Load.'
      : 'Import a character or load a build code first.';
    addResponse(query, el('p', { textContent: msg }));
    return;
  }

  const wrapper = el('div');
  wrapper.appendChild(el('div', { className: 'loading-msg' },
    el('span', { className: 'spinner' }), 'Decoding...',
  ));
  addResponse(query, wrapper);

  try {
    const data = await post('/decode', { build_code: state.buildCode });
    wrapper.innerHTML = '';
    const xmlPanel = el('div', { className: 'result-panel' });
    xmlPanel.innerHTML = escHtml(data.xml || '');
    wrapper.appendChild(xmlPanel);
  } catch (err) {
    showToast(err.message, 'error');
    wrapper.innerHTML = '';
    wrapper.appendChild(el('p', { textContent: err.message }));
  }
}

async function runResimulate(query) {
  const wrapper = el('div');
  wrapper.appendChild(el('div', { className: 'loading-msg' },
    el('span', { className: 'spinner' }), 'Simulating...',
  ));
  addResponse(query, wrapper);

  try {
    const data = await post('/simulate', { build_code: state.buildCode });
    const unwrapped = data.result ?? data;
    state.simResult = unwrapped.simulation ?? unwrapped;
    wrapper.innerHTML = '';
    wrapper.appendChild(renderStatsCard(state.simResult));
    renderCharPanel(state.simResult, unwrapped.character ?? null);
  } catch (err) {
    showToast(err.message, 'error');
    wrapper.innerHTML = '';
    wrapper.appendChild(el('p', { textContent: err.message }));
  }
}

/* ============================================================
   Response Area
   ============================================================ */

function addResponse(query, contentEl) {
  const card = el('div', { className: 'advisor-response' },
    el('div', { className: 'advisor-query', textContent: query }),
    contentEl,
  );
  // Prepend (latest on top)
  dom.responses.prepend(card);
  state.responses.unshift({ query, el: card });
}

/* ============================================================
   Character Panel Rendering
   ============================================================ */

function renderCharLoading(message) {
  dom.charPanel.innerHTML = `<div class="loading-msg"><span class="spinner"></span>${escHtml(message)}</div>`;
}

function renderCharError(message) {
  dom.charPanel.innerHTML = '';
  dom.charPanel.appendChild(el('p', { textContent: message, style: 'color:var(--red)' }));
}

function renderCharPanel(sim, charData) {
  dom.charPanel.innerHTML = '';

  const build = sim.build || {};
  const charName = charData?.name ?? state.character ?? null;
  const level = charData?.level ?? build.level ?? null;
  const className = charData?.class ?? build.ascendancy ?? build.class ?? null;

  if (charName || level || className) {
    const parts = [
      charName,
      (level != null || className) ? `Lv.${level ?? '?'} ${className ?? ''}`.trim() : null,
    ].filter(Boolean).join(' — ');
    dom.charPanel.appendChild(el('h2', { textContent: parts }));
  }

  dom.charPanel.appendChild(renderStatsGrid(sim));

  // Expandable full JSON
  const jsonPanel = el('div', { className: 'result-panel' });
  jsonPanel.innerHTML = escHtml(JSON.stringify(sim, null, 2));
  const details = el('details', {},
    el('summary', {
      textContent: 'All stats',
      style: 'cursor:pointer;color:var(--text-dim);font-size:0.8rem',
    }),
    jsonPanel,
  );
  dom.charPanel.appendChild(details);
}

function renderStatsGrid(sim) {
  const off = sim.offence || {};
  const def = sim.defence || {};
  const res = sim.resources || {};

  const statDefs = [
    ['Combined DPS', off.combinedDPS, fmtDPS],
    ['Life',          def.life,              fmtNum],
    ['Energy Shield', def.energyShield,      fmtNum],
    ['Total EHP',     def.totalEHP,          fmtNum],
    ['Mana',          res.mana,              fmtNum],
    ['Armour',        def.armour,            fmtNum],
    ['Evasion',       def.evasion,           fmtNum],
    ['Block',         def.blockChance,       fmtPct],
    ['Spell Suppress', def.suppressionChance, fmtPct],
  ].filter(([, v]) => v != null && v > 0);

  const grid = el('div', { className: 'stats-grid' });
  for (const [label, value, fmt] of statDefs) {
    grid.appendChild(
      el('div', { className: 'stat-box' },
        el('div', { className: 'value', textContent: fmt(value) }),
        el('div', { className: 'label', textContent: label }),
      ),
    );
  }
  return grid;
}

function renderStatsCard(sim) {
  const card = el('div');
  card.appendChild(renderStatsGrid(sim));
  return card;
}

/* ============================================================
   Item Optimization Renderer
   ============================================================ */

function renderItemResult(container, data) {
  if (data.baseline) {
    const b = data.baseline;
    const baselineEl = el('p', { style: 'margin-bottom:0.5rem;font-size:0.85rem' });
    baselineEl.appendChild(document.createTextNode('Current: '));
    const strong = el('strong');
    strong.textContent = b.item || '\u2014';
    baselineEl.appendChild(strong);
    baselineEl.appendChild(document.createTextNode(
      ' | DPS: ' + fmtDPS(b.combinedDPS) + ' | Life: ' + fmtNum(b.life),
    ));
    container.appendChild(baselineEl);
  }

  const candidates = data.candidates || [];
  if (!candidates.length) {
    container.appendChild(el('p', { textContent: 'No upgrades found.' }));
    return;
  }

  const rows = candidates.map((c, i) => ({
    _rank:      i + 1,
    _name:      c.name || '\u2014',
    chaosValue: c.chaosValue ?? null,
    deltaDPS:   c.delta?.combinedDPS ?? 0,
    deltaLife:  c.delta?.life ?? 0,
    deltaEHP:   c.delta?.totalEHP ?? 0,
    efficiency: c.efficiency ?? null,
  }));

  const tableContainer = document.createElement('div');
  container.appendChild(tableContainer);

  const columns = [
    { key: '_rank',      label: '#',          type: 'number', className: 'num' },
    { key: '_name',      label: 'Item',       type: 'string' },
    { key: 'chaosValue', label: 'Price',      type: 'number', className: 'num' },
    { key: 'deltaDPS',   label: '\u0394DPS',  type: 'number', className: 'num' },
    { key: 'deltaLife',  label: '\u0394Life', type: 'number', className: 'num' },
    { key: 'deltaEHP',   label: '\u0394EHP',  type: 'number', className: 'num' },
    { key: 'efficiency', label: 'Efficiency', type: 'number', className: 'num' },
  ];

  createSortableTable(tableContainer, columns, rows, (row) => {
    const tr = document.createElement('tr');
    tr.appendChild(el('td', { className: 'num', textContent: String(row._rank) }));

    const tdName = el('td');
    tdName.textContent = row._name;
    tr.appendChild(tdName);

    tr.appendChild(el('td', { className: 'num', textContent: fmtChaos(row.chaosValue) }));

    const dpsCls = trendClass(row.deltaDPS);
    const dpsSign = row.deltaDPS > 0 ? '+' : '';
    tr.appendChild(el('td', { className: 'num ' + dpsCls, textContent: dpsSign + fmtDPS(row.deltaDPS) }));

    const lifeSign = row.deltaLife > 0 ? '+' : '';
    tr.appendChild(el('td', { className: 'num', textContent: lifeSign + fmtNum(row.deltaLife) }));

    const ehpSign = row.deltaEHP > 0 ? '+' : '';
    tr.appendChild(el('td', { className: 'num', textContent: ehpSign + fmtNum(row.deltaEHP) }));

    tr.appendChild(el('td', { className: 'num', textContent: fmtNum(row.efficiency) }));
    return tr;
  });
}

/* ============================================================
   Gem Optimization Renderer
   ============================================================ */

function renderGemResult(container, data) {
  if (data.skill) {
    const baselineEl = el('p', { style: 'margin-bottom:0.5rem;font-size:0.85rem' });
    baselineEl.appendChild(document.createTextNode('Skill: '));
    const strong = el('strong');
    strong.textContent = data.skill;
    baselineEl.appendChild(strong);
    baselineEl.appendChild(document.createTextNode(' | Baseline DPS: ' + fmtDPS(data.baseline_dps)));
    container.appendChild(baselineEl);
  }

  if (data.current_supports?.length) {
    container.appendChild(el('p', {
      style: 'font-size:0.8rem;margin-bottom:0.75rem',
      textContent: 'Current supports: ' + data.current_supports.join(', '),
    }));
  }

  const recs = data.recommendations || [];
  if (!recs.length) {
    container.appendChild(el('p', { textContent: 'No gem improvements found.' }));
    return;
  }

  const rows = recs.map((r, i) => ({
    _rank:      i + 1,
    _replace:   r.replace || '\u2014',
    _with:      r.with    || '\u2014',
    deltaDPS:   r.delta_dps  ?? 0,
    gemPrice:   r.gem_price  ?? null,
    efficiency: r.efficiency ?? null,
  }));

  const tableContainer = document.createElement('div');
  container.appendChild(tableContainer);

  const columns = [
    { key: '_rank',      label: '#',          type: 'number', className: 'num' },
    { key: '_replace',   label: 'Replace',    type: 'string' },
    { key: '_with',      label: 'With',       type: 'string' },
    { key: 'deltaDPS',   label: '\u0394DPS',  type: 'number', className: 'num' },
    { key: 'gemPrice',   label: 'Price',      type: 'number', className: 'num' },
    { key: 'efficiency', label: 'Efficiency', type: 'number', className: 'num' },
  ];

  createSortableTable(tableContainer, columns, rows, (row) => {
    const tr = document.createElement('tr');
    tr.appendChild(el('td', { className: 'num', textContent: String(row._rank) }));

    const tdReplace = el('td');
    tdReplace.textContent = row._replace;
    tr.appendChild(tdReplace);

    const tdWith = el('td');
    tdWith.textContent = row._with;
    tr.appendChild(tdWith);

    const dpsCls = trendClass(row.deltaDPS);
    const dpsSign = row.deltaDPS > 0 ? '+' : '';
    tr.appendChild(el('td', { className: 'num ' + dpsCls, textContent: dpsSign + fmtDPS(row.deltaDPS) }));

    tr.appendChild(el('td', {
      className: 'num',
      textContent: row.gemPrice != null ? fmtChaos(row.gemPrice) : '\u2014',
    }));
    tr.appendChild(el('td', { className: 'num', textContent: fmtNum(row.efficiency) }));
    return tr;
  });
}

/* ============================================================
   Helpers
   ============================================================ */

function setAllButtons(disabled) {
  const btns = [dom.importBtn, dom.loadBtn, dom.askBtn];
  btns.forEach(btn => { btn.disabled = disabled; });
}
