#!/usr/bin/env node

// ==============================================================================
// Pipeline Supervisor — Monitoring and Auto-Recovery
// ==============================================================================
//
// Pure Node.js daemon with ZERO npm dependencies. Uses only built-in modules.
//
// Features:
// - Polls pipeline-state.json every N seconds
// - Detects status changes and takes actions
// - Auto-restarts on failures (with max attempts)
// - Exponential backoff for token exhaustion
// - Telegram notifications (rich formatted messages)
// - Stall detection and recovery
// - Sequential feature execution
//
// Usage:
//   node supervisor.js                              — Monitor current pipeline
//   node supervisor.js --features contacts,deals    — Run features sequentially
//   node supervisor.js --once                       — Check state once and exit
//   node supervisor.js --status                     — Print current state
//
// ==============================================================================

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const https = require('https');
const { URL } = require('url');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const STATE_FILE = path.join(PROJECT_ROOT, 'pipeline-state.json');
const LOG_FILE = path.join(PROJECT_ROOT, 'logs', 'supervisor.log');
const CONFIG_FILE = path.join(PROJECT_ROOT, 'pipeline.yaml');

// Colors
const RESET = '\x1b[0m';
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const BLUE = '\x1b[34m';
const CYAN = '\x1b[36m';
const BOLD = '\x1b[1m';

// ==============================================================================
// Configuration
// ==============================================================================

const DEFAULT_CONFIG = {
  poll_interval_seconds: 30,
  max_restarts: 3,
  stall_timeout_minutes: 30,
  backoff_minutes: [5, 10, 20, 40, 60],
  project_name: process.env.PIPELINE_PROJECT_NAME || 'Pipeline',
  telegram: {
    bot_token: process.env.TELEGRAM_BOT_TOKEN || '',
    chat_id: process.env.TELEGRAM_CHAT_ID || '',
  },
};

let CONFIG = { ...DEFAULT_CONFIG };

// State tracking
let restart_count = 0;
let backoff_index = 0;
let pipeline_process = null;

// ==============================================================================
// Utility Functions
// ==============================================================================

function log(message) {
  const timestamp = new Date().toISOString();
  const logLine = `[${timestamp}] ${message}\n`;

  // Ensure logs directory exists
  const logsDir = path.dirname(LOG_FILE);
  if (!fs.existsSync(logsDir)) {
    fs.mkdirSync(logsDir, { recursive: true });
  }

  fs.appendFileSync(LOG_FILE, logLine);
  console.log(`${CYAN}[${timestamp}]${RESET} ${message}`);
}

function logError(message) {
  log(`${RED}ERROR: ${message}${RESET}`);
}

function logSuccess(message) {
  log(`${GREEN}SUCCESS: ${message}${RESET}`);
}

function logWarning(message) {
  log(`${YELLOW}WARNING: ${message}${RESET}`);
}

