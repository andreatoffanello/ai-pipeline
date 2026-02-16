# AI Pipeline — Multi-Agent Development Workflow Boilerplate

Un boilerplate per pipeline di sviluppo multi-agente autonome usando Claude Code CLI.

Ogni feature del progetto attraversa un ciclo completo di quality gates:

```
PM (specifica) --> DR-SPEC (valida spec) --> DEV (implementa) --> DR-IMPL (valida UI) --> QA (valida tutto)
       |                  |                                             |                      |
       v (se boccia)      v (se boccia)                                 v (se boccia)          v (se fallisce)
  PM (corregge)      PM (corregge)                                 DEV (corregge)         DEV-FIX --> QA (ri-valida)
```

## Quick Start

```bash
# 1. Clona il boilerplate
git clone <repo-url> ai-pipeline
cd ai-pipeline

# 2. Lancia il wizard interattivo
./init.sh

# 3. Vai nel progetto generato e verifica l'ambiente
cd /path/to/your-project
./scripts/preflight.sh

# 4. Lancia la pipeline per una feature
./scripts/pipeline.sh contacts

# 5. (Opzionale) Avvia il supervisor per monitoraggio autonomo
node scripts/supervisor.js
```

## Cosa genera il wizard

Il wizard interattivo (`init.sh`) chiede informazioni sul progetto e sullo stack tecnologico, poi genera:

| File | Scopo |
|------|-------|
| `CLAUDE.md` | Istruzioni per gli agenti AI |
| `docs/MASTER_PLAN.md` | Architettura, schema DB, design system, roadmap |
| `docs/CONVENTIONS.md` | Standard di codice, API format, error handling, git workflow |
| `docs/AI_AGENTS.md` | Ruoli agenti, filosofia, flusso di lavoro |
| `docs/PROMPTS.md` | Prompt eseguibili per ogni ruolo (PM, DR, DEV, QA) |
| `docs/SKILLS.md` | Indice delle skill riutilizzabili |
| `docs/skills/*.md` | Skill di generazione codice per lo stack scelto |
| `docs/MCP.md` | Configurazione MCP servers |
| `docs/PRE_KICKOFF.md` | Checklist azioni manuali pre-sviluppo |
| `docs/STATUS.md` | Tracker progressi feature |
| `pipeline.yaml` | Configurazione pipeline (step, modelli, retry, hooks) |
| `.mcp.json` | Configurazione MCP servers per Claude Code |
| `scripts/pipeline.sh` | Orchestratore pipeline autonomo |
| `scripts/preflight.sh` | Verifica ambiente e strumenti |
| `scripts/supervisor.js` | Monitor autonomo con notifiche Telegram |
| `scripts/analytics.js` | Report metriche e analytics |
| `scripts/docs-gen.sh` | Generazione documentazione via AI |

## I 5 Agenti

| Agente | Ruolo | Modello suggerito |
|--------|-------|-------------------|
| **PM** | Produce specifiche dettagliate, user stories, acceptance criteria | Opus |
| **DR** | Valida design UX: sulla spec (pre-dev) e sull'implementazione (post-dev) | Sonnet |
| **DEV** | Implementa la feature seguendo spec e skill | Opus |
| **QA** | Verifica sistematica di ogni acceptance criterion | Sonnet |
| **DEV-FIX** | Corregge issues Critical/Major trovate dal QA | Sonnet |

## Pipeline Configuration (pipeline.yaml)

```yaml
project:
  name: "my-project"

steps:
  - name: pm
    model: opus
    output_check: "docs/specs/{{FEATURE}}.md"
  - name: dr_spec
    model: sonnet
    retry_with: pm
    max_retries: 2
  - name: dev
    model: opus
  - name: dr_impl
    model: sonnet
    retry_with: dev
    max_retries: 2
    requires_dev_server: true
  - name: qa
    model: sonnet
    retry_with: dev_fix
    max_retries: 2
```

## Pipeline CLI

```bash
./scripts/pipeline.sh <feature> [opzioni]

# Ciclo completo
./scripts/pipeline.sh contacts

# Riprendi da uno step
./scripts/pipeline.sh contacts --from dev

# Auto-rileva e riprendi
./scripts/pipeline.sh contacts --resume

# Preview senza eseguire
./scripts/pipeline.sh contacts --dry-run

# Forza un modello
./scripts/pipeline.sh contacts --model opus

# Dump stato corrente
./scripts/pipeline.sh --state
```

## Supervisor

Il supervisor e uno script Node.js puro (nessun LLM) che monitora la pipeline:

- Rileva completamento, fallimento, token exhaustion
- Restart automatico con backoff esponenziale per token exhaustion
- Notifiche Telegram per errori e completamenti
- Git commit+push come fallback su errori fatali
- Stall detection (kill+restart se bloccato da 30min)

```bash
# Monitora la pipeline corrente
node scripts/supervisor.js

# Esegui una lista di feature in sequenza
node scripts/supervisor.js --features contacts,companies,deals
```

## Exit Codes

| Codice | Significato | Azione supervisor |
|--------|-------------|-------------------|
| 0 | Successo | Prossima feature |
| 1 | Errore business logic (QA fail, etc.) | Restart con --resume |
| 75 | Token exhausted | Backoff + retry |
| 76 | Tool/MCP failure | Restart + notifica |
| 99 | Errore fatale | Stop + git push + notifica urgente |

## Meta-Logging e Analytics

Ogni step produce un file `logs/meta/{feature}-{step}.meta.json`:

```json
{
  "feature": "contacts",
  "step": "dev",
  "model": "opus",
  "duration_seconds": 2520,
  "exit_code": 0,
  "retry_attempt": 0,
  "files_changed": ["pages/contacts/index.vue"]
}
```

Le deviazioni dai piani vengono loggate in `logs/decisions.jsonl`.

```bash
# Genera report analytics
node scripts/analytics.js
node scripts/analytics.js --markdown  # Scrive logs/analytics-report.md
node scripts/analytics.js --json      # Output JSON
```

## Stack Supportati

| Stack | File profilo |
|-------|-------------|
| Nuxt 4 + Supabase | `wizard/stacks/nuxt-supabase.yaml` |

### Aggiungere un nuovo stack

1. Crea `wizard/stacks/my-stack.yaml` copiando un profilo esistente
2. Adatta: framework, dev server, modelli, MCP servers, env vars, convenzioni
3. Crea le skill corrispondenti in `templates/skills/my-stack/`
4. Lancia `./init.sh` e seleziona il nuovo stack

## Struttura Documentazione Generata

```
your-project/
  docs/
    MASTER_PLAN.md          # Piano generale (da completare)
    CONVENTIONS.md          # Standard di codice
    AI_AGENTS.md            # Ruoli e workflow agenti
    PROMPTS.md              # Prompt eseguibili per ruolo
    SKILLS.md               # Indice skill
    MCP.md                  # Configurazione MCP
    PRE_KICKOFF.md          # Checklist setup
    STATUS.md               # Tracker progressi
    specs/                  # Output PM: specifiche feature
    design-review/          # Output DR: review design
    qa/                     # Output QA: report test
    skills/                 # Skill files per lo stack
  logs/
    meta/                   # Meta-logging JSON
    decisions.jsonl         # Decision log
  scripts/
    pipeline.sh             # Pipeline orchestrator
    preflight.sh            # Verifica ambiente
    supervisor.js           # Monitor autonomo
    analytics.js            # Report metriche
    docs-gen.sh             # Generazione docs
  pipeline.yaml             # Configurazione pipeline
  CLAUDE.md                 # Istruzioni agenti
  .mcp.json                 # MCP servers
```

## Licenza

MIT
