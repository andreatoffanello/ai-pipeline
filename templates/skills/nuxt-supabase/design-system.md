# Skill: Design System & UI Patterns

> Pattern visivi e di interazione per garantire consistenza e qualità design "Awwwards-level" su tutto il progetto.
> Ispirato a: Linear, Notion, Attio.

**Quando usarla**: Ogni volta che si costruisce UI (layout, pagine, componenti custom).

**Input**: Tipo di elemento da costruire (pagina, componente, interazione).
**Output**: Specifiche visive precise con classi Tailwind e pattern di riferimento.

---

## PRINCIPI DESIGN

### Filosofia
- **Sottrazione**: togli finché non resta solo l'essenziale
- **Respiro**: spazio generoso tra gli elementi (padding/margin abbondanti)
- **Gerarchia**: un solo focal point per schermata
- **Movimento**: micro-animazioni per feedback, mai decorative

### Riferimenti
- **Linear**: sidebar compatta, command palette, transizioni veloci, tipografia pulita
- **Notion**: spazi ampi, content-first, hover reveal, inline editing
- **Attio**: data density intelligente, cards raffinate, palette sobria

---

## PALETTE COLORI

```css
/* === Light mode === */
--background: 0 0% 100%;           /* bianco */
--foreground: 240 10% 3.9%;        /* quasi nero */
--card: 0 0% 100%;                 /* uguale a bg in light */
--muted: 240 4.8% 95.9%;           /* grigio chiaro */
--muted-foreground: 240 3.8% 46.1%;
--border: 240 5.9% 90%;
--input: 240 5.9% 90%;

/* Accent: una tinta primaria, usata con parsimonia */
--primary: 240 5.9% 10%;           /* nero-blu profondo */
--primary-foreground: 0 0% 98%;

/* Feedback semantici */
--destructive: 0 84.2% 60.2%;      /* rosso */
--success: 142 76% 36%;            /* verde */
--warning: 38 92% 50%;             /* ambra */

/* === Dark mode — 3 livelli di elevazione === */
--background: 240 6% 6%;           /* base layer, NOT pure black */
--foreground: 0 0% 93%;            /* NOT pure white — reduces eye strain */
--card: 240 5% 8.5%;               /* elevated above background */
--popover: 240 5% 10%;             /* highest elevation (dropdowns, dialogs) */
--muted: 240 4% 14%;
--muted-foreground: 240 5% 58%;
--border: 240 4% 20%;              /* visible borders for separation */
--input: 240 3.7% 22%;             /* input borders slightly brighter */
--ring: 240 5% 50%;                /* visible focus ring */
```

> NON usare colori saturi come accent. L'accent è il nero/primario. I colori vivi si usano solo per status e feedback.

### CSS Architecture (CRITICAL)

I CSS variables **DEVONO** stare in un file separato caricato via `nuxt.config css[]` array.
**NON** metterli in `main.css` — il modulo Tailwind può droppare silenziosamente i blocchi `:root` e `.dark`.

```
assets/css/
  theme.css   ← CSS variables, base styles, dark mode overrides (loaded via nuxt.config css[])
  main.css    ← SOLO @tailwind base/components/utilities (processed by Tailwind module)
```

Esempio `theme.css`:
```css
:root {
  --background: 0 0% 100%;
  --foreground: 240 10% 3.9%;
  /* ... tutte le altre variabili light */
}

.dark {
  --background: 240 6% 6%;
  --foreground: 0 0% 93%;
  /* ... tutte le altre variabili dark */
}

/* Base styles globali */
body {
  @apply bg-background text-foreground;
  font-feature-settings: "rlig" 1, "calt" 1;
}
```

Esempio `main.css`:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

---

## TIPOGRAFIA

