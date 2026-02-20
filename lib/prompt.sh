#!/usr/bin/env bash
# lib/prompt.sh — estrazione sezioni da prompts.md + build prompt completo
# PIPELINE_DIR, PIPELINE_FEATURE devono essere settati dall'entry point

PROMPTS_FILE="${PIPELINE_DIR}/prompts.md"

# ---------------------------------------------------------------------------
# prompt_extract_section <section_title>
# Estrae il contenuto del fence code block dalla sezione ## <section_title>
# ---------------------------------------------------------------------------
prompt_extract_section() {
    local section_title="$1"
    python3 - "$PROMPTS_FILE" "$section_title" <<'PYEOF'
import sys, re

path = sys.argv[1]
title = sys.argv[2]
content = open(path).read()

# Trova la sezione ## <title>
pattern = r'## ' + re.escape(title) + r'.*?\n(.*?)(?=\n## |\Z)'
m = re.search(pattern, content, re.DOTALL)
if not m:
    sys.exit(1)

section = m.group(1)

# Estrai contenuto dal primo fence code block
fence_m = re.search(r'```[^\n]*\n(.*?)```', section, re.DOTALL)
if fence_m:
    print(fence_m.group(1).rstrip())
else:
    print(section.strip())
PYEOF
}

# ---------------------------------------------------------------------------
# prompt_get_feature_brief <feature>
# Legge il brief da briefs/<feature>.md o chiede interattivamente
# ---------------------------------------------------------------------------
prompt_get_feature_brief() {
    local feature="$1"
    local brief_file="${PIPELINE_DIR}/briefs/${feature}.md"

    if [[ -f "$brief_file" ]]; then
        cat "$brief_file"
        return 0
    fi

    printf "  ${YELLOW}WARN${NC}  Brief non trovato per '${feature}'.\n" >&2
    printf "  ${DIM}Puoi creare ${brief_file} oppure descrivi la feature ora.${NC}\n" >&2
    printf "  Descrizione (termina con riga vuota):\n" >&2

    local brief=""
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        brief+="${line}"$'\n'
    done

    if [[ -z "$brief" ]]; then
        printf "  ERR  Nessuna descrizione fornita. Abort.\n" >&2
        return 1
    fi

    mkdir -p "${PIPELINE_DIR}/briefs"
    echo "$brief" > "$brief_file"
    printf "  >>  Brief salvato: briefs/${feature}.md\n" >&2
    echo "$brief"
}

# ---------------------------------------------------------------------------
# prompt_build_revalidation_context <retry_num> <max_retries> <feedback_file>
# Genera il blocco testo per ri-validazione dopo un gate REJECTED
# ---------------------------------------------------------------------------
prompt_build_revalidation_context() {
    local retry_num="$1"
    local max_retries="$2"
    local feedback_file="$3"

    local feedback=""
    [[ -f "$feedback_file" ]] && feedback=$(cat "$feedback_file")

    cat << EOF
QUESTA È UNA RI-VALIDAZIONE (retry ${retry_num}/${max_retries}).
Le revisioni precedenti erano:
---
${feedback}
---
Il developer ha aggiornato l'implementazione per correggere queste revisioni.
ISTRUZIONI PER LA RI-VALIDAZIONE:
1. Verifica SOLO che le revisioni precedenti siano state corrette
2. Per ogni revisione precedente, indica se è stata risolta o no
3. NON aggiungere nuove revisioni che non erano presenti prima
4. Se tutte le revisioni precedenti sono risolte, scrivi APPROVED nel file .verdict
5. Se alcune non sono risolte, scrivi REJECTED nel .verdict e elenca SOLO quelle ancora aperte
EOF
}

