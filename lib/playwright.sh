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
# playwright_require_server
# Chiamata UNA VOLTA prima di avviare la pipeline, se almeno uno step ha
# playwright: true. Blocca con exit 1 se il server non è attivo.
# ---------------------------------------------------------------------------
playwright_require_server() {
    local port
    port=$(playwright_get_port)

    if playwright_server_is_up "$port"; then
        display_info "Dev server attivo su :${port} — ok"
        return 0
    fi

    printf "\n"
    printf "  ${RED}ERR  Dev server NON attivo su :${port}${NC}\n\n"
    printf "  Gli step con playwright: true richiedono il server attivo.\n"
    printf "  Avvia il dev server in un terminale separato, poi rilancia:\n\n"
    printf "  ${BOLD}    bash pipeline.sh ${PIPELINE_FEATURE:-<feature>}${NC}\n\n"
    exit 1
}

# ---------------------------------------------------------------------------
# playwright_inject_prompt_instruction <prompt_file> <port>
# Prepende al prompt l'istruzione obbligatoria di verifica visiva.
# ---------------------------------------------------------------------------
playwright_inject_prompt_instruction() {
    local prompt_file="$1"
    local port="$2"

    local tmp
    tmp=$(mktemp)

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

    cat "$prompt_file" >> "$tmp"
    mv "$tmp" "$prompt_file"
}

# ---------------------------------------------------------------------------
# playwright_check_step <step_name> <feature> <prompt_file>
# Se lo step richiede playwright, inietta l'istruzione nel prompt.
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

    playwright_inject_prompt_instruction "$prompt_file" "$port"
    display_info "${step}: verifica visiva Playwright iniettata nel prompt"
    return 0
}