function parseYaml(content, key) {
  // Simple YAML parser for "key: value" patterns
  const regex = new RegExp(`^\\s*${key}:\\s*(.+)$`, 'm');
  const match = content.match(regex);
  if (!match) return null;

  let value = match[1].trim();
  // Remove quotes if present
  value = value.replace(/^["']|["']$/g, '');
  return value;
}

function loadConfig() {
  try {
    if (!fs.existsSync(CONFIG_FILE)) {
      logWarning('pipeline.yaml not found, using defaults');
      return;
    }

    const yamlContent = fs.readFileSync(CONFIG_FILE, 'utf-8');

    // Parse supervisor section
    const pollInterval = parseYaml(yamlContent, 'poll_interval_seconds');
    const maxRestarts = parseYaml(yamlContent, 'max_restarts');
    const stallTimeout = parseYaml(yamlContent, 'stall_timeout_minutes');
    const botToken = parseYaml(yamlContent, 'bot_token');
    const chatId = parseYaml(yamlContent, 'chat_id');
    const projectName = parseYaml(yamlContent, 'project_name');

    if (pollInterval) CONFIG.poll_interval_seconds = parseInt(pollInterval, 10);
    if (maxRestarts) CONFIG.max_restarts = parseInt(maxRestarts, 10);
    if (stallTimeout) CONFIG.stall_timeout_minutes = parseInt(stallTimeout, 10);
    if (botToken) CONFIG.telegram.bot_token = botToken;
    if (chatId) CONFIG.telegram.chat_id = chatId;
    if (projectName) CONFIG.project_name = projectName;

    log('Configuration loaded from pipeline.yaml');
  } catch (error) {
    logWarning(`Failed to load config: ${error.message}`);
  }
}

// ==============================================================================
// Message Formatting Helpers
// ==============================================================================

function formatDuration(startedAt, endedAt) {
  if (!startedAt) return 'N/A';
  const start = new Date(startedAt);
  const end = endedAt ? new Date(endedAt) : new Date();
  const seconds = Math.floor((end - start) / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const secs = seconds % 60;
  if (minutes < 60) return `${minutes}m ${secs}s`;
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${hours}h ${mins}m`;
}

function formatStepsProgress(state) {
  // Support both boilerplate format (steps array in state) and CRM format (steps_completed string/array)
  const allSteps = state.steps
    ? state.steps.map(s => s.name || s)
    : ['PM', 'DR-SPEC', 'DEV', 'SEED', 'DR-IMPL', 'QA'];

  let completed = [];
  if (state.steps_completed) {
    completed = Array.isArray(state.steps_completed)
      ? state.steps_completed
      : state.steps_completed.split(' ').filter(Boolean);
  } else if (state.steps) {
    completed = state.steps.filter(s => s.status === 'completed').map(s => s.name || s);
  }

  return allSteps.map(step => {
    const name = typeof step === 'string' ? step : step.name;
    return completed.includes(name) ? `\u2705 ${name}` : `\u2B1C ${name}`;
  }).join('\n');
}

function formatTimestamp(isoString) {
  if (!isoString) return 'N/A';
  const d = new Date(isoString);
  return d.toLocaleString('it-IT', { timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit', second: '2-digit', day: '2-digit', month: '2-digit' });
}

function projectHeader() {
  return `\u{1F3D7} *${CONFIG.project_name}*`;
}

function getFeatureName(state) {
  return state.current_feature || state.feature || 'unknown';
}

// ==============================================================================
// Telegram Notifications
// ==============================================================================

function sendTelegram(message) {
  return new Promise((resolve) => {
    const { bot_token, chat_id } = CONFIG.telegram;

    if (!bot_token || !chat_id) {
      return resolve();
    }

    const url = `https://api.telegram.org/bot${bot_token}/sendMessage`;
    const payload = JSON.stringify({
      chat_id,
      text: message,
      parse_mode: 'Markdown',
    });

    const urlObj = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        if (res.statusCode === 200) {
          log('Telegram notification sent');
        } else {
          logError(`Telegram API error: ${res.statusCode} ${data}`);
        }
        resolve();
      });
    });

    req.on('error', (error) => {
      logError(`Telegram request failed: ${error.message}`);
      resolve();
    });

    req.write(payload);
    req.end();
  });
}

// ==============================================================================
// Pipeline State Management
// ==============================================================================

function readState() {
  try {
    if (!fs.existsSync(STATE_FILE)) {
      return null;
    }

    const content = fs.readFileSync(STATE_FILE, 'utf-8');
    return JSON.parse(content);
  } catch (error) {
    logError(`Failed to read state: ${error.message}`);
    return null;
  }
}

function isStalled(state) {
  if (!state || state.status !== 'running') {
    return false;
  }

  const lastUpdate = new Date(state.last_update || state.started_at);
  const now = new Date();
  const elapsedMinutes = (now - lastUpdate) / 1000 / 60;

  return elapsedMinutes > CONFIG.stall_timeout_minutes;
}

// ==============================================================================
// Pipeline Process Management
// ==============================================================================

function killPipeline(pid) {
  if (!pid) return;

  try {
    process.kill(pid, 'SIGTERM');
    log(`Killed pipeline process (PID: ${pid})`);
  } catch (error) {
    logWarning(`Failed to kill PID ${pid}: ${error.message}`);
  }
}

function restartPipeline(resume = false) {
  log(`Restarting pipeline (attempt ${restart_count + 1}/${CONFIG.max_restarts})${resume ? ' with --resume' : ''}`);

  const args = ['./pipeline.sh'];
  if (resume) args.push('--resume');

  const child = spawn('bash', args, {
    cwd: PROJECT_ROOT,
    stdio: 'inherit',
  });

  pipeline_process = child;

  child.on('exit', (code) => {
    log(`Pipeline exited with code ${code}`);
    pipeline_process = null;
  });

  restart_count++;
}

