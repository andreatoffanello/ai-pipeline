# Skill: Pinia Store (Composition API)

Pattern obbligatorio per creare store Pinia nel progetto.
Leggi questo file integralmente prima di creare o modificare uno store.

## Template completo

```javascript
// stores/useNomeStore.js

/**
 * Store per la gestione di [entità/dominio].
 *
 * Gestisce lo stato, il caricamento e le operazioni CRUD
 * per [descrizione del contesto d'uso].
 */
export const useNomeStore = defineStore('nome', () => {

    // ─── State ───────────────────────────────────────────────────────────────
    const items = ref([])
    const currentItem = ref(null)
    const loading = ref(false)
    const error = ref(null)

    // Pagination (includi solo se serve paginazione)
    const pagination = ref({
        page: 1,
        perPage: 25,
        total: 0,
        totalPages: 0,
    })

    // Filters (includi solo se serve filtraggio)
    const filters = ref({
        search: '',
        sortBy: 'name',
        sortOrder: 'asc',
    })

    // ─── Computed ─────────────────────────────────────────────────────────────
    const hasItems = computed(() => items.value.length > 0)
    const isEmpty = computed(() => !loading.value && items.value.length === 0)
    const isFirstPage = computed(() => pagination.value.page === 1)
    const isLastPage = computed(() => pagination.value.page >= pagination.value.totalPages)

    // ─── Actions ──────────────────────────────────────────────────────────────

    /**
     * Recupera la lista degli elementi.
     * Gestisce loading state e errori.
     */
    const fetchItems = async () => {
        loading.value = true
        error.value = null
        try {
            const response = await $fetch('/api/items', {
                params: {
                    page: pagination.value.page,
                    perPage: pagination.value.perPage,
                    ...filters.value,
                },
            })
            items.value = response.data
            pagination.value.total = response.total
            pagination.value.totalPages = response.totalPages
        } catch (e) {
            error.value = e.message || 'Errore nel caricamento'
            console.error('fetchItems:', e)
        } finally {
            loading.value = false
        }
    }

    /**
     * Recupera un singolo elemento per ID.
     * @param {String|Number} id - ID dell'elemento
     */
    const fetchItem = async (id) => {
        loading.value = true
        error.value = null
        try {
            currentItem.value = await $fetch(`/api/items/${id}`)
        } catch (e) {
            error.value = e.message || 'Elemento non trovato'
            console.error('fetchItem:', e)
        } finally {
            loading.value = false
        }
    }

    /**
     * Imposta la pagina corrente e ricarica i dati.
     * @param {Number} page - Numero di pagina (1-based)
     */
    const setPage = (page) => {
        pagination.value.page = page
        fetchItems()
    }

    /**
     * Aggiorna i filtri e resetta alla pagina 1.
     * Resetta perché i filtri cambiano il dataset totale.
     * @param {Object} newFilters - Filtri da aggiornare (merge parziale)
     */
    const setFilters = (newFilters) => {
        Object.assign(filters.value, newFilters)
        pagination.value.page = 1
        fetchItems()
    }

    /**
     * Resetta filtri e paginazione ai valori iniziali.
     */
    const resetFilters = () => {
        filters.value = { search: '', sortBy: 'name', sortOrder: 'asc' }
        pagination.value.page = 1
        fetchItems()
    }

    /**
     * Pulisce lo stato dello store.
     * Chiama su onUnmounted() se lo store non deve persistere tra navigazioni.
     */
    const $reset = () => {
        items.value = []
        currentItem.value = null
        loading.value = false
        error.value = null
        pagination.value = { page: 1, perPage: 25, total: 0, totalPages: 0 }
        filters.value = { search: '', sortBy: 'name', sortOrder: 'asc' }
    }

    return {
        // State (esponi tutto per trasparenza)
        items,
        currentItem,
        loading,
        error,
        pagination,
        filters,
        // Computed
        hasItems,
        isEmpty,
        isFirstPage,
        isLastPage,
        // Actions
        fetchItems,
        fetchItem,
        setPage,
        setFilters,
        resetFilters,
        $reset,
    }
})
```

## Utilizzo nel componente

```vue
<script setup>
const store = useNomeStore()

// storeToRefs() per mantenere la reattività quando si destruttura
const { items, loading, isEmpty, error, pagination } = storeToRefs(store)

onMounted(() => {
    store.fetchItems()
})

// Pulisci solo se lo store non deve persistere tra navigazioni
onUnmounted(() => {
    store.$reset()
})
</script>

<template>
    <div v-if="loading">Caricamento...</div>
    <div v-else-if="error">{{ error }}</div>
    <div v-else-if="isEmpty">Nessun elemento</div>
    <div v-else>
        <div v-for="item in items" :key="item.id">{{ item.name }}</div>
    </div>
</template>
```

## Regole obbligatorie

- SEMPRE `ref()` e `computed()` — MAI `state:`, `getters:`, `actions:` (Options API)
- SEMPRE `storeToRefs()` per destrutturare stato reattivo nei componenti
- SEMPRE gestire `loading` e `error` nelle actions async
- SEMPRE `try/catch/finally` con `loading.value = false` nel `finally`
- JSDoc su ogni action e computed non banale
- Reset pagination a `page = 1` quando i filtri cambiano
- `$reset()` disponibile per pulizia controllata
- Nome file: `useNomeStore.js` (camelCase, prefisso `use`, estensione `.js` non `.ts`)
- ID store: stringa kebab-case in `defineStore('nome-store', ...)`

## Anti-pattern

❌ `defineStore('nome', { state: () => ({}) })` → ✅ Composition API con `() =>`
❌ `const { items } = store` → ✅ `const { items } = storeToRefs(store)`
❌ Action senza try/catch → ✅ sempre try/catch/finally
❌ `import { ref } from 'vue'` → ✅ auto-imported in Nuxt
❌ File TypeScript `.ts` → ✅ JavaScript `.js` con JSDoc
