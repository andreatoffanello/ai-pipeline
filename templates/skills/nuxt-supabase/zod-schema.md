# Skill: Zod Schema Generator

> Genera schema Zod e types TypeScript derivati per una tabella. Zod è la single source of truth per validazione client e server.

**Quando usarla**: Ogni volta che serve definire la validazione per un'entità del database.

**Input**: Schema SQL della tabella.
**Output**: Zod schemas (base, create, update, filters) + types derivati con z.infer.

---

## Prompt

```
## Obiettivo
Genera gli schema Zod per la tabella: {{TABLE_NAME}}

## Schema SQL
{{INCOLLA_CREATE_TABLE_SQL}}

## Cosa generare

Crea il file validators/{{table-name}}.ts:

```ts
import { z } from 'zod'

/**
 * Schema base con TUTTI i campi della tabella
 * Include: id, timestamps, foreign keys, tutti i campi dati
 */
export const {{tableName}}Schema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid(),

  // Campi dati specifici
  {{campo1}}: z.string().min(1, 'Campo obbligatorio').max(255),
  {{campo2}}: z.string().email('Email non valida').toLowerCase(),
  {{campo3}}: z.string().optional(),
  {{campo_numero}}: z.number().int().positive(),
  {{campo_boolean}}: z.boolean().default(false),
  {{campo_enum}}: z.enum(['value1', 'value2', 'value3']),

  // Foreign keys
  {{related_id}}: z.string().uuid().optional(),

  // Timestamps
  created_at: z.string().datetime(),
  updated_at: z.string().datetime(),
  created_by: z.string().uuid().optional(),
})

/**
 * Schema per creazione
 * Omette: id, timestamps, organization_id (auto-generati dal server)
 * Include: solo campi compilabili dall'utente
 */
export const create{{TableName}}Schema = z.object({
  {{campo1}}: z.string()
    .min(1, 'Campo obbligatorio')
    .max(255, 'Massimo 255 caratteri')
    .trim(),

  {{campo2}}: z.string()
    .email('Email non valida')
    .toLowerCase()
    .trim(),

  {{campo3}}: z.string()
    .max(500, 'Massimo 500 caratteri')
    .optional(),

  {{campo_numero}}: z.coerce.number()
    .int('Deve essere un numero intero')
    .positive('Deve essere positivo'),

  {{campo_boolean}}: z.boolean().default(false),

  {{campo_enum}}: z.enum(['value1', 'value2', 'value3']),

  {{related_id}}: z.string().uuid().optional(),
})
// Refinements custom (opzionali)
.refine(
  (data) => {
    // Esempio: data futura
    if (data.{{data_field}}) {
      return new Date(data.{{data_field}}) > new Date()
    }
    return true
  },
  { message: 'La data deve essere futura', path: ['{{data_field}}'] }
)

/**
 * Schema per update
 * Tutti i campi sono opzionali (partial del create schema)
 */
export const update{{TableName}}Schema = create{{TableName}}Schema.partial()

/**
 * Schema per filtri/query params lista
 * Include: paginazione, sorting, search, filtri specifici
 */
export const {{tableName}}FiltersSchema = z.object({
  // Paginazione standard
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(25),

  // Sorting standard
  sort_by: z.enum([
    'created_at',
    'updated_at',
    '{{campo_sortabile1}}',
    '{{campo_sortabile2}}',
  ]).default('created_at'),
  sort_order: z.enum(['asc', 'desc']).default('desc'),

  // Ricerca full-text
  search: z.string().optional(),

  // Filtri specifici del modulo
  {{filtro_status}}: z.enum(['all', 'active', 'archived']).optional(),
  {{filtro_enum}}: z.enum(['value1', 'value2', 'value3']).optional(),
  {{filtro_related_id}}: z.string().uuid().optional(),
  {{filtro_data_from}}: z.string().datetime().optional(),
  {{filtro_data_to}}: z.string().datetime().optional(),
})

/**
 * Types derivati dagli schema
 * MAI duplicare types a mano — sempre derivare con z.infer
 */
export type {{TableName}} = z.infer<typeof {{tableName}}Schema>
export type Create{{TableName}} = z.infer<typeof create{{TableName}}Schema>
export type Update{{TableName}} = z.infer<typeof update{{TableName}}Schema>
export type {{TableName}}Filters = z.infer<typeof {{tableName}}FiltersSchema>

