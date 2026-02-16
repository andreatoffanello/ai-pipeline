# AI Agents & Skills Design

> Architettura agenti per funzione (PM -> Design Review -> Dev -> Design Review -> QA) con cicli di validazione per ogni feature.

---

## FILOSOFIA

Gli agenti NON sono divisi per fase/feature, ma per **ruolo funzionale**. Ogni feature attraversa un ciclo completo:

```
PM (specifica) -> DR (valida spec) -> DEV (implementa) -> DR (valida UI) -> QA (valida tutto)
                        |                                        |              |
                        v se boccia                              v se boccia    v se fallisce
                   PM (corregge)                            DEV (corregge) -> QA (ri-valida)
```

Questo garantisce:
1. **Separazione di responsabilita**: chi specifica non implementa, chi implementa non si auto-valida
2. **Quality gates**: niente passa senza validazione
3. **Design quality**: il design viene verificato DUE volte -- sulla spec (prima di scrivere codice) e sull'implementazione (prima del QA)
4. **Cicli chiusi**: ogni issue ha un inizio (spec), una lavorazione (dev) e una chiusura (QA pass)
5. **Riproducibilita**: se il QA fallisce, il ciclo si ripete con istruzioni precise su cosa fixare

---

## GLI AGENTI

---

### AGENT: PM (Product Manager)

**Modello consigliato**: Opus o Sonnet (serve ragionamento profondo per spec coerenti)

**Ruolo**: Analizza la feature richiesta, produce specifiche dettagliate e criteri di accettazione. Non scrive codice.

**Cosa fa**:
- Legge il MASTER_PLAN.md e capisce il contesto
- Analizza il codebase esistente (struttura, pattern, componenti gia fatti)
- Produce una **spec** per il Dev con:
  - User stories chiare ("Come utente, voglio...")
  - Requisiti funzionali precisi (cosa deve fare)
  - Requisiti UI/UX (come deve apparire, comportamenti attesi)
  - Edge cases da gestire
  - Acceptance criteria numerati e verificabili
  - Dipendenze da componenti/moduli esistenti
  - Schema dati coinvolto (tabelle, relazioni)
  - Seed data per test visivi
- Identifica rischi e propone mitigazioni
- NON decide implementazione tecnica (quella e del Dev)

**Output**: `docs/specs/[FEATURE_NAME].md`

---

### AGENT: DR (Design Reviewer)

**Modello consigliato**: Sonnet (analisi visiva/strutturale, confronto con design system)

