#!/usr/bin/env bash
# ==============================================================================
# AI Pipeline Wizard - Template Generator
# ==============================================================================
# Processes templates and generates project structure
# Bash 3.2 compatible (macOS) - NO yq dependency, pure grep/sed
# ==============================================================================

set -euo pipefail

# Stack profile variables (populated by load_stack_profile)
STACK_DISPLAY=""
STACK_DESCRIPTION=""
FRAMEWORK=""
UI_LIBRARY=""
CSS_FRAMEWORK=""
STATE_MANAGEMENT=""
DATABASE=""
PACKAGE_MANAGER=""
DEV_SERVER_COMMAND=""
DEV_SERVER_WORKING_DIR=""
DEV_SERVER_PORT=""
DEV_SERVER_HEALTH_CHECK=""
DEV_SERVER_STARTUP_TIMEOUT=""
PM_MODEL=""
DR_SPEC_MODEL=""
DEV_MODEL=""
DR_IMPL_MODEL=""
QA_MODEL=""
DEV_FIX_MODEL=""
ENV_VARS_REQUIRED=""
ENV_VARS_OPTIONAL=""
SKILLS_BASE=""
SKILLS_STACK=""
SKILLS_ORDER=""
MCP_SERVERS=""

# Load and parse stack profile YAML
load_stack_profile() {
  local stack_file="$BOILERPLATE_DIR/wizard/stacks/${STACK_CHOICE}.yaml"

  if [ ! -f "$stack_file" ]; then
    print_error "Stack profile not found: $stack_file"
    exit 1
  fi

  print_info "Loading stack profile: $STACK_CHOICE"

  # Extract simple key-value pairs
  STACK_DISPLAY=$(grep "^display_name:" "$stack_file" | head -n1 | sed 's/^display_name: *//' | tr -d '"' || echo "")
  STACK_DESCRIPTION=$(grep "^description:" "$stack_file" | head -n1 | sed 's/^description: *//' | tr -d '"' || echo "")

  # Extract stack section values
  FRAMEWORK=$(grep "^  framework:" "$stack_file" | head -n1 | sed 's/^  framework: *//' | tr -d '"' || echo "")
  UI_LIBRARY=$(grep "^  ui_library:" "$stack_file" | head -n1 | sed 's/^  ui_library: *//' | tr -d '"' || echo "")
  CSS_FRAMEWORK=$(grep "^  css_framework:" "$stack_file" | head -n1 | sed 's/^  css_framework: *//' | tr -d '"' || echo "")
  STATE_MANAGEMENT=$(grep "^  state_management:" "$stack_file" | head -n1 | sed 's/^  state_management: *//' | tr -d '"' || echo "")
  DATABASE=$(grep "^  database:" "$stack_file" | head -n1 | sed 's/^  database: *//' | tr -d '"' || echo "")
  PACKAGE_MANAGER=$(grep "^  package_manager:" "$stack_file" | head -n1 | sed 's/^  package_manager: *//' | tr -d '"' || echo "")

  # Extract dev_server section values
  DEV_SERVER_COMMAND=$(grep "^  command:" "$stack_file" | head -n1 | sed 's/^  command: *//' | tr -d '"' || echo "")
  DEV_SERVER_WORKING_DIR=$(grep "^  working_dir:" "$stack_file" | head -n1 | sed 's/^  working_dir: *//' | tr -d '"' || echo "")
  DEV_SERVER_PORT=$(grep "^  port:" "$stack_file" | head -n1 | sed 's/^  port: *//' | tr -d '"' || echo "")
  DEV_SERVER_HEALTH_CHECK=$(grep "^  health_check_url:" "$stack_file" | head -n1 | sed 's/^  health_check_url: *//' | tr -d '"' || echo "")
  DEV_SERVER_STARTUP_TIMEOUT=$(grep "^  startup_timeout_seconds:" "$stack_file" | head -n1 | sed 's/^  startup_timeout_seconds: *//' | tr -d '"' || echo "")

  # Extract model names
  PM_MODEL=$(grep "^  pm:" "$stack_file" | head -n1 | sed 's/^  pm: *//' | tr -d '"' || echo "opus")
  DR_SPEC_MODEL=$(grep "^  dr_spec:" "$stack_file" | head -n1 | sed 's/^  dr_spec: *//' | tr -d '"' || echo "sonnet")
  DEV_MODEL=$(grep "^  dev:" "$stack_file" | head -n1 | sed 's/^  dev: *//' | tr -d '"' || echo "opus")
  DR_IMPL_MODEL=$(grep "^  dr_impl:" "$stack_file" | head -n1 | sed 's/^  dr_impl: *//' | tr -d '"' || echo "sonnet")
  QA_MODEL=$(grep "^  qa:" "$stack_file" | head -n1 | sed 's/^  qa: *//' | tr -d '"' || echo "sonnet")
  DEV_FIX_MODEL=$(grep "^  dev_fix:" "$stack_file" | head -n1 | sed 's/^  dev_fix: *//' | tr -d '"' || echo "sonnet")

  # Extract skills lists
  SKILLS_ORDER=$(grep "^  order:" "$stack_file" | head -n1 | sed 's/^  order: *//' | tr -d '"' || echo "")

  # Extract skills base list
  SKILLS_BASE=$(awk '/^  base:$/,/^  [a-z]/ {if (/^    - /) print $2}' "$stack_file" | tr '\n' ',' | sed 's/,$//')

  # Extract skills stack list
  SKILLS_STACK=$(awk '/^  stack:$/,/^  [a-z]/ {if (/^    - /) print $2}' "$stack_file" | tr '\n' ',' | sed 's/,$//')

  # Extract environment variables
  ENV_VARS_REQUIRED=$(awk '/^  required:$/,/^  [a-z]/ {
    if (/^    - name: /) {
      name = $3
      getline
      if (/^      description: /) {
        sub(/^      description: */, "")
        gsub(/"/, "")
        print name "||" $0
      }
    }
  }' "$stack_file")

  ENV_VARS_OPTIONAL=$(awk '/^  optional:$/,/^[a-z]/ {
    if (/^    - name: /) {
      name = $3
      getline
      if (/^      description: /) {
        sub(/^      description: */, "")
        gsub(/"/, "")
        print name "||" $0
      }
    }
  }' "$stack_file")

  # Extract MCP server names
  MCP_SERVERS=$(awk '/^mcp_servers:$/,/^[a-z_]+:$/ {
    if (/^  [a-z_-]+:$/ && !/^mcp_servers:$/) {
      sub(/:$/, "")
      gsub(/^  /, "")
      print
    }
  }' "$stack_file" | tr '\n' ',' | sed 's/,$//')

  print_success "Stack profile loaded successfully"
}

# Process template file with variable substitution
process_template() {
  local template_file="$1"
  local output_file="$2"

  if [ ! -f "$template_file" ]; then
    print_warning "Template not found: $template_file"
    return 1
  fi

  # Create parent directory if needed
  local output_dir=$(dirname "$output_file")
  mkdir -p "$output_dir"

  # Start with template content
  local content=$(cat "$template_file")

  # Replace all placeholders
  content=$(echo "$content" | sed "s|{{PROJECT_NAME}}|$PROJECT_NAME|g")
  content=$(echo "$content" | sed "s|{{PROJECT_DISPLAY_NAME}}|$PROJECT_DISPLAY_NAME|g")
  content=$(echo "$content" | sed "s|{{PROJECT_DESCRIPTION}}|$PROJECT_DESCRIPTION|g")
  content=$(echo "$content" | sed "s|{{PROJECT_DIR}}|$PROJECT_DIR|g")
  content=$(echo "$content" | sed "s|{{STACK_CHOICE}}|$STACK_CHOICE|g")
  content=$(echo "$content" | sed "s|{{STACK_DISPLAY}}|$STACK_DISPLAY|g")
  content=$(echo "$content" | sed "s|{{STACK_DESCRIPTION}}|$STACK_DESCRIPTION|g")
  content=$(echo "$content" | sed "s|{{FRAMEWORK}}|$FRAMEWORK|g")
  content=$(echo "$content" | sed "s|{{UI_LIBRARY}}|$UI_LIBRARY|g")
  content=$(echo "$content" | sed "s|{{CSS_FRAMEWORK}}|$CSS_FRAMEWORK|g")
  content=$(echo "$content" | sed "s|{{STATE_MANAGEMENT}}|$STATE_MANAGEMENT|g")
  content=$(echo "$content" | sed "s|{{DATABASE}}|$DATABASE|g")
  content=$(echo "$content" | sed "s|{{PACKAGE_MANAGER}}|$PACKAGE_MANAGER|g")
  content=$(echo "$content" | sed "s|{{DEV_SERVER_COMMAND}}|$DEV_SERVER_COMMAND|g")
  content=$(echo "$content" | sed "s|{{DEV_SERVER_WORKING_DIR}}|$DEV_SERVER_WORKING_DIR|g")
  content=$(echo "$content" | sed "s|{{DEV_SERVER_PORT}}|$DEV_SERVER_PORT|g")
  content=$(echo "$content" | sed "s|{{DEV_SERVER_HEALTH_CHECK}}|$DEV_SERVER_HEALTH_CHECK|g")
  content=$(echo "$content" | sed "s|{{DEV_SERVER_STARTUP_TIMEOUT}}|$DEV_SERVER_STARTUP_TIMEOUT|g")
  content=$(echo "$content" | sed "s|{{PM_MODEL}}|$PM_MODEL|g")
  content=$(echo "$content" | sed "s|{{DR_SPEC_MODEL}}|$DR_SPEC_MODEL|g")
  content=$(echo "$content" | sed "s|{{DEV_MODEL}}|$DEV_MODEL|g")
  content=$(echo "$content" | sed "s|{{DR_IMPL_MODEL}}|$DR_IMPL_MODEL|g")
  content=$(echo "$content" | sed "s|{{QA_MODEL}}|$QA_MODEL|g")
  content=$(echo "$content" | sed "s|{{DEV_FIX_MODEL}}|$DEV_FIX_MODEL|g")
  content=$(echo "$content" | sed "s|{{DESIGN_LEVEL}}|$DESIGN_LEVEL|g")
  content=$(echo "$content" | sed "s|{{GIT_BRANCH}}|$GIT_BRANCH|g")
  content=$(echo "$content" | sed "s|{{SKILLS_ORDER}}|$SKILLS_ORDER|g")

  # Handle Telegram tokens (may be empty)
  if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    content=$(echo "$content" | sed "s|{{TELEGRAM_BOT_TOKEN}}|$TELEGRAM_BOT_TOKEN|g")
    content=$(echo "$content" | sed "s|{{TELEGRAM_CHAT_ID}}|$TELEGRAM_CHAT_ID|g")
  else
    # Remove telegram configuration lines if not configured
    content=$(echo "$content" | grep -v "{{TELEGRAM_BOT_TOKEN}}" || echo "$content")
    content=$(echo "$content" | grep -v "{{TELEGRAM_CHAT_ID}}" || echo "$content")
  fi

  # Write processed content
  echo "$content" > "$output_file"

  return 0
}

# Generate .env.example from stack profile
generate_env_example() {
  local env_file="$PROJECT_DIR/.env.example"

  cat > "$env_file" << EOF
# ==============================================================================
# $PROJECT_DISPLAY_NAME - Environment Variables
# ==============================================================================
# Copy this file to .env and fill in your actual values
# Generated by AI Pipeline wizard
# ==============================================================================

# --- Required Variables ---
EOF

  # Add required env vars
  local IFS=$'\n'
  for line in $ENV_VARS_REQUIRED; do
    if [ -n "$line" ]; then
      local var_name=$(echo "$line" | cut -d'|' -f1)
      local var_desc=$(echo "$line" | cut -d'|' -f3-)
      echo "# $var_desc" >> "$env_file"
      echo "$var_name=" >> "$env_file"
      echo "" >> "$env_file"
    fi
  done

  cat >> "$env_file" << EOF

# --- Optional Variables ---
EOF

  # Add optional env vars
  for line in $ENV_VARS_OPTIONAL; do
    if [ -n "$line" ]; then
      local var_name=$(echo "$line" | cut -d'|' -f1)
      local var_desc=$(echo "$line" | cut -d'|' -f3-)
      echo "# $var_desc" >> "$env_file"
      echo "# $var_name=" >> "$env_file"
      echo "" >> "$env_file"
    fi
  done

  print_success "Generated .env.example"
}

# Generate CLAUDE.md at project root
generate_claude_md() {
  local claude_file="$PROJECT_DIR/CLAUDE.md"

  cat > "$claude_file" << EOF
# AI Pipeline Instructions for $PROJECT_DISPLAY_NAME

## Stack
$STACK_DISPLAY

## Key Rules
- Framework: $FRAMEWORK
- UI Library: $UI_LIBRARY
- CSS: $CSS_FRAMEWORK
- State: $STATE_MANAGEMENT
- Database: $DATABASE
- Package Manager: $PACKAGE_MANAGER

## Development
- Dev server: \`$DEV_SERVER_COMMAND\` (working dir: $DEV_SERVER_WORKING_DIR)
- Port: $DEV_SERVER_PORT
- DO NOT run dev/build commands directly - ask the user to run them

## Documentation
All specs and docs are in \`docs/\`:
- Functional specs: \`docs/specs/\`
- Design reviews: \`docs/design-review/\`
- QA reports: \`docs/qa/\`
- Skills: \`docs/skills/\`
- Agent roles: \`docs/AI_AGENTS.md\`

## Skill Development Order
$SKILLS_ORDER

## Pipeline
Run the pipeline with: \`./scripts/pipeline.sh\`

Read \`docs/CONVENTIONS.md\` for coding standards.
EOF

  print_success "Generated CLAUDE.md"
}

# Copy skill files
copy_skills() {
  local skills_dir="$PROJECT_DIR/docs/skills"
  mkdir -p "$skills_dir"

  # Copy base skills
  local IFS=','
  for skill in $SKILLS_BASE; do
    if [ -n "$skill" ]; then
      local source_file="$BOILERPLATE_DIR/templates/skills/base/$skill"
      if [ -f "$source_file" ]; then
        cp "$source_file" "$skills_dir/"
        print_success "Copied skill: $skill (base)"
      fi
    fi
  done

  # Copy stack-specific skills
  for skill in $SKILLS_STACK; do
    if [ -n "$skill" ]; then
      local source_file="$BOILERPLATE_DIR/templates/skills/$STACK_CHOICE/$skill"
      if [ -f "$source_file" ]; then
        cp "$source_file" "$skills_dir/"
        print_success "Copied skill: $skill (stack)"
      fi
    fi
  done
}

# Main generation function
generate_project() {
  print_header "Generating Project Structure"

  # Create directory structure
  print_info "Creating directories..."

  mkdir -p "$PROJECT_DIR"
  mkdir -p "$PROJECT_DIR/docs/specs"
  mkdir -p "$PROJECT_DIR/docs/design-review"
  mkdir -p "$PROJECT_DIR/docs/qa"
  mkdir -p "$PROJECT_DIR/docs/skills"
  mkdir -p "$PROJECT_DIR/scripts/hooks"
  mkdir -p "$PROJECT_DIR/logs/meta"
  mkdir -p "$PROJECT_DIR/.claude"

  print_success "Directory structure created"

  # Process documentation templates
  print_info "Processing documentation templates..."

  local templates_docs="$BOILERPLATE_DIR/templates/docs"

  if [ -d "$templates_docs" ]; then
    for template in "$templates_docs"/*.template.md; do
      if [ -f "$template" ]; then
        local filename=$(basename "$template" .template.md)
        process_template "$template" "$PROJECT_DIR/docs/${filename}.md"
        print_success "Generated docs/${filename}.md"
      fi
    done
  fi

  # Copy AI_AGENTS.md
  if [ -f "$templates_docs/AI_AGENTS.md" ]; then
    process_template "$templates_docs/AI_AGENTS.md" "$PROJECT_DIR/docs/AI_AGENTS.md"
    print_success "Generated docs/AI_AGENTS.md"
  fi

  # Copy skills
  print_info "Copying skill files..."
  copy_skills

  # Process script templates
  print_info "Processing script templates..."

  local templates_scripts="$BOILERPLATE_DIR/templates/scripts"

  if [ -d "$templates_scripts" ]; then
    for template in "$templates_scripts"/*.template.sh; do
      if [ -f "$template" ]; then
        local filename=$(basename "$template" .template.sh)
        process_template "$template" "$PROJECT_DIR/scripts/${filename}.sh"
        chmod +x "$PROJECT_DIR/scripts/${filename}.sh"
        print_success "Generated scripts/${filename}.sh"
      fi
    done

    # Process JavaScript scripts
    for template in "$templates_scripts"/*.template.js; do
      if [ -f "$template" ]; then
        local filename=$(basename "$template" .template.js)
        process_template "$template" "$PROJECT_DIR/scripts/${filename}.js"
        chmod +x "$PROJECT_DIR/scripts/${filename}.js"
        print_success "Generated scripts/${filename}.js"
      fi
    done
  fi

  # Process config templates
  print_info "Processing configuration files..."

  local templates_config="$BOILERPLATE_DIR/templates/config"

  if [ -f "$templates_config/pipeline.template.yaml" ]; then
    process_template "$templates_config/pipeline.template.yaml" "$PROJECT_DIR/pipeline.yaml"
    print_success "Generated pipeline.yaml"
  fi

  if [ -f "$templates_config/mcp.template.json" ]; then
    process_template "$templates_config/mcp.template.json" "$PROJECT_DIR/.mcp.json"
    print_success "Generated .mcp.json"
  fi

  if [ -f "$templates_config/claude-settings.template.json" ]; then
    process_template "$templates_config/claude-settings.template.json" "$PROJECT_DIR/.claude/settings.local.json"
    print_success "Generated .claude/settings.local.json"
  fi

  # Generate derived files
  print_info "Generating derived files..."

  generate_env_example
  generate_claude_md

  print_success "Project generation complete!"
}

# Print summary of generated files
print_summary() {
  print_header "Generated Files"

  echo -e "${C_BOLD}Project structure created at:${C_RESET} ${C_CYAN}$PROJECT_DIR${C_RESET}"
  echo ""
  echo -e "${C_GREEN}✓${C_RESET} pipeline.yaml          ${C_YELLOW}# Main pipeline configuration${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} CLAUDE.md              ${C_YELLOW}# AI agent instructions${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} .env.example           ${C_YELLOW}# Environment variables template${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} .mcp.json              ${C_YELLOW}# MCP server configuration${C_RESET}"
  echo ""
  echo -e "${C_BOLD}docs/${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} docs/AI_AGENTS.md      ${C_YELLOW}# Agent roles and responsibilities${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} docs/CONVENTIONS.md    ${C_YELLOW}# Coding standards${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} docs/specs/            ${C_YELLOW}# Functional specifications${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} docs/design-review/    ${C_YELLOW}# Design review reports${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} docs/qa/               ${C_YELLOW}# QA test reports${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} docs/skills/           ${C_YELLOW}# Development skills${C_RESET}"
  echo ""
  echo -e "${C_BOLD}scripts/${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} scripts/pipeline.sh    ${C_YELLOW}# Main pipeline executor${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} scripts/preflight.sh   ${C_YELLOW}# Environment validator${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} scripts/supervisor.js  ${C_YELLOW}# Pipeline monitor${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} scripts/analytics.js   ${C_YELLOW}# Analytics reporter${C_RESET}"
  echo ""
  echo -e "${C_BOLD}.claude/${C_RESET}"
  echo -e "${C_GREEN}✓${C_RESET} .claude/settings.local.json ${C_YELLOW}# Claude IDE settings${C_RESET}"
  echo ""
}
