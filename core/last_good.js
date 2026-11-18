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
      out.push({ ...last.value, stale: true, stale_seconds: Math.round((now - last.at) / 1000) });
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

module.exports = { mergeWithLastGood, GRACE_MS };
