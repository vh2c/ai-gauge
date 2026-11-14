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
  }

  getTokenFromKeychain() {
    if (process.platform !== 'darwin') return null;
    try {
      const username = process.env.USER || os.userInfo().username;
      const raw = execFileSync('security', [
        'find-generic-password',
        '-a', username,
        '-w',
        '-s', 'Claude Code-credentials'
      ], { encoding: 'utf-8', timeout: 4000 }).trim();
      const parsed = JSON.parse(raw);
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

  async fetch() {
    const token = this.token || this.getTokenFromKeychain();

    // Fallback: if no live token, check cache file ~/.claude/vscode-claude-status-cache.json
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
          'anthropic-beta': 'oauth-2025-04-20'
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
              const fiveHourUtil = data.five_hour?.utilization ?? 0.0;
              const sevenDayUtil = data.seven_day?.utilization ?? 0.0;

              const rem5h = Math.round(Math.max(0, Math.min(100, (1.0 - fiveHourUtil) * 100)));
              const rem7d = Math.round(Math.max(0, Math.min(100, (1.0 - sevenDayUtil) * 100)));

              const reset5h = this.formatResetRemaining(data.five_hour?.resets_at) || (rem5h < 100 ? '5h' : '5h');
              const reset7d = this.formatResetRemaining(data.seven_day?.resets_at) || '7d';

              resolve({
                provider: 'claude_pro',
                account: 'Claude Pro (OAuth)',
                plan: 'Claude Pro Plan',
                mode: 'oauth_session',
                groups: [
                  {
                    name: 'Claude Pro (Sessão)',
                    description: 'Limites de uso da assinatura Claude Pro',
                    provider: 'Claude Pro',
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
              });
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
    try {
      const cachePath = path.join(os.homedir(), '.claude', 'vscode-claude-status-cache.json');
      if (fs.existsSync(cachePath)) {
        const raw = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
        const u = raw.usageData;
        if (u) {
          const rem5h = Math.round(Math.max(0, Math.min(100, (1.0 - (u.utilization5h || 0)) * 100)));
          const rem7d = Math.round(Math.max(0, Math.min(100, (1.0 - (u.utilization7d || 0)) * 100)));
          const reset5h = u.reset5hAt ? this.formatResetRemaining(new Date(u.reset5hAt * 1000).toISOString()) : '5h';
          const reset7d = u.reset7dAt ? this.formatResetRemaining(new Date(u.reset7dAt * 1000).toISOString()) : '7d';

          return {
            provider: 'claude_pro',
            account: 'Claude Pro (Cache)',
            plan: 'Claude Pro Plan',
            mode: 'oauth_session',
            groups: [
              {
                name: 'Claude Pro (Sessão)',
                description: 'Limites de uso da assinatura Claude Pro (Cache local)',
                provider: 'Claude Pro',
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
