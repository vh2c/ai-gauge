/**
 * Gemini Gauge Update Checker & Announcement Hub
 * Developed by VH2C • https://vh2c.com.br
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const CURRENT_VERSION = '1.1.0';
const GITHUB_REPO = 'vh2c/gemini-gauge';
const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

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
      if (data && data.timestamp && (Date.now() - data.timestamp < CACHE_TTL_MS)) {
        return data;
      }
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

function fetchGithubRelease() {
  return new Promise((resolve) => {
    const options = {
      hostname: 'api.github.com',
      path: `/repos/${GITHUB_REPO}/releases/latest`,
      headers: {
        'User-Agent': 'GeminiGauge-Desktop/1.0',
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
 * Checks for updates and returns version state + announcement/tier structure
 */
async function checkForUpdates(force = false) {
  if (!force) {
    const cached = readCache();
    if (cached) {
      return cached;
    }
  }

  let remoteData = null;
  try {
    remoteData = await fetchGithubRelease();
  } catch (_) {}

  const latestVer = remoteData?.latest_version || CURRENT_VERSION;
  const updateAvailable = isNewer(latestVer, CURRENT_VERSION);

  // Logical structure for announcements and tiers (Free vs PRO)
  const result = {
    current_version: CURRENT_VERSION,
    latest_version: latestVer,
    update_available: updateAvailable,
    download_url: remoteData?.download_url || `https://github.com/${GITHUB_REPO}/releases/latest`,
    release_notes: remoteData?.release_notes || '',
    
    // Tier structure: 'free' (default) or 'pro'
    tier: remoteData?.tier || 'free',
    
    // Announcement only exists when explicitly sent by the remote API / backend
    announcement: remoteData?.announcement || null
  };

  writeCache(result);
  return result;
}

module.exports = {
  CURRENT_VERSION,
  checkForUpdates,
  writeCache,
  isNewer
};
