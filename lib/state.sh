#!/usr/bin/env bash
# lib/state.sh — Pipeline state management (state.json)

# State file location — set by pipeline.sh
PIPELINE_STATE_FILE="${PIPELINE_STATE_FILE:-${PIPELINE_DIR}/state.json}"

# ---------------------------------------------------------------------------
# state_init <feature>
# Crea/resetta il file di stato per una nuova esecuzione.
# ---------------------------------------------------------------------------
state_init() {
    local feature="$1"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$PIPELINE_STATE_FILE" <<EOF
{
  "feature": "${feature}",
  "started_at": "${now}",
  "updated_at": "${now}",
  "current_step": null,
  "status": "running",
  "steps": {}
}
EOF
}

# ---------------------------------------------------------------------------
# state_step_start <step_name>
# ---------------------------------------------------------------------------
state_step_start() {
    local step="$1"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    _state_update_step "$step" "in_progress" "0" "$now" ""
}

# ---------------------------------------------------------------------------
# state_step_done <step_name> <elapsed_seconds> [retries]
# ---------------------------------------------------------------------------
state_step_done() {
    local step="$1"
    local elapsed="$2"
    local retries="${3:-0}"
    _state_update_step "$step" "completed" "$retries" "" "$elapsed"
    # Registra token usage se disponibile
    if [[ "${CLAUDE_LAST_INPUT_TOKENS:-0}" -gt 0 ]] || [[ "${CLAUDE_LAST_OUTPUT_TOKENS:-0}" -gt 0 ]]; then
        _state_set_step_tokens "$step" "${CLAUDE_LAST_INPUT_TOKENS:-0}" "${CLAUDE_LAST_OUTPUT_TOKENS:-0}"
    fi
}

# ---------------------------------------------------------------------------
# state_get_total_cost
# Calcola e restituisce il costo totale stimato (USD) basato sui token registrati.
# ---------------------------------------------------------------------------
state_get_total_cost() {
    [[ ! -f "$PIPELINE_STATE_FILE" ]] && echo "" && return
    python3 - "$PIPELINE_STATE_FILE" <<'PYEOF'
import sys, json

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except:
    sys.exit(0)

total_input = 0
total_output = 0
for step_name, step_data in data.get("steps", {}).items():
    total_input += step_data.get("input_tokens", 0)
    total_output += step_data.get("output_tokens", 0)

if total_input == 0 and total_output == 0:
    sys.exit(0)

# Pricing approssimativo (Sonnet 4.6: $3/MTok input, $15/MTok output)
# Opus 4.6: $15/MTok input, $75/MTok output
# Usiamo una media conservativa
cost = (total_input * 3.0 / 1_000_000) + (total_output * 15.0 / 1_000_000)
print(f"{cost:.2f}")
PYEOF
}

# ---------------------------------------------------------------------------
# state_step_fail <step_name> <reason>
# ---------------------------------------------------------------------------
state_step_fail() {
    local step="$1"
    local reason="$2"
    _state_update_step "$step" "failed" "0" "" ""
    _state_set_field "status" "failed"
    _state_set_field "error" "$reason"
}

# ---------------------------------------------------------------------------
# state_done
# Marca la pipeline come completata.
# ---------------------------------------------------------------------------
state_done() {
    _state_set_field "status" "completed"
    _state_set_field "current_step" "null"
    _state_update_timestamp
}

# ---------------------------------------------------------------------------
# state_show
# Stampa lo stato corrente.
# ---------------------------------------------------------------------------
state_show() {
    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then
        echo "  Nessuna pipeline in corso." >&2
        return 1
    fi
    cat "$PIPELINE_STATE_FILE"
}

