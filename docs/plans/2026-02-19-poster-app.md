# Poster App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a single-page Nuxt 4 web app where users create and download custom quote posters with mesh/gradient/noise backgrounds via a live canvas editor.

**Architecture:** Single-page editor with 3-column layout (left panel controls, center canvas preview, right panel style/size). State managed by `usePoster` composable, canvas rendering by `useCanvas` composable. Pure client-side, Canvas API for rendering and PNG export.

**Tech Stack:** Nuxt 4, Nuxt UI v3, Vue 3 Composition API, Canvas API (native), no backend

---

### Task 1: Scaffold Nuxt 4 project

**Files:**
- Create: `apps/poster-app/` (directory)

**Step 1: Scaffold the project**

```bash
cd /Users/andreatoffanello/GitHub/ai-pipeline/apps
npx nuxi@latest init poster-app --package-manager pnpm
cd poster-app
```

When prompted: select "No" for git init (already in a repo).

**Step 2: Install Nuxt UI v3**

```bash
pnpm add @nuxt/ui
```

**Step 3: Update nuxt.config.ts**

Replace contents of `apps/poster-app/nuxt.config.ts`:

```ts
export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  devtools: { enabled: true },
  modules: ['@nuxt/ui'],
  css: ['~/assets/css/main.css'],
  ssr: false,
  app: {
    head: {
      link: [
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,700;1,400&family=Inter:wght@300;400;500&family=DM+Serif+Display:ital@0;1&family=Fraunces:ital,wght@0,300;0,700;1,300&display=swap'
        }
      ]
    }
  }
})
```

**Step 4: Create main CSS**

Create `apps/poster-app/assets/css/main.css`:

```css
*, *::before, *::after {
  box-sizing: border-box;
}

html, body, #__nuxt {
  margin: 0;
  padding: 0;
  width: 100%;
  height: 100%;
  background: #0a0a0a;
  color: #ffffff;
  font-family: 'Inter', sans-serif;
  overflow: hidden;
}
```

**Step 5: Delete default files**

```bash
rm -rf apps/poster-app/app.vue 2>/dev/null; true
```

Create `apps/poster-app/app.vue`:

```vue
<template>
  <UApp>
    <NuxtPage />
  </UApp>
</template>
```

**Step 6: Verify dev server starts**

```bash
cd apps/poster-app && pnpm dev
```

Expected: Nuxt dev server on http://localhost:3000 with no errors.

**Step 7: Commit**

```bash
git add apps/poster-app/
git commit -m "feat: scaffold poster-app with Nuxt 4 + Nuxt UI v3"
```

---

### Task 2: usePoster composable (state)

**Files:**
- Create: `apps/poster-app/composables/usePoster.ts`

**Step 1: Create the composable**

Create `apps/poster-app/composables/usePoster.ts`:

```ts
export type TextAlign = 'left' | 'center' | 'right'
export type Preset = 'aurora' | 'mesh' | 'noise' | 'dusk'
export type FontFamily = 'Playfair Display' | 'Inter' | 'DM Serif Display' | 'Fraunces'

export interface PosterState {
  // Text
  quote: string
  attribution: string
  fontSize: number
  fontFamily: FontFamily
  textAlign: TextAlign
  textColor: string
  // Background
  preset: Preset
  primaryColor: string
  secondaryColor: string
  noiseIntensity: number
  // Dimensions
  width: number
  height: number
  padding: number
}

const state = reactive<PosterState>({
  quote: 'The impediment to action advances action. What stands in the way becomes the way.',
  attribution: '— Marcus Aurelius',
  fontSize: 48,
  fontFamily: 'Playfair Display',
  textAlign: 'center',
  textColor: '#ffffff',
  preset: 'aurora',
  primaryColor: '#00c6ff',
  secondaryColor: '#7b2ff7',
  noiseIntensity: 30,
  width: 1080,
  height: 1080,
  padding: 80,
})

export function usePoster() {
  return { state }
}
```

**Step 2: Verify no TypeScript errors**

```bash
cd apps/poster-app && npx nuxi typecheck
```

Expected: No errors.

**Step 3: Commit**

```bash
git add apps/poster-app/composables/usePoster.ts
git commit -m "feat: add usePoster composable with reactive state"
```

---

### Task 3: useCanvas composable (rendering engine)

**Files:**
- Create: `apps/poster-app/composables/useCanvas.ts`

**Step 1: Create the composable**

