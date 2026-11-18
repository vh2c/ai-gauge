/**
 * Tests for UTF-8 BOM handling in config loading/saving and local credential files (Windows PowerShell 5.1 compatibility).
 * Run: node tests/config_bom.test.js
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { loadConfig, saveConfig, stripBom } = require('../core/engine');
const { ClaudeProProvider } = require('../core/providers/claude_pro');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-bom-'));
const cfgFile = path.join(tmpDir, 'config.json');
const claudeDir = path.join(tmpDir, '.claude');
const claudeFile = path.join(claudeDir, '.credentials.json');

const tests = [];
const test = (n, f) => tests.push({ n, f });

test('stripBom removes leading U+FEFF without altering clean strings', () => {
  assert.strictEqual(stripBom('\uFEFF{"a":1}'), '{"a":1}');
  assert.strictEqual(stripBom('{"a":1}'), '{"a":1}');
});

test('loadConfig parses config.json written with a UTF-8 BOM (Windows PowerShell 5.1)', () => {
  const payload = '\uFEFF' + JSON.stringify({ providers: { antigravity: { enabled: true }, cursor: { enabled: true } } });
  fs.writeFileSync(cfgFile, payload, 'utf8');
  const loaded = loadConfig(cfgFile);
  assert.strictEqual(loaded.providers.antigravity.enabled, true);
  assert.strictEqual(loaded.providers.cursor.enabled, true);
});

test('saveConfig writes UTF-8 without BOM', () => {
  const ok = saveConfig({ providers: { antigravity: { enabled: true } } }, cfgFile);
  assert.strictEqual(ok, true);
  const raw = fs.readFileSync(cfgFile, 'utf8');
  assert.notStrictEqual(raw.charCodeAt(0), 0xFEFF);
  assert.strictEqual(JSON.parse(raw).providers.antigravity.enabled, true);
});

test('ClaudeProProvider.getTokenFromFile handles UTF-8 BOM in .credentials.json', () => {
  fs.mkdirSync(claudeDir, { recursive: true });
  const cred = '\uFEFF' + JSON.stringify({ claudeAiOauth: { accessToken: 'sk-ant-bom-test', expiresAt: Date.now() + 3600_000 } });
  fs.writeFileSync(claudeFile, cred, 'utf8');
  const p = new ClaudeProProvider('explicit-token-so-the-keychain-is-not-touched');
  assert.strictEqual(p.getTokenFromFile(tmpDir), 'sk-ant-bom-test');
});

let failed = 0;
for (const t of tests) {
  try { t.f(); console.log('  ok   ' + t.n); } catch (e) { failed++; console.log('  FAIL ' + t.n + '\n       ' + e.message); }
}
fs.rmSync(tmpDir, { recursive: true, force: true });
console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
process.exit(failed ? 1 : 0);
