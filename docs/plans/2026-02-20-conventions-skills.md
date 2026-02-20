# Conventions & Skills System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Aggiungere a `ai-pipeline` un sistema di conventions e skills Nuxt 4 opinionated, leggibili dagli agenti via `Read` tool, referenziate esplicitamente nei prompt di ogni step.

**Architecture:** Directory `conventions/` per regole fisse di stack/stile/qualità, directory `skills/` per guide operative per tipo di artefatto (componente, store, pagina, test). I prompt di ogni step dichiarano esplicitamente quali file leggere prima di operare. Nessuna modifica alla pipeline bash.

**Tech Stack:** Markdown, Nuxt 4, Vue 3 Composition API, Pinia, VueUse, nuxt-i18n, Playwright, JSDoc

---

## Struttura finale

```
ai-pipeline/
  conventions/
    stack.md          # Nuxt4, Pinia, VueUse, i18n, no TS, JSDoc, ES6
    visual.md         # awwwards quality, design tokens, animazioni, qualità visiva
    code.md           # leggibilità, naming, YAGNI, struttura file, commenti
  skills/
    component.md      # struttura Vue SFC, checklist, anti-pattern
    store.md          # Pinia composition API, template completo, gRPC pattern
    page.md           # pattern pagina Nuxt, stati loading/error/empty, test page
    playwright.md     # test visivi reali, screenshot, data-testid, asserzioni visive
  example/prompts/    # prompt aggiornati che referenziano conventions e skills
    pm.md
    dr-spec.md
    dev.md
    qa.md
  prompts/            # (stub minimale lasciato, utente copierà da example/)
```

---

### Task 1: `conventions/stack.md`

**Files:**
- Create: `conventions/stack.md`

**Step 1: Crea il file**

```markdown
# Conventions: Stack Tecnologico

Queste sono le convenzioni obbligatorie per ogni progetto che usa questa pipeline.
Leggi questo file integralmente prima di scrivere qualsiasi codice.

## Framework e librerie

- **Nuxt 4** — framework principale. Usa `definePageMeta`, `useRoute`, `useRouter`,
  `useFetch`, `useAsyncData` dalle auto-import di Nuxt. Non importare da 'vue' o 'nuxt/app'
  se non strettamente necessario.
- **Vue 3 Composition API** — SEMPRE `<script setup>`. Mai Options API.
- **Pinia** — state management. Vedi `skills/store.md` per il pattern obbligatorio.
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
```

**Step 2: Commit**

```bash
git add conventions/stack.md
git commit -m "feat: add conventions/stack.md — Nuxt4, Pinia, VueUse, i18n, JSDoc"
```

---

### Task 2: `conventions/visual.md`

**Files:**
- Create: `conventions/visual.md`

**Step 1: Crea il file**

