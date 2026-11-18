/**
 * ChatGPT Subscription Provider (ChatGPT Plus / Pro / Free / Team Web Session & OAuth)
 * Analogous to Claude Pro: monitors 3-hour GPT-4o window and weekly o1 limits
 * Developed by VH2C • https://vh2c.com.br
 */
const https = require('https');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

class ChatGPTSubscriptionProvider {
  constructor(token) {
    this.token = token;
    this.dedicatedCachePath = path.join(os.homedir(), '.config', 'UniversalAIQuota', 'chatgpt_cache.json');
  }

  getCredentials() {
    if (this.token) {
      return { token: this.token, accountId: null };
    }

    // 1. Check native ChatGPT Mac desktop app storage (~/.codex/auth.json)
    try {
      const codexAuthPath = path.join(os.homedir(), '.codex', 'auth.json');
      if (fs.existsSync(codexAuthPath)) {
        const parsed = JSON.parse(fs.readFileSync(codexAuthPath, 'utf8'));
        const token = parsed?.tokens?.access_token;
        const accountId = parsed?.tokens?.account_id;
        if (token) {
          return { token, accountId };
        }
      }
    } catch (_) {}

    // 2. Check environment variables
    const envToken = process.env.CHATGPT_ACCESS_TOKEN ||
                     process.env.CHATGPT_SESSION_TOKEN ||
                     process.env.OPENAI_SESSION_TOKEN;
    if (envToken) {
      return { token: envToken, accountId: null };
    }

    // 3. Fallback: Keychain
    const kcToken = this.getTokenFromKeychain();
    if (kcToken) {
      return { token: kcToken, accountId: null };
    }

    return { token: null, accountId: null };
  }