async function handleCompleted(state) {
  const feature = getFeatureName(state);
  logSuccess(`Feature ${feature} completed`);

  const duration = formatDuration(state.started_at, state.last_update);
  const steps = formatStepsProgress(state);
  const time = formatTimestamp(state.last_update);

  const summary = [
    `${projectHeader()}`,
    ``,
    `\u2705 *Feature completata!*`,
    ``,
    `\u{1F4CB} *Feature:* \`${feature}\``,
    `\u23F1 *Durata:* ${duration}`,
    `\u{1F552} *Completata:* ${time}`,
    ``,
    `*Progressi:*`,
    steps,
  ].join('\n');

  await sendTelegram(summary);

  // Reset restart counter on success
  restart_count = 0;
  backoff_index = 0;
}

async function handleFailed(state) {
  const feature = getFeatureName(state);
  logError(`Feature ${feature} failed (exit code: ${state.exit_code})`);

  const duration = formatDuration(state.started_at, state.last_update);
  const steps = formatStepsProgress(state);
  const failedStep = state.current_step || 'unknown';
  const time = formatTimestamp(state.last_update);

  if (restart_count >= CONFIG.max_restarts) {
    const message = [
      `${projectHeader()}`,
      ``,
      `\u274C *Pipeline FALLITA* \u2014 intervento manuale richiesto`,
      ``,
      `\u{1F4CB} *Feature:* \`${feature}\``,
      `\u{1F6D1} *Step fallito:* ${failedStep}`,
      `\u{1F4DF} *Exit code:* ${state.exit_code}`,
      `\u{1F504} *Tentativi:* ${restart_count}/${CONFIG.max_restarts} (max raggiunto)`,
      `\u23F1 *Durata:* ${duration}`,
      `\u{1F552} *Ora:* ${time}`,
      ``,
      `*Progressi:*`,
      steps,
      state.error ? `\n\u{1F4AC} *Errore:* ${state.error}` : '',
    ].filter(Boolean).join('\n');

    await sendTelegram(message);
    log('Max restarts reached, stopping');
    return;
  }

  const message = [
    `${projectHeader()}`,
    ``,
    `\u26A0\uFE0F *Pipeline fallita* \u2014 restart automatico`,
    ``,
    `\u{1F4CB} *Feature:* \`${feature}\``,
    `\u{1F6D1} *Step fallito:* ${failedStep}`,
    `\u{1F4DF} *Exit code:* ${state.exit_code}`,
    `\u{1F504} *Tentativo:* ${restart_count + 1}/${CONFIG.max_restarts}`,
    `\u23F1 *Durata finora:* ${duration}`,
    ``,
    `*Progressi:*`,
    steps,
    state.error ? `\n\u{1F4AC} *Errore:* ${state.error}` : '',
    ``,
    `\u{1F501} Riavvio con \`--resume\` in corso...`,
  ].filter(Boolean).join('\n');

  await sendTelegram(message);

  restartPipeline(true);
}