```markdown
# Conventions: Qualità Visiva

Standard visivi obbligatori. Ogni UI prodotta da questa pipeline deve essere
a livello awwwards — non "funzionante", ma **eccellente**.

## Filosofia

- **Meno è più**: rimuovi elementi finché non resta solo l'essenziale
- **Spaziatura generosa**: lo spazio bianco è design, non spreco
- **Un punto focale per schermata**: guida l'occhio dell'utente
- **Micro-animazioni con scopo**: ogni transizione comunica un cambio di stato,
  non è decorazione
- **Tipografia come gerarchia**: dimensioni, pesi e spaziature creano struttura visiva

## Design tokens obbligatori

Non usare MAI valori hardcoded per colori, spazi, radius, font-size.
Usa SEMPRE i CSS custom properties del design system:

### Colori
```css
var(--color-main)              /* azioni primarie, link, focus */
var(--color-main-light)        /* background hover, badge, chip */
var(--color-background-white)  /* background principale */
var(--color-background-alt)    /* sidebar, header, stripe */
var(--color-background-hover)  /* hover su elementi interattivi */
var(--color-border)            /* bordi, separatori */
var(--color-text)              /* testo principale */
var(--color-text-light)        /* testo secondario, placeholder */
var(--color-text-white)        /* testo su sfondo scuro */
var(--color-success)           /* #00B900 */
var(--color-error)             /* #E00000 */
var(--color-warning)           /* #DBB900 */
```

### Spacing (griglia 4px)
```css
var(--space-xs)   /* 0.4rem — gap minimi */
var(--space-sm)   /* 0.8rem — gap tra elementi piccoli */
var(--space-md)   /* 1.6rem — gap standard, padding card */
var(--space-lg)   /* 2.4rem — padding sezioni */
var(--space-xl)   /* 3.2rem — padding pagina */
var(--space-2xl)  /* 4.8rem — gap tra sezioni */
var(--space-3xl)  /* 6.4rem — spaziatura hero */
var(--space-4xl)  /* 9.6rem — spaziatura massima */
```

### Typography
```css
var(--text-xs)    /* 0.8rem — badge, counter */
var(--text-sm)    /* 1.2rem — etichette, meta, caption */
var(--text-md)    /* 1.4rem — testo base (body) */
var(--text-2md)   /* 1.8rem — sottotitoli */
var(--text-lg)    /* 2.2rem — titoli sezione */
var(--text-xl)    /* 3.2rem — titoli pagina */
var(--text-2xl)   /* 4rem — hero */
var(--text-3xl)   /* 5.6rem — hero grande */
```

### Border Radius
```css
var(--radius-xs)  /* 0.4rem — chip, badge */
var(--radius-sm)  /* 0.8rem — input */
var(--radius-md)  /* 1.6rem — card, dialog */
var(--radius-lg)  /* 2.4rem — modal, drawer */
var(--radius-full)/* 9999px — pill, avatar */
```

### Transizioni
```css
var(--ease)       /* cubic-bezier standard — usa sempre questo */
/* Durata: 0.15s per micro-interazioni, 0.25s per pannelli, 0.4s per modal */
transition: all 0.15s var(--ease);
```

## Regole CSS obbligatorie

- `<style lang="scss" scoped>` sempre
- Bordi: `0.1rem solid var(--color-border)` — mai `1px`
- Border radius con progressive enhancement:
  ```scss
  border-radius: var(--radius-md);
  @supports (corner-shape: squircle) {
      border-radius: var(--radius-lg);
      corner-shape: squircle;
  }
  ```
- CSS custom properties interne al componente per varianti:
  ```scss
  .component {
      --height: 3.6rem;
      --padding: var(--space-md);
      height: var(--height);
      padding: var(--padding);
      &.sm { --height: 2.8rem; --padding: var(--space-sm); }
  }
  ```
- Dark mode: supportato automaticamente via `[data-color-mode="dark"]`
  se usi i design tokens. Non aggiungere media queries manuali.

## Anti-pattern visivi

❌ `color: blue` → ✅ `color: var(--color-main)`
❌ `padding: 16px` → ✅ `padding: var(--space-md)`
❌ `border-radius: 8px` → ✅ `border-radius: var(--radius-sm)`
❌ `transition: 0.3s` → ✅ `transition: all 0.15s var(--ease)`
❌ `font-size: 14px` → ✅ `font-size: var(--text-md)`
❌ Layout senza hover state → ✅ ogni elemento interattivo ha hover+focus
❌ Icone come immagini → ✅ `<span class="material-symbols-outlined">icon_name</span>`

## Checklist qualità visiva minima

Prima di completare qualsiasi UI, verifica:
- [ ] Tutti i valori CSS usano design tokens (zero hardcoded)
- [ ] Hover state su ogni elemento interattivo
- [ ] Focus state accessibile (outline visibile)
- [ ] Transizioni su tutti i cambi di stato
- [ ] Empty state, loading state, error state gestiti
- [ ] Responsive (almeno mobile + desktop)
- [ ] Dark mode funzionante (se design tokens usati, è automatico)
- [ ] Squircle progressive enhancement applicato
```

**Step 2: Commit**

```bash
git add conventions/visual.md
git commit -m "feat: add conventions/visual.md — awwwards quality, design tokens, CSS rules"
```

---

### Task 3: `conventions/code.md`

**Files:**
- Create: `conventions/code.md`

**Step 1: Crea il file**

```markdown
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
  __test__/
    feature.vue       ← pagina test Playwright
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
```

**Step 2: Commit**

```bash
git add conventions/code.md
git commit -m "feat: add conventions/code.md — naming, structure, readability rules"
```

---

### Task 4: `skills/component.md`

**Files:**
- Create: `skills/component.md`

**Step 1: Crea il file** (adattato da ebus-cloud-nuxt con convenzioni generiche)

```markdown
# Skill: Componente Vue

Guida per creare o modificare componenti Vue 3 in un progetto Nuxt 4.

## Struttura obbligatoria

```vue
/**
 * ComponenteName
 *
 * Descrizione di cosa fa, quando usarlo, varianti supportate.
 * Max 3 righe.
 */
<script setup>
/**
 * @param {String} variant - Variante stilistica ('primary'|'secondary'|'ghost')
 * @param {String} size - Dimensione ('sm'|'md'|'lg')
 * @param {Boolean} disabled - Disabilita le interazioni
 */
