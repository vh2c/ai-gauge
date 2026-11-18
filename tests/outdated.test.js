/**
 * Tests for the "Outdated" marker: numbers that come from an old local cache must not look current.
 * Run:  node tests/outdated.test.js
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const TMP_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-out-'));
process.env.HOME = TMP_HOME;
process.env.USERPROFILE = TMP_HOME;
const dir = path.join(TMP_HOME, '.config', 'UniversalAIQuota');
fs.mkdirSync(dir, { recursive: true });

const { markOutdated, OUTDATED_AFTER_MS } = require('../core/staleness');
const { ClaudeProProvider } = require('../core/providers/claude_pro');
const { ChatGPTSubscriptionProvider } = require('../core/providers/chatgpt_subscription');

const MIN = 60 * 1000;
const claudeData = { five_hour: { utilization: 15, resets_at: new Date(Date.now() + 3 * 3600_000).toISOString() },
                     seven_day: { utilization: 31, resets_at: new Date(Date.now() + 2 * 86400_000).toISOString() } };
const writeClaude = (ageMs) => fs.writeFileSync(path.join(dir, 'claude_pro_cache.json'), JSON.stringify({ timestamp: Date.now() - ageMs, data: claudeData }));
const writeChatgpt = (ageMs) => fs.writeFileSync(path.join(dir, 'chatgpt_cache.json'), JSON.stringify({ timestamp: Date.now() - ageMs, data: { plan_type: 'plus', email: 'x@example.test' } }));

const tests = [];
const test = (n, f) => tests.push({ n, f });

test('markOutdated leaves recent data untouched', () => {
  const p = { groups: [{ buckets: [{ reset_in: '4h' }] }] };
  markOutdated(p, 5 * MIN, 'hint');
  assert.strictEqual(p.groups[0].buckets[0].reset_in, '4h');
  assert.ok(!p.groups[0].outdated);
});

test('markOutdated flags old data and sets the hint', () => {
  const p = { groups: [{ buckets: [{ reset_in: '4h', detail: 'x' }, { reset_in: '2d', detail: 'y' }] }] };
  markOutdated(p, OUTDATED_AFTER_MS + MIN, 'Outdated: sign in');
  assert.ok(p.groups[0].outdated);
  assert.deepStrictEqual(p.groups[0].buckets.map(b => b.reset_in), ['Outdated', 'Outdated']);
  assert.strictEqual(p.groups[0].buckets[0].detail, 'Outdated: sign in');
});

test('Claude: a cache from 17 hours ago is shown as Outdated (the real-world case)', () => {
  writeClaude(17 * 60 * MIN);
  const r = new ClaudeProProvider('t').fetchFromCache();
  assert.ok(r.groups[0].outdated);
  assert.strictEqual(r.groups[0].buckets[0].reset_in, 'Outdated');
  assert.strictEqual(r.groups[0].buckets[0].remaining_pct, 85);      // the numbers are still there, just flagged
  assert.match(r.groups[0].buckets[0].detail, /sign in to Claude Code/);
});

test('Claude: a cache from 5 minutes ago is shown normally', () => {
  writeClaude(5 * MIN);
  const r = new ClaudeProProvider('t').fetchFromCache();
  assert.ok(!r.groups[0].outdated);
  assert.notStrictEqual(r.groups[0].buckets[0].reset_in, 'Outdated');
});

test('ChatGPT: an old cache is shown as Outdated, a recent one is not', () => {
  writeChatgpt(3 * 60 * MIN);
  const old = new ChatGPTSubscriptionProvider('t').fetchFromCache('t');
  assert.ok(old.groups[0].outdated);
  writeChatgpt(2 * MIN);
  const fresh = new ChatGPTSubscriptionProvider('t').fetchFromCache('t');
  assert.ok(!fresh.groups[0].outdated);
});

test('Claude: desktop usage from recent session is loaded cleanly', () => {
  const desktopDir = path.join(TMP_HOME, 'ClaudeDesktop');
  fs.mkdirSync(desktopDir, { recursive: true });
  fs.writeFileSync(path.join(desktopDir, 'plan-usage-history.json'), JSON.stringify({
    version: 2,
    samples: [
      { t: Date.now() - 5 * MIN, org: 'test-org', u: { fh: 15, sd: 35 } }
    ]
  }));
  const p = new ClaudeProProvider('t');
  const r = p.getDesktopUsage(desktopDir);
  assert.ok(r);
  assert.strictEqual(r.groups[0].outdated, undefined);
  assert.strictEqual(r.groups[0].buckets[0].remaining_pct, 85);
  assert.strictEqual(r.groups[0].buckets[1].remaining_pct, 65);
});

test('Claude: old desktop usage (>30m) is marked Outdated', () => {
  const desktopDir = path.join(TMP_HOME, 'ClaudeDesktopOld');
  fs.mkdirSync(desktopDir, { recursive: true });
  fs.writeFileSync(path.join(desktopDir, 'plan-usage-history.json'), JSON.stringify({
    version: 2,
    samples: [
      { t: Date.now() - 40 * MIN, org: 'test-org', u: { fh: 20, sd: 40 } }
    ]
  }));
  const p = new ClaudeProProvider('t');
  const r = p.getDesktopUsage(desktopDir);
  assert.ok(r);
  assert.strictEqual(r.groups[0].outdated, true);
  assert.strictEqual(r.groups[0].buckets[0].reset_in, 'Outdated');
});

let failed = 0;
for (const t of tests) {
  try { t.f(); console.log('  ok   ' + t.n); } catch (e) { failed++; console.log('  FAIL ' + t.n + '\n       ' + e.message); }
}
fs.rmSync(TMP_HOME, { recursive: true, force: true });
console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
process.exit(failed ? 1 : 0);
