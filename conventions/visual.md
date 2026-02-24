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
var(--color-orange)            /* #F97316 — priorità alta, status blocked */
var(--color-code-bg)           /* #0f0f11 — sfondo code block (tema scuro fisso, non responsivo al dark mode) */
var(--color-code-text)         /* #e2e8f0 — testo code block (tema scuro fisso, non responsivo al dark mode) */
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

var(--font-sans)  /* Inter, system-ui, sans-serif — font principale */
var(--font-mono)  /* JetBrains Mono, Fira Code, monospace — codice e dati numerici */
```

### Border Radius

```css
var(--radius-xs)   /* 0.4rem — chip, badge */
var(--radius-sm)   /* 0.8rem — input */
var(--radius-md)   /* 1.6rem — card, dialog */
var(--radius-lg)   /* 2.4rem — modal, drawer */
var(--radius-full) /* 9999px — pill, avatar */
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
