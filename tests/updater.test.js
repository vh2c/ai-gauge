/**
 * Tests for the API contact rules in core/updater.js.
 * Run:  node tests/updater.test.js
 *
 * Uses a throw-away HOME and a local fake API. Never touches the real network or your real config.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const https = require('https');
const { EventEmitter } = require('events');

// --- isolated environment -------------------------------------------------------------------------------
const TMP_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-test-'));
process.env.HOME = TMP_HOME;
process.env.USERPROFILE = TMP_HOME;
const CFG_DIR = path.join(TMP_HOME, '.config', 'UniversalAIQuota');

// GitHub fallback must never hit the real network in tests
let githubCalls = 0;
https.get = () => {
  githubCalls++;
  const req = new EventEmitter();
  req.destroy = () => {};
  setImmediate(() => req.emit('error', new Error('offline (test)')));
  return req;
};

let server;
let requests = [];
let respond = () => ({ status: 200, body: {} });

function startServer() {
  return new Promise((resolve) => {
    server = http.createServer((req, res) => {
      let raw = '';
      req.on('data', c => { raw += c; });
      req.on('end', () => {
        let body = {};
        try { body = JSON.parse(raw); } catch (_) {}
        requests.push(body);
        const r = respond(body);
        res.writeHead(r.status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(r.body));
      });
    }).listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function reset() {
  requests = [];
  githubCalls = 0;
  fs.rmSync(CFG_DIR, { recursive: true, force: true });
  fs.mkdirSync(CFG_DIR, { recursive: true });
}
const cachePath = () => path.join(CFG_DIR, 'update_cache.json');
const readCache = () => JSON.parse(fs.readFileSync(cachePath(), 'utf8'));
const patchCache = (patch) => fs.writeFileSync(cachePath(), JSON.stringify({ ...readCache(), ...patch }));

const FREE_OK = () => ({ status: 200, body: {
  success: true, tier: 'free', latest_version: '9.9.9', download_url: 'https://example.test/dl',
  announcement: { type: 'aviso', title: 'Hello' },
  promo: { type: 'publicidade', title: 'Offer' }
} });
const PRO_OK = () => ({ status: 200, body: { success: true, tier: 'pro', latest_version: '9.9.9', announcement: null, promo: null } });

const tests = [];
const test = (name, fn) => tests.push({ name, fn });

let updater;

// --- tests ---------------------------------------------------------------------------------------------
test('startup (FREE): one launch call with the full anonymous payload, cache filled', async () => {
  respond = FREE_OK;
  const r = await updater.checkForUpdates({ startup: true });
  assert.strictEqual(requests.length, 1);
  const p = requests[0];
  assert.strictEqual(p.check_only, undefined, 'a startup call must count as a launch');
  assert.ok(p.machine_id && p.version && p.os && p.arch && p.timestamp, 'FREE sends id, version, os, arch');
  assert.strictEqual(r.latest_version, '9.9.9');
  assert.strictEqual(r.update_available, true);
  assert.strictEqual(r.promo.title, 'Offer');
  const c = readCache();
  assert.ok(c.next_check_at - Date.now() > 23 * 3600 * 1000, 'next check in about 24h');
});

test('normal refreshes after startup make NO network call', async () => {
  respond = FREE_OK;
  await updater.checkForUpdates({ startup: true });
  for (let i = 0; i < 5; i++) await updater.checkForUpdates({});
  assert.strictEqual(requests.length, 1);
});

test('restarting within 10 minutes does not call the API again', async () => {
  respond = FREE_OK;
  await updater.checkForUpdates({ startup: true });
  const r = await updater.checkForUpdates({ startup: true });
  assert.strictEqual(requests.length, 1);
  assert.strictEqual(r.promo.title, 'Offer', 'cached promo is still returned');
});

test('restarting after 10 minutes calls the API again', async () => {
  respond = FREE_OK;
  await updater.checkForUpdates({ startup: true });
  patchCache({ last_launch_at: Date.now() - updater.STARTUP_MIN_GAP_MS - 1000 });
  await updater.checkForUpdates({ startup: true });
  assert.strictEqual(requests.length, 2);
});

test('app left open for 24h: one plain check (check_only), not counted as a launch', async () => {
  respond = FREE_OK;
  await updater.checkForUpdates({ startup: true });
  patchCache({ next_check_at: Date.now() - 1000 });
  await updater.checkForUpdates({});
  assert.strictEqual(requests.length, 2);
  assert.strictEqual(requests[1].check_only, true);
  await updater.checkForUpdates({});
  assert.strictEqual(requests.length, 2, 'and no further call until the next 24h');
});

test('PRO: sends only machine_id and version (no os, arch or timestamp)', async () => {
  respond = PRO_OK;
  await updater.checkForUpdates({ startup: true });          // first call: tier unknown -> FREE-style payload
  assert.strictEqual(readCache().tier, 'pro');
  patchCache({ last_launch_at: Date.now() - updater.STARTUP_MIN_GAP_MS - 1000 });
  await updater.checkForUpdates({ startup: true });          // now known to be PRO
  const p = requests[1];
  assert.deepStrictEqual(Object.keys(p).sort(), ['app', 'machine_id', 'version']);
  patchCache({ next_check_at: Date.now() - 1000 });
  await updater.checkForUpdates({});
  assert.deepStrictEqual(Object.keys(requests[2]).sort(), ['app', 'check_only', 'machine_id', 'version']);
});

test('API down: keeps the last announcement/promo, retries in 1h, does not retry on every refresh', async () => {
  respond = FREE_OK;
  await updater.checkForUpdates({ startup: true });
  respond = () => ({ status: 500, body: {} });
  patchCache({ last_launch_at: Date.now() - updater.STARTUP_MIN_GAP_MS - 1000 });
  const r = await updater.checkForUpdates({ startup: true });
  assert.strictEqual(r.announcement.title, 'Hello');
  assert.strictEqual(r.promo.title, 'Offer');
  const wait = readCache().next_check_at - Date.now();
  assert.ok(wait > 50 * 60 * 1000 && wait <= 61 * 60 * 1000, `retry in about 1h (was ${Math.round(wait / 60000)} min)`);
  const before = requests.length;
  for (let i = 0; i < 5; i++) await updater.checkForUpdates({});
  assert.strictEqual(requests.length, before, 'no hammering while offline');
});

test('telemetry opted out: the AI Gauge API is never called and no announcement/promo is kept', async () => {
  respond = FREE_OK;
  fs.writeFileSync(path.join(CFG_DIR, 'config.json'), JSON.stringify({ telemetry: false }));
  const r = await updater.checkForUpdates({ startup: true });
  await updater.checkForUpdates({});
  assert.strictEqual(requests.length, 0);
  assert.strictEqual(r.announcement, null);
  assert.strictEqual(r.promo, null);
  assert.strictEqual(r.tier, 'free');
});

// --- runner --------------------------------------------------------------------------------------------
(async () => {
  const port = await startServer();
  process.env.AIGAUGE_API_URL = `http://127.0.0.1:${port}/v1/geminigauje`;
  updater = require('../core/updater');

  let failed = 0;
  for (const t of tests) {
    reset();
    try {
      await t.fn();
      console.log(`  ok   ${t.name}`);
    } catch (e) {
      failed++;
      console.log(`  FAIL ${t.name}\n       ${e.message}`);
    }
  }
  server.close();
  fs.rmSync(TMP_HOME, { recursive: true, force: true });
  console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
  process.exit(failed ? 1 : 0);
})();
