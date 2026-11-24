/**
 * AI Gauge Update Checker & Announcement Hub
 * Developed by VH2C • https://vh2c.com.br
 *
 * When the app talks to the AI Gauge API (see "Telemetry & Privacy" in the README):
 *   - ONCE when the app starts (the app passes `--startup` to the engine on its first run), and
 *   - once more every 24 hours IF the app is still running (a plain check that is not counted as a launch).
 * Between those moments the engine only reads a local cache. There are no polling timers.
 *
 * What is sent:
 *   - FREE: anonymous random machine_id, app version, OS and CPU architecture.
 *   - PRO / enterprise: only the machine_id (needed to recognise the license) and the app version.
 * Never sent: API keys, tokens, prompts, code, which providers you use, or any personal data.
 * Opt-out: `"telemetry": false` in config.json (no call to the API at all; only a public GitHub version check).
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const CURRENT_VERSION = '1.3.2';
const GITHUB_REPO = 'vh2c/ai-gauge';
const RECHECK_MS = 24 * 60 * 60 * 1000;        // re-check while the app stays open
const RETRY_MS = 60 * 60 * 1000;               // after a failed check, try again in 1 hour (not on every refresh)
const STARTUP_MIN_GAP_MS = 10 * 60 * 1000;     // restarting the app within 10 minutes does not call the API again
const STALE_MAX_AGE_MS = 3 * 24 * 60 * 60 * 1000; // keep the last announcement/promo this long if the API is unreachable
const API_URL = process.env.AIGAUGE_API_URL || 'https://ai-gauge.vh2c.com.br/v1/geminigauje';

function getConfigDir() {
  const dir = path.join(os.homedir(), '.config', 'UniversalAIQuota');
  if (!fs.existsSync(dir)) {
    try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
  }
  return dir;
}

function getCacheFile() {
  return path.join(getConfigDir(), 'update_cache.json');
}

// Last cached payload regardless of age
function readCache() {
  const file = getCacheFile();
  if (fs.existsSync(file)) {
    try {
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {}
  }
  return null;
}

function writeCache(data) {
  const file = getCacheFile();
  try {
    fs.writeFileSync(file, JSON.stringify({ ...data, timestamp: Date.now() }, null, 2), 'utf8');
  } catch (_) {}
}

function isNewer(remoteVer, currentVer) {
  if (!remoteVer) return false;
  const parse = v => v.replace(/^v/, '').trim().split('.').map(n => parseInt(n, 10) || 0);
  const r = parse(remoteVer);
  const c = parse(currentVer);
  for (let i = 0; i < Math.max(r.length, c.length); i++) {
    const rv = r[i] || 0;
    const cv = c[i] || 0;
    if (rv > cv) return true;
    if (rv < cv) return false;
  }
  return false;
}

function isProTier(tier) {
  return tier === 'pro' || tier === 'enterprise';
}

function telemetryOptedOut() {
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(getConfigDir(), 'config.json'), 'utf8'));
    return cfg.telemetry === false || cfg.telemetry_enabled === false;
  } catch (_) {
    return false;
  }
}

// Public GitHub lookup of the latest release (version only). Used when the API is unreachable or telemetry is off.
function fetchGithubRelease() {
  return new Promise((resolve) => {
    const options = {
      hostname: 'api.github.com',
      path: `/repos/${GITHUB_REPO}/releases/latest`,
      headers: {
        'User-Agent': `AIGauge/${CURRENT_VERSION}`,
        'Accept': 'application/vnd.github.v3+json'
      },
      timeout: 3500
    };

    const req = https.get(options, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => {
        try {
          if (res.statusCode === 200) {
            const data = JSON.parse(body);
            resolve({
              latest_version: (data.tag_name || '').replace(/^v/, ''),
              download_url: data.html_url || `https://github.com/${GITHUB_REPO}/releases/latest`,
              release_notes: data.name || data.body || '',
              published_at: data.published_at || ''
            });
            return;
          }
        } catch (_) {}
        resolve(null);
      });
    });

    req.on('error', () => resolve(null));
    req.on('timeout', () => {
      try { req.destroy(); } catch (_) {}
      resolve(null);
    });
  });
}

/**
 * Validates a raw locale string ("pt_BR.UTF-8", "en-US", "pt-BR@x") and returns it as "pt-BR" / "en-US" / "es",
 * or null when it does not look like a locale ("C", "POSIX", garbage).
 */
