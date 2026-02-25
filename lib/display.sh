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
# File in $_SPINNER_TMPDIR:
#   action  — "tool\narg" ultimo tool non-playwright
#   pw_url  — URL corrente playwright (aggiornato da browser_navigate)
#   pw_act  — "icon label" ultima azione playwright
#   count   — una riga per ogni azione (wc -l = totale azioni)
# ---------------------------------------------------------------------------
_SPINNER_PID=""
_SPINNER_TMPDIR=""
_SPINNER_LINES_FILE=""
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

    # Timer live a 3 righe su /dev/tty
    # Riga 1: spinner + elapsed + ultimo tool regolare
    # Riga 2: stato playwright (URL + ultima azione browser)
    # Riga 3: pipeline overview (step completati/in corso/pending)
    local start_epoch="$_SPINNER_START_EPOCH"
    local tmpdir="$_SPINNER_TMPDIR"
    local state_file="${PIPELINE_STATE_FILE:-}"
    (
        set +euo pipefail 2>/dev/null || true
        local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local spin_len=10
        local i=0

        # Riserva 3 righe
        printf '\n\n\n' > /dev/tty

        while true; do
            local now elapsed mins secs
            now=$(date +%s)
            elapsed=$(( now - start_epoch ))
            mins=$(( elapsed / 60 ))
            secs=$(( elapsed % 60 ))
            local c="${spin:$(( i % spin_len )):1}"

            # Leggi stato corrente dai file
            local act_tool="" act_arg="" pw_url="" pw_act=""
            if [[ -f "$tmpdir/action" ]]; then
                act_tool=$(head -1 "$tmpdir/action" 2>/dev/null || true)
                act_arg=$(tail -1 "$tmpdir/action" 2>/dev/null || true)
            fi
            [[ -f "$tmpdir/pw_url" ]] && pw_url=$(cat "$tmpdir/pw_url" 2>/dev/null || true)
            [[ -f "$tmpdir/pw_act" ]] && pw_act=$(cat "$tmpdir/pw_act" 2>/dev/null || true)

            # Colore per tool regolare
            local acol='\033[2m'
            case "$act_tool" in
                Read)      acol='\033[0;36m' ;;
                Write)     acol='\033[0;32m' ;;
                Edit)      acol='\033[1;33m' ;;
                Bash)      acol='\033[0;35m' ;;
                Glob|Grep) acol='\033[0;34m' ;;
            esac

            # Abbrevia tool MCP non-playwright
            local display_tool="$act_tool"
            if [[ "$act_tool" == mcp__*__* ]]; then
                display_tool="${act_tool##*__}"
            fi

            # Torna su 3 righe e sovrascrive
            printf '\033[3A' > /dev/tty

            # Riga 1: spinner + tempo + ultimo tool
            if [[ -n "$act_tool" ]]; then
                printf '\r\033[2K  \033[2m%s  %dm%02ds\033[0m  '"$acol"'%-10s\033[0m  \033[2m%s\033[0m\n' \
                    "$c" "$mins" "$secs" "$display_tool" "${act_arg:0:50}" > /dev/tty
            else
                printf '\r\033[2K  \033[2m%s  %dm%02ds\033[0m\n' \
                    "$c" "$mins" "$secs" > /dev/tty
            fi

            # Riga 2: playwright state (vuota se nessuna attività PW)
            if [[ -n "$pw_url" ]]; then
                local short_url="$pw_url"
                short_url="${short_url#http://}"
                short_url="${short_url#https://}"
                printf '\r\033[2K  \033[2m🌐 %-32s › %s\033[0m\n' \
                    "${short_url:0:32}" "${pw_act:-…}" > /dev/tty
            else
                printf '\r\033[2K\n' > /dev/tty
            fi

            # Riga 3: pipeline overview (ogni ~2s per ridurre I/O)
            if [[ $(( i % 13 )) -eq 0 ]] && [[ -n "$state_file" ]] && [[ -f "$state_file" ]]; then
                local overview
                overview=$(python3 - "$state_file" 2>/dev/null <<'PYEOF' || true
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    steps = d.get("steps", {})
    parts = []
    for name, info in steps.items():
        s = info.get("status", "pending")
        if s == "completed":
            parts.append(f"\033[0;32m✓{name}\033[0m")
        elif s == "in_progress":
            parts.append(f"\033[0;36m⠸{name}\033[0m")
        elif s == "failed":
            parts.append(f"\033[0;31m✗{name}\033[0m")
        else:
            parts.append(f"\033[2m○{name}\033[0m")
    print(" ".join(parts))
except:
    pass
PYEOF
)
                if [[ -n "$overview" ]]; then
                    printf '\r\033[2K  %b\n' "$overview" > /dev/tty
                else
                    printf '\r\033[2K\n' > /dev/tty
                fi
            else
                # Mantieni riga 3 ma non aggiornare
                printf '\r\033[2K\n' > /dev/tty 2>/dev/null || printf '\n' > /dev/tty
            fi

            i=$(( i + 1 ))
            sleep 0.15
        done
    ) &
    _SPINNER_PID=$!
}

