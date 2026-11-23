/**
 * Claude Pro Provider (OAuth / Session via macOS Keychain, ~/.claude/.credentials.json & CLI)
 */
const https = require('https');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { markOutdated } = require('../staleness');
const { readBackoffState, recordBackoff429, clearBackoffState } = require('../last_good');

const CLAUDE_SIGNIN_HINT = 'Outdated: sign in to Claude Code again (run "claude auth login --claudeai") or open Claude Desktop';

class ClaudeProProvider {
  constructor(token) {
    this._explicitToken = Boolean(token);
    this._ignoreCachedDesktopToken = false;
    this.tokenCachePath = path.join(os.homedir(), '.config', 'UniversalAIQuota', 'claude_pro_token_cache.json');
    this.token = token || null;
    this.dedicatedCachePath = path.join(os.homedir(), '.config', 'UniversalAIQuota', 'claude_pro_cache.json');
    this.backoffPath = path.join(os.homedir(), '.config', 'UniversalAIQuota', 'claude_pro_backoff.json');
  }

  /** After a 429 from Anthropic we stop calling the usage endpoint until this time. */
  getBackoffUntil() {
    return readBackoffState(this.backoffPath).until;
  }

  setBackoff(retryAfterSeconds = 0) {
    return recordBackoff429(this.backoffPath, retryAfterSeconds);
  }

  clearBackoff() {
    clearBackoffState(this.backoffPath);
  }

  getCachedToken() {
    if (this._ignoreCachedDesktopToken) return null;
    try {
      if (!fs.existsSync(this.tokenCachePath)) return null;
      const cached = JSON.parse(fs.readFileSync(this.tokenCachePath, 'utf8').replace(/^\uFEFF/, ''));
      if (cached && cached.token && (!cached.expiresAt || cached.expiresAt > (Date.now() + 60000))) {
        return cached.token;
      }
    } catch (_) {}
    return null;
  }

  saveCachedToken(token, expiresAt = null) {
    if (!token) return;
    try {
      const dir = path.dirname(this.tokenCachePath);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(
        this.tokenCachePath,
        JSON.stringify({ token, expiresAt, updatedAt: Date.now() }),
        { encoding: 'utf8', mode: 0o600 }
      );
    } catch (_) {}
  }

  resolveToken() {
    return (
      this.token ||
      this.getTokenFromFile() ||
      this.getCachedToken() ||
      this.getTokenFromDesktopConfig() ||
      this.getTokenFromKeychain()
    );
  }

