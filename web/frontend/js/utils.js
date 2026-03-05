/** @file Formatters, DOM helpers, sortable table, pagination, and toast utilities. */

/* ============================================================
   Formatters
   ============================================================ */

/**
 * Format a number with locale grouping and up to 1 decimal place.
 * @param {number|null|undefined} n
 * @returns {string}
 */
export function fmtNum(n) {
  if (n == null) return '—';
  return Number(n).toLocaleString('en-US', { maximumFractionDigits: 1 });
}

/**
 * Format chaos orb value: 150.5 → "150.5c"
 * @param {number|null|undefined} n
 * @returns {string}
 */
export function fmtChaos(n) {
  if (n == null) return '—';
  return Number(n).toLocaleString('en-US', { maximumFractionDigits: 1 }) + 'c';
}

/**
 * Format divine orb value: 3.2 → "3.2div", null → "—"
 * @param {number|null|undefined} n
 * @returns {string}
 */
export function fmtDivine(n) {
  if (n == null) return '—';
  return Number(n).toLocaleString('en-US', { maximumFractionDigits: 1 }) + 'div';
}

/**
 * Format percentage: 6.21 → "6.2%"
 * @param {number|null|undefined} n
 * @returns {string}
 */
export function fmtPct(n) {
  if (n == null) return '—';
  return Number(n).toFixed(1) + '%';
}

/**
 * Format DPS with K/M abbreviation: 1234567 → "1.2M", 15000 → "15K"
 * @param {number|null|undefined} n
 * @returns {string}
 */
export function fmtDPS(n) {
  if (n == null) return '—';
  const v = Number(n);
  if (v >= 1_000_000) return (v / 1_000_000).toLocaleString('en-US', { maximumFractionDigits: 1 }) + 'M';
  if (v >= 1_000) return (v / 1_000).toLocaleString('en-US', { maximumFractionDigits: 1 }) + 'K';
  return v.toLocaleString('en-US', { maximumFractionDigits: 1 });
}

/**
 * Return a CSS class name based on the sign of a numeric trend value.
 * @param {number} v
 * @returns {'trend-up'|'trend-down'|'trend-flat'}
 */
export function trendClass(v) {
  if (v > 0) return 'trend-up';
  if (v < 0) return 'trend-down';
  return 'trend-flat';
}

/**
 * Return a trend arrow character.
 * @param {number} v
 * @returns {'▲'|'▼'|'—'}
 */
export function trendArrow(v) {
  if (v > 0) return '\u25B2';
  if (v < 0) return '\u25BC';
  return '\u2014';
}

/* ============================================================
   DOM Helpers
   ============================================================ */

/**
 * Create a DOM element with attributes and children.
 * @param {string} tag - HTML tag name
 * @param {Record<string, unknown>} [attrs] - Attribute map. Use 'className', 'textContent',
 *   or 'on{EventName}' for event listeners.
 * @param {...(HTMLElement|string|null|undefined)} children
 * @returns {HTMLElement}
 */
export function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'className') {
      node.className = String(v);
    } else if (k === 'textContent') {
      node.textContent = String(v);
    } else if (k === 'innerHTML') {
      node.innerHTML = String(v);
    } else if (k.startsWith('on') && typeof v === 'function') {
      node.addEventListener(k.slice(2).toLowerCase(), v);
    } else {
      node.setAttribute(k, String(v));
    }
  }
  for (const child of children) {
    if (child == null) continue;
    if (typeof child === 'string') {
      node.appendChild(document.createTextNode(child));
    } else {
      node.appendChild(child);
    }
  }
  return node;
}

/**
 * Escape a string for safe use in innerHTML.
 * @param {string} s
 * @returns {string}
 */
export function escHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/* ============================================================
   Sortable Table
   ============================================================ */

/**
 * @typedef {{ key: string, label: string, type?: 'string'|'number', className?: string, sortable?: boolean }} ColumnDef
 */

/**
 * Create a sortable data table inside a container element.
 *
 * @param {HTMLElement} container - Element to render the table into
 * @param {ColumnDef[]} columns
 * @param {object[]} data - Initial data array
 * @param {(item: object, index: number) => HTMLTableRowElement} renderRow
 * @returns {{ update: (newData: object[]) => void, getSort: () => {key: string|null, asc: boolean}, setSort: (key: string, asc: boolean) => void }}
 */