const props = defineProps({
    variant: { type: String, default: 'primary' },
    size:    { type: String, default: 'md' },
    disabled:{ type: Boolean, default: false },
})

/**
 * @event click - Emesso al click (non emesso se disabled)
 * @event change - Emesso al cambio di valore
 */
const emit = defineEmits(['click', 'change'])
</script>

<template>
    <div
        class="component-name"
        :class="[variant, size, { disabled }]"
    >
        <slot />
    </div>
</template>

<style lang="scss" scoped>
.component-name {
    /* CSS custom properties interne per varianti */
    --height: 3.6rem;
    --padding: var(--space-md);
    --font-size: var(--text-md);
    --bg: var(--color-background-white);
    --border-color: var(--color-border);

    display: flex;
    align-items: center;
    gap: var(--space-sm);
    height: var(--height);
    padding: var(--padding);
    font-size: var(--font-size);
    background: var(--bg);
    border: 0.1rem solid var(--border-color);
    border-radius: var(--radius-md);
    transition: all 0.15s var(--ease);

    @supports (corner-shape: squircle) {
        border-radius: var(--radius-lg);
        corner-shape: squircle;
    }

    &.sm { --height: auto; --padding: var(--space-sm); --font-size: var(--text-sm); }
    &.lg { --height: 4.8rem; --padding: var(--space-lg); --font-size: var(--text-lg); }

    &:hover:not(.disabled) { --border-color: var(--color-main); }
    &:focus-visible { outline: 2px solid var(--color-main); outline-offset: 2px; }
    &.disabled { opacity: 0.5; pointer-events: none; }
}
</style>
```

## Checklist

- [ ] JSDoc con `@param` per ogni prop e `@event` per ogni evento
- [ ] `defineProps()` con `type` e `default` per ogni prop
- [ ] `defineEmits()` dichiarato esplicitamente
- [ ] CSS custom properties interne (`--height`, `--padding`, ecc.)
- [ ] Design tokens dal design system (vedi `conventions/visual.md`)
- [ ] `<style lang="scss" scoped>`
- [ ] Squircle progressive enhancement
- [ ] Hover state + focus-visible state
- [ ] Disabled state con `pointer-events: none`
- [ ] Bordi `0.1rem solid` (non `1px`)
- [ ] Icone: `<span class="material-symbols-outlined">nome</span>`
- [ ] Max ~200 righe — se più grande, splitta in sotto-componenti

## Anti-pattern

❌ `style="color: blue"` → ✅ `color: var(--color-main)`
❌ `padding: 16px` → ✅ `padding: var(--space-md)`
❌ `import { ref } from 'vue'` → ✅ auto-imported in Nuxt
❌ Options API → ✅ `<script setup>` sempre
❌ TypeScript → ✅ JavaScript + JSDoc
❌ Logica complessa nel template → ✅ sposta in `computed`
```

**Step 2: Commit**

```bash
git add skills/component.md
git commit -m "feat: add skills/component.md — Vue SFC structure, checklist, anti-patterns"
```

---

### Task 5: `skills/store.md`

**Files:**
- Create: `skills/store.md`

**Step 1: Crea il file**

(Template Pinia Composition API con sezioni: State, Computed, Actions, utilizzo nei componenti, regole, anti-pattern)

Contenuto: adattamento di `ebus-cloud-nuxt/ai-context/skills/store.md` reso generico (senza riferimenti a gRPC specifici di ebus, ma mantenendo il pattern gRPC come sezione opzionale).

**Step 2: Commit**

```bash
git add skills/store.md
git commit -m "feat: add skills/store.md — Pinia composition API template"
```

---

### Task 6: `skills/page.md`

**Files:**
- Create: `skills/page.md`

**Step 1: Crea il file**

(Pattern pagina Nuxt: lista, dettaglio, form. Stati loading/error/empty. Pattern pagina test `__test__/` per Playwright con `data-testid`.)

**Step 2: Commit**

```bash
git add skills/page.md
git commit -m "feat: add skills/page.md — Nuxt page patterns, states, test page structure"
```

---

### Task 7: `skills/playwright.md`

**Files:**
- Create: `skills/playwright.md`

**Step 1: Crea il file**

```markdown
# Skill: Test Visivi con Playwright

Guida per lo step QA. I test devono essere **reali** — non leggere solo il codice,
ma navigare l'app, interagire con i componenti, fare screenshot e verificare visivamente.

## Setup

```javascript
// Naviga alla pagina di test (non alla pagina di produzione)
await page.goto('http://localhost:3000/__test__/nome-feature')
await page.waitForLoadState('networkidle')
```

## Struttura test visivo

```javascript
import { test, expect } from '@playwright/test'

