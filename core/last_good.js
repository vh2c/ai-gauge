/**
 * Keeps the app stable when a provider fails for a moment.
 *
 * The apps refresh every ~30 seconds. Some providers (for example the Antigravity IDE, which is probed through a
 * local process with a short timeout) occasionally fail or time out for one cycle. Without this module that provider
 * would disappear from the screen until the next successful cycle, which looks like flickering.
 *
 * Each successful result is remembered; if a provider fails (rejects, returns null, or returns no groups) the
 * last good result is reused for up to GRACE_MS and marked `stale: true`. After that it is dropped, so a provider
 * that is really gone (IDE closed, session expired) does not linger forever.
 *
 * The file lives in the same private config folder as the other caches and holds the same kind of data
 * (quota values), never keys or tokens.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const GRACE_MS = 10 * 60 * 1000;          // reuse a failed provider's last good result for up to 10 minutes
const PRUNE_MS = 60 * 60 * 1000;          // forget entries not refreshed for an hour
const BACKOFF_MIN_MS = 30 * 1000;
const BACKOFF_BASE_MS = 60 * 1000;
const BACKOFF_MAX_MS = 15 * 60 * 1000;    // cap exponential 429 backoff at 15 minutes

function formatResetFromIso(targetTime, now = Date.now()) {
  if (!targetTime) return null;
  let target = 0;
  if (typeof targetTime === 'number') {
    target = targetTime > 1e11 ? targetTime : targetTime * 1000;
  } else {
    target = new Date(targetTime).getTime();
  }
  if (!Number.isFinite(target) || target <= 0) return null;
  const diffMs = target - now;
  if (diffMs <= 0) return 'Now';
  const diffMins = Math.floor(diffMs / 60000);
  const days = Math.floor(diffMins / (24 * 60));
  const hours = Math.floor((diffMins % (24 * 60)) / 60);
  const mins = diffMins % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

function recomputeResetCountdowns(payload, now = Date.now()) {
  if (!payload || !Array.isArray(payload.groups)) return payload;
  const groups = payload.groups.map((g) => {
    if (!g || !Array.isArray(g.buckets)) return g;
    const buckets = g.buckets.map((b) => {
      if (!b || b.outdated === true || b.reset_in === 'Outdated') return b;
      const target = b.reset_time || b.resets_at;
      if (!target) return b;
      const nextResetIn = formatResetFromIso(target, now);
      if (!nextResetIn) return b;
      return { ...b, reset_in: nextResetIn };
    });
    return { ...g, buckets };
  });
  return { ...payload, groups };
}

function readBackoffState(filePath) {
  try {
    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
    return {
      until: Number(raw.until) || 0,
      attempts: Number(raw.attempts) || 0,
      delayMs: Number(raw.delayMs) || 0
    };
  } catch (_) {
    return { until: 0, attempts: 0, delayMs: 0 };
  }
}

function recordBackoff429(filePath, retryAfterSeconds = 0, now = Date.now()) {
  const prev = readBackoffState(filePath);
  const attempts = (prev.attempts || 0) + 1;
  const expMs = Math.min(BACKOFF_MAX_MS, BACKOFF_BASE_MS * Math.pow(2, attempts - 1));
  let delayMs = expMs;
  if (retryAfterSeconds > 0) {
    const retryMs = Math.min(Math.max(retryAfterSeconds * 1000, BACKOFF_MIN_MS), BACKOFF_MAX_MS);
    delayMs = attempts === 1 ? retryMs : Math.max(expMs, retryMs);
  }
  const state = { until: now + delayMs, attempts, delayMs };
  try {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, JSON.stringify(state), { encoding: 'utf8', mode: 0o600 });
  } catch (_) {}
  return state;
}

function clearBackoffState(filePath) {
  try { fs.rmSync(filePath, { force: true }); } catch (_) {}
}

function storeFile() {
  const dir = path.join(os.homedir(), '.config', 'UniversalAIQuota');
  try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
  return path.join(dir, 'last_good.json');
}

function load() {
  try {
    const data = JSON.parse(fs.readFileSync(storeFile(), 'utf8'));
    return data && typeof data === 'object' ? data : {};
  } catch (_) {
    return {};
  }
}

function save(store) {
  try {
    fs.writeFileSync(storeFile(), JSON.stringify(store), { encoding: 'utf8', mode: 0o600 });
  } catch (_) {}
}

function isUsable(value) {
  if (!value) return false;
  if (Array.isArray(value.groups) && value.groups.length === 0) return false;
  return true;
}

/**
 * @param {string[]} keys      one key per provider, same order as `settled`
 * @param {Array}    settled   results of Promise.allSettled
 * @returns {Array}            the results to show (fresh ones, or stale ones for providers that just failed)
 */
function mergeWithLastGood(keys, settled, now = Date.now()) {
  const store = load();
  let changed = false;
  const out = [];

  settled.forEach((r, i) => {
    const key = keys[i];
    if (r.status === 'fulfilled' && isUsable(r.value)) {
      store[key] = { at: now, value: r.value };
      changed = true;
      out.push(r.value);
      return;
    }
    const last = store[key];
    if (last && last.value && (now - last.at) < GRACE_MS) {
      const refreshed = recomputeResetCountdowns(last.value, now);
      out.push({ ...refreshed, stale: true, stale_seconds: Math.round((now - last.at) / 1000) });
    }
  });

  for (const k of Object.keys(store)) {
    if (!store[k] || (now - (store[k].at || 0)) > PRUNE_MS) {
      delete store[k];
      changed = true;
    }
  }
  if (changed) save(store);
  return out;
}

module.exports = {
  mergeWithLastGood,
  GRACE_MS,
  recomputeResetCountdowns,
  formatResetFromIso,
  readBackoffState,
  recordBackoff429,
  clearBackoffState,
  BACKOFF_BASE_MS,
  BACKOFF_MAX_MS
};
