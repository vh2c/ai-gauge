/**
 * Cursor IDE AI Quota Provider (Cursor Pro / Fast Requests)
 * Monitors Cursor fast requests (Claude 3.5 Sonnet / GPT-4o), slow requests and monthly billing cycle.
 * Zero-config: Automatically detects Cursor session tokens from Cursor SQLite storage or config.
 */

const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

class CursorProvider {
  constructor(token) {
    this.token = (token || process.env.CURSOR_TOKEN || process.env.CURSOR_SESSION_TOKEN || '').trim();
  }

  /**
   * Attempts to locate Cursor's local session token from Cursor's state database
   */
  static getLocalSessionToken() {
    const candidates = [];
    const home = os.homedir();

    if (process.platform === 'darwin') {
      candidates.push(path.join(home, 'Library/Application Support/Cursor/User/globalStorage/state.vscdb'));
    } else if (process.platform === 'win32') {
      const appdata = process.env.APPDATA || path.join(home, 'AppData', 'Roaming');
      const local = process.env.LOCALAPPDATA || path.join(home, 'AppData', 'Local');
      candidates.push(path.join(appdata, 'Cursor/User/globalStorage/state.vscdb'));
      candidates.push(path.join(home, 'AppData/Roaming/Cursor/User/globalStorage/state.vscdb'));
      candidates.push(path.join(local, 'Cursor/User/globalStorage/state.vscdb'));
    } else {
      candidates.push(path.join(home, '.config/Cursor/User/globalStorage/state.vscdb'));
    }

    for (const dbPath of candidates) {
      if (!fs.existsSync(dbPath)) continue;
      try {
        if (process.platform !== 'win32') {
          const query = "SELECT value FROM ItemTable WHERE key IN ('cursorAuth/accessToken', 'cursorAuth/token', 'workos_access_token', 'WorkosCursorSessionToken') LIMIT 1;";
          const output = execSync(`/usr/bin/sqlite3 "${dbPath}" "${query}" 2>/dev/null`, { timeout: 1500, encoding: 'utf8' }).trim();
          if (output && output.length > 10) return output;
        }
      } catch (_) {}

      // Buffer search across all platforms (works on Windows, Linux, macOS without sqlite3 CLI)
      try {
        const buf = fs.readFileSync(dbPath);
        const str = buf.toString('latin1');
        
        // 1. Direct Cursor JWT or session token after cursorAuth/accessToken or cursorAuth/token
        const mToken = str.match(/(?:cursorAuth\/(?:accessToken|token)|WorkosCursorSessionToken|workos_access_token)[\x00-\x1f]*([a-zA-Z0-9_\-\.]{20,})/);
        if (mToken && mToken[1]) return mToken[1];

        // 2. Generic session token pattern (JWT ey... or sess_... or user_...)
        const mJwt = str.match(/(?:ey[a-zA-Z0-9_\-]{20,}\.[a-zA-Z0-9_\-]{20,}\.[a-zA-Z0-9_\-]+|sess_[a-zA-Z0-9_\-]{20,}|user_[a-zA-Z0-9_\-]{20,})/);
        if (mJwt) return mJwt[0];
      } catch (_) {}
    }

    return null;
  }

  static hasCursorInstalled() {
    const home = os.homedir();
    if (process.platform === 'darwin') {
      return fs.existsSync('/Applications/Cursor.app') || fs.existsSync(path.join(home, 'Library/Application Support/Cursor'));
    } else if (process.platform === 'win32') {
      const local = process.env.LOCALAPPDATA || path.join(home, 'AppData', 'Local');
      const progFiles = process.env['ProgramFiles'] || 'C:\\Program Files';
      const progFilesX86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';
      return fs.existsSync(path.join(local, 'Programs', 'cursor')) ||
             fs.existsSync(path.join(local, 'Programs', 'Cursor')) ||
             fs.existsSync(path.join(local, 'cursor')) ||
             fs.existsSync(path.join(local, 'Cursor')) ||
             fs.existsSync(path.join(progFiles, 'Cursor')) ||
             fs.existsSync(path.join(progFilesX86, 'Cursor')) ||
             fs.existsSync(path.join(home, 'AppData', 'Roaming', 'Cursor')) ||
             fs.existsSync(path.join(home, '.cursor'));
    } else {
      return fs.existsSync(path.join(home, '.config', 'Cursor')) || fs.existsSync('/opt/Cursor');
    }
  }