# ---------------------------------------------------------------------------
# prompt_build <step_name> <feature> [extra_context]
# Assembla il prompt completo per uno step usando prompts.md.
# Se prompts.md non esiste, fallback al file prompt/<step>.md statico.
# ---------------------------------------------------------------------------
prompt_build() {
    local step="$1"
    local feature="$2"
    local extra_context="${3:-}"

    # Fallback a file statico se prompts.md non esiste
    if [[ ! -f "$PROMPTS_FILE" ]]; then
        local static_prompt="${PIPELINE_DIR}/prompts/${step}.md"
        if [[ ! -f "$static_prompt" ]]; then
            printf "  ERR  Prompt non trovato: né prompts.md né prompts/%s.md\n" "$step" >&2
            return 1
        fi
        local content
        content=$(cat "$static_prompt")
        content="${content//\[FEATURE_NAME\]/$feature}"
        content="${content//\$\{FEATURE\}/$feature}"

        # Inietta brief per step pm
        if [[ "$step" == "pm" ]]; then
            local brief
            brief=$(prompt_get_feature_brief "$feature") || return 1
            printf "FEATURE: %s\nBRIEF:\n---\n%s\n---\n\n%s" "$feature" "$brief" "$content"
            return 0
        fi

        # Inietta feedback correzione
        if [[ -n "$extra_context" ]]; then
            printf "FEEDBACK DALLA REVISIONE:\n---\n%s\n---\n\n%s" "$extra_context" "$content"
            return 0
        fi

        printf "%s" "$content"
        return 0
    fi

    # Leggi prompt_section dal YAML
    local section
    section=$(config_step_get "$step" "prompt_section")
    if [[ -z "$section" ]]; then
        # Fallback: usa il nome step come sezione
        section="$step"
    fi

    # Estrai testo base dalla sezione
    local base_prompt
    base_prompt=$(prompt_extract_section "$section")
    if [[ -z "$base_prompt" ]]; then
        printf "  ERR  Sezione '%s' non trovata in prompts.md\n" "$section" >&2
        return 1
    fi

    # Sostituisci [FEATURE_NAME] e ${FEATURE}
    base_prompt="${base_prompt//\[FEATURE_NAME\]/$feature}"
    base_prompt="${base_prompt//\$\{FEATURE\}/$feature}"

    # Blocco contesto globale
    local pipeline_name
    pipeline_name=$(config_get_default "pipeline.name" "pipeline")
    local full_prompt=""
    full_prompt+="Stai lavorando nel progetto: ${pipeline_name}"$'\n'
    full_prompt+="Directory pipeline: ${PIPELINE_DIR}"$'\n'
    if [[ -n "${APP:-}" ]]; then
        full_prompt+="App/Layer target: ${APP}"$'\n'
    fi
    full_prompt+=""$'\n'

    # Brief per step pm
    if [[ "$step" == "pm" ]]; then
        local brief
        brief=$(prompt_get_feature_brief "$feature") || return 1
        full_prompt+="FEATURE: ${feature}"$'\n'
        full_prompt+="BRIEF:"$'\n'
        full_prompt+="---"$'\n'
        full_prompt+="${brief}"$'\n'
        full_prompt+="---"$'\n'$'\n'
    fi

    # extra_context: feedback revisione o ri-validazione
    if [[ -n "$extra_context" ]]; then
        if [[ "$step" == "pm" || "$step" == "dev" || "$step" == "dev-fix" ]]; then
            full_prompt+="IMPORTANTE: QUESTA È UNA CORREZIONE, NON UNA NUOVA IMPLEMENTAZIONE."$'\n'
            full_prompt+="Leggi il file esistente, applica le correzioni indicate nel feedback, riscrivi il file aggiornato nello stesso percorso."$'\n'
            full_prompt+="NON riscrivere da zero. Modifica solo le sezioni indicate nel feedback."$'\n'$'\n'
            full_prompt+="FEEDBACK DALLA REVISIONE:"$'\n'
            full_prompt+="---"$'\n'
            full_prompt+="${extra_context}"$'\n'
            full_prompt+="---"$'\n'$'\n'
        else
            full_prompt+="${extra_context}"$'\n'$'\n'
        fi
    fi

    # Prompt base
    full_prompt+="${base_prompt}"

    printf "%s" "$full_prompt"
}
