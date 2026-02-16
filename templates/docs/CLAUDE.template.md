# {{PROJECT_NAME}} — AI Onboarding

> Read this file FIRST. It tells you everything you need to know to work on this project.

## What is this?

{{PROJECT_DESCRIPTION}}

Stack: {{STACK_DESCRIPTION}}

## Before you do ANYTHING

1. Read `docs/STATUS.md` — current state, what's done, what's next, open problems
2. Read `docs/MASTER_PLAN.md` — architecture, DB schema, design system
3. Read `docs/CONVENTIONS.md` — API format, error handling, testing (MANDATORY to follow)

## Documentation map

| File | What it contains | When to read |
|------|-----------------|--------------|
| `docs/STATUS.md` | Progress tracker, decisions log, open problems | **ALWAYS FIRST** |
| `docs/MASTER_PLAN.md` | Vision, use cases, stack, DB schema, design system, phases | Before any work |
| `docs/CONVENTIONS.md` | API format, error handling, testing, git, coding conventions | Before writing code |
| `docs/PROMPTS.md` | Copy-paste prompts for each role and phase | To execute a phase |
| `docs/SKILLS.md` | Index of reusable skills (individual files in `docs/skills/`) | When building features |
| `docs/MCP.md` | MCP server config (database, browser testing, external APIs) | If MCP tools available |
| `docs/ENVIRONMENTS.md` | Local/staging/prod setup, migration workflow | For deploy/env questions |
| `docs/PRE_KICKOFF.md` | Physical steps user must do before Phase 0 | Only if setup not done |

## How development works

Every feature follows a **PM → DR → Dev → DR → QA** cycle:

1. **PM agent** reads MASTER_PLAN + CONVENTIONS, produces `docs/specs/[feature].md`
2. **DR-SPEC agent** reviews the spec from UX perspective, produces `docs/design-review/[feature]-spec.md`
3. **Dev agent** reads the spec, implements it, commits
4. **DR-IMPL agent** reviews the implementation from design perspective, produces `docs/design-review/[feature]-impl.md`
5. **QA agent** reads spec + code, produces `docs/qa/[feature]-qa.md` (PASS/FAIL)
6. If FAIL → **Dev-Fix agent** reads QA report, fixes issues, commits

See `docs/PROMPTS.md` for the actual prompts.

## Key rules

{{KEY_RULES}}

## Gotchas & Technical Notes

Things that bit us during setup. Read these BEFORE making changes:

*This section will be populated during development as issues are discovered.*

## After every session

Update `docs/STATUS.md`:
- Mark completed tasks ✅
- Log any decisions made
- Log any open problems
- Update "Ultima azione" and "Prossima azione"
