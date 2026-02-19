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
# Crea i prompt in prompts/ (vedi example/prompts/ come riferimento)
# Aggiungi le API key al .env del progetto
```

## Uso

```bash
# Feature nuova con brief inline
./ai-pipeline/pipeline.sh button-outline \
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
│   ├── display.sh       # UI terminale (box, spinner, semi-log)
│   ├── claude.sh        # Claude CLI execution
│   ├── state.sh         # State management
│   └── verdict.sh       # Gate logic
├── prompts/             # Un file .md per agente (creare)
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

## Display terminale

Durante l'esecuzione ogni step attivo mostra un box live con spinner Braille, elapsed time e le ultime 5 tool calls in formato semi-log:

```
  ┌─ dev (claude-sonnet-4-6) ────────────────────── 4m12s ──┐
  │ ⠸ Lavorando...                                           │
  │                                                          │
  │ ~ Write    ButtonOutline.vue                             │
  │ ~ Write    ButtonOutline.test.ts                         │
  │ ~ Edit     index.vue                                     │
  │ ~ Bash     pnpm typecheck → exit 0                       │
  │ ~ Read     Button.vue                                    │
  │                                       (+18 azioni)       │
  └──────────────────────────────────────────────────────────┘
```

## Licenza

MIT
