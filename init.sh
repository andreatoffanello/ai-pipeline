#!/usr/bin/env bash
# ==============================================================================
# AI Pipeline Wizard - Entry Point
# ==============================================================================
# Interactive initialization script for AI multi-agent development pipelines
# ==============================================================================

set -euo pipefail

# Determine boilerplate directory from script location
BOILERPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BOILERPLATE_DIR

# Color codes
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[0;33m'

# Print welcome banner
print_banner() {
  clear
  echo ""
  echo -e "${C_BOLD}${C_CYAN}"
  cat << 'EOF'
   ╔═══════════════════════════════════════════════════════════════════╗
   ║                                                                   ║
   ║              █████╗ ██╗    ██████╗ ██╗██████╗ ███████╗          ║
   ║             ██╔══██╗██║    ██╔══██╗██║██╔══██╗██╔════╝          ║
   ║             ███████║██║    ██████╔╝██║██████╔╝█████╗            ║
   ║             ██╔══██║██║    ██╔═══╝ ██║██╔═══╝ ██╔══╝            ║
   ║             ██║  ██║██║    ██║     ██║██║     ███████╗          ║
   ║             ╚═╝  ╚═╝╚═╝    ╚═╝     ╚═╝╚═╝     ╚══════╝          ║
   ║                                                                   ║
   ║          Multi-Agent Development Pipeline Initialization         ║
   ║                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════╝
EOF
  echo -e "${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Welcome to the AI Pipeline Wizard!${C_RESET}"
  echo ""
  echo -e "This tool will set up a complete AI-powered development pipeline"
  echo -e "with specialized agents for product management, development, QA,"
  echo -e "and design review."
  echo ""
  echo -e "${C_YELLOW}Press Ctrl+C at any time to cancel${C_RESET}"
  echo ""
  read -p "Press Enter to continue..."
  echo ""
}

# Source wizard modules
source "$BOILERPLATE_DIR/wizard/questions.sh"
source "$BOILERPLATE_DIR/wizard/generator.sh"

# Print next steps
print_next_steps() {
  echo ""
  echo -e "${C_BOLD}${C_GREEN}═══════════════════════════════════════════════════════════════════${C_RESET}"
  echo -e "${C_BOLD}${C_GREEN}  Setup Complete!${C_RESET}"
  echo -e "${C_BOLD}${C_GREEN}═══════════════════════════════════════════════════════════════════${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Next Steps:${C_RESET}"
  echo ""
  echo -e "  ${C_CYAN}1.${C_RESET} Navigate to your project:"
  echo -e "     ${C_YELLOW}cd $PROJECT_DIR${C_RESET}"
  echo ""
  echo -e "  ${C_CYAN}2.${C_RESET} Copy and configure environment variables:"
  echo -e "     ${C_YELLOW}cp .env.example .env${C_RESET}"
  echo -e "     ${C_YELLOW}# Edit .env with your actual values${C_RESET}"
  echo ""
  echo -e "  ${C_CYAN}3.${C_RESET} Review the documentation:"
  echo -e "     ${C_YELLOW}cat CLAUDE.md${C_RESET}              ${C_RESET}# AI agent instructions"
  echo -e "     ${C_YELLOW}cat docs/AI_AGENTS.md${C_RESET}      ${C_RESET}# Agent roles"
  echo -e "     ${C_YELLOW}cat docs/CONVENTIONS.md${C_RESET}    ${C_RESET}# Coding standards"
  echo ""
  echo -e "  ${C_CYAN}4.${C_RESET} Run preflight checks:"
  echo -e "     ${C_YELLOW}./scripts/preflight.sh${C_RESET}"
  echo ""
  echo -e "  ${C_CYAN}5.${C_RESET} Initialize your project repository (if not already done):"
  echo -e "     ${C_YELLOW}git init${C_RESET}"
  echo -e "     ${C_YELLOW}git checkout -b $GIT_BRANCH${C_RESET}"
  echo ""
  echo -e "  ${C_CYAN}6.${C_RESET} Start working with the Product Manager agent:"
  echo -e "     ${C_YELLOW}./scripts/pipeline.sh pm \"Your feature request\"${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Example workflow:${C_RESET}"
  echo -e "  ${C_YELLOW}./scripts/pipeline.sh pm \"Add user authentication with email/password\"${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Pipeline phases:${C_RESET}"
  echo -e "  ${C_GREEN}PM${C_RESET}       - Product Manager writes functional spec"
  echo -e "  ${C_GREEN}DR-SPEC${C_RESET}  - Design Reviewer validates spec"
  echo -e "  ${C_GREEN}DEV${C_RESET}      - Developer implements feature"
  echo -e "  ${C_GREEN}DR-IMPL${C_RESET} - Design Reviewer validates implementation"
  echo -e "  ${C_GREEN}QA${C_RESET}       - QA Engineer tests feature"
  echo -e "  ${C_GREEN}DEV-FIX${C_RESET} - Developer fixes issues if any"
  echo ""
  echo -e "${C_BOLD}Documentation:${C_RESET}"
  echo -e "  All specs, reviews, and reports are saved in ${C_CYAN}docs/${C_RESET}"
  echo -e "  Pipeline logs are saved in ${C_CYAN}logs/${C_RESET}"
  echo ""
  echo -e "${C_BOLD}Supervisor monitoring:${C_RESET}"
  if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "  ${C_GREEN}✓${C_RESET} Telegram notifications enabled"
  else
    echo -e "  Configure Telegram notifications by setting:"
    echo -e "    ${C_YELLOW}TELEGRAM_BOT_TOKEN${C_RESET} and ${C_YELLOW}TELEGRAM_CHAT_ID${C_RESET} in pipeline.yaml"
  fi
  echo ""
  echo -e "${C_BOLD}${C_GREEN}Happy building with AI!${C_RESET}"
  echo ""
}

# Main execution
main() {
  print_banner

  # Run the question flow
  run_questions

  # Load the selected stack profile
  load_stack_profile

  # Generate the project structure
  generate_project

  # Show summary of generated files
  print_summary

  # Print next steps
  print_next_steps
}

# Run main function
main
