# MCP (Model Context Protocol) Setup

> Configurazione dei server MCP per dare a Claude Code accesso diretto a strumenti di sviluppo.
> MCP trasforma Claude da "scrittore di codice" a "operatore dell'intero stack".

---

## COS'E MCP E PERCHE CI SERVE

Senza MCP, Claude Code puo solo:
- Leggere/scrivere file
- Eseguire comandi bash
- Navigare il codebase

Con MCP, Claude Code puo anche:
- **Interrogare il DB** direttamente (query, insert, debug dati)
- **Gestire il database** (migrazioni, policies, utenti)
- **Testare visivamente** l'app (browser automation)
- **Gestire il progetto** (GitHub issues, PR)
- **Inviare email di test** (se applicabile)
- **Cercare documentazione** aggiornata

Questo e cruciale per il ciclo PM→Dev→QA:
- **Dev**: puo testare le sue API al volo, verificare che i dati si salvino
- **QA**: puo verificare funzionalita reali, non solo leggere codice

---

## FILOSOFIA

MCP servers give Claude direct access to external tools and services. The key principle:
- **Enable verification**: Dev can test, QA can validate with real data
- **Reduce context switching**: No need to manually check DB or run browser tests
- **Provide evidence**: QA reports include real screenshots and query results

---

## SERVER MCP DA CONFIGURARE

{{MCP_SERVERS_DOCS}}

---

## FILE DI CONFIGURAZIONE

Crea `.mcp.json` nella root del progetto:

{{MCP_CONFIG_JSON}}

**IMPORTANTE**: Il file `.mcp.json` nella root del progetto viene letto automaticamente da Claude Code. Le variabili `env:` referenziano il file `.env` del progetto.

---

## COME CAMBIA IL WORKFLOW CON MCP

### Senza MCP (solo codice)
```
Dev scrive API → committa → "dovrebbe funzionare"
QA legge codice → "sembra corretto" → PASS (ma magari non funziona davvero)
```

### Con MCP (codice + verifica reale)
```
Dev scrive API → usa DB MCP per verificare che i dati si salvino → committa
QA legge codice → usa Browser MCP per navigare l'app reale → verifica UI + dati → PASS/FAIL con screenshot
```

### Esempio concreto: Dev implementa CRUD

1. Dev scrive server route `POST /api/items`
2. Dev usa DB MCP: query per verificare tabella vuota
3. Dev testa manualmente via curl o fetch
4. Dev usa DB MCP: query per verificare record creato
5. Dev committa con confidenza

### Esempio concreto: QA verifica feature

1. QA legge la spec e il codice
2. QA avvia l'app
3. QA usa Browser MCP: naviga alla pagina → screenshot
4. QA verifica: pagina renderizza? empty state visibile?
5. QA usa Browser MCP: compila form → click save
6. QA usa DB MCP: query per verificare record esiste
7. QA usa Browser MCP: screenshot → il record appare nella lista?
8. QA scrive report con evidence reale

---

## ENV VARIABLES NECESSARIE

Le variabili usate da MCP (se applicabili al tuo stack):

```bash
# Database
DATABASE_URL=...
DB_SECRET_KEY=...

# External APIs
API_KEY_SERVICE_X=...
```

Assicurati che `.env` sia in `.gitignore`.

---

## IMPATTO SUI PROMPT DEGLI AGENTI

I prompt in `PROMPTS.md` GIA includono istruzioni per l'uso di MCP:
- **Dev prompt**: sezione "Verifica con browser" — Browser MCP per screenshot, DB MCP per verifica dati
- **QA prompt**: Step 5b "Testing browser" — testing E2E completo con evidenze reali

I prompt funzionano anche senza MCP (le sezioni sono condizionate a "se MCP disponibile").