```
Font stack:
  sans: 'Inter', system-ui, sans-serif
  mono: 'JetBrains Mono', monospace

Gerarchia:
  Page title:   text-2xl font-semibold tracking-tight     (24px)
  Section:      text-lg font-medium                        (18px)
  Card title:   text-sm font-medium                        (14px)
  Body:         text-sm text-foreground                     (14px)
  Caption:      text-xs text-muted-foreground               (12px)
  Badge/Tag:    text-xs font-medium                         (12px)

Regola: quasi tutto è text-sm (14px). Le dimensioni grandi si usano solo per titoli di pagina.
```

---

## SPACING & LAYOUT

```
Spacing rhythm: 4px base (Tailwind default)

Page padding:        p-6 (24px)
Section gap:         gap-6 (24px)
Card padding:        p-4 o p-5 (16-20px)
Form gap:            gap-4 (16px)
Inline elements gap: gap-2 (8px)
Icon-text gap:       gap-2 (8px)

Content max-width:   max-w-7xl (per pagine lista)
                     max-w-3xl (per form/settings)
```

---

## PATTERN UI RICORRENTI

### Page Header
```vue
<div class="flex items-center justify-between">
  <div>
    <h1 class="text-2xl font-semibold tracking-tight">{{Titolo_Pagina}}</h1>
    <p class="text-sm text-muted-foreground">{{Descrizione_pagina}}</p>
  </div>
  <div class="flex items-center gap-2">
    <!-- Azioni secondarie a sinistra, primaria a destra -->
    <Button variant="outline" size="sm">
      <Upload class="mr-2 h-4 w-4" /> Import
    </Button>
    <Button size="sm">
      <Plus class="mr-2 h-4 w-4" /> {{Azione_primaria}}
    </Button>
  </div>
</div>
```

### Filter Bar (stile Linear)
```vue
<div class="flex items-center gap-2 py-2">
  <div class="relative flex-1 max-w-sm">
    <Search class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
    <Input
      class="pl-9 h-8 text-sm"
      placeholder="Cerca..."
    />
  </div>
  <Separator orientation="vertical" class="h-5" />
  <!-- Filter chips: visibili solo quando attivi -->
  <Button variant="ghost" size="sm" class="h-8 text-xs">
    <Filter class="mr-1 h-3 w-3" /> Status
  </Button>
  <Button variant="ghost" size="sm" class="h-8 text-xs">
    <SortAsc class="mr-1 h-3 w-3" /> Sort
  </Button>
</div>
```

### Data Table Row (stile Attio)
```vue
<!-- Riga con hover state raffinato e azioni reveal on hover -->
<tr class="group border-b transition-colors hover:bg-muted/50 cursor-pointer">
  <td class="p-3">
    <div class="flex items-center gap-3">
      <Avatar class="h-8 w-8" />
      <div>
        <p class="text-sm font-medium">{{Nome}}</p>
        <p class="text-xs text-muted-foreground">{{Sottotitolo}}</p>
      </div>
    </div>
  </td>
  <td class="p-3 text-sm text-muted-foreground">{{Campo}}</td>
  <td class="p-3">
    <Badge variant="secondary" class="text-xs">{{Status}}</Badge>
  </td>
  <!-- Azioni visibili solo on hover -->
  <td class="p-3 text-right">
    <div class="opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
      <Button variant="ghost" size="icon" class="h-7 w-7">
        <Pencil class="h-3.5 w-3.5" />
      </Button>
      <Button variant="ghost" size="icon" class="h-7 w-7">
        <MoreHorizontal class="h-3.5 w-3.5" />
      </Button>
    </div>
  </td>
</tr>
```

### Empty State (stile Notion)
```vue
<!-- Icona: h-6 w-6 (24px) in cerchio p-3 — NOT h-8/h-12 (too large, looks amateur) -->
<div class="flex flex-col items-center justify-center py-16 text-center">
  <div class="rounded-full bg-muted p-3 mb-4">
    <{{Icon}} class="h-6 w-6 text-muted-foreground" />
  </div>
  <h3 class="text-lg font-medium mb-1">{{Titolo_empty}}</h3>
  <p class="text-sm text-muted-foreground mb-4 max-w-sm">
    {{Descrizione_empty}}
  </p>
  <Button size="sm">
    <Plus class="mr-2 h-4 w-4" /> {{Azione_cta}}
  </Button>
</div>
```

