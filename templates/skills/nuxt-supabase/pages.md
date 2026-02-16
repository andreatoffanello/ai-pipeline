# Skill: Page Scaffolder

> Genera le 3 pagine standard di un modulo CRUD: lista, dettaglio, form sheet.

**Quando usarla**: Ogni volta che serve creare le pagine per un modulo con operazioni CRUD complete.

**Input**: Nome modulo, store reference, colonne/campi specifici.
**Output**: 3 file Vue completi (lista, dettaglio, form sheet).

---

## Prompt

```
## Obiettivo
Genera le pagine standard per il modulo: {{MODULE_NAME}}

## Specifiche
- Entità: {{ENTITY_NAME}} (es. Contact, Product, Order)
- Store: use{{Module}}Store
- Colonne lista: {{LISTA_COLONNE_TABELLA}}
- Campi form: {{LISTA_CAMPI_FORM}}
- Relazioni: {{RELAZIONI_DA_MOSTRARE}}

## Cosa generare

### 1. Lista - pages/{{module}}/index.vue

Pagina lista completa con:
- **Header**: titolo modulo, conteggio totale, bottone "Nuovo {{Entity}}"
- **Barra filtri**: search input, filtri specifici (dropdown), sort
- **DataTable** con colonne specificate
- Ogni riga: hover state, click naviga a dettaglio
- Checkbox per selezione multipla + azioni bulk (opzionale)
- **Paginazione** bottom
- **Empty state** se nessun risultato
- **Skeleton loading** durante fetch
- Toggle vista tabella/griglia (opzionale, se specificato)

Pattern completo:

```vue
<script setup lang="ts">
import { Plus, Search, Filter, Upload } from 'lucide-vue-next'
import { watchDebounced } from '@vueuse/core'

const store = use{{Module}}Store()
const { items, isLoading, isEmpty, meta, filters } = storeToRefs(store)

// Fetch iniziale
onMounted(() => {
  store.fetchItems()
})

// Cleanup on unmount
onUnmounted(() => {
  store.$reset()
})

// Debounced search
const searchQuery = ref('')
watchDebounced(searchQuery, (val) => {
  store.setFilters({ search: val })
}, { debounce: 300 })

// Navigazione dettaglio
const router = useRouter()
function goToDetail(id: string) {
  router.push(`/{{module}}/${id}`)
}

// Apri form creazione
const isFormOpen = ref(false)
function openCreateForm() {
  isFormOpen.value = true
}

function handleFormSaved() {
  isFormOpen.value = false
  store.fetchItems() // Refresh lista
}

// Gestione filtri specifici
const statusFilter = ref<string>('all')
watch(statusFilter, (val) => {
  if (val === 'all') {
    const { status, ...rest } = filters.value
    store.setFilters(rest)
  } else {
    store.setFilters({ status: val })
  }
})

