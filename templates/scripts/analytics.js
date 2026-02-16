#!/usr/bin/env node

// ==============================================================================
// Pipeline Analytics — Generate Reports from Meta Logs
// ==============================================================================
//
// Pure Node.js analytics script with ZERO npm dependencies.
//
// Reads all logs/meta/*.meta.json files and generates:
// - Total features processed
// - Total pipeline time
// - Average time per step type
// - Failure rate per step
// - Retry count per step
// - Model usage breakdown (opus vs sonnet)
// - Longest/shortest features
//
// Also reads logs/decisions.jsonl for retry analysis.
//
// Usage:
//   node analytics.js                  — Console output (default)
//   node analytics.js --json           — JSON to stdout
//   node analytics.js --markdown       — Write logs/analytics-report.md
//
// ==============================================================================

const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const META_DIR = path.join(PROJECT_ROOT, 'logs', 'meta');
const DECISIONS_FILE = path.join(PROJECT_ROOT, 'logs', 'decisions.jsonl');
const REPORT_FILE = path.join(PROJECT_ROOT, 'logs', 'analytics-report.md');

// Colors
const RESET = '\x1b[0m';
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const BLUE = '\x1b[34m';
const CYAN = '\x1b[36m';
const BOLD = '\x1b[1m';

// ==============================================================================
// Data Collection
// ==============================================================================

function readMetaFiles() {
  if (!fs.existsSync(META_DIR)) {
    return [];
  }

  const files = fs.readdirSync(META_DIR).filter(f => f.endsWith('.meta.json'));
  const data = [];

  for (const file of files) {
    try {
      const content = fs.readFileSync(path.join(META_DIR, file), 'utf-8');
      const meta = JSON.parse(content);
      data.push(meta);
    } catch (error) {
      console.error(`Failed to read ${file}: ${error.message}`);
    }
  }

  return data;
}

function readDecisions() {
  if (!fs.existsSync(DECISIONS_FILE)) {
    return [];
  }

  try {
    const content = fs.readFileSync(DECISIONS_FILE, 'utf-8');
    const lines = content.trim().split('\n');
    return lines.map(line => JSON.parse(line));
  } catch (error) {
    console.error(`Failed to read decisions: ${error.message}`);
    return [];
  }
}

// ==============================================================================
// Analytics Computation
// ==============================================================================

function computeAnalytics(metaData, decisions) {
  const analytics = {
    total_features: 0,
    total_time_seconds: 0,
    total_time_formatted: '',
    features: [],
    steps: {},
    models: {
      opus: { count: 0, time_seconds: 0 },
      sonnet: { count: 0, time_seconds: 0 },
    },
    failures: {
      total: 0,
      by_step: {},
    },
    retries: {
      total: 0,
      by_step: {},
      reasons: {},
    },
    longest_feature: null,
    shortest_feature: null,
  };

  // Process meta files
  for (const meta of metaData) {
    const featureName = meta.feature || 'unknown';
    const duration = meta.duration || 0;

    analytics.total_features++;
    analytics.total_time_seconds += duration;

    analytics.features.push({
      name: featureName,
      duration_seconds: duration,
      duration_formatted: formatDuration(duration),
      steps_completed: meta.steps_completed || 0,
      status: meta.status || 'unknown',
    });

    // Track longest/shortest
    if (!analytics.longest_feature || duration > analytics.longest_feature.duration_seconds) {
      analytics.longest_feature = { name: featureName, duration_seconds: duration, duration_formatted: formatDuration(duration) };
    }

    if (!analytics.shortest_feature || duration < analytics.shortest_feature.duration_seconds) {
      analytics.shortest_feature = { name: featureName, duration_seconds: duration, duration_formatted: formatDuration(duration) };
    }

    // Process steps
    if (meta.steps && Array.isArray(meta.steps)) {
      for (const step of meta.steps) {
        const stepName = step.name || 'unknown';
        const stepDuration = step.duration || 0;
        const stepModel = step.model || 'unknown';
        const stepStatus = step.status || 'unknown';

        if (!analytics.steps[stepName]) {
          analytics.steps[stepName] = {
            count: 0,
            total_time: 0,
            avg_time: 0,
            failures: 0,
            retries: 0,
          };
        }

        analytics.steps[stepName].count++;
        analytics.steps[stepName].total_time += stepDuration;

        if (stepStatus === 'failed') {
          analytics.steps[stepName].failures++;
          analytics.failures.total++;

          if (!analytics.failures.by_step[stepName]) {
            analytics.failures.by_step[stepName] = 0;
          }
          analytics.failures.by_step[stepName]++;
        }

        // Track model usage
        if (stepModel.includes('opus')) {
          analytics.models.opus.count++;
          analytics.models.opus.time_seconds += stepDuration;
        } else if (stepModel.includes('sonnet')) {
          analytics.models.sonnet.count++;
          analytics.models.sonnet.time_seconds += stepDuration;
        }
      }
    }
  }

  // Compute averages
  for (const stepName in analytics.steps) {
    const step = analytics.steps[stepName];
    step.avg_time = step.count > 0 ? Math.round(step.total_time / step.count) : 0;
    step.avg_time_formatted = formatDuration(step.avg_time);
    step.total_time_formatted = formatDuration(step.total_time);
  }

  analytics.total_time_formatted = formatDuration(analytics.total_time_seconds);

  // Process decisions (retries)
  for (const decision of decisions) {
    if (decision.type === 'retry') {
      analytics.retries.total++;

      const step = decision.step || 'unknown';
      if (!analytics.retries.by_step[step]) {
        analytics.retries.by_step[step] = 0;
      }
      analytics.retries.by_step[step]++;

      if (analytics.steps[step]) {
        analytics.steps[step].retries++;
      }

      const reason = decision.reason || 'unknown';
      if (!analytics.retries.reasons[reason]) {
        analytics.retries.reasons[reason] = 0;
      }
      analytics.retries.reasons[reason]++;
    }
  }

  return analytics;
}

