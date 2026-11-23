/**
 * Passive Live Agent Activity Detector (Zero Tokens, Zero Network)
 *
 * Inspects local session logs, transcripts and IDE state files (mtime + tail JSONL)
 * to determine whether each AI agent is `working`, `waiting` (needs user input/approval),
 * or `idle`. Drives adaptive polling and live UI indicators across macOS, Windows and Linux.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const ACTIVE_POLL_SECONDS = 30;
const IDLE_POLL_SECONDS = 300;

const CLAUDE_HOUSEKEEPING_TYPES = new Set([
  'cost-state',
  'last-prompt',
  'file-history-snapshot',
  'queue-operation',
  'attachment'
]);

const CLAUDE_USER_PROMPT_TOOLS = new Set([
  'AskUserQuestion',
  'ExitPlanMode',
  'EnterPlanMode'
]);

const CODEX_WAITING_EVENTS = new Set([
  'request_user_input',
  'approval_required',
  'exec_approval_request',
  'apply_patch_approval_request'
]);

const CODEX_COMPLETE_EVENTS = new Set([
  'task_complete',
  'turn_aborted',
  'session_end'
]);

const CODEX_ACTIVE_EVENTS = new Set([
  'task_started',
  'user_message',
  'function_call',
  'exec_command',
  'agent_reasoning',
  'reasoning'
]);

function makeIdleResult(updatedAtMs = null, now = Date.now(), project = null) {
  return {
    status: 'idle',
    sessions_count: 0,
    project: project || null,
    summary: 'Idle',
    detail: '',
    updated_at_ms: updatedAtMs,
    age_seconds: updatedAtMs ? Math.max(0, Math.round((now - updatedAtMs) / 1000)) : null
  };
}

function makeActivityResult(status, project, summary, updatedAtMs, now) {
  if (status === 'idle') {
    return makeIdleResult(updatedAtMs, now, project);
  }
  const proj = project || null;
  const detail = proj ? `${proj} · ${summary}` : summary;
  return {
    status,
    sessions_count: 1,
    project: proj,
    summary,
    detail,
    updated_at_ms: updatedAtMs,
    age_seconds: updatedAtMs ? Math.max(0, Math.round((now - updatedAtMs) / 1000)) : null
  };
}

/**
 * Reads only the tail of a file so multi-megabyte JSONL transcripts stay fast.
 */
function readTailLines(filePath, maxBytes = 16384, maxLines = 25) {
  let fd = null;
  try {
    fd = fs.openSync(filePath, 'r');
    const stat = fs.fstatSync(fd);
    if (!stat || stat.size <= 0) return [];
    const readLen = Math.min(stat.size, maxBytes);
    const startOffset = Math.max(0, stat.size - readLen);
    const buf = Buffer.alloc(readLen);
    fs.readSync(fd, buf, 0, readLen, startOffset);
    let text = buf.toString('utf8').replace(/^\uFEFF/, '');
    let lines = text.split(/\r?\n/);
    if (stat.size > maxBytes && lines.length > 0) {
      lines = lines.slice(1);
    }
    const clean = lines.map(l => l.trim()).filter(Boolean);
    return clean.slice(-maxLines);
  } catch (_) {
    return [];
  } finally {
    if (fd !== null) {
      try { fs.closeSync(fd); } catch (_) {}
    }
  }
}

function parseJsonLines(lines) {
  const parsed = [];
  for (const line of lines) {
    try {
      const obj = JSON.parse(line);
      if (obj && typeof obj === 'object') parsed.push(obj);
    } catch (_) {}
  }
  return parsed;
}

function findNewestJsonl(rootDir, maxDepth = 2) {
  if (!rootDir || !fs.existsSync(rootDir)) return null;
  let newest = null;

  function walk(dir, depth) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (_) {
      return;
    }
    for (const ent of entries) {
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (depth < maxDepth) walk(full, depth + 1);
      } else if (ent.isFile() && ent.name.endsWith('.jsonl')) {
        try {
          const st = fs.statSync(full);
          if (!newest || st.mtimeMs > newest.mtimeMs) {
            newest = { filePath: full, mtimeMs: st.mtimeMs, parentDir: dir };
          }
        } catch (_) {}
      }
    }
  }

  walk(rootDir, 0);
  return newest;
}

function projectNameFromClaudeDir(folderPath) {
  const base = path.basename(folderPath || '');
  if (!base || base === '-') return null;
  const parts = base.split('-').filter(Boolean);
  return parts.length > 0 ? parts[parts.length - 1] : null;
}

