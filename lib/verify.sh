#!/usr/bin/env bash
# lib/verify.sh — Post-step verification: build, lint, test
# Runs deterministic checks after DEV/DEV-FIX steps to catch errors
# that AI agents might miss (import errors, syntax errors, lint violations).
#
# Configuration in pipeline.yaml:
#   verify:
#     enabled: true
#     commands:
#       - name: lint
#         cmd: "pnpm lint --no-fix"
#       - name: build
#         cmd: "pnpm build"
#       - name: test
#         cmd: "pnpm test --run"
#     after_steps:
#       - dev
#       - dev-fix

VERIFY_DIR="${PIPELINE_DIR}/verify"

# ---------------------------------------------------------------------------
# verify_enabled
# Returns 0 if verify is enabled in pipeline.yaml, 1 otherwise.
# ---------------------------------------------------------------------------
verify_enabled() {
    local val
    val=$(config_get_default "verify.enabled" "false")
    [[ "$val" == "true" ]]
}

# ---------------------------------------------------------------------------
# verify_step_needed <step_name>
# Returns 0 if verification should run after this step.
# ---------------------------------------------------------------------------
verify_step_needed() {
    local step="$1"

    verify_enabled || return 1

    local after_steps
    after_steps=$(_verify_get_after_steps)
    [[ -z "$after_steps" ]] && return 1

    echo "$after_steps" | grep -qx "$step"
}

# ---------------------------------------------------------------------------
# verify_run <step_name> <feature>
# Runs all configured verify commands from the project root.
# Returns 0 if all pass, 1 if any fail.
# Writes combined error output to verify/<feature>-<step>.log
# ---------------------------------------------------------------------------
verify_run() {
    local step="$1"
    local feature="$2"

    mkdir -p "$VERIFY_DIR"
    local log_file="${VERIFY_DIR}/${feature}-${step}.log"
    > "$log_file"

    local project_dir
    project_dir="$(dirname "$PIPELINE_DIR")"

    local commands_json
    commands_json=$(_verify_get_commands)
    if [[ -z "$commands_json" ]]; then
        return 0
    fi

    local all_passed=true
    local total=0
    local passed=0

    # Parse commands (name|cmd pairs, one per line)
    while IFS='|' read -r cmd_name cmd_str; do
        [[ -z "$cmd_name" ]] && continue
        [[ -z "$cmd_str" ]] && continue
        total=$(( total + 1 ))

        display_info "Verify: ${cmd_name} → ${cmd_str}"

        local cmd_exit=0
        local cmd_output
        cmd_output=$(cd "$project_dir" && eval "$cmd_str" 2>&1) || cmd_exit=$?

        if [[ $cmd_exit -ne 0 ]]; then
            all_passed=false
            printf "=== VERIFY FAILED: %s (exit %d) ===\n" "$cmd_name" "$cmd_exit" >> "$log_file"
            printf "Command: %s\n" "$cmd_str" >> "$log_file"
            printf "%s\n\n" "$cmd_output" >> "$log_file"
            display_warn "Verify: ${cmd_name} FAILED (exit ${cmd_exit})"
        else
            passed=$(( passed + 1 ))
            display_info "Verify: ${cmd_name} OK"
        fi
    done <<< "$commands_json"

    if [[ "$all_passed" == "true" ]]; then
        display_info "Verify: ${passed}/${total} checks passed"
        return 0
    else
        display_warn "Verify: ${passed}/${total} checks passed — errors in ${log_file}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# verify_get_errors <feature> <step>
# Returns the content of the verify log file, truncated to max 3000 chars.
# Used to inject errors as context for the retry prompt.
# ---------------------------------------------------------------------------
verify_get_errors() {
    local feature="$1"
    local step="$2"
    local log_file="${VERIFY_DIR}/${feature}-${step}.log"

    if [[ -f "$log_file" ]]; then
        local content
        content=$(cat "$log_file")
        # Truncate to avoid overwhelming the prompt
        if [[ ${#content} -gt 3000 ]]; then
            printf "%s\n\n[... troncato — vedi %s per il log completo]" \
                "${content:0:3000}" "$log_file"
        else
            printf "%s" "$content"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

# Returns after_steps list (one per line)
_verify_get_after_steps() {
    python3 - "$PIPELINE_CONFIG_FILE" <<'PYEOF'
import sys

with open(sys.argv[1]) as f:
    lines = f.readlines()

in_verify = False
in_after = False

for line in lines:
    stripped = line.strip()
    if stripped == 'verify:':
        in_verify = True
        continue
    if not in_verify:
        continue
    # Exit verify section on un-indented line
    if stripped and not line.startswith(' ') and not line.startswith('\t'):
        break
    if stripped == 'after_steps:':
        in_after = True
        continue
    if in_after:
        if stripped.startswith('- '):
            print(stripped[2:].strip().strip('"\''))
        elif stripped and not stripped.startswith('#'):
            break
PYEOF
}

# Returns commands as "name|cmd" lines
_verify_get_commands() {
    python3 - "$PIPELINE_CONFIG_FILE" <<'PYEOF'
import sys

with open(sys.argv[1]) as f:
    lines = f.readlines()

in_verify = False
in_commands = False
current_name = ''

for line in lines:
    stripped = line.strip()
    if stripped == 'verify:':
        in_verify = True
        continue
    if not in_verify:
        continue
    if stripped and not line.startswith(' ') and not line.startswith('\t'):
        break
    if stripped == 'commands:':
        in_commands = True
        continue
    if in_commands:
        if stripped.startswith('- name:'):
            current_name = stripped.split(':', 1)[1].strip().strip('"\'')
        elif stripped.startswith('cmd:'):
            cmd = stripped.split(':', 1)[1].strip().strip('"\'')
            if current_name and cmd:
                print(f'{current_name}|{cmd}')
        elif stripped and not stripped.startswith('-') and not stripped.startswith('#') and not line.startswith('      '):
            # Check if we're exiting the commands section
            indent = len(line) - len(line.lstrip())
            if indent <= 4 and not stripped.startswith('- ') and not stripped.startswith('cmd:') and not stripped.startswith('on_fail:'):
                break
PYEOF
}
