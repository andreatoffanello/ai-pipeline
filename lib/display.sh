#!/usr/bin/env bash
# lib/display.sh — Terminal UI: box ASCII, spinner Braille, semi-log effimeri

# Colori ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# display_header <pipeline_name> <feature> <steps_string>
# Stampa il box di intestazione pipeline.
# ---------------------------------------------------------------------------
display_header() {
    local name="$1"
    local feature="$2"
    local steps_str="$3"
    echo -e ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}  ║  %-61s║${NC}\n" "${name} pipeline"
    printf "${BOLD}  ║  Feature: %-52s║${NC}\n" "${feature}"
    printf "${BOLD}  ║  Steps: %-54s║${NC}\n" "${steps_str}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
}

# ---------------------------------------------------------------------------
# display_step_done <name> <verdict_or_status> <elapsed> [retry_info]
# ---------------------------------------------------------------------------
display_step_done() {
    local name="$1"
    local step_status="$2"
    local elapsed="$3"
    local retry_info="${4:-}"

    local icon color
    case "$step_status" in
        APPROVED|completato)
            icon="✓"; color="$GREEN" ;;
        REJECTED)
            icon="✗"; color="$RED" ;;
        *)
            icon="✓"; color="$GREEN" ;;
    esac

    printf "  ${color}${icon}${NC}  %-14s %-14s %s %s\n" \
        "$name" "$step_status" "$elapsed" "${DIM}${retry_info}${NC}"
}

# ---------------------------------------------------------------------------
# display_step_waiting <name>
# ---------------------------------------------------------------------------
display_step_waiting() {
    local name="$1"
    printf "  ${DIM}○${NC}  %-14s %s\n" "$name" "${DIM}in attesa${NC}"
}

# ---------------------------------------------------------------------------
# Spinner state
# ---------------------------------------------------------------------------
_SPINNER_PID=""
_SPINNER_TMPDIR=""
_SPINNER_LINES_FILE=""
_SPINNER_ACTION_COUNT=0
_SPINNER_START_EPOCH=0
_BOX_LINES=9

# ---------------------------------------------------------------------------
# display_box_start <step_name> <model>
# Avvia il box interattivo con spinner e semi-log.
# ---------------------------------------------------------------------------
display_box_start() {
    local step_name="$1"
    local model="$2"

    _SPINNER_TMPDIR=$(mktemp -d)
    _SPINNER_LINES_FILE="$_SPINNER_TMPDIR/actions"
    _SPINNER_ACTION_COUNT=0
    _SPINNER_START_EPOCH=$(date +%s)

    # Stampa box iniziale (riserva le righe)
    _display_box_initial "$step_name" "$model"

    # Avvia refresh loop in background
    local lines_file="$_SPINNER_LINES_FILE"
    local start_epoch="$_SPINNER_START_EPOCH"
    local box_lines="$_BOX_LINES"

    (
        local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0

        while true; do
            local c="${spin_chars:$(( i % ${#spin_chars} )):1}"
            local now elapsed mins secs elapsed_str
            now=$(date +%s)
            elapsed=$(( now - start_epoch ))
            mins=$(( elapsed / 60 ))
            secs=$(( elapsed % 60 ))
            elapsed_str=$(printf "%dm%02ds" "$mins" "$secs")

            local actions="" total=0
            if [[ -f "$lines_file" ]]; then
                actions=$(tail -5 "$lines_file" 2>/dev/null || true)
                total=$(wc -l < "$lines_file" 2>/dev/null | tr -d ' ' || echo 0)
            fi

            # Torna su di box_lines righe e ridisegna
            printf "\033[%dA\033[J" "$box_lines"
            _display_box_render "$step_name" "$model" "$elapsed_str" "$c" "$actions" "$total"

            i=$(( i + 1 ))
            sleep 0.15
        done
    ) &
    _SPINNER_PID=$!
}

# Stampa box iniziale statico (9 righe)
_display_box_initial() {
    local step_name="$1"
    local model="$2"
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    local inner=$(( cols - 4 ))

    printf "  ${CYAN}┌─ %-*s─┐${NC}\n" $(( inner - 1 )) "${step_name} (${model}) "
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" "⠋ Lavorando..."
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""
    local bar
    bar=$(printf '─%.0s' $(seq 1 $(( inner + 2 ))))
    printf "  ${CYAN}└%s┘${NC}\n" "$bar"
}

