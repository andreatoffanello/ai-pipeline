#!/usr/bin/env bash
# pipeline.sh — AI Pipeline Orchestrator
#
# Usage:
#   ./ai-pipeline/pipeline.sh <feature> [options]
#
# Options:
#   --from <step>          Riparte da uno step specifico
#   --resume               Riprende dall'ultimo step incompleto
#   --only <step>          Esegue solo quello step
#   --dry-run              Mostra i prompt senza eseguire
#   --model <model>        Override modello per tutti gli step
#   --description "..."    Brief inline (crea briefs/<feature>.md)
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

export PIPELINE_DIR PIPELINE_CONFIG_FILE PIPELINE_STATE_FILE

# ---------------------------------------------------------------------------
# Load libs
# ---------------------------------------------------------------------------
source "${PIPELINE_DIR}/lib/config.sh"
source "${PIPELINE_DIR}/lib/display.sh"
source "${PIPELINE_DIR}/lib/state.sh"
source "${PIPELINE_DIR}/lib/verdict.sh"
source "${PIPELINE_DIR}/lib/claude.sh"

# ---------------------------------------------------------------------------
# Trap
# ---------------------------------------------------------------------------
trap 'display_trap_cleanup; exit 1' INT TERM

# ---------------------------------------------------------------------------
# CLI parsing vars
# ---------------------------------------------------------------------------
PIPELINE_FEATURE=""
PIPELINE_FROM_STEP=""
PIPELINE_ONLY_STEP=""
PIPELINE_DRY_RUN="false"
PIPELINE_RESUME="false"
PIPELINE_MODEL_OVERRIDE=""
PIPELINE_DESCRIPTION=""
PIPELINE_SHOW_STATE="false"

# ---------------------------------------------------------------------------
# _usage
# ---------------------------------------------------------------------------
_usage() {
    cat <<EOF

Usage: $(basename "$0") <feature> [options]

Options:
  --from <step>          Riparte da uno step specifico
  --resume               Riprende dall'ultimo step incompleto
  --only <step>          Esegue solo quello step
  --dry-run              Mostra i prompt senza eseguire
  --model <model>        Override modello per tutti gli step
  --description "..."    Brief inline (crea briefs/<feature>.md)
  --state                Mostra stato corrente
  --help                 Aiuto

Examples:
  ./ai-pipeline/pipeline.sh button-outline --description "Aggiungere variante outline"
  ./ai-pipeline/pipeline.sh button-outline --resume
  ./ai-pipeline/pipeline.sh button-outline --from dev
  ./ai-pipeline/pipeline.sh button-outline --only qa
  ./ai-pipeline/pipeline.sh --state

EOF
}

# ---------------------------------------------------------------------------
# _pipeline_show_state — mostra stato corrente da state.json
# ---------------------------------------------------------------------------
_pipeline_show_state() {
    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then
        display_error "Nessuna pipeline in corso (state.json non trovato)"
        return 1
    fi

    local feature started
    feature=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('feature','?'))" \
        "$PIPELINE_STATE_FILE" 2>/dev/null || echo "?")
    started=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('started_at','?'))" \
        "$PIPELINE_STATE_FILE" 2>/dev/null || echo "?")

    echo ""
    echo "  Pipeline: ${feature}"
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
            failed)      printf "  ${RED}✗${NC}  %-14s %s\n" "$show_step" "${RED}fallito${NC}" ;;
            *)           display_step_waiting "$show_step" ;;
        esac
    done <<< "$all_steps"
    echo ""
}