# ---------------------------------------------------------------------------
# display_box_add_action <tool_type> <argument>
# Scrive solo su file (IPC con spinner subshell). Nessun output diretto su tty.
# ---------------------------------------------------------------------------
display_box_add_action() {
    local tool="$1"
    local arg="$2"

    # Log azioni (per debug/audit)
    if [[ -n "$_SPINNER_LINES_FILE" ]]; then
        printf "%-24s %s\n" "$tool" "$arg" >> "$_SPINNER_LINES_FILE"
    fi

    [[ -z "$_SPINNER_TMPDIR" ]] && return 0

    # Contatore azioni (una riga per azione — wc -l in display_box_stop)
    printf '1\n' >> "$_SPINNER_TMPDIR/count" 2>/dev/null || true

    # Contatore per tipo di tool (per summary in display_box_stop)
    local tool_type="$tool"
    # Normalizza MCP tool names
    if [[ "$tool" == *"playwright"* ]]; then
        tool_type="Playwright"
    elif [[ "$tool" == mcp__*__* ]]; then
        tool_type="${tool##*__}"
    fi
    printf '%s\n' "$tool_type" >> "$_SPINNER_TMPDIR/tool_types" 2>/dev/null || true

    if [[ "$tool" == *"playwright"*"browser_"* ]]; then
        # Tool playwright (pipeline mcp__playwright__* o plugin mcp__plugin_playwright_*) — aggiorna riga 2
        local bname="${tool##*browser_}"

        local icon label
        case "$bname" in
            navigate)        icon="🔗"; label="navigate ${arg}"
                             # Aggiorna URL corrente
                             [[ -n "$arg" ]] && printf '%s' "$arg" > "$_SPINNER_TMPDIR/pw_url" 2>/dev/null || true
                             ;;
            snapshot)        icon="👁 "; label="snapshot" ;;
            click)           icon="🖱 "; label="click ${arg}" ;;
            type)            icon="⌨ "; label="type ${arg}" ;;
            fill_form)       icon="📝"; label="fill form" ;;
            take_screenshot) icon="📸"; label="screenshot" ;;
            hover)           icon="🔍"; label="hover ${arg}" ;;
            wait_for)        icon="⏳"; label="wait ${arg}" ;;
            press_key)       icon="⌨ "; label="key ${arg}" ;;
            scroll)          icon="📜"; label="scroll" ;;
            run_code)        icon="▶ "; label="run ${arg}" ;;
            evaluate)        icon="⚡"; label="eval ${arg}" ;;
            *)               icon="🌐"; label="${bname} ${arg}" ;;
        esac

        printf '%s %s' "$icon" "${label:0:45}" > "$_SPINNER_TMPDIR/pw_act" 2>/dev/null || true
    else
        # Tool regolare — aggiorna riga 1
        printf '%s\n%s' "$tool" "${arg:0:50}" > "$_SPINNER_TMPDIR/action" 2>/dev/null || true
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

        # Conta azioni dal file (robusto anche da subshell pipe)
        local action_count=0
        if [[ -n "$_SPINNER_TMPDIR" && -f "$_SPINNER_TMPDIR/count" ]]; then
            action_count=$(wc -l < "$_SPINNER_TMPDIR/count" | tr -d ' ' 2>/dev/null || echo 0)
        fi

        # Summary per tipo di tool
        local tool_summary=""
        if [[ -n "$_SPINNER_TMPDIR" && -f "$_SPINNER_TMPDIR/tool_types" ]]; then
            tool_summary=$(sort "$_SPINNER_TMPDIR/tool_types" 2>/dev/null | uniq -c | sort -rn | \
                awk '{printf "%s:%d ", $2, $1}' | sed 's/ $//' 2>/dev/null || true)
        fi

        # Sovrascrive le 3 righe del spinner con il messaggio finale
        local summary_text="${action_count} azioni"
        [[ -n "$tool_summary" ]] && summary_text="${action_count} azioni: ${tool_summary}"
        printf '\033[3A\r\033[2K  %b✓%b  Step %b%s%b completato in %b%dm%02ds%b  %b(%s)%b\n\r\033[2K\n\r\033[2K\n' \
            "$GREEN" "$NC" \
            "$BOLD" "$_SPINNER_STEP_NAME" "$NC" \
            "$GREEN" "$mins" "$secs" "$NC" \
            "$DIM" "$summary_text" "$NC" > /dev/tty
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

        printf "  ${DIM}|  %s${NC}  %-38s  %b\n" \
            "$mtime" "$display_path" "$stat_str"
    done

    printf "  ${DIM}+----------------------------------------------------------+${NC}\n"
    printf "\n"
}

