#!/usr/bin/env bash
# lib/context.sh — Cross-step context sharing
# Accumulates metadata (modified files, routes, components) between pipeline steps
# so downstream agents can avoid redundant exploration.

CONTEXT_DIR="${PIPELINE_DIR}/context"

# ---------------------------------------------------------------------------
# context_init <feature>
# Creates/resets the context file for a new pipeline execution.
# ---------------------------------------------------------------------------
context_init() {
    local feature="$1"
    mkdir -p "$CONTEXT_DIR"
    cat > "${CONTEXT_DIR}/${feature}.json" << EOF
{
  "feature": "${feature}",
  "files_modified": [],
  "steps_completed": []
}
EOF
}

# ---------------------------------------------------------------------------
# context_add_files <feature> <file1> [file2 ...]
# Adds files to the context (deduplicates).
# ---------------------------------------------------------------------------
context_add_files() {
    local feature="$1"
    shift
    local ctx_file="${CONTEXT_DIR}/${feature}.json"

    [[ ! -f "$ctx_file" ]] && return 0
    [[ $# -eq 0 ]] && return 0

    # Build JSON array of new files
    local files_json="["
    local first=true
    for f in "$@"; do
        [[ -z "$f" ]] && continue
        if [[ "$first" == "true" ]]; then
            files_json+="\"${f}\""
            first=false
        else
            files_json+=",\"${f}\""
        fi
    done
    files_json+="]"

    python3 - "$ctx_file" "$files_json" <<'PYEOF'
import sys, json

path = sys.argv[1]
new_files = json.loads(sys.argv[2])

with open(path) as f:
    data = json.load(f)

existing = set(data.get("files_modified", []))
for f in new_files:
    existing.add(f)
data["files_modified"] = sorted(existing)

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}

# ---------------------------------------------------------------------------
# context_add_step <feature> <step_name>
# Records a completed step in the context.
# ---------------------------------------------------------------------------
context_add_step() {
    local feature="$1"
    local step="$2"
    local ctx_file="${CONTEXT_DIR}/${feature}.json"

    [[ ! -f "$ctx_file" ]] && return 0

    python3 - "$ctx_file" "$step" <<'PYEOF'
import sys, json

path = sys.argv[1]
step = sys.argv[2]

with open(path) as f:
    data = json.load(f)

steps = data.get("steps_completed", [])
if step not in steps:
    steps.append(step)
data["steps_completed"] = steps

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}
