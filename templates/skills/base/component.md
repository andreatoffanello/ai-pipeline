# Skill: Component Builder

> Crea componenti custom riutilizzabili per il design system del progetto.

**Quando usarla**: Per creare componenti UI custom non coperti dalle librerie UI standard o per costruire varianti specializzate.

**Input**: Scopo, props, emits, varianti.
**Output**: File componente completo con TypeScript, styling e accessibilità.

---

## Prompt

```
## Obiettivo
Crea il componente: {{COMPONENT_NAME}}

## Specifiche
- Scopo: {{DESCRIZIONE_FUNZIONALITA}}
- Props: {{LISTA_PROPS_CON_TIPO_E_DEFAULT}}
- Emits: {{LISTA_EVENTI_EMESSI}}
- Slots: {{SLOT_DISPONIBILI}}
- Varianti: {{SIZE_VARIANT_ETC}}

## Cosa generare

File: {{PATH_TO_COMPONENTS}}/{{ComponentName}}.vue

## Requisiti
- Struttura: <script setup> → <template> → <style> (se necessario)
- Props tipizzate con interface + withDefaults(defineProps<Props>(), { ... })
- Emits tipizzati con defineEmits<{ ... }>()
- Tailwind per styling (no <style> block se possibile)
- Varianti gestite con cva() o class-variance-authority (se applicabile)
- Responsive
- Dark mode compatibile
- Accessibilità: aria-labels, keyboard navigation dove rilevante
- Max 150 righe. Se più grande, split in sotto-componenti.
- Segui le convenzioni del progetto per naming, structure, patterns

## Pattern di riferimento

```vue
<script setup lang="ts">
import { cva, type VariantProps } from 'class-variance-authority'

// Variants definition
const variants = cva(
  'base-classes', // common classes
  {
    variants: {
      variant: {
        default: 'classes-for-default',
        secondary: 'classes-for-secondary',
      },
      size: {
        sm: 'classes-for-small',
        md: 'classes-for-medium',
        lg: 'classes-for-large',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'md',
    },
  }
)

// Props interface
interface Props {
  variant?: VariantProps<typeof variants>['variant']
  size?: VariantProps<typeof variants>['size']
  disabled?: boolean
  // ... altre props
}

// Props with defaults
const props = withDefaults(defineProps<Props>(), {
  variant: 'default',
  size: 'md',
  disabled: false,
})

// Emits
const emit = defineEmits<{
  click: [event: MouseEvent]
  change: [value: string]
}>()

// Computed per le classi finali
const componentClasses = computed(() =>
  variants({
    variant: props.variant,
    size: props.size,
  })
)
</script>

<template>
  <div :class="componentClasses">
    <!-- Template structure -->
    <slot />
  </div>
</template>

<style scoped>
/* Solo se necessario per animazioni complesse o stili non esprimibili in Tailwind */
</style>
```

## Anti-pattern da evitare
- Non usare Options API
- Non usare `any` come tipo
- Non creare componenti monolitici > 150 righe
- Non mescolare logica business con presentazione
- Non dimenticare casi edge (loading, error, empty states)
- Non assumere che gli slot siano sempre popolati
```
