# ai-pipeline

Orchestratore bash per pipeline di agenti AI. Portabile — copia `ai-pipeline/` in qualsiasi progetto.

## Requisiti

- `bash` 3.2+
- `python3` (standard su macOS/Linux)
- `claude` CLI installato e autenticato

## Installazione

```bash
# Copia in qualsiasi progetto
cp -r ai-pipeline/ my-project/ai-pipeline/
cd my-project/ai-pipeline

# Personalizza pipeline.yaml con il tuo progetto e i tuoi step
# Opzione A: crea i prompt in prompts/<step>.md (un file per agente)
# Opzione B: crea prompts.md con sezioni ## per ogni agente (vedi sotto)
# Aggiungi le API key al .env del progetto
```

## Uso

```bash
# Feature nuova con brief inline
./ai-pipeline/pipeline.sh button-outline \
  --description "Aggiungere variante outline al Button"

# Target app/layer specifico (esposto a prompt_build)
./ai-pipeline/pipeline.sh button-outline \
  --app my-app \
  --description "Aggiungere variante outline al Button"

# Feature con brief file in briefs/
./ai-pipeline/pipeline.sh fleet-alerts

# Riprende da dove era rimasta (controlla output files)
./ai-pipeline/pipeline.sh button-outline --resume

# Riparte da uno step specifico
./ai-pipeline/pipeline.sh button-outline --from dev

# Solo uno step
./ai-pipeline/pipeline.sh button-outline --only qa

# Stato corrente
./ai-pipeline/pipeline.sh --state

# Anteprima prompt senza eseguire
./ai-pipeline/pipeline.sh button-outline --dry-run

# Override modello per tutti gli step
./ai-pipeline/pipeline.sh button-outline --model claude-opus-4-6
```

## Batch mode (esecuzione sequenziale)

Passa più feature per eseguirle in sequenza — la successiva parte solo quando la precedente ha completato con successo.

```bash
# Più feature come argomenti
./ai-pipeline/pipeline.sh feat-login feat-signup feat-dashboard

# Da file (una feature per riga, # per commenti)
./ai-pipeline/pipeline.sh --batch-file features.txt

# Continua anche se una feature fallisce
./ai-pipeline/pipeline.sh feat-a feat-b feat-c --continue-on-error

# Combinabile con altre opzioni
./ai-pipeline/pipeline.sh feat-a feat-b --model claude-sonnet-4-6 --dry-run
```

Ogni feature deve avere il suo brief in `briefs/<feature>.md`. Feature senza brief vengono saltate con warning.

Lo stato batch è tracciato in `batch-state.json`, visibile con `--state`:

```
  Batch: v completed  (3/3 completate, 0 fallite)
  Avviato: 2026-02-24T14:22:00Z

  v  feat-login                     completed  5m30s
  v  feat-signup                    completed  4m15s
  v  feat-dashboard                 completed  8m22s
```

### Opzioni batch

| Opzione | Descrizione |
|---------|-------------|
| `--batch-file <file>` | Carica feature da file (una per riga, `#` per commenti) |
| `--continue-on-error` | Non fermarti al primo errore, continua con le successive |

**Note:** `--description` non è compatibile con batch mode (crea i brief prima). Le opzioni `--from`, `--only`, `--model` si applicano a tutte le feature del batch.

## Struttura

```
ai-pipeline/
├── pipeline.sh          # Entry point
├── pipeline.yaml        # Configurazione (personalizzare)
├── .mcp.json            # MCP server disponibili
├── lib/
│   ├── config.sh        # Parsing YAML
│   ├── display.sh       # UI terminale (box, spinner, colori tool)
│   ├── claude.sh        # Claude CLI execution + file change tracking + token tracking
│   ├── state.sh         # State management (pipeline + batch + token usage)
│   ├── verdict.sh       # Gate logic
│   ├── prompt.sh        # Assemblaggio prompt (prompts.md o file statici)
│   ├── playwright.sh    # Dev server check + visual verification + screenshot
│   ├── verify.sh        # Build/lint verification post-step
│   └── context.sh       # Cross-step context sharing
├── prompts/             # Un file .md per agente (usati se prompts.md assente)
├── prompts.md           # Alternativa: tutti i prompt in un file con sezioni ##
└── example/             # Template e prompt di esempio
    └── prompts/
```

### Directory generate a runtime

```
ai-pipeline/
├── briefs/              # Brief delle feature (input)
├── specs/               # Specifiche PM (output)
├── reviews/             # Report DR (output)
├── qa/                  # Report QA (output)
├── verdicts/            # File .verdict (APPROVED/REJECTED)
├── screenshots/         # Screenshot Playwright per feature/step
│   └── <feature>/
│       ├── dev/
│       ├── dr-impl/
│       └── qa/
├── logs/                # Log stream-json + dev server
├── verify/              # Output dei comandi di verifica (lint, build)
├── context/             # Contesto condiviso tra step (<feature>.json)
├── state.json           # Stato pipeline corrente (include token usage)
└── batch-state.json     # Stato batch (se batch mode)
```