// Colonne tabella
const columns = [
  { key: '{{campo1}}', label: '{{Label1}}', sortable: true },
  { key: '{{campo2}}', label: '{{Label2}}', sortable: true },
  { key: '{{campo3}}', label: '{{Label3}}', sortable: false },
  { key: 'actions', label: '', sortable: false },
]
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight">
          {{Entity_Plural}}
        </h1>
        <p class="text-sm text-muted-foreground">
          {{Descrizione_modulo}}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <!-- Azioni secondarie (opzionali) -->
        <Button variant="outline" size="sm">
          <Upload class="mr-2 h-4 w-4" /> Import
        </Button>
        <!-- Azione primaria -->
        <Button size="sm" @click="openCreateForm">
          <Plus class="mr-2 h-4 w-4" /> Nuovo {{Entity}}
        </Button>
      </div>
    </div>

    <!-- Filtri -->
    <div class="flex items-center gap-3">
      <!-- Search -->
      <div class="relative flex-1 max-w-sm">
        <Search class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          v-model="searchQuery"
          class="pl-9 h-9"
          placeholder="Cerca..."
        />
      </div>

      <Separator orientation="vertical" class="h-5" />

      <!-- Filtri specifici -->
      <Select v-model="statusFilter">
        <SelectTrigger class="w-[180px] h-9">
          <SelectValue placeholder="Tutti gli stati" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Tutti</SelectItem>
          <SelectItem value="active">Attivi</SelectItem>
          <SelectItem value="archived">Archiviati</SelectItem>
        </SelectContent>
      </Select>

      <!-- Reset filtri -->
      <Button
        v-if="filters.search || statusFilter !== 'all'"
        variant="ghost"
        size="sm"
        @click="() => { searchQuery = ''; statusFilter = 'all'; store.resetFilters() }"
      >
        Reset
      </Button>
    </div>

    <!-- Conteggio risultati -->
    <div v-if="!isLoading" class="text-sm text-muted-foreground">
      {{ meta.total }} risultati
    </div>

    <!-- Contenuto: Loading / Empty / Table -->
    <div class="border rounded-lg">
      <!-- Skeleton loading -->
      <div v-if="isLoading && !items.length" class="p-4">
        <div class="space-y-3">
          <div v-for="i in 5" :key="i" class="flex items-center gap-3">
            <Skeleton class="h-10 w-10 rounded-full" />
            <div class="space-y-2 flex-1">
              <Skeleton class="h-4 w-[250px]" />
              <Skeleton class="h-3 w-[180px]" />
            </div>
            <Skeleton class="h-6 w-[80px] rounded-full" />
          </div>
        </div>
      </div>

      <!-- Empty state -->
      <div v-else-if="isEmpty" class="flex flex-col items-center justify-center py-16 text-center">
        <div class="rounded-full bg-muted p-3 mb-4">
          <{{EmptyIcon}} class="h-6 w-6 text-muted-foreground" />
        </div>
        <h3 class="text-lg font-medium mb-1">
          Nessun {{entity}} trovato
        </h3>
        <p class="text-sm text-muted-foreground mb-4 max-w-sm">
          {{Messaggio_empty_state}}
        </p>
        <Button size="sm" @click="openCreateForm">
          <Plus class="mr-2 h-4 w-4" /> Crea il primo {{entity}}
        </Button>
      </div>

      <!-- Tabella -->
      <Table v-else>
        <TableHeader>
          <TableRow>
            <TableHead v-for="col in columns" :key="col.key">
              {{ col.label }}
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow
            v-for="item in items"
            :key="item.id"
            class="group cursor-pointer hover:bg-muted/50"
            @click="goToDetail(item.id)"
          >
            <TableCell>
              <!-- Contenuto cella 1 -->
              <div class="flex items-center gap-3">
                <Avatar v-if="item.{{avatar_field}}" class="h-8 w-8">
                  <AvatarImage :src="item.{{avatar_field}}" />
                  <AvatarFallback>{{Fallback}}</AvatarFallback>
                </Avatar>
                <div>
                  <p class="text-sm font-medium">{{ item.{{nome_campo}} }}</p>
                  <p class="text-xs text-muted-foreground">{{ item.{{sotto_campo}} }}</p>
                </div>
              </div>
            </TableCell>
            <TableCell class="text-sm">
              {{ item.{{campo2}} }}
            </TableCell>
            <TableCell>
              <Badge :variant="item.{{status}} === 'active' ? 'default' : 'secondary'">
                {{ item.{{status}} }}
              </Badge>
            </TableCell>
            <!-- Azioni row (visibili on hover) -->
            <TableCell class="text-right">
              <div class="opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-end gap-1">
                <Button
                  variant="ghost"
                  size="icon"
                  class="h-8 w-8"
                  @click.stop="() => {/* edit action */}"
                >
                  <Pencil class="h-4 w-4" />
                </Button>
                <DropdownMenu>
                  <DropdownMenuTrigger as-child>
                    <Button
                      variant="ghost"
                      size="icon"
                      class="h-8 w-8"
                      @click.stop
                    >
                      <MoreHorizontal class="h-4 w-4" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem @click.stop="() => {/* action */}">
                      Azione 1
                    </DropdownMenuItem>
                    <DropdownMenuItem @click.stop="() => {/* action */}">
                      Azione 2
                    </DropdownMenuItem>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem
                      class="text-destructive"
                      @click.stop="() => store.deleteItem(item.id)"
                    >
                      Elimina
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <!-- Paginazione -->
    <div v-if="meta.totalPages > 1" class="flex items-center justify-between">
      <p class="text-sm text-muted-foreground">
        Pagina {{ meta.page }} di {{ meta.totalPages }}
      </p>
      <div class="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          :disabled="meta.page === 1"
          @click="store.setPage(meta.page - 1)"
        >
          Precedente
        </Button>
        <Button
          variant="outline"
          size="sm"
          :disabled="meta.page >= meta.totalPages"
          @click="store.setPage(meta.page + 1)"
        >
          Successivo
        </Button>
      </div>
    </div>

    <!-- Form Sheet -->
    <{{Module}}FormSheet
      :open="isFormOpen"
      :item="null"
      @close="isFormOpen = false"
      @saved="handleFormSaved"
    />
  </div>
</template>
```

### 2. Dettaglio - pages/{{module}}/[id].vue

Pagina dettaglio con layout 2 colonne:

```vue
<script setup lang="ts">
import { ArrowLeft, Pencil, MoreHorizontal } from 'lucide-vue-next'

const route = useRoute()
const router = useRouter()
const store = use{{Module}}Store()
const { currentItem, isLoading } = storeToRefs(store)

const id = computed(() => route.params.id as string)

