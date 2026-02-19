# Status implementazione

## Tasks completati

| # | Task | File | Commit |
|---|------|------|--------|
| 1 | Cleanup repo — rimosse wizard/, templates/, init.sh; scaffolding nuove dir | — | `ceca537` |
| 2 | `lib/config.sh` — YAML parser con python3 | `lib/config.sh` | `7a88c74` |
| 3 | `lib/display.sh` — UI terminale: box ASCII, spinner Braille, semi-log | `lib/display.sh` | `9915c54` |
| 4 | `lib/state.sh` — gestione state.json | `lib/state.sh` | `c0d79e1` |
| 5 | `lib/verdict.sh` — gate file-based APPROVED/REJECTED | `lib/verdict.sh` | `6c93988` |
| 6 | `lib/claude.sh` — esecuzione claude CLI con streaming e token retry | `lib/claude.sh` | `0f3a0e6` |
| 7 | `pipeline.sh` — orchestratore principale | `pipeline.sh` | `336dbd5` + `8a6c8d9` |
| 8 | Config e template files | `pipeline.yaml`, `.mcp.json`, `example/prompts/` | `23401b8` |
| 9 | `.gitignore`, `README.md` | — | `198f4a0` |
| 10 | Test dry-run — `--help` ✓, `--state` ✓, `--dry-run` ✓ | — | — |

## Pending

### Task 11 — Test reale con claude CLI

**Obiettivo:** eseguire un singolo step (`pm`) con claude CLI e verificare che funzioni end-to-end.

**Bloccato:** `ANTHROPIC_API_KEY` non impostata nell'env di sviluppo.

**Comando da eseguire:**
```bash
export ANTHROPIC_API_KEY=sk-ant-...
bash pipeline.sh test-feature --only pm --description "test feature descrizione"
```

**Cosa verificare:**
- Header box visualizzato correttamente
- Spinner animato durante l'esecuzione
- Tool calls mostrati nel semi-log
- `specs/test-feature.md` creato da claude
- Log scritto in `logs/test-feature-pm.log`
- Step marcato come completato

## Struttura progetto

```
pipeline.sh              # entry point
lib/
  config.sh              # YAML parsing (python3)
  display.sh             # terminal UI
  state.sh               # state.json management
  verdict.sh             # .verdict gate logic
  claude.sh              # claude CLI wrapper
pipeline.yaml            # config pipeline
.mcp.json                # MCP servers per step
prompts/
  pm.md                  # prompt PM (esiste, semplice)
example/prompts/         # template di esempio completi
  pm.md, dr-spec.md, dev.md, qa.md
docs/
  STATUS.md              # questo file
```

## Bug risolti in questa sessione

- `status` read-only in zsh → rinominato `step_status` in `lib/display.sh`
- Funzioni helper nested dentro `_main()` → spostate al top level in `pipeline.sh` (fix: `8a6c8d9`)
