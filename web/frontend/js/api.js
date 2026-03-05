/** @file Fetch wrapper for the poe-ai API. */

const API_BASE = '/api';

const DEFAULT_GET_TIMEOUT_MS = 30_000;
const DEFAULT_POST_TIMEOUT_MS = 120_000;

/**
 * Make a GET request to the API.
 * @param {string} path - Path relative to /api (e.g. '/health')
 * @param {{ timeout?: number }} [opts]
 * @returns {Promise<unknown>}
 * @throws {{ status: number, message: string }}
 */
export async function get(path, opts = {}) {
  return _request('GET', path, undefined, opts.timeout ?? DEFAULT_GET_TIMEOUT_MS);
}

/**
 * Make a POST request to the API with a JSON body.
 * @param {string} path - Path relative to /api
 * @param {unknown} data - Request body (will be JSON-serialized)
 * @param {{ timeout?: number }} [opts]
 * @returns {Promise<unknown>}
 * @throws {{ status: number, message: string }}
 */
export async function post(path, data, opts = {}) {
  return _request('POST', path, data, opts.timeout ?? DEFAULT_POST_TIMEOUT_MS);
}

async function _request(method, path, data, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  const init = {
    method,
    signal: controller.signal,
  };

  if (data !== undefined) {
    init.headers = { 'Content-Type': 'application/json' };
    init.body = JSON.stringify(data);
  }

  let res;
  try {
    res = await fetch(`${API_BASE}${path}`, init);
  } catch (err) {
    clearTimeout(timer);
    if (err.name === 'AbortError') {
      throw { status: 408, message: `Request timed out after ${timeoutMs / 1000}s` };
    }
    throw { status: 0, message: err.message || 'Network error' };
  }

  clearTimeout(timer);

  if (!res.ok) {
    let message = `${res.status} ${res.statusText}`;
    try {
      const body = await res.json();
      if (body.detail) message = String(body.detail);
      else if (body.message) message = String(body.message);
    } catch {
      // Ignore parse failure; keep the status-based message.
    }
    throw { status: res.status, message };
  }

  return res.json();
}