test('ComponenteName — stato default', async ({ page }) => {
    await page.goto('http://localhost:3000/__test__/nome-feature')
    await page.waitForLoadState('networkidle')

    // Screenshot baseline
    await expect(page).toHaveScreenshot('component-default.png', {
        maxDiffPixelRatio: 0.02,  // tolleranza 2%
    })
})

test('ComponenteName — interazione click', async ({ page }) => {
    await page.goto('http://localhost:3000/__test__/nome-feature')

    const btn = page.getByTestId('btn-action')
    await expect(btn).toBeVisible()

    await btn.click()

    // Verifica cambio di stato visibile
    await expect(page.getByTestId('result-text')).toHaveText('Clicked: 1')

    // Screenshot dopo interazione
    await expect(page).toHaveScreenshot('component-after-click.png')
})
```

## Selezione elementi

Preferenza in ordine:
1. `page.getByTestId('nome')` — usa `data-testid` nel componente
2. `page.getByRole('button', { name: 'Salva' })` — semantico
3. `page.getByText('testo esatto')` — per testo
4. `page.locator('.classe')` — ultimo resort

## Verifiche visive obbligatorie per step QA

Per ogni criterio di accettazione della feature, verifica:

1. **Stato iniziale** — la pagina si carica correttamente
2. **Interazione** — ogni elemento interattivo risponde
3. **Feedback visivo** — hover, focus, active states visibili
4. **Loading state** — se ci sono dati asincroni, mostra spinner
5. **Error state** — se la chiamata API fallisce, mostra errore
6. **Empty state** — se non ci sono dati, mostra empty state
7. **Responsive** — verifica a 375px (mobile) e 1440px (desktop)
8. **Dark mode** — se supportato

```javascript
// Test responsive
test('ComponenteName — mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 })
    await page.goto('http://localhost:3000/__test__/nome-feature')
    await expect(page).toHaveScreenshot('component-mobile.png')
})

// Test dark mode
test('ComponenteName — dark mode', async ({ page }) => {
    await page.goto('http://localhost:3000/__test__/nome-feature')
    await page.evaluate(() => {
        document.documentElement.setAttribute('data-color-mode', 'dark')
    })
    await expect(page).toHaveScreenshot('component-dark.png')
})
```

## Criteri qualità visiva awwwards

Quando fai gli screenshot, verifica manualmente:
- [ ] Spaziatura consistente (usa design tokens, non valori arbitrari)
- [ ] Tipografia gerarchica (dimensioni comunicano importanza)
- [ ] Transizioni fluide (non brusche)
- [ ] Hover state chiari
- [ ] Focus state accessibile e visibile
- [ ] Nessun elemento "tagliato" o overflow non intenzionale
- [ ] Allineamenti precisi (usa gap e flexbox, non margin arbitrari)

## Report QA

Nel file `qa/${FEATURE}-qa.md`, per ogni test visivo includi:
- Path dello screenshot: `screenshots/feature-stato.png`
- Viewport testato
- Risultato PASS/FAIL con motivazione specifica
- Se FAIL: descrizione esatta del problema visivo
```

**Step 2: Commit**

```bash
git add skills/playwright.md
git commit -m "feat: add skills/playwright.md — visual testing, screenshots, awwwards criteria"
```

---

### Task 8: Aggiorna `example/prompts/pm.md`

**Files:**
- Modify: `example/prompts/pm.md`

**Step 1: Aggiungi sezione conventions**

Aggiungi in cima al file, dopo il titolo:

```markdown
## Prima di iniziare

Leggi questi file di contesto:
- `ai-pipeline/conventions/stack.md` — stack tecnologico del progetto
- `ai-pipeline/conventions/code.md` — standard di qualità del codice

Usa queste informazioni per scrivere criteri di accettazione e note tecniche
coerenti con il progetto reale.
```

**Step 2: Commit**

```bash
git add example/prompts/pm.md
git commit -m "feat: pm prompt reads conventions before writing spec"
```

---

### Task 9: Aggiorna `example/prompts/dr-spec.md`

**Files:**
- Modify: `example/prompts/dr-spec.md`

**Step 1: Aggiungi sezione conventions**

```markdown
## Prima di iniziare

Leggi questi file di contesto:
- `ai-pipeline/conventions/stack.md` — verifica che la specifica sia compatibile con lo stack
- `ai-pipeline/conventions/code.md` — verifica che i criteri di accettazione siano verificabili
```