// ==============================================================================
// Formatting
// ==============================================================================

function formatDuration(seconds) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  } else {
    return `${secs}s`;
  }
}

function formatTable(headers, rows) {
  const colWidths = headers.map((h, i) => {
    const maxContentWidth = Math.max(...rows.map(r => String(r[i] || '').length));
    return Math.max(h.length, maxContentWidth) + 2;
  });

  const headerRow = headers.map((h, i) => h.padEnd(colWidths[i])).join('│');
  const separator = colWidths.map(w => '─'.repeat(w)).join('┼');

  const lines = [headerRow, separator];

  for (const row of rows) {
    const rowStr = row.map((cell, i) => String(cell || '').padEnd(colWidths[i])).join('│');
    lines.push(rowStr);
  }

  return lines.join('\n');
}

// ==============================================================================
// Output Renderers
// ==============================================================================

function renderConsole(analytics) {
  console.log(`\n${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}`);
  console.log(`${BOLD}║  Pipeline Analytics Report                               ║${RESET}`);
  console.log(`${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}\n`);

  // Summary
  console.log(`${BOLD}${CYAN}Summary${RESET}`);
  console.log(`${'─'.repeat(60)}`);
  console.log(`Total Features:       ${GREEN}${analytics.total_features}${RESET}`);
  console.log(`Total Pipeline Time:  ${YELLOW}${analytics.total_time_formatted}${RESET}`);
  console.log(`Total Failures:       ${analytics.failures.total > 0 ? RED : GREEN}${analytics.failures.total}${RESET}`);
  console.log(`Total Retries:        ${analytics.retries.total > 0 ? YELLOW : GREEN}${analytics.retries.total}${RESET}`);

  // Model usage
  console.log(`\n${BOLD}${CYAN}Model Usage${RESET}`);
  console.log(`${'─'.repeat(60)}`);
  console.log(`Opus:    ${analytics.models.opus.count} steps (${formatDuration(analytics.models.opus.time_seconds)})`);
  console.log(`Sonnet:  ${analytics.models.sonnet.count} steps (${formatDuration(analytics.models.sonnet.time_seconds)})`);

  // Step breakdown
  console.log(`\n${BOLD}${CYAN}Step Performance${RESET}`);
  console.log(`${'─'.repeat(60)}`);

  const stepRows = Object.entries(analytics.steps).map(([name, data]) => [
    name,
    data.count,
    data.avg_time_formatted,
    data.total_time_formatted,
    data.failures,
    data.retries,
  ]);

  console.log(formatTable(
    ['Step', 'Count', 'Avg Time', 'Total Time', 'Failures', 'Retries'],
    stepRows
  ));

  // Features
  console.log(`\n${BOLD}${CYAN}Features${RESET}`);
  console.log(`${'─'.repeat(60)}`);

  if (analytics.longest_feature) {
    console.log(`Longest:  ${YELLOW}${analytics.longest_feature.name}${RESET} (${analytics.longest_feature.duration_formatted})`);
  }

  if (analytics.shortest_feature) {
    console.log(`Shortest: ${GREEN}${analytics.shortest_feature.name}${RESET} (${analytics.shortest_feature.duration_formatted})`);
  }

  console.log('');
}

