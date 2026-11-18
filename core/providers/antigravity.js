/**
 * Antigravity Provider for Universal AI Quota Monitor
 * Supports live process discovery + headless language_server fallback
 */

const { exec, spawn } = require('child_process');
const http = require('http');
const https = require('https');
const util = require('util');
const fs = require('fs');
const path = require('path');
const os = require('os');

const execAsync = util.promisify(exec);

const RPC_SUMMARY_PATH = '/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary';
const RPC_USER_STATUS_PATH = '/exa.language_server_pb.LanguageServerService/GetUserStatus';

const DEFAULT_METADATA_BODY = {
  metadata: {
    ideName: 'antigravity',
    extensionName: 'universal-ai-quota-monitor',
    locale: 'en'
  }
};

function formatTimeRemaining(resetTimeString, remainingFraction = 1.0) {
  if (!resetTimeString) return '';
  const resetDate = new Date(resetTimeString);
  if (Number.isNaN(resetDate.getTime()) || resetDate.getFullYear() < 2020) return '';
  const now = new Date();
  const diffMs = resetDate - now;
  if (diffMs <= 0) {
    return (remainingFraction !== undefined && remainingFraction >= 0.99) ? '' : 'Renewing...';
  }
  const totalMinutes = Math.floor(diffMs / (1000 * 60));
  const hours = Math.floor(totalMinutes / 60);
  const mins = totalMinutes % 60;
  if (hours > 24) {
    const days = Math.floor(hours / 24);
    const remHours = hours % 24;
    return `${days}d ${remHours}h`;
  }
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

function extractCsrfToken(commandLine) {
  if (!commandLine || typeof commandLine !== 'string') return null;
  const match = commandLine.match(/--csrf[_-]token(?:=|\s+)["']?([a-z0-9_-]{8,})["']?/i);
  return match ? match[1] : null;
}

function extractCliPorts(commandLine) {
  if (!commandLine || typeof commandLine !== 'string') return [];
  const ports = [];
  const patterns = [
    /--hub[_-]port(?:=|\s+)["']?(\d{2,5})["']?/gi,
    /--extension[_-]server[_-]port(?:=|\s+)["']?(\d{2,5})["']?/gi,
    /--port(?:=|\s+)["']?(\d{2,5})["']?/gi
  ];
  for (const regex of patterns) {
    for (const match of commandLine.matchAll(regex)) {
      const p = parseInt(match[1], 10);
      if (p > 0 && p <= 65535 && !ports.includes(p)) {
        ports.push(p);
      }
    }
  }
  return ports;
}

class AntigravityProvider {
  constructor() {
    this.platform = process.platform;
  }

  findAllDaemonHubs() {
    const hubs = [];
    try {
      const home = os.homedir();
      const userProfile = process.env.USERPROFILE || home;
      const localApp = process.env.LOCALAPPDATA || path.join(userProfile, 'AppData', 'Local');
      const appData = process.env.APPDATA || path.join(userProfile, 'AppData', 'Roaming');

      const daemonDirs = [
        path.join(home, '.gemini', 'antigravity', 'daemon'),
        path.join(userProfile, '.gemini', 'antigravity', 'daemon'),
        path.join(localApp, 'Antigravity', 'daemon'),
        path.join(appData, 'Antigravity', 'daemon'),
        path.join(home, '.antigravity', 'daemon')
      ];

      const seenDirs = new Set();
      for (const d of daemonDirs) {
        if (!d || seenDirs.has(d)) continue;
        seenDirs.add(d);
        if (!fs.existsSync(d)) continue;

        let files = [];
        try {
          files = fs.readdirSync(d).filter(f => f.startsWith('hub_') && f.endsWith('.json'));
        } catch (_) { continue; }

        // Sort newest first and take top 10 hub files regardless of age
        files.sort((a, b) => {
          try {
            return fs.statSync(path.join(d, b)).mtimeMs - fs.statSync(path.join(d, a)).mtimeMs;
          } catch (_) { return 0; }
        });

        for (const file of files.slice(0, 10)) {
          try {
            const filePath = path.join(d, file);
            const content = JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
            if (content.csrfToken && (content.httpPort || content.httpsPort)) {
              hubs.push({
                pid: content.pid || 0,
                csrfToken: content.csrfToken,
                httpPort: content.httpPort || null,
                httpsPort: content.httpsPort || null,
                commandLine: ''
              });
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return hubs;
  }

  findFromDaemonHubs() {
    const hubs = this.findAllDaemonHubs();
    return hubs.length > 0 ? hubs[0] : null;
  }

  async findRunningProcess() {
    try {
      if (this.platform === 'win32') {
        const cmd = 'powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -match \'language_server|agy|Antigravity\' } | Select-Object ProcessId, CommandLine | ConvertTo-Json"';
        const { stdout } = await execAsync(cmd, { timeout: 5000 });
        let items = JSON.parse(stdout || '[]');
        if (!Array.isArray(items)) items = [items];
        for (const item of items) {
          const token = extractCsrfToken(item.CommandLine || '');
          if (item.ProcessId && token) {
            return { pid: item.ProcessId, commandLine: item.CommandLine, csrfToken: token };
          }
        }
      } else {
        const cmd = 'ps -eo pid,command | grep -E "language_server|agy|Antigravity" | grep -v grep';
        const { stdout } = await execAsync(cmd, { timeout: 3000 });
        for (const line of stdout.split('\n')) {
          const match = line.trim().match(/^(\d+)\s+(.+)$/);
          if (match) {
            const token = extractCsrfToken(match[2]);
            if (token) return { pid: parseInt(match[1], 10), commandLine: match[2], csrfToken: token };
          }
        }
      }
    } catch (_) {}
    return null;
  }

  async getPorts(proc) {
    const ports = [];
    if (proc.httpPort && !ports.includes(proc.httpPort)) ports.push(proc.httpPort);
    if (proc.httpsPort && !ports.includes(proc.httpsPort)) ports.push(proc.httpsPort);

    const pid = proc.pid;
    const commandLine = proc.commandLine || '';
    for (const p of extractCliPorts(commandLine)) {
      if (!ports.includes(p)) ports.push(p);
    }

    try {
      if (this.platform === 'win32') {
        const { stdout } = await execAsync(`netstat -ano | findstr "${pid}"`, { timeout: 4000 });
        for (const line of stdout.split('\n')) {
          if (!line.includes('LISTENING')) continue;
          const parts = line.trim().split(/\s+/);
          if (parts[1] && parts[parts.length - 1] === String(pid)) {
            const m = parts[1].match(/:(\d+)$/);
            if (m) {
              const p = parseInt(m[1], 10);
              if (p > 1024 && !ports.includes(p)) ports.push(p);
            }
          }
        }
      } else {
        const { stdout } = await execAsync(`lsof -nP -p ${pid} -a -iTCP -sTCP:LISTEN 2>/dev/null`, { timeout: 3000 });
        for (const line of stdout.split('\n')) {
          const m = line.match(/:(\d+)\s+\(LISTEN\)/);
          if (m) {
            const p = parseInt(m[1], 10);
            if (!ports.includes(p)) ports.push(p);
          }
        }
      }
    } catch (_) {}

    // Fallback: add ports seen in any hub file and default IDE ports
    for (const h of this.findAllDaemonHubs()) {
      if (h.httpPort && !ports.includes(h.httpPort)) ports.push(h.httpPort);
      if (h.httpsPort && !ports.includes(h.httpsPort)) ports.push(h.httpsPort);
    }
    const defaults = [53078, 53079, 58014, 58013, 53530, 53527, 53529, 53533, 53534];
    for (const d of defaults) {
      if (!ports.includes(d)) ports.push(d);
    }

    return ports;
  }

  requestRpc(port, token, path, body, useHttps = false) {
    return new Promise((resolve) => {
      const data = JSON.stringify(body || DEFAULT_METADATA_BODY);
      const options = {
        hostname: '127.0.0.1',
        port: port,
        path: path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          'x-codeium-csrf-token': token
        },
        timeout: 1500,
        rejectUnauthorized: false
      };

      const lib = useHttps ? https : http;
      const req = lib.request(options, (res) => {
        let respData = '';
        res.on('data', chunk => respData += chunk);
        res.on('end', () => {
          if (res.statusCode === 200) {
            try {
              resolve({ ok: true, data: JSON.parse(respData) });
            } catch (_) {
              resolve({ ok: false });
            }
          } else {
            resolve({ ok: false, status: res.statusCode });
          }
        });
      });

      req.on('error', () => resolve({ ok: false }));
      req.on('timeout', () => { req.destroy(); resolve({ ok: false }); });
      req.write(data);
      req.end();
    });
  }

  findLanguageServerBinary() {
    const home = os.homedir();
    const userProfile = process.env.USERPROFILE || home;
    const localApp = process.env.LOCALAPPDATA || path.join(userProfile, 'AppData', 'Local');
    const progFiles = process.env['ProgramFiles'] || 'C:\\Program Files';
    const progFilesX86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';

    const candidates = [
      '/Applications/Antigravity.app/Contents/Resources/bin/language_server_macos_arm64',
      '/Applications/Antigravity.app/Contents/Resources/bin/language_server_macos_x64',
      '/Applications/Antigravity.app/Contents/Resources/bin/language_server',
      path.join(home, '.local/share/antigravity/bin/language_server'),
      path.join(home, '.gemini/antigravity/bin/language_server'),
      // Windows candidates:
      path.join(localApp, 'Programs', 'Antigravity', 'resources', 'app', 'bin', 'language_server_windows_x64.exe'),
      path.join(localApp, 'Programs', 'Antigravity', 'resources', 'bin', 'language_server_windows_x64.exe'),
      path.join(localApp, 'Programs', 'Antigravity', 'resources', 'bin', 'language_server.exe'),
      path.join(localApp, 'Programs', 'Antigravity', 'bin', 'language_server_windows_x64.exe'),
      path.join(localApp, 'Programs', 'Antigravity', 'bin', 'language_server.exe'),
      path.join(localApp, 'Antigravity', 'bin', 'language_server_windows_x64.exe'),
      path.join(progFiles, 'Antigravity', 'resources', 'app', 'bin', 'language_server_windows_x64.exe'),
      path.join(progFiles, 'Antigravity', 'resources', 'bin', 'language_server_windows_x64.exe'),
      path.join(progFiles, 'Antigravity', 'resources', 'bin', 'language_server.exe'),
      path.join(progFiles, 'Antigravity', 'bin', 'language_server_windows_x64.exe'),
      path.join(progFilesX86, 'Antigravity', 'resources', 'bin', 'language_server_windows_x64.exe'),
      path.join(progFilesX86, 'Antigravity', 'bin', 'language_server_windows_x64.exe'),
      path.join(home, '.gemini', 'antigravity', 'bin', 'language_server_windows_x64.exe'),
      path.join(home, '.gemini', 'antigravity', 'bin', 'language_server.exe'),
      path.join(userProfile, '.gemini', 'antigravity', 'bin', 'language_server_windows_x64.exe'),
      path.join(userProfile, '.gemini', 'antigravity', 'bin', 'language_server.exe'),
      path.join(home, '.gemini', 'antigravity', 'bin', 'language_server')
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return c;
    }
    return null;
  }

  async fetchHeadless() {
    const binPath = this.findLanguageServerBinary();
    if (!binPath) return null;

    const token = 'uaqm-' + Math.random().toString(36).substring(2, 12);
    const args = [
      '--standalone',
      '--override_ide_name', 'antigravity',
      '--subclient_type', 'hub',
      '--app_data_dir', 'antigravity',
      '--api_server_url', 'https://generativelanguage.googleapis.com',
      '--cloud_code_endpoint', 'https://daily-cloudcode-pa.googleapis.com',
      '--https_server_port', '0',
      '--csrf_token', token
    ];

    const proc = spawn(binPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    return new Promise((resolve) => {
      let resolved = false;
      let stderrOutput = '';
      let stdoutOutput = '';

      const cleanup = () => {
        try { proc.kill(); } catch (_) {}
      };

      const timer = setTimeout(() => {
        if (!resolved) {
          resolved = true;
          cleanup();
          resolve(null);
        }
      }, 8000);

      const activeConnections = new Set();
      const tryConnect = async (port, isHttps) => {
        const key = `${port}:${isHttps}`;
        if (resolved || activeConnections.has(key)) return;
        activeConnections.add(key);

        for (let attempt = 0; attempt < 8 && !resolved; attempt++) {
          await new Promise(r => setTimeout(r, 350));
          if (resolved) return;

          let userRes = await this.requestRpc(port, token, RPC_USER_STATUS_PATH, {}, isHttps);
          const sumRes = await this.requestRpc(port, token, RPC_SUMMARY_PATH, {}, isHttps);
          if (!resolved && (sumRes.ok || userRes.ok)) {
            if (sumRes.ok && !userRes.ok) {
              const retryUser = await this.requestRpc(port, token, RPC_USER_STATUS_PATH, {}, isHttps);
              if (retryUser.ok) userRes = retryUser;
            }
            if (!resolved) {
              resolved = true;
              clearTimeout(timer);
              cleanup();
              resolve({ summary: sumRes.data || {}, user: userRes.data || {}, mode: 'headless' });
              return;
            }
          }
        }
      };

      const handleChunk = (chunk) => {
        const text = chunk.toString();
        // Check for HTTP port (\b prevents matching "for HTTPS")
        const mHttp = text.match(/listening on random port at (\d+) for HTTP\b/i) ||
                      text.match(/hub_(\d+)\.json/i);
        if (mHttp) {
          const port = parseInt(mHttp[1], 10);
          tryConnect(port, false);
        }
        // Check for HTTPS port
        const mHttps = text.match(/listening on random port at (\d+) for HTTPS\b/i);
        if (mHttps) {
          const port = parseInt(mHttps[1], 10);
          tryConnect(port, true);
        }
        // Generic port match fallback
        const mGen = text.match(/http:\/\/127\.0\.0\.1:(\d+)/i) || text.match(/port\s*[:=]\s*(\d+)/i);
        if (mGen) {
          const port = parseInt(mGen[1], 10);
          tryConnect(port, false);
        }
      };

      proc.stderr.on('data', (d) => {
        stderrOutput += d.toString();
        handleChunk(d);
      });
      proc.stdout.on('data', (d) => {
        stdoutOutput += d.toString();
        handleChunk(d);
      });

      proc.on('error', () => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timer);
          resolve(null);
        }
      });

      proc.on('exit', () => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timer);
          resolve(null);
        }
      });
    });
  }

  async fetch() {
    // 1. Tenta todos os hubs locais salvos (~/.gemini/antigravity/daemon) - 0 overhead, mais rápido e direto
    const hubs = this.findAllDaemonHubs();
    for (const hub of hubs) {
      if (hub.httpPort) {
        const userRes = await this.requestRpc(hub.httpPort, hub.csrfToken, RPC_USER_STATUS_PATH, {}, false);
        if (userRes.ok) {
          const sumRes = await this.requestRpc(hub.httpPort, hub.csrfToken, RPC_SUMMARY_PATH, {}, false);
          return this.normalize(sumRes.data || {}, userRes.data || {}, 'online');
        }
      }
      if (hub.httpsPort) {
        const userRes = await this.requestRpc(hub.httpsPort, hub.csrfToken, RPC_USER_STATUS_PATH, {}, true);
        if (userRes.ok) {
          const sumRes = await this.requestRpc(hub.httpsPort, hub.csrfToken, RPC_SUMMARY_PATH, {}, true);
          return this.normalize(sumRes.data || {}, userRes.data || {}, 'online');
        }
      }
    }

    // 2. Se nenhum hub de arquivo respondeu, tenta processo em execução
    const proc = await this.findRunningProcess();
    if (proc && proc.csrfToken) {
      const ports = await this.getPorts(proc);
      for (const port of ports) {
        for (const isHttps of [false, true]) {
          const userRes = await this.requestRpc(port, proc.csrfToken, RPC_USER_STATUS_PATH, {}, isHttps);
          if (userRes.ok) {
            const sumRes = await this.requestRpc(port, proc.csrfToken, RPC_SUMMARY_PATH, {}, isHttps);
            return this.normalize(sumRes.data || {}, userRes.data || {}, 'online');
          }
        }
      }
    }

    // 3. Se não estiver rodando, tenta boot headless independente
    const headlessRes = await this.fetchHeadless();
    if (headlessRes) {
      return this.normalize(headlessRes.summary || {}, headlessRes.user || {}, 'headless');
    }

    return null;
  }

  normalize(quotaData, userData, mode = 'online') {
    const userStatus = userData.userStatus || {};
    const planInfo = userStatus.planStatus?.planInfo || {};

    const groups = [];
    const qPayload = quotaData.response || quotaData;
    const rawGroups = qPayload.groups || [];
    for (const g of rawGroups) {
      const gItem = {
        name: g.displayName || 'Antigravity Models',
        description: g.description || '',
        provider: 'Antigravity (' + (mode === 'headless' ? 'Headless' : 'Live') + ')',
        buckets: []
      };
      for (const b of (g.buckets || [])) {
        const pct = Math.round((b.remainingFraction ?? 1) * 100);
        const timeStr = formatTimeRemaining(b.resetTime, b.remainingFraction);
        gItem.buckets.push({
          id: b.bucketId || '',
          name: b.displayName || 'Limit',
          remaining_pct: pct,
          reset_in: timeStr,
          reset_time: b.resetTime || null,
          detail: timeStr ? `Resets in ${timeStr}` : ''
        });
      }
      if (gItem.buckets.length > 0) groups.push(gItem);
    }

    return {
      provider: 'antigravity',
      account: userStatus.email || 'Antigravity Account',
      plan: planInfo.planName || 'Pro',
      mode: mode,
      groups: groups
    };
  }
}

module.exports = { AntigravityProvider };
