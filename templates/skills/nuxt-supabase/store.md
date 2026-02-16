# Skill: Pinia Store Generator

> Genera Pinia store in Composition API per un modulo con gestione completa di stato, paginazione, filtri e operazioni CRUD con optimistic updates.

**Quando usarla**: Ogni volta che serve uno store per un modulo con operazioni CRUD.

**Input**: Nome modulo, tipo dei dati, operazioni necessarie.
**Output**: Pinia store completo in Composition API.

---

## Prompt

```
## Obiettivo
Genera il Pinia store per il modulo: {{MODULE_NAME}}

## Tipo dati
{{INCOLLA_TYPE_TYPESCRIPT_ENTITY}}

## Cosa generare

Crea il file stores/use{{Module}}Store.ts:

```ts
import { defineStore } from 'pinia'

export const use{{Module}}Store = defineStore('{{module}}', () => {
  // === STATE ===
  const items = ref<{{Type}}[]>([])
  const currentItem = ref<{{Type}} | null>(null)
  const isLoading = ref(false)
  const error = ref<string | null>(null)

  // Paginazione
  const meta = ref({
    total: 0,
    page: 1,
    perPage: 25,
    totalPages: 0
  })

  // Filtri
  const filters = ref({
    search: '',
    sortBy: 'created_at',
    sortOrder: 'desc' as 'asc' | 'desc',
    // ... filtri specifici del modulo
  })

  // === GETTERS (computed) ===
  const hasItems = computed(() => items.value.length > 0)
  const isEmpty = computed(() => !isLoading.value && !hasItems.value)
  const isFirstPage = computed(() => meta.value.page === 1)
  const isLastPage = computed(() => meta.value.page >= meta.value.totalPages)

  // ... getter specifici del modulo (es. filtri attivi, conteggi, aggregazioni)

  // === ACTIONS ===

  /**
   * Fetch lista con filtri e paginazione correnti
   */
  async function fetchItems() {
    isLoading.value = true
    error.value = null
    try {
      const params = new URLSearchParams({
        page: meta.value.page.toString(),
        per_page: meta.value.perPage.toString(),
        sort_by: filters.value.sortBy,
        sort_order: filters.value.sortOrder,
        ...(filters.value.search && { search: filters.value.search }),
        // ... altri filtri specifici
      })

      const response = await $fetch(`/api/{{module}}?${params}`)
      items.value = response.data
      meta.value = response.meta
    } catch (e: any) {
      error.value = e.message
      throw e
    } finally {
      isLoading.value = false
    }
  }

  /**
   * Fetch singolo item per dettaglio
   */
  async function fetchItem(id: string) {
    isLoading.value = true
    error.value = null
    try {
      const response = await $fetch(`/api/{{module}}/${id}`)
      currentItem.value = response.data
      return response.data
    } catch (e: any) {
      error.value = e.message
      throw e
    } finally {
      isLoading.value = false
    }
  }

  /**
   * Crea nuovo item con optimistic update
   */
  async function createItem(data: Create{{Type}}) {
    try {
      const response = await $fetch('/api/{{module}}', {
        method: 'POST',
        body: data
      })
      // Optimistic: aggiungi in cima alla lista
      items.value.unshift(response.data)
      meta.value.total += 1
      return response.data
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'Create failed'
      throw e
    }
  }

  /**
   * Aggiorna item con optimistic update e rollback on error
   */
  async function updateItem(id: string, data: Partial<{{Type}}>) {
    // Optimistic update
    const index = items.value.findIndex(i => i.id === id)
    const previous = index >= 0 ? { ...items.value[index] } : null

    if (index >= 0) {
      items.value[index] = { ...items.value[index], ...data }
    }
    if (currentItem.value?.id === id) {
      currentItem.value = { ...currentItem.value, ...data }
    }

    try {
      const response = await $fetch(`/api/{{module}}/${id}`, {
        method: 'PUT',
        body: data
      })

      // Aggiorna con i dati reali dal server
      if (index >= 0) items.value[index] = response.data
      if (currentItem.value?.id === id) currentItem.value = response.data

      return response.data
    } catch (e) {
      // Rollback optimistic update
      if (index >= 0 && previous) {
        items.value[index] = previous
      }
      if (currentItem.value?.id === id && previous) {
        currentItem.value = previous as {{Type}}
      }
      error.value = e instanceof Error ? e.message : 'Update failed'
      throw e
    }
  }

  /**
   * Elimina item con optimistic update e rollback on error
   */
  async function deleteItem(id: string) {
    const index = items.value.findIndex(i => i.id === id)
    const previous = index >= 0 ? items.value[index] : null

    // Optimistic delete
    if (index >= 0) {
      items.value.splice(index, 1)
      meta.value.total -= 1
    }

    try {
      await $fetch(`/api/{{module}}/${id}`, { method: 'DELETE' })

      // Se era l'ultimo item della pagina e non siamo alla prima, torna indietro
      if (items.value.length === 0 && meta.value.page > 1) {
        setPage(meta.value.page - 1)
      }
    } catch (e) {
      // Rollback optimistic delete
      if (previous && index >= 0) {
        items.value.splice(index, 0, previous)
        meta.value.total += 1
      }
      error.value = e instanceof Error ? e.message : 'Delete failed'
      throw e
    }
  }

  /**
   * Cambia pagina e ricarica
   */
  function setPage(page: number) {
    meta.value.page = page
    fetchItems()
  }

  /**
   * Aggiorna filtri e ricarica dalla prima pagina
   */
  function setFilters(newFilters: Partial<typeof filters.value>) {
    Object.assign(filters.value, newFilters)
    meta.value.page = 1 // Reset to first page
    fetchItems()
  }

  /**
   * Reset filtri ai valori default
   */
  function resetFilters() {
    filters.value = {
      search: '',
      sortBy: 'created_at',
      sortOrder: 'desc',
      // ... reset filtri specifici
    }
    meta.value.page = 1
    fetchItems()
  }

  /**
   * Reset completo dello stato (utile per cleanup on unmount)
   */
  function $reset() {
    items.value = []
    currentItem.value = null
    isLoading.value = false
    error.value = null
    meta.value = { total: 0, page: 1, perPage: 25, totalPages: 0 }
    filters.value = { search: '', sortBy: 'created_at', sortOrder: 'desc' }
  }

  return {
    // State
    items,
    currentItem,
    isLoading,
    error,
    meta,
    filters,

    // Getters
    hasItems,
    isEmpty,
    isFirstPage,
    isLastPage,

    // Actions
    fetchItems,
    fetchItem,
    createItem,
    updateItem,
    deleteItem,
    setPage,
    setFilters,
    resetFilters,
    $reset,
  }
})
```

## Pattern avanzati

### Watch sui filtri per auto-refetch (opzionale)
```ts
// Nel composable o nella pagina che usa lo store:
const store = use{{Module}}Store()
const { filters } = storeToRefs(store)

