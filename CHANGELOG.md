# Changelog

## [Unreleased] — Enhance Code Quality & Autonomy

### Nuovi File

- **`lib/verify.sh`** — Verifica deterministica post-step (build, lint, test)
  - `verify_run()`: esegue i comandi configurati dopo step DEV/DEV-FIX
  - `verify_get_errors()`: restituisce gli errori per iniettarli nel retry
  - Configurabile in `pipeline.yaml` sezione `verify`

- **`lib/context.sh`** — Contesto condiviso cross-step
  - `context_init()`: crea `context/<feature>.json` all'avvio della pipeline
  - `context_add_files()`: registra file modificati da ogni step
  - `context_add_step()`: registra step completati
  - Gli agenti successivi leggono il context per evitare esplorazione ridondante

### Modifiche a `pipeline.sh`

- **Verify gate** (riga ~440): dopo `claude_run` per step dev/dev-fix, esegue `verify_run()`. Se fallisce, inietta gli errori come contesto nel retry
- **Integration check** (riga ~487): dopo `state_done`, esegue i comandi di integrazione configurati in `pipeline.yaml`
- **Model escalation on retry** (riga ~361): se `model_on_retry` è configurato per lo step, scala al modello più potente dal secondo tentativo
- **Context tracking** (riga ~462): dopo ogni step completato, aggiorna `context/<feature>.json`
- **Dry-run migliorato** (riga ~399): mostra word count, sezioni del prompt, e output formattato
- **Retry banner** (riga ~447): usa `display_retry_banner` per contesto visivo nei retry

### Modifiche a `pipeline.yaml`

Nuove sezioni di configurazione:

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

integration:
  enabled: true
  commands:
    - "pnpm lint --no-fix"
    - "pnpm build"

notifications:
  webhook_url: ""
```

Nuovo campo per step:
```yaml
model_on_retry: claude-opus-4-6  # scala a opus se il primo tentativo fallisce
```

### Modifiche a `lib/claude.sh`

- **Token usage tracking**: dopo ogni `claude_run`, parsa i token dal log stream-json e li espone in `CLAUDE_LAST_INPUT_TOKENS` / `CLAUDE_LAST_OUTPUT_TOKENS`
- **`_claude_parse_token_usage()`**: nuova funzione che estrae input/output tokens dal log
- **Token exhaustion detection**: pattern regex più specifico per evitare false positive (es. codice JWT che contiene "token")

### Modifiche a `lib/state.sh`

- **`_state_set_step_tokens()`**: registra input/output tokens per step in `state.json`
- **`state_get_total_cost()`**: calcola costo stimato basato sui token (pricing Sonnet 4.6)
- `state_step_done()` ora salva automaticamente i token usage

### Modifiche a `lib/display.sh`

- **Spinner a 3 righe**: riga 1 (tool), riga 2 (playwright), riga 3 (pipeline overview con stato di ogni step)
- **Per-tool action counters**: `display_box_stop` mostra `(42 azioni: Write:15 Edit:12 Read:8 Bash:5 Glob:2)`
- **`display_retry_banner()`**: box giallo compatto `↺ Retry 1/3 step_name → reason`
- **`display_success()`**: mostra costo stimato nel box finale
- **`_notify()` cross-platform**: supporto macOS (osascript), Linux (notify-send), webhook HTTP

### Modifiche a `lib/prompt.sh`

- **Revalidation migliorata**: i reviewer possono ora segnalare `NEW-001, NEW-002` per problemi introdotti dalla correzione (prima era vietato aggiungere nuove REV)
- **Retry incrementale**: istruzioni più forti per modifiche con Edit (non riscritture), no re-esplorazione del codebase
- **Context injection**: se `context/<feature>.json` esiste, viene referenziato nel prompt

### Modifiche ai Prompts

#### `prompts/dev.md`
- Aggiunta sezione "Dopo l'implementazione — OBBLIGATORIO" con istruzioni per eseguire lint, build, test prima di completare

#### `prompts/dev-fix.md`
- Aggiunta sezione "Dopo le correzioni — OBBLIGATORIO" con stesse verifiche
- Enfasi su "usa Edit, non riscrivere da zero"

#### `prompts/qa.md`
- Aggiunta sezione "In caso di ri-validazione (retry dopo DEV-FIX)"
- Obbligo di ri-testare TUTTI i criteri, non solo quelli falliti
- Label `[RE-TEST]` e `[FIX-VERIFY]` per tracciabilità nel report

#### `prompts/dr-impl.md`
- Sezione "Cosa valutare" sostituita con **Checklist Obbligatoria** binaria
  - A. Code Quality (7 punti)
  - B. Visual Quality (8 punti — da verificare in Playwright)
  - C. Functional Completeness (4 punti)
- "Ogni punto FAIL diventa una REV. NON approvare se anche UN solo punto fallisce."

### Come Usare le Nuove Funzionalità

#### Verify (automatico)
Se `verify.enabled: true` in pipeline.yaml, la verifica avviene automaticamente dopo step dev e dev-fix. Se fallisce, il retry include gli errori di build/lint come contesto.

#### Integration Check (automatico)
Se `integration.enabled: true`, dopo che tutti i gate passano viene eseguito un check finale di integrazione.

#### Model Escalation
Aggiungi `model_on_retry: claude-opus-4-6` a uno step per scalare automaticamente a un modello più potente dal secondo tentativo.

#### Webhook Notifications
Configura `notifications.webhook_url` in pipeline.yaml per ricevere notifiche HTTP POST per ogni evento pipeline (gate, completion, failure).

#### Disabilitare Verify/Integration
Per disabilitare:
```yaml
verify:
  enabled: false

integration:
  enabled: false
```
