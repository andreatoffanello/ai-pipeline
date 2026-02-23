#!/usr/bin/env bash
# lib/playwright.sh — verifica dev server + iniezione istruzione nei prompt
# PIPELINE_DIR, PIPELINE_FEATURE devono essere settati dall'entry point

# ---------------------------------------------------------------------------
# playwright_get_port
# ---------------------------------------------------------------------------
playwright_get_port() {
    config_get_default "project.dev_port" "3000"
}

# ---------------------------------------------------------------------------
# playwright_server_is_up <port>
# Exit 0 se il server risponde, exit 1 altrimenti
# ---------------------------------------------------------------------------
playwright_server_is_up() {
    local port="$1"
    if command -v curl &>/dev/null; then
        local code
        code=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "http://localhost:${port}" 2>/dev/null || echo "000")
        [[ "$code" != "000" ]] && return 0
    elif command -v nc &>/dev/null; then
        nc -z localhost "$port" 2>/dev/null && return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# playwright_start_server
# Avvia il dev server in background usando project.dev_start dal config.
# Attende fino a project.dev_start_timeout secondi che risponda.
# Exit 0 se il server è up, exit 1 se timeout o nessun comando configurato.
# ---------------------------------------------------------------------------
playwright_start_server() {
    local port
    port=$(playwright_get_port)

    local cmd
    cmd=$(config_get_default "project.dev_start" "")

    if [[ -z "$cmd" ]]; then
        return 1
    fi

    local timeout
    timeout=$(config_get_default "project.dev_start_timeout" "30")

    # Avvia dalla directory del progetto (parent di ai-pipeline)
    local project_dir
    project_dir="$(dirname "$PIPELINE_DIR")"

    mkdir -p "${PIPELINE_DIR}/logs"
    local logfile="${PIPELINE_DIR}/logs/dev-server.log"

    display_info "Dev server non attivo — avvio automatico: ${cmd}"
    (cd "$project_dir" && eval "$cmd" >> "$logfile" 2>&1) &

    local i=0
    while [[ $i -lt $timeout ]]; do
        sleep 1
        i=$(( i + 1 ))
        if playwright_server_is_up "$port"; then
            display_info "Dev server attivo su :${port} dopo ${i}s"
            return 0
        fi
        # Feedback ogni 5 secondi
        if (( i % 5 == 0 )); then
            display_info "Attesa dev server... ${i}/${timeout}s"
        fi
    done

    return 1
}

# ---------------------------------------------------------------------------
# playwright_require_server
# Chiamata UNA VOLTA prima di avviare la pipeline, se almeno uno step ha
# playwright: true. Tenta auto-start se configurato, blocca con exit 1
# se il server non risponde.
# ---------------------------------------------------------------------------
playwright_require_server() {
    local port
    port=$(playwright_get_port)

    if playwright_server_is_up "$port"; then
        display_info "Dev server attivo su :${port} — ok"
        return 0
    fi

    # Tenta auto-start
    if playwright_start_server; then
        return 0
    fi

    printf "\n"
    printf "  ${RED}ERR  Dev server NON attivo su :${port}${NC}\n\n"
    printf "  Configura project.dev_start in pipeline.yaml per l'avvio automatico,\n"
    printf "  oppure avvia il dev server manualmente e rilancia:\n\n"
    printf "  ${BOLD}    bash pipeline.sh ${PIPELINE_FEATURE:-<feature>}${NC}\n\n"
    _notify "🛑 Dev Server Non Attivo" "Avvia il server e rilancia la pipeline" "${PIPELINE_FEATURE:-pipeline}"
    exit 1
}

