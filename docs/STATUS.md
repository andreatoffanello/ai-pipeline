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
- Conventions e skills Nuxt 4 opinionated — leggibili dagli agenti via Read tool
- Portabile: basta copiare la cartella `ai-pipeline/` in qualsiasi repo

## Stato corrente

**Tutto completato (11/11 + conventions/skills):**

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
| — | `conventions/` — stack, visual, code | ✅ |
| — | `skills/` — component, store, page, playwright | ✅ |
| — | `example/prompts/` aggiornati con conventions/skills | ✅ |

## Unico pending

**Test reale con claude CLI:**
```bash
export ANTHROPIC_API_KEY=sk-ant-...
bash pipeline.sh test-feature --only pm --description "test feature"
```
Cosa verificare: header box, spinner animato, tool calls nel semi-log,
`specs/test-feature.md` creato, log in `logs/test-feature-pm.log`.

## Struttura completa del progetto

```
pipeline.sh              # entry point
lib/
  config.sh              # YAML parsing (python3)
  display.sh             # terminal UI: box, spinner Braille, semi-log
  state.sh               # state.json tracking
  verdict.sh             # .verdict gate: APPROVED/REJECTED/MISSING
  claude.sh              # claude CLI: streaming, token retry, provider routing
pipeline.yaml            # config: nome, steps, provider, modelli, gate
.mcp.json                # MCP servers per step (playwright)
conventions/             # regole fisse del progetto — lette dagli agenti
  stack.md               # Nuxt4, Pinia, VueUse, i18n, no TS, JSDoc, ES6
  visual.md              # awwwards quality, design tokens, CSS rules
  code.md                # naming, struttura, leggibilità, anti-pattern
skills/                  # guide operative per tipo di artefatto
  component.md           # Vue SFC: struttura, checklist, anti-pattern
  store.md               # Pinia composition API: template completo
  page.md                # Nuxt page: stati loading/error/empty, test page
  playwright.md          # test visivi reali: screenshot, data-testid, awwwards
prompts/
  pm.md                  # prompt PM (stub minimale — copiare da example/prompts/)
example/prompts/         # template pronti all'uso, referenziano conventions/skills
  pm.md, dr-spec.md, dev.md, qa.md
docs/
  STATUS.md              # questo file
  plans/                 # piani di implementazione
    2026-02-20-conventions-skills.md
briefs/                  # input: brief feature (gitignored)
specs/                   # output pm step (gitignored)
reviews/                 # output dr-spec step (gitignored)
qa/                      # output qa step (gitignored)
verdicts/                # gate files .verdict (gitignored)
logs/                    # stream-json logs (gitignored)
```

## Come usare la pipeline in un progetto

1. Copia la cartella `ai-pipeline/` nella root del progetto
2. Copia `example/prompts/*.md` in `prompts/` e adattali al progetto
3. Adatta `pipeline.yaml` al progetto (nome, steps, modelli)
4. Lancia: `bash ai-pipeline/pipeline.sh nome-feature --description "..."`

## Come funziona il flusso

```
pipeline.sh <feature> [options]
  └─ _main()
       ├─ CLI parsing
       ├─ prerequisiti (claude, python3, pipeline.yaml)
       └─ _run_pipeline()
            ├─ per ogni step in pipeline.yaml:
            │    ├─ legge config step (model, provider, tools, verdict)
            │    ├─ costruisce prompt (template + ${FEATURE} + brief + gate instruction)
            │    ├─ display_box_start() → spinner background
            │    ├─ claude_run() → CLAUDECODE= claude -p --output-format stream-json
            │    ├─ display_box_stop()
            │    └─ se verdict:true → legge .verdict → APPROVED/REJECTED
            └─ display_success()
```

## Dettagli implementativi critici

- `CLAUDECODE=` (stringa vuota) — evita conflitti se lanciato dentro Claude Code
- `status` è read-only in zsh → la variabile è rinominata `step_status` in display.sh
- Tutte le funzioni (`_pipeline_show_state`, `_run_pipeline`, `_run_reject_step`) sono
  al **top level** in pipeline.sh — non nested dentro `_main()`
- `_main()` contiene solo: CLI parsing + validazione + setup + `_run_pipeline`
- Spinner: background subprocess, tmpdir per action lines, box sempre 9 righe

## Comandi rapidi

```bash
# Sintassi OK su tutti i file
bash -n pipeline.sh lib/config.sh lib/display.sh lib/state.sh lib/verdict.sh lib/claude.sh

# Help
bash pipeline.sh --help

# Dry-run (non richiede API key)
bash pipeline.sh test-feature --dry-run --description "prova"

# State
bash pipeline.sh --state

# Test reale (richiede ANTHROPIC_API_KEY)
export ANTHROPIC_API_KEY=sk-ant-...
bash pipeline.sh test-feature --only pm --description "test"
```