### Skeleton Loading
```vue
<!-- Scheletro che rispetta la struttura della tabella/card -->
<div class="space-y-3">
  <div v-for="i in 5" :key="i" class="flex items-center gap-3 p-3">
    <Skeleton class="h-8 w-8 rounded-full" />
    <div class="space-y-1.5 flex-1">
      <Skeleton class="h-4 w-[180px]" />
      <Skeleton class="h-3 w-[120px]" />
    </div>
    <Skeleton class="h-5 w-[60px] rounded-full" />
  </div>
</div>
```

### Card Info (stile sidebar dettaglio)
```vue
<Card>
  <CardHeader class="pb-3">
    <CardTitle class="text-sm font-medium">{{Titolo_card}}</CardTitle>
  </CardHeader>
  <CardContent class="space-y-3">
    <!-- Riga info: label a sinistra, value a destra -->
    <div class="flex items-center justify-between">
      <span class="text-xs text-muted-foreground">{{Label}}</span>
      <span class="text-sm">{{Value}}</span>
    </div>
    <Separator />
    <div class="flex items-center justify-between">
      <span class="text-xs text-muted-foreground">{{Label}}</span>
      <span class="text-sm">{{Value}}</span>
    </div>
  </CardContent>
</Card>
```

---

## ANIMAZIONI E TRANSIZIONI

```
Durate:
  Micro (hover, focus):     150ms
  Standard (sheet, dialog): 200ms
  Navigazione (page):       250ms

Easing:
  Default:     ease-out
  Spring:      cubic-bezier(0.16, 1, 0.3, 1)   (per sheet/dialog)

Cosa animare:
  ✅ opacity (fade in/out)
  ✅ transform: translateY (slide up on enter)
  ✅ background-color (hover states)
  ✅ border-color (focus states)
  ❌ width/height (janky, evitare)
  ❌ margin/padding (causa reflow)

Pattern entrata elementi lista:
  Stagger: ogni elemento entra con 30ms di delay dal precedente
  Animazione: opacity 0→1 + translateY 4px→0
```

Esempio transition CSS:
```css
.fade-enter-active,
.fade-leave-active {
  transition: opacity 200ms ease-out;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.slide-up-enter-active {
  transition: all 200ms cubic-bezier(0.16, 1, 0.3, 1);
}

.slide-up-enter-from {
  opacity: 0;
  transform: translateY(4px);
}
```

---

## REGOLE DARK MODE

```
NON invertire semplicemente i colori. Il dark mode deve avere:

1. TRE LIVELLI DI ELEVAZIONE (non un unico grigio):
   - background (6%)  — base layer, pagina
   - card (8.5%)      — pannelli, sidebar info, tabelle
   - popover (10%)    — dropdown, dialog, sheet overlay

2. TESTO NON BIANCO PURO:
   - foreground: 93% (non 98/100%) — riduce affaticamento visivo
   - muted-foreground: 58% — leggibile ma distinto dal testo primario

3. BORDI VISIBILI:
   - --border: 20% — contrasto sufficiente su bg 6% per separazione
   - --input: 22% — input borders leggermente più chiari dei bordi normali

4. OMBRE ELIMINATE:
   - In dark mode box-shadow è invisibile. La separazione avviene SOLO tramite bordi.
   - Aggiungere in theme.css: .dark .shadow-soft { box-shadow: none; }

5. FOCUS RING VISIBILE:
   - --ring: 50% — deve essere ben visibile su sfondo 6%

6. FORM INPUT IN SHEET/DIALOG:
   - Input bg-background (6%) su card bg (8.5%) crea contrasto sufficiente
   - NON usare bg-card per input dentro card — diventa invisibile
```

