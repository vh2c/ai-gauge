/**
 * AI Gauge machine identity
 * Developed by VH2C • https://vh2c.com.br
 *
 * The only thing this module does is create and read a random, anonymous machine_id (no hardware or host
 * fingerprints). All network traffic to the AI Gauge API lives in updater.js, which documents what is sent
 * and when. Telemetry can be turned off with `"telemetry": false` in config.json.
 */

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

module.exports = {
  ENDPOINT,
  getMachineId
};
