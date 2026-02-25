#!/usr/bin/env bash
# pipeline.sh — AI Pipeline Orchestrator
#
# Usage:
#   ./ai-pipeline/pipeline.sh <feature> [options]
#   ./ai-pipeline/pipeline.sh <feat1> <feat2> ... [options]   (batch mode)
#
# Options:
#   --from <step>          Riparte da uno step specifico
#   --resume               Riprende dall'ultimo step incompleto
#   --only <step>          Esegue solo quello step
#   --dry-run              Mostra i prompt senza eseguire
#   --model <model>        Override modello per tutti gli step
#   --app <app>            Target app/layer (es. my-app, my-lib)
#   --description "..."    Brief inline (crea briefs/<feature>.md)
#   --batch-file <file>    Carica feature da file (una per riga)
#   --continue-on-error    In batch: continua anche se una feature fallisce
#   --state                Mostra stato corrente
#   --help                 Aiuto
#
# Requires: bash 3.2+, python3, claude CLI

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths — tutto relativo a dove si trova questo script
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR"
PIPELINE_CONFIG_FILE="${PIPELINE_DIR}/pipeline.yaml"
PIPELINE_STATE_FILE="${PIPELINE_DIR}/state.json"

PIPELINE_BATCH_STATE_FILE="${PIPELINE_DIR}/batch-state.json"

export PIPELINE_DIR PIPELINE_CONFIG_FILE PIPELINE_STATE_FILE PIPELINE_BATCH_STATE_FILE

# ---------------------------------------------------------------------------
# Load libs
# ---------------------------------------------------------------------------
source "${PIPELINE_DIR}/lib/config.sh"
source "${PIPELINE_DIR}/lib/display.sh"
source "${PIPELINE_DIR}/lib/state.sh"
source "${PIPELINE_DIR}/lib/verdict.sh"
source "${PIPELINE_DIR}/lib/claude.sh"
source "${PIPELINE_DIR}/lib/prompt.sh"
source "${PIPELINE_DIR}/lib/playwright.sh"
source "${PIPELINE_DIR}/lib/verify.sh"
source "${PIPELINE_DIR}/lib/context.sh"

# ---------------------------------------------------------------------------
# Trap
# ---------------------------------------------------------------------------
trap 'display_trap_cleanup; rm -f /tmp/pipeline-prompt-* /tmp/pipeline-reject-*; exit 1' INT TERM

# ---------------------------------------------------------------------------
# CLI parsing vars
# ---------------------------------------------------------------------------
export PIPELINE_FEATURE=""
export APP=""
PIPELINE_FEATURES=()
PIPELINE_FROM_STEP=""
PIPELINE_ONLY_STEP=""
PIPELINE_DRY_RUN="false"
PIPELINE_RESUME="false"
PIPELINE_MODEL_OVERRIDE=""
PIPELINE_DESCRIPTION=""
PIPELINE_SHOW_STATE="false"
PIPELINE_CONTINUE_ON_ERROR="false"
PIPELINE_BATCH_FILE=""

# ---------------------------------------------------------------------------
# _usage
# ---------------------------------------------------------------------------
_usage() {
    cat <<EOF

Usage: $(basename "$0") <feature> [options]
       $(basename "$0") <feature1> <feature2> ... [options]   (batch mode)

Options:
  --from <step>          Riparte da uno step specifico
  --resume               Riprende dall'ultimo step incompleto
  --only <step>          Esegue solo quello step
  --dry-run              Mostra i prompt senza eseguire
  --model <model>        Override modello per tutti gli step
  --app <app>            Target app/layer
  --description "..."    Brief inline (crea briefs/<feature>.md)
  --batch-file <file>    Carica feature da file (una per riga)
  --continue-on-error    In batch: continua anche se una feature fallisce
  --state                Mostra stato corrente
  --help                 Aiuto

Examples:
  ./pipeline.sh button-outline --description "Aggiungere variante outline"
  ./pipeline.sh button-outline --resume
  ./pipeline.sh button-outline --from dev
  ./pipeline.sh button-outline --only qa
  ./pipeline.sh --state

  # Batch mode (esecuzione sequenziale):
  ./pipeline.sh feat-login feat-signup feat-dashboard
  ./pipeline.sh --batch-file features.txt
  ./pipeline.sh feat-a feat-b --continue-on-error --model claude-sonnet-4-6

EOF
}