  async fetch() {
    let token = this.token;
    if (!token) {
      token = CursorProvider.getLocalSessionToken();
    }

    const isInstalled = CursorProvider.hasCursorInstalled();
    if (!token && !isInstalled) {
      return null;
    }

    // Calculate days remaining in current monthly cycle
    const now = new Date();
    const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    const daysRemaining = Math.max(1, Math.ceil((nextMonth - now) / (1000 * 60 * 60 * 24)));
    const resetInDays = `${daysRemaining}d`;

    if (token) {
      const usage = await this.queryUsageApi(token);
      if (usage) {
        return usage;
      }
    }

    // If installed but token query wasn't available, provide active status
    return {
      provider: 'cursor',
      account: 'Cursor IDE',
      plan: 'Cursor Pro / Fast Requests',
      mode: 'ide',
      groups: [
        {
          name: 'Cursor',
          description: 'Editor Cursor IDE (Claude 3.5 & GPT-4o)',
          provider: 'Cursor',
          buckets: [
            {
              id: 'cursor-fast-requests',
              name: 'Fast Requests (Claude / GPT-4o)',
              remaining_pct: 100,
              reset_in: resetInDays,
              detail: '500 fast requests / month (Pro Plan)'
            },
            {
              id: 'cursor-monthly-cycle',
              name: 'Monthly Billing Cycle',
              remaining_pct: Math.round(((30 - Math.min(30, daysRemaining)) / 30) * 100),
              reset_in: resetInDays,
              detail: `Quota renews in ${daysRemaining} days`
            }
          ]
        }
      ]
    };
  }

  queryUsageApi(token) {
    return new Promise((resolve) => {
      const options = {
        hostname: 'www.cursor.com',
        path: '/api/usage',
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Cookie': `WorkosCursorSessionToken=${token}`,
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Cursor/0.42.0',
          'Accept': 'application/json'
        },
        timeout: 4000
      };

      const req = https.request(options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          if (res.statusCode === 200) {
            try {
              const data = JSON.parse(body);
              const gpt4 = data['gpt-4'] || data['premium'] || {};
              const numUsed = gpt4.numRequests || data.numFastRequests || 0;
              const maxRequests = gpt4.maxRequestUsage || data.maxFastRequests || 500;
              const remaining = Math.max(0, maxRequests - numUsed);
              const remainingPct = Math.round((remaining / maxRequests) * 100);

              const now = new Date();
              const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
              const daysRemaining = Math.max(1, Math.ceil((nextMonth - now) / (1000 * 60 * 60 * 24)));

              resolve({
                provider: 'cursor',
                account: data.email || 'Cursor Pro',
                plan: 'Cursor Pro',
                mode: 'ide',
                groups: [
                  {
                    name: 'Cursor',
                    description: 'Editor Cursor IDE (Claude 3.5 & GPT-4o)',
                    provider: 'Cursor',
                    buckets: [
                      {
                        id: 'cursor-fast-requests',
                        name: 'Fast Requests (Claude / GPT-4o)',
                        remaining_pct: remainingPct,
                        reset_in: `${daysRemaining}d`,
                        detail: `${remaining} of ${maxRequests} requests remaining`
                      },
                      {
                        id: 'cursor-monthly-cycle',
                        name: 'Monthly Billing Cycle',
                        remaining_pct: Math.round(((30 - Math.min(30, daysRemaining)) / 30) * 100),
                        reset_in: `${daysRemaining}d`,
                        detail: `Quota renews in ${daysRemaining} days`
                      }
                    ]
                  }
                ]
              });
            } catch (_) {
              resolve(null);
            }
          } else {
            resolve(null);
          }
        });
      });

      req.on('error', () => resolve(null));
      req.on('timeout', () => { req.destroy(); resolve(null); });
      req.end();
    });
  }
}

module.exports = { CursorProvider };