# Render completo con contenuto dinamico (9 righe)
_display_box_render() {
    local step_name="$1"
    local model="$2"
    local elapsed="$3"
    local spinner_char="$4"
    local actions="$5"
    local total_actions="$6"

    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    local inner=$(( cols - 4 ))

    # Header con elapsed a destra
    local header_left="${step_name} (${model})"
    local header_right="${elapsed}"
    local dash_space=$(( inner - ${#header_left} - ${#header_right} - 4 ))
    [[ $dash_space -lt 1 ]] && dash_space=1
    local dashes
    dashes=$(printf '─%.0s' $(seq 1 $dash_space))

    printf "  ${CYAN}┌─ %s %s %s ─┐${NC}\n" \
        "$header_left" "$dashes" "$header_right"

    # Spinner line
    printf "  ${CYAN}│${NC} ${CYAN}%s${NC} %-*s ${CYAN}│${NC}\n" \
        "$spinner_char" $(( inner - 2 )) "Lavorando..."

    # Empty separator
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""

    # 5 action lines
    local action_lines=()
    if [[ -n "$actions" ]]; then
        while IFS= read -r line; do
            action_lines+=("$line")
        done <<< "$actions"
    fi

    local extra=$(( total_actions > 5 ? total_actions - 5 : 0 ))

    for i in 0 1 2 3 4; do
        local line="${action_lines[$i]:-}"
        line="${line:0:$inner}"
        if [[ -n "$line" ]]; then
            printf "  ${CYAN}│${NC} ${DIM}~ %-*s${NC} ${CYAN}│${NC}\n" $(( inner - 2 )) "$line"
        else
            printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$inner" ""
        fi
    done

    # Footer con counter azioni extra
    local footer=""
    if [[ $extra -gt 0 ]]; then
        footer="(+${extra} azioni)"
    fi
    printf "  ${CYAN}│${NC} %*s${DIM}%s${NC}  ${CYAN}│${NC}\n" \
        $(( inner - ${#footer} )) "" "$footer"

    # Bottom border
    local bar
    bar=$(printf '─%.0s' $(seq 1 $(( inner + 2 ))))
    printf "  ${CYAN}└%s┘${NC}\n" "$bar"
}

# ---------------------------------------------------------------------------
# display_box_add_action <tool_type> <argument>
# Aggiunge un'azione al semi-log del box attivo.
# ---------------------------------------------------------------------------
display_box_add_action() {
    local tool="$1"
    local arg="$2"
    if [[ -n "$_SPINNER_LINES_FILE" ]]; then
        printf "%-8s %s\n" "$tool" "$arg" >> "$_SPINNER_LINES_FILE"
        _SPINNER_ACTION_COUNT=$(( _SPINNER_ACTION_COUNT + 1 ))
    fi
}

# ---------------------------------------------------------------------------
# display_box_stop
# Ferma lo spinner e cancella il box.
# ---------------------------------------------------------------------------
display_box_stop() {
    if [[ -n "$_SPINNER_PID" ]] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null || true
    fi
    _SPINNER_PID=""

    # Cancella il box
    printf "\033[%dA\033[J" "$_BOX_LINES"

    if [[ -n "$_SPINNER_TMPDIR" ]]; then
        rm -rf "$_SPINNER_TMPDIR"
        _SPINNER_TMPDIR=""
        _SPINNER_LINES_FILE=""
    fi
}

# ---------------------------------------------------------------------------
# display_gate_result <step_name> <APPROVED|REJECTED> <elapsed> [info]
# ---------------------------------------------------------------------------
display_gate_result() {
    local step_name="$1"
    local result="$2"
    local elapsed="$3"
    local info="${4:-}"

    if [[ "$result" == "APPROVED" ]]; then
        printf "  ${GREEN}✓${NC}  %-14s ${GREEN}APPROVED${NC}      %s %s\n" \
            "$step_name" "$elapsed" "${DIM}${info}${NC}"
    else
        printf "  ${RED}✗${NC}  %-14s ${RED}REJECTED${NC}      %s   ${DIM}→ %s${NC}\n" \
            "$step_name" "$elapsed" "$info"
    fi
}

# ---------------------------------------------------------------------------
# display_success <feature> <elapsed> [output_file...]
# Box finale di completamento.
# ---------------------------------------------------------------------------
display_success() {
    local feature="$1"
    local elapsed="$2"
    shift 2
    local files=("$@")

    echo -e ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${GREEN}  ║  ✓ Pipeline completata — %-37s║${NC}\n" "${elapsed}"
    printf "${BOLD}${GREEN}  ║  Feature: %-52s║${NC}\n" "${feature}"
    echo -e "${BOLD}${GREEN}  ║                                                              ║${NC}"
    for f in "${files[@]}"; do
        printf "${BOLD}${GREEN}  ║  %-61s║${NC}\n" "$f"
    done
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
}

# ---------------------------------------------------------------------------
# display_error / display_warn / display_info
# ---------------------------------------------------------------------------
display_error() {
    echo -e "  ${RED}✗  $1${NC}" >&2
}

display_warn() {
    echo -e "  ${YELLOW}⚠  $1${NC}"
}

display_info() {
    echo -e "  ${DIM}▸  $1${NC}"
}

# ---------------------------------------------------------------------------
# Trap handler — ferma spinner su INT/TERM
# ---------------------------------------------------------------------------
display_trap_cleanup() {
    if [[ -n "$_SPINNER_PID" ]] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null || true
    fi
    if [[ -n "$_SPINNER_TMPDIR" ]]; then
        rm -rf "$_SPINNER_TMPDIR"
    fi
}