Create `apps/poster-app/composables/useCanvas.ts`:

```ts
import { usePoster, type Preset } from './usePoster'

function generateNoise(ctx: CanvasRenderingContext2D, width: number, height: number, intensity: number) {
  const imageData = ctx.createImageData(width, height)
  const data = imageData.data
  for (let i = 0; i < data.length; i += 4) {
    const value = Math.random() * 255
    data[i] = value
    data[i + 1] = value
    data[i + 2] = value
    data[i + 3] = (intensity / 100) * 60
  }
  ctx.putImageData(imageData, 0, 0)
}

function drawBackground(ctx: CanvasRenderingContext2D, width: number, height: number, preset: Preset, primary: string, secondary: string, noiseIntensity: number) {
  ctx.clearRect(0, 0, width, height)

  if (preset === 'aurora') {
    const base = ctx.createLinearGradient(0, 0, width, height)
    base.addColorStop(0, '#0a0a0f')
    base.addColorStop(1, '#0a0a0f')
    ctx.fillStyle = base
    ctx.fillRect(0, 0, width, height)

    const g1 = ctx.createRadialGradient(width * 0.3, height * 0.3, 0, width * 0.3, height * 0.3, width * 0.7)
    g1.addColorStop(0, primary + 'cc')
    g1.addColorStop(1, 'transparent')
    ctx.fillStyle = g1
    ctx.fillRect(0, 0, width, height)

    const g2 = ctx.createRadialGradient(width * 0.7, height * 0.7, 0, width * 0.7, height * 0.7, width * 0.6)
    g2.addColorStop(0, secondary + 'aa')
    g2.addColorStop(1, 'transparent')
    ctx.fillStyle = g2
    ctx.fillRect(0, 0, width, height)

  } else if (preset === 'mesh') {
    ctx.fillStyle = '#080808'
    ctx.fillRect(0, 0, width, height)

    const positions = [[0.2, 0.2], [0.8, 0.2], [0.5, 0.5], [0.2, 0.8], [0.8, 0.8]]
    const colors = [primary, secondary, primary + '88', secondary + '88', primary + '66']
    positions.forEach(([x, y], i) => {
      const g = ctx.createRadialGradient(width * x, height * y, 0, width * x, height * y, width * 0.5)
      g.addColorStop(0, colors[i])
      g.addColorStop(1, 'transparent')
      ctx.globalCompositeOperation = 'screen'
      ctx.fillStyle = g
      ctx.fillRect(0, 0, width, height)
    })
    ctx.globalCompositeOperation = 'source-over'

  } else if (preset === 'noise') {
    const grad = ctx.createLinearGradient(0, 0, 0, height)
    grad.addColorStop(0, primary)
    grad.addColorStop(1, secondary)
    ctx.fillStyle = grad
    ctx.fillRect(0, 0, width, height)

  } else if (preset === 'dusk') {
    const grad = ctx.createLinearGradient(width * 0.2, 0, width * 0.8, height)
    grad.addColorStop(0, primary)
    grad.addColorStop(0.5, secondary)
    grad.addColorStop(1, '#1a0033')
    ctx.fillStyle = grad
    ctx.fillRect(0, 0, width, height)
  }

  // Always apply noise overlay
  generateNoise(ctx, width, height, noiseIntensity)
}

function wrapText(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string[] {
  const words = text.split(' ')
  const lines: string[] = []
  let current = ''

  for (const word of words) {
    const test = current ? `${current} ${word}` : word
    if (ctx.measureText(test).width > maxWidth) {
      if (current) lines.push(current)
      current = word
    } else {
      current = test
    }
  }
  if (current) lines.push(current)
  return lines
}

function drawText(ctx: CanvasRenderingContext2D, quote: string, attribution: string, fontSize: number, fontFamily: string, textAlign: string, textColor: string, width: number, height: number, padding: number) {
  ctx.fillStyle = textColor
  ctx.textAlign = textAlign as CanvasTextAlign

  const maxWidth = width - padding * 2
  const x = textAlign === 'left' ? padding : textAlign === 'right' ? width - padding : width / 2

  // Quote text
  ctx.font = `${fontSize}px '${fontFamily}', serif`
  const lines = wrapText(ctx, quote, maxWidth)
  const lineHeight = fontSize * 1.35
  const totalQuoteHeight = lines.length * lineHeight

  // Attribution
  const attrFontSize = Math.max(fontSize * 0.4, 18)
  ctx.font = `${attrFontSize}px '${fontFamily}', serif`
  const attrHeight = attrFontSize * 1.5

  const totalHeight = totalQuoteHeight + attrHeight + fontSize * 0.8
  let y = (height - totalHeight) / 2 + lineHeight

  // Draw quote lines
  ctx.font = `${fontSize}px '${fontFamily}', serif`
  for (const line of lines) {
    ctx.fillText(line, x, y)
    y += lineHeight
  }

  // Draw attribution
  y += fontSize * 0.4
  ctx.font = `300 ${attrFontSize}px 'Inter', sans-serif`
  ctx.globalAlpha = 0.7
  ctx.fillText(attribution, x, y)
  ctx.globalAlpha = 1
}

export function useCanvas() {
  const { state } = usePoster()
  const canvasRef = ref<HTMLCanvasElement | null>(null)

  function render() {
    const canvas = canvasRef.value
    if (!canvas) return
    canvas.width = state.width
    canvas.height = state.height
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    drawBackground(ctx, state.width, state.height, state.preset, state.primaryColor, state.secondaryColor, state.noiseIntensity)
    drawText(ctx, state.quote, state.attribution, state.fontSize, state.fontFamily, state.textAlign, state.textColor, state.width, state.height, state.padding)
  }

  function exportPNG() {
    const canvas = canvasRef.value
    if (!canvas) return
    const link = document.createElement('a')
    link.download = 'poster.png'
    link.href = canvas.toDataURL('image/png')
    link.click()
  }

  let rafId: number | null = null
  watch(
    () => ({ ...state }),
    () => {
      if (rafId) cancelAnimationFrame(rafId)
      rafId = requestAnimationFrame(render)
    },
    { deep: true }
  )

  onMounted(() => render())

  return { canvasRef, render, exportPNG }
}
```

