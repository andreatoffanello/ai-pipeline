#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AI Pipeline — Autonomous Multi-Step Feature Pipeline
# ==============================================================================
#
# Configuration-driven pipeline that executes multi-step agentic workflows.
# Steps are defined in pipeline.yaml at project root.
#
# Features:
# - Configuration-driven: all steps read from pipeline.yaml
# - Meta-logging: writes .meta.json for each step
# - Pipeline state: maintains pipeline-state.json at project root
# - Decision log: tracks retries and failures in logs/decisions.jsonl
# - Exit code mapping: handles Claude CLI errors (token exhaustion, MCP failures)
# - Hooks: runs pre/post hooks for each step if they exist
# - Bash 3.2 compatible (macOS) — no declare -A, no readarray
#
# Requirements:
# - Claude Code CLI installed and authenticated
# - pipeline.yaml at project root
# - Project initialized with ai-pipeline boilerplate
#
# Usage:
#   ./scripts/pipeline.sh <feature-name> [--dry-run] [--from <step>] [--model <model>] [--state] [--config <path>]
#
# Examples:
#   ./scripts/pipeline.sh contacts
#   ./scripts/pipeline.sh contacts --from dev
#   ./scripts/pipeline.sh contacts --dry-run
#   ./scripts/pipeline.sh contacts --model opus
#   ./scripts/pipeline.sh contacts --state              # dump pipeline-state.json
#   ./scripts/pipeline.sh contacts --config custom.yaml # use alternate config
#
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configurazione default
MAX_RETRIES=2           # Max tentativi per step fallito
DEFAULT_MODEL=""        # Vuoto = usa il default di Claude Code
CONFIG_FILE=""          # Path to pipeline.yaml (default: PROJECT_ROOT/pipeline.yaml)

# Exit codes (map Claude CLI exit codes to pipeline-specific codes)
EXIT_SUCCESS=0
EXIT_BUSINESS_ERROR=1       # Agent failed task
EXIT_TOKEN_EXHAUSTED=75     # Rate limit, over capacity, token exhausted
EXIT_TOOL_FAILURE=76        # MCP tool errors
EXIT_FATAL=99               # Fatal pipeline error

# ==============================================================================
# Configuration loading — parse pipeline.yaml without yq dependency
# ==============================================================================

# Global config variables (loaded from pipeline.yaml)
CONFIG_PROMPTS_FILE=""
CONFIG_DEV_SERVER_DIR=""
CONFIG_DEV_SERVER_CMD=""
CONFIG_DEV_SERVER_PORT=""
CONFIG_SUCCESS_PATTERNS=""
CONFIG_FAIL_PATTERNS=""
CONFIG_ERROR_PATTERNS=""

# Load configuration from pipeline.yaml
load_config() {
    local config_path="${CONFIG_FILE:-${PROJECT_ROOT}/pipeline.yaml}"

    if [[ ! -f "$config_path" ]]; then
        log_error "Configuration file not found: ${config_path}"
        log_info "Create pipeline.yaml at project root. See ai-pipeline docs for template."
        exit "$EXIT_FATAL"
    fi

    log_info "Loading configuration from: ${config_path}"

    # Parse YAML using grep/sed (Bash 3.2 compatible)
    # Simple parser — assumes proper YAML indentation

    # prompts_file
    CONFIG_PROMPTS_FILE=$(grep -E '^prompts_file:' "$config_path" | sed 's/prompts_file: *//' | tr -d '"' | tr -d "'" || echo "docs/PROMPTS.md")

    # dev_server (if exists)
    if grep -q '^dev_server:' "$config_path"; then
        CONFIG_DEV_SERVER_DIR=$(grep -A10 '^dev_server:' "$config_path" | grep 'directory:' | sed 's/.*directory: *//' | tr -d '"' | tr -d "'" | head -1 || echo "")
        CONFIG_DEV_SERVER_CMD=$(grep -A10 '^dev_server:' "$config_path" | grep 'command:' | sed 's/.*command: *//' | tr -d '"' | tr -d "'" | head -1 || echo "")
        CONFIG_DEV_SERVER_PORT=$(grep -A10 '^dev_server:' "$config_path" | grep 'port:' | sed 's/.*port: *//' | tr -d '"' | tr -d "'" | head -1 || echo "3000")
    fi

    # result patterns
    CONFIG_SUCCESS_PATTERNS=$(grep -A3 '^result_patterns:' "$config_path" | grep 'success:' | sed 's/.*success: *//' | tr -d '"' | tr -d "'" || echo "PASS|APPROVATA")
    CONFIG_FAIL_PATTERNS=$(grep -A3 '^result_patterns:' "$config_path" | grep 'fail:' | sed 's/.*fail: *//' | tr -d '"' | tr -d "'" || echo "FAIL|REVISIONI RICHIESTE")

    # smoke_test error patterns
    CONFIG_ERROR_PATTERNS=$(grep -A10 '^smoke_test:' "$config_path" | grep 'error_patterns:' | sed 's/.*error_patterns: *//' | tr -d '"' | tr -d "'" || echo "error|ERR_|WARN|failed|exception|TypeError|ReferenceError")

    log_success "Configuration loaded"
}

# Get config value by key (dot notation)
get_config() {
    local key="$1"
    local config_path="${CONFIG_FILE:-${PROJECT_ROOT}/pipeline.yaml}"

    # Simple key lookup using grep
    grep -E "^${key}:" "$config_path" | sed "s/${key}: *//" | tr -d '"' | tr -d "'" || echo ""
}