// Fetch item
onMounted(async () => {
  try {
    await store.fetchItem(id.value)
  } catch (e) {
    // Redirect se non trovato
    router.push('/{{module}}')
  }
})

// Edit form
const isEditFormOpen = ref(false)
function openEditForm() {
  isEditFormOpen.value = true
}

function handleFormSaved() {
  isEditFormOpen.value = false
  store.fetchItem(id.value) // Refresh
}

// Delete
async function handleDelete() {
  if (!confirm('Sei sicuro?')) return
  try {
    await store.deleteItem(id.value)
    router.push('/{{module}}')
  } catch (e) {
    console.error(e)
  }
}
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-4">
        <Button variant="ghost" size="icon" @click="router.back()">
          <ArrowLeft class="h-4 w-4" />
        </Button>
        <div v-if="currentItem">
          <h1 class="text-2xl font-semibold tracking-tight">
            {{ currentItem.{{nome_campo}} }}
          </h1>
          <p class="text-sm text-muted-foreground">
            {{ currentItem.{{sotto_campo}} }}
          </p>
        </div>
        <Skeleton v-else class="h-8 w-[200px]" />
      </div>

      <div v-if="currentItem" class="flex items-center gap-2">
        <Badge>{{ currentItem.{{status}} }}</Badge>
        <Button variant="outline" size="sm" @click="openEditForm">
          <Pencil class="mr-2 h-4 w-4" /> Modifica
        </Button>
        <DropdownMenu>
          <DropdownMenuTrigger as-child>
            <Button variant="ghost" size="icon">
              <MoreHorizontal class="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem>Azione 1</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem class="text-destructive" @click="handleDelete">
              Elimina
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>

    <!-- Layout 2 colonne: content + sidebar -->
    <div class="grid grid-cols-1 lg:grid-cols-5 gap-6">
      <!-- Colonna sinistra: content principale (es. timeline, tabs) -->
      <div class="lg:col-span-3 space-y-6">
        <Card>
          <CardHeader>
            <CardTitle class="text-sm font-medium">Attività recenti</CardTitle>
          </CardHeader>
          <CardContent>
            <!-- Timeline, lista attività, tab content, etc. -->
            <p class="text-sm text-muted-foreground">Timeline / Content principale</p>
          </CardContent>
        </Card>
      </div>

      <!-- Colonna destra: info sidebar -->
      <div class="lg:col-span-2 space-y-4">
        <!-- Card info -->
        <Card>
          <CardHeader class="pb-3">
            <CardTitle class="text-sm font-medium">Dettagli</CardTitle>
          </CardHeader>
          <CardContent class="space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-xs text-muted-foreground">{{Label1}}</span>
              <span class="text-sm">{{ currentItem?.{{campo1}} }}</span>
            </div>
            <Separator />
            <div class="flex items-center justify-between">
              <span class="text-xs text-muted-foreground">{{Label2}}</span>
              <span class="text-sm">{{ currentItem?.{{campo2}} }}</span>
            </div>
            <Separator />
            <div class="flex items-center justify-between">
              <span class="text-xs text-muted-foreground">Creato il</span>
              <span class="text-sm">{{ formatDate(currentItem?.created_at) }}</span>
            </div>
          </CardContent>
        </Card>

        <!-- Card relazioni (se applicabile) -->
        <Card>
          <CardHeader class="pb-3">
            <CardTitle class="text-sm font-medium">{{Relazione}}</CardTitle>
          </CardHeader>
          <CardContent>
            <!-- Lista elementi correlati -->
            <p class="text-sm text-muted-foreground">Lista relazioni</p>
          </CardContent>
        </Card>
      </div>
    </div>

    <!-- Edit Form Sheet -->
    <{{Module}}FormSheet
      v-if="currentItem"
      :open="isEditFormOpen"
      :item="currentItem"
      @close="isEditFormOpen = false"
      @saved="handleFormSaved"
    />
  </div>
</template>
```

### 3. Form Sheet - components/{{module}}/{{Module}}FormSheet.vue

Sheet laterale per creazione/modifica:

```vue
<script setup lang="ts">
import { useForm } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
import { create{{Module}}Schema } from '{{PATH_TO_VALIDATORS}}'

interface Props {
  open: boolean
  item?: {{Type}} | null
}

const props = defineProps<Props>()
const emit = defineEmits<{
  close: []
  saved: [item: {{Type}}]
}>()

const store = use{{Module}}Store()
const isSubmitting = ref(false)

// Modalità edit vs create
const isEditMode = computed(() => !!props.item)
const title = computed(() =>
  isEditMode.value ? 'Modifica {{entity}}' : 'Nuovo {{entity}}'
)

// Form setup
const { handleSubmit, resetForm, values, errors } = useForm({
  validationSchema: toTypedSchema(create{{Module}}Schema),
  initialValues: props.item || {
    {{campo1}}: '',
    {{campo2}}: '',
    // ... campi default
  }
})

