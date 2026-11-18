/**
 * AI Gauge Update Checker & Announcement Hub
 * Developed by VH2C • https://vh2c.com.br
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const CURRENT_VERSION = '1.1.1';
const GITHUB_REPO = 'vh2c/ai-gauge';
const CACHE_TTL_MS = 60 * 60 * 1000;        // how often announcements/version are re-checked
const SLOW_TTL_MS = 6 * 60 * 60 * 1000;       // server without check_only support: do not poll often (each call would count as a launch)
const PROBE_MS = 60 * 60 * 1000;               // how often the public list is probed for changes (no launch counted)
const STALE_MAX_AGE_MS = 24 * 60 * 60 * 1000; // keep last known announcement this long if the API is unreachable
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

function readCache() {
  const file = getCacheFile();
  if (fs.existsSync(file)) {
    try {
      const data = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (data && data.timestamp && (Date.now() - data.timestamp < (data.poll_ttl_ms || CACHE_TTL_MS))) {
        return data;
      }
    } catch (_) {}
  }
  return null;
}

// Last cached payload regardless of age (used to keep the announcement alive between heartbeats)
function readStaleCache() {
  const file = getCacheFile();
  if (fs.existsSync(file)) {
    try {
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {}
  }
  return null;
}

function writeCacheRaw(data) {
  const file = getCacheFile();
  try {
    fs.writeFileSync(file, JSON.stringify(data, null, 2), 'utf8');
  } catch (_) {}
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

function fetchGithubRelease() {
  return new Promise((resolve) => {
    const options = {
      hostname: 'api.github.com',
      path: `/repos/${GITHUB_REPO}/releases/latest`,
      headers: {
        'User-Agent': 'AIGauge-Desktop/1.1',
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
 * Cheap change detector for servers WITHOUT check_only support: GET the public list of active announcements
 * (read-only, sends nothing about the user) and reduce it to a signature. If the signature changes, the app
 * does one full check; otherwise it keeps the cache. Returns null if the list cannot be read.
 */
function fetchAnnouncementSignature() {
  return new Promise((resolve) => {
    if (telemetryOptedOut()) return resolve(null);
    let url;
    try { url = new URL(API_URL); } catch (_) { return resolve(null); }
    const client = url.protocol === 'https:' ? https : http;
    const req = client.request({
      hostname: url.hostname,
      port: url.port || (url.protocol === 'https:' ? 443 : 80),
      path: '/api/announcements',
      method: 'GET',
      headers: { 'User-Agent': `AIGauge/${CURRENT_VERSION} (VH2C; Desktop)`, 'Accept': 'application/json' },
      timeout: 3000
    }, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => {
        try {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            const data = JSON.parse(body);
            if (data && Array.isArray(data.items)) {
              return resolve(data.items.map(i => `${i.id}:${i.tipo || ''}:${i.data_fim || ''}`).sort().join('|'));
            }
          }
        } catch (_) {}
        resolve(null);
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { try { req.destroy(); } catch (_) {} resolve(null); });
    req.end();
  });
}

function telemetryOptedOut() {
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(getConfigDir(), 'config.json'), 'utf8'));
    return cfg.telemetry === false || cfg.telemetry_enabled === false;
  } catch (_) {
    return false;
  }
}

/**
 * Asks the AI Gauge API for the current announcement / tier / latest version WITHOUT counting a launch
 * (check_only). The API is the source of truth for banners; nothing about providers or accounts is sent.
 */
function fetchApiCheck() {
  return new Promise((resolve) => {
    if (telemetryOptedOut()) return resolve(null);
    let payload;
    try {
      const { getMachineId } = require('./telemetry');
      payload = JSON.stringify({
        app: 'ai-gauge',
        version: CURRENT_VERSION,
        os: os.platform(),
        arch: os.arch(),
        machine_id: getMachineId(),
        timestamp: Math.floor(Date.now() / 1000),
        check_only: true
      });
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
                promo: data.promo || null,
                supports_check_only: data.check_only === true
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
 * Checks for updates and returns version state + announcement/tier structure
 */
async function checkForUpdates(force = false) {
  if (!force) {
    const cached = readCache();
    if (cached) {
      // Server without check_only: the cache can live for hours, but we probe the public list
      // every hour so a new/disabled announcement is picked up quickly without counting a launch.
      const probeDue = cached.supports_check_only !== true &&
        (Date.now() - (cached.probe_at || cached.timestamp || 0)) > PROBE_MS;
      if (!probeDue) {
        return cached;
      }
      const sig = await fetchAnnouncementSignature();
      if (sig === null || sig === cached.list_sig) {
        if (sig !== null) writeCacheRaw({ ...cached, probe_at: Date.now() });
        return cached;
      }
      // signature changed: fall through to a full refresh
    }
  }

  const stale = readStaleCache();
  const staleFresh = stale && stale.timestamp && (Date.now() - stale.timestamp < STALE_MAX_AGE_MS);

  // 1. The API decides announcements, tier, latest version and download URL
  let apiData = null;
  try {
    apiData = await fetchApiCheck();
  } catch (_) {}

  // 2. GitHub is only a fallback for the version when the API is unreachable
  let remoteData = null;
  if (!apiData) {
    try {
      remoteData = await fetchGithubRelease();
    } catch (_) {}
  }

  const latestVer = apiData?.latest_version || remoteData?.latest_version || stale?.latest_version || CURRENT_VERSION;
  const updateAvailable = isNewer(latestVer, CURRENT_VERSION);

  let listSig = null;
  if (apiData && !apiData.supports_check_only) {
    try { listSig = await fetchAnnouncementSignature(); } catch (_) {}
  }

  const result = {
    current_version: CURRENT_VERSION,
    latest_version: latestVer,
    update_available: updateAvailable,
    download_url: apiData?.download_url || remoteData?.download_url || `https://github.com/${GITHUB_REPO}/releases/latest`,
    release_notes: remoteData?.release_notes || '',
    poll_ttl_ms: (apiData && !apiData.supports_check_only) ? SLOW_TTL_MS : CACHE_TTL_MS,
    supports_check_only: !!(apiData && apiData.supports_check_only),
    list_sig: listSig,
    probe_at: Date.now(),

    // Tier structure: 'free' (default) or 'pro'
    tier: apiData ? apiData.tier : (staleFresh && stale.tier) || 'free',

    // API reachable: its answer is authoritative (null = no announcement, clears an old banner).
    // API unreachable: keep the last known announcement for up to 24h.
    announcement: apiData ? (apiData.announcement || null) : (staleFresh ? (stale.announcement || null) : null)
  };

  // Advertising toast. New API sends `promo`; an older API only sends `announcement`, where an ad
  // (type "publicidade") means "show the toast".
  if (apiData && apiData.promo) {
    result.promo = apiData.promo;
  } else if (result.announcement && result.announcement.type === 'publicidade') {
    result.promo = result.announcement;
  } else if (!apiData && staleFresh && stale.promo) {
    result.promo = stale.promo;
  } else {
    result.promo = null;
  }

  writeCache(result);
  return result;
}

module.exports = {
  CURRENT_VERSION,
  checkForUpdates,
  writeCache,
  isNewer
};