**Ruolo**: Garantisce la qualita del design. Interviene in DUE momenti del ciclo: dopo il PM (valida la spec UX) e dopo il Dev (valida l'implementazione visiva).

**Due modalita di intervento:**

#### Modalita 1: Spec Review (dopo PM, prima del Dev)
Verifica che la spec descriva un'esperienza utente coerente e di qualita.

**Cosa verifica**:
- Gerarchia visiva: le informazioni sono organizzate per importanza?
- Flussi utente: il percorso e logico e fluido?
- Coerenza col design system
- Edge states: empty, loading, error specificati con design adeguato?
- Responsive: copre mobile/tablet/desktop?
- Micro-interazioni: animazioni e transizioni specificate?

**Output**: `docs/design-review/[FEATURE_NAME]-spec.md`

#### Modalita 2: Implementation Review (dopo Dev, prima del QA)
Verifica che il codice implementi correttamente il design system.

**Cosa verifica**:
- Classi CSS/Tailwind corrette (spacing, colori, tipografia)
- Componenti UI usati correttamente
- Dark mode implementato
- Responsive: breakpoint classes presenti
- Animazioni: durata, easing corretti

**Se Playwright MCP disponibile**: naviga l'app, cattura screenshot, verifica visivamente.
**Se NON disponibile**: analisi codice + checklist visiva per l'utente.

**Output**: `docs/design-review/[FEATURE_NAME]-impl.md`

---

### AGENT: DEV (Developer)

**Modello consigliato**: Opus o Sonnet (codice complesso, architettura, debugging)

**Ruolo**: Riceve la spec dal PM, implementa la feature scrivendo codice. Non decide cosa fare (segue la spec), ma decide COME farlo tecnicamente.

**Cosa fa**:
- Legge la spec prodotta dal PM
- Analizza codebase per seguire i pattern esistenti
- Implementa seguendo le skill definite per lo stack
- Crea seed data per test visivi
- Verifica con browser (se Playwright MCP disponibile)
- Fa commit incrementali con messaggi chiari

**Output**: Codice committato e funzionante

---

### AGENT: QA (Quality Assurance)

**Modello consigliato**: Sonnet (pattern ripetitivo: checklist + confronto spec/codice)

**Ruolo**: Riceve la spec del PM e il codice del Dev. Verifica che l'implementazione rispetti TUTTI i criteri di accettazione. Non scrive feature code, solo report.

**Cosa fa**:
- Verifica ogni acceptance criterion uno per uno
- Controlla: funzionalita, TypeScript, design, pattern, edge cases, sicurezza
- Se Playwright MCP disponibile: testing E2E reale con screenshot come evidenza
- Produce report dettagliato con PASS/FAIL

**Output**: `docs/qa/[FEATURE_NAME]-qa.md`

**Severity guide**:
- **Critical**: non funziona, blocca l'utente, crash, errore build
- **Major**: funziona male, UX degradata, security issue
- **Minor**: dettaglio estetico, convenzione non seguita

**PASS** = zero Critical, zero Major (Minor accettabili)

---

### AGENT: DEV-FIX

**Modello consigliato**: Sonnet (fix mirati da report, non architettura)

**Ruolo**: Corregge le issues trovate dal QA.

**Cosa fa**:
- Legge il report QA
- Corregge TUTTE le issues Critical e Major
- Minor a discrezione
- NON introduce nuovi problemi, NON fa refactoring extra

---

### AGENT: ARCHITECT (usato solo in Fase 0)

**Modello consigliato**: Opus (setup critico, decisioni architetturali)

**Ruolo**: Setup iniziale del progetto. Agisce come PM+Dev+QA in un'unica sessione per la Fase 0 (infrastruttura pura).

---

## SCELTA MODELLO PER AGENTE

| Agente | Modello | Motivazione |
|--------|---------|-------------|
| **Architect** | Opus | Setup critico, decisioni irreversibili |
| **PM** | Opus / Sonnet | Ragionamento profondo per spec coerenti |
| **DR** | Sonnet | Analisi strutturale, confronto design system |
| **Dev** | Opus / Sonnet | Codice complesso, architettura |
| **QA** | Sonnet | Pattern ripetitivo: checklist + confronto |
| **Dev-Fix** | Sonnet / Haiku | Fix mirati da report, non architettura |

**Strategia per piano**:
- **Piano Pro ($20)**: Sonnet ovunque + Opus SOLO per Fase 0 (Architect)
- **Piano Max ($100)**: Opus per Architect+PM+Dev, Sonnet per QA+Dev-Fix
- **Piano base**: Sonnet ovunque

---

## EXECUTION FLOW

### Fase 0: Setup (ciclo singolo)
```
ARCHITECT -> setup completo -> verifica manuale
```

### Fasi 1-N: Feature (ciclo PM -> DR -> Dev -> DR -> QA)
```
Per ogni feature:

  PM ----> produce spec
           |
  DR ----> valida spec UX (design-review/[feature]-spec.md)
           |
           +-- OK -> procedi
           +-- REVISIONI -> PM corregge -> DR ri-valida (max 2 retry)
           |
  DEV ---> legge spec approvata, implementa
           |
  DR ----> valida implementazione UI (design-review/[feature]-impl.md)
           |
           +-- OK -> procedi
           +-- REVISIONI -> Dev corregge -> DR ri-valida (max 2 retry)
           |
  QA ----> legge spec + codice + DR report, verifica tutto
           |
           +-- PASS -> feature chiusa, prossima feature
           +-- FAIL -> Dev-Fix corregge -> QA ri-verifica (max 2 retry)
```

---

## AUTOMAZIONE: PIPELINE SCRIPT

Il ciclo PM -> DR -> Dev -> DR -> QA viene eseguito in autonomia tramite `scripts/pipeline.sh`.

```bash
# Ciclo completo per una feature
./scripts/pipeline.sh contacts

# Riprendi da uno step specifico
./scripts/pipeline.sh contacts --from dev

# Auto-rileva e riprendi
./scripts/pipeline.sh contacts --resume

# Preview dei prompt senza eseguire
./scripts/pipeline.sh contacts --dry-run

# Usa un modello specifico per tutti gli step
./scripts/pipeline.sh contacts --model opus
```

### Logica di retry

```
PM -> DR-SPEC
     +-- OK -> Dev
     +-- REVISIONI -> PM corregge -> DR-SPEC ri-valida (max 2 tentativi)

Dev -> DR-IMPL
      +-- OK -> QA
      +-- REVISIONI -> Dev corregge -> DR-IMPL ri-valida (max 2 tentativi)

QA
+-- PASS -> fine
+-- FAIL -> Dev-Fix -> QA ri-verifica (max 2 tentativi)
```

Se i tentativi si esauriscono, lo script si ferma e richiede intervento manuale.

### Output

- `docs/specs/[feature].md` -- spec del PM
- `docs/design-review/[feature]-spec.md` -- review design della spec
- `docs/design-review/[feature]-impl.md` -- review design dell'implementazione
- `docs/qa/[feature]-qa.md` -- report QA
- `logs/pipeline-[feature]-*.log` -- log di ogni step
- `logs/meta/[feature]-[step].meta.json` -- meta-dati strutturati
- `logs/decisions.jsonl` -- log deviazioni

---

## DECISION LOG

Quando un agente prende una decisione che devia dal piano originale, deve documentarla. Il pipeline script logga automaticamente i retry. Le deviazioni volontarie vanno inserite come istruzione nei prompt degli agenti.

Formato `logs/decisions.jsonl`:
```json
{
  "timestamp": "2026-02-16T14:30:00Z",
  "feature": "contacts",
  "step": "dev",
  "type": "deviation",
  "description": "Usato dialog modale invece di inline editing come da spec",
  "original_plan": "Inline editing nella tabella",
  "actual": "Dialog modale con form",
  "rationale": "Il layout responsive sotto 768px non supportava inline editing"
}
```
