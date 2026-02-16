# Convenzioni Tecniche

> Standard obbligatori per tutto il codice del progetto.
> Il Dev li segue, il QA li verifica.

---

## 1. FORMATO RISPOSTE API

Tutte le API rispondono con lo stesso formato. Nessuna eccezione.

### Successo (lista)
```json
{
  "data": [...],
  "meta": {
    "total": 150,
    "page": 1,
    "per_page": 25,
    "total_pages": 6
  }
}
```
HTTP Status: `200`

### Successo (singolo)
```json
{
  "data": { ... }
}
```
HTTP Status: `200` (GET/PUT), `201` (POST)

### Successo (delete)
```json
{
  "data": null
}
```
HTTP Status: `200`

### Errore
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Email is required",
    "details": {
      "field": "email",
      "rule": "required"
    }
  }
}
```

### HTTP Status Codes usati
| Code | Quando |
|------|--------|
| `200` | Successo GET, PUT, DELETE |
| `201` | Successo POST (creazione) |
| `400` | Validazione fallita, input malformato |
| `401` | Non autenticato (no session) |
| `403` | Non autorizzato (session OK ma non ha permesso) |
| `404` | Risorsa non trovata |
| `409` | Conflitto (es. email duplicata) |
| `422` | Entita non processabile (Zod validation fail) |
| `500` | Errore server (mai esporre dettagli interni) |

### Query Parameters standard
```
GET /api/items?page=1&per_page=25&sort_by=created_at&sort_order=desc&search=query
```
| Param | Tipo | Default | Descrizione |
|-------|------|---------|-------------|
| `page` | number | 1 | Pagina corrente |
| `per_page` | number | 25 | Record per pagina (max 100) |
| `sort_by` | string | "created_at" | Colonna di ordinamento |
| `sort_order` | "asc" \| "desc" | "desc" | Direzione ordinamento |
| `search` | string | "" | Ricerca full-text |

---

## 2. ERROR HANDLING

### Lato server (server routes)
```ts
// Pattern OBBLIGATORIO per ogni server route
export default defineEventHandler(async (event) => {
  try {
    // ... logica
    return { data: result }
  } catch (error: any) {
    // Zod validation error
    if (error.name === 'ZodError') {
      throw createError({
        statusCode: 422,
        data: {
          error: {
            code: 'VALIDATION_ERROR',
            message: 'Invalid input',
            details: error.flatten().fieldErrors
          }
        }
      })
    }

    // Database error
    if (error.code) {
      throw createError({
        statusCode: error.code === 'PGRST116' ? 404 : 400,
        data: {
          error: {
            code: 'DATABASE_ERROR',
            message: error.message
          }
        }
      })
    }

    // Errore generico - NON esporre dettagli interni
    console.error('[API Error]', error)
    throw createError({
      statusCode: 500,
      data: {
        error: {
          code: 'INTERNAL_ERROR',
          message: 'Something went wrong'
        }
      }
    })
  }
})
```

### Lato client (store/composable)
```ts
// Pattern OBBLIGATORIO per chiamate API
import { toast } from 'vue-sonner'

async function createItem(data: CreateItem) {
  try {
    const response = await $fetch('/api/items', {
      method: 'POST',
      body: data
    })
    toast.success('Item created')
    return response.data
  } catch (error: any) {
    const message = error.data?.error?.message || 'Something went wrong'
    toast.error(message)
    throw error // ri-lancia per il chiamante
  }
}
```

### Regole
1. **Mai** `console.log` in produzione (solo `console.error` per errori veri)
2. **Mai** esporre stack trace o dettagli interni al client
3. **Sempre** toast per feedback errore all'utente
4. **Sempre** try/catch su ogni chiamata API
5. **Mai** swallare errori silenziosamente (catch senza throw o log)

---

## 3. SOFT DELETE VS HARD DELETE

{{SOFT_DELETE_STRATEGY}}

---

## 4. RLS POLICIES

{{RLS_SECTION}}

---

## 5. TESTING STRATEGY

### Cosa testare e quando

| Tipo | Tool | Chi | Quando | Coverage target |
|------|------|-----|--------|-----------------|
| **Type checking** | `tsc --noEmit` | Dev | Ogni commit | 100% (zero errori) |
| **Unit tests** | {{TESTING_TOOLS}} | Dev | Per logica business complessa | Funzioni utils, validators, store logic |
| **Component tests** | {{TESTING_TOOLS}} | Dev | Per componenti con logica | Componenti interattivi, form, filtri |
| **API integration tests** | {{TESTING_TOOLS}} | Dev | Per ogni endpoint API | Tutti gli endpoint |
| **E2E tests** | {{TESTING_TOOLS}} | QA (opzionale) | Per flussi critici | Login, CRUD, flussi principali |

### Acceptance criteria aggiornati
I prompt PM devono includere:
```
- [ ] [AC-TESTS] Unit test per logica business
- [ ] [AC-API-TESTS] Integration test per ogni endpoint API
```

---

## 6. GIT WORKFLOW

### Branch naming
```
main                          ← produzione, sempre deployabile
├── feat/feature-name         ← feature branch
├── fix/bug-description       ← bug fix
└── chore/task-description    ← manutenzione
```

### Commit convention (Conventional Commits)
```
feat(scope): add feature description
fix(scope): resolve bug description
chore(deps): update dependencies
refactor(scope): extract shared logic
docs(readme): add setup instructions
```

Formato: `type(scope): description`

Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `style`

### Merge strategy
- **Squash merge** per feature branches → 1 commit pulito per feature
- **Mai** force push su main

---

## 7. LINGUA INTERFACCIA

Default: **inglese** per l'interfaccia.

Motivi:
- Standard SaaS internazionale
- Componenti UI sono in inglese
- Documentazione e codice in inglese
- Se in futuro vuoi vendere, e gia pronto

L'italiano si usa per:
- Documentazione interna (questi docs)
- Comunicazioni con il team
- Email template (configurabili per lingua, futuro i18n)

---

## 8. CONVENZIONI FRAMEWORK

{{FRAMEWORK_CONVENTIONS}}

---

## 9. ENVIRONMENT VARIABLES

{{ENV_VARS_SECTION}}
