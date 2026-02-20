#!/usr/bin/env bash
# lib/display.sh — Terminal UI: box ASCII, spinner, semi-log effimeri

# Colori ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# _tool_color <tool_type>  — colore ANSI per tipo di tool
# ---------------------------------------------------------------------------
_tool_color() {
    case "$1" in
        Read)      printf '%b' "${CYAN}" ;;
        Write)     printf '%b' "${GREEN}" ;;
        Edit)      printf '%b' "${YELLOW}" ;;
        Bash)      printf '%b' "${MAGENTA}" ;;
        Glob|Grep) printf '%b' "${BLUE}" ;;
        *)         printf '%b' "${DIM}" ;;
    esac
}

# ---------------------------------------------------------------------------
# _display_progress <current> <total>
# ---------------------------------------------------------------------------
_display_progress() {
    local cur="$1" tot="$2"
    local width=20
    local filled=$(( cur * width / tot ))
    local bar="" i
    for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
    for (( i=filled; i<width; i++ )); do bar="${bar}░"; done
    printf "${GREEN}[${BOLD}%s${NC}${GREEN}]${NC} ${BOLD}%d/%d${NC}" "$bar" "$cur" "$tot"
}

# ---------------------------------------------------------------------------
# _agent_emoji <step_name>  — emoji per tipo di agente
# ---------------------------------------------------------------------------
_agent_emoji() {
    case "$1" in
        pm)        printf '🎯' ;;
        dr-spec)   printf '📐' ;;
        dev*)      printf '⚙️ ' ;;
        dr-impl)   printf '🔍' ;;
        qa*)       printf '✅' ;;
        *)         printf '▸ ' ;;
    esac
}

# ---------------------------------------------------------------------------
# display_header <pipeline_name> <feature> <steps_string>
# ---------------------------------------------------------------------------
display_header() {
    local name="$1"
    local feature="$2"
    local steps_str="$3"
    local started
    started=$(date "+%Y-%m-%d %H:%M:%S")

    printf "\n"
    printf "  ${BOLD}${CYAN}+----------------------------------------------------------+${NC}\n"
    printf "  ${CYAN}|${NC}  ${BOLD}%-56s${NC}${CYAN}|${NC}\n" "${name} pipeline"
    printf "  ${CYAN}|${NC}  Feature: ${BOLD}%-50s${CYAN}|${NC}\n" "$feature"
    printf "  ${CYAN}|${NC}  Steps:   ${DIM}%-50s${NC}${CYAN}|${NC}\n" "$steps_str"
    printf "  ${CYAN}|${NC}  Started: ${DIM}%-50s${NC}${CYAN}|${NC}\n" "$started"
    printf "  ${BOLD}${CYAN}+----------------------------------------------------------+${NC}\n"
    printf "\n"
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
        APPROVED|completato) icon="v"; color="$GREEN" ;;
        REJECTED)            icon="x"; color="$RED" ;;
        *)                   icon="v"; color="$GREEN" ;;
    esac

    printf "  ${color}${BOLD}%s${NC}  Step ${BOLD}%s${NC} completato in ${color}%s${NC}  ${DIM}%s${NC}\n" \
        "$icon" "$name" "$elapsed" "$retry_info"
}

# ---------------------------------------------------------------------------
# display_step_waiting <name>
# ---------------------------------------------------------------------------
display_step_waiting() {
    printf "  ${DIM}o  %s${NC}\n" "$1"
}

# ---------------------------------------------------------------------------
# Stato interno spinner
# ---------------------------------------------------------------------------
_SPINNER_PID=""
_SPINNER_TMPDIR=""
_SPINNER_LINES_FILE=""
_SPINNER_ACTION_COUNT=0
_SPINNER_START_EPOCH=0
_SPINNER_STEP_NAME=""