  /**
   * Last REAL numbers from the API (dedicated cache), used when the live call fails (rate limit, timeout, expired
   * login). Real-but-a-bit-old is better than a guess: the Claude Desktop estimate assumes 100% once its 5h window
   * "expired", which is wrong whenever Claude Code was used in between. Returns null when there is no real cache.
   *  - older than 30 min -> everything is flagged Outdated ("--%")
   *  - the cached 5h window already ended -> that bucket is unknown (a new window may have started): Outdated too,
   *    never 100%.
   */
  fetchFromRealCache() {
    try {
      if (!fs.existsSync(this.dedicatedCachePath)) return null;
      const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8').replace(/^\uFEFF/, ''));
      if (!cached || !cached.data) return null;
      const age = cached.timestamp ? (Date.now() - cached.timestamp) : Infinity;
      const payload = markOutdated(this.buildPayload(cached.data, true), age, CLAUDE_SIGNIN_HINT);
      const resets5h = cached.data.five_hour?.resets_at ? new Date(cached.data.five_hour.resets_at).getTime() : null;
      if (resets5h !== null && resets5h <= Date.now()) {
        const b5 = payload.groups?.[0]?.buckets?.find(b => b.id === 'claude-pro-5h');
        if (b5) {
          b5.reset_in = 'Outdated';
          b5.outdated = true;
          b5.detail = 'Waiting for Claude to answer…';
        }
      }
      return payload;
    } catch (_) {
      return null;
    }
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
        return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
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

      const tok = parsed?.claudeAiOauth?.accessToken || null;
      if (tok) {
        this.saveCachedToken(tok, parsed?.claudeAiOauth?.expiresAt || null);
      }
      return tok;
    } catch (_) {
      return null;
    }
  }

  /**
   * Pick the best OAuth token from Claude Desktop's decrypted tokenCache object,
   * preferring unexpired entries whose key includes the `user:profile` scope
   * (required by /api/oauth/usage) and highest expiration timestamp.
   */
  extractBestTokenFromCacheObj(parsedObj) {
    if (!parsedObj || typeof parsedObj !== 'object') return null;
    const now = Date.now();
    const candidates = [];

    for (const [key, entry] of Object.entries(parsedObj)) {
      if (!entry || typeof entry !== 'object') continue;
      const rawToken = entry.token || entry.accessToken;
      if (typeof rawToken !== 'string' || !rawToken.trim()) continue;

      const expiresAt = typeof entry.expiresAt === 'number' ? entry.expiresAt : null;
      const isValid = expiresAt === null ? true : expiresAt > (now + 60000);
      if (!isValid) continue;

      candidates.push({
        token: rawToken.trim(),
        expiresAt,
        hasProfile: key.includes('user:profile')
      });
    }

    if (candidates.length === 0) return null;

    candidates.sort((a, b) => {
      if (a.hasProfile !== b.hasProfile) return a.hasProfile ? -1 : 1;
      return (b.expiresAt ?? 0) - (a.expiresAt ?? 0);
    });

    return {
      token: candidates[0].token,
      expiresAt: candidates[0].expiresAt
    };
  }

  getDesktopConfigDir(customDir) {
    if (customDir) return customDir;
    if (process.platform === 'darwin') {
      return path.join(os.homedir(), 'Library', 'Application Support', 'Claude');
    }
    if (process.platform === 'win32') {
      return path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'Claude');
    }
    return path.join(os.homedir(), '.config', 'Claude');
  }

  decryptSafeStorageValue(encryptedBase64, desktopDir) {
    if (typeof encryptedBase64 !== 'string' || !encryptedBase64) return null;
    try {
      const buf = Buffer.from(encryptedBase64, 'base64');
      if (buf.length < 4) return null;
      const prefix = buf.subarray(0, 3).toString('utf8');
      if (prefix !== 'v10') return null;

      if (process.platform === 'darwin') {
        const pass = execFileSync('security', [
          'find-generic-password',
          '-w',
          '-s', 'Claude Safe Storage'
        ], { encoding: 'utf8', timeout: 4000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
        if (!pass) return null;
        const key = crypto.pbkdf2Sync(pass, 'saltysalt', 1003, 16, 'sha1');
        const iv = Buffer.alloc(16, 0x20);
        const decipher = crypto.createDecipheriv('aes-128-cbc', key, iv);
        return Buffer.concat([decipher.update(buf.subarray(3)), decipher.final()]).toString('utf8');
      }

      if (process.platform === 'win32') {
        if (buf.length <= 31) return null;
        const localStatePath = path.join(desktopDir, 'Local State');
        if (!fs.existsSync(localStatePath)) return null;
        const localState = JSON.parse(fs.readFileSync(localStatePath, 'utf8').replace(/^\uFEFF/, ''));
        const encKeyB64 = localState?.os_crypt?.encrypted_key;
        if (!encKeyB64) return null;
        const keyBuf = Buffer.from(encKeyB64, 'base64');
        if (keyBuf.length <= 5 || keyBuf.subarray(0, 5).toString('utf8') !== 'DPAPI') return null;

        const protectedB64 = keyBuf.subarray(5).toString('base64');
        const psScript = [
          'Add-Type -AssemblyName System.Security;',
          '$bytes = [Convert]::FromBase64String($env:CLAUDE_DPAPI_BLOB);',
          '$plain = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser);',
          '[Convert]::ToBase64String($plain)'
        ].join(' ');
        const masterKeyB64 = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', psScript], {
          encoding: 'utf8',
          timeout: 5000,
          stdio: ['ignore', 'pipe', 'ignore'],
          env: { ...process.env, CLAUDE_DPAPI_BLOB: protectedB64 }
        }).trim();
        const masterKey = Buffer.from(masterKeyB64, 'base64');
        if (masterKey.length !== 32) return null;

        const nonce = buf.subarray(3, 15);
        const tag = buf.subarray(buf.length - 16);
        const ciphertext = buf.subarray(15, buf.length - 16);
        const decipher = crypto.createDecipheriv('aes-256-gcm', masterKey, nonce);
        decipher.setAuthTag(tag);
        return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
      }

      // Linux Electron safeStorage (v10 uses fixed 'peanuts' PBKDF2 key)
      const key = crypto.pbkdf2Sync('peanuts', 'saltysalt', 1, 16, 'sha1');
      const iv = Buffer.alloc(16, 0x20);
      const decipher = crypto.createDecipheriv('aes-128-cbc', key, iv);
      return Buffer.concat([decipher.update(buf.subarray(3)), decipher.final()]).toString('utf8');
    } catch (_) {
      return null;
    }
  }

  getTokenFromDesktopConfig(customDir) {
    if (!customDir && !this._ignoreCachedDesktopToken) {
      try {
        if (fs.existsSync(this.tokenCachePath)) {
          const cached = JSON.parse(fs.readFileSync(this.tokenCachePath, 'utf8').replace(/^\uFEFF/, ''));
          if (cached?.token && (!cached.expiresAt || cached.expiresAt > (Date.now() + 60000))) {
            return cached.token;
          }
        }
      } catch (_) {}
    }

    try {
      const desktopDir = this.getDesktopConfigDir(customDir);
      const cfgPath = path.join(desktopDir, 'config.json');
      if (!fs.existsSync(cfgPath)) return null;

      const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8').replace(/^\uFEFF/, ''));
      const combined = {};

      for (const cacheKey of ['oauth:tokenCache', 'oauth:tokenCacheV2']) {
        const rawEnc = cfg?.[cacheKey];
        if (!rawEnc) continue;
        const dec = this.decryptSafeStorageValue(rawEnc, desktopDir);
        if (!dec) continue;
        try {
          const parsed = JSON.parse(dec);
          if (parsed && typeof parsed === 'object') {
            Object.assign(combined, parsed);
          }
        } catch (_) {}
      }

      const best = this.extractBestTokenFromCacheObj(combined);
      if (!best || !best.token) return null;

      if (!customDir) {
        try {
          const dir = path.dirname(this.tokenCachePath);
          if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
          fs.writeFileSync(
            this.tokenCachePath,
            JSON.stringify({ token: best.token, expiresAt: best.expiresAt, updatedAt: Date.now() }),
            { encoding: 'utf8', mode: 0o600 }
          );
        } catch (_) {}
      }

      return best.token;
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
              reset_time: data.five_hour?.resets_at || null,
              detail: `5h window (${rem5h}% available)${time5hStr}`
            },
            {
              id: 'claude-pro-7d',
              name: 'Weekly Limit',
              remaining_pct: rem7d,
              reset_in: reset7d,
              reset_time: reset7dIso,
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
      const raw = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
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
        const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8').replace(/^\uFEFF/, ''));
        if (cached?.timestamp && (Date.now() - cached.timestamp < 45000) && cached.data) {
          return this.buildPayload(cached.data, false);
        }
      }
    } catch (_) {}

    const fallback = () => {
      const desktop = this.getDesktopUsage();
      if (desktop && !desktop.groups?.[0]?.outdated) {
        return desktop;
      }
      return this.fetchFromCache(desktop);
    };

    // The usage endpoint is rate limited (a burst of calls ends in 429). While we are paused, do not call it
    // (nor touch Keychain): show the last real numbers instead of hammering the API.
    if (Date.now() < this.getBackoffUntil()) {
      return this.fetchFromRealCache() || fallback();
    }

    const token = this.resolveToken();

    // Fallback: if no live token, check desktop session first, then cache
    if (!token) {
      return fallback();
    }

    const requestUsage = (bearerToken) => new Promise((resolve) => {
      const options = {
        hostname: 'api.anthropic.com',
        path: '/api/oauth/usage',
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${bearerToken}`,
          'anthropic-beta': 'oauth-2025-04-20',
          'User-Agent': 'Claude-Code/2.1'
        },
        timeout: 4500
      };

      const req = https.request(options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => resolve({ statusCode: res.statusCode || 0, body, retryAfter: Number(res.headers && res.headers['retry-after']) || 0 }));
      });

      req.on('error', () => resolve({ statusCode: 0, body: '' }));
      req.on('timeout', () => {
        req.destroy();
        resolve({ statusCode: 0, body: '' });
      });
      req.end();
    });

    let res = await requestUsage(token);

    if (res.statusCode === 401 || res.statusCode === 403) {
      try { fs.rmSync(this.tokenCachePath, { force: true }); } catch (_) {}
      this._ignoreCachedDesktopToken = true;

      if (!this._explicitToken) {
        let freshToken = this.getTokenFromFile() || this.getTokenFromDesktopConfig();
        if (!freshToken || freshToken === token) {
          freshToken = this.getTokenFromKeychain();
        }
        if (freshToken && freshToken !== token) {
          this.token = freshToken;
          res = await requestUsage(freshToken);
        }
      }
    }

    if (res.statusCode === 429) {
      // Exponential persisted backoff (60s -> 15m) honouring Retry-After when supplied
      this.setBackoff(res.retryAfter || 0);
    }

    if (res.statusCode === 200) {
      try {
        const data = JSON.parse(res.body);
        this.clearBackoff();
        // Save to dedicated cache
        try {
          const dir = path.dirname(this.dedicatedCachePath);
          if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
          fs.writeFileSync(this.dedicatedCachePath, JSON.stringify({ timestamp: Date.now(), data }), 'utf8');
        } catch (_) {}

        return this.buildPayload(data, false);
      } catch (_) {}
    }

    // Live call failed (429, timeout, expired login): last real numbers first, the Desktop estimate only if there
    // is nothing real at all.
    return this.fetchFromRealCache() || fallback();
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
        const cached = JSON.parse(fs.readFileSync(this.dedicatedCachePath, 'utf8').replace(/^\uFEFF/, ''));
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
        const raw = JSON.parse(fs.readFileSync(cachePath, 'utf8').replace(/^\uFEFF/, ''));
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