// Watch item changes per reset form in modalità edit
watch(() => props.item, (newItem) => {
  if (newItem) {
    resetForm({ values: newItem })
  }
})

// Submit
const onSubmit = handleSubmit(async (formData) => {
  isSubmitting.value = true
  try {
    let savedItem
    if (isEditMode.value) {
      savedItem = await store.updateItem(props.item!.id, formData)
    } else {
      savedItem = await store.createItem(formData)
    }
    emit('saved', savedItem)
    resetForm()
  } catch (e) {
    console.error('Form submit error:', e)
  } finally {
    isSubmitting.value = false
  }
})

// Handle close
function handleClose() {
  resetForm()
  emit('close')
}
</script>

<template>
  <Sheet :open="open" @update:open="(val) => !val && handleClose()">
    <SheetContent class="overflow-y-auto">
      <!-- Header con padding-right per evitare overlap con close button -->
      <SheetHeader class="pr-8">
        <SheetTitle>{{ title }}</SheetTitle>
        <SheetDescription>
          {{ isEditMode ? 'Modifica i dati' : 'Compila i campi per creare' }}
        </SheetDescription>
      </SheetHeader>

      <!-- Form con padding negativo per evitare clip dei focus ring -->
      <form @submit="onSubmit" class="space-y-4 mt-6 -mx-6 px-7">
        <!-- Campo 1 -->
        <div class="space-y-2">
          <Label for="{{campo1}}">{{Label1}}</Label>
          <Input
            id="{{campo1}}"
            v-model="values.{{campo1}}"
            placeholder="{{Placeholder}}"
            :class="{ 'border-destructive': errors.{{campo1}} }"
          />
          <p v-if="errors.{{campo1}}" class="text-xs text-destructive">
            {{ errors.{{campo1}} }}
          </p>
        </div>

        <!-- Campo 2 -->
        <div class="space-y-2">
          <Label for="{{campo2}}">{{Label2}}</Label>
          <Input
            id="{{campo2}}"
            v-model="values.{{campo2}}"
            placeholder="{{Placeholder}}"
            :class="{ 'border-destructive': errors.{{campo2}} }"
          />
          <p v-if="errors.{{campo2}}" class="text-xs text-destructive">
            {{ errors.{{campo2}} }}
          </p>
        </div>

        <!-- Select esempio -->
        <div class="space-y-2">
          <Label for="{{campo_select}}">{{Label}}</Label>
          <Select v-model="values.{{campo_select}}">
            <SelectTrigger :class="{ 'border-destructive': errors.{{campo_select}} }">
              <SelectValue placeholder="Seleziona..." />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="option1">Opzione 1</SelectItem>
              <SelectItem value="option2">Opzione 2</SelectItem>
            </SelectContent>
          </Select>
          <p v-if="errors.{{campo_select}}" class="text-xs text-destructive">
            {{ errors.{{campo_select}} }}
          </p>
        </div>

        <!-- Textarea esempio -->
        <div class="space-y-2">
          <Label for="{{campo_textarea}}">{{Label}}</Label>
          <Textarea
            id="{{campo_textarea}}"
            v-model="values.{{campo_textarea}}"
            rows="3"
            placeholder="{{Placeholder}}"
            :class="{ 'border-destructive': errors.{{campo_textarea}} }"
          />
          <p v-if="errors.{{campo_textarea}}" class="text-xs text-destructive">
            {{ errors.{{campo_textarea}} }}
          </p>
        </div>
      </form>

      <!-- Footer actions -->
      <SheetFooter class="mt-6">
        <Button variant="outline" @click="handleClose" :disabled="isSubmitting">
          Annulla
        </Button>
        <Button @click="onSubmit" :disabled="isSubmitting">
          <span v-if="isSubmitting">Salvataggio...</span>
          <span v-else>{{ isEditMode ? 'Salva modifiche' : 'Crea' }}</span>
        </Button>
      </SheetFooter>
    </SheetContent>
  </Sheet>
</template>
```

## Requisiti
- Usa componenti UI library (es. Shadcn, Nuxt UI, etc.)
- Icone da Lucide o altra libreria icon
- Tailwind utility classes (no style scoped)
- Responsive: mobile-first, breakpoint `lg:` per 2 colonne
- Dark mode compatibile
- Validazione form con Zod + vee-validate
- Loading states chiari
- Empty states informativi
- Error handling con toast notifications
- Navigazione breadcrumb aggiornata

## Anti-pattern da evitare
- NON creare tabelle non responsive
- NON dimenticare skeleton loading
- NON hardcodare stringhe (usa i18n se disponibile)
- NON dimenticare cleanup on unmount (store.$reset())
- NON usare `v-if` per form — usa Sheet open prop per gestire visibilità
```
