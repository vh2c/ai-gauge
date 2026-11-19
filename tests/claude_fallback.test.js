/**
 * Claude provider when the live usage call fails (HTTP 429 rate limit, timeout...).
 * Run:  node tests/claude_fallback.test.js
 *
 * Regression: on app start the API answered 429 and the provider showed the Claude Desktop estimate
 * (5h window "expired" -> 100%) until the limit lifted. Now: last REAL numbers (or "--%"), never an invented 100%,
 * and no calls to the API while it asks us to wait.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const { EventEmitter } = require('events');

const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-claude429-'));
process.env.HOME = HOME;
process.env.USERPROFILE = HOME;
process.env.APPDATA = path.join(HOME, 'AppData', 'Roaming');
const CFG = path.join(HOME, '.config', 'UniversalAIQuota');
fs.mkdirSync(CFG, { recursive: true });

// --- fake API -------------------------------------------------------------------------------------------
let respond = null;
let calls = 0;
https.request = (opts, cb) => {
  calls++;
  const req = new EventEmitter();
  req.destroy = () => {};
  req.end = () => setImmediate(() => {
    const r = respond();
    const res = new EventEmitter();
    res.statusCode = r.status;
    res.headers = r.headers || {};
    cb(res);
    res.emit('data', JSON.stringify(r.body || {}));
    res.emit('end');
  });
  return req;
};
const { ClaudeProProvider } = require('../core/providers/claude_pro');

const usage = (fh, sd, resets5h) => ({ five_hour: { utilization: fh, resets_at: resets5h }, seven_day: { utilization: sd, resets_at: new Date(Date.now() + 3 * 86400e3).toISOString() } });
const OK = (fh, sd) => () => ({ status: 200, body: usage(fh, sd, new Date(Date.now() + 2 * 3600e3).toISOString()) });
const TOO_MANY = (headers) => () => ({ status: 429, headers: headers || {}, body: { error: 'rate_limited' } });

const cachePath = path.join(CFG, 'claude_pro_cache.json');
const backoffPath = path.join(CFG, 'claude_pro_backoff.json');
const desktopFile = process.platform === 'darwin'
  ? path.join(HOME, 'Library', 'Application Support', 'Claude', 'plan-usage-history.json')
  : (process.platform === 'win32' ? path.join(process.env.APPDATA, 'Claude', 'plan-usage-history.json') : path.join(HOME, '.config', 'Claude', 'plan-usage-history.json'));

const reset = () => {
  for (const f of [cachePath, backoffPath, desktopFile]) fs.rmSync(f, { force: true });
  calls = 0;
};
// The Claude Desktop history whose last sample is 6h old: its estimator says "5h window expired -> 100%"
const writeDesktopHistory = () => {
  fs.mkdirSync(path.dirname(desktopFile), { recursive: true });
  fs.writeFileSync(desktopFile, JSON.stringify({ samples: [{ t: Date.now() - 6 * 3600e3, u: { fh: 10, sd: 52 } }] }));
};
const ageCache = (ms) => { const c = JSON.parse(fs.readFileSync(cachePath, 'utf8')); c.timestamp = Date.now() - ms; fs.writeFileSync(cachePath, JSON.stringify(c)); };
const b5 = (r) => r.groups[0].buckets.find(b => b.id === 'claude-pro-5h');
const b7 = (r) => r.groups[0].buckets.find(b => b.id === 'claude-pro-7d');
const provider = () => new ClaudeProProvider('explicit-token');

const tests = [];
const test = (n, f) => tests.push({ n, f });

test('baseline: a 200 shows the real numbers and stores them', async () => {
  reset(); respond = OK(28, 56);
  const r = await provider().fetch();
  assert.strictEqual(b5(r).remaining_pct, 72);
  assert.strictEqual(b7(r).remaining_pct, 44);
  assert.ok(fs.existsSync(cachePath));
});

test('429 on app start: shows the last REAL numbers, not the Desktop estimate (100%)', async () => {
  reset(); writeDesktopHistory();
  respond = OK(28, 56); await provider().fetch(); ageCache(60_000);          // a previous session left real data
  respond = TOO_MANY();
  const r = await provider().fetch();
  assert.strictEqual(b5(r).remaining_pct, 72, '5h must be the real 72, not an invented 100');
  assert.strictEqual(b7(r).remaining_pct, 44);
  assert.notStrictEqual(r.mode, 'desktop_session');
  assert.ok(!b5(r).outdated);
});

test('429 starts a pause: the next refreshes do NOT call the API and keep showing real numbers', async () => {
  reset(); writeDesktopHistory();
  respond = OK(28, 56); await provider().fetch(); ageCache(60_000);
  respond = TOO_MANY(); await provider().fetch();
  assert.ok(fs.existsSync(backoffPath));
  const before = calls;
  for (let i = 0; i < 3; i++) { const r = await provider().fetch(); assert.strictEqual(b5(r).remaining_pct, 72); }
  assert.strictEqual(calls, before, 'no request while paused');
});

test('Retry-After is honoured (clamped to 30s..5min); default is 60s', async () => {
  reset(); respond = OK(10, 10); await provider().fetch(); ageCache(60_000);
  respond = TOO_MANY({ 'retry-after': '120' }); await provider().fetch();
  const wait = JSON.parse(fs.readFileSync(backoffPath, 'utf8')).until - Date.now();
  assert.ok(wait > 110_000 && wait <= 120_500, 'about 120s: ' + wait);
  fs.rmSync(backoffPath); ageCache(60_000);
  respond = TOO_MANY(); await provider().fetch();
  const w2 = JSON.parse(fs.readFileSync(backoffPath, 'utf8')).until - Date.now();
  assert.ok(w2 > 55_000 && w2 <= 60_500, 'default 60s: ' + w2);
});

test('after the pause a 200 returns to live data and clears it', async () => {
  reset(); respond = OK(28, 56); await provider().fetch(); ageCache(60_000);
  respond = TOO_MANY(); await provider().fetch();
  fs.writeFileSync(backoffPath, JSON.stringify({ until: Date.now() - 1 }));      // pause is over
  respond = OK(50, 60); const r = await provider().fetch();
  assert.strictEqual(b5(r).remaining_pct, 50);
  assert.ok(!fs.existsSync(backoffPath));
});

test('cached 5h window already ended: that bucket is "--%" (Outdated), never 100%', async () => {
  reset(); writeDesktopHistory();
  fs.writeFileSync(cachePath, JSON.stringify({ timestamp: Date.now() - 60_000, data: usage(28, 56, new Date(Date.now() - 1000).toISOString()) }));
  respond = TOO_MANY();
  const r = await provider().fetch();
  assert.strictEqual(b5(r).reset_in, 'Outdated');
  assert.strictEqual(b5(r).outdated, true);
  assert.strictEqual(b7(r).remaining_pct, 44, 'the weekly number is still the real one');
  assert.notStrictEqual(b7(r).reset_in, 'Outdated');
});

test('real cache older than 30 min: everything flagged Outdated', async () => {
  reset();
  fs.writeFileSync(cachePath, JSON.stringify({ timestamp: Date.now() - 3 * 3600e3, data: usage(28, 56, new Date(Date.now() + 3600e3).toISOString()) }));
  respond = TOO_MANY();
  const r = await provider().fetch();
  assert.ok(r.groups[0].buckets.every(b => b.reset_in === 'Outdated'));
});

test('network timeout / error (status 0) behaves like 429: real cache, no invented 100%', async () => {
  reset(); writeDesktopHistory();
  respond = OK(28, 56); await provider().fetch(); ageCache(60_000);
  respond = () => ({ status: 0 });
  const r = await provider().fetch();
  assert.strictEqual(b5(r).remaining_pct, 72);
  assert.ok(!fs.existsSync(backoffPath), 'only a 429 pauses the calls');
});

test('nothing real at all (first run) and the call fails: falls back to the Desktop data (only source left)', async () => {
  reset(); writeDesktopHistory();
  respond = TOO_MANY();
  const r = await provider().fetch();
  assert.strictEqual(r.mode, 'desktop_session');
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try { await t.f(); console.log('  ok   ' + t.n); }
    catch (e) { failed++; console.log('  FAIL ' + t.n + '\n       ' + (e && e.message)); }
  }
  console.log(failed ? `\n${failed} test(s) FAILED` : `\nAll ${tests.length} tests passed`);
  process.exit(failed ? 1 : 0);
})();
