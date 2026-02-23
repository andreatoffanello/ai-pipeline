# Conventions: Qualità del Codice

Standard di leggibilità e struttura obbligatori. Il codice deve essere
**human readable** — comprensibile da un altro sviluppatore senza commenti aggiuntivi.

## Principi fondamentali

- **Leggibile prima di tutto**: se devi scegliere tra clever e chiaro, scegli chiaro
- **Nomi descrittivi**: variabili, funzioni e file devono dire cosa sono/fanno
- **Funzioni piccole**: ogni funzione fa una cosa sola (max ~20 righe)
- **Componenti piccoli**: max ~200 righe per `.vue`. Se è più grande, splitta.
- **Commenti sul perché, non sul cosa**: il codice dice cosa fa, i commenti dicono perché

## Naming conventions

```
PascalCase    → Componenti Vue (MyComponent.vue), classi
camelCase     → variabili, funzioni, props, eventi, store names
kebab-case    → file non-componenti, CSS classes, eventi Vue ($emit)
UPPER_SNAKE   → costanti globali (MAX_RETRIES, DEFAULT_LOCALE)
use*          → composables (useAuth, useCart, useI18n)
*Store        → Pinia stores (useAuthStore, useCartStore)
on*           → event handlers (onClick, onSubmit, onKeydown)
is*/has*/can* → booleani (isLoading, hasError, canSubmit)
```

## Struttura file Vue

```
<script setup>   ← sempre prima
<template>       ← secondo
<style>          ← ultimo
```

Ordine interno dello `<script setup>`:
1. `definePageMeta` (solo nelle pagine)
2. `defineProps` + `defineEmits`
3. Store / composables esterni
4. `ref` e `reactive` (state locale)
5. `computed`
6. `watch` / `watchEffect`
7. Funzioni / handlers
8. `onMounted` / lifecycle hooks

## Commenti e JSDoc

```javascript
// Commento inline: spiega perché, non cosa
// ✅ Resettiamo la pagina perché i filtri cambiano il dataset totale
// ❌ Impostiamo page a 1

/**
 * Calcola il prezzo finale con sconti e tasse.
 * Non include i costi di spedizione (gestiti separatamente in CartStore).
 *
 * @param {Number} basePrice - Prezzo base in centesimi
 * @param {Number} discountPercent - Sconto in percentuale (0-100)
 * @param {Number} taxRate - Aliquota IVA (es. 0.22 per 22%)
 * @returns {Number} Prezzo finale in centesimi
 */
const calculateFinalPrice = (basePrice, discountPercent, taxRate) => {
    const discounted = basePrice * (1 - discountPercent / 100)
    return Math.round(discounted * (1 + taxRate))
}
```

## Struttura cartelle Nuxt

```
components/
  [Feature]/          ← componenti raggruppati per feature
    FeatureCard.vue
    FeatureList.vue
    FeatureForm.vue
composables/
  useFeature.js       ← logica riusabile
stores/
  useFeatureStore.js  ← Pinia store
pages/
  feature/
    index.vue         ← lista
    [id].vue          ← dettaglio
    new.vue           ← creazione
```

## Anti-pattern da evitare

❌ Nomi generici: `data`, `item`, `temp`, `foo`, `x`
✅ Nomi specifici: `userProfile`, `selectedProduct`, `cartTotal`

❌ Funzioni lunghe con più responsabilità
✅ Funzioni brevi, una responsabilità, nome descrittivo

❌ `v-if` e `v-for` sullo stesso elemento
✅ Usa un `<template>` wrapper per il `v-if`

❌ Logica complessa nel template
✅ Sposta in `computed` o funzione

❌ `console.log` dimenticati in produzione
✅ Rimuovi tutti i log di debug prima del commit

❌ Stringhe hardcoded visibili all'utente
✅ Chiavi i18n sempre (`$t('feature.title')`)