function defaultDesktopClaudeDir(homeDir) {
  if (process.platform === 'darwin') {
    return path.join(homeDir, 'Library', 'Application Support', 'Claude');
  }
  if (process.platform === 'win32') {
    return path.join(process.env.APPDATA || path.join(homeDir, 'AppData', 'Roaming'), 'Claude');
  }
  return path.join(homeDir, '.config', 'Claude');
}

function detectClaudeActivity(opts = {}) {
  const homeDir = opts.homeDir || os.homedir();
  const now = typeof opts.now === 'number' ? opts.now : Date.now();
  const claudeDir = opts.claudeDir || process.env.CLAUDE_CONFIG_DIR || path.join(homeDir, '.claude');
  const projectsDir = path.join(claudeDir, 'projects');

  const newest = findNewestJsonl(projectsDir, 2);
  let lastMtimeMs = newest ? newest.mtimeMs : null;
  let detectedProject = newest ? projectNameFromClaudeDir(newest.parentDir) : null;

  if (newest) {
    const entries = parseJsonLines(readTailLines(newest.filePath, 16384, 25));
    for (let i = entries.length - 1; i >= 0; i--) {
      if (typeof entries[i].cwd === 'string' && entries[i].cwd.trim()) {
        detectedProject = path.basename(entries[i].cwd.trim()) || detectedProject;
        break;
      }
    }

    let last = null;
    for (let i = entries.length - 1; i >= 0; i--) {
      const e = entries[i];
      if (!CLAUDE_HOUSEKEEPING_TYPES.has(e.type)) {
        last = e;
        break;
      }
    }

    const ageMs = Math.max(0, now - newest.mtimeMs);
    let claudeCodeDone = false;

    if (last) {
      if (last.type === 'assistant' && last.message && last.message.stop_reason === 'tool_use') {
        const blocks = Array.isArray(last.message.content) ? last.message.content : [];
        let toolName = '';
        for (let i = blocks.length - 1; i >= 0; i--) {
          if (blocks[i] && blocks[i].type === 'tool_use') {
            toolName = blocks[i].name || '';
            break;
          }
        }
        if (CLAUDE_USER_PROMPT_TOOLS.has(toolName)) {
          if (ageMs <= 15 * 60 * 1000) {
            return makeActivityResult('waiting', detectedProject, 'Waiting for your input', newest.mtimeMs, now);
          }
          claudeCodeDone = true;
        } else if (ageMs <= 20 * 1000) {
          const sum = toolName ? `Running ${toolName}` : 'Running tool';
          return makeActivityResult('working', detectedProject, sum, newest.mtimeMs, now);
        } else if (ageMs <= 10 * 60 * 1000) {
          const sum = toolName ? `Waiting approval (${toolName})` : 'Waiting for approval';
          return makeActivityResult('waiting', detectedProject, sum, newest.mtimeMs, now);
        } else {
          claudeCodeDone = true;
        }
      } else if (
        last.type === 'api-request' ||
        last.type === 'user' ||
        last.type === 'progress' ||
        (last.type === 'assistant' && (!last.message || !last.message.stop_reason))
      ) {
        if (ageMs <= 90 * 1000) {
          const sum = last.type === 'user' ? 'Generating response' : 'Working';
          return makeActivityResult('working', detectedProject, sum, newest.mtimeMs, now);
        }
        claudeCodeDone = true;
      } else if (
        (last.type === 'assistant' && last.message && last.message.stop_reason === 'end_turn') ||
        (last.type === 'system' && (last.subtype === 'stop_hook_summary' || last.subtype === 'turn_duration'))
      ) {
        claudeCodeDone = true;
      }
    }

    if (!claudeCodeDone && ageMs <= 15 * 1000) {
      return makeActivityResult('working', detectedProject, 'Working', newest.mtimeMs, now);
    }
  }

  // Secondary check: Claude Desktop active session file
  try {
    const desktopDir = opts.desktopClaudeDir || defaultDesktopClaudeDir(homeDir);
    const historyFile = path.join(desktopDir, 'plan-usage-history.json');
    if (fs.existsSync(historyFile)) {
      const st = fs.statSync(historyFile);
      const ageMs = Math.max(0, now - st.mtimeMs);
      if (ageMs <= 20 * 1000) {
        return makeActivityResult('working', 'Claude Desktop', 'Active desktop session', st.mtimeMs, now);
      }
      if (!lastMtimeMs || st.mtimeMs > lastMtimeMs) {
        lastMtimeMs = st.mtimeMs;
      }
    }
  } catch (_) {}

  return makeIdleResult(lastMtimeMs, now, detectedProject);
}

