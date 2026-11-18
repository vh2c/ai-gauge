/**
 * Marks provider data that comes from an old local cache as "Outdated".
 *
 * When a provider cannot reach its service (for example the Claude Code login expired), it falls back to the last
 * cached numbers. Showing them as if they were current is misleading, so after OUTDATED_AFTER_MS the buckets are
 * flagged: the apps show "Outdated" where they normally show the reset time.
 */

const OUTDATED_AFTER_MS = 30 * 60 * 1000;

function markOutdated(payload, ageMs, hint) {
  if (!payload || !(ageMs > OUTDATED_AFTER_MS)) return payload;
  payload.outdated_seconds = Math.round(ageMs / 1000);
  for (const g of payload.groups || []) {
    g.outdated = true;
    for (const b of g.buckets || []) {
      b.reset_in = 'Outdated';
      b.outdated = true;
      b.detail = hint || 'Data is outdated';
    }
  }
  return payload;
}

module.exports = { markOutdated, OUTDATED_AFTER_MS };
