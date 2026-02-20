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

## Struttura

```
ai-pipeline/
├── pipeline.sh          # Entry point
├── pipeline.yaml        # Configurazione (personalizzare)
├── .mcp.json            # MCP server disponibili
├── lib/
│   ├── config.sh        # Parsing YAML
│   ├── display.sh       # UI terminale (box, spinner, colori tool)
│   ├── claude.sh        # Claude CLI execution + file change tracking
│   ├── state.sh         # State management
│   ├── verdict.sh       # Gate logic
│   ├── prompt.sh        # Assemblaggio prompt (prompts.md o file statici)
│   └── playwright.sh    # Dev server check + visual verification
├── prompts/             # Un file .md per agente (usati se prompts.md assente)
├── prompts.md           # Alternativa: tutti i prompt in un file con sezioni ##
└── example/             # Template e prompt di esempio
    └── prompts/
```

## Gate system

Gli step con `verdict: true` richiedono che l'agente scriva una sola parola in un file `.verdict` separato:

- `APPROVED` → pipeline avanza al prossimo step
- `REJECTED` → esegue `on_reject` step con feedback, poi riprova

Il file `.verdict` è fisicamente separato dal report markdown: nessun parsing, confronto stringa esatta dopo `tr -d '[:space:]'`. Fail-safe: file mancante o malformato = `MISSING` = `REJECTED`.

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

## Playwright (dev server)

Gli step con `playwright: true` in `pipeline.yaml` richiedono il dev server attivo. La pipeline verifica la connessione prima di partire e inietta nel prompt l'istruzione obbligatoria di verifica visiva con browser.

```yaml
steps:
  - name: qa
    playwright: true
    mcp_servers:
      - playwright
```

Configura la porta in `pipeline.yaml`:

```yaml
project:
  dev_port: 3000
```

## Display terminale

Header con timestamp e progress bar per step:

```
  Progress: [████████████░░░░░░░░] 3/4

  +----------------------------------------------------------+
  | ⚙️  dev                          (step 3/4)              |
  |  Feature: button-outline  | Model: sonnet     | 14:22:01 |
  |  Tools: Read,Write,Edit,Bash,Glob,Grep                   |
  +----------------------------------------------------------+

  |  Write   ButtonOutline.vue
  |  Edit    index.vue
  /  0m45s
```

Dopo ogni step: file modificati con diff stat git (`+N -N`) e timestamp:

```
  +----------------------------------------------------------+
  |  File modificati                                         |
  +----------------------------------------------------------+
  |  components/ButtonOutline.vue      +142    14:22:48      |
  |  components/index.vue              +3 -1   14:22:49      |
  +----------------------------------------------------------+
```

In caso di gate REJECTED: estratto del motivo dal report markdown.

## Licenza

MIT