function detectAntigravityActivity(opts = {}) {
  const homeDir = opts.homeDir || os.homedir();
  const now = typeof opts.now === 'number' ? opts.now : Date.now();
  const agyDir = opts.antigravityDir || path.join(homeDir, '.gemini', 'antigravity');
  const brainDir = path.join(agyDir, 'brain');

  if (!fs.existsSync(brainDir)) {
    return makeIdleResult(null, now, null);
  }

  let newest = null;
  try {
    for (const ent of fs.readdirSync(brainDir, { withFileTypes: true })) {
      if (!ent.isDirectory()) continue;
      const candidate = path.join(brainDir, ent.name, '.system_generated', 'logs', 'transcript.jsonl');
      if (!fs.existsSync(candidate)) continue;
      try {
        const st = fs.statSync(candidate);
        if (!newest || st.mtimeMs > newest.mtimeMs) {
          newest = { filePath: candidate, mtimeMs: st.mtimeMs };
        }
      } catch (_) {}
    }
  } catch (_) {}

  if (!newest) {
    return makeIdleResult(null, now, null);
  }

  const entries = parseJsonLines(readTailLines(newest.filePath, 16384, 20));
  const ageMs = Math.max(0, now - newest.mtimeMs);
  let project = 'Antigravity IDE';
  for (let i = entries.length - 1; i >= 0; i--) {
    const ws = entries[i].workspace || entries[i].cwd || entries[i].project;
    if (typeof ws === 'string' && ws.trim()) {
      project = path.basename(ws.trim()) || project;
      break;
    }
  }

  const last = entries.length > 0 ? entries[entries.length - 1] : null;
  if (!last) {
    if (ageMs <= 15 * 1000) {
      return makeActivityResult('working', project, 'Agent running', newest.mtimeMs, now);
    }
    return makeIdleResult(newest.mtimeMs, now, project);
  }

  const tools = Array.isArray(last.tool_calls)
    ? last.tool_calls.map(t => (t && (t.name || t.tool_name)) || '').filter(Boolean)
    : [];

  if (
    last.status === 'WAITING_FOR_USER' ||
    last.status === 'BLOCKED' ||
    (last.type === 'PLANNER_RESPONSE' && tools.includes('ask_question'))
  ) {
    if (ageMs <= 15 * 60 * 1000) {
      return makeActivityResult('waiting', project, 'Waiting for your response', newest.mtimeMs, now);
    }
    return makeIdleResult(newest.mtimeMs, now, project);
  }

  if (last.type === 'USER_INPUT' && ageMs <= 90 * 1000) {
    return makeActivityResult('working', project, 'Processing prompt', newest.mtimeMs, now);
  }

  if (last.status === 'RUNNING' || last.status === 'IN_PROGRESS' || last.status === 'PENDING') {
    if (ageMs <= 120 * 1000) {
      return makeActivityResult('working', project, 'Agent running', newest.mtimeMs, now);
    }
    return makeIdleResult(newest.mtimeMs, now, project);
  }

  if (last.type === 'PLANNER_RESPONSE') {
    if (tools.length > 0 && ageMs <= 45 * 1000) {
      return makeActivityResult('working', project, `Running ${tools[0]}`, newest.mtimeMs, now);
    }
    if (tools.length === 0 && last.status === 'DONE') {
      return makeIdleResult(newest.mtimeMs, now, project);
    }
  }

  if (last.type === 'GENERIC' && ageMs <= 30 * 1000) {
    return makeActivityResult('working', project, 'Executing tools', newest.mtimeMs, now);
  }

  return makeIdleResult(newest.mtimeMs, now, project);
}

