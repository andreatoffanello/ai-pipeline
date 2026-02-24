# Conventions: Stack Tecnologico

Queste sono le convenzioni obbligatorie per ogni progetto che usa questa pipeline.
Leggi questo file integralmente prima di scrivere qualsiasi codice.

## Framework e librerie

- **Nuxt 4** — framework principale. Usa `definePageMeta`, `useRoute`, `useRouter`,
  `useFetch`, `useAsyncData` dalle auto-import di Nuxt. Non importare da 'vue' o 'nuxt/app'
  se non strettamente necessario.
- **Vue 3 Composition API** — SEMPRE `<script setup>`. Mai Options API.
- **Pinia** — state management. Vedi `ai-pipeline/skills/store.md` per il pattern obbligatorio.
- **VueUse** — utility composables. Prima di scrivere un composable custom, verifica
  se esiste già in VueUse (`useLocalStorage`, `useDebounce`, `useDark`, `useEventListener`, ecc.)
- **@nuxtjs/i18n** — internazionalizzazione. Usa `useI18n()` e `$t()`. Tutte le stringhe
  visibili all'utente devono usare chiavi i18n, mai testo hardcoded.

## Linguaggio

- **JavaScript ES6+** — NO TypeScript. File `.js` e `.vue`, mai `.ts` o `.tsx`.
- **JSDoc obbligatorio** per:
  - Ogni `defineProps()` — `@param` per ogni prop
  - Ogni `defineEmits()` — `@event` per ogni evento
  - Ogni funzione/composable/action non banale — `@param`, `@returns`
  - Store: ogni action e computed complesso
- **Arrow functions** `() =>` per callbacks e funzioni inline.
  Funzioni nominate con `function` solo se necessario hoisting.

## Auto-import Nuxt

Non usare import espliciti per:
- `ref`, `computed`, `watch`, `watchEffect`, `onMounted`, `onUnmounted` (Vue)
- `defineStore`, `storeToRefs` (Pinia — se configurato)
- Composables in `composables/`
- Componenti in `components/`
- Utils in `utils/`

## Regole generali

- **YAGNI**: implementa solo ciò che serve adesso
- **DRY**: se copi-incolli 2 volte, estrai un composable o utility
- **No magic numbers**: usa costanti con nome descrittivo
- **Async/await** sempre, mai `.then().catch()` a catena
- **Error handling**: ogni async function deve avere try/catch con `error.value`
