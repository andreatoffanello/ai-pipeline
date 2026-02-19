#!/usr/bin/env bash
# lib/config.sh — Pipeline YAML configuration parser
# Requires: python3 (standard on macOS/Linux)

# Loaded by pipeline.sh via: source "$SCRIPT_DIR/lib/config.sh"
# All functions use PIPELINE_CONFIG_FILE (set by pipeline.sh)

# ---------------------------------------------------------------------------
# config_get <key>
# Get a scalar value from the top-level pipeline config.
# Usage: config_get "pipeline.name"  →  "my-project"
# ---------------------------------------------------------------------------
config_get() {
    local key="$1"
    python3 - "$PIPELINE_CONFIG_FILE" "$key" <<'PYEOF'
import sys, re

def get_nested(data, path):
    keys = path.split('.')
    cur = data
    for k in keys:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return None
    return cur

# Minimal YAML parser (handles simple key: value and nested dicts)
def parse_yaml(text):
    result = {}
    stack = [(0, result)]
    for line in text.splitlines():
        if not line.strip() or line.strip().startswith('#'):
            continue
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if ':' not in stripped:
            continue
        key, _, val = stripped.partition(':')
        key = key.strip()
        val = val.strip().strip('"\'')
        # pop stack to current indent level
        while len(stack) > 1 and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if val:
            parent[key] = val
        else:
            parent[key] = {}
            stack.append((indent, parent[key]))
    return result

with open(sys.argv[1]) as f:
    data = parse_yaml(f.read())

val = get_nested(data, sys.argv[2])
if val is not None and not isinstance(val, dict):
    print(val)
PYEOF
}

# ---------------------------------------------------------------------------
# config_get_default <key> <default>
# Like config_get but returns default if key not found or empty.
# ---------------------------------------------------------------------------
config_get_default() {
    local key="$1"
    local default="$2"
    local val
    val=$(config_get "$key")
    echo "${val:-$default}"
}

# ---------------------------------------------------------------------------
# config_steps_names
# Returns all step names in order, one per line.
# ---------------------------------------------------------------------------
config_steps_names() {
    python3 - "$PIPELINE_CONFIG_FILE" <<'PYEOF'
import sys

with open(sys.argv[1]) as f:
    lines = f.readlines()

in_steps = False
for line in lines:
    stripped = line.strip()
    if stripped == 'steps:':
        in_steps = True
        continue
    if in_steps:
        if stripped.startswith('- name:'):
            print(stripped.split(':', 1)[1].strip().strip('"\''))
        elif stripped and not stripped.startswith('-') and not stripped.startswith('#') and not line.startswith(' '):
            break
PYEOF
}

# ---------------------------------------------------------------------------
# config_step_get <step_name> <field>
# Get a field value from a specific step definition.
# Returns empty string if not found.
# ---------------------------------------------------------------------------
config_step_get() {
    local step_name="$1"
    local field="$2"
    python3 - "$PIPELINE_CONFIG_FILE" "$step_name" "$field" <<'PYEOF'
import sys

with open(sys.argv[1]) as f:
    lines = f.readlines()

step_name = sys.argv[2]
field = sys.argv[3]

in_steps = False
in_target = False
for line in lines:
    stripped = line.strip()
    if stripped == 'steps:':
        in_steps = True
        continue
    if not in_steps:
        continue
    if stripped == f'- name: {step_name}' or stripped == f"- name: '{step_name}'" or stripped == f'- name: "{step_name}"':
        in_target = True
        continue
    if in_target:
        if stripped.startswith('- name:'):
            break
        if stripped.startswith(f'{field}:'):
            val = stripped.split(':', 1)[1].strip().strip('"\'')
            print(val)
            break
PYEOF
}

# ---------------------------------------------------------------------------
# config_step_get_default <step_name> <field> <default>
# Like config_step_get but returns default if not found.
# ---------------------------------------------------------------------------
config_step_get_default() {
    local step_name="$1"
    local field="$2"
    local default="$3"
    local val
    val=$(config_step_get "$step_name" "$field")
    echo "${val:-$default}"
}

# ---------------------------------------------------------------------------
# config_step_mcp_servers <step_name>
# Returns MCP server names for a step, one per line.
# ---------------------------------------------------------------------------
config_step_mcp_servers() {
    local step_name="$1"
    python3 - "$PIPELINE_CONFIG_FILE" "$step_name" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    lines = f.readlines()

step_name = sys.argv[2]
in_steps = False
in_target = False
in_mcp = False

for line in lines:
    stripped = line.strip()
    if stripped == 'steps:':
        in_steps = True
        continue
    if not in_steps:
        continue
    if stripped == f'- name: {step_name}' or stripped == f"- name: '{step_name}'" or stripped == f'- name: "{step_name}"':
        in_target = True
        continue
    if in_target:
        if stripped.startswith('- name:'):
            break
        if stripped == 'mcp_servers: []':
            break
        if stripped.startswith('mcp_servers:'):
            in_mcp = True
            continue
        if in_mcp:
            if stripped.startswith('- '):
                print(stripped[2:].strip().strip('"\''))
            else:
                break
PYEOF
}

# ---------------------------------------------------------------------------
# config_provider_get <provider_name> <field>
# Get a field from the providers section.
# ---------------------------------------------------------------------------
config_provider_get() {
    local provider="$1"
    local field="$2"
    python3 - "$PIPELINE_CONFIG_FILE" "$provider" "$field" <<'PYEOF'
import sys

with open(sys.argv[1]) as f:
    lines = f.readlines()

provider = sys.argv[2]
field = sys.argv[3]
in_providers = False
in_target = False

for line in lines:
    stripped = line.strip()
    if stripped == 'providers:':
        in_providers = True
        continue
    if not in_providers:
        continue
    if stripped == f'{provider}:':
        in_target = True
        continue
    if in_target:
        if stripped and not line.startswith('    ') and not line.startswith('  '):
            break
        if stripped.startswith(f'{field}:'):
            val = stripped.split(':', 1)[1].strip().strip('"\'')
            print(val)
            break
PYEOF
}

# ---------------------------------------------------------------------------
# config_validate
# Basic validation: checks required fields exist.
# ---------------------------------------------------------------------------
config_validate() {
    local name
    name=$(config_get "pipeline.name")
    if [[ -z "$name" ]]; then
        echo "ERROR: pipeline.name is required in pipeline.yaml" >&2
        return 1
    fi

    local steps
    steps=$(config_steps_names)
    if [[ -z "$steps" ]]; then
        echo "ERROR: No steps defined in pipeline.yaml" >&2
        return 1
    fi

    return 0
}