# ---------------------------------------------------------------------------
# display_box_start <step_name> <model> [step_num] [step_total] [tools] [output]
# ---------------------------------------------------------------------------
display_box_start() {
    local step_name="$1"
    local model="$2"
    local step_num="${3:-}"
    local step_total="${4:-}"
    local tools="${5:-}"
    local output="${6:-}"

    _SPINNER_STEP_NAME="$step_name"
    _SPINNER_TMPDIR=$(mktemp -d)
    _SPINNER_LINES_FILE="$_SPINNER_TMPDIR/actions"
    _SPINNER_ACTION_COUNT=0
    _SPINNER_START_EPOCH=$(date +%s)
    _SPINNER_PID=""

    local started_at
    started_at=$(date "+%H:%M:%S")

    # Progress bar
    if [[ -n "$step_num" && -n "$step_total" ]]; then
        printf "\n  Progress: "
        _display_progress "$step_num" "$step_total"
        printf "\n"
    fi

    # Box step
    local emoji
    emoji=$(_agent_emoji "$step_name")
    printf "\n"
    printf "  ${BOLD}${CYAN}+----------------------------------------------------------+${NC}\n"
    if [[ -n "$step_num" ]]; then
        printf "  ${CYAN}|${NC}  %s ${BOLD}%-28s${NC}  ${DIM}(step %s/%s)${NC}%*s${CYAN}|${NC}\n" \
            "$emoji" "$step_name" "$step_num" "$step_total" \
            $(( 14 - ${#step_num} - ${#step_total} )) ""
    else
        printf "  ${CYAN}|${NC}  %s ${BOLD}%-53s${NC}${CYAN}|${NC}\n" "$emoji" "$step_name"
    fi
    printf "  ${CYAN}|${NC}  ${DIM}Feature: %-14s | Model: ${CYAN}%-10s${DIM} | %s${NC}%*s${CYAN}|${NC}\n" \
        "${PIPELINE_FEATURE:-?}" "$model" "$started_at" 2 ""
    [[ -n "$output" ]] && \
    printf "  ${CYAN}|${NC}  ${DIM}Output atteso: %-43s${NC}${CYAN}|${NC}\n" "$output"
    [[ -n "$tools" ]] && \
    printf "  ${CYAN}|${NC}  ${DIM}Tools: %-51s${NC}${CYAN}|${NC}\n" "$tools"
    printf "  ${BOLD}${CYAN}+----------------------------------------------------------+${NC}\n"
    printf "\n"

    # Timer live su /dev/tty con \r
    local start_epoch="$_SPINNER_START_EPOCH"
    (
        set +euo pipefail 2>/dev/null || true
        local spin='|/-\'
        local i=0
        while true; do
            local now elapsed mins secs
            now=$(date +%s)
            elapsed=$(( now - start_epoch ))
            mins=$(( elapsed / 60 ))
            secs=$(( elapsed % 60 ))
            local c="${spin:$(( i % 4 )):1}"
            printf "\r  ${DIM}%s  %dm%02ds${NC}  " "$c" "$mins" "$secs" > /dev/tty
            i=$(( i + 1 ))
            sleep 0.15
        done
    ) &
    _SPINNER_PID=$!
}

# ---------------------------------------------------------------------------
# display_box_add_action <tool_type> <argument>
# ---------------------------------------------------------------------------
display_box_add_action() {
    local tool="$1"
    local arg="$2"
    if [[ -n "$_SPINNER_LINES_FILE" ]]; then
        printf "%-8s %s\n" "$tool" "$arg" >> "$_SPINNER_LINES_FILE"
        _SPINNER_ACTION_COUNT=$(( _SPINNER_ACTION_COUNT + 1 ))
        local col
        col=$(_tool_color "$tool")
        printf "\r  %b%-8s${NC}  %s\n" "$col" "$tool" "$arg" > /dev/tty
    fi
}

# ---------------------------------------------------------------------------
# display_box_stop
# ---------------------------------------------------------------------------
display_box_stop() {
    if [[ -n "$_SPINNER_PID" ]] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null || true
    fi
    _SPINNER_PID=""

    if [[ "$_SPINNER_START_EPOCH" -gt 0 ]]; then
        local now elapsed mins secs
        now=$(date +%s)
        elapsed=$(( now - _SPINNER_START_EPOCH ))
        mins=$(( elapsed / 60 ))
        secs=$(( elapsed % 60 ))
        printf "\r  ${GREEN}v${NC}  Step ${BOLD}%s${NC} completato in ${GREEN}%dm%02ds${NC}  ${DIM}(%d azioni)${NC}\n" \
            "$_SPINNER_STEP_NAME" "$mins" "$secs" "$_SPINNER_ACTION_COUNT" > /dev/tty
    fi

    if [[ -n "$_SPINNER_TMPDIR" ]]; then
        rm -rf "$_SPINNER_TMPDIR"
        _SPINNER_TMPDIR=""
        _SPINNER_LINES_FILE=""
    fi
}

# ---------------------------------------------------------------------------
# display_file_changes <file1> [file2 ...]
# Mostra i file modificati/creati con diff stat git e timestamp.
# ---------------------------------------------------------------------------
display_file_changes() {
    local files=("$@")
    [[ ${#files[@]} -eq 0 ]] && return 0

    local has_files=false
    for f in "${files[@]}"; do
        [[ -f "$f" ]] && has_files=true && break
    done
    [[ "$has_files" == "false" ]] && return 0

    printf "\n"
    printf "  ${DIM}+----------------------------------------------------------+${NC}\n"
    printf "  ${DIM}|  File modificati                                         |${NC}\n"
    printf "  ${DIM}+----------------------------------------------------------+${NC}\n"

    for f in "${files[@]}"; do
        [[ ! -f "$f" ]] && continue

        local mtime
        mtime=$(date -r "$f" "+%H:%M:%S" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -c12-19)

        local added=0 removed=0
        if git -C "$(dirname "$f")" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
            local diff_stat
            diff_stat=$(git -C "$(dirname "$f")" diff --numstat HEAD -- "$f" 2>/dev/null || true)
            if [[ -n "$diff_stat" ]]; then
                added=$(echo "$diff_stat" | awk '{print $1}')
                removed=$(echo "$diff_stat" | awk '{print $2}')
            else
                added=$(wc -l < "$f" 2>/dev/null | tr -d ' ' || echo 0)
                removed=0
            fi
        else
            added=$(wc -l < "$f" 2>/dev/null | tr -d ' ' || echo 0)
            removed=0
        fi

        local relpath="${f/#$PWD\//}"
        local display_path="$relpath"
        [[ ${#display_path} -gt 38 ]] && display_path="...${relpath: -35}"

        local stat_str=""
        [[ $added -gt 0 ]]   && stat_str="${stat_str}${GREEN}+${added}${NC}"
        [[ $added -gt 0 && $removed -gt 0 ]] && stat_str="${stat_str} "
        [[ $removed -gt 0 ]] && stat_str="${stat_str}${RED}-${removed}${NC}"
        [[ -z "$stat_str" ]]  && stat_str="${DIM}~${NC}"

        printf "  ${DIM}|${NC}  %-38s  %b  ${DIM}%s${NC}\n" \
            "$display_path" "$stat_str" "$mtime"
    done

    printf "  ${DIM}+----------------------------------------------------------+${NC}\n"
    printf "\n"
}

# ---------------------------------------------------------------------------
# display_rejected_summary <report_file>
# Estrae e mostra il motivo di REJECTED dal file .md del report.
# ---------------------------------------------------------------------------
display_rejected_summary() {
    local report_file="$1"
    [[ ! -f "$report_file" ]] && return 0

    local summary
    summary=$(python3 - "$report_file" <<'PYEOF'
import sys, re

path = sys.argv[1]
try:
    with open(path) as f:
        lines = f.readlines()
except:
    sys.exit(0)

keywords = re.compile(r'(motiv|reject|problem|issue|critic|mancant|errat|non conform|da corregger|fallito|fail|bloccat)', re.I)
section_header = re.compile(r'^#{1,3}\s+')

output = []
in_section = False
for line in lines:
    stripped = line.rstrip()
    if not stripped:
        continue
    if section_header.match(stripped) and keywords.search(stripped):
        in_section = True
        output.append(stripped)
        continue
    if section_header.match(stripped) and in_section:
        break
    if in_section:
        output.append(stripped)
        if len(output) >= 12:
            break

if not output:
    count = 0
    for line in lines:
        stripped = line.rstrip()
        if stripped:
            output.append(stripped)
            count += 1
            if count >= 6:
                break

print('\n'.join(output[:12]))
PYEOF
)

    [[ -z "$summary" ]] && return 0

    printf "\n"
    printf "  ${RED}+----------------------------------------------------------+${NC}\n"
    printf "  ${RED}|  Motivo rejection                                        |${NC}\n"
    printf "  ${RED}+----------------------------------------------------------+${NC}\n"
    while IFS= read -r line; do
        line="${line#\#\#\# }"
        line="${line#\#\# }"
        line="${line#\# }"
        printf "  ${RED}|${NC}  ${DIM}%-56s${NC}${RED}|${NC}\n" "${line:0:56}"
    done <<< "$summary"
    printf "  ${RED}+----------------------------------------------------------+${NC}\n"
    printf "\n"
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
        printf "\n  ${GREEN}v${NC}  Verdetto: ${BOLD}${GREEN}%s -- APPROVATO${NC}  ${DIM}%s${NC}\n" \
            "$step_name" "$elapsed"
    else
        printf "\n  ${RED}x${NC}  Verdetto: ${BOLD}${RED}%s -- RESPINTO${NC}  ${DIM}%s  %s${NC}\n" \
            "$step_name" "$elapsed" "$info"
    fi
}

# ---------------------------------------------------------------------------
# display_success <feature> <elapsed> [output_file...]
# ---------------------------------------------------------------------------
display_success() {
    local feature="$1"
    local elapsed="$2"
    shift 2
    local files=("$@")

    printf "\n"
    printf "  ${BOLD}${GREEN}+----------------------------------------------------------+${NC}\n"
    printf "  ${GREEN}|${NC}  ${BOLD}${GREEN}Pipeline completata${NC}  ${DIM}%s${NC}%*s${GREEN}|${NC}\n" \
        "$elapsed" $(( 27 - ${#elapsed} )) ""
    printf "  ${GREEN}|${NC}  Feature: ${BOLD}%-50s${GREEN}|${NC}\n" "$feature"
    printf "  ${GREEN}|${NC}%*s${GREEN}|${NC}\n" 58 ""
    for f in "${files[@]}"; do
        printf "  ${GREEN}|${NC}  ${DIM}%-56s${NC}${GREEN}|${NC}\n" "$f"
    done
    printf "  ${BOLD}${GREEN}+----------------------------------------------------------+${NC}\n"
    printf "\n"
}

# ---------------------------------------------------------------------------
# display_error / display_warn / display_info
# ---------------------------------------------------------------------------
display_error() {
    printf "\n  ${RED}ERR  %s${NC}\n" "$1" >&2
}

display_warn() {
    printf "  ${YELLOW}WARN  %s${NC}\n" "$1"
}

display_info() {
    printf "  ${DIM}>>  %s${NC}\n" "$1"
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