# Get step configuration from pipeline.yaml
# Returns: name, model, prompt_section, output_file, retry_on_fail (all on separate lines)
get_step_config() {
    local step_name="$1"
    local config_path="${CONFIG_FILE:-${PROJECT_ROOT}/pipeline.yaml}"

    # Extract step block (multi-line)
    # Find the step in the steps: list
    local in_step=false
    local step_data=""

    while IFS= read -r line; do
        # Check if we're entering the target step
        if echo "$line" | grep -qE "^  - name: ['\"]?${step_name}['\"]?"; then
            in_step=true
            step_data="$line"
            continue
        fi

        # If in step, collect lines until next step or end of steps section
        if [[ "$in_step" == "true" ]]; then
            # Check if we hit another step (starts with "  - name:")
            if echo "$line" | grep -qE "^  - name:"; then
                break
            fi
            # Check if we left the steps section (line without leading spaces)
            if [[ ! "$line" =~ ^[[:space:]] ]] && [[ -n "$line" ]]; then
                break
            fi
            step_data="${step_data}"$'\n'"${line}"
        fi
    done < "$config_path"

    if [[ -z "$step_data" ]]; then
        echo ""
        return 1
    fi

    echo "$step_data"
}

# Get step field value
get_step_field() {
    local step_name="$1"
    local field="$2"
    local default_value="${3:-}"

    local step_config
    step_config=$(get_step_config "$step_name")

    if [[ -z "$step_config" ]]; then
        echo "$default_value"
        return
    fi

    local value
    value=$(echo "$step_config" | grep -E "^    ${field}:" | sed "s/.*${field}: *//" | tr -d '"' | tr -d "'" | head -1)

    if [[ -z "$value" ]]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Get all step names from pipeline.yaml
get_all_steps() {
    local config_path="${CONFIG_FILE:-${PROJECT_ROOT}/pipeline.yaml}"
    grep -E "^  - name:" "$config_path" | sed 's/.*name: *//' | tr -d '"' | tr -d "'"
}

# ==============================================================================
# Funzioni utility
# ==============================================================================

log_step() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

log_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_agent() {
    local color="$1"
    local agent="$2"
    local msg="$3"
    echo -e "${color}[${agent}]${NC} ${msg}"
}

# Controlla che un file esista e non sia vuoto
check_file() {
    local file="$1"
    if [[ -f "$file" ]] && [[ -s "$file" ]]; then
        return 0
    fi
    return 1
}

# Controlla il risultato nel file di review/QA
# Cerca pattern configurabili per successo/fallimento
check_result() {
    local file="$1"
    if ! check_file "$file"; then
        echo "MISSING"
        return
    fi

    local content
    content=$(cat "$file")

    # Cerca pattern di successo (configurabili)
    if echo "$content" | grep -qiE "${CONFIG_SUCCESS_PATTERNS}"; then
        echo "PASS"
        return
    fi

    # Cerca pattern di fallimento (configurabili)
    if echo "$content" | grep -qiE "${CONFIG_FAIL_PATTERNS}"; then
        echo "FAIL"
        return
    fi

    # Default: non determinabile
    echo "UNKNOWN"
}

# ==============================================================================
# Meta-logging — write .meta.json and pipeline-state.json
# ==============================================================================

# Write meta log for a step
write_meta_log() {
    local feature="$1"
    local step="$2"
    local model="$3"
    local started_at="$4"
    local ended_at="$5"
    local exit_code="$6"
    local log_file="$7"
    local retry_attempt="${8:-0}"

    local meta_dir="${PROJECT_ROOT}/logs/meta"
    mkdir -p "$meta_dir"

    local meta_file="${meta_dir}/${feature}-${step}-${retry_attempt}.meta.json"

    # Calculate duration
    local start_epoch
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || echo "0")
    local end_epoch
    end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ended_at" +%s 2>/dev/null || echo "0")
    local duration=$((end_epoch - start_epoch))

    # Write JSON (manually constructed to avoid jq dependency)
    cat > "$meta_file" <<EOF
{
  "feature": "${feature}",
  "step": "${step}",
  "model": "${model}",
  "started_at": "${started_at}",
  "ended_at": "${ended_at}",
  "duration_seconds": ${duration},
  "exit_code": ${exit_code},
  "log_file": "${log_file}",
  "retry_attempt": ${retry_attempt}
}
EOF

    log_info "Meta log written: ${meta_file}"
}

# Write/update pipeline state file
write_pipeline_state() {
    local feature="$1"
    local current_step="$2"
    local status="$3"
    local steps_completed="$4"
    local exit_code="${5:-null}"
    local error="${6:-}"

    local state_file="${PROJECT_ROOT}/pipeline-state.json"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Read existing state to preserve started_at
    local started_at="$now"
    if [[ -f "$state_file" ]]; then
        started_at=$(grep '"started_at"' "$state_file" | sed 's/.*"started_at": *"//' | sed 's/".*//' || echo "$now")
    fi

    # Convert steps_completed array to JSON array string
    # NOTE: use _s (not step) to avoid clobbering the caller's loop variable
    local steps_json="["
    local first=true
    local _s
    for _s in $steps_completed; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            steps_json="${steps_json}, "
        fi
        steps_json="${steps_json}\"${_s}\""
    done
    steps_json="${steps_json}]"

    # Error field (null or quoted string)
    local error_json="null"
    if [[ -n "$error" ]]; then
        error_json="\"${error}\""
    fi

    # Exit code (null or number)
    local exit_code_json="null"
    if [[ "$exit_code" != "null" ]]; then
        exit_code_json="$exit_code"
    fi

    # Write state file
    cat > "$state_file" <<EOF
{
  "feature": "${feature}",
  "current_step": "${current_step}",
  "status": "${status}",
  "started_at": "${started_at}",
  "last_update": "${now}",
  "steps_completed": ${steps_json},
  "exit_code": ${exit_code_json},
  "error": ${error_json}
}
EOF
}

# Log decision (retry, failure, etc.)
log_decision() {
    local feature="$1"
    local step="$2"
    local decision_type="$3"
    local reason="$4"
    local attempt="${5:-0}"

    local decisions_file="${PROJECT_ROOT}/logs/decisions.jsonl"
    mkdir -p "${PROJECT_ROOT}/logs"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Append JSONL entry
    echo "{\"timestamp\":\"${timestamp}\",\"feature\":\"${feature}\",\"step\":\"${step}\",\"type\":\"${decision_type}\",\"reason\":\"${reason}\",\"attempt\":${attempt}}" >> "$decisions_file"
}

# ==============================================================================
# Hooks — pre/post step execution
# ==============================================================================