**Step 2: Commit**

```bash
git add example/prompts/dr-spec.md
git commit -m "feat: dr-spec prompt reads conventions before review"
```

---

### Task 10: Aggiorna `example/prompts/dev.md`

**Files:**
- Modify: `example/prompts/dev.md`

**Step 1: Riscrivi con conventions e skills**

```markdown
# DEV — Developer

Sei uno sviluppatore senior. Il tuo compito è implementare la feature: ${FEATURE}.

## Prima di iniziare

Leggi questi file nell'ordine indicato:

1. `ai-pipeline/conventions/stack.md` — stack e regole obbligatorie
2. `ai-pipeline/conventions/visual.md` — standard visivi awwwards
3. `ai-pipeline/conventions/code.md` — qualità e leggibilità del codice
4. `ai-pipeline/skills/component.md` — se crei/modifichi componenti Vue
5. `ai-pipeline/skills/store.md` — se crei/modifichi Pinia store
6. `ai-pipeline/skills/page.md` — se crei/modifichi pagine Nuxt

Poi leggi la specifica della feature: `specs/${FEATURE}.md`

## Istruzioni

1. Esplora il codebase per capire la struttura esistente (`Glob`, `Read`)
2. Identifica i file da creare/modificare
3. Implementa seguendo ESATTAMENTE le conventions e skills lette
4. Crea la pagina di test in `pages/__test__/${FEATURE}.vue` con `data-testid`
   su ogni elemento interattivo (necessaria per il QA Playwright)

## Vincoli

- Non modificare file fuori dallo scope della feature
- Zero TypeScript — solo JavaScript con JSDoc
- Zero valori CSS hardcoded — solo design tokens
- Zero stringhe hardcoded — solo chiavi i18n
- Ogni componente creato: checklist di `skills/component.md` completata
- Ogni store creato: template di `skills/store.md` seguito
- Max ~200 righe per file `.vue` — se più grande, splitta
```

**Step 2: Commit**

```bash
git add example/prompts/dev.md
git commit -m "feat: dev prompt reads all conventions and skills before implementing"
```

---

### Task 11: Aggiorna `example/prompts/qa.md`

**Files:**
- Modify: `example/prompts/qa.md`

**Step 1: Riscrivi con skill playwright**

```markdown
# QA — Quality Assurance

Sei un QA Engineer. Il tuo compito è verificare la feature: ${FEATURE}.

## Prima di iniziare

Leggi questi file:
1. `ai-pipeline/skills/playwright.md` — come eseguire test visivi reali
2. `ai-pipeline/conventions/visual.md` — criteri qualità visiva awwwards
3. `specs/${FEATURE}.md` — criteri di accettazione da verificare

## Istruzioni

**Non leggere solo il codice.** Usa Playwright per navigare l'app e verificare
visivamente ogni criterio.

1. Avvia il dev server se non è attivo (`npm run dev` o verifica porta 3000)
2. Naviga a `http://localhost:3000/__test__/${FEATURE}` — la pagina di test
3. Per ogni criterio di accettazione in `specs/${FEATURE}.md`:
   - Interagisci con l'UI
   - Fai uno screenshot
   - Verifica visivamente la qualità (checklist in `skills/playwright.md`)
4. Testa anche: mobile (375px), dark mode, stati loading/error/empty

## Output Report

Scrivi il report in: `qa/${FEATURE}-qa.md`

Includi per ogni criterio:
- **Risultato**: PASS / FAIL
- **Come verificato**: URL, azione eseguita, screenshot path
- **Qualità visiva**: rispetta i criteri awwwards? (spaziatura, hover, transizioni)
- **Note**: se FAIL, descrizione esatta del problema

(La gate instruction verrà aggiunta automaticamente dalla pipeline)
```

**Step 2: Commit**

```bash
git add example/prompts/qa.md
git commit -m "feat: qa prompt uses playwright skill and visual quality criteria"
```

---

### Task 12: Aggiorna `docs/STATUS.md` e commit finale

**Files:**
- Modify: `docs/STATUS.md`

**Step 1: Aggiorna la sezione struttura e pending**

Aggiungi le nuove directory `conventions/` e `skills/` alla struttura,
marca Task 11 come completato, aggiorna il pending con:
- "Test reale con ANTHROPIC_API_KEY" come unico pending rimasto

**Step 2: Commit**

```bash
git add docs/STATUS.md
git commit -m "docs: update STATUS.md — conventions/skills system complete"
```
