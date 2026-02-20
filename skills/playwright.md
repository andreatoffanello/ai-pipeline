# Skill: Test Visivi con Playwright

Guida per lo step QA. I test devono essere **reali** — non leggere solo il codice,
ma navigare l'app, interagire con i componenti, fare screenshot e verificare visivamente.

## Prerequisiti

Prima di eseguire i test, verifica che il dev server sia attivo:
```bash
# Controlla se la porta 3000 è in uso
lsof -i :3000 | grep LISTEN
# Se non attivo, l'agente dev dovrebbe averlo lasciato running
# oppure lancia: npm run dev (in background)
```

## Struttura test visivo

```javascript
import { test, expect } from '@playwright/test'

test('NomeComponente — stato default', async ({ page }) => {
    await page.goto('http://localhost:3000/__test__/nome-feature')
    await page.waitForLoadState('networkidle')

    // Verifica che la pagina si sia caricata
    await expect(page.getByTestId('test-nome-feature')).toBeVisible()

    // Screenshot baseline — confrontato con run precedenti
    await expect(page).toHaveScreenshot('nome-feature-default.png', {
        maxDiffPixelRatio: 0.02, // tolleranza 2%
    })
})

test('NomeComponente — interazione click', async ({ page }) => {
    await page.goto('http://localhost:3000/__test__/nome-feature')
    await page.waitForLoadState('networkidle')

    const btn = page.getByTestId('btn-action')
    await expect(btn).toBeVisible()
    await btn.click()

    // Verifica cambio di stato visibile nella UI
    await expect(page.getByTestId('result-counter')).toHaveText('1')

    await expect(page).toHaveScreenshot('nome-feature-after-click.png')
})

test('NomeComponente — mobile 375px', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 })
    await page.goto('http://localhost:3000/__test__/nome-feature')
    await page.waitForLoadState('networkidle')
    await expect(page).toHaveScreenshot('nome-feature-mobile.png')
})

test('NomeComponente — dark mode', async ({ page }) => {
    await page.goto('http://localhost:3000/__test__/nome-feature')
    await page.waitForLoadState('networkidle')
    // Attiva dark mode via attributo HTML (pattern del design system)
    await page.evaluate(() => {
        document.documentElement.setAttribute('data-color-mode', 'dark')
    })
    await expect(page).toHaveScreenshot('nome-feature-dark.png')
})
```

## Selezione elementi — ordine di preferenza

1. `page.getByTestId('nome')` — usa attributo `data-testid` nel componente ✅ preferito
2. `page.getByRole('button', { name: 'Salva' })` — semantico e accessibile
3. `page.getByText('testo esatto')` — per testo visibile
4. `page.locator('.classe-css')` — ultimo resort, fragile

## Suite completa per ogni feature

Per ogni criterio di accettazione in `specs/${FEATURE}.md`, crea un test che verifica:

| Test | Cosa verificare |
|------|----------------|
| Stato iniziale | Pagina carica, elementi visibili, layout corretto |
| Interazione principale | Click, input, submit — risposta visibile |
| Loading state | Spinner/skeleton visibile durante fetch asincrono |
| Error state | Messaggio errore visibile, pulsante retry presente |
| Empty state | Messaggio + CTA quando nessun dato |
| Mobile 375px | Layout non rotto, elementi accessibili |
| Desktop 1440px | Layout ottimale, spazio usato bene |
| Dark mode | Colori invertiti correttamente via design tokens |

## Criteri qualità visiva awwwards

Per ogni screenshot, verifica visivamente prima di scrivere PASS:

- [ ] **Spaziatura**: consistente, usa design tokens (no valori arbitrari)
- [ ] **Tipografia**: gerarchia chiara (titoli > sottotitoli > body)
- [ ] **Hover state**: visibile e fluido su ogni elemento interattivo
- [ ] **Focus state**: outline visibile per accessibilità da tastiera
- [ ] **Transizioni**: fluide (non brusche), 0.15s per micro-interazioni
- [ ] **Allineamenti**: precisi, nessun elemento storto o disallineato
- [ ] **Overflow**: nessun testo tagliato, nessuno scroll non intenzionale
- [ ] **Densità**: né troppo affollato né troppo vuoto — equilibrio

## Report QA obbligatorio

Per ogni test nel file `qa/${FEATURE}-qa.md`:

```markdown
### AC-001: [Titolo criterio dalla specifica]

**Risultato:** PASS / FAIL
**URL testato:** http://localhost:3000/__test__/${FEATURE}
**Azione:** [cosa hai fatto — es. "click su btn-submit, atteso 2s"]
**Screenshot:** `screenshots/${FEATURE}-ac001-default.png`
**Viewport:** 1440x900 (desktop) / 375x812 (mobile)
**Qualità visiva:** PASS — spaziatura consistente, hover fluido, transizioni ok
**Note:** [se FAIL: descrizione esatta del problema visivo]
```

Se FAIL, descrivi:
- Cosa ti aspettavi di vedere
- Cosa hai visto invece
- Path dello screenshot che mostra il problema