function renderMarkdown(analytics) {
  let md = '';

  md += '# Pipeline Analytics Report\n\n';
  md += `_Generated: ${new Date().toISOString()}_\n\n`;

  // Summary
  md += '## Summary\n\n';
  md += `- **Total Features:** ${analytics.total_features}\n`;
  md += `- **Total Pipeline Time:** ${analytics.total_time_formatted}\n`;
  md += `- **Total Failures:** ${analytics.failures.total}\n`;
  md += `- **Total Retries:** ${analytics.retries.total}\n\n`;

  // Model usage
  md += '## Model Usage\n\n';
  md += `- **Opus:** ${analytics.models.opus.count} steps (${formatDuration(analytics.models.opus.time_seconds)})\n`;
  md += `- **Sonnet:** ${analytics.models.sonnet.count} steps (${formatDuration(analytics.models.sonnet.time_seconds)})\n\n`;

  // Step breakdown
  md += '## Step Performance\n\n';
  md += '| Step | Count | Avg Time | Total Time | Failures | Retries |\n';
  md += '|------|-------|----------|------------|----------|----------|\n';

  for (const [name, data] of Object.entries(analytics.steps)) {
    md += `| ${name} | ${data.count} | ${data.avg_time_formatted} | ${data.total_time_formatted} | ${data.failures} | ${data.retries} |\n`;
  }

  md += '\n';

  // Features
  md += '## Features\n\n';

  if (analytics.longest_feature) {
    md += `- **Longest:** ${analytics.longest_feature.name} (${analytics.longest_feature.duration_formatted})\n`;
  }

  if (analytics.shortest_feature) {
    md += `- **Shortest:** ${analytics.shortest_feature.name} (${analytics.shortest_feature.duration_formatted})\n`;
  }

  md += '\n### All Features\n\n';
  md += '| Feature | Duration | Steps | Status |\n';
  md += '|---------|----------|-------|--------|\n';

  for (const feature of analytics.features) {
    md += `| ${feature.name} | ${feature.duration_formatted} | ${feature.steps_completed} | ${feature.status} |\n`;
  }

  md += '\n';

  // Retry reasons
  if (Object.keys(analytics.retries.reasons).length > 0) {
    md += '## Retry Reasons\n\n';
    md += '| Reason | Count |\n';
    md += '|--------|-------|\n';

    for (const [reason, count] of Object.entries(analytics.retries.reasons)) {
      md += `| ${reason} | ${count} |\n`;
    }

    md += '\n';
  }

  return md;
}

// ==============================================================================
// CLI
// ==============================================================================

function showHelp() {
  console.log(`
${BOLD}Pipeline Analytics${RESET}

${CYAN}Usage:${RESET}
  node analytics.js                  Console output (colored tables)
  node analytics.js --json           JSON to stdout
  node analytics.js --markdown       Write logs/analytics-report.md
  node analytics.js --help           Show this help

${CYAN}Examples:${RESET}
  node analytics.js
  node analytics.js --json > report.json
  node analytics.js --markdown
`);
}

function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    showHelp();
    process.exit(0);
  }

  const metaData = readMetaFiles();
  const decisions = readDecisions();

  if (metaData.length === 0) {
    console.error(`${RED}No meta logs found in ${META_DIR}${RESET}`);
    process.exit(1);
  }

  const analytics = computeAnalytics(metaData, decisions);

  if (args.includes('--json')) {
    console.log(JSON.stringify(analytics, null, 2));
  } else if (args.includes('--markdown')) {
    const markdown = renderMarkdown(analytics);
    fs.writeFileSync(REPORT_FILE, markdown);
    console.log(`${GREEN}Report written to: ${REPORT_FILE}${RESET}`);
  } else {
    renderConsole(analytics);
  }
}

main();
