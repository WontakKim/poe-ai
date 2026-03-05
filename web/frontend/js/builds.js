/** @file Build meta-statistics dashboard. */

import { get } from './api.js';
import {
  fmtNum, fmtPct, trendClass, trendArrow,
  el, createSortableTable, createPagination, showToast,
} from './utils.js';

/* ============================================================
   Entry point
   ============================================================ */

export async function init(container) {
  container.innerHTML = '';
  container.appendChild(
    el('div', { className: 'loading-msg' },
      el('span', { className: 'spinner' }),
      ' Loading builds…',
    ),
  );

  let data;
  try {
    data = await get('/builds');
  } catch (err) {
    showToast(err.message || 'Failed to load builds', 'error');
    container.innerHTML = '';
    container.appendChild(
      el('div', { className: 'card' },
        el('h2', { textContent: 'Error loading builds' }),
        el('p', { textContent: err.message || 'Unknown error' }),
      ),
    );
    return;
  }

  container.innerHTML = '';
  renderDashboard(container, data);
}

/* ============================================================
   Dashboard layout
   ============================================================ */

function renderDashboard(container, data) {
  // Stats grid (always visible)
  container.appendChild(renderStatsGrid(data));

  // Tab bar
  const tabs = ['Overview', 'Skills', 'Classes', 'Items', 'Keystones', 'Gems'];
  const { tabBar, contentMap } = buildTabLayout(container, tabs);
  container.appendChild(tabBar);

  // Render each tab's content
  renderOverviewTab(contentMap.get('Overview'), data);
  renderDimensionTab(contentMap.get('Skills'), data.skills || [], { searchable: true, paginated: true });
  renderClassesTab(contentMap.get('Classes'), data);
  renderDimensionTab(contentMap.get('Items'), data.items || [], { searchable: true, paginated: true });
  renderDimensionTab(contentMap.get('Keystones'), data.keystones || [], { searchable: false, paginated: false });
  renderDimensionTab(contentMap.get('Gems'), data.allgems || [], { searchable: true, paginated: true });
}

/* ============================================================
   Stats grid
   ============================================================ */

function renderStatsGrid(data) {
  return el('div', { className: 'stats-grid' },
    statBox(fmtNum(data.total), 'Total Characters'),
    statBox(String((data.topBuilds || []).length), 'Build Archetypes'),
    statBox(String((data.class || []).length), 'Classes'),
  );
}

function statBox(value, label) {
  return el('div', { className: 'stat-box' },
    el('div', { className: 'value', textContent: value }),
    el('div', { className: 'label', textContent: label }),
  );
}

/* ============================================================
   Tab layout builder
   ============================================================ */

/**
 * Build a tab bar and matching content divs.
 * Returns the tab bar element and a Map<tabLabel, contentDiv>.
 * The first tab is active by default.
 */
function buildTabLayout(container, tabs) {
  const tabBar = el('div', { className: 'tab-bar' });
  /** @type {Map<string, HTMLElement>} */
  const contentMap = new Map();

  const tabButtons = [];

  tabs.forEach((label, index) => {
    const btn = el('button', {
      className: 'tab-btn' + (index === 0 ? ' active' : ''),
      textContent: label,
    });
    tabBar.appendChild(btn);
    tabButtons.push(btn);

    const pane = el('div', { className: index === 0 ? 'tab-content' : 'tab-hidden' });
    container.appendChild(pane);
    contentMap.set(label, pane);

    btn.addEventListener('click', () => {
      // Deactivate all
      tabButtons.forEach(b => b.classList.remove('active'));
      contentMap.forEach(p => {
        p.classList.remove('tab-content');
        p.classList.add('tab-hidden');
      });
      // Activate clicked
      btn.classList.add('active');
      pane.classList.remove('tab-hidden');
      pane.classList.add('tab-content');
    });
  });

  return { tabBar, contentMap };
}

/* ============================================================
   Overview tab
   ============================================================ */

