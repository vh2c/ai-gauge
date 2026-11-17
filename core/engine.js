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
const { sendHeartbeat } = require('./telemetry');
const { checkForUpdates, CURRENT_VERSION } = require('./updater');

const CONFIG_DIR = path.join(os.homedir(), '.config', 'UniversalAIQuota');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

let _lastValidConfig = null;

function loadConfig() {
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
      _lastValidConfig = parsed;
      return parsed;
    } catch (e) {
      // Security: If config exists on disk but failed to parse, reuse last known valid config.
      // NEVER silently re-enable disabled sessions!
      if (_lastValidConfig) {
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

class UniversalQuotaEngine {
  constructor() {
    this.config = loadConfig();
  }

  async fetchAll() {
    // Send anonymous telemetry update check (strictly throttled to max once per 6h, no provider tracking)
    try {
      sendHeartbeat();
    } catch (_) {}

    const providers = [];
    const pCfg = this.config.providers || {};

    // Security: Only probe providers explicitly enabled by user
    if (pCfg.antigravity?.enabled === true) {
      providers.push(new AntigravityProvider().fetch());
    }
    if (pCfg.claude_pro?.enabled === true) {
      providers.push(new ClaudeProProvider(pCfg.claude_pro?.token).fetch());
    }
    if (pCfg.chatgpt_subscription?.enabled === true) {
      providers.push(new ChatGPTSubscriptionProvider(pCfg.chatgpt_subscription?.token).fetch());
    }
    if (pCfg.cursor?.enabled === true) {
      providers.push(new CursorProvider(pCfg.cursor?.token).fetch());
    }
    if (pCfg.github_copilot?.enabled === true) {
      providers.push(new GitHubCopilotProvider(pCfg.github_copilot?.token).fetch());
    }
    if (pCfg.gemini?.enabled === true && pCfg.gemini?.api_key) {
      providers.push(new GeminiProvider(pCfg.gemini.api_key).fetch());
    }
    if (pCfg.openai?.enabled === true && pCfg.openai?.api_key) {
      providers.push(new OpenAIProvider(pCfg.openai.api_key).fetch());
    }
    if (pCfg.anthropic?.enabled === true && pCfg.anthropic?.api_key) {
      providers.push(new AnthropicProvider(pCfg.anthropic.api_key).fetch());
    }

    const results = await Promise.allSettled(providers);
    const valid = results.filter(r => r.status === 'fulfilled' && r.value !== null).map(r => r.value);

    let updateData = null;
    try {
      updateData = await checkForUpdates();
    } catch (_) {}

    if (valid.length === 0) {
      return {
        needs_setup: true,
        account: 'Nenhum Provedor Configurado',
        plan: 'Configurar',
        providers_count: 0,
        groups: [],
        version: CURRENT_VERSION,
        tier: updateData?.tier || 'free',
        update: updateData || { current_version: CURRENT_VERSION, update_available: false },
        announcement: updateData?.announcement || null,
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
      groups: allGroups,
      version: CURRENT_VERSION,
      tier: updateData?.tier || 'free',
      update: updateData || { current_version: CURRENT_VERSION, update_available: false },
      announcement: updateData?.announcement || null,
      updated_at: new Date().toLocaleTimeString('pt-BR')
    };
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);
  if (args[0] === '--test-gemini' || args[0] === '--test-key') {
    const key = args[1] || '';
    new GeminiProvider(key).fetch().then(res => {
      if (res && res.groups && res.groups.length > 0) {
        console.log(JSON.stringify({ ok: true, provider: 'gemini', models_count: 3 }));
      } else {
        console.log(JSON.stringify({ ok: false, error: 'Chave inválida ou sem permissão de acesso' }));
      }
    }).catch(err => {
      console.log(JSON.stringify({ ok: false, error: err.message }));
    });
  } else {
    const engine = new UniversalQuotaEngine();
    engine.fetchAll().then(res => {
      console.log(JSON.stringify(res, null, 2));
    }).catch(err => {
      console.error(JSON.stringify({ error: err.message }));
      process.exit(1);
    });
  }
}

module.exports = { UniversalQuotaEngine };
