/**
 * Tests for core/last_good.js (a provider that fails for one cycle must not vanish from the screen).
 * Run:  node tests/last_good.test.js
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const TMP_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-lg-'));
process.env.HOME = TMP_HOME;
process.env.USERPROFILE = TMP_HOME;
const { mergeWithLastGood, GRACE_MS } = require('../core/last_good');

const ok = (name) => ({ status: 'fulfilled', value: { provider: name, groups: [{ name: name + ' group', buckets: [] }] } });
const nul = { status: 'fulfilled', value: null };
const boom = { status: 'rejected', reason: new Error('timeout') };
const empty = { status: 'fulfilled', value: { provider: 'x', groups: [] } };

const reset = () => fs.rmSync(path.join(TMP_HOME, '.config'), { recursive: true, force: true });
const tests = [];
const test = (n, f) => tests.push({ n, f });
const T0 = 1_000_000_000_000;

test('fresh results pass through untouched', () => {
  const out = mergeWithLastGood(['a', 'b'], [ok('a'), ok('b')], T0);
  assert.strictEqual(out.length, 2);
  assert.ok(!out[0].stale && !out[1].stale);
});

test('a provider that returns null for one cycle keeps its last good result (stale)', () => {
  mergeWithLastGood(['antigravity'], [ok('antigravity')], T0);
  const out = mergeWithLastGood(['antigravity'], [nul], T0 + 30_000);
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].stale, true);
  assert.strictEqual(out[0].stale_seconds, 30);
  assert.strictEqual(out[0].groups[0].name, 'antigravity group');
});

test('a rejected provider keeps its last good result', () => {
  mergeWithLastGood(['a'], [ok('a')], T0);
  assert.strictEqual(mergeWithLastGood(['a'], [boom], T0 + 60_000).length, 1);
});

test('a provider that returns no groups counts as a failure', () => {
  mergeWithLastGood(['a'], [ok('a')], T0);
  const out = mergeWithLastGood(['a'], [empty], T0 + 30_000);
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].stale, true);
});

test('after the grace period the provider is dropped (really gone)', () => {
  mergeWithLastGood(['a'], [ok('a')], T0);
  assert.strictEqual(mergeWithLastGood(['a'], [nul], T0 + GRACE_MS + 1000).length, 0);
});

test('a provider that never succeeded shows nothing', () => {
  assert.strictEqual(mergeWithLastGood(['a'], [nul], T0).length, 0);
});

test('one provider failing does not affect the others', () => {
  mergeWithLastGood(['a', 'b'], [ok('a'), ok('b')], T0);
  const out = mergeWithLastGood(['a', 'b'], [nul, ok('b')], T0 + 30_000);
  assert.strictEqual(out.length, 2);
  assert.strictEqual(out.filter(x => x.stale).length, 1);
});

test('a new success replaces the stored result', () => {
  mergeWithLastGood(['a'], [ok('a')], T0);
  mergeWithLastGood(['a'], [{ status: 'fulfilled', value: { provider: 'a', groups: [{ name: 'newer' }] } }], T0 + 30_000);
  const out = mergeWithLastGood(['a'], [nul], T0 + 60_000);
  assert.strictEqual(out[0].groups[0].name, 'newer');
});

let failed = 0;
for (const t of tests) {
  reset();
  try { t.f(); console.log('  ok   ' + t.n); } catch (e) { failed++; console.log('  FAIL ' + t.n + '\n       ' + e.message); }
}
fs.rmSync(TMP_HOME, { recursive: true, force: true });
console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
process.exit(failed ? 1 : 0);