function detectCodexActivity(opts = {}) {
  const homeDir = opts.homeDir || os.homedir();
  const now = typeof opts.now === 'number' ? opts.now : Date.now();
  const codexDir = opts.codexDir || path.join(homeDir, '.codex');
  const sessionsDir = path.join(codexDir, 'sessions');

  const newest = findNewestJsonl(sessionsDir, 4);
  let lastMtimeMs = newest ? newest.mtimeMs : null;
  let project = 'Codex';

  let codexTurnDone = false;
  if (newest) {
    const entries = parseJsonLines(readTailLines(newest.filePath, 16384, 20));
    const ageMs = Math.max(0, now - newest.mtimeMs);
    for (let i = entries.length - 1; i >= 0; i--) {
      const cwd = entries[i].cwd || entries[i].payload?.cwd;
      if (typeof cwd === 'string' && cwd.trim()) {
        project = path.basename(cwd.trim()) || project;
        break;
      }
    }

    const last = entries.length > 0 ? entries[entries.length - 1] : null;
    if (last) {
      const evType = String(last.payload?.type || last.type || '').toLowerCase();
      if (CODEX_WAITING_EVENTS.has(evType)) {
        if (ageMs <= 15 * 60 * 1000) {
          return makeActivityResult('waiting', project, 'Waiting for approval', newest.mtimeMs, now);
        }
        codexTurnDone = true;
      } else if (CODEX_COMPLETE_EVENTS.has(evType)) {
        codexTurnDone = true;
      } else if (CODEX_ACTIVE_EVENTS.has(evType)) {
        if (ageMs <= 45 * 1000) {
          return makeActivityResult('working', project, 'Running Codex task', newest.mtimeMs, now);
        }
        codexTurnDone = true;
      }
    }

    if (!codexTurnDone && ageMs <= 15 * 1000) {
      return makeActivityResult('working', project, 'Running Codex task', newest.mtimeMs, now);
    }
  }

  // Fallback: SQLite WAL files touched by active Codex CLI / Desktop
  const walCandidates = [
    path.join(codexDir, 'sqlite', 'codex.db-wal'),
    path.join(codexDir, 'logs_2.sqlite-wal')
  ];
  for (const wf of walCandidates) {
    try {
      if (fs.existsSync(wf)) {
        const st = fs.statSync(wf);
        if (!lastMtimeMs || st.mtimeMs > lastMtimeMs) lastMtimeMs = st.mtimeMs;
        const newerThanCompletedTurn = !codexTurnDone || !newest || st.mtimeMs > newest.mtimeMs;
        if (Math.max(0, now - st.mtimeMs) <= 20 * 1000 && newerThanCompletedTurn) {
          return makeActivityResult('working', 'Codex', 'Active Codex session', st.mtimeMs, now);
        }
      }
    } catch (_) {}
  }

  return makeIdleResult(lastMtimeMs, now, project);
}

function defaultCursorStorageDirs(homeDir) {
  if (process.platform === 'darwin') {
    return [path.join(homeDir, 'Library', 'Application Support', 'Cursor', 'User', 'globalStorage')];
  }
  if (process.platform === 'win32') {
    const appData = process.env.APPDATA || path.join(homeDir, 'AppData', 'Roaming');
    const localApp = process.env.LOCALAPPDATA || path.join(homeDir, 'AppData', 'Local');
    return [
      path.join(appData, 'Cursor', 'User', 'globalStorage'),
      path.join(localApp, 'Cursor', 'User', 'globalStorage')
    ];
  }
  return [path.join(homeDir, '.config', 'Cursor', 'User', 'globalStorage')];
}

function detectCursorActivity(opts = {}) {
  const homeDir = opts.homeDir || os.homedir();
  const now = typeof opts.now === 'number' ? opts.now : Date.now();
  const dirs = opts.cursorDir ? [opts.cursorDir] : defaultCursorStorageDirs(homeDir);

  let latestMtime = null;
  for (const dir of dirs) {
    for (const fname of ['state.vscdb-wal', 'state.vscdb']) {
      const fp = path.join(dir, fname);
      try {
        if (fs.existsSync(fp)) {
          const st = fs.statSync(fp);
          if (!latestMtime || st.mtimeMs > latestMtime) {
            latestMtime = st.mtimeMs;
          }
        }
      } catch (_) {}
    }
  }

  if (latestMtime && Math.max(0, now - latestMtime) <= 15 * 1000) {
    return makeActivityResult('working', 'Cursor IDE', 'Active editor session', latestMtime, now);
  }
  return makeIdleResult(latestMtime, now, 'Cursor IDE');
}