---

## RESPONSIVE

```
Breakpoints (mobile-first):
  Default:  mobile (< 640px)
  sm:       tablet portrait (640px)
  md:       tablet landscape (768px)
  lg:       desktop (1024px)
  xl:       desktop large (1280px)

Sidebar:
  mobile:   hidden, attivabile con hamburger (Sheet component)
  lg+:      visibile, collapsible a icon-only

Layout 2 colonne (dettaglio):
  mobile:   stack verticale
  lg+:      grid-cols-5 (content 3/5 + sidebar 2/5)

Tabelle:
  mobile:   card list view (no tabella)
  md+:      tabella completa

Spacing:
  mobile:   p-4
  lg+:      p-6
```

Esempio layout responsive:
```vue
<template>
  <!-- Layout dettaglio 2 colonne -->
  <div class="grid grid-cols-1 lg:grid-cols-5 gap-4 lg:gap-6">
    <!-- Content principale -->
    <div class="lg:col-span-3">
      <!-- content -->
    </div>
    <!-- Sidebar -->
    <div class="lg:col-span-2">
      <!-- sidebar -->
    </div>
  </div>
</template>
```

---

## ANTI-PATTERN (cosa NON fare)

- **No bordi ovunque**: preferisci separazione con spacing, non con bordi (eccezione: dark mode, dove i bordi SERVONO)
- **No colori saturi come sfondo**: i colori vivi sono solo per badge di status
- **No ombre grosse**: max `shadow-soft`, in dark mode nessuna ombra (usa bordi)
- **No icone decorative**: ogni icona deve avere una funzione
- **No testo grande**: quasi tutto è `text-sm` — i titoli enormi sprecano spazio
- **No animazioni lente**: > 300ms sembra lento
- **No hover state su mobile**: usa `@media (hover: hover)` o classi `md:hover:`
- **No icone empty state giganti**: mai h-12/h-16, sempre `h-6 w-6` in cerchio `bg-muted p-3`
- **No CSS variables in main.css**: Tailwind può dropparle. Usare theme.css separato
- **No @apply in @layer base** per body/global styles: anche questi vengono droppati
- **No overflow-y-auto senza padding extra**: taglia i focus ring degli input. Usare `-mx-6 px-7` trick
- **No bg-card per input dentro card**: in dark mode bg-card (8.5%) e bg-background (6%) sono quasi uguali. Usare sempre `bg-background` per gli input

---

## CHECKLIST QUALITÀ UI

Prima di considerare completata una UI, verifica:

- [ ] Spacing consistente (usa solo valori standard: 2, 3, 4, 6, 8)
- [ ] Tipografia rispetta la gerarchia (text-sm per quasi tutto)
- [ ] Dark mode funziona senza strani contrast issues
- [ ] Responsive su mobile (test almeno 375px width)
- [ ] Loading states chiari (skeleton, spinner, disabled buttons)
- [ ] Empty states informativi con CTA
- [ ] Focus states visibili (ring su input, outline su button)
- [ ] Hover states raffinati (transition 150ms)
- [ ] Error states chiari con messaggi utili
- [ ] Icone 4x4 (16px) per inline, 5x5 (20px) per standalone
- [ ] No console.log/errors in browser console
- [ ] Accessibilità base (aria-labels dove serve, keyboard navigation)

---

## QUANDO DUBITARE

Se ti trovi a:
- Usare più di 3 colori diversi in una schermata → troppi colori
- Creare componenti > 150 righe → split in sotto-componenti
- Aggiungere bordi ovunque in dark mode → ok, in light mode valuta se serve
- Animare width/height → usa opacity/transform invece
- Fare animazioni > 300ms → troppo lento
- Usare text-lg+ per tutto → usa text-sm come base
- Mettere bg-card su input dentro card in dark mode → usa bg-background

**Regola d'oro**: quando in dubbio, togli. Meno è sempre meglio di più.