# ---------------------------------------------------------------------------
# _run_reject_step <reject_step> <gate_step> <gate_output> <provider> <model> <tools>
# Esegue lo step di correzione quando un gate viene rifiutato.
# ---------------------------------------------------------------------------
_run_reject_step() {
    local reject_step="$1"
    local gate_step="$2"
    local gate_output="$3"
    local fallback_provider="$4"
    local fallback_model="$5"
    local fallback_tools="$6"

    local reject_prompt_rel
    reject_prompt_rel=$(config_step_get_default "$reject_step" "prompt" "prompts/${reject_step}.md")
    local reject_prompt="${PIPELINE_DIR}/${reject_prompt_rel}"

    if [[ ! -f "$reject_prompt" ]]; then
        display_warn "Prompt on_reject non trovato: ${reject_prompt} — salto"
        return 0
    fi

    local reject_provider reject_model reject_tools
    reject_provider=$(config_step_get_default "$reject_step" "provider" "$fallback_provider")
    reject_model=$(config_step_get_default "$reject_step" "model" "$fallback_model")
    [[ -n "$PIPELINE_MODEL_OVERRIDE" ]] && reject_model="$PIPELINE_MODEL_OVERRIDE"
    reject_tools=$(config_step_get_default "$reject_step" "allowed_tools" "$fallback_tools")

    claude_setup_provider "$reject_provider" "$reject_model"

    local reject_tmp
    reject_tmp=$(mktemp /tmp/pipeline-reject.XXXXXX.md)
    cp "$reject_prompt" "$reject_tmp"
    sed -i.bak "s/\${FEATURE}/${PIPELINE_FEATURE}/g" "$reject_tmp"
    rm -f "${reject_tmp}.bak"

    # Inietta feedback dalla review
    local review_file="${PIPELINE_DIR}/${gate_output}"
    if [[ -f "$review_file" ]]; then
        printf "\n---\nFEEDBACK dalla revisione (da correggere):\n%s\n" \
            "$(cat "$review_file")" >> "$reject_tmp"
    fi

    display_info "Eseguo step di correzione: ${reject_step}"
    display_box_start "$reject_step" "${reject_model:-default}"
    claude_run "$reject_tmp" "$reject_step" "$reject_model" "$reject_tools" "" || true
    rm -f "$reject_tmp"
    display_box_stop

    # Ripristina provider originale
    claude_setup_provider "$fallback_provider" "$fallback_model"
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
        local emoji
        case "$step" in
            pm)   emoji="📋" ;;
            dr*)  emoji="🔍" ;;
            dev*) emoji="⚡" ;;
            qa*)  emoji="✅" ;;
            *)    emoji="▸"  ;;
        esac
        if [[ "$first" == "true" ]]; then
            steps_str="${emoji} ${step}"
            first=false
        else
            steps_str="${steps_str} → ${emoji} ${step}"
        fi
    done <<< "$all_steps"

    display_header "$pipeline_name" "$PIPELINE_FEATURE" "$steps_str"

    state_init "$PIPELINE_FEATURE"

    local pipeline_start
    pipeline_start=$(date +%s)
    local skip="false"
    [[ -n "$PIPELINE_FROM_STEP" ]] && skip="true"

    local completed_steps=()

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
        local verdict_required on_reject output prompt_file_rel

        provider=$(config_step_get_default "$step_name" "provider" \
            "$(config_get_default 'defaults.provider' 'anthropic')")
        model=$(config_step_get_default "$step_name" "model" \
            "$(config_get_default 'defaults.model' '')")
        [[ -n "$PIPELINE_MODEL_OVERRIDE" ]] && model="$PIPELINE_MODEL_OVERRIDE"

        allowed_tools=$(config_step_get_default "$step_name" "allowed_tools" \
            "$(config_get_default 'defaults.allowed_tools' 'Read,Write,Edit,Bash,Glob,Grep')")
        mcp_servers=$(config_step_mcp_servers "$step_name" | tr '\n' ' ' | sed 's/ $//')
        verdict_required=$(config_step_get_default "$step_name" "verdict" "false")
        on_reject=$(config_step_get_default "$step_name" "on_reject" "")
        output=$(config_step_get_default "$step_name" "output" "")
        output="${output//\$\{FEATURE\}/$PIPELINE_FEATURE}"
        prompt_file_rel=$(config_step_get_default "$step_name" "prompt" "prompts/${step_name}.md")

        state_step_start "$step_name"
        claude_setup_provider "$provider" "$model"

        local step_start retries step_ok
        step_start=$(date +%s)
        retries=0
        step_ok="false"

        while true; do
            local prompt_file="${PIPELINE_DIR}/${prompt_file_rel}"
            if [[ ! -f "$prompt_file" ]]; then
                display_error "Prompt non trovato: ${prompt_file}"
                exit 1
            fi

            # Costruisci prompt finale in tmp file
            local final_prompt
            final_prompt=$(mktemp /tmp/pipeline-prompt.XXXXXX.md)

            cp "$prompt_file" "$final_prompt"

            # Sostituisci ${FEATURE}
            sed -i.bak "s/\${FEATURE}/${PIPELINE_FEATURE}/g" "$final_prompt"
            rm -f "${final_prompt}.bak"

            # Inietta brief per step pm
            local brief_file="${PIPELINE_DIR}/briefs/${PIPELINE_FEATURE}.md"
            if [[ "$step_name" == "pm" ]] && [[ -f "$brief_file" ]]; then
                printf "\n---\nBRIEF FEATURE:\n%s\n" "$(cat "$brief_file")" >> "$final_prompt"
            fi

            # Inietta gate instruction
            if [[ "$verdict_required" == "true" ]] && [[ -n "$output" ]]; then
                local report_path="${PIPELINE_DIR}/${output}"
                verdict_gate_instruction "$PIPELINE_FEATURE" "$step_name" "$report_path" >> "$final_prompt"
                verdict_clear "$PIPELINE_FEATURE" "$step_name"
                verdict_ensure_dir
            fi

            # Inietta feedback retry se necessario
            if [[ $retries -gt 0 ]] && [[ -n "$on_reject" ]] && [[ -n "$output" ]]; then
                local review_file="${PIPELINE_DIR}/${output}"
                if [[ -f "$review_file" ]]; then
                    printf "\n---\nRIVALIDAZIONE (tentativo %d/%d):\n" "$retries" "$max_retries" >> "$final_prompt"
                    printf "Verifica SOLO che i problemi della revisione precedente siano stati risolti.\n" >> "$final_prompt"
                    printf "Non aggiungere nuove revisioni.\n\nRevisione precedente:\n%s\n" \
                        "$(cat "$review_file")" >> "$final_prompt"
                fi
            fi

            # Dry-run: mostra prompt e continua
            if [[ "$PIPELINE_DRY_RUN" == "true" ]]; then
                echo ""
                echo "  [DRY-RUN] Step: ${step_name} | Model: ${model} | Provider: ${provider}"
                echo "  Prompt: ${final_prompt}"
                echo "  ---"
                cat "$final_prompt"
                echo "  ---"
                rm -f "$final_prompt"
                step_ok="true"
                break
            fi

            # Esegui
            display_box_start "$step_name" "${model:-default}"

            local claude_exit=0
            claude_run "$final_prompt" "$step_name" "$model" \
                "$allowed_tools" "$mcp_servers" || claude_exit=$?

            rm -f "$final_prompt"

            local step_end elapsed_s elapsed_str
            step_end=$(date +%s)
            elapsed_s=$(( step_end - step_start ))
            elapsed_str=$(printf "%dm%02ds" $(( elapsed_s / 60 )) $(( elapsed_s % 60 )))

            display_box_stop

            # Claude fallito (non token)
            if [[ $claude_exit -ne 0 ]] && [[ $claude_exit -ne 75 ]]; then
                retries=$(( retries + 1 ))
                if [[ $retries -gt $max_retries ]]; then
                    display_step_done "$step_name" "FAILED" "$elapsed_str"
                    state_step_fail "$step_name" "exit ${claude_exit} dopo ${max_retries} tentativi"
                    display_error "Step ${step_name} fallito dopo ${max_retries} tentativi"
                    exit 1
                fi
                display_warn "Step fallito (exit ${claude_exit}) — retry ${retries}/${max_retries}"
                continue
            fi

            if [[ $claude_exit -eq 75 ]]; then
                display_step_done "$step_name" "FAILED" "$elapsed_str"
                state_step_fail "$step_name" "token exhausted"
                display_error "Token esauriti — impossibile continuare"
                exit 75
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
                        state_step_fail "$step_name" "REJECTED dopo ${max_retries} tentativi"
                        display_error "Gate ${step_name} non superato dopo ${max_retries} tentativi"
                        exit 1
                    fi

                    display_gate_result "$step_name" "REJECTED" "$elapsed_str" \
                        "retry ${on_reject} (${retries}/${max_retries})"

                    # Esegui on_reject step
                    if [[ -n "$on_reject" ]]; then
                        _run_reject_step "$on_reject" "$step_name" "$output" \
                            "$provider" "$model" "$allowed_tools"
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

    display_success "$PIPELINE_FEATURE" "$total_str" "${output_files[@]}"
}

