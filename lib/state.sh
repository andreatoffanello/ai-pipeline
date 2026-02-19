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
