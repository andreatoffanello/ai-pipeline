#!/usr/bin/env bash
# ==============================================================================
# AI Pipeline Wizard - Interactive Questions
# ==============================================================================
# Collects user inputs for project initialization
# Bash 3.2 compatible (macOS) - NO declare -A, NO readarray
# ==============================================================================

set -euo pipefail

# Color codes
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'

# Global variables that will be populated by questions
PROJECT_NAME=""
PROJECT_DISPLAY_NAME=""
PROJECT_DESCRIPTION=""
PROJECT_DIR=""
STACK_CHOICE=""
DESIGN_LEVEL=""
GIT_BRANCH=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Print colored header
print_header() {
  echo ""
  echo -e "${C_BOLD}${C_BLUE}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${C_RESET}"
  echo -e "${C_BOLD}${C_CYAN}  $1${C_RESET}"
  echo -e "${C_BOLD}${C_BLUE}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${C_RESET}"
  echo ""
}

# Print info message
print_info() {
  echo -e "${C_BLUE}ℹ${C_RESET}  $1"
}

# Print success message
print_success() {
  echo -e "${C_GREEN}✓${C_RESET}  $1"
}

# Print error message
print_error() {
  echo -e "${C_RED}✗${C_RESET}  $1"
}

# Print warning message
print_warning() {
  echo -e "${C_YELLOW}⚠${C_RESET}  $1"
}

# Validate slug format (lowercase alphanumeric with hyphens)
validate_slug() {
  local slug="$1"
  if echo "$slug" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    return 0
  else
    return 1
  fi
}

# Convert string to slug format
to_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'
}

# List available stack profiles
list_stacks() {
  local stacks_dir="$BOILERPLATE_DIR/wizard/stacks"
  local stack_files=""

  if [ -d "$stacks_dir" ]; then
    stack_files=$(find "$stacks_dir" -name "*.yaml" -type f 2>/dev/null || true)
  fi

  if [ -z "$stack_files" ]; then
    print_error "No stack profiles found in $stacks_dir"
    exit 1
  fi

  echo -e "\n${C_BOLD}Available stacks:${C_RESET}\n"

  local index=1
  local IFS=$'\n'
  for stack_file in $stack_files; do
    local stack_name=$(basename "$stack_file" .yaml)
    local display_name=$(grep "^display_name:" "$stack_file" | head -n1 | sed 's/^display_name: *//' | tr -d '"' || echo "$stack_name")
    local description=$(grep "^description:" "$stack_file" | head -n1 | sed 's/^description: *//' | tr -d '"' || echo "")

    echo -e "  ${C_GREEN}[$index]${C_RESET} ${C_BOLD}$display_name${C_RESET}"
    if [ -n "$description" ]; then
      echo -e "      $description"
    fi
    echo -e "      ${C_CYAN}($stack_name)${C_RESET}"
    echo ""

    index=$((index + 1))
  done
}

# Get stack name by index
get_stack_by_index() {
  local target_index="$1"
  local stacks_dir="$BOILERPLATE_DIR/wizard/stacks"
  local stack_files=$(find "$stacks_dir" -name "*.yaml" -type f 2>/dev/null | sort)

  local index=1
  local IFS=$'\n'
  for stack_file in $stack_files; do
    if [ "$index" -eq "$target_index" ]; then
      basename "$stack_file" .yaml
      return 0
    fi
    index=$((index + 1))
  done

  return 1
}

# Count available stacks
count_stacks() {
  local stacks_dir="$BOILERPLATE_DIR/wizard/stacks"
  local stack_files=$(find "$stacks_dir" -name "*.yaml" -type f 2>/dev/null || true)
  echo "$stack_files" | grep -c . || echo "0"
}

