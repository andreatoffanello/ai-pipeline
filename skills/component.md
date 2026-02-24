# Skill: Componente Vue

Guida per creare o modificare componenti Vue 3 in un progetto Nuxt 4.
Leggi questo file integralmente prima di scrivere qualsiasi componente.

## Struttura obbligatoria

Il file `.vue` segue SEMPRE questo ordine: `<script setup>` → `<template>` → `<style>`.

```vue
<!--
  NomeComponente

  Descrizione di cosa fa, quando usarlo, varianti supportate.
  Max 3 righe.
-->
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
    /* CSS custom properties interne per varianti facilmente sovrascrivibili */
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

    /* Varianti di dimensione */
    &.sm { --height: auto; --padding: var(--space-sm); --font-size: var(--text-sm); }
    &.lg { --height: 4.8rem; --padding: var(--space-lg); --font-size: var(--text-lg); }

    /* Stati */
    &:hover:not(.disabled) { --border-color: var(--color-main); }
    &:focus-visible { outline: 2px solid var(--color-main); outline-offset: 2px; }
    &.disabled { opacity: 0.5; pointer-events: none; }
}
</style>
```

## Checklist obbligatoria

Prima di considerare il componente completo, verifica ogni punto:

- [ ] Commento descrittivo in cima al file (cosa fa, quando usarlo)
- [ ] JSDoc con `@param` per ogni prop e `@event` per ogni evento
- [ ] `defineProps()` con `type` e `default` per ogni prop
- [ ] `defineEmits()` dichiarato esplicitamente
- [ ] CSS custom properties interne (`--height`, `--padding`, ecc.) per varianti
- [ ] Solo design tokens CSS (vedi `ai-pipeline/conventions/visual.md`) — zero valori hardcoded
- [ ] `<style lang="scss" scoped>`
- [ ] Squircle progressive enhancement (`@supports (corner-shape: squircle)`)
- [ ] Hover state con `--border-color: var(--color-main)` o equivalente
- [ ] Focus-visible state accessibile
- [ ] Disabled state con `opacity: 0.5` + `pointer-events: none`
- [ ] Bordi `0.1rem solid` (mai `1px`)
- [ ] Icone: `<span class="material-symbols-outlined">nome_icona</span>`
- [ ] Max ~200 righe totali — se più grande, splitta in sotto-componenti

## Anti-pattern

❌ `style="color: blue"` → ✅ `color: var(--color-main)`
❌ `padding: 16px` → ✅ `padding: var(--space-md)`
❌ `border-radius: 8px` → ✅ `border-radius: var(--radius-sm)`
❌ `import { ref } from 'vue'` → ✅ auto-imported in Nuxt, non serve
❌ Options API (`data()`, `methods:`) → ✅ `<script setup>` sempre
❌ TypeScript (`.ts`, tipi inline) → ✅ JavaScript + JSDoc
❌ Logica complessa nel template → ✅ sposta in `computed` o funzione
❌ `v-if` e `v-for` sullo stesso elemento → ✅ usa `<template v-if>` wrapper
❌ Testo hardcoded visibile → ✅ chiavi i18n con `$t('chiave')`
