/**
 * Tests for universal API key testing (--test-key / --test-gemini routing) in core/engine.js.
 */
const assert = require('assert');
const https = require('https');
const { EventEmitter } = require('events');
const { detectKeyProvider, testProviderKey } = require('../core/engine');
const { GeminiProvider } = require('../core/providers/gemini');

class FakeSuccessProvider {
  constructor(key) {
    this.key = key;
  }
  async fetch() {
    return { groups: [{ name: 'Fake', buckets: [{ id: 'b1', remaining_pct: 100 }] }] };
  }
}

class FakeFailProvider {
  constructor(key) {
    this.key = key;
  }
  async fetch() {
    return null;
  }
}

(async () => {
  const tests = [];
  const test = (name, fn) => tests.push({ name, fn });

  test('detectKeyProvider identifies Gemini, OpenAI, Anthropic and Claude Pro prefixes', () => {
    assert.strictEqual(detectKeyProvider('AIzaSyTest123'), 'gemini');
    assert.strictEqual(detectKeyProvider('AQ.Ab8RN6Test123'), 'gemini');
    assert.strictEqual(detectKeyProvider('sk-proj-abc123'), 'openai');
    assert.strictEqual(detectKeyProvider('sk-ant-api03-xyz'), 'anthropic');
    assert.strictEqual(detectKeyProvider('sk-ant-oat01-xyz'), 'claude_pro');
    assert.strictEqual(detectKeyProvider('ghp_abc123'), 'github_copilot');
  });

  test('GeminiProvider sends x-goog-api-key for AQ. and AIza keys, Bearer for ya29.', async () => {
    const origGet = https.get;
    const seenHeaders = [];
    https.get = (_url, opts, cb) => {
      seenHeaders.push(opts.headers);
      const res = new EventEmitter();
      res.statusCode = 200;
      process.nextTick(() => {
        cb(res);
        res.emit('data', JSON.stringify({ models: [{ name: 'models/gemini-2.5-flash' }] }));
        res.emit('end');
      });
      const req = new EventEmitter();
      req.destroy = () => {};
      return req;
    };
    try {
      const rAq = await GeminiProvider.testConnection('AQ.Ab8RN6TestKey');
      assert.ok(rAq && rAq.provider === 'gemini_api');
      assert.strictEqual(seenHeaders[0]['x-goog-api-key'], 'AQ.Ab8RN6TestKey');
      assert.strictEqual(seenHeaders[0]['Authorization'], undefined);

      const rAiza = await GeminiProvider.testConnection('AIzaSyTestKey');
      assert.ok(rAiza && rAiza.provider === 'gemini_api');
      assert.strictEqual(seenHeaders[1]['x-goog-api-key'], 'AIzaSyTestKey');
      assert.strictEqual(seenHeaders[1]['Authorization'], undefined);

      const rOauth = await GeminiProvider.testConnection('ya29.OAuthToken');
      assert.ok(rOauth && rOauth.provider === 'gemini_api');
      assert.strictEqual(seenHeaders[2]['Authorization'], 'Bearer ya29.OAuthToken');
      assert.strictEqual(seenHeaders[2]['x-goog-api-key'], undefined);
    } finally {
      https.get = origGet;
    }
  });

  test('testProviderKey routes explicit provider names correctly', async () => {
    const fakeClasses = {
      gemini: FakeSuccessProvider,
      openai: FakeSuccessProvider,
      anthropic: FakeFailProvider
    };
    const rGem = await testProviderKey('gemini', 'AIzaSy123', fakeClasses);
    assert.strictEqual(rGem.ok, true);
    assert.strictEqual(rGem.provider, 'gemini');
    assert.strictEqual(rGem.status, 'OK');

    const rOai = await testProviderKey('openai', 'sk-123', fakeClasses);
    assert.strictEqual(rOai.ok, true);
    assert.strictEqual(rOai.provider, 'openai');
    assert.strictEqual(rOai.status, 'OK');

    const rAnt = await testProviderKey('anthropic', 'sk-ant-bad', fakeClasses);
    assert.strictEqual(rAnt.ok, false);
    assert.strictEqual(rAnt.provider, 'anthropic');
  });

  test('testProviderKey auto-detects provider when only key is provided', async () => {
    const fakeClasses = {
      gemini: FakeFailProvider,
      openai: FakeSuccessProvider,
      anthropic: FakeSuccessProvider
    };
    const r1 = await testProviderKey('sk-test-key', '', fakeClasses);
    assert.strictEqual(r1.ok, true);
    assert.strictEqual(r1.provider, 'openai');

    const r2 = await testProviderKey('sk-ant-api03-test', '', fakeClasses);
    assert.strictEqual(r2.ok, true);
    assert.strictEqual(r2.provider, 'anthropic');
  });

  test('testProviderKey rejects empty key gracefully', async () => {
    const r = await testProviderKey('openai', '   ');
    assert.strictEqual(r.ok, false);
    assert.strictEqual(r.provider, 'openai');
  });

  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log('  ok   ' + t.name);
    } catch (e) {
      failed++;
      console.log('  FAIL ' + t.name + '\n       ' + e.message);
    }
  }
  console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
  process.exit(failed ? 1 : 0);
})();
