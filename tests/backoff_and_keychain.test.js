/**
 * Tests for persisted exponential 429 backoff (60s -> 15 min), local reset_in recomputation,
 * ChatGPT 429 pause, and Keychain-avoidance ordering in ClaudeProProvider.
 * Run: node tests/backoff_and_keychain.test.js
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const { EventEmitter } = require('events');

const TMP_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-backoff-'));
process.env.HOME = TMP_HOME;
process.env.USERPROFILE = TMP_HOME;
process.env.APPDATA = path.join(TMP_HOME, 'AppData', 'Roaming');
const CFG_DIR = path.join(TMP_HOME, '.config', 'UniversalAIQuota');
fs.mkdirSync(CFG_DIR, { recursive: true });

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

const {
  mergeWithLastGood,
  recomputeResetCountdowns,
  readBackoffState,
  recordBackoff429,
  clearBackoffState,
  BACKOFF_BASE_MS,
  BACKOFF_MAX_MS
} = require('../core/last_good');
const { ClaudeProProvider } = require('../core/providers/claude_pro');
const { ChatGPTSubscriptionProvider } = require('../core/providers/chatgpt_subscription');

const tests = [];
const test = (n, f) => tests.push({ n, f });

function resetAll() {
  fs.rmSync(CFG_DIR, { recursive: true, force: true });
  fs.rmSync(path.join(TMP_HOME, '.claude'), { recursive: true, force: true });
  fs.mkdirSync(CFG_DIR, { recursive: true });
  calls = 0;
}

test('recordBackoff429 escalates exponentially 60s -> 120s -> 240s -> 480s -> 900s and clears cleanly', () => {
  resetAll();
  const bf = path.join(CFG_DIR, 'exp_backoff.json');
  const t0 = 1_795_500_000_000;
  const expected = [60_000, 120_000, 240_000, 480_000, 900_000, 900_000];
  expected.forEach((ms, idx) => {
    const st = recordBackoff429(bf, 0, t0 + idx * 1000);
    assert.strictEqual(st.delayMs, ms);
    assert.strictEqual(st.attempts, idx + 1);
    assert.strictEqual(readBackoffState(bf).until, t0 + idx * 1000 + ms);
  });
  clearBackoffState(bf);
  assert.strictEqual(readBackoffState(bf).attempts, 0);
  assert.strictEqual(readBackoffState(bf).until, 0);
});

test('recomputeResetCountdowns & mergeWithLastGood update reset_in against system clock while preserving Outdated', () => {
  resetAll();
  const T0 = 1_795_500_000_000;
  const targetIso = new Date(T0 + 3 * 3600_000 + 30 * 60_000).toISOString();
  const payload = {
    provider: 'claude_pro',
    groups: [{
      name: 'Claude',
      buckets: [
        { id: 'b1', name: '5h', remaining_pct: 80, reset_in: '3h 30m', reset_time: targetIso },
        { id: 'b2', name: '7d', remaining_pct: 50, reset_in: 'Outdated', outdated: true, reset_time: targetIso }
      ]
    }]
  };

  mergeWithLastGood(['claude_pro'], [{ status: 'fulfilled', value: payload }], T0);
  // 2 minutes later, provider times out -> stale result must recalculate reset_in to 3h 28m
  const out = mergeWithLastGood(['claude_pro'], [{ status: 'fulfilled', value: null }], T0 + 120_000);
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].stale, true);
  assert.strictEqual(out[0].groups[0].buckets[0].reset_in, '3h 28m');
  assert.strictEqual(out[0].groups[0].buckets[1].reset_in, 'Outdated');

  // Once reset_time passes, recomputeResetCountdowns reports Now
  const expired = recomputeResetCountdowns(payload, T0 + 4 * 3600_000);
  assert.strictEqual(expired.groups[0].buckets[0].reset_in, 'Now');
});

test('ClaudeProProvider avoids Keychain in constructor, during fresh cache, during 429 backoff, and when file/token cache exist', async () => {
  resetAll();
  let keychainCalls = 0;
  const origKc = ClaudeProProvider.prototype.getTokenFromKeychain;
  ClaudeProProvider.prototype.getTokenFromKeychain = function () {
    keychainCalls++;
    return 'kc-token-123';
  };

  try {
    // 1. Constructor must not touch Keychain
    const p0 = new ClaudeProProvider();
    assert.strictEqual(keychainCalls, 0);

    // 2. When token_cache exists and is valid, fetch uses it with 0 Keychain calls
    fs.writeFileSync(path.join(CFG_DIR, 'claude_pro_token_cache.json'), JSON.stringify({
      token: 'cached-tok',
      expiresAt: Date.now() + 3600_000
    }));
    respond = () => ({
      status: 200,
      body: {
        five_hour: { utilization: 10, resets_at: new Date(Date.now() + 3600_000).toISOString() },
        seven_day: { utilization: 20, resets_at: new Date(Date.now() + 86400_000).toISOString() }
      }
    });
    const r1 = await p0.fetch();
    assert.strictEqual(keychainCalls, 0);
    assert.strictEqual(r1.groups[0].buckets[0].remaining_pct, 90);
    assert.ok(r1.groups[0].buckets[0].reset_time);

    // 3. When ~/.claude/.credentials.json exists (even with expired dedicated cache), Keychain is still skipped
    fs.rmSync(path.join(CFG_DIR, 'claude_pro_token_cache.json'), { force: true });
    fs.rmSync(path.join(CFG_DIR, 'claude_pro_cache.json'), { force: true });
    fs.mkdirSync(path.join(TMP_HOME, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(TMP_HOME, '.claude', '.credentials.json'), JSON.stringify({
      claudeAiOauth: { accessToken: 'file-tok', expiresAt: Date.now() + 3600_000 }
    }));
    await new ClaudeProProvider().fetch();
    assert.strictEqual(keychainCalls, 0);

    // 4. During active 429 backoff, Keychain is skipped even without file token
    fs.rmSync(path.join(TMP_HOME, '.claude', '.credentials.json'), { force: true });
    recordBackoff429(path.join(CFG_DIR, 'claude_pro_backoff.json'), 0, Date.now());
    const callsBefore = calls;
    await new ClaudeProProvider().fetch();
    assert.strictEqual(keychainCalls, 0);
    assert.strictEqual(calls, callsBefore);

    // 5. With no file/cache/backoff, falls back to Keychain once
    clearBackoffState(path.join(CFG_DIR, 'claude_pro_backoff.json'));
    fs.rmSync(path.join(CFG_DIR, 'claude_pro_cache.json'), { force: true });
    await new ClaudeProProvider().fetch();
    assert.strictEqual(keychainCalls, 1);
  } finally {
    ClaudeProProvider.prototype.getTokenFromKeychain = origKc;
  }
});

test('ClaudeProProvider escalates 429 backoff across retries and resets attempts on 200', async () => {
  resetAll();
  const cachePath = path.join(CFG_DIR, 'claude_pro_cache.json');
  const backoffPath = path.join(CFG_DIR, 'claude_pro_backoff.json');

  respond = () => ({
    status: 200,
    body: {
      five_hour: { utilization: 15, resets_at: new Date(Date.now() + 3600_000).toISOString() },
      seven_day: { utilization: 25, resets_at: new Date(Date.now() + 86400_000).toISOString() }
    }
  });
  await new ClaudeProProvider('tok').fetch();

  const ageCache = () => {
    const c = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    c.timestamp = Date.now() - 120_000;
    fs.writeFileSync(cachePath, JSON.stringify(c));
  };

  ageCache();
  respond = () => ({ status: 429, headers: {} });
  await new ClaudeProProvider('tok').fetch();
  let bf = readBackoffState(backoffPath);
  assert.strictEqual(bf.attempts, 1);
  assert.strictEqual(bf.delayMs, BACKOFF_BASE_MS);

  // Expire pause manually and hit 429 a second time -> 120s
  fs.writeFileSync(backoffPath, JSON.stringify({ ...bf, until: Date.now() - 10 }));
  ageCache();
  await new ClaudeProProvider('tok').fetch();
  bf = readBackoffState(backoffPath);
  assert.strictEqual(bf.attempts, 2);
  assert.strictEqual(bf.delayMs, 120_000);
  assert.ok(bf.delayMs <= BACKOFF_MAX_MS);

  // Expire pause and succeed with 200 -> backoff cleared
  fs.writeFileSync(backoffPath, JSON.stringify({ ...bf, until: Date.now() - 10 }));
  ageCache();
  respond = () => ({
    status: 200,
    body: {
      five_hour: { utilization: 30, resets_at: new Date(Date.now() + 3600_000).toISOString() },
      seven_day: { utilization: 40, resets_at: new Date(Date.now() + 86400_000).toISOString() }
    }
  });
  const r = await new ClaudeProProvider('tok').fetch();
  assert.strictEqual(r.groups[0].buckets[0].remaining_pct, 70);
  assert.ok(!fs.existsSync(backoffPath));
});

test('ChatGPTSubscriptionProvider persists 429 backoff and skips calls until pause expires', async () => {
  resetAll();
  const cachePath = path.join(CFG_DIR, 'chatgpt_cache.json');
  const backoffPath = path.join(CFG_DIR, 'chatgpt_backoff.json');

  respond = () => ({
    status: 200,
    body: {
      plan_type: 'plus',
      email: 'u@example.test',
      rate_limit: {
        primary_window: { used_percent: 25, reset_at: Math.floor((Date.now() + 7200_000) / 1000) },
        secondary_window: { used_percent: 10, reset_at: Math.floor((Date.now() + 5 * 86400_000) / 1000) }
      }
    }
  });
  const okRes = await new ChatGPTSubscriptionProvider('gpt-tok').fetch();
  assert.strictEqual(okRes.groups[0].buckets[0].remaining_pct, 75);
  assert.ok(okRes.groups[0].buckets[0].reset_time);

  // Age cache > 45s and hit 429
  const c = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  c.timestamp = Date.now() - 120_000;
  fs.writeFileSync(cachePath, JSON.stringify(c));
  respond = () => ({ status: 429, headers: {} });
  const r429 = await new ChatGPTSubscriptionProvider('gpt-tok').fetch();
  assert.strictEqual(r429.groups[0].buckets[0].remaining_pct, 75);
  assert.ok(fs.existsSync(backoffPath));

  // Next call during backoff must not hit network
  const callsBefore = calls;
  const rPaused = await new ChatGPTSubscriptionProvider('gpt-tok').fetch();
  assert.strictEqual(calls, callsBefore);
  assert.strictEqual(rPaused.groups[0].buckets[0].remaining_pct, 75);
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.f();
      console.log('  ok   ' + t.n);
    } catch (e) {
      failed++;
      console.log('  FAIL ' + t.n + '\n       ' + (e && e.stack ? e.stack : e));
    }
  }
  fs.rmSync(TMP_HOME, { recursive: true, force: true });
  console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
  process.exit(failed ? 1 : 0);
})();
