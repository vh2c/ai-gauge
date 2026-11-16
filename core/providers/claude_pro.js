/**
 * Claude Pro Provider (OAuth / Session via macOS Keychain & CLI)
 */
const https = require('https');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

class ClaudeProProvider {
  constructor(token) {
    this.token = token || this.getTokenFromKeychain();
    this.dedicatedCachePath = path.join(os.homedir(), '.config', 'UniversalAIQuota', 'claude_pro_cache.json');
  }

  findClaudeBinary() {
    const candidates = [
      path.join(os.homedir(), '.local', 'bin', 'claude'),
      '/usr/local/bin/claude',
      '/opt/homebrew/bin/claude'
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return c;
    }
    return null;
  }

  attemptCliRefresh() {
    try {
      const claudeBin = this.findClaudeBinary();
      if (claudeBin) {
        execFileSync(claudeBin, ['-p', 'ping'], {
          timeout: 6000,
          stdio: ['ignore', 'ignore', 'ignore'],
          env: {
            ...process.env,
            PATH: (process.env.PATH || '') + ':/usr/local/bin:/opt/homebrew/bin:' + path.join(os.homedir(), '.local', 'bin')
          }
        });
      }
    } catch (_) {}
  }

  getTokenFromKeychain() {
    if (process.platform !== 'darwin') return null;
    try {
      const username = process.env.USER || os.userInfo().username;
      let raw = execFileSync('security', [
        'find-generic-password',
        '-a', username,
        '-w',
        '-s', 'Claude Code-credentials'
      ], { encoding: 'utf-8', timeout: 4000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
      let parsed = JSON.parse(raw);

      // Check if access token is expired or close to expiration (within 60s)
      const expiresAt = parsed?.claudeAiOauth?.expiresAt;
      if (expiresAt && Date.now() >= (expiresAt - 60000)) {
        this.attemptCliRefresh();
        try {
          raw = execFileSync('security', [
            'find-generic-password',
            '-a', username,
            '-w',
            '-s', 'Claude Code-credentials'
          ], { encoding: 'utf-8', timeout: 4000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
          parsed = JSON.parse(raw);
        } catch (_) {}
      }

      return parsed?.claudeAiOauth?.accessToken || null;
    } catch (_) {
      return null;
    }
  }

  formatResetRemaining(isoString) {
    if (!isoString) return null;
    const target = new Date(isoString).getTime();
    const now = Date.now();
    const diffMs = target - now;
    if (diffMs <= 0) return 'Agora';
    const diffMins = Math.floor(diffMs / 60000);
    const days = Math.floor(diffMins / (24 * 60));
    const hours = Math.floor((diffMins % (24 * 60)) / 60);
    const mins = diffMins % 60;
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  buildPayload(data, isCache = false) {
    const fiveHourUtil = Number(data.five_hour?.utilization ?? 0.0);
    const sevenDayUtil = Number(data.seven_day?.utilization ?? 0.0);

    // Anthropic API returns utilization on a 0-100 percentage scale (e.g., 7.0 for 7% used)
    const rem5h = Math.round(Math.max(0, Math.min(100, 100.0 - fiveHourUtil)));
    const rem7d = Math.round(Math.max(0, Math.min(100, 100.0 - sevenDayUtil)));

    const reset5h = this.formatResetRemaining(data.five_hour?.resets_at) || (rem5h < 100 ? '5h' : '5h');
    const reset7d = this.formatResetRemaining(data.seven_day?.resets_at) || '7d';

    return {
      provider: 'claude_pro',
      account: isCache ? 'Claude Pro (Cache)' : 'Claude Pro (OAuth)',
      plan: 'Claude Pro Plan',
      mode: 'oauth_session',
      groups: [
        {
          name: 'Claude',
          description: isCache ? 'Limites de uso da assinatura Claude (Cache local)' : 'Limites de uso da assinatura Claude',
          provider: 'Claude',
          buckets: [
            {
              id: 'claude-pro-5h',
              name: '5 Hours Limit',
              remaining_pct: rem5h,
              reset_in: reset5h,
              detail: `Janela de 5h (${rem5h}% disponível)`
            },
            {
              id: 'claude-pro-7d',
              name: 'Weekly Limit',
              remaining_pct: rem7d,
              reset_in: reset7d,
              detail: `Cota semanal (${rem7d}% disponível)`
            }
          ]
        }
      ]
    };
  }

  async fetch() {
    // Check if we have a very fresh cache (< 45s) to avoid triggering Anthropic 429 rate limit
    try {
      if (fs.existsSync(this.dedicatedCachePath)) {
        const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8'));
        if (cached?.timestamp && (Date.now() - cached.timestamp < 45000) && cached.data) {
          return this.buildPayload(cached.data, false);
        }
      }
    } catch (_) {}

    const token = this.token || this.getTokenFromKeychain();

    // Fallback: if no live token, check cache
    if (!token) {
      return this.fetchFromCache();
    }

    return new Promise((resolve) => {
      const options = {
        hostname: 'api.anthropic.com',
        path: '/api/oauth/usage',
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'anthropic-beta': 'oauth-2025-04-20',
          'User-Agent': 'Claude-Code/2.1'
        },
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
          resolve(this.fetchFromCache());
        });
      });

      req.on('error', () => resolve(this.fetchFromCache()));
      req.on('timeout', () => {
        req.destroy();
        resolve(this.fetchFromCache());
      });
      req.end();
    });
  }

  fetchFromCache() {
    // 1. Try dedicated live cache first
    try {
      if (fs.existsSync(this.dedicatedCachePath)) {
        const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8'));
        if (cached?.data) {
          return this.buildPayload(cached.data, true);
        }
      }
    } catch (_) {}

    // 2. Fallback to VS Code status cache
    try {
      const cachePath = path.join(os.homedir(), '.claude', 'vscode-claude-status-cache.json');
      if (fs.existsSync(cachePath)) {
        const raw = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
        const u = raw.usageData;
        if (u) {
          const util5h = Number(u.utilization5h || 0);
          const util7d = Number(u.utilization7d || 0);
          // Scale to percentage
          const p5h = util5h > 1 ? util5h : (util5h * 100);
          const p7d = util7d > 1 ? util7d : (util7d * 100);

          const rem5h = Math.round(Math.max(0, Math.min(100, 100.0 - p5h)));
          const rem7d = Math.round(Math.max(0, Math.min(100, 100.0 - p7d)));
          const reset5h = u.reset5hAt ? this.formatResetRemaining(new Date(u.reset5hAt * 1000).toISOString()) : '5h';
          const reset7d = u.reset7dAt ? this.formatResetRemaining(new Date(u.reset7dAt * 1000).toISOString()) : '7d';

          return {
            provider: 'claude_pro',
            account: 'Claude Pro (Cache)',
            plan: 'Claude Pro Plan',
            mode: 'oauth_session',
            groups: [
              {
                name: 'Claude',
                description: 'Limites de uso da assinatura Claude (Cache local)',
                provider: 'Claude',
                buckets: [
                  {
                    id: 'claude-pro-5h',
                    name: '5 Hours Limit',
                    remaining_pct: rem5h,
                    reset_in: reset5h,
                    detail: `Janela de 5h (${rem5h}% disponível)`
                  },
                  {
                    id: 'claude-pro-7d',
                    name: 'Weekly Limit',
                    remaining_pct: rem7d,
                    reset_in: reset7d,
                    detail: `Cota semanal (${rem7d}% disponível)`
                  }
                ]
              }
            ]
          };
        }
      }
    } catch (_) {}
    return null;
  }
}

module.exports = { ClaudeProProvider };