/**
 * Type helper per form (opzionale)
 * Utile quando il form ha campi aggiuntivi non presenti nel create schema
 */
export type {{TableName}}FormData = Create{{TableName}} & {
  // Campi aggiuntivi solo per il form (non salvati sul DB)
  {{campo_ui_only}}?: string
}
```

## Esempi validazioni comuni

### Stringhe
```ts
// Stringa obbligatoria con lunghezza
z.string().min(1, 'Obbligatorio').max(255).trim()

// Email
z.string().email('Email non valida').toLowerCase().trim()

// URL
z.string().url('URL non valido')

// Pattern custom (es. codice fiscale)
z.string().regex(/^[A-Z]{6}[0-9]{2}[A-Z][0-9]{2}[A-Z][0-9]{3}[A-Z]$/, 'Formato non valido')

// Enum
z.enum(['option1', 'option2', 'option3'])

// Stringa opzionale con transform per empty string
z.string().optional().transform(val => val || undefined)
```

### Numeri
```ts
// Numero intero positivo
z.coerce.number().int().positive()

// Numero con min/max
z.coerce.number().min(0).max(100)

// Numero decimale con precision
z.coerce.number().multipleOf(0.01) // 2 decimali
```

### Date
```ts
// Data ISO string
z.string().datetime()

// Data con validazione custom
z.string().datetime().refine(
  (val) => new Date(val) > new Date(),
  'La data deve essere futura'
)

// Data opzionale con default
z.string().datetime().optional().default(() => new Date().toISOString())
```

### Relazioni
```ts
// Foreign key UUID
z.string().uuid()

// Foreign key opzionale con sentinel per "nessuna selezione"
z.string().uuid().or(z.literal('_none')).optional()

// Array di foreign keys
z.array(z.string().uuid()).optional()
```

### Refinements complessi
```ts
// Validazione cross-field
z.object({
  start_date: z.string().datetime(),
  end_date: z.string().datetime(),
}).refine(
  (data) => new Date(data.end_date) > new Date(data.start_date),
  { message: 'End date deve essere dopo start date', path: ['end_date'] }
)

// Validazione condizionale
z.object({
  type: z.enum(['individual', 'company']),
  company_name: z.string().optional(),
}).refine(
  (data) => {
    if (data.type === 'company') {
      return !!data.company_name
    }
    return true
  },
  { message: 'Company name obbligatorio per tipo company', path: ['company_name'] }
)
```

## Export centralizzato

Nel file validators/index.ts, re-export tutti gli schema:

```ts
export * from './{{table-name}}'
export * from './{{another-table}}'
// ... altri export
```

## Uso negli endpoint API

```ts
// Server route
import { create{{TableName}}Schema } from '{{PATH_TO_VALIDATORS}}'

export default defineEventHandler(async (event) => {
  const body = await readBody(event)

  // Validazione con error handling
  const validated = create{{TableName}}Schema.parse(body)
  // Se la validazione fallisce, Zod lancia ZodError che Nuxt gestisce automaticamente

  // Usa validated data
  const { data, error } = await client
    .from('{{table_name}}')
    .insert(validated)

  // ...
})
```

## Uso nei form con vee-validate

```ts
// Component
import { useForm } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
import { create{{TableName}}Schema } from '{{PATH_TO_VALIDATORS}}'

const { handleSubmit, errors, values } = useForm({
  validationSchema: toTypedSchema(create{{TableName}}Schema),
  initialValues: {
    {{campo1}}: '',
    {{campo2}}: '',
    // ...
  }
})

const onSubmit = handleSubmit(async (formData) => {
  // formData è già validato e tipizzato come Create{{TableName}}
  await $fetch('/api/{{table-name}}', {
    method: 'POST',
    body: formData
  })
})
```

## Requisiti
- Validazione stringent: .trim() sui campi testo, .toLowerCase() su email
- Custom refinements per regole business complesse
- Error messages chiari e user-friendly in italiano
- Coercion con z.coerce.number() per query params
- Export sia schema che types
- Re-export da index.ts per import centralizzato
- Commenti JSDoc per schema complessi

## Anti-pattern da evitare
- NON duplicare types a mano — sempre usare z.infer
- NON dimenticare .trim() sulle stringhe
- NON usare z.any() — sempre tipizzare correttamente
- NON validare lato client diversamente da lato server — usa gli stessi schema
- NON dimenticare coerce per query params (arrivano come string)
- NON omettere error messages custom — i default di Zod sono in inglese e poco chiari
```
