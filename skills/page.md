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

## Pagina di test Playwright (obbligatoria)

Per ogni feature implementata, crea una pagina di test in `pages/__test__/`:

```vue
<!--
  Pagina Test: nome-feature

  Pagina di test per Playwright. Mostra tutte le varianti/stati
  del componente/feature con elementi data-testid per l'automazione.
-->
<script setup>
definePageMeta({ layout: false }) // nessun layout per isolare il componente

// Stato interattivo per simulare scenari di test
const counter = ref(0)
const isLoading = ref(false)
const hasError = ref(false)
const isEmpty = ref(false)

/** Simula loading state per 2 secondi */
const simulateLoading = async () => {
    isLoading.value = true
    await new Promise((resolve) => setTimeout(resolve, 2000))
    isLoading.value = false
}
</script>

<template>
    <div class="test-page" data-testid="test-nome-feature">

        <section class="test-section" data-testid="section-default">
            <h2>Stato default</h2>
            <!-- Componente nello stato normale -->
            <NomeComponente data-testid="component-default" />
        </section>

        <section class="test-section" data-testid="section-interactive">
            <h2>Interazione</h2>
            <button data-testid="btn-action" @click="counter++">
                Azione ({{ counter }})
            </button>
            <span data-testid="result-counter">{{ counter }}</span>
        </section>

        <section class="test-section" data-testid="section-states">
            <h2>Stati</h2>
            <button data-testid="btn-loading" @click="simulateLoading">
                Simula loading
            </button>
            <button data-testid="btn-error" @click="hasError = !hasError">
                Toggle error
            </button>
            <button data-testid="btn-empty" @click="isEmpty = !isEmpty">
                Toggle empty
            </button>

            <NomeComponente
                :loading="isLoading"
                :error="hasError ? 'Errore simulato' : null"
                :empty="isEmpty"
                data-testid="component-states"
            />
        </section>

    </div>
</template>

<style lang="scss" scoped>
.test-page {
    padding: var(--space-xl);
    display: flex;
    flex-direction: column;
    gap: var(--space-2xl);
}

.test-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-md);
    padding: var(--space-lg);
    border: 0.1rem dashed var(--color-border);
    border-radius: var(--radius-md);

    h2 {
        font-size: var(--text-sm);
        color: var(--color-text-light);
        text-transform: uppercase;
        letter-spacing: 0.1em;
    }
}
</style>
```

### Regole pagina test

- `layout: false` per isolare il componente da header/sidebar
- `data-testid` su ogni elemento interattivo e su ogni stato
- Mostra tutte le varianti del componente nella stessa pagina
- Includi controlli per simulare ogni stato (loading, error, empty)
- Stato visibile (counter, testo che cambia) per verificare interazioni
- Path: `pages/__test__/nome-feature.vue`
- Accessibile su: `http://localhost:3000/__test__/nome-feature`
