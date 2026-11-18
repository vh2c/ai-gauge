/**
 * Tests for reading an existing Claude Code login from ~/.claude/.credentials.json (Windows / Linux / macOS fallback).
 * Run:  node tests/claude_file.test.js
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ClaudeProProvider } = require('../core/providers/claude_pro');

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-claude-'));
const dir = path.join(home, '.claude');
const file = path.join(dir, '.credentials.json');
const p = new ClaudeProProvider('explicit-token-so-the-keychain-is-not-touched');

const tests = [];
const test = (n, f) => tests.push({ n, f });

test('reads the OAuth access token', () => {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ claudeAiOauth: { accessToken: 'sk-ant-oat-abc', refreshToken: 'r', expiresAt: Date.now() + 3600_000 } }));
  assert.strictEqual(p.getTokenFromFile(home), 'sk-ant-oat-abc');
});

test('an expired token is still returned (the API call decides), without trying to run the CLI in tests', () => {
  fs.writeFileSync(file, JSON.stringify({ claudeAiOauth: { accessToken: 'old', expiresAt: Date.now() - 1000 } }));
  assert.strictEqual(p.getTokenFromFile(home), 'old');
});

test('missing file -> null', () => {
  fs.rmSync(file, { force: true });
  assert.strictEqual(p.getTokenFromFile(home), null);
});

test('broken JSON -> null (no crash)', () => {
  fs.writeFileSync(file, '{not json');
  assert.strictEqual(p.getTokenFromFile(home), null);
});

test('file without the claudeAiOauth block -> null', () => {
  fs.writeFileSync(file, JSON.stringify({ something: 'else' }));
  assert.strictEqual(p.getTokenFromFile(home), null);
});

let failed = 0;
for (const t of tests) {
  try { t.f(); console.log('  ok   ' + t.n); } catch (e) { failed++; console.log('  FAIL ' + t.n + '\n       ' + e.message); }
}
fs.rmSync(home, { recursive: true, force: true });
console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
process.exit(failed ? 1 : 0);
