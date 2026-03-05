/** @file Inline SVG sparkline renderer. */

/**
 * Create a sparkline SVG from an array of values.
 * @param {number[]} data - Array of values (typically 7 data points)
 * @param {object} opts
 * @param {number} opts.width - SVG width (default 60)
 * @param {number} opts.height - SVG height (default 20)
 * @param {string} opts.color - Stroke color (auto: green if last > 0, red if < 0)
 * @returns {SVGElement}
 */
export function sparkline(data, opts = {}) {
  const w = opts.width || 60;
  const h = opts.height || 20;
  const pad = 2;

  if (!data || data.length === 0) {
    const svg = _svg(w, h);
    return svg;
  }

  const last = data[data.length - 1] || 0;
  const color = opts.color || (last >= 0 ? '#4caf50' : '#e05050');

  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;

  // Single data point: draw a centred dot instead of a line (avoids division by zero).
  if (data.length < 2) {
    const svg = _svg(w, h);
    const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    circle.setAttribute('cx', (w / 2).toFixed(1));
    circle.setAttribute('cy', (h / 2).toFixed(1));
    circle.setAttribute('r', '2');
    circle.setAttribute('fill', color);
    svg.appendChild(circle);
    return svg;
  }

  const points = data.map((v, i) => {
    const x = pad + (i / (data.length - 1)) * (w - 2 * pad);
    const y = pad + (1 - (v - min) / range) * (h - 2 * pad);
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');

  const svg = _svg(w, h);
  const polyline = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
  polyline.setAttribute('points', points);
  polyline.setAttribute('fill', 'none');
  polyline.setAttribute('stroke', color);
  polyline.setAttribute('stroke-width', '1.5');
  polyline.setAttribute('stroke-linecap', 'round');
  polyline.setAttribute('stroke-linejoin', 'round');
  svg.appendChild(polyline);
  return svg;
}

function _svg(w, h) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('width', w);
  svg.setAttribute('height', h);
  svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
  svg.style.verticalAlign = 'middle';
  return svg;
}