# ---------------------------------------------------------------------------
# _main — CLI parsing + validation + avvio
# ---------------------------------------------------------------------------
_main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)        PIPELINE_FROM_STEP="$2"; shift 2 ;;
            --only)        PIPELINE_ONLY_STEP="$2"; shift 2 ;;
            --resume)      PIPELINE_RESUME="true"; shift ;;
            --dry-run)     PIPELINE_DRY_RUN="true"; shift ;;
            --model)       PIPELINE_MODEL_OVERRIDE="$2"; shift 2 ;;
            --description) PIPELINE_DESCRIPTION="$2"; shift 2 ;;
            --state)       PIPELINE_SHOW_STATE="true"; shift ;;
            --help|-h)     _usage; exit 0 ;;
            -*)            display_error "Opzione sconosciuta: $1"; _usage; exit 1 ;;
            *)
                if [[ -z "$PIPELINE_FEATURE" ]]; then
                    PIPELINE_FEATURE="$1"
                else
                    display_error "Feature già specificata: ${PIPELINE_FEATURE}"; exit 1
                fi
                shift ;;
        esac
    done

    export PIPELINE_FEATURE

    # --state (non richiede feature)
    if [[ "$PIPELINE_SHOW_STATE" == "true" ]]; then
        _pipeline_show_state
        exit 0
    fi

    if [[ -z "$PIPELINE_FEATURE" ]]; then
        display_error "Feature name richiesta"
        _usage
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
             "${PIPELINE_DIR}/verdicts"

    # Brief management
    if [[ -n "$PIPELINE_DESCRIPTION" ]]; then
        echo "$PIPELINE_DESCRIPTION" > "${PIPELINE_DIR}/briefs/${PIPELINE_FEATURE}.md"
        display_info "Brief creato: briefs/${PIPELINE_FEATURE}.md"
    fi

    # Configura token retry da YAML
    CLAUDE_TOKEN_MAX_RETRIES=$(config_get_default "defaults.token_max_retries" "5")
    CLAUDE_TOKEN_BASE_DELAY=$(config_get_default "defaults.token_base_delay" "60")
    export CLAUDE_TOKEN_MAX_RETRIES CLAUDE_TOKEN_BASE_DELAY

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
}

# ---------------------------------------------------------------------------
# Avvia
# ---------------------------------------------------------------------------
_main "$@"