  getTokenFromKeychain() {
    if (process.platform !== 'darwin') return null;
    const keychainServices = ['ChatGPT-credentials', 'chatgpt-credentials', 'ChatGPT', 'Codex-credentials'];
    const username = process.env.USER || os.userInfo().username;

    for (const service of keychainServices) {
      try {
        const raw = execFileSync('security', [
          'find-generic-password',
          '-a', username,
          '-w',
          '-s', service
        ], { encoding: 'utf-8', timeout: 3000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
        if (raw) {
          try {
            const parsed = JSON.parse(raw);
            const token = parsed?.accessToken || parsed?.access_token || parsed?.sessionToken || parsed?.token;
            if (token) return token;
          } catch (_) {
            if (raw.startsWith('ey') || raw.length > 20) return raw;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  formatResetRemaining(targetTime) {
    if (!targetTime) return null;
    let target = 0;
    if (typeof targetTime === 'number') {
      target = targetTime > 1e11 ? targetTime : targetTime * 1000;
    } else {
      target = new Date(targetTime).getTime();
    }
    const now = Date.now();
    const diffMs = target - now;
    if (diffMs <= 0) return 'Now';
    const diffMins = Math.floor(diffMs / 60000);
    const days = Math.floor(diffMins / (24 * 60));
    const hours = Math.floor((diffMins % (24 * 60)) / 60);
    const mins = diffMins % 60;
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  calcRemainingPct(util, usedPct) {
    if (usedPct !== undefined && usedPct !== null) {
      const u = Number(usedPct);
      return Math.round(Math.max(0, Math.min(100, 100.0 - u)));
    }
    if (util !== undefined && util !== null) {
      const u = Number(util);
      if (u > 1.0) {
        return Math.round(Math.max(0, Math.min(100, 100.0 - u)));
      }
      return Math.round(Math.max(0, Math.min(100, (1.0 - u) * 100.0)));
    }
    return 100;
  }

  buildPayload(data, isCache = false) {
    const planType = (data.plan_type || 'plus').toLowerCase();
    const planTitle = planType === 'free' ? 'ChatGPT Free' :
                      (planType === 'pro' ? 'ChatGPT Pro' : 'ChatGPT Plus');
    const accountEmail = data.email || data.account_email || 'ChatGPT';

    const pw = data.rate_limit?.primary_window;
    const gpt4oUsage = data.usage?.['gpt-4o'] || data.model_usage?.['gpt-4o'] || data.gpt_4o;
    const o1Usage = data.usage?.['o1'] || data.model_usage?.['o1'] || data.o1;

    let rem4o = 100;
    let reset4o = '3h';
    if (gpt4oUsage) {
      rem4o = this.calcRemainingPct(gpt4oUsage.utilization, gpt4oUsage.used_percent);
      reset4o = this.formatResetRemaining(gpt4oUsage.resets_at) || '3h';
    } else if (pw) {
      rem4o = this.calcRemainingPct(null, pw.used_percent);
      reset4o = this.formatResetRemaining(pw.reset_at) || (pw.reset_after_seconds ? `${Math.round(pw.reset_after_seconds / 3600)}h` : '3h');
    }

    let remO1 = 100;
    let resetO1 = '7d';
    if (o1Usage) {
      remO1 = this.calcRemainingPct(o1Usage.utilization, o1Usage.used_percent);
      resetO1 = this.formatResetRemaining(o1Usage.resets_at) || '7d';
    } else if (data.rate_limit?.secondary_window) {
      const sw = data.rate_limit.secondary_window;
      remO1 = this.calcRemainingPct(null, sw.used_percent);
      resetO1 = this.formatResetRemaining(sw.reset_at) || '7d';
    }

    return {
      provider: 'chatgpt_subscription',
      account: accountEmail + (isCache ? ' (Cache)' : ''),
      plan: planTitle,
      mode: 'web_session',
      groups: [
        {
          name: 'ChatGPT',
          description: isCache ? 'Limites de uso da assinatura ChatGPT (Cache local)' : 'Limites de uso da assinatura ChatGPT',
          provider: 'ChatGPT',
          buckets: [
            {
              id: 'chatgpt-4o-3h',
              name: 'GPT-4o (3h)',
              remaining_pct: rem4o,
              reset_in: reset4o,
              detail: planType === 'free' ? `Active quota (${rem4o}% available)` : `3h window (${rem4o}% available)`
            },
            {
              id: 'chatgpt-o1-weekly',
              name: 'o1 Reasoning (Weekly)',
              remaining_pct: remO1,
              reset_in: resetO1,
              detail: `Weekly o1 quota (${remO1}% available)`
            }
          ]
        }
      ]
    };
  }

  async fetch() {
    // Check if we have a fresh cache (< 45s) to reduce polling overhead
    try {
      if (fs.existsSync(this.dedicatedCachePath)) {
        const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8'));
        if (cached?.timestamp && (Date.now() - cached.timestamp < 45000) && cached.data) {
          return this.buildPayload(cached.data, false);
        }
      }
    } catch (_) {}

    const { token, accountId } = this.getCredentials();

    if (!token) {
      return this.fetchFromCache();
    }

    return new Promise((resolve) => {
      const headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'application/json'
      };

      if (accountId) {
        headers['ChatGPT-Account-ID'] = accountId;
      }

      const options = {
        hostname: 'chatgpt.com',
        path: '/backend-api/wham/usage',
        method: 'GET',
        headers,
        timeout: 4500
      };

      const req = https.request(options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          if (res.statusCode === 200) {
            try {
              const data = JSON.parse(body);
              // Save to dedicated cache
              try {
                const dir = path.dirname(this.dedicatedCachePath);
                if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
                fs.writeFileSync(this.dedicatedCachePath, JSON.stringify({ timestamp: Date.now(), data }), 'utf8');
              } catch (_) {}

              resolve(this.buildPayload(data, false));
              return;
            } catch (_) {}
          }

          // Fallback to cache or synthetic active session representation
          resolve(this.fetchFromCache(token));
        });
      });

      req.on('error', () => resolve(this.fetchFromCache(token)));
      req.on('timeout', () => {
        req.destroy();
        resolve(this.fetchFromCache(token));
      });
      req.end();
    });
  }

  fetchFromCache(activeToken = null) {
    // 1. Check dedicated cache first
    try {
      if (fs.existsSync(this.dedicatedCachePath)) {
        const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8'));
        if (cached?.data) {
          return this.buildPayload(cached.data, true);
        }
      }
    } catch (_) {}

    // 2. Check fallback candidates
    try {
      const candidates = [
        path.join(os.homedir(), '.chatgpt', 'status-cache.json'),
        path.join(os.homedir(), '.codex', 'session.json')
      ];

      for (const cachePath of candidates) {
        if (fs.existsSync(cachePath)) {
          const raw = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
          const rem4o = raw.rem_4o ?? raw.remaining_pct_4o ?? 100;
          const remO1 = raw.rem_o1 ?? raw.remaining_pct_o1 ?? 100;
          const reset4o = raw.reset_4o || '3h';
          const resetO1 = raw.reset_o1 || '7d';

          return {
            provider: 'chatgpt_subscription',
            account: raw.account || 'ChatGPT Plus / Pro (Cache)',
            plan: raw.plan || 'ChatGPT Plus',
            mode: 'web_session',
            groups: [
              {
                name: 'ChatGPT',
                description: 'Limites de uso da assinatura ChatGPT (Cache local)',
                provider: 'ChatGPT',
                buckets: [
                  {
                    id: 'chatgpt-4o-3h',
                    name: 'GPT-4o (3h)',
                    remaining_pct: rem4o,
                    reset_in: reset4o,
                    detail: `3h window (${rem4o}% available)`
                  },
                  {
                    id: 'chatgpt-o1-weekly',
                    name: 'o1 Reasoning (Weekly)',
                    remaining_pct: remO1,
                    reset_in: resetO1,
                    detail: `Weekly o1 quota (${remO1}% available)`
                  }
                ]
              }
            ]
          };
        }
      }
    } catch (_) {}

    // If an active token was supplied manually but no live API / cache returned:
    if (activeToken) {
      return {
        provider: 'chatgpt_subscription',
        account: 'ChatGPT Plus / Pro',
        plan: 'ChatGPT Subscription',
        mode: 'web_session',
        groups: [
          {
            name: 'ChatGPT',
            description: 'Limites de uso da assinatura ChatGPT',
            provider: 'ChatGPT',
            buckets: [
              {
                id: 'chatgpt-4o-3h',
                name: 'GPT-4o (3h)',
                remaining_pct: 100,
                reset_in: '3h',
                detail: '3h window (100% available)'
              },
              {
                id: 'chatgpt-o1-weekly',
                name: 'o1 Reasoning (Weekly)',
                remaining_pct: 100,
                reset_in: '7d',
                detail: 'Weekly o1 quota (100% available)'
              }
            ]
          }
        ]
      };
    }

    return null;
  }
}

module.exports = { ChatGPTSubscriptionProvider };
