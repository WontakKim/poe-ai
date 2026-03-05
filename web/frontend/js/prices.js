/** @file Price dashboard page. */

import { get } from './api.js';
import { fmtNum, fmtChaos, fmtDivine, fmtPct, trendClass, trendArrow, el, createPagination } from './utils.js';
import { sparkline } from './sparkline.js';

const TYPE_LABELS = {
  'currency':         'Currency',
  'unique-weapon':    'Unique Weapons',
  'unique-armour':    'Unique Armour',
  'unique-accessory': 'Unique Accessories',
  'unique-flask':     'Unique Flasks',
  'unique-jewel':     'Unique Jewels',
  'skill-gem':        'Skill Gems',
};

const PAGE_SIZE = 50;

const COLUMNS = [
  { key: 'name',       label: 'Name',   type: 'string' },
  { key: 'chaosValue', label: 'Chaos',  type: 'number', className: 'num' },
  { key: 'divineValue',label: 'Divine', type: 'number', className: 'num' },
  { key: 'volume',     label: 'Volume', type: 'number', className: 'num' },
  { key: 'trend',      label: 'Trend',  type: 'number', className: 'num' },
  { key: null,         label: '7d',     type: null,     className: 'sparkline-col', sortable: false },
];

export async function init(container) {
  container.innerHTML = '<div class="loading-msg"><span class="spinner"></span>Loading price data...</div>';

  let overview;
  try {
    overview = await get('/prices');
  } catch (err) {
    container.innerHTML = `<div class="card"><h2>Error</h2><p>${err.message}</p></div>`;
    return;
  }

  const types = overview.types || {};
  const typeKeys = Object.keys(types);

  // Build layout: [type selector] [search input] + card with table + pagination
  const inputRow = el('div', { className: 'input-row' });

  const typeSelect = el('select', { id: 'price-type-select' });
  for (const t of typeKeys) {
    const label = TYPE_LABELS[t] || t;
    const count = types[t]?.count || 0;
    const opt = el('option', { value: t });
    opt.textContent = `${label} (${count})`;
    typeSelect.appendChild(opt);
  }
  inputRow.appendChild(el('div', { className: 'input-group' }, el('label', { textContent: 'Type' }), typeSelect));

  const searchInput = el('input', { id: 'price-search', placeholder: 'Filter by name...' });
  inputRow.appendChild(el('div', { className: 'input-group' }, el('label', { textContent: 'Search' }), searchInput));

  const titleEl = el('h2', { id: 'price-title', textContent: 'Prices' });
  const tableWrap = el('div', { id: 'price-table-wrap' });
  const paginationEl = el('div', { id: 'price-pagination' });
  const card = el('div', { className: 'card' }, titleEl, tableWrap, paginationEl);

  container.innerHTML = '';
  container.appendChild(inputRow);
  container.appendChild(card);

  // State
  let currentItems = [];
  let filteredItems = [];
  let sortKey = 'chaosValue';
  let sortAsc = false;    // chaosValue descending by default
  let pagination = null;

  function applyFilter() {
    const q = searchInput.value.toLowerCase();
    if (q) {
      filteredItems = currentItems.filter(it => (it.name || '').toLowerCase().includes(q));
    } else {
      filteredItems = currentItems.slice();
    }
  }

  function applySort() {
    if (!sortKey) return;
    const col = COLUMNS.find(c => c.key === sortKey);
    if (!col) return;
    filteredItems.sort((a, b) => {
      const va = a[sortKey];
      const vb = b[sortKey];
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      const cmp = col.type === 'number'
        ? Number(va) - Number(vb)
        : String(va).localeCompare(String(vb));
      return sortAsc ? cmp : -cmp;
    });
  }

  function renderPage(page) {
    const start = (page - 1) * PAGE_SIZE;
    const slice = filteredItems.slice(start, start + PAGE_SIZE);
    renderTableRows(slice);
  }

  function buildTableSkeleton() {
    tableWrap.innerHTML = '';

    const wrapper = el('div', { className: 'data-table-wrapper' });
    const table = el('table', { className: 'data-table' });
    const thead = el('thead');
    const headerRow = el('tr');

    for (const col of COLUMNS) {
      const th = document.createElement('th');
      if (col.className) th.className = col.className;

      if (col.sortable === false) {
        th.textContent = col.label;
      } else {
        th.classList.add('sortable');
        th.appendChild(document.createTextNode(col.label));
        const arrow = el('span', { className: 'sort-arrow' });
        arrow.setAttribute('aria-hidden', 'true');
        th.appendChild(arrow);

        th.addEventListener('click', () => {
          if (sortKey === col.key) {
            sortAsc = !sortAsc;
          } else {
            sortKey = col.key;
            sortAsc = col.type !== 'number'; // numbers default desc, strings asc
          }
          updateArrows();
          applySort();
          renderPage(pagination.getPage());
        });
      }
      headerRow.appendChild(th);
    }

    thead.appendChild(headerRow);
    table.appendChild(thead);
    table.appendChild(el('tbody'));
    wrapper.appendChild(table);
    tableWrap.appendChild(wrapper);

    return table;
  }

  let _table = null;

  function updateArrows() {
    if (!_table) return;
    const ths = _table.querySelectorAll('thead th');
    COLUMNS.forEach((col, i) => {
      if (col.sortable === false) return;
      const th = ths[i];
      if (!th) return;
      const arrow = th.querySelector('.sort-arrow');
      if (!arrow) return;
      if (col.key === sortKey) {
        th.classList.add('sort-active');
        arrow.textContent = sortAsc ? ' \u25B2' : ' \u25BC';
      } else {
        th.classList.remove('sort-active');
        arrow.textContent = '';
      }
    });
  }

  function renderTableRows(slice) {
    if (!_table) return;
    const tbody = _table.querySelector('tbody');
    tbody.innerHTML = '';

    if (slice.length === 0) {
      const tr = el('tr');
      const td = el('td', { colspan: String(COLUMNS.length) });
      td.style.textAlign = 'center';
      td.style.color = 'var(--text-dim)';
      td.textContent = 'No items match filter.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    for (const it of slice) {
      tbody.appendChild(buildRow(it));
    }
  }

  function buildRow(it) {
    const trendVal = it.trend ?? 0;
    const tr = el('tr');

    // Name — textContent only, XSS safe
    const tdName = el('td');
    tdName.textContent = it.name || it.id || '—';
    tr.appendChild(tdName);

    // Chaos
    const tdChaos = el('td', { className: 'num', textContent: fmtChaos(it.chaosValue) });
    tr.appendChild(tdChaos);

    // Divine
    const tdDivine = el('td', { className: 'num', textContent: fmtDivine(it.divineValue ?? null) });
    tr.appendChild(tdDivine);

    // Volume
    const tdVol = el('td', { className: 'num', textContent: fmtNum(it.volume) });
    tr.appendChild(tdVol);

    // Trend
    const tdTrend = el('td', { className: `num ${trendClass(trendVal)}` });
    tdTrend.textContent = `${trendArrow(trendVal)} ${fmtPct(Math.abs(trendVal))}`;
    tr.appendChild(tdTrend);

    // 7d sparkline — appended via DOM, never innerHTML
    const tdSpark = el('td', { className: 'sparkline-col' });
    if (Array.isArray(it.sparkline) && it.sparkline.length > 0) {
      tdSpark.appendChild(sparkline(it.sparkline));
    }
    tr.appendChild(tdSpark);

    return tr;
  }

  function initPagination() {
    paginationEl.innerHTML = '';
    pagination = createPagination(paginationEl, {
      totalItems: filteredItems.length,
      pageSize: PAGE_SIZE,
      onPageChange: (page) => renderPage(page),
    });
  }

  const loadType = async (type) => {
    tableWrap.innerHTML = '<div class="loading-msg"><span class="spinner"></span>Loading...</div>';
    paginationEl.innerHTML = '';
    titleEl.textContent = TYPE_LABELS[type] || type;

    // Reset state on type switch
    searchInput.value = '';
    sortKey = 'chaosValue';
    sortAsc = false;
    _table = null;

    try {
      const data = await get(`/prices/${type}`);
      currentItems = data.items || [];

      applyFilter();
      applySort();

      _table = buildTableSkeleton();
      updateArrows();
      initPagination();
      renderPage(1);
    } catch (err) {
      tableWrap.innerHTML = `<p style="color:var(--color-error)">${err.message}</p>`;
    }
  };

  typeSelect.addEventListener('change', () => loadType(typeSelect.value));

  searchInput.addEventListener('input', () => {
    if (!pagination) return;
    applyFilter();
    applySort();
    pagination.setTotal(filteredItems.length);
    renderPage(1);
  });

  if (typeKeys.length > 0) {
    await loadType(typeKeys[0]);
  }
}