async function handleTokenExhausted(state) {
  const feature = getFeatureName(state);
  logWarning(`Token exhausted, applying backoff`);

  const backoffMinutes = CONFIG.backoff_minutes[Math.min(backoff_index, CONFIG.backoff_minutes.length - 1)];
  const steps = formatStepsProgress(state);
  const failedStep = state.current_step || 'unknown';
  const retryAt = new Date(Date.now() + backoffMinutes * 60 * 1000);
  const retryTime = retryAt.toLocaleString('it-IT', { timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit' });

  const message = [
    `${projectHeader()}`,
    ``,
    `\u23F3 *Token esauriti* \u2014 backoff automatico`,
    ``,
    `\u{1F4CB} *Feature:* \`${feature}\``,
    `\u{1F6D1} *Step interrotto:* ${failedStep}`,
    `\u{1F504} *Backoff:* ${backoffMinutes} minuti (livello ${backoff_index + 1}/${CONFIG.backoff_minutes.length})`,
    `\u23F0 *Prossimo retry:* ${retryTime}`,
    ``,
    `*Progressi:*`,
    steps,
    ``,
    `\u{1F4A1} _I backoff crescono: ${CONFIG.backoff_minutes.join(', ')} min_`,
  ].join('\n');

  await sendTelegram(message);

  log(`Waiting ${backoffMinutes} minutes...`);
  setTimeout(() => {
    backoff_index++;
    restartPipeline(true);
  }, backoffMinutes * 60 * 1000);
}

async function handleToolFailure(state) {
  const feature = getFeatureName(state);
  logError(`Tool failure detected (exit code: 76)`);

  const steps = formatStepsProgress(state);
  const failedStep = state.current_step || 'unknown';
  const canRestart = restart_count < CONFIG.max_restarts;

  const message = [
    `${projectHeader()}`,
    ``,
    `\uD83D\uDD27 *MCP Tool Failure*`,
    ``,
    `\u{1F4CB} *Feature:* \`${feature}\``,
    `\u{1F6D1} *Step fallito:* ${failedStep}`,
    `\u{1F504} *Tentativo:* ${restart_count + 1}/${CONFIG.max_restarts}`,
    ``,
    `*Progressi:*`,
    steps,
    state.error ? `\n\u{1F4AC} *Errore:* ${state.error}` : '',
    ``,
    canRestart ? `\u{1F501} Riavvio con \`--resume\` in corso...` : `\u274C Max restart raggiunto. Intervento manuale richiesto.`,
  ].filter(Boolean).join('\n');

  await sendTelegram(message);

  if (canRestart) {
    restartPipeline(true);
  } else {
    log('Max restarts reached after tool failure');
  }
}

async function handleFatal(state) {
  const feature = getFeatureName(state);
  logError(`Fatal error (exit code: 99) — DO NOT RESTART`);

  const steps = formatStepsProgress(state);
  const failedStep = state.current_step || 'unknown';
  const duration = formatDuration(state.started_at, state.last_update);
  const time = formatTimestamp(state.last_update);

  const message = [
    `${projectHeader()}`,
    ``,
    `\uD83D\uDEA8\uD83D\uDEA8\uD83D\uDEA8 *ERRORE FATALE* \uD83D\uDEA8\uD83D\uDEA8\uD83D\uDEA8`,
    ``,
    `\u{1F4CB} *Feature:* \`${feature}\``,
    `\u{1F6D1} *Step fallito:* ${failedStep}`,
    `\u{1F4DF} *Exit code:* 99 (FATAL)`,
    `\u23F1 *Durata:* ${duration}`,
    `\u{1F552} *Ora:* ${time}`,
    ``,
    `*Progressi:*`,
    steps,
    state.error ? `\n\u{1F4AC} *Errore:* ${state.error}` : '',
    ``,
    `\u26D4 *Pipeline FERMATA \u2014 NO auto-restart*`,
    `\u{1F4BE} Emergency git commit in corso...`,
    `\u{1F6E0} Intervento manuale richiesto`,
  ].filter(Boolean).join('\n');

  await sendTelegram(message);

  // Emergency commit
  log('Attempting emergency git commit...');
  try {
    const gitAdd = spawn('git', ['add', '-A'], { cwd: PROJECT_ROOT, stdio: 'inherit' });
    gitAdd.on('exit', () => {
      const gitCommit = spawn('git', ['commit', '-m', '[EMERGENCY] Fatal pipeline error - auto-commit'], { cwd: PROJECT_ROOT, stdio: 'inherit' });
      gitCommit.on('exit', () => {
        const gitPush = spawn('git', ['push'], { cwd: PROJECT_ROOT, stdio: 'inherit' });
        gitPush.on('exit', () => {
          log('Emergency commit completed');
        });
      });
    });
  } catch (error) {
    logError(`Emergency commit failed: ${error.message}`);
  }
}

async function handleStalled(state) {
  const feature = getFeatureName(state);
  logWarning(`Pipeline stalled (no updates for ${CONFIG.stall_timeout_minutes}min)`);

  const steps = formatStepsProgress(state);
  const stalledStep = state.current_step || 'unknown';
  const duration = formatDuration(state.started_at);
  const lastUpdate = formatTimestamp(state.last_update);
  const canRestart = restart_count < CONFIG.max_restarts;

  const message = [
    `${projectHeader()}`,
    ``,
    `\u23F1 *Pipeline in stallo*`,
    ``,
    `\u{1F4CB} *Feature:* \`${feature}\``,
    `\u{1F6D1} *Step bloccato:* ${stalledStep}`,
    `\u23F1 *Durata totale:* ${duration}`,
    `\u{1F552} *Ultimo update:* ${lastUpdate}`,
    `\u{1F6AB} *Nessun update da:* ${CONFIG.stall_timeout_minutes} min`,
    state.pid ? `\u{1F480} *PID:* ${state.pid} (killing...)` : '',
    ``,
    `*Progressi:*`,
    steps,
    ``,
    canRestart ? `\u{1F501} Kill + riavvio con \`--resume\`...` : `\u274C Max restart raggiunto. Intervento manuale richiesto.`,
  ].filter(Boolean).join('\n');

  await sendTelegram(message);

  if (state.pid) {
    killPipeline(state.pid);
  }

  if (canRestart) {
    restartPipeline(true);
  }
}

// ==============================================================================
// Main Monitoring Loop
// ==============================================================================

let lastStatus = null;

async function checkState() {
  const state = readState();

  if (!state) {
    log('No pipeline state found');
    return;
  }

  // Detect status change
  const statusChanged = lastStatus !== state.status;
  lastStatus = state.status;

  if (!statusChanged && state.status !== 'running') {
    return;
  }

  // Handle status
  switch (state.status) {
    case 'completed':
      if (statusChanged) {
        await handleCompleted(state);
      }
      break;

    case 'failed':
    case 'token_exhausted':
    case 'tool_failure':
    case 'fatal':
      if (statusChanged) {
        const exitCode = state.exit_code || 1;

        if (exitCode === 75 || state.status === 'token_exhausted') {
          await handleTokenExhausted(state);
        } else if (exitCode === 76 || state.status === 'tool_failure') {
          await handleToolFailure(state);
        } else if (exitCode === 99 || state.status === 'fatal') {
          await handleFatal(state);
        } else {
          await handleFailed(state);
        }
      }
      break;

    case 'running':
      if (isStalled(state)) {
        await handleStalled(state);
      }
      break;

    default:
      log(`Unknown status: ${state.status}`);
  }
}

function startMonitoring() {
  log('Supervisor started');
  log(`Poll interval: ${CONFIG.poll_interval_seconds}s`);
  log(`Max restarts: ${CONFIG.max_restarts}`);
  log(`Stall timeout: ${CONFIG.stall_timeout_minutes}min`);

  setInterval(checkState, CONFIG.poll_interval_seconds * 1000);
  checkState(); // Initial check
}

// ==============================================================================
// Feature Queue Mode
// ==============================================================================

async function runFeatures(features) {
  log(`Running features sequentially: ${features.join(', ')}`);

  const totalFeatures = features.length;
  const queueStartTime = new Date();

  const startMessage = [
    `${projectHeader()}`,
    ``,
    `\uD83D\uDE80 *Coda pipeline avviata*`,
    ``,
    `\u{1F4CB} *Feature in coda:* ${totalFeatures}`,
    ...features.map((f, i) => `  ${i + 1}. \`${f}\``),
    ``,
    `\u{1F552} *Avvio:* ${formatTimestamp(queueStartTime.toISOString())}`,
  ].join('\n');

  await sendTelegram(startMessage);

  for (let idx = 0; idx < features.length; idx++) {
    const feature = features[idx];
    log(`\n${'='.repeat(60)}`);
    log(`Starting feature: ${feature}`);
    log('='.repeat(60));

    const featureMessage = [
      `${projectHeader()}`,
      ``,
      `\u{1F3AC} *Avvio feature* (${idx + 1}/${totalFeatures})`,
      ``,
      `\u{1F4CB} *Feature:* \`${feature}\``,
      `\u{1F4CA} *Progresso coda:* ${idx}/${totalFeatures} completate`,
    ].join('\n');

    await sendTelegram(featureMessage);

    // Launch pipeline for this feature
    await new Promise((resolve) => {
      const child = spawn('bash', ['./pipeline.sh', '--feature', feature], {
        cwd: PROJECT_ROOT,
        stdio: 'inherit',
      });

      child.on('exit', (code) => {
        log(`Feature ${feature} exited with code ${code}`);
        resolve(code);
      });
    });

    // Check final state
    const state = readState();
    if (state && state.status === 'completed') {
      await handleCompleted(state);
    } else if (state && state.status === 'failed') {
      logError(`Feature ${feature} failed, stopping queue`);

      const failMessage = [
        `${projectHeader()}`,
        ``,
        `\u274C *Coda pipeline FERMATA*`,
        ``,
        `\u{1F6D1} *Fallita:* \`${feature}\` (${idx + 1}/${totalFeatures})`,
        `\u{1F4DF} *Exit code:* ${state.exit_code || 'unknown'}`,
        `\u23F1 *Durata coda:* ${formatDuration(queueStartTime.toISOString())}`,
        state.error ? `\u{1F4AC} *Errore:* ${state.error}` : '',
        ``,
        `*Feature rimanenti non eseguite:*`,
        ...features.slice(idx + 1).map(f => `  \u2B1C \`${f}\``),
      ].filter(Boolean).join('\n');

      await sendTelegram(failMessage);
      break;
    }
  }

  const queueDuration = formatDuration(queueStartTime.toISOString());
  const doneMessage = [
    `${projectHeader()}`,
    ``,
    `\u{1F3C1} *Coda pipeline completata*`,
    ``,
    `\u{1F4CB} *Feature eseguite:* ${totalFeatures}`,
    `\u23F1 *Durata totale:* ${queueDuration}`,
  ].join('\n');

  await sendTelegram(doneMessage);
  log('Feature queue completed');
}

// ==============================================================================
// CLI
// ==============================================================================

function printStatus() {
  const state = readState();

  if (!state) {
    console.log(`${RED}No pipeline state found${RESET}`);
    return;
  }

  const feature = getFeatureName(state);

  console.log(`\n${BOLD}Pipeline State${RESET}`);
  console.log(`${'─'.repeat(60)}`);
  console.log(`Status:          ${state.status === 'completed' ? GREEN : state.status === 'failed' ? RED : YELLOW}${state.status}${RESET}`);
  console.log(`Feature:         ${feature}`);
  console.log(`Current Step:    ${state.current_step || 'N/A'}`);
  console.log(`Started:         ${state.started_at || 'N/A'}`);
  console.log(`Last Update:     ${state.last_update || 'N/A'}`);
  console.log(`Exit Code:       ${state.exit_code !== undefined ? state.exit_code : 'N/A'}`);
  console.log(`PID:             ${state.pid || 'N/A'}`);

  if (state.steps_completed) {
    const steps = Array.isArray(state.steps_completed) ? state.steps_completed.join(', ') : state.steps_completed;
    console.log(`Steps Completed: ${steps}`);
  }

  if (state.duration) {
    const minutes = Math.floor(state.duration / 60);
    const seconds = state.duration % 60;
    console.log(`Duration:        ${minutes}m ${seconds}s`);
  }

  console.log(`${'─'.repeat(60)}\n`);
}

function showHelp() {
  console.log(`
${BOLD}Pipeline Supervisor${RESET}

${CYAN}Usage:${RESET}
  node supervisor.js                              Monitor current pipeline
  node supervisor.js --features <list>            Run features sequentially
  node supervisor.js --once                       Check state once and exit
  node supervisor.js --status                     Print current state
  node supervisor.js --help                       Show this help

${CYAN}Examples:${RESET}
  node supervisor.js
  node supervisor.js --features contacts,companies,deals
  node supervisor.js --once
  node supervisor.js --status

${CYAN}Configuration:${RESET}
  Set in pipeline.yaml under "supervisor" section or via environment variables:
  - TELEGRAM_BOT_TOKEN        Bot token
  - TELEGRAM_CHAT_ID          Chat/group ID
  - PIPELINE_PROJECT_NAME     Nome progetto nei messaggi (default: Pipeline)
`);
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    showHelp();
    process.exit(0);
  }

  loadConfig();

  if (args.includes('--status')) {
    printStatus();
    process.exit(0);
  }

  if (args.includes('--once')) {
    await checkState();
    process.exit(0);
  }

  const featuresIndex = args.indexOf('--features');
  if (featuresIndex !== -1 && args[featuresIndex + 1]) {
    const features = args[featuresIndex + 1].split(',').map(f => f.trim());
    await runFeatures(features);
    process.exit(0);
  }

  // Default: monitor mode
  startMonitoring();
}

main().catch((error) => {
  logError(`Supervisor crashed: ${error.message}`);
  process.exit(1);
});
