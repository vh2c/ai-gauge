/**
 * AI Gauge Telemetry & Update Check
 * Developed by VH2C • https://vh2c.com.br
 *
 * Privacy Promise:
 * - Collects ONLY anonymous launch ping: app version, OS platform, arch, and random machine_id.
 * - NEVER collects or transmits API keys, tokens, prompts, code, active providers or personal data.
 * - Supports complete opt-out via `telemetry: false` in config.json.
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const ENDPOINT = 'https://ai-gauge.vh2c.com.br/v1/geminigauje';

function getTelemetryDir() {
  const dir = path.join(os.homedir(), '.config', 'UniversalAIQuota');
  if (!fs.existsSync(dir)) {
    try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
  }
  return dir;
}

function getMachineId() {
  const idFile = path.join(getTelemetryDir(), 'device_id');
  if (fs.existsSync(idFile)) {
    try {
      const id = fs.readFileSync(idFile, 'utf8').trim();
      if (id && id.length >= 8) return id;
    } catch (_) {}
  }

  // Generate completely random anonymous device ID (no hardware/host fingerprints)
  const newId = crypto.randomUUID ? crypto.randomUUID().replace(/-/g, '') : crypto.randomBytes(16).toString('hex');
  try {
    fs.writeFileSync(idFile, newId, 'utf8');
  } catch (_) {}
  return newId;
}

function sendHeartbeat(force = false) {
  const dir = getTelemetryDir();
  
  // 1. Check user opt-out
  const cfgFile = path.join(dir, 'config.json');
  if (fs.existsSync(cfgFile)) {
    try {
      const cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
      if (cfg.telemetry === false || cfg.telemetry_enabled === false) {
        return; // User opted out
      }
    } catch (_) {}
  }

  // 2. Throttle pings to at most once per 6 hours (prevent repeated/excessive calls)
  const stampFile = path.join(dir, '.last_ping');
  const now = Math.floor(Date.now() / 1000);
  if (!force && fs.existsSync(stampFile)) {
    try {
      const last = parseInt(fs.readFileSync(stampFile, 'utf8').trim(), 10);
      if (now - last < 21600) { // 6 hours
        return;
      }
    } catch (_) {}
  }

  // 3. Strictly minimal, privacy-first payload matching README declaration
  const payload = JSON.stringify({
    app: 'ai-gauge',
    version: '1.1.0',
    os: os.platform(),
    arch: os.arch(),
    machine_id: getMachineId(),
    timestamp: now
  });

  try {
    const url = new URL(ENDPOINT);
    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === 'https:' ? 443 : 80),
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'User-Agent': 'AIGauge/1.1 (VH2C; Desktop)'
      },
      timeout: 2500
    };

    const client = url.protocol === 'https:' ? https : http;
    const req = client.request(options, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => {
        try {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            try { fs.writeFileSync(stampFile, String(now), 'utf8'); } catch (_) {}
            const data = JSON.parse(body);
            if (data && (data.latest_version || data.announcement || data.tier)) {
              const { writeCache, CURRENT_VERSION, isNewer } = require('./updater');
              writeCache({
                current_version: CURRENT_VERSION,
                latest_version: data.latest_version || CURRENT_VERSION,
                update_available: isNewer(data.latest_version, CURRENT_VERSION),
                download_url: data.download_url || 'https://github.com/vh2c/gemini-gauge/releases/latest',
                tier: data.tier || 'free',
                announcement: data.announcement || null,
                promo: data.promo || ((data.announcement && data.announcement.type === 'publicidade') ? data.announcement : null),
                supports_check_only: data.check_only === true
              });
            }
          }
        } catch (_) {}
      });
    });

    req.on('error', () => {});
    req.on('timeout', () => {
      try { req.destroy(); } catch (_) {}
    });

    req.write(payload);
    req.end();
  } catch (_) {
    // Fail silently
  }
}

module.exports = {
  ENDPOINT,
  getMachineId,
  sendHeartbeat
};