function parseLocale(raw) {
  if (typeof raw !== 'string') return null;
  const base = raw.trim().split('.')[0].split('@')[0].replace(/_/g, '-');
  const m = /^([A-Za-z]{2,3})(?:-([A-Za-z]{2}|[0-9]{3}))?(?:-[A-Za-z0-9]{2,8})*$/.exec(base);
  if (!m) return null;
  return m[2] ? `${m[1].toLowerCase()}-${m[2].toUpperCase()}` : m[1].toLowerCase();
}

let cachedLocale;
/**
 * The system interface language (e.g. "pt-BR"), used by the server only to choose the notice language and the
 * donation account (Brazil x international). Returns null when it cannot be read: the server then assumes English.
 * macOS: the real preferred language (Node's own default depends on env vars that GUI launches do not have).
 */
function getSystemLocale() {
  if (cachedLocale !== undefined) return cachedLocale;
  let found = null;
  try {
    if (process.platform === 'darwin') {
      const { execFileSync } = require('child_process');
      const langs = execFileSync('/usr/bin/defaults', ['read', '-g', 'AppleLanguages'], { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] });
      const first = /"?([A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*)"?\s*[,)]/.exec(langs.replace(/^\(\s*/, ''));
      found = parseLocale(first && first[1]);
    } else if (process.platform !== 'win32') {
      const env = process.env;
      found = parseLocale(env.LC_ALL) || parseLocale(env.LC_MESSAGES) || parseLocale(env.LANG) || parseLocale((env.LANGUAGE || '').split(':')[0]);
    }
    if (!found) found = parseLocale(Intl.DateTimeFormat().resolvedOptions().locale); // Windows (user locale) and fallback
  } catch (_) {}
  cachedLocale = found;
  return found;
}

/**
 * The exact data sent to the API. PRO users send the bare minimum.
 * `checkOnly` = a plain check that the server does not count as an app launch.
 */
function buildPayload(tier, checkOnly) {
  const { getMachineId } = require('./telemetry');
  const payload = {
    app: 'ai-gauge',
    version: CURRENT_VERSION,
    machine_id: getMachineId()
  };
  // System language: lets the server pick the Portuguese/English notice and the right donation account. Sent by
  // FREE and PRO; the server stores it only for FREE. Omitted when unknown (the server then assumes English).
  const locale = getSystemLocale();
  if (locale) payload.locale = locale;
  if (!isProTier(tier)) {
    payload.os = os.platform();
    payload.arch = os.arch();
    payload.timestamp = Math.floor(Date.now() / 1000);
  }
  if (checkOnly) payload.check_only = true;
  return payload;
}

function fetchApi(tier, checkOnly) {
  return new Promise((resolve) => {
    let payload;
    try {
      payload = JSON.stringify(buildPayload(tier, checkOnly));
    } catch (_) {
      return resolve(null);
    }

    let url;
    try { url = new URL(API_URL); } catch (_) { return resolve(null); }
    const client = url.protocol === 'https:' ? https : http;
    const req = client.request({
      hostname: url.hostname,
      port: url.port || (url.protocol === 'https:' ? 443 : 80),
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'User-Agent': `AIGauge/${CURRENT_VERSION} (VH2C; Desktop)`
      },
      timeout: 3000
    }, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => {
        try {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            const data = JSON.parse(body);
            if (data && data.success !== false) {
              return resolve({
                latest_version: data.latest_version || '',
                download_url: data.download_url || '',
                tier: data.tier || 'free',
                announcement: data.announcement || null,
                promo: data.promo || null
              });
            }
          }
        } catch (_) {}
        resolve(null);
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { try { req.destroy(); } catch (_) {} resolve(null); });
    req.write(payload);
    req.end();
  });
}