**Step 2: Commit**

```bash
git add apps/poster-app/composables/useCanvas.ts
git commit -m "feat: add useCanvas composable with background rendering and text layout"
```

---

### Task 4: PosterCanvas component

**Files:**
- Create: `apps/poster-app/components/PosterCanvas.vue`

**Step 1: Create the component**

Create `apps/poster-app/components/PosterCanvas.vue`:

```vue
<script setup lang="ts">
import { useCanvas } from '~/composables/useCanvas'
import { usePoster } from '~/composables/usePoster'

const { canvasRef } = useCanvas()
const { state } = usePoster()
</script>

<template>
  <div class="canvas-wrapper">
    <canvas
      ref="canvasRef"
      :width="state.width"
      :height="state.height"
      class="poster-canvas"
    />
  </div>
</template>

<style scoped>
.canvas-wrapper {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  padding: 32px;
}

.poster-canvas {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
  box-shadow: 0 32px 80px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255,255,255,0.05);
  border-radius: 2px;
}
</style>
```

**Step 2: Commit**

```bash
git add apps/poster-app/components/PosterCanvas.vue
git commit -m "feat: add PosterCanvas component"
```

---

### Task 5: PanelLeft component (text controls)

**Files:**
- Create: `apps/poster-app/components/PanelLeft.vue`

**Step 1: Create the component**

Create `apps/poster-app/components/PanelLeft.vue`:

```vue
<script setup lang="ts">
import { usePoster, type FontFamily, type TextAlign } from '~/composables/usePoster'

const { state } = usePoster()

const fontOptions: { label: string; value: FontFamily }[] = [
  { label: 'Playfair Display', value: 'Playfair Display' },
  { label: 'Inter', value: 'Inter' },
  { label: 'DM Serif Display', value: 'DM Serif Display' },
  { label: 'Fraunces', value: 'Fraunces' },
]

const alignOptions: { icon: string; value: TextAlign }[] = [
  { icon: 'i-lucide-align-left', value: 'left' },
  { icon: 'i-lucide-align-center', value: 'center' },
  { icon: 'i-lucide-align-right', value: 'right' },
]
</script>

<template>
  <aside class="panel panel-left">
    <div class="panel-header">
      <span class="panel-title">Typography</span>
    </div>

    <div class="panel-body">
      <!-- Quote -->
      <div class="field">
        <label class="field-label">Quote</label>
        <UTextarea
          v-model="state.quote"
          :rows="5"
          placeholder="Enter your quote..."
          class="field-input"
        />
      </div>

      <!-- Attribution -->
      <div class="field">
        <label class="field-label">Attribution</label>
        <UInput
          v-model="state.attribution"
          placeholder="— Author Name"
          class="field-input"
        />
      </div>

      <!-- Font Family -->
      <div class="field">
        <label class="field-label">Font</label>
        <USelect
          v-model="state.fontFamily"
          :items="fontOptions"
          value-key="value"
          label-key="label"
          class="field-input"
        />
      </div>

      <!-- Font Size -->
      <div class="field">
        <label class="field-label">
          Size
          <span class="field-value">{{ state.fontSize }}px</span>
        </label>
        <input
          v-model.number="state.fontSize"
          type="range"
          min="24"
          max="120"
          step="2"
          class="slider"
        />
      </div>

      <!-- Text Align -->
      <div class="field">
        <label class="field-label">Alignment</label>
        <div class="button-group">
          <button
            v-for="opt in alignOptions"
            :key="opt.value"
            :class="['align-btn', { active: state.textAlign === opt.value }]"
            @click="state.textAlign = opt.value"
          >
            <UIcon :name="opt.icon" class="icon" />
          </button>
        </div>
      </div>

      <!-- Text Color -->
      <div class="field">
        <label class="field-label">Text Color</label>
        <div class="color-row">
          <input
            v-model="state.textColor"
            type="color"
            class="color-swatch"
          />
          <UInput
            v-model="state.textColor"
            class="field-input"
            size="sm"
          />
        </div>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.panel {
  width: 300px;
  min-width: 300px;
  height: 100%;
  background: #111111;
  border-right: 1px solid #1f1f1f;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.panel-header {
  padding: 20px 20px 16px;
  border-bottom: 1px solid #1f1f1f;
}

.panel-title {
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: #666;
}

.panel-body {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 20px;
  scrollbar-width: thin;
  scrollbar-color: #2a2a2a transparent;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.field-label {
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: #888;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.field-value {
  color: #fff;
  font-weight: 400;
  text-transform: none;
  letter-spacing: 0;
}

.slider {
  width: 100%;
  height: 3px;
  appearance: none;
  background: #2a2a2a;
  border-radius: 2px;
  outline: none;
  cursor: pointer;
}

.slider::-webkit-slider-thumb {
  appearance: none;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: #fff;
  cursor: pointer;
}

.button-group {
  display: flex;
  gap: 4px;
}

.align-btn {
  flex: 1;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #1a1a1a;
  border: 1px solid #2a2a2a;
  border-radius: 6px;
  cursor: pointer;
  color: #666;
  transition: all 0.15s;
}

.align-btn:hover {
  background: #222;
  color: #fff;
  border-color: #3a3a3a;
}

.align-btn.active {
  background: #fff;
  color: #000;
  border-color: #fff;
}

.icon {
  width: 14px;
  height: 14px;
}

.color-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.color-swatch {
  width: 36px;
  height: 36px;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  padding: 2px;
  background: #1a1a1a;
}
</style>
```

**Step 2: Commit**

```bash
git add apps/poster-app/components/PanelLeft.vue
git commit -m "feat: add PanelLeft component with typography controls"
```

---

### Task 6: PanelRight component (style + dimensions)

**Files:**
- Create: `apps/poster-app/components/PanelRight.vue`

**Step 1: Create the component**

Create `apps/poster-app/components/PanelRight.vue`:

```vue
<script setup lang="ts">
import { usePoster, type Preset } from '~/composables/usePoster'
import { useCanvas } from '~/composables/useCanvas'

const { state } = usePoster()
const { exportPNG } = useCanvas()

const presets: { value: Preset; label: string; colors: string[] }[] = [
  { value: 'aurora', label: 'Aurora', colors: ['#00c6ff', '#7b2ff7'] },
  { value: 'mesh', label: 'Mesh', colors: ['#ff6ec4', '#7873f5'] },
  { value: 'noise', label: 'Noise', colors: ['#1a1a2e', '#16213e'] },
  { value: 'dusk', label: 'Dusk', colors: ['#f7971e', '#cc2b5e'] },
]

const sizePresets = [
  { label: '1:1', w: 1080, h: 1080 },
  { label: '4:5', w: 1080, h: 1350 },
  { label: '9:16', w: 1080, h: 1920 },
  { label: 'A4', w: 2480, h: 3508 },
]

function applyPreset(preset: typeof presets[0]) {
  state.preset = preset.value
  state.primaryColor = preset.colors[0]
  state.secondaryColor = preset.colors[1]
}

function applySizePreset(sp: typeof sizePresets[0]) {
  state.width = sp.w
  state.height = sp.h
}
</script>

<template>
  <aside class="panel panel-right">
    <div class="panel-header">
      <span class="panel-title">Style</span>
    </div>

    <div class="panel-body">
      <!-- Presets -->
      <div class="field">
        <label class="field-label">Background</label>
        <div class="preset-grid">
          <button
            v-for="p in presets"
            :key="p.value"
            :class="['preset-card', { active: state.preset === p.value }]"
            :style="`background: linear-gradient(135deg, ${p.colors[0]}, ${p.colors[1]})`"
            @click="applyPreset(p)"
          >
            <span class="preset-label">{{ p.label }}</span>
          </button>
        </div>
      </div>

      <!-- Primary Color -->
      <div class="field">
        <label class="field-label">Primary Color</label>
        <div class="color-row">
          <input v-model="state.primaryColor" type="color" class="color-swatch" />
          <UInput v-model="state.primaryColor" class="field-input" size="sm" />
        </div>
      </div>

      <!-- Secondary Color -->
      <div class="field">
        <label class="field-label">Secondary Color</label>
        <div class="color-row">
          <input v-model="state.secondaryColor" type="color" class="color-swatch" />
          <UInput v-model="state.secondaryColor" class="field-input" size="sm" />
        </div>
      </div>

      <!-- Noise -->
      <div class="field">
        <label class="field-label">
          Grain
          <span class="field-value">{{ state.noiseIntensity }}%</span>
        </label>
        <input
          v-model.number="state.noiseIntensity"
          type="range"
          min="0"
          max="100"
          class="slider"
        />
      </div>

      <div class="divider" />

      <!-- Size Presets -->
      <div class="field">
        <label class="field-label">Size Presets</label>
        <div class="size-grid">
          <button
            v-for="sp in sizePresets"
            :key="sp.label"
            class="size-btn"
            @click="applySizePreset(sp)"
          >
            {{ sp.label }}
          </button>
        </div>
      </div>

      <!-- Custom Dimensions -->
      <div class="field">
        <label class="field-label">Dimensions (px)</label>
        <div class="dim-row">
          <UInput v-model.number="state.width" type="number" placeholder="Width" size="sm" />
          <span class="dim-sep">×</span>
          <UInput v-model.number="state.height" type="number" placeholder="Height" size="sm" />
        </div>
      </div>

      <!-- Padding -->
      <div class="field">
        <label class="field-label">
          Padding
          <span class="field-value">{{ state.padding }}px</span>
        </label>
        <input
          v-model.number="state.padding"
          type="range"
          min="40"
          max="200"
          step="4"
          class="slider"
        />
      </div>

      <div class="divider" />

      <!-- Download -->
      <button class="download-btn" @click="exportPNG">
        <UIcon name="i-lucide-download" class="btn-icon" />
        Download PNG
      </button>
    </div>
  </aside>
</template>

<style scoped>
.panel {
  width: 260px;
  min-width: 260px;
  height: 100%;
  background: #111111;
  border-left: 1px solid #1f1f1f;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.panel-header {
  padding: 20px 20px 16px;
  border-bottom: 1px solid #1f1f1f;
}

.panel-title {
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: #666;
}

.panel-body {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 20px;
  scrollbar-width: thin;
  scrollbar-color: #2a2a2a transparent;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.field-label {
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: #888;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.field-value {
  color: #fff;
  font-weight: 400;
  text-transform: none;
  letter-spacing: 0;
}

.preset-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.preset-card {
  height: 60px;
  border-radius: 8px;
  border: 2px solid transparent;
  cursor: pointer;
  display: flex;
  align-items: flex-end;
  padding: 8px;
  transition: all 0.15s;
  position: relative;
  overflow: hidden;
}

.preset-card::after {
  content: '';
  position: absolute;
  inset: 0;
  background: rgba(0,0,0,0.3);
}

.preset-card:hover {
  transform: scale(1.02);
}

.preset-card.active {
  border-color: #fff;
}

.preset-label {
  font-size: 10px;
  font-weight: 600;
  color: #fff;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  position: relative;
  z-index: 1;
}

.slider {
  width: 100%;
  height: 3px;
  appearance: none;
  background: #2a2a2a;
  border-radius: 2px;
  outline: none;
  cursor: pointer;
}

.slider::-webkit-slider-thumb {
  appearance: none;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: #fff;
  cursor: pointer;
}

.divider {
  height: 1px;
  background: #1f1f1f;
  margin: 0 -20px;
}

.size-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 4px;
}

.size-btn {
  height: 32px;
  background: #1a1a1a;
  border: 1px solid #2a2a2a;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 500;
  color: #888;
  cursor: pointer;
  transition: all 0.15s;
  letter-spacing: 0.03em;
}

.size-btn:hover {
  background: #222;
  color: #fff;
  border-color: #3a3a3a;
}

.dim-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.dim-sep {
  color: #444;
  font-size: 14px;
}

.color-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.color-swatch {
  width: 36px;
  height: 36px;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  padding: 2px;
  background: #1a1a1a;
}

.download-btn {
  width: 100%;
  height: 44px;
  background: #fff;
  color: #000;
  border: none;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  transition: all 0.15s;
  letter-spacing: 0.02em;
}

.download-btn:hover {
  background: #e8e8e8;
  transform: translateY(-1px);
}

.btn-icon {
  width: 16px;
  height: 16px;
}
</style>
```