function renderOverviewTab(container, data) {
  const topBuilds = data.topBuilds || [];
  const classes = data.class || [];

  // Filter controls
  const classSelect = el('select');
  classSelect.appendChild(el('option', { value: '', textContent: 'All Classes' }));
  classes.forEach(c => {
    classSelect.appendChild(
      el('option', { value: c.name, textContent: `${c.name} (${fmtPct(c.share)})` }),
    );
  });

  const skillInput = el('input', { placeholder: 'Filter by skill…', type: 'text' });

  const limitSelect = el('select');
  [20, 50, 100].forEach(n => {
    limitSelect.appendChild(el('option', { value: String(n), textContent: String(n) }));
  });
  limitSelect.appendChild(el('option', { value: '999999', textContent: 'All' }));

  const filterRow = el('div', { className: 'input-row' },
    el('div', { className: 'input-group' },
      el('label', { textContent: 'Class' }),
      classSelect,
    ),
    el('div', { className: 'input-group' },
      el('label', { textContent: 'Skill' }),
      skillInput,
    ),
    el('div', { className: 'input-group' },
      el('label', { textContent: 'Limit' }),
      limitSelect,
    ),
  );

  const tableCard = el('div', { className: 'card' });
  tableCard.appendChild(el('h2', { textContent: 'Top Builds' }));
  const tableContainer = el('div');
  tableCard.appendChild(tableContainer);

  container.appendChild(filterRow);
  container.appendChild(tableCard);

  const columns = [
    { key: '_rank', label: '#', type: 'number', className: 'num' },
    { key: 'skill', label: 'Skill', type: 'string' },
    { key: 'class', label: 'Class', type: 'string' },
    { key: 'share', label: 'Share%', type: 'number', className: 'num' },
    { key: 'trend', label: 'Trend', type: 'number', className: 'num', sortable: false },
  ];

  // Assign initial ranks
  topBuilds.forEach((b, i) => { b._rank = i + 1; });

  const table = createSortableTable(tableContainer, columns, topBuilds, renderBuildRow);

  function applyFilter() {
    const cls = classSelect.value;
    const skill = skillInput.value.toLowerCase().trim();
    const limit = parseInt(limitSelect.value, 10);

    let filtered = topBuilds;
    if (cls) filtered = filtered.filter(b => b.class === cls);
    if (skill) filtered = filtered.filter(b => (b.skill || '').toLowerCase().includes(skill));
    filtered = filtered.slice(0, limit);

    // Re-rank before updating table
    filtered.forEach((b, i) => { b._rank = i + 1; });
    table.update(filtered);
  }

  classSelect.addEventListener('change', applyFilter);
  skillInput.addEventListener('input', applyFilter);
  limitSelect.addEventListener('change', applyFilter);
}

function renderBuildRow(b) {
  const trendVal = b.trend ?? 0;
  const trendTd = el('td', { className: `num ${trendClass(trendVal)}` });
  trendTd.textContent = trendArrow(trendVal);

  return el('tr', {},
    el('td', { className: 'num', textContent: String(b._rank) }),
    el('td', { textContent: b.skill || '—' }),
    el('td', { textContent: b.class || '—' }),
    el('td', { className: 'num', textContent: fmtPct(b.share) }),
    trendTd,
  );
}

/* ============================================================
   Classes tab
   ============================================================ */

function renderClassesTab(container, data) {
  const classes = data.class || [];
  const ascendancies = data.secondascendancy || [];

  // Class distribution card
  const classCard = el('div', { className: 'card' });
  classCard.appendChild(el('h2', { textContent: 'Class Distribution' }));
  const classTableContainer = el('div');
  classCard.appendChild(classTableContainer);
  container.appendChild(classCard);

  const maxClassShare = classes.length
    ? Math.max(...classes.map(c => c.share || 0))
    : 1;

  const classColumns = [
    { key: 'name', label: 'Class', type: 'string' },
    { key: 'count', label: 'Count', type: 'number', className: 'num' },
    { key: 'share', label: 'Share%', type: 'number', className: 'num' },
    { key: '_bar', label: 'Bar', type: 'string', sortable: false },
  ];

  createSortableTable(classTableContainer, classColumns, classes, c => {
    return el('tr', {},
      el('td', { textContent: c.name || '—' }),
      el('td', { className: 'num', textContent: fmtNum(c.count) }),
      el('td', { className: 'num', textContent: fmtPct(c.share) }),
      buildBarCell(c.share, maxClassShare),
    );
  });

  // Ascendancy card (if data present)
  if (ascendancies.length) {
    const ascCard = el('div', { className: 'card' });
    ascCard.appendChild(el('h2', { textContent: 'Ascendancy Distribution' }));
    const ascTableContainer = el('div');
    ascCard.appendChild(ascTableContainer);
    container.appendChild(ascCard);

    const maxAscShare = Math.max(...ascendancies.map(a => a.share || 0));
    const ascColumns = [
      { key: 'name', label: 'Ascendancy', type: 'string' },
      { key: 'count', label: 'Count', type: 'number', className: 'num' },
      { key: 'share', label: 'Share%', type: 'number', className: 'num' },
      { key: '_bar', label: 'Bar', type: 'string', sortable: false },
    ];

    createSortableTable(ascTableContainer, ascColumns, ascendancies, a => {
      return el('tr', {},
        el('td', { textContent: a.name || '—' }),
        el('td', { className: 'num', textContent: fmtNum(a.count) }),
        el('td', { className: 'num', textContent: fmtPct(a.share) }),
        buildBarCell(a.share, maxAscShare),
      );
    });
  }
}