run_hooks() {
    local step="$1"
    local hook_type="$2"  # "pre" or "post"

    local hook_script="${PROJECT_ROOT}/scripts/hooks/${hook_type}-${step}.sh"

    if [[ ! -f "$hook_script" ]]; then
        return 0
    fi

    if [[ ! -x "$hook_script" ]]; then
        log_warning "Hook script not executable: ${hook_script}"
        return 0
    fi

    log_info "Running ${hook_type}-${step} hook..."

    if bash "$hook_script" "$FEATURE"; then
        log_success "Hook ${hook_type}-${step} completed"
        return 0
    else
        log_error "Hook ${hook_type}-${step} failed"
        return 1
    fi
}

# ==============================================================================
# Live activity display — mostra cosa sta facendo Claude in tempo reale
# ==============================================================================

ACTIVITY_PID=""
LAST_LINES_FILE=""

start_activity_monitor() {
    local log_file="$1"
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    LAST_LINES_FILE=$(mktemp)

    (
        local i=0
        local last_activity="In attesa..."
        local elapsed=0

        while true; do
            local c="${spin_chars:i%${#spin_chars}:1}"

            # Leggi ultime attivita dal file di tracking
            if [[ -f "$LAST_LINES_FILE" ]] && [[ -s "$LAST_LINES_FILE" ]]; then
                local new_activity
                new_activity=$(tail -1 "$LAST_LINES_FILE" 2>/dev/null)
                if [[ -n "$new_activity" ]]; then
                    last_activity="$new_activity"
                fi
            fi

            # Calcola tempo trascorso
            local mins=$((elapsed / 600))
            local secs=$(( (elapsed / 10) % 60 ))
            local time_str
            time_str=$(printf "%d:%02d" "$mins" "$secs")

            # Mostra spinner + tempo + attivita
            local cols
            cols=$(tput cols 2>/dev/null || echo 80)
            local display="${c}  [${time_str}] ${last_activity}"
            printf "\r\033[K\033[0;36m%s\033[0m" "${display:0:$cols}"

            sleep 0.1
            i=$((i + 1))
            elapsed=$((elapsed + 1))
        done
    ) &
    ACTIVITY_PID=$!
}

stop_activity_monitor() {
    if [[ -n "$ACTIVITY_PID" ]] && kill -0 "$ACTIVITY_PID" 2>/dev/null; then
        kill "$ACTIVITY_PID" 2>/dev/null
        wait "$ACTIVITY_PID" 2>/dev/null || true
        printf "\r\033[K"
    fi
    ACTIVITY_PID=""
    if [[ -n "$LAST_LINES_FILE" ]]; then
        rm -f "$LAST_LINES_FILE"
        LAST_LINES_FILE=""
    fi
}

# Parsa una riga di stream-json e restituisce un messaggio leggibile
parse_stream_event() {
    local line="$1"

    # Tool use: estrai nome tool e input chiave
    local tool_name
    tool_name=$(echo "$line" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -n "$tool_name" ]]; then
        case "$tool_name" in
            Read)
                local file_path
                file_path=$(echo "$line" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4)
                if [[ -n "$file_path" ]]; then
                    echo "Reading ${file_path##*/}"
                else
                    echo "Reading file..."
                fi
                ;;
            Write)
                local file_path
                file_path=$(echo "$line" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4)
                if [[ -n "$file_path" ]]; then
                    echo "Writing ${file_path##*/}"
                else
                    echo "Writing file..."
                fi
                ;;
            Edit)
                local file_path
                file_path=$(echo "$line" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4)
                if [[ -n "$file_path" ]]; then
                    echo "Editing ${file_path##*/}"
                else
                    echo "Editing file..."
                fi
                ;;
            Bash)
                local cmd
                cmd=$(echo "$line" | grep -o '"command":"[^"]*"' | head -1 | cut -d'"' -f4 | head -c 60)
                if [[ -n "$cmd" ]]; then
                    echo "Running: ${cmd}"
                else
                    echo "Running command..."
                fi
                ;;
            Glob)
                local pattern
                pattern=$(echo "$line" | grep -o '"pattern":"[^"]*"' | head -1 | cut -d'"' -f4)
                echo "Finding files: ${pattern:-...}"
                ;;
            Grep)
                local pattern
                pattern=$(echo "$line" | grep -o '"pattern":"[^"]*"' | head -1 | cut -d'"' -f4)
                echo "Searching code: ${pattern:-...}"
                ;;
            *)
                echo "Tool: ${tool_name}"
                ;;
        esac
        return 0
    fi

    # Contenuto testuale (ragionamento)
    if echo "$line" | grep -q '"type":"text"'; then
        local snippet
        snippet=$(echo "$line" | grep -o '"text":"[^"]*"' | head -1 | cut -d'"' -f4 | head -c 80)
        if [[ -n "$snippet" ]] && [[ ${#snippet} -gt 10 ]]; then
            echo "Thinking: ${snippet}..."
            return 0
        fi
    fi

    return 1
}

# Assicurati che il monitor venga fermato se lo script viene interrotto
trap 'stop_activity_monitor; stop_dev_server; exit 1' INT TERM

# ==============================================================================
# Dev server management — avvia/ferma dev server per test visivi
# ==============================================================================

DEV_SERVER_PID=""
DEV_SERVER_LOG="${PROJECT_ROOT}/logs/dev-server.log"
SMOKE_TEST_RESULT=""

start_dev_server() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would start dev server"
        return 0
    fi

    # Check if dev server is configured
    if [[ -z "$CONFIG_DEV_SERVER_CMD" ]]; then
        log_info "Dev server not configured in pipeline.yaml — skipping"
        return 0
    fi

    # Se gia in esecuzione, non riavviare
    if [[ -n "$DEV_SERVER_PID" ]] && kill -0 "$DEV_SERVER_PID" 2>/dev/null; then
        log_info "Dev server already running (PID: ${DEV_SERVER_PID})"
        return 0
    fi

    log_step "🖥  Starting dev server for visual tests"

    # Controlla se la porta e gia occupata da un altro processo
    local port="${CONFIG_DEV_SERVER_PORT:-3000}"
    local port_pid=""
    port_pid=$(lsof -ti:"$port" 2>/dev/null || true)
    if [[ -n "$port_pid" ]]; then
        log_warning "Port ${port} already in use by PID: ${port_pid}"
        log_warning "Killing existing process to avoid conflicts..."
        kill "$port_pid" 2>/dev/null || true
        sleep 2
        # Verifica che sia morto
        if lsof -ti:"$port" &>/dev/null; then
            log_error "Cannot free port ${port}. Close the process manually and retry."
            return 1
        fi
        log_success "Port ${port} freed"
    fi

    > "$DEV_SERVER_LOG"

    # Avvia dev server in background
    local server_dir="${PROJECT_ROOT}/${CONFIG_DEV_SERVER_DIR}"
    if [[ ! -d "$server_dir" ]]; then
        log_error "Dev server directory not found: ${server_dir}"
        return 1
    fi

    cd "$server_dir"
    eval "${CONFIG_DEV_SERVER_CMD}" > "$DEV_SERVER_LOG" 2>&1 &
    DEV_SERVER_PID=$!
    cd "$PROJECT_ROOT"

    # Aspetta che il server sia pronto (max 30s)
    log_info "Waiting for server to be ready..."
    local waited=0
    local max_wait=30
    while [[ $waited -lt $max_wait ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}" 2>/dev/null | grep -qE '200|302'; then
            log_success "Dev server ready on http://localhost:${port} (${waited}s)"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))

        # Controlla se il processo e morto
        if ! kill -0 "$DEV_SERVER_PID" 2>/dev/null; then
            log_error "Dev server crashed. Log:"
            tail -20 "$DEV_SERVER_LOG"
            DEV_SERVER_PID=""
            return 1
        fi
    done

    log_warning "Dev server not responding after ${max_wait}s — proceeding anyway"
    return 0
}