// Debounced watch sul search
watchDebounced(
  () => filters.value.search,
  () => store.fetchItems(),
  { debounce: 300 }
)

// Immediate watch su altri filtri
watch(
  () => filters.value.status,
  () => store.fetchItems(),
  { immediate: false }
)
```

### Gestione cache locale (opzionale)
```ts
// Aggiungi al return dello store:
const itemsById = computed(() =>
  Object.fromEntries(items.value.map(item => [item.id, item]))
)

function getItemFromCache(id: string) {
  return itemsById.value[id] || null
}

// Uso:
const cachedItem = store.getItemFromCache(id)
if (cachedItem) {
  // usa cache
} else {
  await store.fetchItem(id)
}
```

## Requisiti
- Composition API (setup function syntax con `() => { ... }`)
- Optimistic updates con rollback on error per tutte le mutazioni
- Loading e error state gestiti correttamente
- Paginazione e filtri integrati e sincronizzati
- TypeScript strict: types per state, params, responses
- Nessun uso di `any`
- Export pulito: solo stato reattivo e funzioni pubbliche
- Naming consistente: `fetchItems`, `createItem`, `updateItem`, `deleteItem`

## Anti-pattern da evitare
- NON usare Options API (state/getters/actions)
- NON fare mutazioni dirette senza optimistic update
- NON dimenticare il rollback in caso di errore
- NON usare `items.push()` per create — usa `unshift()` per aggiungere in cima
- NON dimenticare di resettare alla pagina 1 quando cambiano i filtri
```