**Step 2: Commit**

```bash
git add apps/poster-app/components/PanelRight.vue
git commit -m "feat: add PanelRight component with style and dimension controls"
```

---

### Task 7: Main page and app shell

**Files:**
- Create: `apps/poster-app/pages/index.vue`

**Step 1: Create the main page**

Create `apps/poster-app/pages/index.vue`:

```vue
<script setup lang="ts">
// All state and logic is in composables
</script>

<template>
  <div class="editor-layout">
    <!-- Top bar -->
    <header class="topbar">
      <div class="topbar-brand">
        <span class="brand-mark">◈</span>
        <span class="brand-name">Poster Studio</span>
      </div>
      <div class="topbar-center">
        <span class="topbar-hint">Live canvas — edit freely</span>
      </div>
      <div class="topbar-right">
        <!-- intentionally empty, download is in right panel -->
      </div>
    </header>

    <!-- Main editor -->
    <div class="editor-body">
      <PanelLeft />
      <main class="canvas-area">
        <PosterCanvas />
      </main>
      <PanelRight />
    </div>
  </div>
</template>

<style scoped>
.editor-layout {
  width: 100vw;
  height: 100vh;
  display: flex;
  flex-direction: column;
  background: #0a0a0a;
  overflow: hidden;
}

.topbar {
  height: 48px;
  min-height: 48px;
  background: #0d0d0d;
  border-bottom: 1px solid #1a1a1a;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
}

.topbar-brand {
  display: flex;
  align-items: center;
  gap: 10px;
}

.brand-mark {
  font-size: 16px;
  color: #fff;
}

.brand-name {
  font-size: 13px;
  font-weight: 500;
  color: #fff;
  letter-spacing: 0.02em;
}

.topbar-center {
  position: absolute;
  left: 50%;
  transform: translateX(-50%);
}

.topbar-hint {
  font-size: 11px;
  color: #444;
  letter-spacing: 0.05em;
}

.topbar-right {
  width: 120px;
}

.editor-body {
  flex: 1;
  display: flex;
  overflow: hidden;
}

.canvas-area {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #0a0a0a;
  background-image:
    radial-gradient(circle at 20% 50%, rgba(255,255,255,0.01) 0%, transparent 50%),
    radial-gradient(circle at 80% 50%, rgba(255,255,255,0.01) 0%, transparent 50%);
  overflow: hidden;
}
</style>
```

**Step 2: Verify the app renders**

```bash
cd apps/poster-app && pnpm dev
```

Open http://localhost:3000 — you should see the 3-column layout with the canvas centered and rendering a poster.

**Step 3: Commit**

```bash
git add apps/poster-app/pages/index.vue
git commit -m "feat: add main editor page with 3-column layout"
```

---

### Task 8: Final polish and verification

**Step 1: Check for TypeScript errors**

```bash
cd apps/poster-app && npx nuxi typecheck
```

Fix any errors that appear.

**Step 2: Verify canvas renders all 4 presets**

Open http://localhost:3000, click each preset card (Aurora, Mesh, Noise, Dusk) and confirm the canvas updates in real-time.

**Step 3: Verify export**

Click "Download PNG" — a `poster.png` file should download at the configured resolution.

**Step 4: Verify custom dimensions**

Change width to 1080 and height to 1920 — the canvas should resize and the text should reflow.

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete poster-app — live editor with canvas export"
```