# ---------------------------------------------------------------------------
# state_get_current_step
# ---------------------------------------------------------------------------
state_get_current_step() {
    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then
        echo ""
        return
    fi
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
s = d.get('current_step') or ''
print(s)
" "$PIPELINE_STATE_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# state_step_status <step_name>
# Returns: pending | in_progress | completed | failed
# ---------------------------------------------------------------------------
state_step_status() {
    local step="$1"
    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then
        echo "pending"
        return
    fi
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
s = d.get('steps', {}).get(sys.argv[2], {})
print(s.get('status', 'pending'))
" "$PIPELINE_STATE_FILE" "$step" 2>/dev/null || echo "pending"
}

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

_state_set_field() {
    local field="$1"
    local value="$2"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then return; fi

    python3 - "$PIPELINE_STATE_FILE" "$field" "$value" "$now" <<'PYEOF'
import sys, json

with open(sys.argv[1]) as f:
    data = json.load(f)

field = sys.argv[2]
value = sys.argv[3]
now = sys.argv[4]

data[field] = None if value == 'null' else value
data['updated_at'] = now

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}

_state_update_step() {
    local step="$1"
    local step_status="$2"
    local retries="$3"
    local started_at="${4:-}"
    local elapsed="${5:-}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then return; fi

    python3 - "$PIPELINE_STATE_FILE" "$step" "$step_status" "$retries" \
        "$started_at" "$elapsed" "$now" <<'PYEOF'
import sys, json

with open(sys.argv[1]) as f:
    data = json.load(f)

step = sys.argv[2]
step_status = sys.argv[3]
retries = int(sys.argv[4])
started_at = sys.argv[5]
elapsed = sys.argv[6]
now = sys.argv[7]

if 'steps' not in data:
    data['steps'] = {}

data['steps'][step] = {
    'status': step_status,
    'retries': retries,
}
if started_at:
    data['steps'][step]['started_at'] = started_at
if elapsed:
    data['steps'][step]['elapsed_seconds'] = int(elapsed)

if step_status == 'in_progress':
    data['current_step'] = step
data['updated_at'] = now

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}

_state_set_step_tokens() {
    local step="$1"
    local input_tokens="$2"
    local output_tokens="$3"

    [[ ! -f "$PIPELINE_STATE_FILE" ]] && return

    python3 - "$PIPELINE_STATE_FILE" "$step" "$input_tokens" "$output_tokens" <<'PYEOF'
import sys, json

with open(sys.argv[1]) as f:
    data = json.load(f)

step = sys.argv[2]
input_t = int(sys.argv[3])
output_t = int(sys.argv[4])

if step in data.get("steps", {}):
    data["steps"][step]["input_tokens"] = input_t
    data["steps"][step]["output_tokens"] = output_t

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}

_state_update_timestamp() {
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then return; fi
    python3 - "$PIPELINE_STATE_FILE" "$now" <<'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
data['updated_at'] = sys.argv[2]
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}

# ===========================================================================
# Batch state management (batch-state.json)
# ===========================================================================

PIPELINE_BATCH_STATE_FILE="${PIPELINE_BATCH_STATE_FILE:-${PIPELINE_DIR}/batch-state.json}"

# ---------------------------------------------------------------------------
# batch_state_init <features_json>
# Crea batch-state.json per una nuova esecuzione batch.
# features_json: array JSON di nomi feature, es. '["feat1","feat2"]'
# ---------------------------------------------------------------------------
batch_state_init() {
    local features_json="$1"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 - "$PIPELINE_BATCH_STATE_FILE" "$features_json" "$now" <<'PYEOF'
import sys, json

path = sys.argv[1]
features = json.loads(sys.argv[2])
now = sys.argv[3]

data = {
    "mode": "batch",
    "started_at": now,
    "updated_at": now,
    "total": len(features),
    "completed": 0,
    "failed": 0,
    "skipped": 0,
    "status": "running",
    "features": {}
}

for f in features:
    data["features"][f] = {"status": "pending"}

with open(path, 'w') as fh:
    json.dump(data, fh, indent=2)
PYEOF
}

# ---------------------------------------------------------------------------
# batch_state_feature_start <feature>
# ---------------------------------------------------------------------------
batch_state_feature_start() {
    local feature="$1"
    _batch_state_update_feature "$feature" "in_progress"
}

# ---------------------------------------------------------------------------
# batch_state_feature_done <feature> <elapsed_str>
# ---------------------------------------------------------------------------
batch_state_feature_done() {
    local feature="$1"
    local elapsed="${2:-}"
    _batch_state_update_feature "$feature" "completed" "$elapsed"
}

# ---------------------------------------------------------------------------
# batch_state_feature_fail <feature> <exit_code>
# ---------------------------------------------------------------------------
batch_state_feature_fail() {
    local feature="$1"
    local exit_code="${2:-1}"
    _batch_state_update_feature "$feature" "failed" "" "$exit_code"
}

# ---------------------------------------------------------------------------
# batch_state_feature_skip <feature>
# ---------------------------------------------------------------------------
batch_state_feature_skip() {
    local feature="$1"
    _batch_state_update_feature "$feature" "skipped"
}

# ---------------------------------------------------------------------------
# batch_state_done [status]
# Finalizza il batch-state.json. Default status=completed.
# ---------------------------------------------------------------------------
batch_state_done() {
    local status="${1:-completed}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    [[ ! -f "$PIPELINE_BATCH_STATE_FILE" ]] && return

    python3 - "$PIPELINE_BATCH_STATE_FILE" "$status" "$now" <<'PYEOF'
import sys, json

path = sys.argv[1]
status = sys.argv[2]
now = sys.argv[3]

with open(path) as f:
    data = json.load(f)

data["status"] = status
data["updated_at"] = now

completed = sum(1 for v in data["features"].values() if v["status"] == "completed")
failed = sum(1 for v in data["features"].values() if v["status"] == "failed")
skipped = sum(1 for v in data["features"].values() if v["status"] == "skipped")

data["completed"] = completed
data["failed"] = failed
data["skipped"] = skipped

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}

# ---------------------------------------------------------------------------
# _batch_state_update_feature <feature> <status> [elapsed] [exit_code]
# ---------------------------------------------------------------------------
_batch_state_update_feature() {
    local feature="$1"
    local feature_status="$2"
    local elapsed="${3:-}"
    local exit_code="${4:-}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    [[ ! -f "$PIPELINE_BATCH_STATE_FILE" ]] && return

    python3 - "$PIPELINE_BATCH_STATE_FILE" "$feature" "$feature_status" \
        "$elapsed" "$exit_code" "$now" <<'PYEOF'
import sys, json

path = sys.argv[1]
feature = sys.argv[2]
status = sys.argv[3]
elapsed = sys.argv[4]
exit_code = sys.argv[5]
now = sys.argv[6]

with open(path) as f:
    data = json.load(f)

if feature not in data["features"]:
    data["features"][feature] = {}

data["features"][feature]["status"] = status
if elapsed:
    data["features"][feature]["elapsed"] = elapsed
if exit_code:
    data["features"][feature]["exit_code"] = int(exit_code)
if status == "in_progress":
    data["features"][feature]["started_at"] = now

data["updated_at"] = now

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}
