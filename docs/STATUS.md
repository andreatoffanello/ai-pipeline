# AI Pipeline — Status e Handoff

> Documento di handoff per continuare lo sviluppo in una nuova sessione AI.

## Obiettivo del progetto

`ai-pipeline` è un orchestratore bash portabile per pipeline AI multi-step.
Si mette nella cartella di qualsiasi progetto e coordina agenti Claude su feature requests.

**Caratteristiche chiave:**
- Config YAML (`pipeline.yaml`) — steps, modelli, provider, gate di approvazione
- Gate file-based: ogni step "reviewer" scrive `APPROVED` o `REJECTED` in un file `.verdict`
- Display terminale: box ASCII con spinner Braille e semi-log dei tool calls in tempo reale
- Provider routing: env vars per puntare a OpenAI-compat API, Ollama, ecc.
- Portabile: basta copiare la cartella `ai-pipeline/` in qualsiasi repo

## Stato corrente

**Task completati (10/11):**

| # | Task | Stato |
|---|------|-------|
| 1 | Cleanup repo, scaffolding directory | ✅ |
| 2 | `lib/config.sh` — YAML parser | ✅ |
| 3 | `lib/display.sh` — terminal UI | ✅ |
| 4 | `lib/state.sh` — state.json | ✅ |
| 5 | `lib/verdict.sh` — gate logic | ✅ |
| 6 | `lib/claude.sh` — claude CLI wrapper | ✅ |
| 7 | `pipeline.sh` — orchestratore principale | ✅ |
| 8 | `pipeline.yaml`, `.mcp.json`, `example/prompts/` | ✅ |
| 9 | `.gitignore`, `README.md` | ✅ |
| 10 | Test dry-run (`--help`, `--state`, `--dry-run`) | ✅ |
| 11 | **Test reale con claude CLI** | ⏳ pending |

**Task 11 — bloccato su API key:**
```bash
export ANTHROPIC_API_KEY=sk-ant-...
bash pipeline.sh test-feature --only pm --description "test"
```
Cosa verificare: header box, spinner, tool calls nel semi-log,
`specs/test-feature.md` creato, log in `logs/test-feature-pm.log`.

## Struttura file

```
pipeline.sh              # entry point — chmod +x, bash 3.2+
lib/
  config.sh              # YAML parsing via python3 inline scripts
  display.sh             # terminal UI: box, spinner Braille, semi-log
  state.sh               # state.json tracking (python3)
  verdict.sh             # .verdict gate: APPROVED/REJECTED/MISSING
  claude.sh              # claude CLI: streaming, token retry, provider routing
pipeline.yaml            # config: nome, steps, provider, modelli, gate
.mcp.json                # MCP servers per step (es. playwright)
prompts/
  pm.md                  # prompt PM (esiste, minimal)
example/prompts/         # template prompts completi da copiare in prompts/
  pm.md, dr-spec.md, dev.md, qa.md
briefs/                  # input: brief feature (gitignored)
specs/                   # output dr-spec step (gitignored)
reviews/                 # output review step (gitignored)
qa/                      # output qa step (gitignored)
verdicts/                # gate files .verdict (gitignored)
logs/                    # stream-json logs (gitignored)
docs/
  STATUS.md              # questo file
```

## Come funziona (flusso completo)

```
pipeline.sh <feature> [options]
  └─ _main()
       ├─ CLI parsing
       ├─ prerequisiti (claude, python3, pipeline.yaml)
       └─ _run_pipeline()
            ├─ per ogni step in pipeline.yaml:
            │    ├─ legge config step (model, provider, allowed_tools, verdict, on_reject)
            │    ├─ claude_setup_provider() → imposta ANTHROPIC_BASE_URL, API_KEY
            │    ├─ costruisce prompt finale (template + ${FEATURE} + brief + gate instruction)
            │    ├─ display_box_start() → spinner in background
            │    ├─ claude_run() → CLAUDECODE= claude -p --output-format stream-json
            │    ├─ display_box_stop()
            │    └─ se verdict:true → legge .verdict → APPROVED continua / REJECTED retry
            └─ display_success()
```

## pipeline.yaml — formato