# ---------------------------------------------------------------------------
# display_screenshots_saved <dir>
# Mostra quanti screenshot sono stati salvati nella directory.
# ---------------------------------------------------------------------------
display_screenshots_saved() {
    local dir="$1"
    [[ -z "$dir" ]] && return 0
    [[ ! -d "$dir" ]] && return 0

    local count=0
    local files
    files=$(find "$dir" -maxdepth 1 \( -name "*.png" -o -name "*.jpeg" -o -name "*.jpg" -o -name "*.webp" \) 2>/dev/null || true)
    if [[ -n "$files" ]]; then
        count=$(echo "$files" | wc -l | tr -d ' ')
    fi

    if [[ $count -gt 0 ]]; then
        # Mostra path relativo al progetto (non a pipeline dir)
        local project_dir
        project_dir="$(dirname "$PIPELINE_DIR")"
        local rel_dir="${dir#$project_dir/}"
        printf "  ${DIM}📸 %d screenshot → %s${NC}\n" "$count" "$rel_dir"
    fi
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
        content = f.read()
        lines = content.splitlines()
except:
    sys.exit(0)

output = []

# 1. Cerca REV-XXX e mostra titolo + prima riga del problema
rev_pattern = re.compile(r'^#{1,4}\s+(REV-\d+[^:]*:.*)', re.I)
prob_pattern = re.compile(r'^\*\*Problema[:\*]+\*?\*?\s*(.*)', re.I)

i = 0
rev_count = 0
while i < len(lines):
    m = rev_pattern.match(lines[i].rstrip())
    if m:
        rev_count += 1
        title = m.group(1).strip()
        # Cerca **Problema:** nella prossima riga
        prob = ''
        for j in range(i+1, min(i+5, len(lines))):
            pm = prob_pattern.match(lines[j].rstrip())
            if pm:
                prob = pm.group(1).strip()
                break
        output.append(f'REV: {title}')
        if prob:
            output.append(f'     {prob[:70]}')
    i += 1

# 2. Se nessun REV trovato, mostra valutazione generale (prime 8 righe non vuote)
if not output:
    count = 0
    for line in lines:
        stripped = line.rstrip()
        if stripped and not stripped.startswith('---'):
            stripped = re.sub(r'^#{1,4}\s+', '', stripped)
            stripped = stripped.replace('**', '')
            output.append(stripped)
            count += 1
            if count >= 8:
                break

if rev_count > 0:
    output.insert(0, f'{rev_count} revisioni aperte:')

print('\n'.join(output[:20]))
PYEOF
)

    [[ -z "$summary" ]] && return 0

    printf "\n"
    printf "  ${RED}+----------------------------------------------------------+${NC}\n"
    printf "  ${RED}|  Revisioni aperte                                        |${NC}\n"
    printf "  ${RED}+----------------------------------------------------------+${NC}\n"
    while IFS= read -r line; do
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
        _notify "✅ Gate Approvato" "approvato in ${elapsed}" "${PIPELINE_FEATURE:-} › ${step_name}"
    else
        printf "\n  ${RED}x${NC}  Verdetto: ${BOLD}${RED}%s -- RESPINTO${NC}  ${DIM}%s  %s${NC}\n" \
            "$step_name" "$elapsed" "$info"
        _notify "❌ Gate Respinto" "${info}" "${PIPELINE_FEATURE:-} › ${step_name}"
    fi
}