function buildBarCell(share, maxShare) {
  const pct = maxShare > 0 ? Math.round((share || 0) / maxShare * 100) : 0;
  const bar = el('div', {});
  bar.style.cssText = `background:var(--accent-dim);height:12px;width:${pct}%;border-radius:2px;min-width:2px`;
  const td = el('td');
  td.appendChild(bar);
  return td;
}

/* ============================================================
   Dimension tab helper (skills / items / keystones / gems)
   ============================================================ */

/**
 * Render a tab with a searchable, optionally paginated sortable table for
 * dimension data ({name, count, share}[]).
 *
 * @param {HTMLElement} container
 * @param {{ name: string, count: number, share: number }[]} data
 * @param {{ searchable?: boolean, paginated?: boolean, pageSize?: number }} opts
 */
function renderDimensionTab(container, data, opts = {}) {
  const { searchable = false, paginated = false, pageSize = 50 } = opts;

  let searchInput = null;

  if (searchable) {
    searchInput = el('input', { className: 'search-input', placeholder: 'Search…', type: 'text' });
    const searchRow = el('div', { className: 'input-row' },
      el('div', { className: 'input-group' },
        el('label', { textContent: 'Search' }),
        searchInput,
      ),
    );
    container.appendChild(searchRow);
  }

  const tableContainer = el('div');
  container.appendChild(tableContainer);

  const paginationContainer = el('div');
  if (paginated) {
    container.appendChild(paginationContainer);
  }

  const columns = [
    { key: '_rank', label: '#', type: 'number', className: 'num' },
    { key: 'name', label: 'Name', type: 'string' },
    { key: 'count', label: 'Count', type: 'number', className: 'num' },
    { key: 'share', label: 'Share%', type: 'number', className: 'num' },
  ];

  // Assign ranks to original data
  data.forEach((item, i) => { item._rank = i + 1; });

  const table = createSortableTable(tableContainer, columns, getPage(data, 1, pageSize, paginated), renderDimensionRow);

  let pagination = null;

  if (paginated) {
    pagination = createPagination(paginationContainer, {
      totalItems: data.length,
      pageSize,
      onPageChange(page) {
        const filtered = getFilteredData();
        const slice = getPage(filtered, page, pageSize, paginated);
        table.update(slice);
      },
    });
  }

  function getFilteredData() {
    if (!searchInput) return data;
    const query = searchInput.value.toLowerCase().trim();
    if (!query) return data;
    return data.filter(item => (item.name || '').toLowerCase().includes(query));
  }

  function refresh() {
    const filtered = getFilteredData();
    if (pagination) {
      pagination.setTotal(filtered.length);
      // setTotal resets to page 1 and triggers onPageChange — but we need to render here too
      // because setTotal only calls render() internally without calling onPageChange
      const slice = getPage(filtered, 1, pageSize, paginated);
      table.update(slice);
    } else {
      table.update(filtered);
    }
  }

  if (searchInput) {
    searchInput.addEventListener('input', refresh);
  }

  // Initial render for paginated case: table already shows page 1 from createSortableTable init
  // For non-paginated: data is already passed directly
}

function renderDimensionRow(item) {
  return el('tr', {},
    el('td', { className: 'num', textContent: String(item._rank) }),
    el('td', { textContent: item.name || '—' }),
    el('td', { className: 'num', textContent: fmtNum(item.count) }),
    el('td', { className: 'num', textContent: fmtPct(item.share) }),
  );
}

/**
 * Return the slice of data for a given page.
 * If not paginated, return the full array.
 */
function getPage(data, page, pageSize, paginated) {
  if (!paginated) return data;
  const start = (page - 1) * pageSize;
  return data.slice(start, start + pageSize);
}