## Verify (build/lint automatico)

Dopo gli step `dev` e `dev-fix`, la pipeline esegue automaticamente comandi di verifica deterministica (build, lint, typecheck). Se un comando fallisce, gli errori vengono iniettati come contesto nel retry — l'agente riceve l'output esatto dell'errore e deve correggerlo.

```yaml
verify:
  enabled: true
  commands:
    - name: lint
      cmd: "pnpm lint --no-fix"
    - name: build
      cmd: "pnpm build"
  after_steps:
    - dev
    - dev-fix
```

Disabilitare: `verify.enabled: false`.

## Integration check

Dopo che tutti i gate passano e la pipeline è completata, viene eseguito un check finale di integrazione. Esegue gli stessi comandi in sequenza come sanity check.

```yaml
integration:
  enabled: true
  commands:
    - "pnpm lint --no-fix"
    - "pnpm build"
```

Se il check fallisce, la pipeline avvisa ma non marca la feature come fallita (i gate AI hanno già approvato). Disabilitare: `integration.enabled: false`.

## Model escalation on retry

Se uno step fallisce al primo tentativo, può scalare automaticamente a un modello più potente per i retry successivi.

```yaml
steps:
  - name: dev
    model: claude-sonnet-4-6
    model_on_retry: claude-opus-4-6  # dal 2° tentativo usa opus
```

## Context cross-step

La pipeline mantiene un file `context/<feature>.json` che accumula i file modificati e gli step completati. Gli agenti successivi possono leggerlo per evitare di ri-esplorare il codebase da zero.

```json
{
  "feature": "button-outline",
  "files_modified": ["components/Button.vue", "composables/useButton.ts"],
  "steps_completed": ["pm", "dr-spec", "dev"]
}
```

Il contesto viene referenziato automaticamente nei prompt degli agenti.

## Token tracking

La pipeline traccia automaticamente i token (input/output) consumati da ogni step. I dati vengono salvati in `state.json` e mostrati nel box di completamento finale.

```
  +----------------------------------------------------------+
  |  Pipeline completata  4m23s                              |
  |  Feature: button-outline                                 |
  |  Tokens: 208.0K in / 55.5K out                          |
  +----------------------------------------------------------+
```

## Notifiche

Supporto notifiche cross-platform per eventi pipeline (completamento, fallimento):

- **macOS**: notifica nativa via `osascript`
- **Linux**: `notify-send` (se disponibile)
- **Webhook HTTP**: POST JSON a qualsiasi URL

```yaml
notifications:
  webhook_url: "https://hooks.slack.com/services/..."  # opzionale
```

## Gate system

Gli step con `verdict: true` richiedono che l'agente scriva una sola parola in un file `.verdict` separato:

- `APPROVED` → pipeline avanza al prossimo step
- `REJECTED` → esegue `on_reject` step con feedback, poi riprova

Il file `.verdict` è fisicamente separato dal report markdown: nessun parsing, confronto stringa esatta dopo `tr -d '[:space:]'`. Fail-safe: file mancante o malformato = `MISSING` = `REJECTED`.

## Retry e token exhaustion

### Step-level retry

Se uno step fallisce o il gate è REJECTED, la pipeline ritenta fino a `defaults.max_retries` volte. Ad ogni retry viene iniettato il feedback della revisione precedente.

### Token exhaustion

Se il modello non risponde per esaurimento token o rate limit, la pipeline:

1. Rileva l'errore (exit code 75, pattern specifici in stderr: `rate.?limit(ed)?`, `over.?capacity`, `context.?(window|length).?(exceed|limit)`, `model.?overloaded`, `too.?many.?tokens`, `token.?limit`, `quota.?exceed`)
2. Attende con backoff esponenziale: `base_delay * 2^(attempt-1)` secondi
3. Riprova fino a `token_max_retries` volte
4. Mostra countdown in tempo reale nel terminale

```yaml
defaults:
  max_retries: 3              # retry per step (gate REJECTED o errore)
  token_max_retries: 5        # retry per token exhaustion
  token_base_delay: 60        # delay base in secondi (60, 120, 240, ...)
```

## Provider per step

Configura provider e modello per step in `pipeline.yaml`:

```yaml
steps:
  - name: dev
    provider: kimi
    model: kimi-k2-thinking-turbo

providers:
  kimi:
    base_url: "https://api.moonshot.ai/anthropic"
    api_key_env: KIMI_API_KEY
```

## MCP

Dichiara i server disponibili in `.mcp.json`, poi specifica per step quali attivare in `pipeline.yaml`:

```yaml
steps:
  - name: qa
    mcp_servers:
      - playwright
```

## Prompt: due modalità

**Modalità A — file statici** (default): un file `.md` per step in `prompts/`.

**Modalità B — `prompts.md`**: un unico file con sezioni `## <NomeSezione>` e fence code block. Configura `prompt_section` per step in `pipeline.yaml`:

```yaml
steps:
  - name: pm
    prompt_section: "PM (Product Manager)"
```

`lib/prompt.sh` sceglie automaticamente la modalità in base all'esistenza di `prompts.md`.

## Playwright (dev server + screenshot)

Gli step con `playwright: true` in `pipeline.yaml` richiedono il dev server attivo. La pipeline:

1. Verifica la connessione al dev server prima di partire (auto-start se configurato)
2. Inietta nel prompt l'istruzione obbligatoria di verifica visiva con browser
3. Lancia Playwright MCP in **headless mode** (configurato in `.mcp.json`)
4. Salva automaticamente tutti gli screenshot in `screenshots/<feature>/<step>/`
5. Mostra il conteggio screenshot nella TUI dopo ogni step

```yaml
project:
  dev_host: localhost          # host del dev server (default: localhost)
  dev_port: 3000               # porta del dev server

steps:
  - name: qa
    playwright: true
    mcp_servers:
      - playwright
```

### Screenshot persistenti

Gli screenshot fatti con `browser_take_screenshot` vengono salvati automaticamente in:

```
screenshots/<feature>/<step>/
```

Questo permette:
- **Riferimenti tra agenti**: il QA può consultare gli screenshot del dev
- **Polish post-pipeline**: tutti gli screenshot disponibili per review manuale
- **Debug regressioni visive**: cronologia visiva della feature

La directory degli screenshot viene comunicata nel prompt iniettato, così gli agenti sanno dove trovare quelli degli step precedenti.

### Headless mode

Il server Playwright MCP è configurato con `--headless` in `.mcp.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--headless"]
    }
  }
}
```

Non viene aperta nessuna finestra del browser. Per debug locale, rimuovi `--headless` da `.mcp.json`.

### TUI per Playwright

Durante l'esecuzione, la TUI mostra in tempo reale:

- **Riga 1**: spinner + tempo + ultimo tool usato
- **Riga 2**: URL corrente nel browser + ultima azione Playwright (navigate, click, screenshot, ecc.)

Icone per tipo di azione: `🔗 navigate`, `👁 snapshot`, `🖱 click`, `📸 screenshot`, `🔍 hover`, `📜 scroll`, `⌨ type`, `⏳ wait`

Dopo lo step: `📸 N screenshot salvati → screenshots/<feature>/<step>/`

## Display terminale

Header con timestamp, progress bar, e overview degli step:

```
  Progress: [████████████░░░░░░░░] 3/6

  +----------------------------------------------------------+
  | ⚙️  dev                          (step 3/6)              |
  |  Feature: button-outline  | Model: sonnet     | 14:22:01 |
  |  Tools: Read,Write,Edit,Bash,Glob,Grep                   |
  |  ✓pm ✓dr-spec ▶dev ○dr-impl ○qa ○dev-fix                |
  +----------------------------------------------------------+

  |  Write   ButtonOutline.vue
  |  Edit    index.vue
  /  0m45s
```

### Pipeline overview

Una riga compatta mostra lo stato di tutti gli step:
- `✓` verde = completato
- `▶` cyan = in corso
- `✗` rosso = fallito
- `○` dim = pending

### Contatori azioni per tool

Al completamento di ogni step, il box mostra il totale azioni suddiviso per tipo di tool:

```
  ✓  Step dev completato in 5m23s  (42 azioni: Write:15 Edit:12 Read:8 Bash:5 Glob:2)
```

### Retry banner

Quando un gate rigetta e la pipeline esegue retry, viene mostrato un banner compatto:

```
  +----------------------------------------------------------+
  |  ↺ Retry 1/3  dev → REJECTED by dr-impl                 |
  +----------------------------------------------------------+
```

### File modificati

Dopo ogni step: file modificati con diff stat git (`+N -N`) e timestamp:

```
  +----------------------------------------------------------+
  |  File modificati                                         |
  +----------------------------------------------------------+
  |  components/ButtonOutline.vue      +142    14:22:48      |
  |  components/index.vue              +3 -1   14:22:49      |
  +----------------------------------------------------------+
```

### Box di completamento

Al termine della pipeline, mostra feature, tempo totale e token consumati:

```
  +----------------------------------------------------------+
  |  Pipeline completata  4m23s                              |
  |  Feature: button-outline                                 |
  |  Tokens: 208.0K in / 55.5K out                          |
  +----------------------------------------------------------+
```

In caso di gate REJECTED: estratto del motivo dal report markdown.

## Licenza

MIT