function defaultCopilotStorageDirs(homeDir) {
  if (process.platform === 'darwin') {
    return [path.join(homeDir, 'Library', 'Application Support', 'Code', 'User', 'globalStorage', 'github.copilot-chat')];
  }
  if (process.platform === 'win32') {
    const appData = process.env.APPDATA || path.join(homeDir, 'AppData', 'Roaming');
    return [path.join(appData, 'Code', 'User', 'globalStorage', 'github.copilot-chat')];
  }
  return [path.join(homeDir, '.config', 'Code', 'User', 'globalStorage', 'github.copilot-chat')];
}

function detectCopilotActivity(opts = {}) {
  const homeDir = opts.homeDir || os.homedir();
  const now = typeof opts.now === 'number' ? opts.now : Date.now();
  const dirs = opts.copilotDir ? [opts.copilotDir] : defaultCopilotStorageDirs(homeDir);

  let latestMtime = null;
  for (const dir of dirs) {
    if (!dir || !fs.existsSync(dir)) continue;
    try {
      const stDir = fs.statSync(dir);
      if (!latestMtime || stDir.mtimeMs > latestMtime) latestMtime = stDir.mtimeMs;
      for (const ent of fs.readdirSync(dir)) {
        try {
          const st = fs.statSync(path.join(dir, ent));
          if (!latestMtime || st.mtimeMs > latestMtime) latestMtime = st.mtimeMs;
        } catch (_) {}
      }
    } catch (_) {}
  }

  if (latestMtime && Math.max(0, now - latestMtime) <= 15 * 1000) {
    return makeActivityResult('working', 'VS Code', 'Copilot active', latestMtime, now);
  }
  return makeIdleResult(latestMtime, now, 'VS Code');
}

function detectAllActivity(opts = {}) {
  const homeDir = opts.homeDir || os.homedir();
  const now = typeof opts.now === 'number' ? opts.now : Date.now();
  const configDir = opts.configDir || path.join(homeDir, '.config', 'UniversalAIQuota');
  const statePath = path.join(configDir, 'activity_state.json');

  const providers = {
    antigravity: detectAntigravityActivity(opts),
    claude_pro: detectClaudeActivity(opts),
    chatgpt_subscription: detectCodexActivity(opts),
    cursor: detectCursorActivity(opts),
    github_copilot: detectCopilotActivity(opts)
  };

  let workingCount = 0;
  let waitingCount = 0;
  for (const key of Object.keys(providers)) {
    const st = providers[key].status;
    if (st === 'working') workingCount++;
    else if (st === 'waiting') waitingCount++;
  }

  const activeCount = workingCount + waitingCount;
  const overallStatus = waitingCount > 0 ? 'waiting' : (workingCount > 0 ? 'working' : 'idle');
  const recommendedPollSeconds = activeCount > 0 ? ACTIVE_POLL_SECONDS : IDLE_POLL_SECONDS;

  let prev = null;
  try {
    if (fs.existsSync(statePath)) {
      prev = JSON.parse(fs.readFileSync(statePath, 'utf8').replace(/^\uFEFF/, ''));
    }
  } catch (_) {}

  let transitionToIdle = false;
  let transitionToActive = false;
  if (prev && typeof prev === 'object') {
    const prevProviders = prev.providers || {};
    for (const key of Object.keys(providers)) {
      if (prevProviders[key] === 'working' && providers[key].status === 'idle') {
        transitionToIdle = true;
        break;
      }
    }
    if (prev.overall_status === 'idle' && overallStatus !== 'idle') {
      transitionToActive = true;
    }
  }

  if (opts.persistState !== false) {
    try {
      fs.mkdirSync(configDir, { recursive: true });
      const snapshot = {
        overall_status: overallStatus,
        providers: Object.fromEntries(
          Object.keys(providers).map(k => [k, providers[k].status])
        ),
        checked_at: now
      };
      fs.writeFileSync(statePath, JSON.stringify(snapshot), { encoding: 'utf8', mode: 0o600 });
    } catch (_) {}
  }

  return {
    overall_status: overallStatus,
    active_count: activeCount,
    working_count: workingCount,
    waiting_count: waitingCount,
    recommended_poll_seconds: recommendedPollSeconds,
    transition_to_idle: transitionToIdle,
    transition_to_active: transitionToActive,
    checked_at: now,
    providers
  };
}

module.exports = {
  detectAllActivity,
  detectClaudeActivity,
  detectAntigravityActivity,
  detectCodexActivity,
  detectCursorActivity,
  detectCopilotActivity,
  readTailLines,
  ACTIVE_POLL_SECONDS,
  IDLE_POLL_SECONDS
};
