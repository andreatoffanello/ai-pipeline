# Skill: Test Visivi con Playwright MCP

Guida per gli step QA, DR-IMPL e DEV. I test devono essere **reali** —
non leggere solo il codice, ma navigare l'app con i tool `browser_*`,
interagire con i componenti, fare screenshot e verificare visivamente.

## Tool MCP disponibili

| Tool | Uso |
|------|-----|
| `browser_navigate` | Naviga a un URL |
| `browser_snapshot` | Legge struttura accessibilità (testo, ruoli, ref) |
| `browser_take_screenshot` | Screenshot visivo — usa per verificare qualità estetica |
| `browser_click` | Click su un elemento (usa `element` per descrizione testuale) |
| `browser_hover` | Hover su un elemento — verifica hover state |
| `browser_type` | Digita testo in un input |
| `browser_fill_form` | Compila più campi in un form |
| `browser_scroll` | Scrolla la pagina — usa per vedere elementi below-the-fold |
| `browser_resize` | Cambia viewport — usa per testare mobile/desktop |
| `browser_evaluate` | Esegui JS nella pagina (es. attivare dark mode) |
| `browser_wait_for` | Attendi che appaia un testo o sparisca un loader |
| `browser_press_key` | Premi un tasto (es. `Escape`, `Enter`, `Tab`) |

## Flusso base per ogni criterio di accettazione

```
1. browser_navigate → URL della feature
2. browser_wait_for → attendi che la pagina carichi (testo o elemento)
3. browser_snapshot → verifica struttura e accessibilità
4. browser_take_screenshot → verifica qualità visiva
5. browser_hover → verifica hover state su elementi interattivi
6. browser_click / browser_type → simula interazione utente
7. browser_take_screenshot → verifica stato post-interazione
```

## Test viewport obbligatori

```
# Desktop
browser_resize(1440, 900) → browser_take_screenshot

# Mobile
browser_resize(375, 812) → browser_take_screenshot

# Dark mode
browser_evaluate("document.documentElement.setAttribute('data-color-mode', 'dark')")
→ browser_take_screenshot
```

## Elementi below-the-fold

Dopo il primo screenshot, esegui sempre:
```
browser_scroll(direction: "down", scroll_amount: 3)
browser_take_screenshot
# Ripeti finché non hai visto tutta la pagina
```

## Verifica stati UI

Per ogni stato, naviga o interagisci per raggiungerlo:

| Stato | Come raggiungerlo |
|-------|------------------|
| Loading | Clicca una CTA che triggera un fetch, screenshot immediato |
| Empty | Naviga con dati vuoti, o rimuovi dati via UI |
| Error | Naviga con ID inesistente, o disconnetti rete via JS |
| Populated | Stato normale con dati presenti |

## Checklist qualità visiva awwwards

Per ogni screenshot, verifica prima di scrivere PASS:

- [ ] **Spaziatura**: consistente, usa design tokens (no valori arbitrari)
- [ ] **Tipografia**: gerarchia chiara (titoli > sottotitoli > body)
- [ ] **Hover state**: visibile e fluido su ogni elemento interattivo
- [ ] **Focus state**: outline visibile per accessibilità da tastiera
- [ ] **Transizioni**: fluide (non brusche), 0.15s per micro-interazioni
- [ ] **Allineamenti**: precisi, nessun elemento storto o disallineato
- [ ] **Overflow**: nessun testo tagliato, nessuno scroll non intenzionale
- [ ] **Densità**: né troppo affollato né troppo vuoto — equilibrio
- [ ] **Dark mode**: tutti i colori si invertono correttamente via design tokens
- [ ] **Mobile**: layout non rotto, testo leggibile, elementi toccabili

## Formato report QA

Per ogni test in `${PIPELINE_DIR}/qa/${FEATURE}-qa.md`:

```markdown
### AC-001: [Titolo criterio dalla specifica]

**Risultato:** PASS / FAIL
**URL testata:** http://localhost:PORT/__test__/${FEATURE}
**Azioni eseguite:** [es. "scroll down, hover su btn-submit, click"]
**Viewport:** 1440×900 (desktop) / 375×812 (mobile)
**Qualità visiva:** PASS — spaziatura consistente, hover fluido, transizioni ok
**Note:** [se FAIL: descrizione esatta del problema visivo]
```

Se FAIL, descrivi:
- Cosa ti aspettavi di vedere
- Cosa hai visto invece
- Viewport e stato in cui si manifesta il problema
