#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Preflight Check — Environment Verification
# ==============================================================================
#
# Verifica che l'ambiente sia pronto per eseguire la pipeline AI.
# Bash 3.2 compatible (macOS default).
#
# Exit codes:
#   0 — Tutti i check critici passati
#   1 — Uno o piu check critici falliti
#
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Contatori
CRITICAL_PASSED=0
CRITICAL_FAILED=0
WARNINGS=0

# ==============================================================================
# Utility
# ==============================================================================

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    CRITICAL_PASSED=$((CRITICAL_PASSED + 1))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    CRITICAL_FAILED=$((CRITICAL_FAILED + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

section_header() {
    echo -e "\n${BOLD}${CYAN}$1${NC}"
}

# Parse YAML helper (simple regex extraction for key: value pairs)
get_yaml_value() {
    local file="$1"
    local key="$2"
    local default="${3:-}"

    if [[ ! -f "$file" ]]; then
        echo "$default"
        return
    fi

    # Match "key: value" or "key: "value""
    local value
    value=$(grep "^[[:space:]]*${key}:" "$file" | head -n1 | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*"?([^"]*)"?.*/\1/' | sed 's/[[:space:]]*$//')

    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# ==============================================================================
# Checks
# ==============================================================================

check_pipeline_config() {
    section_header "Pipeline Configuration"

    local pipeline_file="${PROJECT_ROOT}/pipeline.yaml"

    if [[ ! -f "$pipeline_file" ]]; then
        check_fail "pipeline.yaml not found at project root"
        return
    fi

    check_pass "pipeline.yaml found"

    # Leggi configurazione
    PROJECT_NAME=$(get_yaml_value "$pipeline_file" "name" "")

    if [[ -z "$PROJECT_NAME" ]]; then
        check_warn "pipeline.yaml: project.name is empty"
    else
        echo -e "  ${CYAN}→${NC} Project: ${PROJECT_NAME}"
    fi
}

check_node() {
    section_header "Node.js"

    if ! command -v node &> /dev/null; then
        check_fail "Node.js not installed"
        return
    fi

    local node_version
    node_version=$(node --version)
    local node_major
    node_major=$(echo "$node_version" | sed -E 's/v([0-9]+).*/\1/')

    # Minimum Node.js version: 18 (Nuxt 4 requirement)
    if [[ "$node_major" -lt 18 ]]; then
        check_fail "Node.js ${node_version} is too old (need v18+)"
        return
    fi

    check_pass "Node.js ${node_version}"
}

check_package_manager() {
    section_header "Package Manager"

    local pipeline_file="${PROJECT_ROOT}/pipeline.yaml"
    local pm
    pm=$(get_yaml_value "$pipeline_file" "package_manager" "pnpm")

    if ! command -v "$pm" &> /dev/null; then
        check_fail "${pm} not installed"
        return
    fi

    local pm_version
    pm_version=$($pm --version 2>/dev/null || echo "unknown")
    check_pass "${pm} ${pm_version}"
}

check_claude_cli() {
    section_header "Claude Code CLI"

    if ! command -v claude &> /dev/null; then
        check_fail "Claude CLI not installed (CRITICAL)"
        echo -e "  ${CYAN}→${NC} Install: https://claude.com/download"
        return
    fi

    check_pass "Claude CLI found"

    # Test authentication
    if claude --version &> /dev/null; then
        local version
        version=$(claude --version 2>&1 | head -n1 || echo "unknown")
        echo -e "  ${CYAN}→${NC} Version: ${version}"
        check_pass "Claude CLI authenticated"
    else
        check_warn "Claude CLI authentication unclear"
    fi
}

check_playwright() {
    section_header "Playwright Browsers"

    local browser_found=0

    # macOS: ~/Library/Caches/ms-playwright
    # Linux: ~/.cache/ms-playwright
    local playwright_dirs=(
        "$HOME/Library/Caches/ms-playwright"
        "$HOME/.cache/ms-playwright"
    )

    for dir in "${playwright_dirs[@]}"; do
        if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
            browser_found=1
            break
        fi
    done

    if [[ $browser_found -eq 1 ]]; then
        check_pass "Playwright browsers installed"
    else
        check_warn "Playwright browsers not found (optional for QA screenshots)"
        echo -e "  ${CYAN}→${NC} Install: npx playwright install"
    fi
}

check_env_file() {
    section_header "Environment Variables"

    local env_file="${PROJECT_ROOT}/.env"

    if [[ ! -f "$env_file" ]]; then
        check_warn ".env file not found (may be OK if no external services)"
        return
    fi

    check_pass ".env file exists"

    # Controlla variabili richieste (se definite in pipeline.yaml)
    local pipeline_file="${PROJECT_ROOT}/pipeline.yaml"

    # Esempio: se il progetto usa Supabase, controlla SUPABASE_URL e SUPABASE_KEY
    # Questo e generico, dipende dal progetto
    local required_vars=(
        "SUPABASE_URL"
        "SUPABASE_PUBLISHABLE_KEY"
    )

    local missing_vars=0

    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file" 2>/dev/null; then
            continue
        fi

        local value
        value=$(grep "^${var}=" "$env_file" | head -n1 | cut -d= -f2-)

        if [[ -z "$value" ]]; then
            check_warn "${var} is set but empty"
            missing_vars=$((missing_vars + 1))
        fi
    done

    if [[ $missing_vars -eq 0 ]]; then
        echo -e "  ${CYAN}→${NC} Required variables present"
    fi
}

check_mcp_config() {
    section_header "MCP Configuration"

    local mcp_file="${PROJECT_ROOT}/.mcp.json"

    if [[ ! -f "$mcp_file" ]]; then
        check_warn ".mcp.json not found (MCP tools won't be available)"
        return
    fi

    check_pass ".mcp.json found"

    # Conta i server MCP configurati
    local server_count
    server_count=$(grep -c '"mcpServers"' "$mcp_file" 2>/dev/null || echo 0)

    if [[ $server_count -gt 0 ]]; then
        echo -e "  ${CYAN}→${NC} MCP servers configured"
    fi
}

check_git() {
    section_header "Git Repository"

    if ! git -C "$PROJECT_ROOT" rev-parse --git-dir &> /dev/null; then
        check_warn "Not a git repository (commits will fail)"
        return
    fi

    check_pass "Git repository initialized"

    # Controlla modifiche non committate
    if ! git -C "$PROJECT_ROOT" diff-index --quiet HEAD -- 2>/dev/null; then
        check_warn "Uncommitted changes detected"
        echo -e "  ${CYAN}→${NC} Consider committing before running pipeline"
    fi

    # Controlla se ci sono file non tracciati
    local untracked
    untracked=$(git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$untracked" -gt 0 ]]; then
        echo -e "  ${CYAN}→${NC} ${untracked} untracked files"
    fi
}

check_disk_space() {
    section_header "Disk Space"

    local available_kb

    # macOS: df -k . | tail -1 | awk '{print $4}'
    # Linux: df -k . | tail -1 | awk '{print $4}'
    available_kb=$(df -k "$PROJECT_ROOT" | tail -1 | awk '{print $4}')

    local available_mb=$((available_kb / 1024))
    local available_gb=$((available_mb / 1024))

    if [[ $available_gb -lt 1 ]]; then
        check_warn "Less than 1GB disk space available (${available_mb}MB)"
        echo -e "  ${CYAN}→${NC} Pipeline may fail if space runs out"
    else
        check_pass "${available_gb}GB available"
    fi
}

check_project_structure() {
    section_header "Project Structure"

    local required_dirs=(
        "docs"
        "logs"
        "scripts"
    )

    local missing_dirs=0

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${PROJECT_ROOT}/${dir}" ]]; then
            missing_dirs=$((missing_dirs + 1))
        fi
    done

    if [[ $missing_dirs -eq 0 ]]; then
        check_pass "Required directories present"
    else
        check_warn "${missing_dirs} required directories missing"
        echo -e "  ${CYAN}→${NC} Pipeline will create them if needed"
    fi

    # Controlla MASTER_PLAN.md
    if [[ -f "${PROJECT_ROOT}/docs/MASTER_PLAN.md" ]]; then
        check_pass "docs/MASTER_PLAN.md found"
    else
        check_warn "docs/MASTER_PLAN.md not found (recommended)"
    fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    echo -e "\n${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  Preflight Check — Environment Verification             ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

    check_pipeline_config
    check_node
    check_package_manager
    check_claude_cli
    check_playwright
    check_env_file
    check_mcp_config
    check_git
    check_disk_space
    check_project_structure

    # Summary
    echo -e "\n${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  Summary                                                 ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}\n"

    echo -e "${GREEN}✓${NC} ${CRITICAL_PASSED} critical checks passed"

    if [[ $CRITICAL_FAILED -gt 0 ]]; then
        echo -e "${RED}✗${NC} ${CRITICAL_FAILED} critical checks failed"
    fi

    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}⚠${NC} ${WARNINGS} warnings"
    fi

    echo ""

    if [[ $CRITICAL_FAILED -gt 0 ]]; then
        echo -e "${RED}${BOLD}❌ Environment is NOT ready to run the pipeline${NC}\n"
        exit 1
    else
        echo -e "${GREEN}${BOLD}✅ Environment is ready to run the pipeline${NC}\n"
        exit 0
    fi
}

main "$@"