# Main question flow
run_questions() {
  print_header "AI Pipeline Project Initialization"

  echo -e "${C_BOLD}This wizard will guide you through setting up your AI development pipeline.${C_RESET}"
  echo ""

  # Question 1: Project name slug
  print_header "Project Identification"

  while true; do
    read -p "$(echo -e ${C_CYAN}Enter project slug ${C_RESET}${C_YELLOW}[e.g., my-crm]${C_RESET}: )" PROJECT_NAME

    if [ -z "$PROJECT_NAME" ]; then
      print_error "Project name cannot be empty"
      continue
    fi

    if ! validate_slug "$PROJECT_NAME"; then
      print_warning "Invalid format. Converting to slug: $(to_slug "$PROJECT_NAME")"
      PROJECT_NAME=$(to_slug "$PROJECT_NAME")
    fi

    print_success "Project slug: $PROJECT_NAME"
    break
  done

  # Question 2: Display name
  echo ""
  local default_display_name=$(echo "$PROJECT_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
  read -p "$(echo -e ${C_CYAN}Enter display name ${C_RESET}${C_YELLOW}[$default_display_name]${C_RESET}: )" PROJECT_DISPLAY_NAME

  if [ -z "$PROJECT_DISPLAY_NAME" ]; then
    PROJECT_DISPLAY_NAME="$default_display_name"
  fi
  print_success "Display name: $PROJECT_DISPLAY_NAME"

  # Question 3: Description
  echo ""
  read -p "$(echo -e ${C_CYAN}Enter project description ${C_RESET}${C_YELLOW}[one line]${C_RESET}: )" PROJECT_DESCRIPTION

  if [ -z "$PROJECT_DESCRIPTION" ]; then
    PROJECT_DESCRIPTION="AI-powered application built with multi-agent pipeline"
  fi
  print_success "Description: $PROJECT_DESCRIPTION"

  # Question 4: Project directory
  print_header "Project Location"

  local default_project_dir="$HOME/Projects/$PROJECT_NAME"
  read -p "$(echo -e ${C_CYAN}Enter project directory ${C_RESET}${C_YELLOW}[$default_project_dir]${C_RESET}: )" PROJECT_DIR

  if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$default_project_dir"
  fi

  # Expand ~ to home directory
  PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"

  # Check if directory exists and has pipeline.yaml
  if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/pipeline.yaml" ]; then
    print_error "Directory already contains pipeline.yaml"
    print_error "Please choose a different directory or remove existing pipeline configuration"
    exit 1
  fi

  print_success "Project directory: $PROJECT_DIR"

  # Question 5: Stack choice
  print_header "Technology Stack"

  list_stacks

  local stack_count=$(count_stacks)

  while true; do
    read -p "$(echo -e ${C_CYAN}Select stack ${C_RESET}${C_YELLOW}[1-$stack_count]${C_RESET}: )" stack_index

    if ! echo "$stack_index" | grep -qE '^[0-9]+$'; then
      print_error "Please enter a number"
      continue
    fi

    if [ "$stack_index" -lt 1 ] || [ "$stack_index" -gt "$stack_count" ]; then
      print_error "Please enter a number between 1 and $stack_count"
      continue
    fi

    STACK_CHOICE=$(get_stack_by_index "$stack_index")
    if [ $? -eq 0 ] && [ -n "$STACK_CHOICE" ]; then
      print_success "Stack: $STACK_CHOICE"
      break
    else
      print_error "Failed to retrieve stack"
    fi
  done

  # Question 6: Design level
  print_header "Design Quality Level"

  echo -e "${C_BOLD}Choose design level:${C_RESET}"
  echo ""
  echo -e "  ${C_GREEN}[1]${C_RESET} ${C_BOLD}Premium${C_RESET} - Awwwards-level design with micro-interactions and polish"
  echo -e "  ${C_GREEN}[2]${C_RESET} ${C_BOLD}Standard${C_RESET} - Clean, professional design with best practices"
  echo ""

  while true; do
    read -p "$(echo -e ${C_CYAN}Select design level ${C_RESET}${C_YELLOW}[1-2, default: 2]${C_RESET}: )" design_choice

    case "$design_choice" in
      1)
        DESIGN_LEVEL="premium"
        print_success "Design level: Premium"
        break
        ;;
      2|"")
        DESIGN_LEVEL="standard"
        print_success "Design level: Standard"
        break
        ;;
      *)
        print_error "Please enter 1 or 2"
        ;;
    esac
  done

  # Question 7: Git branch
  print_header "Git Configuration"

  read -p "$(echo -e ${C_CYAN}Default working branch ${C_RESET}${C_YELLOW}[main]${C_RESET}: )" GIT_BRANCH

  if [ -z "$GIT_BRANCH" ]; then
    GIT_BRANCH="main"
  fi
  print_success "Git branch: $GIT_BRANCH"

  # Question 8 & 9: Telegram notifications (optional)
  print_header "Supervisor Notifications (Optional)"

  echo -e "${C_BOLD}Configure Telegram notifications for pipeline supervisor?${C_RESET}"
  echo -e "${C_YELLOW}You can skip this and configure later.${C_RESET}"
  echo ""

  read -p "$(echo -e ${C_CYAN}Telegram Bot Token ${C_RESET}${C_YELLOW}[press Enter to skip]${C_RESET}: )" TELEGRAM_BOT_TOKEN

  if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    read -p "$(echo -e ${C_CYAN}Telegram Chat ID ${C_RESET}${C_YELLOW}[required]${C_RESET}: )" TELEGRAM_CHAT_ID

    if [ -z "$TELEGRAM_CHAT_ID" ]; then
      print_warning "Chat ID required when Bot Token is provided. Notifications will be disabled."
      TELEGRAM_BOT_TOKEN=""
      TELEGRAM_CHAT_ID=""
    else
      print_success "Telegram notifications enabled"
    fi
  else
    print_info "Telegram notifications skipped"
    TELEGRAM_CHAT_ID=""
  fi

  # Summary and confirmation
  print_header "Configuration Summary"

  echo -e "${C_BOLD}Project Details:${C_RESET}"
  echo -e "  Name:        ${C_GREEN}$PROJECT_NAME${C_RESET}"
  echo -e "  Display:     ${C_GREEN}$PROJECT_DISPLAY_NAME${C_RESET}"
  echo -e "  Description: ${C_GREEN}$PROJECT_DESCRIPTION${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Location:${C_RESET}"
  echo -e "  Directory:   ${C_GREEN}$PROJECT_DIR${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Stack:${C_RESET}"
  echo -e "  Profile:     ${C_GREEN}$STACK_CHOICE${C_RESET}"
  echo -e "  Design:      ${C_GREEN}$DESIGN_LEVEL${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Git:${C_RESET}"
  echo -e "  Branch:      ${C_GREEN}$GIT_BRANCH${C_RESET}"
  echo ""

  if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${C_BOLD}Notifications:${C_RESET}"
    echo -e "  Telegram:    ${C_GREEN}Enabled${C_RESET}"
    echo ""
  fi

  echo ""
  while true; do
    read -p "$(echo -e ${C_BOLD}${C_YELLOW}Proceed with this configuration? [y/N]${C_RESET}: )" confirm

    case "$confirm" in
      y|Y|yes|Yes|YES)
        print_success "Configuration confirmed"
        echo ""
        return 0
        ;;
      n|N|no|No|NO|"")
        print_warning "Initialization cancelled"
        exit 0
        ;;
      *)
        print_error "Please answer y or n"
        ;;
    esac
  done
}