stop_dev_server() {
    if [[ -n "$DEV_SERVER_PID" ]] && kill -0 "$DEV_SERVER_PID" 2>/dev/null; then
        # Kill entire process group
        kill -- -"$DEV_SERVER_PID" 2>/dev/null || kill "$DEV_SERVER_PID" 2>/dev/null || true
        sleep 1
        # Force kill if still alive
        kill -9 -- -"$DEV_SERVER_PID" 2>/dev/null || kill -9 "$DEV_SERVER_PID" 2>/dev/null || true
        wait "$DEV_SERVER_PID" 2>/dev/null || true
        log_info "Dev server stopped (PID: ${DEV_SERVER_PID})"
    fi
    DEV_SERVER_PID=""

    # Also kill anything left on port
    local port="${CONFIG_DEV_SERVER_PORT:-3000}"
    local leftover
    leftover=$(lsof -ti:"$port" 2>/dev/null || true)
    if [[ -n "$leftover" ]]; then
        log_warning "Processes remaining on port ${port}: ${leftover} — killing them"
        echo "$leftover" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
}

# ==============================================================================
# Smoke test — cattura errori dalla console del dev server
# ==============================================================================

run_smoke_test() {
    log_step "🔍 Smoke test — checking console errors"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run smoke test"
        SMOKE_TEST_RESULT="DRY-RUN: no test executed"
        return 0
    fi

    local errors_file="${PROJECT_ROOT}/logs/smoke-test-${FEATURE}.log"
    > "$errors_file"

    # 1. Controlla errori nel log del dev server
    local server_errors=""
    if [[ -f "$DEV_SERVER_LOG" ]]; then
        server_errors=$(grep -iE "${CONFIG_ERROR_PATTERNS}" "$DEV_SERVER_LOG" 2>/dev/null | grep -viE 'node_modules' | tail -20 || true)
    fi

    # 2. Get pages to check from pipeline.yaml
    local config_path="${CONFIG_FILE:-${PROJECT_ROOT}/pipeline.yaml}"
    local pages_to_check=()

    # Parse smoke_test.pages from YAML
    if grep -q '^smoke_test:' "$config_path"; then
        # Extract pages list (simple parser)
        local in_pages=false
        while IFS= read -r line; do
            if echo "$line" | grep -q 'pages:'; then
                in_pages=true
                continue
            fi
            if [[ "$in_pages" == "true" ]]; then
                # Check if line is a list item (starts with "    - ")
                if echo "$line" | grep -qE '^    - '; then
                    local page
                    page=$(echo "$line" | sed 's/.*- *//' | tr -d '"' | tr -d "'")
                    pages_to_check+=("$page")
                else
                    # End of pages list
                    break
                fi
            fi
        done < "$config_path"
    fi

    # Default to "/" if no pages configured
    if [[ ${#pages_to_check[@]} -eq 0 ]]; then
        pages_to_check=("/")
    fi

    local page_results=""
    local page_errors=""
    local has_errors=false
    local port="${CONFIG_DEV_SERVER_PORT:-3000}"

    for page in "${pages_to_check[@]}"; do
        # Scarica body + status code insieme
        local body_file
        body_file=$(mktemp)
        local status
        status=$(curl -sL -o "$body_file" -w "%{http_code}" "http://localhost:${port}${page}" 2>/dev/null)

        local line_result=""
        local body_issues=""

        # Check HTTP status
        if [[ "$status" =~ ^5 ]]; then
            line_result="  ✗ ${page} → HTTP ${status} (SERVER ERROR)"
            has_errors=true
        elif [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
            line_result="  ✓ ${page} → HTTP ${status}"
        else
            line_result="  ? ${page} → HTTP ${status}"
        fi

        # Check body per errori runtime (anche se HTTP 200)
        if [[ -f "$body_file" ]] && [[ -s "$body_file" ]]; then
            # Cerca pattern di errore nel body HTML
            local body_error=""
            body_error=$(grep -ioE 'an error has occurred|is not defined|Internal Server Error|Cannot read properties|TypeError|ReferenceError|SyntaxError' "$body_file" 2>/dev/null | head -3 || true)

            if [[ -n "$body_error" ]]; then
                line_result="  ✗ ${page} → HTTP ${status} but RUNTIME ERROR in body"
                body_issues=$(echo "$body_error" | sed 's/^/      /')
                has_errors=true
            fi
        fi

        page_results+="${line_result}\n"
        if [[ -n "$body_issues" ]]; then
            page_results+="${body_issues}\n"
        fi

        rm -f "$body_file"
    done

    # Componi il risultato
    {
        echo "=== SMOKE TEST: ${FEATURE} ==="
        echo ""
        echo "--- Pages ---"
        echo -e "$page_results"
        if [[ -n "$server_errors" ]]; then
            echo "--- Console errors from dev server ---"
            echo "$server_errors"
        else
            echo "--- Console: no errors detected ---"
        fi
        if [[ "$has_errors" == "true" ]]; then
            echo ""
            echo "⚠️  SMOKE TEST FAILED — errors detected in pages"
        fi
        echo ""
        echo "=== END SMOKE TEST ==="
    } > "$errors_file"

    SMOKE_TEST_RESULT=$(cat "$errors_file")

    # Mostra risultato
    if [[ -n "$server_errors" ]]; then
        local error_count
        error_count=$(echo "$server_errors" | wc -l | tr -d ' ')
        log_warning "Found ${error_count} errors/warnings in console"
        echo -e "${YELLOW}${server_errors}${NC}" | head -5
    else
        log_success "No errors in dev server console"
    fi

    echo -e "${CYAN}Pages:${NC}"
    echo -e "$page_results"

    if [[ "$has_errors" == "true" ]]; then
        log_error "SMOKE TEST FAILED — runtime errors detected"
        log_info "Review agents will receive these errors in their prompts"
    fi
}

# ==============================================================================
# Playwright health check — verifica che Playwright sia disponibile
# ==============================================================================

PLAYWRIGHT_AVAILABLE="false"

check_playwright() {
    log_info "Checking Playwright availability..."

    # 1. Controlla che .mcp.json abbia la configurazione playwright
    local mcp_config="${PROJECT_ROOT}/.mcp.json"
    if [[ ! -f "$mcp_config" ]]; then
        log_warning "Playwright: .mcp.json not found — visual tests not available"
        return 1
    fi

    if ! grep -q '"playwright"' "$mcp_config"; then
        log_warning "Playwright: no configuration in .mcp.json — visual tests not available"
        log_info "Add to .mcp.json: \"playwright\": { \"command\": \"npx\", \"args\": [\"@anthropic/mcp-playwright@latest\"] }"
        return 1
    fi

    # 2. Controlla che i browser binaries siano installati
    local browser_found=false
    local browser_paths=(
        "$HOME/Library/Caches/ms-playwright"      # macOS
        "$HOME/.cache/ms-playwright"                # Linux
        "$HOME/.cache/ms-playwright-chromium"       # Linux alt
    )

    for bp in "${browser_paths[@]}"; do
        if [[ -d "$bp" ]] && [[ -n "$(ls -A "$bp" 2>/dev/null)" ]]; then
            browser_found=true
            log_success "Playwright: browsers found in ${bp}"
            break
        fi
    done

    if [[ "$browser_found" == "false" ]]; then
        log_warning "Playwright: browsers not installed — visual tests not available"
        log_info "Install with: npx playwright install chromium"
        return 1
    fi

    # 3. Controlla che npx sia disponibile (necessario per avviare il MCP server)
    if ! command -v npx &> /dev/null; then
        log_warning "Playwright: npx not found — cannot start MCP server"
        return 1
    fi

    PLAYWRIGHT_AVAILABLE="true"
    log_success "Playwright: configured and ready for visual tests"
    return 0
}

# ==============================================================================
# Esegui Claude Code in modalita non-interattiva
# ==============================================================================

run_claude() {
    local prompt="$1"
    local step_name="$2"
    local log_file="${PROJECT_ROOT}/logs/pipeline-${FEATURE}-${step_name}.log"

    mkdir -p "${PROJECT_ROOT}/logs"

    log_info "Starting Claude Code for step: ${step_name}..."
    log_info "Log: ${log_file}"

    if [[ "$DRY_RUN" == "true" ]]; then
        local dry_model="${MODEL:-$(get_step_field "$step_name" "model" "")}"
        dry_model="${dry_model:-default}"
        echo -e "${YELLOW}[DRY-RUN] Step: ${step_name} | Model: ${dry_model}${NC}"
        echo -e "${YELLOW}Prompt that would be executed:${NC}"
        echo "---"
        echo "$prompt"
        echo "---"
        return 0
    fi

    # Determina modello: --model globale > config per-step > default Claude Code
    local step_model=""
    if [[ -n "$MODEL" ]]; then
        step_model="$MODEL"
    else
        step_model="$(get_step_field "$step_name" "model" "")"
    fi

    local model_flag=""
    if [[ -n "$step_model" ]]; then
        model_flag="--model $step_model"
        log_info "Model: ${step_model}"
    fi

    # Salva il prompt in un file temporaneo
    local prompt_file
    prompt_file=$(mktemp)
    echo "$prompt" > "$prompt_file"

    # Svuota il log precedente
    > "$log_file"

    # Track start time for meta-logging
    local started_at
    started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Avvia monitor attivita
    start_activity_monitor "$log_file"

    # Esegui Claude Code con stream-json per output in tempo reale
    # Unset CLAUDECODE to allow nested sessions (pipeline launched from Claude Code)
    # shellcheck disable=SC2086
    CLAUDECODE= claude -p \
        --verbose \
        --output-format stream-json \
        --allowedTools "Read,Write,Edit,Bash,Glob,Grep,NotebookEdit,WebFetch,mcp__*" \
        $model_flag \
        < "$prompt_file" 2>"${log_file}.stderr" | while IFS= read -r line; do
        # Salva tutto nel log
        echo "$line" >> "$log_file"

        # Parsa e mostra attivita interessanti
        local activity
        activity=$(parse_stream_event "$line")
        if [[ -n "$activity" ]]; then
            echo "$activity" >> "$LAST_LINES_FILE"
        fi
    done

    local exit_code=${PIPESTATUS[0]}

    # Track end time for meta-logging
    local ended_at
    ended_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    stop_activity_monitor
    rm -f "$prompt_file"

    # Map Claude CLI exit codes to pipeline exit codes
    local mapped_exit_code="$exit_code"
    if [[ $exit_code -ne 0 ]]; then
        # Check stderr for specific error patterns
        if [[ -f "${log_file}.stderr" ]]; then
            local stderr_content
            stderr_content=$(cat "${log_file}.stderr")

            # Check for token/rate limit errors
            if echo "$stderr_content" | grep -qiE 'rate_limit|over_capacity|token|context_length'; then
                mapped_exit_code="$EXIT_TOKEN_EXHAUSTED"
                log_error "Token exhausted or rate limit hit"
            # Check for MCP tool errors
            elif echo "$stderr_content" | grep -qiE 'mcp|tool.*error|tool.*failed'; then
                mapped_exit_code="$EXIT_TOOL_FAILURE"
                log_error "MCP tool failure"
            else
                mapped_exit_code="$EXIT_BUSINESS_ERROR"
            fi
        fi
    fi

    # Write meta log
    write_meta_log "$FEATURE" "$step_name" "${step_model:-default}" "$started_at" "$ended_at" "$mapped_exit_code" "$log_file" "${RETRY_ATTEMPT:-0}"

    if [[ $mapped_exit_code -eq 0 ]]; then
        log_success "Step ${step_name} completed"
        return 0
    else
        log_error "Step ${step_name} failed (exit code: ${exit_code}, mapped: ${mapped_exit_code})"
        log_info "See log: ${log_file}"

        # Log decision
        local error_type="unknown"
        case "$mapped_exit_code" in
            "$EXIT_TOKEN_EXHAUSTED") error_type="token_exhausted" ;;
            "$EXIT_TOOL_FAILURE") error_type="tool_failure" ;;
            "$EXIT_BUSINESS_ERROR") error_type="business_error" ;;
        esac
        log_decision "$FEATURE" "$step_name" "failure" "$error_type" "${RETRY_ATTEMPT:-0}"

        return "$mapped_exit_code"
    fi
}

# ==============================================================================
# Git commit e push dei file prodotti dallo step
# ==============================================================================

git_sync() {
    local msg="$1"
    cd "$PROJECT_ROOT"

    # Controlla se ci sono cambiamenti
    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        log_info "No changes to commit"
        return 0
    fi

    git add -A
    git commit -m "$msg" || true
    log_success "Commit: $msg"
}

# ==============================================================================
# Prompt generators — leggono da PROMPTS.md (single source of truth)
# ==============================================================================
# Ogni funzione genera una meta-istruzione che dice a Claude di leggere il
# prompt completo da PROMPTS.md e di eseguirlo per la feature specificata.
# Questo evita duplicazione e garantisce che pipeline e prompt siano sempre in sync.

generate_step_prompt() {
    local step_name="$1"

    # Get prompt section from config
    local prompt_section
    prompt_section=$(get_step_field "$step_name" "prompt_section" "")

    if [[ -z "$prompt_section" ]]; then
        log_error "No prompt_section configured for step: ${step_name}"
        return 1
    fi

    # Build meta-prompt
    cat <<PROMPT
Read the file ${CONFIG_PROMPTS_FILE} in the repo ${PROJECT_ROOT}.
Find the section "${prompt_section}" and read the complete prompt contained in the code block.
Execute it exactly for the feature: ${FEATURE}
Replace every occurrence of [FEATURE_NAME] with: ${FEATURE}
PROMPT

    # Add context-specific additions (dev server status, smoke test, etc.)
    case "$step_name" in
        dev)
            cat <<EXTRA

IMPORTANT — MANDATORY FINAL VERIFICATION:
Before declaring work finished, you MUST:
1. Start the dev server (${CONFIG_DEV_SERVER_CMD}) in directory ${CONFIG_DEV_SERVER_DIR}
2. Wait for it to be ready on http://localhost:${CONFIG_DEV_SERVER_PORT}
3. Curl the feature pages and verify NO 5xx errors
4. Check that response body does NOT contain "An error has occurred", "is not defined", "TypeError", "ReferenceError"
5. Check dev server output for runtime errors
6. If you find errors, FIX THEM before declaring finished
7. Stop the dev server when done (kill the process)
EXTRA
            ;;
        dr-impl|qa)
            cat <<EXTRA

