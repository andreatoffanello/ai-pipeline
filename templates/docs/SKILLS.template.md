# Skills Riutilizzabili

> Sotto-routine pronte all'uso che gli agenti (PM, Dev, QA) possono invocare per operazioni ripetitive.
> Ogni skill e un prompt autonomo con input/output definiti.

---

## FILOSOFIA

Le skills sono **generatori di codice standardizzato**. Invece di scrivere da zero ogni volta lo stesso boilerplate (CRUD API, store, pagine lista/dettaglio), il Dev invoca una skill e ottiene output consistente.

Vantaggi:
- **Consistenza**: ogni modulo segue lo stesso pattern
- **Velocita**: zero boilerplate manuale
- **Qualita**: il pattern e testato e validato una volta, riusato N volte

---

## INDICE SKILLS

{{SKILLS_TABLE}}

---

## ORDINE DI APPLICAZIONE

{{SKILLS_ORDER}}

---

## COME IL DEV USA LE SKILLS

Il Dev non deve copiarle a mano. Sono **pattern mentali** che segue automaticamente.

Quando il Dev vede nella spec "Implementa CRUD con lista, dettaglio e form", sa che deve applicare le skill nell'ordine definito.

In alternativa, puoi dare esplicitamente una skill come prompt separato prima del prompt Dev, per pre-generare il boilerplate e poi far fare al Dev solo la customizzazione.

---

## AGGIUNGERE NUOVE SKILLS

Per aggiungere una skill:
1. Crea un file `docs/skills/nome-skill.md` seguendo lo stesso formato (titolo, quando usarla, input/output, prompt)
2. Aggiungi una riga alla tabella indice qui sopra
3. Se la skill va usata automaticamente dal Dev, aggiungila all'ordine di applicazione