# ---------------------------------------------------------------------------
# display_retry_banner <step> <retry_num> <max_retries> [reason]
# Mostra un banner compatto tra i retry.
# ---------------------------------------------------------------------------
display_retry_banner() {
    local step="$1"
    local retry_num="$2"
    local max_retries="$3"
    local reason="${4:-}"

    local reason_str=""
    [[ -n "$reason" ]] && reason_str=" → ${reason}"

    printf "\n"
    printf "  ${YELLOW}+----------------------------------------------------------+${NC}\n"
    printf "  ${YELLOW}|${NC}  ${BOLD}↺ Retry %s/%s${NC}  ${DIM}%s%s${NC}" \
        "$retry_num" "$max_retries" "$step" "$reason_str"
    # Pad to box width
    local content_len=$(( 12 + ${#retry_num} + ${#max_retries} + ${#step} + ${#reason_str} ))
    local padding=$(( 56 - content_len ))
    [[ $padding -gt 0 ]] && printf "%*s" "$padding" ""
    printf "${YELLOW}|${NC}\n"
    printf "  ${YELLOW}+----------------------------------------------------------+${NC}\n"
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

    # Mostra costo stimato se disponibile
    local total_cost
    total_cost=$(state_get_total_cost 2>/dev/null || true)
    if [[ -n "$total_cost" && "$total_cost" != "0" ]]; then
        printf "  ${GREEN}|${NC}  ${DIM}Costo stimato: ~\$%-40s${NC}${GREEN}|${NC}\n" "$total_cost"
    fi

    printf "  ${GREEN}|${NC}%*s${GREEN}|${NC}\n" 58 ""
    for f in "${files[@]}"; do
        printf "  ${GREEN}|${NC}  ${DIM}%-56s${NC}${GREEN}|${NC}\n" "$f"
    done
    printf "  ${BOLD}${GREEN}+----------------------------------------------------------+${NC}\n"
    printf "\n"
    _notify "🎉 Pipeline Completata" "completata in ${elapsed}" "${feature}"
}

# ---------------------------------------------------------------------------
# _notify <title> <message> [subtitle]
# Notifica macOS tramite osascript. No-op su sistemi non-macOS.
# ---------------------------------------------------------------------------
_notify() {
    local title="$1"
    local msg="$2"
    local subtitle="${3:-}"

    # macOS
    if [[ "$(uname)" == "Darwin" ]] && command -v osascript &>/dev/null; then
        if [[ -n "$subtitle" ]]; then
            osascript -e "display notification \"${msg}\" with title \"${title}\" subtitle \"${subtitle}\"" &>/dev/null || true
        else
            osascript -e "display notification \"${msg}\" with title \"${title}\"" &>/dev/null || true
        fi
    fi

    # Linux
    if command -v notify-send &>/dev/null; then
        notify-send "${title}" "${subtitle:+$subtitle — }${msg}" 2>/dev/null || true
    fi

    # Webhook opzionale
    if [[ -n "${PIPELINE_CONFIG_FILE:-}" ]] && command -v curl &>/dev/null; then
        local webhook_url
        webhook_url=$(config_get_default "notifications.webhook_url" "" 2>/dev/null || true)
        if [[ -n "$webhook_url" ]]; then
            curl -s -X POST "$webhook_url" \
                -H "Content-Type: application/json" \
                -d "{\"title\":\"${title}\",\"message\":\"${msg}\",\"subtitle\":\"${subtitle}\"}" \
                --max-time 5 &>/dev/null || true
        fi
    fi
}

# ---------------------------------------------------------------------------
# display_error / display_warn / display_info
# ---------------------------------------------------------------------------
display_error() {
    printf "\n  ${RED}ERR  %s${NC}\n" "$1" >&2
    _notify "⛔ Pipeline Error" "$1" "${PIPELINE_FEATURE:-pipeline}"
}

display_warn() {
    printf "  ${YELLOW}WARN  %s${NC}\n" "$1"
}

display_info() {
    printf "  ${DIM}>>  %s${NC}\n" "$1"
}

# ===========================================================================
# Batch display functions
# ===========================================================================

# ---------------------------------------------------------------------------
# display_batch_header <total> <feature1> [feature2 ...]
# ---------------------------------------------------------------------------
display_batch_header() {
    local total="$1"
    shift
    local features=("$@")
    local started
    started=$(date "+%Y-%m-%d %H:%M:%S")

    printf "\n"
    printf "  ${BOLD}${MAGENTA}+----------------------------------------------------------+${NC}\n"
    printf "  ${MAGENTA}|${NC}  ${BOLD}BATCH MODE${NC}  ${DIM}%d feature in coda${NC}%*s${MAGENTA}|${NC}\n" \
        "$total" $(( 32 - ${#total} )) ""
    printf "  ${MAGENTA}|${NC}  ${DIM}Avviato: %-49s${NC}${MAGENTA}|${NC}\n" "$started"
    printf "  ${MAGENTA}|${NC}%*s${MAGENTA}|${NC}\n" 58 ""
    local idx=0
    for f in "${features[@]}"; do
        idx=$(( idx + 1 ))
        printf "  ${MAGENTA}|${NC}  ${DIM}%2d.${NC} %-54s${MAGENTA}|${NC}\n" "$idx" "$f"
    done
    printf "  ${BOLD}${MAGENTA}+----------------------------------------------------------+${NC}\n"
    printf "\n"
}

# ---------------------------------------------------------------------------
# display_batch_feature_start <feature> <idx> <total>
# ---------------------------------------------------------------------------
display_batch_feature_start() {
    local feature="$1"
    local idx="$2"
    local total="$3"

    printf "\n"
    printf "  ${BOLD}${MAGENTA}===========================================================${NC}\n"
    printf "  ${MAGENTA}>>${NC}  ${BOLD}Feature %d/%d: %s${NC}\n" "$idx" "$total" "$feature"
    printf "  ${BOLD}${MAGENTA}===========================================================${NC}\n"
}

# ---------------------------------------------------------------------------
# display_batch_feature_result <feature> <status> <elapsed> <idx> <total>
# ---------------------------------------------------------------------------
display_batch_feature_result() {
    local feature="$1"
    local status="$2"
    local elapsed="$3"
    local idx="$4"
    local total="$5"

    if [[ "$status" == "completed" ]]; then
        printf "\n  ${GREEN}${BOLD}v${NC}  Feature ${BOLD}%s${NC} completata  ${DIM}%s${NC}  ${DIM}(%d/%d)${NC}\n" \
            "$feature" "$elapsed" "$idx" "$total"
    else
        printf "\n  ${RED}${BOLD}x${NC}  Feature ${BOLD}%s${NC} fallita  ${DIM}%s${NC}  ${DIM}(%d/%d)${NC}\n" \
            "$feature" "$elapsed" "$idx" "$total"
    fi
}

# ---------------------------------------------------------------------------
# display_batch_summary <total> <completed> <failed> <skipped> <elapsed> [detail...]
# ---------------------------------------------------------------------------
display_batch_summary() {
    local total="$1"
    local completed="$2"
    local failed="$3"
    local skipped="$4"
    local elapsed="$5"
    shift 5
    local details=("$@")

    local status_color="$GREEN"
    local status_text="COMPLETATO"
    if [[ $failed -gt 0 ]]; then
        status_color="$RED"
        status_text="CON ERRORI"
    elif [[ $skipped -gt 0 ]]; then
        status_color="$YELLOW"
        status_text="PARZIALE"
    fi

    printf "\n"
    printf "  ${BOLD}${status_color}+----------------------------------------------------------+${NC}\n"
    printf "  ${status_color}|${NC}  ${BOLD}Batch %s${NC}  ${DIM}%s${NC}%*s${status_color}|${NC}\n" \
        "$status_text" "$elapsed" $(( 36 - ${#status_text} - ${#elapsed} )) ""
    printf "  ${status_color}|${NC}%*s${status_color}|${NC}\n" 58 ""
    printf "  ${status_color}|${NC}  Totale: ${BOLD}%d${NC}" "$total"
    printf "  ${GREEN}OK: %d${NC}" "$completed"
    printf "  ${RED}Err: %d${NC}" "$failed"
    printf "  ${DIM}Skip: %d${NC}" "$skipped"
    local stats_len=$(( 16 + ${#total} + ${#completed} + ${#failed} + ${#skipped} ))
    printf "%*s${status_color}|${NC}\n" $(( 58 - stats_len )) ""

    if [[ ${#details[@]} -gt 0 ]]; then
        printf "  ${status_color}|${NC}%*s${status_color}|${NC}\n" 58 ""
        for d in "${details[@]}"; do
            printf "  ${status_color}|${NC}  %-56s${status_color}|${NC}\n" "${d:0:56}"
        done
    fi

    printf "  ${BOLD}${status_color}+----------------------------------------------------------+${NC}\n"
    printf "\n"

    if [[ $failed -gt 0 ]]; then
        _notify "Batch Terminato" "${completed}/${total} completate, ${failed} fallite" "batch"
    else
        _notify "Batch Completato" "Tutte ${total} feature completate in ${elapsed}" "batch"
    fi
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