# ---------------------------------------------------------------------------
# _pipeline_show_state — mostra stato corrente da state.json e batch-state.json
# ---------------------------------------------------------------------------
_pipeline_show_state() {
    local found=false

    # Mostra batch state se presente
    if [[ -f "$PIPELINE_BATCH_STATE_FILE" ]]; then
        found=true
        _pipeline_show_batch_state
    fi

    # Mostra pipeline state se presente
    if [[ -f "$PIPELINE_STATE_FILE" ]]; then
        found=true

        local feature started
        feature=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('feature','?'))" \
            "$PIPELINE_STATE_FILE" 2>/dev/null || echo "?")
        started=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('started_at','?'))" \
            "$PIPELINE_STATE_FILE" 2>/dev/null || echo "?")

        echo ""
        echo "  Pipeline (ultimo run): ${feature}"
        echo "  Avviata:  ${started}"
        echo ""

        local all_steps
        all_steps=$(config_steps_names)
        while IFS= read -r show_step; do
            local show_status
            show_status=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
s=d.get('steps',{}).get(sys.argv[2],{})
print(s.get('status','pending'))
" "$PIPELINE_STATE_FILE" "$show_step" 2>/dev/null || echo "pending")

            case "$show_status" in
                completed)   display_step_done "$show_step" "completato" "" ;;
                in_progress) printf "  ${CYAN}⠸${NC}  %-14s %s\n" "$show_step" "${CYAN}in corso${NC}" ;;
                failed)      printf "  ${RED}x${NC}  %-14s %s\n" "$show_step" "${RED}fallito${NC}" ;;
                *)           display_step_waiting "$show_step" ;;
            esac
        done <<< "$all_steps"
        echo ""
    fi

    if [[ "$found" == "false" ]]; then
        display_error "Nessuna pipeline in corso (state.json non trovato)"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# _pipeline_show_batch_state — mostra stato batch da batch-state.json
# ---------------------------------------------------------------------------
_pipeline_show_batch_state() {
    [[ ! -f "$PIPELINE_BATCH_STATE_FILE" ]] && return

    python3 - "$PIPELINE_BATCH_STATE_FILE" <<'PYEOF'
import sys, json

with open(sys.argv[1]) as f:
    data = json.load(f)

status = data.get("status", "?")
started = data.get("started_at", "?")
total = data.get("total", 0)
completed = data.get("completed", 0)
failed = data.get("failed", 0)

status_icon = {"running": "⠸", "completed": "v", "failed": "x", "interrupted": "!"}.get(status, "?")

print()
print(f"  Batch: {status_icon} {status}  ({completed}/{total} completate, {failed} fallite)")
print(f"  Avviato: {started}")
print()

for name, info in data.get("features", {}).items():
    s = info.get("status", "pending")
    elapsed = info.get("elapsed", "")
    icon = {"completed": "v", "failed": "x", "in_progress": "*", "skipped": "-", "pending": "o"}.get(s, "?")
    elapsed_str = f"  {elapsed}" if elapsed else ""
    print(f"  {icon}  {name:<30} {s}{elapsed_str}")

print()
PYEOF
}

# ---------------------------------------------------------------------------
# _integration_enabled — true se integration check è abilitato
# ---------------------------------------------------------------------------
_integration_enabled() {
    local val
    val=$(config_get_default "integration.enabled" "false")
    [[ "$val" == "true" ]]
}

# ---------------------------------------------------------------------------
# _integration_run <log_file>
# Esegue i comandi di integration check. Return 0 se tutti passano.
# ---------------------------------------------------------------------------
_integration_run() {
    local log_file="$1"
    local project_dir
    project_dir="$(dirname "$PIPELINE_DIR")"
    > "$log_file"

    local all_passed=true

    # Parsing semplice: legge le righe sotto integration.commands
    local commands
    commands=$(python3 - "$PIPELINE_CONFIG_FILE" <<'PYEOF'
import sys

with open(sys.argv[1]) as f:
    lines = f.readlines()

in_integration = False
in_commands = False

for line in lines:
    stripped = line.strip()
    if stripped == 'integration:':
        in_integration = True
        continue
    if not in_integration:
        continue
    if stripped and not line.startswith(' ') and not line.startswith('\t'):
        break
    if stripped == 'commands:':
        in_commands = True
        continue
    if in_commands:
        if stripped.startswith('- '):
            cmd = stripped[2:].strip().strip('"\'')
            if cmd:
                print(cmd)
        elif stripped and not stripped.startswith('#'):
            break
PYEOF
)

    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        display_info "Integration: ${cmd}"
        local cmd_exit=0
        local cmd_output
        cmd_output=$(cd "$project_dir" && eval "$cmd" 2>&1) || cmd_exit=$?
        if [[ $cmd_exit -ne 0 ]]; then
            all_passed=false
            printf "=== INTEGRATION FAILED: %s (exit %d) ===\n%s\n\n" "$cmd" "$cmd_exit" "$cmd_output" >> "$log_file"
            display_warn "Integration: ${cmd} FAILED"
        fi
    done <<< "$commands"

    [[ "$all_passed" == "true" ]]
}

