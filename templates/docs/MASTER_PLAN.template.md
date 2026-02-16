# {{PROJECT_NAME}} Master Plan

> Piano esecutivo completo per la progettazione e lo sviluppo.

---

## 1. VISIONE E PRINCIPI

### Vision

{{PROJECT_DESCRIPTION}}

### Principi di Design

*To be filled: design philosophy, UX principles*

### Principi Tecnici

*To be filled: technical principles, architecture decisions*

---

## 2. CASI D'USO

*To be filled by the user. Example structure:*

| Caso d'uso | Descrizione | Priorita |
|---|---|---|
| *Example feature* | *What it does* | P0/P1/P2 |

---

## 3. STACK & ARCHITETTURA

### 3.1 Stack Decisioni

{{STACK_DESCRIPTION}}

### 3.2 Struttura Monorepo

{{MONOREPO_STRUCTURE}}

### 3.3 Schema Database (Core)

**TODO**: Define database schema here. Include:
- Tables with columns and types
- Relationships (foreign keys)
- Indexes
- RLS policies
- Triggers
- Helper functions

Example:
```sql
-- Organizations (multi-tenant)
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add your tables here...
```

---

## 4. DESIGN SYSTEM

### 4.1 Filosofia Visiva

*To be filled: color palette, typography, spacing, radius, shadows, animations, dark mode approach*

For detailed UI patterns and component architecture, see `docs/skills/design-system.md`.

### 4.2 Component Architecture

*To be filled: component organization, naming conventions, reusable patterns*

---

## 5. FASI DI ESECUZIONE

*To be filled by the user. Example structure:*

| # | Fase | Descrizione | Sessioni stimate |
|---|------|-------------|------------------|
| 0 | Setup | Infrastruttura, DB, auth, layout | 1-2 |
| 1 | *Feature name* | *What will be built* | *N* |
| 2 | *Feature name* | *What will be built* | *N* |

---

## 6. DOCUMENTAZIONE CORRELATA

| Documento | Contenuto |
|-----------|-----------|
| [PROMPTS.md](./PROMPTS.md) | Prompt copia-incolla pronti per ogni fase e ruolo |
| [SKILLS.md](./SKILLS.md) | Indice skills riutilizzabili |
| [MCP.md](./MCP.md) | Configurazione MCP servers |
| [ENVIRONMENTS.md](./ENVIRONMENTS.md) | Setup ambienti local, staging, production |
| [CONVENTIONS.md](./CONVENTIONS.md) | Coding conventions e standard obbligatori |
| [PRE_KICKOFF.md](./PRE_KICKOFF.md) | Azioni fisiche da compiere prima di iniziare |
| [STATUS.md](./STATUS.md) | Progress tracker — aggiornato dopo ogni sessione |

---

## 7. NON INCLUSO NEL PROTOTIPO (Backlog Futuro)

*To be filled: features deferred to later phases*
