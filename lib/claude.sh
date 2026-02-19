#!/usr/bin/env bash
# lib/claude.sh — Claude CLI execution with streaming, provider routing, retry

# Token exhaustion retry defaults (overridden from pipeline.yaml)
CLAUDE_TOKEN_MAX_RETRIES="${CLAUDE_TOKEN_MAX_RETRIES:-5}"
CLAUDE_TOKEN_BASE_DELAY="${CLAUDE_TOKEN_BASE_DELAY:-60}"

# ---------------------------------------------------------------------------
# claude_setup_provider <provider_name> <model>
# Configura le env vars per il provider specificato.
# ---------------------------------------------------------------------------
claude_setup_provider() {
    local provider="$1"
    local model="$2"

    local base_url
    base_url=$(config_provider_get "$provider" "base_url")
    local api_key_env
    api_key_env=$(config_provider_get "$provider" "api_key_env")

    if [[ -n "$base_url" ]]; then
        export ANTHROPIC_BASE_URL="$base_url"
    else
        unset ANTHROPIC_BASE_URL
    fi

    if [[ -n "$api_key_env" ]]; then
        local api_key="${!api_key_env}"
        if [[ -z "$api_key" ]]; then
            display_warn "Provider ${provider}: env var ${api_key_env} not set"
        else
            export ANTHROPIC_AUTH_TOKEN="$api_key"
            export ANTHROPIC_API_KEY="$api_key"
        fi
    fi

    # Per provider non-anthropic: punta tutti gli alias al modello specificato
    if [[ "$provider" != "anthropic" ]] && [[ -n "$model" ]]; then
        export ANTHROPIC_DEFAULT_OPUS_MODEL="$model"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="$model"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="$model"
        export CLAUDE_CODE_SUBAGENT_MODEL="$model"
    else
        unset ANTHROPIC_DEFAULT_OPUS_MODEL 2>/dev/null || true
        unset ANTHROPIC_DEFAULT_SONNET_MODEL 2>/dev/null || true
        unset ANTHROPIC_DEFAULT_HAIKU_MODEL 2>/dev/null || true
        unset CLAUDE_CODE_SUBAGENT_MODEL 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# claude_run <prompt_file> <step_name> <model> <allowed_tools> <mcp_servers>
# Esegue claude CLI con stream-json, popola semi-log, gestisce token exhaustion.
# Exit code: 0=success, 1=error, 75=token exhausted
# ---------------------------------------------------------------------------
claude_run() {
    local prompt_file="$1"
    local step_name="$2"
    local model="$3"
    local allowed_tools="${4:-Read,Write,Edit,Bash,Glob,Grep}"
    local mcp_servers="${5:-}"

    local log_dir="${PIPELINE_DIR}/logs"
    local log_file="${log_dir}/${PIPELINE_FEATURE}-${step_name}.log"
    mkdir -p "$log_dir"

    # Costruisci --mcp-config se ci sono server MCP per questo step
    local mcp_flag=""
    local tmp_mcp=""
    if [[ -n "$mcp_servers" ]] && [[ -f "${PIPELINE_DIR}/.mcp.json" ]]; then
        local filtered_mcp
        filtered_mcp=$(_claude_filter_mcp "$mcp_servers")
        if [[ -n "$filtered_mcp" ]]; then
            tmp_mcp=$(mktemp /tmp/pipeline-mcp.XXXXXX.json)
            echo "$filtered_mcp" > "$tmp_mcp"
            mcp_flag="--mcp-config ${tmp_mcp}"
        fi
    fi

    local model_flag=""
    if [[ -n "$model" ]]; then
        model_flag="--model ${model}"
    fi

    local attempt=0
    local claude_exit=0

    while true; do
        attempt=$(( attempt + 1 ))
        > "$log_file"
        claude_exit=0

        # CLAUDECODE= evita conflitti se lanciato da dentro Claude Code interattivo
        # shellcheck disable=SC2086
        CLAUDECODE= claude -p \
            --verbose \
            --output-format stream-json \
            --allowedTools "$allowed_tools" \
            $model_flag \
            $mcp_flag \
            < "$prompt_file" \
            2>"${log_file}.stderr" \
        | while IFS= read -r json_line; do
            echo "$json_line" >> "$log_file"
            local action
            action=$(_claude_parse_tool_use "$json_line")
            if [[ -n "$action" ]]; then
                local tool_type tool_arg
                tool_type="${action%%  *}"
                tool_arg="${action#*  }"
                display_box_add_action "$tool_type" "$tool_arg"
            fi
        done || claude_exit=$?

        # Cleanup mcp temporaneo
        [[ -n "$tmp_mcp" ]] && rm -f "$tmp_mcp"

        # Controlla token exhaustion
        if _claude_is_token_exhausted "$claude_exit" "${log_file}.stderr"; then
            if [[ $attempt -ge $CLAUDE_TOKEN_MAX_RETRIES ]]; then
                display_error "Token esaurito dopo ${attempt} tentativi — step: ${step_name}"
                return 75
            fi
            local delay=$(( CLAUDE_TOKEN_BASE_DELAY * ( 2 ** (attempt - 1) ) ))
            display_warn "Rate limit — attendo ${delay}s (tentativo ${attempt}/${CLAUDE_TOKEN_MAX_RETRIES})"
            _claude_countdown "$delay"
            continue
        fi

        break
    done

    return $claude_exit
}

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

_claude_is_token_exhausted() {
    local exit_code="$1"
    local stderr_file="$2"

    [[ $exit_code -eq 75 ]] && return 0

    if [[ -f "$stderr_file" ]]; then
        grep -qiE 'rate.?limit|over.?capacity|token|context.?length|overloaded' \
            "$stderr_file" 2>/dev/null && return 0
    fi

    return 1
}

_claude_countdown() {
    local seconds="$1"
    local remaining=$seconds
    while [[ $remaining -gt 0 ]]; do
        printf "\r  ${YELLOW}⏳ Attesa: %ds rimanenti...${NC}   " "$remaining"
        sleep 1
        remaining=$(( remaining - 1 ))
    done
    printf "\r\033[K"
}

_claude_parse_tool_use() {
    local line="$1"
    python3 -c "
import sys, json, os

try:
    d = json.loads('''${line//\'/\'\\\'\'}''')
except:
    try:
        import sys
        d = json.loads(sys.stdin.read())
    except:
        sys.exit(0)

tool_name = ''
inp = {}

if d.get('type') == 'tool_use' and 'name' in d:
    tool_name = d['name']
    inp = d.get('input', {})
elif 'content_block' in d and isinstance(d.get('content_block'), dict):
    cb = d['content_block']
    if cb.get('type') == 'tool_use' and 'name' in cb:
        tool_name = cb['name']
        inp = cb.get('input', {})

if not tool_name:
    sys.exit(0)

arg = ''
for key in ['file_path', 'command', 'pattern', 'query', 'url']:
    if key in inp:
        val = str(inp[key])
        if key == 'file_path':
            val = os.path.basename(val)
        else:
            val = val[:60]
        arg = val[:60]
        break

print(f'{tool_name}  {arg}')
" 2>/dev/null <<< "$line" || true
}

_claude_filter_mcp() {
    local servers_space="$1"
    local mcp_file="${PIPELINE_DIR}/.mcp.json"

    [[ ! -f "$mcp_file" ]] && echo "" && return

    python3 - "$mcp_file" "$servers_space" <<'PYEOF'
import sys, json

with open(sys.argv[1]) as f:
    mcp_config = json.load(f)

requested = sys.argv[2].split()
servers = mcp_config.get('mcpServers', {})
filtered = {k: v for k, v in servers.items() if k in requested}

if filtered:
    print(json.dumps({'mcpServers': filtered}, indent=2))
PYEOF
}
