# Poster App — Design Document
**Date:** 2026-02-19
**Stack:** Nuxt 4, Nuxt UI v3, Composition API, Canvas API
**Location:** `apps/poster-app/`

## Overview

Single-page web app per creare poster scaricabili con citazioni su sfondi mesh/gradient/noise. Editor live con canvas centrale, pannelli laterali per i controlli. Export PNG via Canvas API nativa. Nessun backend.

## Architecture

```
apps/poster-app/
├── app.vue
├── pages/index.vue
├── composables/
│   ├── useCanvas.ts       # rendering canvas + exportPNG()
│   └── usePoster.ts       # stato reattivo globale
├── components/
│   ├── PosterCanvas.vue   # canvas + live preview
│   ├── PanelLeft.vue      # controlli testo + tipografia
│   └── PanelRight.vue     # controlli sfondo + dimensioni
└── nuxt.config.ts
```

## Data Model

```ts
// usePoster.ts
quote: string
attribution: string
fontSize: number           // 24-120px
fontFamily: string         // Playfair Display | Inter | DM Serif Display | Fraunces
textAlign: 'left' | 'center' | 'right'
textColor: string          // hex

preset: 'aurora' | 'mesh' | 'noise' | 'dusk'
primaryColor: string
secondaryColor: string
noiseIntensity: number     // 0-100

width: number              // default 1080
height: number             // default 1080
padding: number            // 40-120px
```

## Canvas Rendering (useCanvas.ts)

- Watch su tutto lo stato poster → ridisegna automaticamente
- Background: gradient/mesh via `createLinearGradient` / `createRadialGradient` composti
- Noise: generazione procedurale su offscreen canvas (ImageData pixel manipulation)
- Testo: `wrapText()` helper per word-wrap manuale, posizionamento centrato
- Export: `canvas.toDataURL('image/png')` → link download programmatico

## UI Layout

Layout full-viewport a 3 colonne:
- **Left panel** (320px): font picker, size slider, alignment, color, quote textarea, attribution input
- **Center**: canvas preview scalato per stare nello spazio disponibile (CSS `object-fit: contain`)
- **Right panel** (280px): preset selector (4 card visive), color pickers, noise slider, width/height inputs, padding slider, bottone Download

## Preset Backgrounds

| Preset | Tecnica |
|--------|---------|
| `aurora` | 2 radial gradient sovrapposti, colori freddi (teal/violet) |
| `mesh` | 4+ radial gradient in posizioni diverse, blend mode multiply |
| `noise` | solid color + noise grain overlay |
| `dusk` | linear gradient diagonale warm (orange/pink/purple) |

## Design Language

- Stile: dark UI, minimal, alta qualità — awwwards-level
- Font UI: Inter
- Sfondo app: `#0a0a0a`
- Pannelli: `#111111` con border sottile `#1f1f1f`
- Accent: bianco puro per interazioni primarie
- Transizioni canvas: 16ms debounce su watch per smoothness
