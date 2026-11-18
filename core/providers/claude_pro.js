/**
 * Claude Pro Provider (OAuth / Session via macOS Keychain, ~/.claude/.credentials.json & CLI)
 */
const https = require('https');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { markOutdated } = require('../staleness');

const CLAUDE_SIGNIN_HINT = 'Outdated: sign in to Claude Code again (run "claude auth login --claudeai") or open Claude Desktop';

class ClaudeProProvider {
  constructor(token) {
    this.token = token || this.getTokenFromKeychain() || this.getTokenFromFile();
    this.dedicatedCachePath = path.join(os.homedir(), '.config', 'UniversalAIQuota', 'claude_pro_cache.json');
  }

  findClaudeBinary() {
    const candidates = process.platform === 'win32'
      ? [
          path.join(os.homedir(), '.local', 'bin', 'claude.exe'),
          path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'Programs', 'claude', 'claude.exe')
        ]
      : [
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
        execFileSync(claudeBin, ['auth', 'status'], {
          timeout: 6000,
          stdio: ['ignore', 'ignore', 'ignore'],
          env: {
            ...process.env,
            PATH: (process.env.PATH || '') + path.delimiter + ['/usr/local/bin', '/opt/homebrew/bin', path.join(os.homedir(), '.local', 'bin')].join(path.delimiter)
          }
        });
      }
    } catch (_) {}
  }

  /**
   * Claude Code keeps its OAuth login in ~/.claude/.credentials.json on Windows and Linux (and macOS uses the Keychain).
   * Reading the file lets the app pick up an existing Claude Code login automatically, with nothing to paste.
   * `homeDir` is only for tests.
   */
  getTokenFromFile(homeDir) {
    const file = path.join(homeDir || os.homedir(), '.claude', '.credentials.json');
    const read = () => {
      try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
      } catch (_) {
        return null;
      }
    };
    let parsed = read();
    if (!parsed) return null;

    // Access token expired or about to expire: let the Claude CLI refresh it, then read the file again
    const expiresAt = parsed?.claudeAiOauth?.expiresAt;
    if (expiresAt && Date.now() >= (expiresAt - 60000) && !homeDir) {
      this.attemptCliRefresh();
      parsed = read() || parsed;
    }
    return parsed?.claudeAiOauth?.accessToken || null;
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
    if (diffMs <= 0) return 'Now';
    const diffMins = Math.floor(diffMs / 60000);
    const days = Math.floor(diffMins / (24 * 60));
    const hours = Math.floor((diffMins % (24 * 60)) / 60);
    const mins = diffMins % 60;
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  getWeeklyResetIso() {
    const d = new Date();
    const target = new Date(d);
    const day = d.getUTCDay();
    let daysUntilFriday = (5 - day + 7) % 7;
    target.setUTCDate(target.getUTCDate() + daysUntilFriday);
    target.setUTCHours(8, 0, 0, 0);
    if (target.getTime() <= d.getTime()) {
      target.setUTCDate(target.getUTCDate() + 7);
    }
    return target.toISOString();
  }

  buildPayload(data, isCache = false) {
    const fiveHourUtil = Number(data.five_hour?.utilization ?? 0.0);
    const sevenDayUtil = Number(data.seven_day?.utilization ?? 0.0);

    // Anthropic API returns utilization on a 0-100 percentage scale (e.g., 7.0 for 7% used)
    const rem5h = Math.round(Math.max(0, Math.min(100, 100.0 - fiveHourUtil)));
    const rem7d = Math.round(Math.max(0, Math.min(100, 100.0 - sevenDayUtil)));

    const reset5h = this.formatResetRemaining(data.five_hour?.resets_at) || (rem5h < 100 ? '5h' : '5h');
    const reset7dIso = data.seven_day?.resets_at || this.getWeeklyResetIso();
    const reset7d = this.formatResetRemaining(reset7dIso) || '7d';

    const time5hStr = data.five_hour?.resets_at
      ? ` · Renews at ${new Date(data.five_hour.resets_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`
      : '';
    const time7dStr = reset7dIso
      ? ` · Renews ${new Date(reset7dIso).toLocaleDateString([], { weekday: 'short', hour: 'numeric', minute: '2-digit' })}`
      : '';

    return {
      provider: 'claude_pro',
      account: isCache ? 'Claude Pro (Cache)' : 'Claude Pro (OAuth)',
      plan: 'Claude Pro Plan',
      mode: 'oauth_session',
      groups: [
        {
          name: 'Claude',
          description: isCache ? 'Claude subscription usage limits (local cache)' : 'Claude subscription usage limits',
          provider: 'Claude',
          buckets: [
            {
              id: 'claude-pro-5h',
              name: '5 Hours Limit',
              remaining_pct: rem5h,
              reset_in: reset5h,
              detail: `5h window (${rem5h}% available)${time5hStr}`
            },
            {
              id: 'claude-pro-7d',
              name: 'Weekly Limit',
              remaining_pct: rem7d,
              reset_in: reset7d,
              detail: `Weekly quota (${rem7d}% available)${time7dStr}`
            }
          ]
        }
      ]
    };
  }

  getDesktopUsage(customDir) {
    const defaultFile = process.platform === 'darwin'
      ? path.join(os.homedir(), 'Library', 'Application Support', 'Claude', 'plan-usage-history.json')
      : (process.platform === 'win32'
        ? path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'Claude', 'plan-usage-history.json')
        : path.join(os.homedir(), '.config', 'Claude', 'plan-usage-history.json'));

    const file = customDir ? path.join(customDir, 'plan-usage-history.json') : defaultFile;
    if (!fs.existsSync(file)) return null;

    try {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
      const samples = raw.samples;
      if (!Array.isArray(samples) || samples.length === 0) return null;
      const latest = samples[samples.length - 1];
      if (!latest || typeof latest.t !== 'number' || !latest.u) return null;

      const now = Date.now();
      const age = now - latest.t;

      let windowStart = latest.t;
      for (let i = samples.length - 1; i >= 0; i--) {
        const s = samples[i];
        if (i === 0 || (s.t - samples[i - 1].t > 5 * 3600 * 1000)) {
          windowStart = s.t;
          break;
        }
        if (now - s.t > 5 * 3600 * 1000) {
          break;
        }
        windowStart = s.t;
      }
      const reset5hTarget = windowStart + (5 * 3600 * 1000);
      const is5hExpired = now >= reset5hTarget;

      const util5h = Number(latest.u.fh ?? 0.0);
      const util7d = Number(latest.u.sd ?? 0.0);

      // If the 5-hour rolling window has fully elapsed, the 5-hour quota has naturally renewed to 100%
      const rem5h = is5hExpired ? 100 : Math.round(Math.max(0, Math.min(100, 100.0 - util5h)));
      const rem7d = Math.round(Math.max(0, Math.min(100, 100.0 - util7d)));

      const reset5h = is5hExpired
        ? '5h'
        : (this.formatResetRemaining(new Date(reset5hTarget).toISOString()) || '5h');
      const reset7dIso = this.getWeeklyResetIso();
      const reset7d = this.formatResetRemaining(reset7dIso) || '7d';

      const time5hStr = is5hExpired
        ? ''
        : ` · Renews at ${new Date(reset5hTarget).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`;
      const time7dStr = ` · Renews ${new Date(reset7dIso).toLocaleDateString([], { weekday: 'short', hour: 'numeric', minute: '2-digit' })}`;

      const payload = {
        provider: 'claude_pro',
        account: 'Claude Pro (Desktop)',
        plan: 'Claude Pro Plan',
        mode: 'desktop_session',
        groups: [
          {
            name: 'Claude',
            description: 'Claude subscription limits (Claude Desktop)',
            provider: 'Claude',
            buckets: [
              {
                id: 'claude-pro-5h',
                name: '5 Hours Limit',
                remaining_pct: rem5h,
                reset_in: reset5h,
                detail: `5h window (${rem5h}% available)${time5hStr}`
              },
              {
                id: 'claude-pro-7d',
                name: 'Weekly Limit',
                remaining_pct: rem7d,
                reset_in: reset7d,
                detail: `Weekly quota (${rem7d}% available)${time7dStr}`
              }
            ]
          }
        ]
      };

      // Desktop session data is considered active and valid if recorded within the last 24 hours.
      // (Claude Desktop only appends to plan-usage-history when turns complete, not on an idle timer).
      const DESKTOP_MAX_AGE_MS = 24 * 3600 * 1000;
      if (age > DESKTOP_MAX_AGE_MS) {
        return markOutdated(payload, age, CLAUDE_SIGNIN_HINT);
      }
      return payload;
    } catch (_) {
      return null;
    }
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

    const token = this.token || this.getTokenFromKeychain() || this.getTokenFromFile();

    // Fallback: if no live token, check desktop session first, then cache
    if (!token) {
      const desktop = this.getDesktopUsage();
      if (desktop && !desktop.groups?.[0]?.outdated) {
        return desktop;
      }
      return this.fetchFromCache(desktop);
    }

    return new Promise((resolve) => {
      const fallback = () => {
        const desktop = this.getDesktopUsage();
        if (desktop && !desktop.groups?.[0]?.outdated) {
          resolve(desktop);
          return;
        }
        resolve(this.fetchFromCache(desktop));
      };

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
          fallback();
        });
      });

      req.on('error', () => fallback());
      req.on('timeout', () => {
        req.destroy();
        fallback();
      });
      req.end();
    });
  }

  fetchFromCache(desktopUsage) {
    const desktop = desktopUsage !== undefined ? desktopUsage : this.getDesktopUsage();
    if (desktop && !desktop.groups?.[0]?.outdated) {
      return desktop;
    }

    const candidates = [];

    // 1. Dedicated live cache
    try {
      if (fs.existsSync(this.dedicatedCachePath)) {
        const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8'));
        if (cached?.data) {
          const age = cached.timestamp
            ? (Date.now() - cached.timestamp)
            : (fs.statSync(this.dedicatedCachePath).mtimeMs ? Date.now() - fs.statSync(this.dedicatedCachePath).mtimeMs : Infinity);
          candidates.push({
            age,
            payload: markOutdated(this.buildPayload(cached.data, true), age, CLAUDE_SIGNIN_HINT)
          });
        }
      }
    } catch (_) {}

    // 2. Desktop usage
    if (desktop) {
      const age = desktop.outdated_seconds ? desktop.outdated_seconds * 1000 : 0;
      candidates.push({ age, payload: desktop });
    }

    // 3. VS Code status cache
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

          const vscAge = Date.now() - fs.statSync(cachePath).mtimeMs;
          const payload = {
            provider: 'claude_pro',
            account: 'Claude Pro (Cache)',
            plan: 'Claude Pro Plan',
            mode: 'oauth_session',
            groups: [
              {
                name: 'Claude',
                description: 'Claude subscription usage limits (local cache)',
                provider: 'Claude',
                buckets: [
                  {
                    id: 'claude-pro-5h',
                    name: '5 Hours Limit',
                    remaining_pct: rem5h,
                    reset_in: reset5h,
                    detail: `5h window (${rem5h}% available)`
                  },
                  {
                    id: 'claude-pro-7d',
                    name: 'Weekly Limit',
                    remaining_pct: rem7d,
                    reset_in: reset7d,
                    detail: `Weekly quota (${rem7d}% available)`
                  }
                ]
              }
            ]
          };
          candidates.push({
            age: vscAge,
            payload: markOutdated(payload, vscAge, CLAUDE_SIGNIN_HINT)
          });
        }
      }
    } catch (_) {}

    if (candidates.length === 0) return null;

    // Freshest candidate (smallest age) wins
    candidates.sort((a, b) => a.age - b.age);
    return candidates[0].payload;
  }
}

module.exports = { ClaudeProProvider };