# ---------------------------------------------------------------------------
# playwright_inject_prompt_instruction <prompt_file> <port> <has_bash>
# Prepende al prompt l'istruzione obbligatoria di verifica visiva.
# Se has_bash=true aggiunge anche la verifica curl, altrimenti solo MCP.
# ---------------------------------------------------------------------------
playwright_inject_prompt_instruction() {
    local prompt_file="$1"
    local port="$2"
    local has_bash="${3:-false}"

    local tmp
    tmp=$(mktemp)

    if [[ "$has_bash" == "true" ]]; then
        cat > "$tmp" << GATE
# VERIFICA VISIVA OBBLIGATORIA — ESEGUI PRIMA DI QUALSIASI ALTRA COSA

Il dev server è attivo su http://localhost:${port}.

**Devi obbligatoriamente:**
1. Usare il tool Bash per verificare che il server risponda:
   \`\`\`
   curl -s --max-time 5 -o /dev/null -w "%{http_code}" http://localhost:${port}
   \`\`\`
2. Usare il MCP Playwright (browser_navigate + browser_snapshot)
   per navigare le pagine rilevanti e osservare il risultato visivo reale nel browser.
3. Basare il tuo output e le tue conclusioni ESCLUSIVAMENTE su ciò che hai visto nel browser,
   non solo sui file sorgente.

**Non è accettabile:**
- Fare solo code review statica dei file sorgente
- Saltare la verifica nel browser
- Scrivere "da verificare" o "non verificabile" per elementi visivi

---

GATE
    else
        cat > "$tmp" << GATE
# VERIFICA VISIVA OBBLIGATORIA — ESEGUI PRIMA DI QUALSIASI ALTRA COSA

Il dev server è attivo su http://localhost:${port} (verificato dalla pipeline).

**Devi obbligatoriamente:**
1. Usare il MCP Playwright (browser_navigate + browser_snapshot)
   per navigare le pagine rilevanti e osservare il risultato visivo reale nel browser.
2. Basare il tuo output e le tue conclusioni ESCLUSIVAMENTE su ciò che hai visto nel browser,
   non solo sui file sorgente.

**Non è accettabile:**
- Fare solo code review statica dei file sorgente
- Saltare la verifica nel browser
- Scrivere "da verificare" o "non verificabile" per elementi visivi
- Dichiarare che il server non è attivo: la pipeline ha già verificato che risponde su :${port}

---

GATE
    fi

    cat "$prompt_file" >> "$tmp"
    mv "$tmp" "$prompt_file"
}

# ---------------------------------------------------------------------------
# playwright_check_step <step_name> <feature> <prompt_file>
# Se lo step richiede playwright, verifica che il server sia ancora up
# e inietta l'istruzione nel prompt. Blocca con exit 1 se server giù.
# ---------------------------------------------------------------------------
playwright_check_step() {
    local step="$1"
    local feature="$2"
    local prompt_file="$3"

    local needs_playwright
    needs_playwright=$(config_step_needs_playwright "$step")

    if [[ "$needs_playwright" != "true" ]]; then
        return 0
    fi

    local port
    port=$(playwright_get_port)

    # Reverifica che il server sia ancora attivo prima di ogni step playwright
    if ! playwright_server_is_up "$port"; then
        display_warn "Dev server non risponde su :${port} — tentativo di riavvio..."
        if ! playwright_start_server; then
            printf "\n"
            printf "  ${RED}ERR  Dev server NON attivo su :${port} (step: ${step})${NC}\n\n"
            printf "  Il server si è spento durante la pipeline e il riavvio automatico è fallito.\n"
            printf "  Riavvia il dev server, poi riprendi con:\n\n"
            printf "  ${BOLD}    bash pipeline.sh ${PIPELINE_FEATURE:-<feature>} --from ${step}${NC}\n\n"
            _notify "🛑 Dev Server Spento" "Riavvio fallito — riprendi da: ${step}" "${PIPELINE_FEATURE:-pipeline} › ${step}"
            exit 1
        fi
    fi

    local step_tools
    step_tools=$(config_step_allowed_tools "$step")
    local has_bash="false"
    [[ "$step_tools" == *"Bash"* ]] && has_bash="true"

    playwright_inject_prompt_instruction "$prompt_file" "$port" "$has_bash"
    display_info "${step}: verifica visiva Playwright iniettata nel prompt (Bash: ${has_bash})"
    return 0
}
