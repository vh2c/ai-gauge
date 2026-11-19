#!/usr/bin/env node
/**
 * Universal AI Quota Engine
 * Aggregates Antigravity (Live & Headless), Google Gemini API, OpenAI, and Anthropic
 * Developed by VH2C • https://vh2c.com.br
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const { AntigravityProvider } = require('./providers/antigravity');
const { GeminiProvider } = require('./providers/gemini');
const { ClaudeProProvider } = require('./providers/claude_pro');
const { ChatGPTSubscriptionProvider } = require('./providers/chatgpt_subscription');
const { CursorProvider } = require('./providers/cursor');
const { GitHubCopilotProvider } = require('./providers/github_copilot');
const { OpenAIProvider } = require('./providers/openai');
const { AnthropicProvider } = require('./providers/anthropic');
const { checkForUpdates, CURRENT_VERSION } = require('./updater');
const { mergeWithLastGood } = require('./last_good');

const CONFIG_DIR = path.join(os.homedir(), '.config', 'UniversalAIQuota');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

let _lastValidConfig = null;

function stripBom(str) {
  return typeof str === 'string' ? str.replace(/^\uFEFF/, '') : str;
}

function loadConfig(filePath = CONFIG_FILE) {
  if (fs.existsSync(filePath)) {
    try {
      const parsed = JSON.parse(stripBom(fs.readFileSync(filePath, 'utf8')));
      if (filePath === CONFIG_FILE) _lastValidConfig = parsed;
      return parsed;
    } catch (e) {
      // Security: If config exists on disk but failed to parse, reuse last known valid config.
      // NEVER silently re-enable disabled sessions!
      if (filePath === CONFIG_FILE && _lastValidConfig) {
        return _lastValidConfig;
      }
      return { providers: {} };
    }
  }
  return {
    providers: {
      antigravity: { enabled: true },
      claude_pro: { enabled: true },
      chatgpt_subscription: { enabled: true },
      cursor: { enabled: true },
      github_copilot: { enabled: true },
      gemini: { enabled: Boolean(process.env.GEMINI_API_KEY), api_key: process.env.GEMINI_API_KEY || '' },
      openai: { enabled: Boolean(process.env.OPENAI_API_KEY), api_key: process.env.OPENAI_API_KEY || '' },
      anthropic: { enabled: Boolean(process.env.ANTHROPIC_API_KEY), api_key: process.env.ANTHROPIC_API_KEY || '' }
    }
  };
}

function saveConfig(cfg, filePath = CONFIG_FILE) {
  try {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, JSON.stringify(cfg, null, 2), 'utf8');
    if (filePath === CONFIG_FILE) _lastValidConfig = cfg;
    return true;
  } catch (_) {
    return false;
  }
}

class UniversalQuotaEngine {
  constructor() {
    this.config = loadConfig();
  }

  buildProviderTasks(scanMode = false, skipKeys = new Set()) {
    const keys = [];
    const providers = [];
    const add = (key, promise) => {
      if (skipKeys.has(key)) return;
      keys.push(key);
      providers.push(promise);
    };
    const pCfg = this.config.providers || {};
    const isEnabled = (v) => v === true || v === 'true' || v === 1 || v === '1';

    if (scanMode || isEnabled(pCfg.antigravity?.enabled)) {
      add('antigravity', new AntigravityProvider().fetch());
    }
    if (scanMode || isEnabled(pCfg.claude_pro?.enabled)) {
      add('claude_pro', new ClaudeProProvider(pCfg.claude_pro?.token).fetch());
    }
    if (scanMode || isEnabled(pCfg.chatgpt_subscription?.enabled)) {
      add('chatgpt_subscription', new ChatGPTSubscriptionProvider(pCfg.chatgpt_subscription?.token).fetch());
    }
    if (scanMode || isEnabled(pCfg.cursor?.enabled)) {
      add('cursor', new CursorProvider(pCfg.cursor?.token).fetch());
    }
    if (scanMode || isEnabled(pCfg.github_copilot?.enabled)) {
      add('github_copilot', new GitHubCopilotProvider(pCfg.github_copilot?.token).fetch());
    }

    const geminiKey = pCfg.gemini?.api_key || process.env.GEMINI_API_KEY || '';
    if ((scanMode && geminiKey) || (isEnabled(pCfg.gemini?.enabled) && geminiKey)) {
      add('gemini', new GeminiProvider(geminiKey).fetch());
    }
    const openaiKey = pCfg.openai?.api_key || process.env.OPENAI_API_KEY || '';
    if ((scanMode && openaiKey) || (isEnabled(pCfg.openai?.enabled) && openaiKey)) {
      add('openai', new OpenAIProvider(openaiKey).fetch());
    }
    const anthropicKey = pCfg.anthropic?.api_key || process.env.ANTHROPIC_API_KEY || '';
    if ((scanMode && anthropicKey) || (isEnabled(pCfg.anthropic?.enabled) && anthropicKey)) {
      add('anthropic', new AnthropicProvider(anthropicKey).fetch());
    }

    return { keys, providers };
  }

  async fetchAll(opts = {}) {
    // Version / announcement check: talks to the network only when the app was just opened (opts.startup)
    // or when 24h have passed since the last check. Otherwise it just reads the local cache.
    const updatePromise = checkForUpdates({ startup: opts.startup === true }).catch(() => null);

    let scanUsed = opts.scan === true;
    const { keys, providers } = this.buildProviderTasks(scanUsed);
    const results = await Promise.allSettled(providers);
    // A provider that fails for one cycle keeps showing its last good result (up to 10 min) instead of vanishing
    let valid = mergeWithLastGood(keys, results);

    // If startup produced 0 valid providers, run a discovery pass over any unprobed local providers/env keys
    if (!scanUsed && opts.startup === true && valid.length === 0) {
      scanUsed = true;
      const alreadyProbed = new Set(keys);
      const scanTasks = this.buildProviderTasks(true, alreadyProbed);
      if (scanTasks.providers.length > 0) {
        const scanResults = await Promise.allSettled(scanTasks.providers);
        valid = mergeWithLastGood(scanTasks.keys, scanResults);
      }
    }

    if (scanUsed && valid.length > 0) {
      if (!this.config.providers) this.config.providers = {};
      let configChanged = false;
      for (const item of valid) {
        if (item && item.provider && Array.isArray(item.groups) && item.groups.length > 0) {
          const cfgKey = item.provider === 'gemini_api' ? 'gemini' : item.provider;
          const prev = this.config.providers[cfgKey] || {};
          if (prev.enabled !== true) {
            this.config.providers[cfgKey] = { ...prev, enabled: true };
            if (cfgKey === 'gemini' && !this.config.providers.gemini.api_key && process.env.GEMINI_API_KEY) {
              this.config.providers.gemini.api_key = process.env.GEMINI_API_KEY;
            }
            if (cfgKey === 'openai' && !this.config.providers.openai.api_key && process.env.OPENAI_API_KEY) {
              this.config.providers.openai.api_key = process.env.OPENAI_API_KEY;
            }
            if (cfgKey === 'anthropic' && !this.config.providers.anthropic.api_key && process.env.ANTHROPIC_API_KEY) {
              this.config.providers.anthropic.api_key = process.env.ANTHROPIC_API_KEY;
            }
            configChanged = true;
          }
        }
      }
      if (configChanged) {
        saveConfig(this.config);
      }
    }

    const updateData = await updatePromise;

    if (valid.length === 0) {
      return {
        needs_setup: true,
        account: 'No Provider Configured',
        plan: 'Setup required',
        providers_count: 0,
        detected_providers: [],
        groups: [],
        version: CURRENT_VERSION,
        tier: updateData?.tier || 'free',
        update: updateData || { current_version: CURRENT_VERSION, update_available: false },
        announcement: updateData?.announcement || null,
        promo: updateData?.promo || null,
        updated_at: new Date().toLocaleTimeString('pt-BR')
      };
    }

    const allGroups = [];
    let mainAccount = 'Multi-Provider AI';
    let mainPlan = 'Universal Hub';

    for (const item of valid) {
      if (item.provider === 'antigravity') {
        mainAccount = item.account;
        mainPlan = item.plan;
      }
      for (const g of item.groups || []) {
        allGroups.push(g);
      }
    }

    return {
      account: mainAccount,
      plan: mainPlan,
      providers_count: valid.length,
      detected_providers: valid.map(v => v.provider),
      groups: allGroups,
      version: CURRENT_VERSION,
      tier: updateData?.tier || 'free',
      update: updateData || { current_version: CURRENT_VERSION, update_available: false },
      announcement: updateData?.announcement || null,
      promo: updateData?.promo || null,
      updated_at: new Date().toLocaleTimeString('pt-BR')
    };
  }
}

function detectKeyProvider(key) {
  const k = (key || '').trim();
  if (k.startsWith('AIza') || k.startsWith('ya29.') || k.startsWith('AQ.')) return 'gemini';
  if (k.startsWith('sk-ant-oat')) return 'claude_pro';
  if (k.startsWith('sk-ant-')) return 'anthropic';
  if (k.startsWith('sk-')) return 'openai';
  if (k.startsWith('ghp_') || k.startsWith('github_pat_') || k.startsWith('gho_')) return 'github_copilot';
  return 'gemini';
}

function normalizeTestProviderName(raw) {
  const p = (raw || '').trim().toLowerCase();
  if (p === 'google' || p === 'gemini_api' || p === 'ai_studio') return 'gemini';
  if (p === 'claude') return 'anthropic';
  if (p === 'chatgpt' || p === 'codex') return 'chatgpt_subscription';
  if (p === 'copilot') return 'github_copilot';
  return p;
}

const KNOWN_TEST_PROVIDERS = new Set([
  'gemini',
  'openai',
  'anthropic',
  'claude_pro',
  'chatgpt_subscription',
  'cursor',
  'github_copilot',
  'google',
  'gemini_api',
  'ai_studio',
  'claude',
  'chatgpt',
  'codex',
  'copilot'
]);

async function testProviderKey(providerArg, keyArg, customProviders) {
  const rawProvider = (providerArg || '').trim().toLowerCase();
  let provider;
  let key;

  if (KNOWN_TEST_PROVIDERS.has(rawProvider)) {
    provider = normalizeTestProviderName(rawProvider);
    key = (keyArg || '').trim();
  } else {
    key = (providerArg || '').trim();
    provider = detectKeyProvider(key);
  }

  if (!key) {
    return { ok: false, provider, error: 'Missing API key or token' };
  }

  const classes = customProviders || {
    gemini: GeminiProvider,
    openai: OpenAIProvider,
    anthropic: AnthropicProvider,
    claude_pro: ClaudeProProvider,
    chatgpt_subscription: ChatGPTSubscriptionProvider,
    cursor: CursorProvider,
    github_copilot: GitHubCopilotProvider
  };

  const ProviderClass = classes[provider];
  if (!ProviderClass) {
    return { ok: false, provider, error: `Unsupported provider: ${provider}` };
  }

  try {
    const instance = new ProviderClass(key);
    const res = await instance.fetch();
    if (res && Array.isArray(res.groups) && res.groups.length > 0) {
      const result = { ok: true, provider, status: 'OK' };
      if (provider === 'gemini') result.models_count = 3;
      return result;
    }
    return { ok: false, provider, error: 'Invalid key or no access permission' };
  } catch (err) {
    return { ok: false, provider, error: err && err.message ? err.message : 'Test failed' };
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);
  if (args[0] === '--test-gemini' || args[0] === '--test-key') {
    const runTest = args[0] === '--test-gemini'
      ? testProviderKey('gemini', args[1] || '')
      : testProviderKey(args[1] || '', args[2] || '');
    runTest.then(out => {
      console.log(JSON.stringify(out));
    }).catch(err => {
      console.log(JSON.stringify({ ok: false, error: err.message }));
    });
  } else {
    const engine = new UniversalQuotaEngine();
    // `--startup` is passed by the apps on their first run after being opened; `--scan` probes all local AIs
    engine.fetchAll({ startup: args.includes('--startup'), scan: args.includes('--scan') }).then(res => {
      console.log(JSON.stringify(res, null, 2));
    }).catch(err => {
      console.error(JSON.stringify({ error: err.message }));
      process.exit(1);
    });
  }
}

module.exports = {
  UniversalQuotaEngine,
  loadConfig,
  saveConfig,
  stripBom,
  detectKeyProvider,
  testProviderKey
};