IMPORTANT: Dev server is running on http://localhost:${CONFIG_DEV_SERVER_PORT}.
$(if [[ "$PLAYWRIGHT_AVAILABLE" == "true" ]]; then
    echo "Playwright MCP is AVAILABLE. Use mcp__playwright__* tools to navigate pages, capture screenshots, and visually verify implementation."
else
    echo "Playwright is NOT available. Analyze source code and produce visual checklist based on component structure and styles."
fi)

Smoke test results:
${SMOKE_TEST_RESULT:-No smoke test executed}
EXTRA
            ;;
    esac
}

# ==============================================================================
# Step runner — generic step execution with retry logic
# ==============================================================================

run_step() {
    local step_name="$1"
    local display_name="$2"
    local color="${3:-$CYAN}"

    log_step "${color}${display_name}"
    log_agent "$color" "$display_name" "Executing step..."

    # Run pre-hook
    run_hooks "$step_name" "pre" || log_warning "Pre-hook failed, continuing anyway"

    # Generate and run prompt
    local prompt
    prompt=$(generate_step_prompt "$step_name")

    if [[ -z "$prompt" ]]; then
        log_error "Failed to generate prompt for step: ${step_name}"
        return "$EXIT_FATAL"
    fi

    run_claude "$prompt" "$step_name"
    local exit_code=$?

    # Run post-hook
    if [[ $exit_code -eq 0 ]]; then
        run_hooks "$step_name" "post" || log_warning "Post-hook failed, continuing anyway"
    fi

    return $exit_code
}

