# Skill: CRUD API Generator

> Genera server routes Nuxt complete per una tabella Supabase con validazione, paginazione e multi-tenancy.

**Quando usarla**: Ogni volta che serve un set di API endpoints per una tabella del database.

**Input**: Nome tabella, schema colonne, relazioni.
**Output**: Server routes Nuxt complete con validazione Zod e gestione errori.

---

## Prompt

```
## Obiettivo
Genera le server routes API CRUD per la tabella: {{TABLE_NAME}}

## Schema tabella
{{INCOLLA_SCHEMA_SQL_DELLA_TABELLA}}

## Relazioni
- {{TABLE_NAME}}.organization_id → organizations.id (multi-tenant, sempre filtrato)
- {{ALTRE_RELAZIONI_SPECIFICHE}}

## Cosa generare

Crea i seguenti file in server/api/{{table-name}}/:

### 1. index.get.ts - Lista con filtri
```ts
// GET /api/{{table-name}}
// Query params: page, per_page, sort_by, sort_order, search, {{filtri_specifici}}
// Response: { data: T[], meta: { total, page, per_page, total_pages } }
```
Requisiti:
- Filtra SEMPRE per organization_id dell'utente autenticato (multi-tenancy)
- Paginazione con default 25 per pagina
- Sorting dinamico (whitelist di colonne sortabili)
- Ricerca full-text sui campi testuali principali
- Filtri specifici via query params
- Include relazioni necessarie per la lista

### 2. index.post.ts - Creazione
```ts
// POST /api/{{table-name}}
// Body: validato con Zod schema
// Response: { data: T }
```
Requisiti:
- Validazione body con Zod (import da validators)
- Imposta automaticamente: organization_id, created_by, created_at
- Ritorna il record creato con relazioni

### 3. [id].get.ts - Dettaglio
```ts
// GET /api/{{table-name}}/:id
// Response: { data: T } con relazioni complete
```
Requisiti:
- Verifica che il record appartenga all'organization dell'utente
- Include tutte le relazioni rilevanti
- 404 se non trovato

### 4. [id].put.ts - Modifica
```ts
// PUT /api/{{table-name}}/:id
// Body: validato con Zod (partial schema)
// Response: { data: T }
```
Requisiti:
- Validazione body con Zod partial
- Verifica ownership (organization_id)
- Aggiorna updated_at automaticamente

### 5. [id].delete.ts - Eliminazione
```ts
// DELETE /api/{{table-name}}/:id
// Response: { data: null }
```
Requisiti:
- Verifica ownership
- Soft delete dove appropriato (status → 'archived') o hard delete

### Pattern per ogni file
```ts
import { serverSupabaseClient, serverSupabaseUser } from '#supabase/server'
import { z } from 'zod'

export default defineEventHandler(async (event) => {
  const client = await serverSupabaseClient(event)
  const user = await serverSupabaseUser(event)

  if (!user) {
    throw createError({ statusCode: 401, message: 'Unauthorized' })
  }

  // Recupera organization_id dal profilo utente
  const { data: profile } = await client
    .from('profiles')
    .select('organization_id')
    .eq('id', user.id)
    .single()

  if (!profile) {
    throw createError({ statusCode: 403, message: 'No organization' })
  }

  // ... logica specifica dell'endpoint
})
```

## Esempio completo: index.get.ts (Lista)

```ts
import { serverSupabaseClient, serverSupabaseUser } from '#supabase/server'
import { {{tableName}}FiltersSchema } from '{{PATH_TO_VALIDATORS}}'

export default defineEventHandler(async (event) => {
  const client = await serverSupabaseClient(event)
  const user = await serverSupabaseUser(event)

  if (!user) {
    throw createError({ statusCode: 401, message: 'Unauthorized' })
  }

  // Get organization_id
  const { data: profile } = await client
    .from('profiles')
    .select('organization_id')
    .eq('id', user.id)
    .single()

  if (!profile) {
    throw createError({ statusCode: 403, message: 'No organization' })
  }

  // Parse e valida query params
  const query = getQuery(event)
  const filters = {{tableName}}FiltersSchema.parse(query)

  // Build query
  let queryBuilder = client
    .from('{{table_name}}')
    .select('*, {{relazioni}}', { count: 'exact' })
    .eq('organization_id', profile.organization_id)

  // Ricerca full-text
  if (filters.search) {
    queryBuilder = queryBuilder.or(
      `{{campo1}}.ilike.%${filters.search}%,{{campo2}}.ilike.%${filters.search}%`
    )
  }

  // Filtri specifici
  if (filters.{{filtro_custom}}) {
    queryBuilder = queryBuilder.eq('{{campo}}', filters.{{filtro_custom}})
  }

  // Sorting
  queryBuilder = queryBuilder.order(filters.sort_by, {
    ascending: filters.sort_order === 'asc'
  })

  // Paginazione
  const from = (filters.page - 1) * filters.per_page
  const to = from + filters.per_page - 1
  queryBuilder = queryBuilder.range(from, to)

  const { data, error, count } = await queryBuilder

  if (error) {
    throw createError({
      statusCode: 500,
      message: error.message,
    })
  }

  return {
    data: data || [],
    meta: {
      total: count || 0,
      page: filters.page,
      per_page: filters.per_page,
      total_pages: Math.ceil((count || 0) / filters.per_page),
    },
  }
})
```

## Esempio completo: index.post.ts (Creazione)

```ts
import { serverSupabaseClient, serverSupabaseUser } from '#supabase/server'
import { create{{TableName}}Schema } from '{{PATH_TO_VALIDATORS}}'

export default defineEventHandler(async (event) => {
  const client = await serverSupabaseClient(event)
  const user = await serverSupabaseUser(event)

  if (!user) {
    throw createError({ statusCode: 401, message: 'Unauthorized' })
  }

  const { data: profile } = await client
    .from('profiles')
    .select('organization_id')
    .eq('id', user.id)
    .single()

  if (!profile) {
    throw createError({ statusCode: 403, message: 'No organization' })
  }

  // Valida body
  const body = await readBody(event)
  const validated = create{{TableName}}Schema.parse(body)

  // Crea record
  const { data, error } = await client
    .from('{{table_name}}')
    .insert({
      ...validated,
      organization_id: profile.organization_id,
      created_by: user.id,
    })
    .select('*, {{relazioni}}')
    .single()

  if (error) {
    throw createError({
      statusCode: 500,
      message: error.message,
    })
  }

  return { data }
})
```

## Vincoli
- Usa SOLO Supabase JS client (non query SQL dirette)
- Validazione con Zod importato da validators
- Error handling con createError() di Nuxt
- Nessun console.log in production code
- TypeScript strict
- Multi-tenancy: SEMPRE filtrare per organization_id
- Response format standard: { data, meta } per liste, { data } per singoli
```