```yaml
pipeline:
  name: my-project

defaults:
  provider: anthropic
  model: claude-sonnet-4-5-20250929
  allowed_tools: Read,Write,Edit,Bash,Glob,Grep
  max_retries: 2
  token_max_retries: 5
  token_base_delay: 60

steps:
  pm:
    model: claude-opus-4-6
    prompt: prompts/pm.md          # relativo alla dir pipeline
    output: specs/${FEATURE}.md    # ${FEATURE} viene sostituito

  dr-spec:
    model: claude-sonnet-4-5-20250929
    prompt: prompts/dr-spec.md
    output: reviews/${FEATURE}-dr-spec.md
    verdict: true                  # attende APPROVED/REJECTED nel .verdict
    on_reject: dev                 # step da eseguire se REJECTED

  dev:
    model: claude-sonnet-4-5-20250929
    prompt: prompts/dev.md

  qa:
    model: claude-sonnet-4-5-20250929
    prompt: prompts/qa.md
    output: qa/${FEATURE}-qa.md
    verdict: true
    mcp_servers:
      - playwright

providers:
  anthropic:
    api_key_env: ANTHROPIC_API_KEY
  kimi:
    base_url: https://api.moonshot.cn/v1
    api_key_env: KIMI_API_KEY
  ollama:
    base_url: http://localhost:11434/v1
```

## Dettagli implementativi importanti

### lib/config.sh
- Nessun `yq` o `jq` — tutto via `python3 -c`
- `config_steps_names` → lista step nell'ordine del YAML
- `config_step_get_default <step> <key> <default>` → valore o default se mancante
- `config_provider_get <provider> <key>` → base_url o api_key_env

### lib/display.sh
- Variabile `step_status` (NON `status` — è read-only in zsh)
- `display_box_start` lancia spinner in background (`_SPINNER_PID`)
- Spinner scrive in tmpdir (`$_BOX_TMPDIR/actions`), box sempre 9 righe (`_BOX_LINES=9`)
- ANSI: `\033[9A\033[J` per ridisegnare il box in-place
- `display_trap_cleanup` ferma lo spinner e ripristina il terminale

### lib/claude.sh
- `CLAUDECODE=` (stringa vuota) evita conflitti se lanciato dentro Claude Code interattivo
- Stream-json: `claude -p --verbose --output-format stream-json --allowedTools ...`
- Token exhaustion: retry con backoff esponenziale `delay = BASE_DELAY * 2^(attempt-1)`
- `_claude_parse_tool_use` riceve JSON su stdin (NON via argomento — bash heredoc interpolation fallisce)
- `_claude_filter_mcp` filtra `.mcp.json` per restituire solo i server richiesti dallo step

### lib/verdict.sh
- Gate instruction iniettata in fondo al prompt con `verdict_gate_instruction()`
- Il file `.verdict` deve contenere SOLO `APPROVED` o `REJECTED` (no spazi, no newline)
- `verdict_read` usa `tr -d '[:space:]'` prima di confrontare — fail-safe su malformato

### pipeline.sh
- Tutte le funzioni (`_pipeline_show_state`, `_run_pipeline`, `_run_reject_step`) sono al **top level** prima di `_main()`
- `_main()` contiene solo: CLI parsing + validazione + setup + chiamata a `_run_pipeline`
- `_main "$@"` chiamato alla fine del file
- `--resume` trova il primo step il cui `output` non esiste ancora su disco

## Possibili miglioramenti futuri (backlog)

- [ ] `pipeline.sh init` — wizard interattivo per creare `pipeline.yaml` di base
- [ ] Notifiche Telegram/Slack al completamento/fallimento (vedi vecchio `lib/notify.sh`)
- [ ] Supporto `--parallel` per step indipendenti
- [ ] Dashboard web minimale che legge `state.json`
- [ ] Test automatici con `bats` (bash testing framework)

## Comandi rapidi per verificare che tutto funzioni

```bash
# Sintassi OK
bash -n pipeline.sh && echo "OK"
bash -n lib/config.sh && echo "OK"
bash -n lib/display.sh && echo "OK"
bash -n lib/state.sh && echo "OK"
bash -n lib/verdict.sh && echo "OK"
bash -n lib/claude.sh && echo "OK"

# Help
bash pipeline.sh --help

# Dry-run (non richiede API key)
bash pipeline.sh test-feature --dry-run --description "prova"

# State (legge state.json se esiste)
bash pipeline.sh --state

# Test reale (richiede ANTHROPIC_API_KEY)
export ANTHROPIC_API_KEY=sk-ant-...
bash pipeline.sh test-feature --only pm --description "test feature"
```