# ==============================================================================
# Pipeline orchestrator — configuration-driven main loop
# ==============================================================================

run_pipeline() {
    local start_time
    start_time=$(date +%s)

    echo -e "\n${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  AI Pipeline — Feature: ${CYAN}${FEATURE}${NC}${BOLD}                        ║${NC}"
    echo -e "${BOLD}║  Configuration-driven multi-step workflow              ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}\n"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN MODE — no commands will be executed"
    fi

    # Load configuration
    load_config

    # Controlla Playwright (non bloccante — la pipeline funziona anche senza)
    if [[ "$DRY_RUN" != "true" ]]; then
        check_playwright || true
        echo ""
    fi

    # Get all steps from configuration
    local all_steps
    all_steps=$(get_all_steps)

    if [[ -z "$all_steps" ]]; then
        log_error "No steps defined in pipeline.yaml"
        return "$EXIT_FATAL"
    fi

    log_info "Pipeline steps: ${all_steps}"
    echo ""

    # Convert to array (Bash 3.2 compatible)
    local steps=()
    while IFS= read -r step; do
        steps+=("$step")
    done <<< "$all_steps"

    # Initialize pipeline state
    write_pipeline_state "$FEATURE" "starting" "running" "" "null" ""

    # Se --from specificato, salta gli step precedenti
    local skip=true
    if [[ -z "$FROM_STEP" ]]; then
        skip=false
    fi

    local steps_completed=""
    local step_retries=0

    for step_name in "${steps[@]}"; do
        # Skip management
        if [[ "$skip" == "true" ]]; then
            if [[ "$step_name" == "$FROM_STEP" ]]; then
                skip=false
            else
                log_info "Skip step: ${step_name} (--from ${FROM_STEP})"
                continue
            fi
        fi

        # Update pipeline state
        write_pipeline_state "$FEATURE" "$step_name" "running" "$steps_completed" "null" ""

        # Get step configuration
        local retry_on_fail
        retry_on_fail=$(get_step_field "$step_name" "retry_on_fail" "false")

        local output_file
        output_file=$(get_step_field "$step_name" "output_file" "")

        # Execute step with retry logic if configured
        local step_exit_code=0
        RETRY_ATTEMPT=0

        while true; do
            # Run the step
            run_step "$step_name" "$step_name" "$CYAN"
            step_exit_code=$?

            if [[ $step_exit_code -eq 0 ]]; then
                # Success — check output file if configured
                if [[ -n "$output_file" ]]; then
                    local full_output_path="${PROJECT_ROOT}/${output_file}"
                    if check_file "$full_output_path"; then
                        log_success "Output file produced: ${output_file}"

                        # Check result pattern if this is a review step
                        local result
                        result=$(check_result "$full_output_path")

                        if [[ "$result" == "PASS" ]]; then
                            log_success "Result: PASS"
                            break
                        elif [[ "$result" == "FAIL" ]] && [[ "$retry_on_fail" == "true" ]]; then
                            log_warning "Result: FAIL — retry configured"

                            # Check retry limit
                            step_retries=$((step_retries + 1))
                            if [[ $step_retries -gt $MAX_RETRIES ]]; then
                                log_error "Max retries (${MAX_RETRIES}) exceeded for step: ${step_name}"
                                log_decision "$FEATURE" "$step_name" "max_retries_exceeded" "FAIL" "$step_retries"
                                write_pipeline_state "$FEATURE" "$step_name" "failed" "$steps_completed" "$EXIT_BUSINESS_ERROR" "Max retries exceeded"
                                return "$EXIT_BUSINESS_ERROR"
                            fi

                            log_decision "$FEATURE" "$step_name" "retry" "FAIL" "$step_retries"
                            log_warning "Retry ${step_retries}/${MAX_RETRIES} for step: ${step_name}"
                            RETRY_ATTEMPT=$step_retries
                            continue
                        else
                            # UNKNOWN or non-retry FAIL — proceed
                            if [[ "$result" == "UNKNOWN" ]]; then
                                log_warning "Result: UNKNOWN — proceeding anyway"
                            fi
                            break
                        fi
                    else
                        log_warning "Output file not found: ${output_file}"
                        break
                    fi
                else
                    # No output file to check — success
                    break
                fi
            else
                # Step failed — check if should retry
                log_error "Step failed with exit code: ${step_exit_code}"

                # Don't retry on fatal errors
                if [[ $step_exit_code -eq $EXIT_FATAL ]]; then
                    write_pipeline_state "$FEATURE" "$step_name" "fatal" "$steps_completed" "$step_exit_code" "Fatal error in step"
                    return "$EXIT_FATAL"
                fi

                # Check retry limit
                step_retries=$((step_retries + 1))
                if [[ $step_retries -gt $MAX_RETRIES ]]; then
                    log_error "Max retries (${MAX_RETRIES}) exceeded for step: ${step_name}"

                    local status="failed"
                    if [[ $step_exit_code -eq $EXIT_TOKEN_EXHAUSTED ]]; then
                        status="token_exhausted"
                    elif [[ $step_exit_code -eq $EXIT_TOOL_FAILURE ]]; then
                        status="tool_failure"
                    fi

                    write_pipeline_state "$FEATURE" "$step_name" "$status" "$steps_completed" "$step_exit_code" "Max retries exceeded"
                    return "$step_exit_code"
                fi

                log_decision "$FEATURE" "$step_name" "retry" "error" "$step_retries"
                log_warning "Retry ${step_retries}/${MAX_RETRIES} for step: ${step_name}"
                RETRY_ATTEMPT=$step_retries
                continue
            fi
        done

        # Step completed successfully — add to completed list
        if [[ -z "$steps_completed" ]]; then
            steps_completed="$step_name"
        else
            steps_completed="${steps_completed} ${step_name}"
        fi

        # Reset retry counter for next step
        step_retries=0
    done

    # Ferma il dev server se in esecuzione
    stop_dev_server

    # Pipeline completata
    write_pipeline_state "$FEATURE" "completed" "completed" "$steps_completed" "0" ""

    # Sommario finale
    local end_time
    end_time=$(date +%s)
    local duration=$(( end_time - start_time ))
    local minutes=$(( duration / 60 ))
    local seconds=$(( duration % 60 ))

    echo -e "\n${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  ✅ PIPELINE COMPLETED — ${FEATURE}${NC}"
    echo -e "${BOLD}${GREEN}║  Time: ${minutes}m ${seconds}s${NC}"
    echo -e "${BOLD}${GREEN}║                                                          ║${NC}"
    echo -e "${BOLD}${GREEN}║  Output:                                                 ║${NC}"

    # List output files from completed steps
    for step_name in $steps_completed; do
        local output_file
        output_file=$(get_step_field "$step_name" "output_file" "")
        if [[ -n "$output_file" ]]; then
            echo -e "${BOLD}${GREEN}║  - ${step_name}: ${output_file}${NC}"
        fi
    done

    echo -e "${BOLD}${GREEN}║  - Logs: logs/pipeline-${FEATURE}-*.log${NC}"
    echo -e "${BOLD}${GREEN}║  - Meta: logs/meta/${FEATURE}-*.meta.json${NC}"
    echo -e "${BOLD}${GREEN}║  - State: pipeline-state.json${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
}