/**
 * Returns version state + announcement / promo / tier, talking to the network only when due:
 *   - startup:true  -> app just opened: one launch call (skipped if the previous launch call was < 10 min ago)
 *   - startup:false -> normal refresh: cache only, unless 24 h passed since the last successful check
 *                      (then one plain check; after a failure, retry in 1 h)
 */
async function checkForUpdates(opts = {}) {
  const startup = opts.startup === true;
  const now = Date.now();
  const cached = readCache();

  let mode = null; // 'launch' | 'recheck'
  if (startup) {
    // A different app version than the one that wrote the cache means the app was just updated: always check,
    // regardless of the 10-minute guard, so the "new release" banner for the old version is cleared right away.
    const upgraded = !!cached && !!cached.current_version && cached.current_version !== CURRENT_VERSION;
    const gapOk = !cached || !cached.last_launch_at || upgraded || (now - cached.last_launch_at) >= STARTUP_MIN_GAP_MS;
    if (gapOk) mode = 'launch';
  } else if (!cached) {
    mode = 'launch';
  } else if (now >= (cached.next_check_at || 0)) {
    mode = 'recheck';
  }
  if (!mode) {
    // Whether an update is available depends on the version that is running NOW, not on the one that wrote the cache
    return cached ? {
      ...cached,
      current_version: CURRENT_VERSION,
      update_available: isNewer(cached.latest_version, CURRENT_VERSION)
    } : cached;
  }

  const optedOut = telemetryOptedOut();
  const staleFresh = !optedOut && cached && cached.timestamp && (now - cached.timestamp < STALE_MAX_AGE_MS);
  const knownTier = (staleFresh && cached.tier) || 'free';

  // 1. The API decides announcements, promo, tier, latest version and download URL (skipped when opted out)
  let apiData = null;
  if (!optedOut) {
    try { apiData = await fetchApi(knownTier, mode === 'recheck'); } catch (_) {}
  }

  // 2. GitHub is only a fallback for the version (API unreachable or telemetry off)
  let remoteData = null;
  if (!apiData) {
    try { remoteData = await fetchGithubRelease(); } catch (_) {}
  }

  const latestVer = apiData?.latest_version || remoteData?.latest_version || cached?.latest_version || CURRENT_VERSION;
  const answered = !!(apiData || remoteData);

  const result = {
    current_version: CURRENT_VERSION,
    latest_version: latestVer,
    update_available: isNewer(latestVer, CURRENT_VERSION),
    download_url: apiData?.download_url || remoteData?.download_url || `https://github.com/${GITHUB_REPO}/releases/latest`,
    release_notes: remoteData?.release_notes || '',
    next_check_at: now + (answered ? RECHECK_MS : RETRY_MS),
    last_launch_at: mode === 'launch' ? now : (cached?.last_launch_at || 0),

    // 'free' (default) or 'pro'
    tier: apiData ? apiData.tier : (staleFresh && cached.tier) || 'free',

    // API reachable: its answer is authoritative (null clears an old banner).
    // API unreachable: keep the last known announcement for up to 3 days. Opted out: none.
    announcement: apiData ? (apiData.announcement || null) : (staleFresh ? (cached.announcement || null) : null)
  };

  // Ad toast. The shown cadence (every 6 h) is handled locally by each app, from this cached value.
  if (apiData && apiData.promo) {
    result.promo = apiData.promo;
  } else if (result.announcement && result.announcement.type === 'publicidade') {
    result.promo = result.announcement;
  } else if (!apiData && staleFresh && cached.promo) {
    result.promo = cached.promo;
  } else {
    result.promo = null;
  }

  writeCache(result);
  return result;
}

module.exports = {
  CURRENT_VERSION,
  RECHECK_MS,
  RETRY_MS,
  STARTUP_MIN_GAP_MS,
  checkForUpdates,
  buildPayload,
  parseLocale,
  getSystemLocale,
  writeCache,
  isNewer
};
