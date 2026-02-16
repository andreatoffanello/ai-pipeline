#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Documentation Generator — Generate project docs using Claude CLI
# ==============================================================================
#
# Abstracted from project-specific references. Reads project context from
# docs/MASTER_PLAN.md and pipeline.yaml.
#
# Usage:
#   ./scripts/docs-gen.sh [type] [options]
#
# Types:
#   readme      Update README.md at project root
#   user        Generate user manual (with screenshots if Playwright available)
#   technical   Generate technical documentation (architecture, API, DB)
#   all         All of the above (default)
#
# Options:
#   --feature <name>  Scope to one feature
#   --model <model>   Claude model to use (default: sonnet)
#   --dry-run         Show prompt without executing
#
# Examples:
#   ./scripts/docs-gen.sh
#   ./scripts/docs-gen.sh readme
#   ./scripts/docs-gen.sh user --feature contacts
#   ./scripts/docs-gen.sh technical --model opus
#
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ==============================================================================
# Utility
# ==============================================================================

log_step() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

log_info() { echo -e "${CYAN}ℹ $1${NC}"; }
log_success() { echo -e "${GREEN}✓ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_error() { echo -e "${RED}✗ $1${NC}"; }

# Parse YAML helper (Bash 3.2 compatible)
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
# Doc Generators
# ==============================================================================

generate_readme_prompt() {
    local project_name="$1"

    cat <<PROMPT
You are a technical writer for a software project.

Read these files to understand the project:
- docs/MASTER_PLAN.md (vision, architecture, stack)
- docs/CONVENTIONS.md (if exists: conventions, patterns, API format)
- docs/STATUS.md (if exists: current state, what's implemented)

Explore the codebase to understand what's actually implemented:
- Check for pages/routes (e.g., app/pages/, pages/, src/pages/)
- Check for components (e.g., app/components/, components/, src/components/)
- Check for stores/state management (e.g., app/stores/, stores/, src/stores/)
- Check for API routes (e.g., server/api/, api/, src/api/)

Generate/update the README.md file at the project root with:

# ${project_name}

## Overview
Brief description of the project (2-3 lines)

## Features
List of implemented features with brief descriptions (based on what EXISTS in the code, NOT the roadmap)

## Tech Stack
Technology stack with versions (read from package.json, docs/MASTER_PLAN.md)

## Getting Started
### Prerequisites
### Installation
### Environment Variables
(based on .env.example if it exists, or docs/ENVIRONMENTS.md)
### Running locally

## Project Structure
Structure overview with brief explanation of key directories

## Development
### Conventions
Link to docs/CONVENTIONS.md if it exists
### Adding a new feature
Brief description of the development workflow

## License

Write in English. Be concise and practical. DO NOT invent features that don't exist in the code.
Commit the README.md and push.
PROMPT
}

generate_user_docs_prompt() {
    local project_name="$1"
    local feature_filter="$2"

    local feature_section=""
    if [[ -n "$feature_filter" ]]; then
        feature_section="Focus ONLY on the feature: ${feature_filter}
Read the spec: docs/specs/${feature_filter}.md"
    else
        feature_section="Cover ALL implemented features.
Read all specs in docs/specs/ to understand what's been implemented."
    fi

    cat <<PROMPT
You are a UX writer for a software project.

Read these files:
- docs/MASTER_PLAN.md (general context)
- docs/STATUS.md (if exists: what's implemented)
${feature_section}

Explore the codebase to understand pages and flows:
- Check all pages/routes (e.g., app/pages/, pages/, src/pages/)
- Check UI components (e.g., app/components/, components/, src/components/)

$(if command -v npx &>/dev/null && [[ -f "${PROJECT_ROOT}/.mcp.json" ]] && grep -q '"playwright"' "${PROJECT_ROOT}/.mcp.json" 2>/dev/null; then
    echo "IMPORTANT: You have Playwright MCP available."
    echo "For EACH page/feature:"
    echo "1. Navigate to the page (e.g., http://localhost:3000/<page>) with Playwright"
    echo "2. Capture screenshots"
    echo "3. Save screenshots in docs/user-guide/screenshots/"
    echo "4. Include them in the manual as markdown images"
else
    echo "Playwright is NOT available. Describe screens textually without screenshots."
fi)

Generate the file docs/user-guide/README.md (and subpages if needed) with:

# ${project_name} — User Manual

## Table of Contents
(links to each section)

For EACH implemented feature:
## [Feature Name]
### Overview
What it does and why (1-2 lines)
### How to access
Where to find it in the UI, direct URL
### Main functionality
For each function: description + screenshot (if available)
### Common operations
Step-by-step for frequent actions (create, edit, delete, search, filter)
### FAQ / Common issues
Frequently asked questions and solutions

Write in clear, simple language. NO technical jargon.
Commit and push.
PROMPT
}

generate_technical_docs_prompt() {
    local project_name="$1"
    local feature_filter="$2"

    local feature_section=""
    if [[ -n "$feature_filter" ]]; then
        feature_section="Focus ONLY on the feature: ${feature_filter}"
    else
        feature_section="Cover ALL implemented features."
    fi

    cat <<PROMPT
You are a senior technical writer for a software project.

Read these files:
- docs/MASTER_PLAN.md (architecture, DB schema, design system)
- docs/CONVENTIONS.md (if exists: API format, error handling, patterns)
- docs/STATUS.md (if exists: current state)
${feature_section}

Explore the codebase deeply:
- All API routes (e.g., server/api/, api/, src/api/)
- State management (e.g., stores/, src/stores/)
- Validation schemas (e.g., schemas/, src/schemas/, look for Zod schemas)
- Database migrations (e.g., supabase/migrations/, prisma/migrations/, migrations/)
- Composables/hooks (e.g., composables/, hooks/, src/composables/)

Generate/update docs/technical/README.md with:

# ${project_name} — Technical Documentation

## Architecture
- High-level system diagram (ASCII or Mermaid)
- Request flow: Client → Server → Database
- Project structure overview

## Database Schema
For each table:
- Name, columns with types, constraints
- Relations (foreign keys)
- Access control policies (if applicable, e.g., RLS in Supabase)
- Indexes
(Based on migration files, DO NOT invent)

## API Reference
For each implemented endpoint:
- Method + Path
- Request params/body (with types)
- Response shape (with example)
- Authentication requirements
- Possible error codes

## State Management
For each store/state container:
- Name and responsibility
- State shape
- Main actions/methods
- Where it's used

## Components
Main reusable components (not all, only shared ones):
- Name, props, events
- Where it's used
- Usage example

## Authentication & Authorization
- Auth flow (e.g., Supabase Auth, NextAuth, etc.)
- Access control: how it works, who can see what
- Roles and permissions

Write in English. Be precise and based ONLY on what exists in the code.
DO NOT document unimplemented features.
Commit and push.
PROMPT
}

# ==============================================================================
# Runner
# ==============================================================================

run_doc_agent() {
    local doc_type="$1"
    local prompt="$2"
    local log_file="${PROJECT_ROOT}/logs/docs-gen-${doc_type}.log"

    mkdir -p "${PROJECT_ROOT}/logs"
    mkdir -p "${PROJECT_ROOT}/docs/user-guide"
    mkdir -p "${PROJECT_ROOT}/docs/technical"

    log_step "📝 Generating: ${doc_type}"
    log_info "Log: ${log_file}"

    local model_flag=""
    if [[ -n "$MODEL" ]]; then
        model_flag="--model $MODEL"
    else
        # Sonnet is sufficient for docs — no need for Opus
        model_flag="--model sonnet"
    fi

    local prompt_file
    prompt_file=$(mktemp)
    echo "$prompt" > "$prompt_file"

    > "$log_file"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN — Prompt:"
        echo ""
        cat "$prompt_file"
        echo ""
        rm -f "$prompt_file"
        return 0
    fi

    # shellcheck disable=SC2086
    claude -p \
        --output-format stream-json \
        --allowedTools "Read,Write,Edit,Bash,Glob,Grep,WebFetch,mcp__*" \
        $model_flag \
        < "$prompt_file" 2>/dev/null | while IFS= read -r line; do
        echo "$line" >> "$log_file"
    done

    local exit_code=${PIPESTATUS[0]}
    rm -f "$prompt_file"

    if [[ $exit_code -eq 0 ]]; then
        log_success "${doc_type} completed"
    else
        log_error "${doc_type} failed (exit: ${exit_code})"
        log_info "See log: ${log_file}"
    fi

    return $exit_code
}

# ==============================================================================
# CLI
# ==============================================================================

usage() {
    cat <<EOF
Usage: ./scripts/docs-gen.sh [type] [options]

Generate documentation for the project using Claude CLI.

Types:
  readme      README.md at project root
  user        User manual (with screenshots if Playwright available)
  technical   Technical documentation (architecture, API, DB)
  all         All of the above (default)

Options:
  --feature <name>   Generate docs only for a specific feature
  --model <model>    Claude model to use (default: sonnet)
  --dry-run          Show prompt without executing
  --help             Show this help

Examples:
  ./scripts/docs-gen.sh                            # Generate all docs
  ./scripts/docs-gen.sh readme                     # Only README
  ./scripts/docs-gen.sh user                       # Only user manual
  ./scripts/docs-gen.sh technical                  # Only technical docs
  ./scripts/docs-gen.sh user --feature contacts    # User docs for one feature
  ./scripts/docs-gen.sh --model opus               # Use Opus model
  ./scripts/docs-gen.sh --dry-run                  # Show prompts without running
EOF
}

DOC_TYPE="all"
FEATURE=""
MODEL=""
DRY_RUN="false"

# Parse positional argument first (doc type)
if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    DOC_TYPE="$1"
    shift
fi

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature)
            FEATURE="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validations
if ! command -v claude &> /dev/null; then
    log_error "Claude Code CLI not found."
    log_info "Install from: https://claude.com/download"
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/docs/MASTER_PLAN.md" ]]; then
    log_warning "docs/MASTER_PLAN.md not found (recommended for context)"
fi

# Get project name from pipeline.yaml
PROJECT_NAME=$(get_yaml_value "${PROJECT_ROOT}/pipeline.yaml" "name" "Project")

# Header
echo -e "\n${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Documentation Generator                                 ║${NC}"
echo -e "${BOLD}║  Project: ${CYAN}${PROJECT_NAME}${NC}${BOLD}                                        ║${NC}"
echo -e "${BOLD}║  Type: ${CYAN}${DOC_TYPE}${NC}${BOLD}                                            ║${NC}"
if [[ -n "$FEATURE" ]]; then
echo -e "${BOLD}║  Feature: ${CYAN}${FEATURE}${NC}${BOLD}                                        ║${NC}"
fi
if [[ "$DRY_RUN" == "true" ]]; then
echo -e "${BOLD}║  ${YELLOW}DRY RUN${NC}${BOLD}                                              ║${NC}"
fi
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}\n"

start_time=$(date +%s)
errors=0

# Execute
case "$DOC_TYPE" in
    readme)
        run_doc_agent "readme" "$(generate_readme_prompt "$PROJECT_NAME")" || errors=$((errors + 1))
        ;;
    user)
        run_doc_agent "user" "$(generate_user_docs_prompt "$PROJECT_NAME" "$FEATURE")" || errors=$((errors + 1))
        ;;
    technical)
        run_doc_agent "technical" "$(generate_technical_docs_prompt "$PROJECT_NAME" "$FEATURE")" || errors=$((errors + 1))
        ;;
    all)
        run_doc_agent "readme" "$(generate_readme_prompt "$PROJECT_NAME")" || errors=$((errors + 1))
        run_doc_agent "user" "$(generate_user_docs_prompt "$PROJECT_NAME" "$FEATURE")" || errors=$((errors + 1))
        run_doc_agent "technical" "$(generate_technical_docs_prompt "$PROJECT_NAME" "$FEATURE")" || errors=$((errors + 1))
        ;;
    *)
        log_error "Invalid type: ${DOC_TYPE}. Use: readme, user, technical, all"
        exit 1
        ;;
esac

end_time=$(date +%s)
duration=$(( end_time - start_time ))
minutes=$(( duration / 60 ))
seconds=$(( duration % 60 ))

# Summary
echo ""
if [[ $errors -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✅ Documentation generated in ${minutes}m ${seconds}s${NC}"
else
    echo -e "${BOLD}${YELLOW}⚠ Completed with ${errors} errors in ${minutes}m ${seconds}s${NC}"
fi

echo -e "${CYAN}Output:${NC}"
[[ "$DOC_TYPE" == "readme" || "$DOC_TYPE" == "all" ]] && echo "  - README.md"
[[ "$DOC_TYPE" == "user" || "$DOC_TYPE" == "all" ]] && echo "  - docs/user-guide/"
[[ "$DOC_TYPE" == "technical" || "$DOC_TYPE" == "all" ]] && echo "  - docs/technical/"
echo "  - logs/docs-gen-*.log"
echo ""

exit $errors