# ==============================================================================
# Auto-resume: rileva step gia completati e riparte dal primo incompleto
# ==============================================================================

detect_resume_point() {
    local feature="$1"

    echo -e "${CYAN}Checking completed steps for ${feature}:${NC}"

    # Get all steps from config
    local all_steps
    all_steps=$(get_all_steps)

    # Check each step's output file
    while IFS= read -r step_name; do
        local output_file
        output_file=$(get_step_field "$step_name" "output_file" "")

        if [[ -z "$output_file" ]]; then
            # No output file — assume step needs to run
            echo -e "  ${YELLOW}?${NC} ${step_name}: no output file configured"
            echo "$step_name"
            return
        fi

        local full_output_path="${PROJECT_ROOT}/${output_file}"

        if ! check_file "$full_output_path"; then
            echo -e "  ${RED}✗${NC} ${step_name}: output missing → resume from ${step_name}"
            echo "$step_name"
            return
        fi

        # Check result if this is a review step
        local result
        result=$(check_result "$full_output_path")

        if [[ "$result" == "PASS" ]]; then
            echo -e "  ${GREEN}✓${NC} ${step_name}: PASS"
        elif [[ "$result" == "FAIL" ]]; then
            echo -e "  ${RED}✗${NC} ${step_name}: FAIL → resume from ${step_name}"
            echo "$step_name"
            return
        else
            echo -e "  ${GREEN}✓${NC} ${step_name}: completed (result: ${result})"
        fi
    done <<< "$all_steps"

    # All steps completed
    echo "done"
}

