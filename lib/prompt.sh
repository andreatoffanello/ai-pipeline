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
# prompt_build_revalidation_context <retry_num> <max_retries> <feedback_file> [step]
# Genera il blocco testo per ri-validazione dopo un gate REJECTED
# ---------------------------------------------------------------------------
prompt_build_revalidation_context() {
    local retry_num="$1"
    local max_retries="$2"
    local feedback_file="$3"
    local step="${4:-}"

    local feedback=""
    [[ -f "$feedback_file" ]] && feedback=$(cat "$feedback_file")

    # Messaggio agente-specifico
    local agent_msg="L'autore ha aggiornato l'artefatto per correggere queste revisioni."
    case "$step" in
        pm)   agent_msg="Il PM ha aggiornato la specifica per correggere queste revisioni." ;;
        dev|dev-fix) agent_msg="Il developer ha aggiornato l'implementazione per correggere queste revisioni." ;;
        dr-spec|dr-impl) agent_msg="Il reviewer sta ri-validando dopo la correzione dell'autore." ;;
    esac

    cat << EOF
QUESTA È UNA RI-VALIDAZIONE (retry ${retry_num}/${max_retries}).

Le revisioni aperte dal round precedente erano:
---
${feedback}
---

${agent_msg}

ISTRUZIONI OBBLIGATORIE PER LA RI-VALIDAZIONE:
1. Leggi il file aggiornato — non fare affidamento sulla memoria di round precedenti
2. Per ogni REV elencata sopra, cerca nella spec/implementazione la correzione corrispondente
3. Marca esplicitamente ogni REV come "RESOLVED ✓" o "OPEN ✗" con motivazione
4. Se la correzione ha introdotto NUOVI problemi (non preesistenti), segnalali come NEW-001, NEW-002, ecc.
   Segnala solo problemi effettivamente introdotti dalla correzione, non problemi che c'erano già prima.
5. Verdetto binario: tutte le REV RESOLVED e zero NEW → APPROVED. Altrimenti → REJECTED
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
        content="${content//\$\{PIPELINE_DIR\}/$PIPELINE_DIR}"

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

    # Sostituisci [FEATURE_NAME], ${FEATURE} e ${PIPELINE_DIR}
    base_prompt="${base_prompt//\[FEATURE_NAME\]/$feature}"
    base_prompt="${base_prompt//\$\{FEATURE\}/$feature}"
    base_prompt="${base_prompt//\$\{PIPELINE_DIR\}/$PIPELINE_DIR}"

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

    # Contesto cross-step (se esiste)
    local ctx_file="${PIPELINE_DIR}/context/${feature}.json"
    if [[ -f "$ctx_file" ]]; then
        full_prompt+="File di contesto della feature: ${ctx_file}"$'\n'
        full_prompt+="Leggilo per sapere quali file sono stati creati/modificati dagli step precedenti."$'\n'$'\n'
    fi

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
            full_prompt+="IMPORTANTE: QUESTA È UNA CORREZIONE INCREMENTALE, NON UNA NUOVA IMPLEMENTAZIONE."$'\n'
            full_prompt+="Il file/implementazione attuale è già stato prodotto. NON ri-esplorare il codebase da zero."$'\n'
            full_prompt+="NON riscrivere file da zero. Usa il tool Edit per modifiche mirate alle sezioni indicate nel feedback."$'\n'
            full_prompt+="Leggi prima il file corrente, poi applica SOLO le modifiche necessarie."$'\n'$'\n'
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