# ---------------------------------------------------------------------------
# _run_pipeline — orchestration loop
# ---------------------------------------------------------------------------
_run_pipeline() {
    local pipeline_name
    pipeline_name=$(config_get_default "pipeline.name" "pipeline")
    local max_retries
    max_retries=$(config_get_default "defaults.max_retries" "2")
    local all_steps
    all_steps=$(config_steps_names)

    # Costruisci steps string per header
    local steps_str="" first=true
    while IFS= read -r step; do
        local icon
        case "$step" in
            pm)      icon="📋" ;;
            dr-spec) icon="🔍" ;;
            dev)     icon="⚡" ;;
            dr-impl) icon="🎨" ;;
            qa)      icon="✅" ;;
            dev-fix) icon="🔧" ;;
            *)       icon="▸"  ;;
        esac
        if [[ "$first" == "true" ]]; then
            steps_str="${icon} ${step}"
            first=false
        else
            steps_str="${steps_str} → ${icon} ${step}"
        fi
    done <<< "$all_steps"

    display_header "$pipeline_name" "$PIPELINE_FEATURE" "$steps_str"

    state_init "$PIPELINE_FEATURE"
    verdict_ensure_dir
    context_init "$PIPELINE_FEATURE"

    local pipeline_start
    pipeline_start=$(date +%s)
    local skip="false"
    [[ -n "$PIPELINE_FROM_STEP" ]] && skip="true"

    local completed_steps=()
    local total_steps step_counter
    total_steps=$(echo "$all_steps" | wc -l | tr -d ' ')
    step_counter=0

    while IFS= read -r step_name; do
        # --from: skip fino allo step specificato
        if [[ "$skip" == "true" ]]; then
            if [[ "$step_name" == "$PIPELINE_FROM_STEP" ]]; then
                skip="false"
            else
                display_step_waiting "$step_name"
                continue
            fi
        fi

        # --only: esegui solo quello step
        if [[ -n "$PIPELINE_ONLY_STEP" ]] && [[ "$step_name" != "$PIPELINE_ONLY_STEP" ]]; then
            display_step_waiting "$step_name"
            continue
        fi

        # Leggi config step
        local provider model allowed_tools mcp_servers
        local verdict_required on_reject output

        provider=$(config_step_get_default "$step_name" "provider" \
            "$(config_get_default 'defaults.provider' 'anthropic')")
        model=$(config_step_get_default "$step_name" "model" \
            "$(config_get_default 'defaults.model' '')")
        [[ -n "$PIPELINE_MODEL_OVERRIDE" ]] && model="$PIPELINE_MODEL_OVERRIDE"

        allowed_tools=$(config_step_allowed_tools "$step_name")
        mcp_servers=$(config_step_mcp_servers "$step_name" | tr '\n' ' ' | sed 's/ $//')
        verdict_required=$(config_step_get_default "$step_name" "verdict" "false")
        on_reject=$(config_step_get_default "$step_name" "on_reject" "")
        # Supporto sia on_reject che retry_step (compatibilità con entrambi i formati)
        [[ -z "$on_reject" ]] && on_reject=$(config_step_get_default "$step_name" "retry_step" "")
        output=$(config_step_get_default "$step_name" "output" "")
        output="${output//\$\{FEATURE\}/$PIPELINE_FEATURE}"

        step_counter=$(( step_counter + 1 ))
        state_step_start "$step_name"
        claude_setup_provider "$provider" "$model"

        local step_start retries step_ok
        step_start=$(date +%s)
        retries=0
        step_ok="false"

        while true; do
            # Model escalation on retry
            if [[ $retries -gt 0 ]]; then
                local retry_model
                retry_model=$(config_step_get_default "$step_name" "model_on_retry" "")
                if [[ -n "$retry_model" ]] && [[ "$retry_model" != "$model" ]]; then
                    model="$retry_model"
                    claude_setup_provider "$provider" "$model"
                    display_info "Model escalation per retry: ${model}"
                fi
            fi

            # Costruisci prompt
            local final_prompt
            final_prompt=$(mktemp /tmp/pipeline-prompt-XXXXXX)

            local extra_ctx=""
            if [[ $retries -gt 0 ]] && [[ -n "$on_reject" ]] && [[ -n "$output" ]]; then
                local review_file="${PIPELINE_DIR}/${output}"
                extra_ctx=$(prompt_build_revalidation_context "$retries" "$max_retries" "$review_file" "$step_name")
            fi

            prompt_build "$step_name" "$PIPELINE_FEATURE" "$extra_ctx" > "$final_prompt" || {
                display_error "Impossibile costruire prompt per step ${step_name}"
                rm -f "$final_prompt"
                exit 1
            }

            # Playwright: inietta istruzione se necessario
            playwright_check_step "$step_name" "$PIPELINE_FEATURE" "$final_prompt"

            # Inietta gate instruction se verdict richiesto
            if [[ "$verdict_required" == "true" ]] && [[ -n "$output" ]]; then
                local report_path="${PIPELINE_DIR}/${output}"
                verdict_gate_instruction "$PIPELINE_FEATURE" "$step_name" "$report_path" >> "$final_prompt"
                verdict_clear "$PIPELINE_FEATURE" "$step_name"
            fi

            # Dry-run: mostra prompt con sommario strutturato
            if [[ "$PIPELINE_DRY_RUN" == "true" ]]; then
                local word_count
                word_count=$(wc -w < "$final_prompt" 2>/dev/null | tr -d ' ' || echo "?")
                echo ""
                printf "  ${BOLD}${CYAN}[DRY-RUN]${NC} Step: ${BOLD}%s${NC} | Model: %s | Provider: %s\n" \
                    "$step_name" "$model" "$provider"
                printf "  ${DIM}Prompt: %s parole${NC}\n" "$word_count"
                echo ""
                # Mostra sezioni del prompt (header markdown)
                printf "  ${DIM}Sezioni:${NC}\n"
                grep -E '^#{1,3} ' "$final_prompt" 2>/dev/null | while IFS= read -r header; do
                    printf "  ${DIM}  %s${NC}\n" "$header"
                done
                echo ""
                echo "  --- PROMPT COMPLETO (${word_count} parole) ---"
                cat "$final_prompt"
                echo "  --- END ---"
                rm -f "$final_prompt"
                step_ok="true"
                break
            fi

            # Esegui
            local display_tools="$allowed_tools"
            [[ -n "$mcp_servers" ]] && display_tools="${display_tools} +mcp(${mcp_servers// /,})"
            display_box_start "$step_name" "${model:-default}" "$step_counter" "$total_steps" \
                "$display_tools" "$output"

            local claude_exit=0
            claude_run "$final_prompt" "$step_name" "$model" \
                "$allowed_tools" "$mcp_servers" || claude_exit=$?

            rm -f "$final_prompt"

            local step_end elapsed_s elapsed_str
            step_end=$(date +%s)
            elapsed_s=$(( step_end - step_start ))
            elapsed_str=$(printf "%dm%02ds" $(( elapsed_s / 60 )) $(( elapsed_s % 60 )))

            display_box_stop
            display_file_changes "${CLAUDE_MODIFIED_FILES[@]:-}"
            display_screenshots_saved "${PLAYWRIGHT_OUTPUT_DIR:-}"

            if [[ $claude_exit -eq 75 ]]; then
                state_step_fail "$step_name" "token exhausted"
                display_error "Token esauriti — impossibile continuare"
                exit 75
            fi

            # Claude fallito (non token)
            if [[ $claude_exit -ne 0 ]]; then
                retries=$(( retries + 1 ))
                if [[ $retries -gt $max_retries ]]; then
                    display_step_done "$step_name" "FAILED" "$elapsed_str"
                    state_step_fail "$step_name" "exit ${claude_exit} dopo ${max_retries} tentativi"
                    display_error "Step ${step_name} fallito dopo ${max_retries} tentativi"
                    exit 1
                fi
                display_retry_banner "$step_name" "$retries" "$max_retries" "exit ${claude_exit}"
                continue
            fi

            # Verify: build/lint/test dopo step dev/dev-fix
            if verify_step_needed "$step_name"; then
                if ! verify_run "$step_name" "$PIPELINE_FEATURE"; then
                    retries=$(( retries + 1 ))
                    if [[ $retries -gt $max_retries ]]; then
                        display_step_done "$step_name" "FAILED" "$elapsed_str"
                        state_step_fail "$step_name" "verify fallito dopo ${max_retries} tentativi"
                        display_error "Verify fallito per step ${step_name} dopo ${max_retries} tentativi"
                        exit 1
                    fi
                    local verify_errors
                    verify_errors=$(verify_get_errors "$PIPELINE_FEATURE" "$step_name")
                    display_retry_banner "$step_name" "$retries" "$max_retries" "verify failed"
                    extra_ctx="ERRORI DI BUILD/LINT/TEST — correggili prima di procedere:
---
${verify_errors}
---

Leggi attentamente gli errori sopra. Correggi SOLO i file che causano questi errori.
NON riscrivere file da zero. Usa Edit per modifiche mirate."
                    continue
                fi
            fi

            # Controlla verdict se richiesto
            if [[ "$verdict_required" == "true" ]]; then
                local verdict
                verdict=$(verdict_read "$PIPELINE_FEATURE" "$step_name")

                if [[ "$verdict" == "APPROVED" ]]; then
                    local retry_label=""
                    [[ $retries -gt 0 ]] && retry_label="[retry ${retries}/${max_retries}]"
                    display_gate_result "$step_name" "APPROVED" "$elapsed_str" "$retry_label"
                    step_ok="true"
                    break
                else
                    retries=$(( retries + 1 ))
                    if [[ $retries -gt $max_retries ]]; then
                        display_gate_result "$step_name" "REJECTED" "$elapsed_str" \
                            "max retries raggiunto"
                        [[ -n "$output" ]] && display_rejected_summary "${PIPELINE_DIR}/${output}"
                        state_step_fail "$step_name" "REJECTED dopo ${max_retries} tentativi"
                        display_error "Gate ${step_name} non superato dopo ${max_retries} tentativi"
                        exit 1
                    fi

                    display_gate_result "$step_name" "REJECTED" "$elapsed_str" \
                        "→ retry ${on_reject} (${retries}/${max_retries})"
                    [[ -n "$output" ]] && display_rejected_summary "${PIPELINE_DIR}/${output}"
                    display_retry_banner "$on_reject" "$retries" "$max_retries" "REJECTED by ${step_name}"

                    # Esegui on_reject step
                    if [[ -n "$on_reject" ]]; then
                        local reject_model reject_tools
                        reject_model=$(config_step_get_default "$on_reject" "model" \
                            "$(config_get_default 'defaults.model' '')")
                        [[ -n "$PIPELINE_MODEL_OVERRIDE" ]] && reject_model="$PIPELINE_MODEL_OVERRIDE"
                        reject_tools=$(config_step_allowed_tools "$on_reject")

                        local feedback=""
                        [[ -f "${PIPELINE_DIR}/${output}" ]] && feedback=$(cat "${PIPELINE_DIR}/${output}")

                        local reject_prompt
                        reject_prompt=$(mktemp /tmp/pipeline-reject-XXXXXX)
                        prompt_build "$on_reject" "$PIPELINE_FEATURE" "$feedback" > "$reject_prompt" || true

                        playwright_check_step "$on_reject" "$PIPELINE_FEATURE" "$reject_prompt"

                        claude_setup_provider "$provider" "$reject_model"
                        display_box_start "$on_reject" "$reject_model" "$step_counter" "$total_steps" \
                            "$reject_tools" ""
                        claude_run "$reject_prompt" "$on_reject" "$reject_model" "$reject_tools" "" || true
                        rm -f "$reject_prompt"
                        display_box_stop
                        display_file_changes "${CLAUDE_MODIFIED_FILES[@]:-}"
                        display_screenshots_saved "${PLAYWRIGHT_OUTPUT_DIR:-}"
                        claude_setup_provider "$provider" "$model"
                    fi
                    continue
                fi
            else
                display_step_done "$step_name" "completato" "$elapsed_str"
                step_ok="true"
                break
            fi
        done

        if [[ "$step_ok" == "true" ]]; then
            local step_end_final
            step_end_final=$(date +%s)
            state_step_done "$step_name" $(( step_end_final - step_start )) "$retries"
            completed_steps+=("$step_name")
            # Aggiorna contesto cross-step
            context_add_step "$PIPELINE_FEATURE" "$step_name"
            context_add_files "$PIPELINE_FEATURE" "${CLAUDE_MODIFIED_FILES[@]:-}"
        fi

    done <<< "$all_steps"

    state_done

    local pipeline_end total_s total_str
    pipeline_end=$(date +%s)
    total_s=$(( pipeline_end - pipeline_start ))
    total_str=$(printf "%dm%02ds" $(( total_s / 60 )) $(( total_s % 60 )))

    # Raccogli file di output
    local output_files=()
    for completed_step in "${completed_steps[@]}"; do
        local step_out
        step_out=$(config_step_get_default "$completed_step" "output" "")
        step_out="${step_out//\$\{FEATURE\}/$PIPELINE_FEATURE}"
        if [[ -n "$step_out" ]]; then
            output_files+=("${completed_step}: ${step_out}")
        fi
    done

    # Integration check finale (non-AI)
    if _integration_enabled; then
        display_info "Integration check finale..."
        local int_log="${PIPELINE_DIR}/verify/${PIPELINE_FEATURE}-integration.log"
        if _integration_run "$int_log"; then
            display_info "Integration check: PASSED"
        else
            display_warn "Integration check: FAILED — vedi ${int_log}"
            output_files+=("integration: FAILED (${int_log})")
        fi
    fi

    display_success "$PIPELINE_FEATURE" "$total_str" "${output_files[@]}"
}