# ==============================================================================
# CLI parsing
# ==============================================================================

usage() {
    cat <<EOF
Usage: ./scripts/pipeline.sh <feature-name> [options]

Options:
  --dry-run        Show prompts without executing
  --from <step>    Resume from a specific step
  --resume         Auto-detect completed steps and resume from first incomplete
  --model <model>  Force a model for ALL steps (opus, sonnet, haiku)
                   Default: configured per-step in pipeline.yaml
  --state          Dump pipeline-state.json and exit
  --config <path>  Use alternate configuration file (default: pipeline.yaml)
  --help           Show this help

Examples:
  ./scripts/pipeline.sh contacts                     # Complete cycle
  ./scripts/pipeline.sh contacts --resume            # Auto-detect and resume
  ./scripts/pipeline.sh contacts --from dev          # Resume from dev step
  ./scripts/pipeline.sh contacts --dry-run           # Preview only
  ./scripts/pipeline.sh contacts --model opus        # Force opus for all steps
  ./scripts/pipeline.sh contacts --state             # Show current state
  ./scripts/pipeline.sh contacts --config custom.yaml # Use custom config
EOF
}

# Defaults
FEATURE=""
DRY_RUN="false"
FROM_STEP=""
AUTO_RESUME="false"
MODEL="$DEFAULT_MODEL"
SHOW_STATE="false"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --from)
            FROM_STEP="$2"
            shift 2
            ;;
        --resume)
            AUTO_RESUME="true"
            shift
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --state)
            SHOW_STATE="true"
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$FEATURE" ]]; then
                FEATURE="$1"
            else
                log_error "Feature already specified: ${FEATURE}. Extra argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validazione
if [[ -z "$FEATURE" ]]; then
    log_error "Feature name required"
    echo ""
    usage
    exit 1
fi

# --state flag: dump state and exit
if [[ "$SHOW_STATE" == "true" ]]; then
    local state_file="${PROJECT_ROOT}/pipeline-state.json"
    if [[ ! -f "$state_file" ]]; then
        log_error "No pipeline state file found: ${state_file}"
        exit 1
    fi
    cat "$state_file"
    exit 0
fi

# Verifica che Claude Code sia installato
if ! command -v claude &> /dev/null; then
    log_error "Claude Code CLI not found. Install it first: https://docs.anthropic.com/en/docs/claude-code"
    exit "$EXIT_FATAL"
fi

# Verifica che siamo nel progetto giusto
local config_path="${CONFIG_FILE:-${PROJECT_ROOT}/pipeline.yaml}"
if [[ ! -f "$config_path" ]]; then
    log_error "Not an ai-pipeline project. pipeline.yaml not found at: ${config_path}"
    exit "$EXIT_FATAL"
fi

# Crea directory necessarie
mkdir -p "${PROJECT_ROOT}/logs"
mkdir -p "${PROJECT_ROOT}/logs/meta"

# Auto-resume: rileva step completati
if [[ "$AUTO_RESUME" == "true" ]] && [[ -z "$FROM_STEP" ]]; then
    resume_point=$(detect_resume_point "$FEATURE")
    if [[ "$resume_point" == "done" ]]; then
        log_success "Feature ${FEATURE} already completed (all steps PASS)."
        log_info "Use --from <step> to force re-execution of a specific step."
        exit 0
    fi
    FROM_STEP="$resume_point"
    echo ""
fi

# Vai!
cd "$PROJECT_ROOT"
run_pipeline
