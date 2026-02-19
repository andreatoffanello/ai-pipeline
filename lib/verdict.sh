#!/usr/bin/env bash
# lib/verdict.sh — Gate logic via .verdict files

# PIPELINE_DIR must be set by pipeline.sh
VERDICT_DIR="${PIPELINE_DIR}/verdicts"

# ---------------------------------------------------------------------------
# verdict_file_path <feature> <step_name>
# ---------------------------------------------------------------------------
verdict_file_path() {
    local feature="$1"
    local step="$2"
    echo "${VERDICT_DIR}/${feature}-${step}.verdict"
}

# ---------------------------------------------------------------------------
# verdict_read <feature> <step_name>
# Returns "APPROVED", "REJECTED", or "MISSING".
# Strips all whitespace — comparison is exact string match only.
# ---------------------------------------------------------------------------
verdict_read() {
    local feature="$1"
    local step="$2"
    local vfile
    vfile=$(verdict_file_path "$feature" "$step")

    if [[ ! -f "$vfile" ]]; then
        echo "MISSING"
        return
    fi

    local content
    content=$(tr -d '[:space:]' < "$vfile")

    case "$content" in
        APPROVED) echo "APPROVED" ;;
        REJECTED) echo "REJECTED" ;;
        *)         echo "MISSING"  ;;  # malformato → fail-safe
    esac
}

# ---------------------------------------------------------------------------
# verdict_gate_instruction <feature> <step_name> <report_path>
# Istruzione gate da iniettare alla fine del prompt.
# ---------------------------------------------------------------------------
verdict_gate_instruction() {
    local feature="$1"
    local step="$2"
    local report_path="$3"
    local vfile
    vfile=$(verdict_file_path "$feature" "$step")

    cat <<GATE

---
GATE ISTRUZIONI (non modificare questo blocco):
Al termine scrivi il tuo report in: ${report_path}
Poi scrivi UNA SOLA PAROLA in: ${vfile}

  Se approvi → scrivi esattamente: APPROVED
  Se rifiuti → scrivi esattamente: REJECTED

Nessun altro contenuto nel file .verdict.
Il file .verdict deve contenere solo la parola, senza spazi, senza newline extra.
GATE
}

# ---------------------------------------------------------------------------
# verdict_clear <feature> <step_name>
# Rimuove il file .verdict (usato prima di un retry).
# ---------------------------------------------------------------------------
verdict_clear() {
    local feature="$1"
    local step="$2"
    local vfile
    vfile=$(verdict_file_path "$feature" "$step")
    rm -f "$vfile"
}

# ---------------------------------------------------------------------------
# verdict_ensure_dir
# Crea la directory verdicts/ se non esiste.
# ---------------------------------------------------------------------------
verdict_ensure_dir() {
    mkdir -p "$VERDICT_DIR"
}
