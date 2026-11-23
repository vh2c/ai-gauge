/**
 * Tests for core/agent_activity.js (passive local agent detection, zero tokens).
 * Run: node tests/agent_activity.test.js
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const TMP_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aigauge-activity-'));
const {
  detectAllActivity,
  detectClaudeActivity,
  detectAntigravityActivity,
  detectCodexActivity,
  detectCursorActivity,
  detectCopilotActivity,
  readTailLines,
  ACTIVE_POLL_SECONDS,
  IDLE_POLL_SECONDS
} = require('../core/agent_activity');

function setMtime(filePath, mtimeMs) {
  const sec = mtimeMs / 1000;
  fs.utimesSync(filePath, sec, sec);
}

function writeJsonl(filePath, objects, mtimeMs) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, objects.map(o => JSON.stringify(o)).join('\n') + '\n', 'utf8');
  if (typeof mtimeMs === 'number') setMtime(filePath, mtimeMs);
}

const tests = [];
const test = (n, f) => tests.push({ n, f });
const T0 = 1_795_500_000_000;

function makeSandbox(name) {
  const root = path.join(TMP_HOME, name);
  fs.mkdirSync(root, { recursive: true });
  return {
    homeDir: root,
    configDir: path.join(root, '.config', 'UniversalAIQuota'),
    claudeDir: path.join(root, '.claude'),
    desktopClaudeDir: path.join(root, 'ClaudeDesktop'),
    antigravityDir: path.join(root, '.gemini', 'antigravity'),
    codexDir: path.join(root, '.codex'),
    cursorDir: path.join(root, 'Cursor', 'User', 'globalStorage'),
    copilotDir: path.join(root, 'Code', 'User', 'globalStorage', 'github.copilot-chat')
  };
}

test('readTailLines reads only tail of large files (>32KB) without dropping last entries', () => {
  const sb = makeSandbox('tail');
  const fp = path.join(sb.homeDir, 'big.jsonl');
  const padLine = JSON.stringify({ type: 'progress', padding: 'x'.repeat(500) });
  const lines = [];
  for (let i = 0; i < 80; i++) lines.push(padLine);
  lines.push(JSON.stringify({ type: 'user', marker: 'LAST_ENTRY' }));
  fs.writeFileSync(fp, lines.join('\n') + '\n', 'utf8');
  assert.ok(fs.statSync(fp).size > 32768);
  const tail = readTailLines(fp, 16384, 5);
  assert.strictEqual(tail.length, 5);
  assert.strictEqual(JSON.parse(tail[tail.length - 1]).marker, 'LAST_ENTRY');
});

test('Claude Code: fresh tool_use (<=20s) is working; >20s..10m is waiting; AskUserQuestion is waiting', () => {
  const sb = makeSandbox('claude-tools');
  const fp = path.join(sb.claudeDir, 'projects', '-Volumes-ED01-ai-gauge', 's1.jsonl');

  writeJsonl(fp, [
    { type: 'user', cwd: '/Volumes/ED01/AntiGravity/ai_gauge', message: { role: 'user', content: 'run' } },
    { type: 'assistant', message: { role: 'assistant', stop_reason: 'tool_use', content: [{ type: 'tool_use', name: 'Bash' }] } }
  ], T0 - 5000);
  let res = detectClaudeActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'working');
  assert.strictEqual(res.project, 'ai_gauge');
  assert.match(res.summary, /Running Bash/);

  // Same tool_use sitting for 45s -> waiting for approval
  setMtime(fp, T0 - 45_000);
  res = detectClaudeActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'waiting');
  assert.match(res.summary, /Waiting approval \(Bash\)/);

  // AskUserQuestion / ExitPlanMode stays waiting up to 15 min
  writeJsonl(fp, [
    { type: 'assistant', cwd: '/work/my_app', message: { role: 'assistant', stop_reason: 'tool_use', content: [{ type: 'tool_use', name: 'AskUserQuestion' }] } }
  ], T0 - 5000);
  res = detectClaudeActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'waiting');
  assert.strictEqual(res.project, 'my_app');
  assert.strictEqual(res.summary, 'Waiting for your input');

  writeJsonl(fp, [
    { type: 'assistant', cwd: '/work/my_app', message: { role: 'assistant', stop_reason: 'tool_use', content: [{ type: 'tool_use', name: 'ExitPlanMode' }] } }
  ], T0 - 120_000);
  res = detectClaudeActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'waiting');
});

test('Claude Code: skips trailing housekeeping events and handles end_turn / stop_hook_summary as idle', () => {
  const sb = makeSandbox('claude-housekeeping');
  const fp = path.join(sb.claudeDir, 'projects', '-work-proj', 's2.jsonl');

  // Trailing cost-state after tool_use should still see tool_use
  writeJsonl(fp, [
    { type: 'assistant', cwd: '/work/proj', message: { role: 'assistant', stop_reason: 'tool_use', content: [{ type: 'tool_use', name: 'Edit' }] } },
    { type: 'cost-state', totalCostUSD: 1.2 },
    { type: 'last-prompt', lastPrompt: 'fix' }
  ], T0 - 3000);
  let res = detectClaudeActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'working');
  assert.match(res.summary, /Edit/);

  // end_turn followed by stop_hook_summary & cost-state -> idle
  writeJsonl(fp, [
    { type: 'assistant', cwd: '/work/proj', message: { role: 'assistant', stop_reason: 'end_turn', content: [{ type: 'text', text: 'done' }] } },
    { type: 'system', subtype: 'stop_hook_summary' },
    { type: 'cost-state', totalCostUSD: 1.4 }
  ], T0 - 2000);
  res = detectClaudeActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'idle');
  assert.strictEqual(res.detail, '');

  // Secondary check: recent Claude Desktop plan-usage-history.json -> working
  const desktopHist = path.join(sb.desktopClaudeDir, 'plan-usage-history.json');
  fs.mkdirSync(sb.desktopClaudeDir, { recursive: true });
  fs.writeFileSync(desktopHist, JSON.stringify({ samples: [{ t: T0 - 5000 }] }), 'utf8');
  setMtime(desktopHist, T0 - 5000);
  res = detectClaudeActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'working');
  assert.strictEqual(res.project, 'Claude Desktop');
});

test('Antigravity transcript: WAITING_FOR_USER/ask_question -> waiting; active tools -> working; DONE without tools -> idle', () => {
  const sb = makeSandbox('agy');
  const fp = path.join(sb.antigravityDir, 'brain', 'conv-1', '.system_generated', 'logs', 'transcript.jsonl');

  writeJsonl(fp, [
    { type: 'PLANNER_RESPONSE', status: 'DONE', tool_calls: [{ name: 'ask_question' }] }
  ], T0 - 60_000);
  let res = detectAntigravityActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'waiting');

  writeJsonl(fp, [
    { type: 'USER_INPUT', status: 'DONE' }
  ], T0 - 4000);
  res = detectAntigravityActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'working');

  writeJsonl(fp, [
    { type: 'PLANNER_RESPONSE', status: 'DONE', tool_calls: [{ name: 'run_command' }] }
  ], T0 - 6000);
  res = detectAntigravityActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'working');
  assert.match(res.summary, /run_command/);

  writeJsonl(fp, [
    { type: 'PLANNER_RESPONSE', status: 'DONE', tool_calls: [] }
  ], T0 - 2000);
  res = detectAntigravityActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'idle');
});

test('Codex sessions: approval -> waiting, exec_command -> working, task_complete -> idle, WAL fallback -> working', () => {
  const sb = makeSandbox('codex');
  const fp = path.join(sb.codexDir, 'sessions', '2026', '11', '23', 'rollout-1.jsonl');

  writeJsonl(fp, [
    { type: 'event_msg', payload: { type: 'exec_approval_request', cwd: '/tmp/repo' } }
  ], T0 - 30_000);
  let res = detectCodexActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'waiting');

  writeJsonl(fp, [
    { type: 'event_msg', payload: { type: 'exec_command' }, cwd: '/tmp/repo' }
  ], T0 - 5000);
  res = detectCodexActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'working');
  assert.strictEqual(res.project, 'repo');

  writeJsonl(fp, [
    { type: 'event_msg', payload: { type: 'task_complete' } }
  ], T0 - 3000);
  res = detectCodexActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'idle');

  // WAL fallback older than task_complete stays idle; WAL newer than task_complete -> working
  const wal = path.join(sb.codexDir, 'sqlite', 'codex.db-wal');
  fs.mkdirSync(path.dirname(wal), { recursive: true });
  fs.writeFileSync(wal, 'wal', 'utf8');
  setMtime(wal, T0 - 4000);
  res = detectCodexActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'idle');

  setMtime(wal, T0 - 1000);
  res = detectCodexActivity({ ...sb, now: T0 });
  assert.strictEqual(res.status, 'working');
});

test('Cursor and Copilot detect active local file mtime and become idle when stale', () => {
  const sb = makeSandbox('cursor-copilot');
  const cDb = path.join(sb.cursorDir, 'state.vscdb-wal');
  fs.mkdirSync(sb.cursorDir, { recursive: true });
  fs.writeFileSync(cDb, 'wal', 'utf8');
  setMtime(cDb, T0 - 4000);
  assert.strictEqual(detectCursorActivity({ ...sb, now: T0 }).status, 'working');
  setMtime(cDb, T0 - 60_000);
  assert.strictEqual(detectCursorActivity({ ...sb, now: T0 }).status, 'idle');

  const copFile = path.join(sb.copilotDir, 'state.json');
  fs.mkdirSync(sb.copilotDir, { recursive: true });
  fs.writeFileSync(copFile, '{}', 'utf8');
  setMtime(copFile, T0 - 4000);
  assert.strictEqual(detectCopilotActivity({ ...sb, now: T0 }).status, 'working');
  setMtime(copFile, T0 - 60_000);
  assert.strictEqual(detectCopilotActivity({ ...sb, now: T0 }).status, 'idle');
});

test('detectAllActivity computes priority (waiting > working > idle), adaptive polling and state transitions', () => {
  const sb = makeSandbox('all');
  const claudeFp = path.join(sb.claudeDir, 'projects', '-app', 's.jsonl');
  const agyFp = path.join(sb.antigravityDir, 'brain', 'c1', '.system_generated', 'logs', 'transcript.jsonl');

  // 1. All idle -> 300s polling
  let out = detectAllActivity({ ...sb, now: T0 });
  assert.strictEqual(out.overall_status, 'idle');
  assert.strictEqual(out.recommended_poll_seconds, IDLE_POLL_SECONDS);
  assert.strictEqual(out.transition_to_idle, false);
  assert.strictEqual(out.transition_to_active, false);

  // 2. Claude becomes working -> idle -> active transition + 30s polling
  writeJsonl(claudeFp, [
    { type: 'assistant', cwd: '/tmp/app', message: { role: 'assistant', stop_reason: 'tool_use', content: [{ type: 'tool_use', name: 'Bash' }] } }
  ], T0 + 1000);
  out = detectAllActivity({ ...sb, now: T0 + 4000 });
  assert.strictEqual(out.overall_status, 'working');
  assert.strictEqual(out.working_count, 1);
  assert.strictEqual(out.recommended_poll_seconds, ACTIVE_POLL_SECONDS);
  assert.strictEqual(out.transition_to_active, true);
  assert.strictEqual(out.transition_to_idle, false);

  // 3. Antigravity is waiting while Claude is working -> overall priority is waiting
  writeJsonl(agyFp, [
    { type: 'PLANNER_RESPONSE', status: 'WAITING_FOR_USER', tool_calls: [] }
  ], T0 + 5000);
  out = detectAllActivity({ ...sb, now: T0 + 8000 });
  assert.strictEqual(out.overall_status, 'waiting');
  assert.strictEqual(out.working_count, 1);
  assert.strictEqual(out.waiting_count, 1);
  assert.strictEqual(out.active_count, 2);

  // 4. Claude finishes turn (working -> idle) -> transition_to_idle = true
  writeJsonl(claudeFp, [
    { type: 'assistant', cwd: '/tmp/app', message: { role: 'assistant', stop_reason: 'end_turn', content: [{ type: 'text', text: 'ok' }] } }
  ], T0 + 9000);
  writeJsonl(agyFp, [
    { type: 'PLANNER_RESPONSE', status: 'DONE', tool_calls: [] }
  ], T0 + 9000);
  out = detectAllActivity({ ...sb, now: T0 + 12_000 });
  assert.strictEqual(out.overall_status, 'idle');
  assert.strictEqual(out.recommended_poll_seconds, IDLE_POLL_SECONDS);
  assert.strictEqual(out.transition_to_idle, true);
});

test('engine.js --activity-only outputs valid activity JSON without network', () => {
  const enginePath = path.resolve(__dirname, '../core/engine.js');
  const raw = execFileSync(process.execPath, [enginePath, '--activity-only'], {
    encoding: 'utf8',
    env: { ...process.env, HOME: TMP_HOME, USERPROFILE: TMP_HOME }
  });
  const parsed = JSON.parse(raw);
  assert.ok(['working', 'waiting', 'idle'].includes(parsed.overall_status));
  assert.strictEqual(parsed.recommended_poll_seconds, IDLE_POLL_SECONDS);
  assert.ok(parsed.providers && parsed.providers.claude_pro && parsed.providers.antigravity);
});

let failed = 0;
for (const t of tests) {
  try {
    t.f();
    console.log('  ok   ' + t.n);
  } catch (e) {
    failed++;
    console.log('  FAIL ' + t.n + '\n       ' + (e && e.stack ? e.stack : e));
  }
}
fs.rmSync(TMP_HOME, { recursive: true, force: true });
console.log(failed ? `\n${failed} test(s) failed` : `\nAll ${tests.length} tests passed`);
process.exit(failed ? 1 : 0);