export function createSortableTable(container, columns, data, renderRow) {
  let currentData = [...data];
  let sortKey = null;
  let sortAsc = true;

  // Build wrapper for horizontal scroll on mobile
  const wrapper = document.createElement('div');
  wrapper.className = 'data-table-wrapper';

  const table = document.createElement('table');
  table.className = 'data-table';

  // Thead
  const thead = document.createElement('thead');
  const headerRow = document.createElement('tr');

  columns.forEach(col => {
    const th = document.createElement('th');
    if (col.className) th.className = col.className;

    const isSortable = col.sortable !== false; // default true
    if (isSortable) {
      th.className = (th.className ? th.className + ' ' : '') + 'sortable';
    }

    const labelNode = document.createTextNode(col.label);
    th.appendChild(labelNode);

    if (isSortable) {
      const arrow = document.createElement('span');
      arrow.className = 'sort-arrow';
      arrow.setAttribute('aria-hidden', 'true');
      th.appendChild(arrow);

      th.addEventListener('click', () => {
        if (sortKey === col.key) {
          sortAsc = !sortAsc;
        } else {
          sortKey = col.key;
          sortAsc = col.type !== 'number'; // numbers default desc, strings asc
        }
        _applySort();
        _updateArrows();
        _render();
      });
    }

    headerRow.appendChild(th);
  });

  thead.appendChild(headerRow);
  table.appendChild(thead);

  const tbody = document.createElement('tbody');
  table.appendChild(tbody);

  wrapper.appendChild(table);
  container.appendChild(wrapper);

  // Initial render
  _render();

  function _applySort() {
    if (!sortKey) return;
    const col = columns.find(c => c.key === sortKey);
    if (!col) return;

    currentData.sort((a, b) => {
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

    // Re-number any _rank field after sort
    currentData.forEach((item, i) => {
      if ('_rank' in item) item._rank = i + 1;
    });
  }

  function _updateArrows() {
    headerRow.querySelectorAll('th').forEach((th, i) => {
      const col = columns[i];
      if (!col || col.sortable === false) return;
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

  function _render() {
    tbody.innerHTML = '';
    currentData.forEach((item, i) => {
      const row = renderRow(item, i);
      if (row) tbody.appendChild(row);
    });
  }

  return {
    update(newData) {
      currentData = [...newData];
      _applySort();
      _render();
    },
    getSort() {
      return { key: sortKey, asc: sortAsc };
    },
    setSort(key, asc) {
      sortKey = key;
      sortAsc = asc;
      _applySort();
      _updateArrows();
      _render();
    },
  };
}

/* ============================================================
   Pagination
   ============================================================ */

/**
 * Create a pagination control inside a container.
 *
 * @param {HTMLElement} container
 * @param {{ totalItems: number, pageSize?: number, onPageChange: (page: number) => void }} opts
 * @returns {{ setTotal: (n: number) => void, setPage: (n: number) => void, getPage: () => number }}
 */
export function createPagination(container, opts) {
  const pageSize = opts.pageSize ?? 50;
  let totalItems = opts.totalItems ?? 0;
  let currentPage = 1;

  container.className = 'pagination';

  function totalPages() {
    return Math.max(1, Math.ceil(totalItems / pageSize));
  }

  function render() {
    container.innerHTML = '';
    const total = totalPages();
    if (total <= 1) return;

    const prevBtn = _pageBtn('\u2039', currentPage > 1, () => setPage(currentPage - 1));
    prevBtn.title = 'Previous page';
    container.appendChild(prevBtn);

    // Determine which page numbers to show with ellipsis
    const pages = _pageNumbers(currentPage, total);

    let lastRendered = null;
    for (const p of pages) {
      if (p === null) {
        const dot = document.createElement('span');
        dot.className = 'page-ellipsis';
        dot.textContent = '\u2026';
        container.appendChild(dot);
      } else {
        if (lastRendered !== null && p !== lastRendered + 1) {
          const dot = document.createElement('span');
          dot.className = 'page-ellipsis';
          dot.textContent = '\u2026';
          container.appendChild(dot);
        }
        const btn = _pageBtn(String(p), true, () => setPage(p));
        if (p === currentPage) btn.classList.add('active');
        container.appendChild(btn);
        lastRendered = p;
      }
    }

    const nextBtn = _pageBtn('\u203A', currentPage < total, () => setPage(currentPage + 1));
    nextBtn.title = 'Next page';
    container.appendChild(nextBtn);
  }

  function setPage(p) {
    const total = totalPages();
    currentPage = Math.max(1, Math.min(p, total));
    render();
    opts.onPageChange(currentPage);
  }

  render();

  return {
    setTotal(n) {
      totalItems = n;
      currentPage = 1;
      render();
    },
    setPage,
    getPage() {
      return currentPage;
    },
  };
}

/**
 * Compute page numbers to display, with null for ellipsis positions.
 * Shows first 2, last 2, and a window around current page.
 * @param {number} current
 * @param {number} total
 * @returns {(number|null)[]}
 */
function _pageNumbers(current, total) {
  if (total <= 9) {
    return Array.from({ length: total }, (_, i) => i + 1);
  }

  const show = new Set([1, 2, total - 1, total]);
  for (let p = Math.max(1, current - 2); p <= Math.min(total, current + 2); p++) {
    show.add(p);
  }

  const sorted = [...show].sort((a, b) => a - b);
  const result = [];
  let prev = 0;
  for (const p of sorted) {
    if (prev && p - prev > 2) {
      result.push(null); // ellipsis
    } else if (prev && p - prev === 2) {
      result.push(prev + 1); // fill single gap rather than ellipsis
    }
    result.push(p);
    prev = p;
  }
  return result;
}

function _pageBtn(label, enabled, onClick) {
  const btn = document.createElement('button');
  btn.textContent = label;
  btn.disabled = !enabled;
  if (enabled) btn.addEventListener('click', onClick);
  return btn;
}

/* ============================================================
   Toast Notifications
   ============================================================ */

/**
 * Show a toast notification.
 * @param {string} message
 * @param {'error'|'success'|'info'} [type]
 */
export function showToast(message, type = 'info') {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;

  container.appendChild(toast);

  // Auto-remove after 4 seconds (300ms fade + 3.7s display)
  const DISPLAY_MS = 3700;
  const FADE_MS = 300;

  setTimeout(() => {
    toast.classList.add('toast-fade');
    setTimeout(() => {
      if (toast.parentNode === container) {
        container.removeChild(toast);
      }
    }, FADE_MS);
  }, DISPLAY_MS);
}