# ---------------------------------------------------------------------------
# _run_batch — esecuzione sequenziale di più feature
# Ogni feature viene eseguita in una subshell per isolare eventuali exit.
# ---------------------------------------------------------------------------
_run_batch() {
    local features=("${PIPELINE_FEATURES[@]}")
    local total=${#features[@]}

    # Genera JSON array dei nomi per batch_state_init
    local features_json="["
    local first=true
    for f in "${features[@]}"; do
        if [[ "$first" == "true" ]]; then
            features_json+="\"${f}\""
            first=false
        else
            features_json+=",\"${f}\""
        fi
    done
    features_json+="]"

    display_batch_header "$total" "${features[@]}"
    batch_state_init "$features_json"

    local completed_features=()
    local failed_features=()
    local skipped_features=()
    local batch_start
    batch_start=$(date +%s)

    for i in "${!features[@]}"; do
        local feature="${features[$i]}"
        local idx=$(( i + 1 ))

        PIPELINE_FEATURE="$feature"
        export PIPELINE_FEATURE

        # Verifica che il brief esista
        local brief_file="${PIPELINE_DIR}/briefs/${feature}.md"
        if [[ ! -f "$brief_file" ]]; then
            display_warn "Brief non trovato per '${feature}' — skip"
            skipped_features+=("$feature")
            batch_state_feature_skip "$feature"
            continue
        fi

        display_batch_feature_start "$feature" "$idx" "$total"
        batch_state_feature_start "$feature"

        local feature_start
        feature_start=$(date +%s)

        # Esegui pipeline in subshell per isolare exit
        local exit_code=0
        ( _run_pipeline ) || exit_code=$?

        local feature_end feature_elapsed_s feature_elapsed_str
        feature_end=$(date +%s)
        feature_elapsed_s=$(( feature_end - feature_start ))
        feature_elapsed_str=$(printf "%dm%02ds" $(( feature_elapsed_s / 60 )) $(( feature_elapsed_s % 60 )))

        if [[ $exit_code -eq 0 ]]; then
            completed_features+=("$feature")
            batch_state_feature_done "$feature" "$feature_elapsed_str"
            display_batch_feature_result "$feature" "completed" "$feature_elapsed_str" "$idx" "$total"
        else
            failed_features+=("$feature")
            batch_state_feature_fail "$feature" "$exit_code"
            display_batch_feature_result "$feature" "failed" "$feature_elapsed_str" "$idx" "$total"

            if [[ "$PIPELINE_CONTINUE_ON_ERROR" != "true" ]]; then
                # Marca le rimanenti come skipped
                local j
                for (( j = i + 1; j < total; j++ )); do
                    skipped_features+=("${features[$j]}")
                    batch_state_feature_skip "${features[$j]}"
                done
                break
            fi
        fi
    done

    local batch_end batch_elapsed_s batch_elapsed_str
    batch_end=$(date +%s)
    batch_elapsed_s=$(( batch_end - batch_start ))
    batch_elapsed_str=$(printf "%dm%02ds" $(( batch_elapsed_s / 60 )) $(( batch_elapsed_s % 60 )))

    # Determina stato finale
    local final_status="completed"
    [[ ${#failed_features[@]} -gt 0 ]] && final_status="failed"
    [[ ${#skipped_features[@]} -gt 0 ]] && [[ ${#failed_features[@]} -eq 0 ]] && final_status="completed"

    batch_state_done "$final_status"

    # Componi dettagli per il summary
    local detail_lines=()
    for f in "${completed_features[@]}"; do
        detail_lines+=("v  ${f}")
    done
    for f in "${failed_features[@]}"; do
        detail_lines+=("x  ${f}")
    done
    for f in "${skipped_features[@]}"; do
        detail_lines+=("-  ${f} (skip)")
    done

    display_batch_summary "$total" "${#completed_features[@]}" "${#failed_features[@]}" \
        "${#skipped_features[@]}" "$batch_elapsed_str" "${detail_lines[@]}"

    [[ ${#failed_features[@]} -gt 0 ]] && exit 1
    exit 0
}

# ---------------------------------------------------------------------------
# _main — CLI parsing + validation + avvio
# ---------------------------------------------------------------------------
_main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)              PIPELINE_FROM_STEP="$2"; shift 2 ;;
            --only)              PIPELINE_ONLY_STEP="$2"; shift 2 ;;
            --resume)            PIPELINE_RESUME="true"; shift ;;
            --dry-run)           PIPELINE_DRY_RUN="true"; shift ;;
            --model)             PIPELINE_MODEL_OVERRIDE="$2"; shift 2 ;;
            --app)               APP="$2"; shift 2 ;;
            --description)       PIPELINE_DESCRIPTION="$2"; shift 2 ;;
            --batch-file)        PIPELINE_BATCH_FILE="$2"; shift 2 ;;
            --continue-on-error) PIPELINE_CONTINUE_ON_ERROR="true"; shift ;;
            --state)             PIPELINE_SHOW_STATE="true"; shift ;;
            --help|-h)           _usage; exit 0 ;;
            -*)                  display_error "Opzione sconosciuta: $1"; _usage; exit 1 ;;
            *)                   PIPELINE_FEATURES+=("$1"); shift ;;
        esac
    done

    # Carica feature da batch file se specificato
    if [[ -n "$PIPELINE_BATCH_FILE" ]]; then
        if [[ ! -f "$PIPELINE_BATCH_FILE" ]]; then
            display_error "Batch file non trovato: ${PIPELINE_BATCH_FILE}"
            exit 1
        fi
        while IFS= read -r _line; do
            _line="${_line%%#*}"                       # strip commenti
            _line=$(echo "$_line" | xargs 2>/dev/null) # strip whitespace
            [[ -z "$_line" ]] && continue
            PIPELINE_FEATURES+=("$_line")
        done < "$PIPELINE_BATCH_FILE"
    fi

    # Imposta PIPELINE_FEATURE per single-feature (backward compat)
    if [[ ${#PIPELINE_FEATURES[@]} -eq 1 ]]; then
        PIPELINE_FEATURE="${PIPELINE_FEATURES[0]}"
    fi

    export PIPELINE_FEATURE APP

    # --state (non richiede feature)
    if [[ "$PIPELINE_SHOW_STATE" == "true" ]]; then
        _pipeline_show_state
        exit 0
    fi

    if [[ ${#PIPELINE_FEATURES[@]} -eq 0 ]]; then
        display_error "Feature name richiesta"
        _usage
        exit 1
    fi

    # Validazione: --description incompatibile con batch mode
    if [[ -n "$PIPELINE_DESCRIPTION" ]] && [[ ${#PIPELINE_FEATURES[@]} -gt 1 ]]; then
        display_error "--description non è compatibile con batch mode. Crea i file brief prima."
        exit 1
    fi

    # ---------------------------------------------------------------------------
    # Prerequisiti
    # ---------------------------------------------------------------------------
    if ! command -v claude &>/dev/null; then
        display_error "Claude Code CLI non trovato. Installa: https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    fi

    if ! command -v python3 &>/dev/null; then
        display_error "python3 richiesto ma non trovato."
        exit 1
    fi

    # Blocca se lanciato dall'interno di Claude Code interattivo
    if [[ -n "${CLAUDECODE:-}" ]] && [[ "$PIPELINE_DRY_RUN" != "true" ]]; then
        display_error "Non puoi lanciare la pipeline dall'interno di Claude Code. Usa un terminale esterno."
        exit 1
    fi

    if [[ ! -f "$PIPELINE_CONFIG_FILE" ]]; then
        display_error "pipeline.yaml non trovato in: ${PIPELINE_DIR}"
        display_info "Copia example/pipeline.yaml e personalizzalo."
        exit 1
    fi

    config_validate || exit 1

    # Crea directory necessarie
    mkdir -p "${PIPELINE_DIR}/briefs" \
             "${PIPELINE_DIR}/specs" \
             "${PIPELINE_DIR}/reviews" \
             "${PIPELINE_DIR}/qa" \
             "${PIPELINE_DIR}/logs" \
             "${PIPELINE_DIR}/verdicts" \
             "${PIPELINE_DIR}/screenshots" \
             "${PIPELINE_DIR}/verify" \
             "${PIPELINE_DIR}/context"

    # Brief management
    if [[ -n "$PIPELINE_DESCRIPTION" ]]; then
        echo "$PIPELINE_DESCRIPTION" > "${PIPELINE_DIR}/briefs/${PIPELINE_FEATURE}.md"
        display_info "Brief creato: briefs/${PIPELINE_FEATURE}.md"
    fi

    # Configura token retry da YAML
    CLAUDE_TOKEN_MAX_RETRIES=$(config_get_default "defaults.token_max_retries" "5")
    CLAUDE_TOKEN_BASE_DELAY=$(config_get_default "defaults.token_base_delay" "60")
    export CLAUDE_TOKEN_MAX_RETRIES CLAUDE_TOKEN_BASE_DELAY

    # Verifica dev server se almeno uno step attivo richiede playwright
    if [[ "$PIPELINE_DRY_RUN" != "true" ]]; then
        local _needs_pw=false
        local _all_steps_check
        _all_steps_check=$(config_steps_names)
        while IFS= read -r _s; do
            if [[ -n "$PIPELINE_ONLY_STEP" ]] && [[ "$_s" != "$PIPELINE_ONLY_STEP" ]]; then continue; fi
            if [[ "$(config_step_needs_playwright "$_s")" == "true" ]]; then
                _needs_pw=true
                break
            fi
        done <<< "$_all_steps_check"
        if [[ "$_needs_pw" == "true" ]]; then
            playwright_require_server
        fi
    fi

    # =========================================================================
    # Dispatch: batch mode vs single feature
    # =========================================================================
    if [[ ${#PIPELINE_FEATURES[@]} -gt 1 ]]; then
        # ----- BATCH MODE -----
        # Valida che tutti i brief esistano (avvisa ma non blocca)
        local _missing_briefs=0
        for _bf in "${PIPELINE_FEATURES[@]}"; do
            if [[ ! -f "${PIPELINE_DIR}/briefs/${_bf}.md" ]]; then
                display_warn "Brief mancante: briefs/${_bf}.md — sarà saltata"
                _missing_briefs=$(( _missing_briefs + 1 ))
            fi
        done
        if [[ $_missing_briefs -eq ${#PIPELINE_FEATURES[@]} ]]; then
            display_error "Nessun brief trovato per le feature specificate."
            exit 1
        fi

        _run_batch
    else
        # ----- SINGLE FEATURE MODE -----
        # --resume: trova il primo step incompleto
        if [[ "$PIPELINE_RESUME" == "true" ]] && [[ -z "$PIPELINE_FROM_STEP" ]]; then
            display_info "Rilevamento step completati..."
            local all_steps_resume
            all_steps_resume=$(config_steps_names)
            while IFS= read -r resume_step; do
                local resume_output
                resume_output=$(config_step_get "$resume_step" "output")
                resume_output="${resume_output//\$\{FEATURE\}/$PIPELINE_FEATURE}"
                if [[ -n "$resume_output" ]] && [[ ! -f "${PIPELINE_DIR}/${resume_output}" ]]; then
                    PIPELINE_FROM_STEP="$resume_step"
                    display_info "Resume da: ${resume_step}"
                    break
                fi
            done <<< "$all_steps_resume"
        fi

        _run_pipeline
    fi
}

# ---------------------------------------------------------------------------
# Avvia
# ---------------------------------------------------------------------------
_main "$@"
