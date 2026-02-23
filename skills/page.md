# Skill: Pagina Nuxt

Pattern per creare pagine nelle app Nuxt 4.
Leggi questo file integralmente prima di creare o modificare una pagina.

## Template pagina lista

```vue
<!--
  Pagina Lista [Entità]

  Visualizza la lista di [entità] con ricerca, filtri e paginazione.
  Gestisce stati: loading, error, empty, populated.
-->
<script setup>
definePageMeta({
    layout: 'default', // adatta al layout del progetto
})

const store = useNomeStore()
const { items, loading, isEmpty, error, pagination } = storeToRefs(store)

/** Ricerca locale client-side (alternativa: delegare allo store con setFilters) */
const searchQuery = ref('')

const filteredItems = computed(() => {
    if (!searchQuery.value) return items.value
    const q = searchQuery.value.toLowerCase()
    return items.value.filter((item) =>
        item.name.toLowerCase().includes(q)
    )
})

onMounted(() => {
    store.fetchItems()
})
</script>

<template>
    <div class="page-container">

        <!-- Header: titolo + azione primaria -->
        <header class="page-header">
            <h1 class="text-xl bold">{{ $t('pagina.titolo') }}</h1>
            <Button icon-left="add" @click="router.push('/entita/new')">
                {{ $t('pagina.cta_nuovo') }}
            </Button>
        </header>

        <!-- Filtri / ricerca -->
        <div class="page-filters">
            <input
                v-model="searchQuery"
                class="search-input"
                :placeholder="$t('comune.cerca')"
                data-testid="search-input"
            />
        </div>

        <!-- Loading state -->
        <div v-if="loading" class="page-state" data-testid="state-loading">
            <span class="spinner" />
            <p>{{ $t('comune.caricamento') }}</p>
        </div>

        <!-- Error state -->
        <div v-else-if="error" class="page-state page-state--error" data-testid="state-error">
            <span class="material-symbols-outlined">error</span>
            <p>{{ error }}</p>
            <button class="btn-retry" @click="store.fetchItems()">
                {{ $t('comune.riprova') }}
            </button>
        </div>

        <!-- Empty state -->
        <div v-else-if="isEmpty" class="page-state page-state--empty" data-testid="state-empty">
            <span class="material-symbols-outlined">inbox</span>
            <p>{{ $t('pagina.vuoto_messaggio') }}</p>
            <Button icon-left="add" @click="router.push('/entita/new')">
                {{ $t('pagina.cta_primo') }}
            </Button>
        </div>

        <!-- Content -->
        <div v-else class="page-content" data-testid="content-list">
            <div
                v-for="item in filteredItems"
                :key="item.id"
                class="list-item"
                data-testid="list-item"
                @click="router.push(`/entita/${item.id}`)"
            >
                {{ item.name }}
            </div>
        </div>

    </div>
</template>

<style lang="scss" scoped>
.page-container {
    padding: var(--space-xl);
    max-width: 120rem;
    margin: 0 auto;
}

.page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: var(--space-xl);
}

.page-filters {
    display: flex;
    gap: var(--space-md);
    margin-bottom: var(--space-lg);
}

.page-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-md);
    padding: var(--space-4xl) 0;
    text-align: center;

    .material-symbols-outlined {
        font-size: 4.8rem;
        color: var(--color-text-light);
    }

    p {
        font-size: var(--text-2md);
        color: var(--color-text-light);
    }

    &--error .material-symbols-outlined { color: var(--color-error); }
}

.page-content {
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
}

.list-item {
    padding: var(--space-md);
    background: var(--color-background-white);
    border: 0.1rem solid var(--color-border);
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: all 0.15s var(--ease);

    @supports (corner-shape: squircle) {
        border-radius: var(--radius-lg);
        corner-shape: squircle;
    }

    &:hover {
        border-color: var(--color-main);
        background: var(--color-background-hover);
    }
}
</style>
```

## Checklist pagina

- [ ] `definePageMeta()` con layout corretto
- [ ] Store con `storeToRefs()` per stato reattivo
- [ ] `onMounted()` per fetch iniziale dati
- [ ] **Loading state** visibile con `data-testid="state-loading"`
- [ ] **Error state** con messaggio + retry con `data-testid="state-error"`
- [ ] **Empty state** con icona + messaggio + CTA con `data-testid="state-empty"`
- [ ] **Content** con `data-testid="content-list"`
- [ ] Header con titolo (i18n) + azione primaria
- [ ] Tutti i testi via `$t()` — zero stringhe hardcoded
- [ ] CSS con design tokens (zero valori hardcoded)
- [ ] Responsive (max-width + padding)
- [ ] Dark mode automatica (se usi design tokens)

## data-testid sulle pagine reali

Aggiungi `data-testid` direttamente sugli elementi interattivi delle pagine reali
della feature — il QA li usa per interagire con precisione tramite Playwright.

```vue
<!-- Esempi di data-testid sulle pagine reali -->
<button data-testid="btn-submit" @click="onSubmit">{{ $t('action.save') }}</button>
<input data-testid="input-name" v-model="name" />
<div data-testid="state-empty" v-if="isEmpty">...</div>
<div data-testid="state-loading" v-if="isLoading">...</div>
<div data-testid="content-list" v-else>...</div>
```

### Regole data-testid

- Aggiungi `data-testid` su tutti gli elementi interattivi: bottoni, input, link, dropdown
- Aggiungi `data-testid` sui contenitori di stato: loading, empty, error, populated
- Usa nomi descrittivi con prefisso: `btn-*`, `input-*`, `state-*`, `content-*`
- Mai su elementi puramente decorativi
