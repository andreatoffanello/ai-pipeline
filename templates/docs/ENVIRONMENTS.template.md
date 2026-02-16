# Ambienti: Development, Staging, Production

> Strategia completa per gestire ambienti separati per DB, server e deploy.

---

## PANORAMICA

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  DEV        │    │  STAGING    │    │ PRODUCTION  │
│  (local)    │    │  (preview)  │    │  (live)     │
├─────────────┤    ├─────────────┤    ├─────────────┤
│ {{PROJECT_NAME}}│ │ {{PROJECT_NAME}}│ │ {{PROJECT_NAME}}│
│ localhost   │    │ staging URL │    │ prod URL    │
├─────────────┤    ├─────────────┤    ├─────────────┤
│ Database    │    │ Database    │    │ Database    │
│ Dev         │    │ Staging     │    │ Production  │
└─────────────┘    └─────────────┘    └─────────────┘
```

| Aspetto | Dev (locale) | Staging | Production |
|---------|-------------|---------|------------|
| **URL app** | localhost | staging.domain.com | domain.com |
| **DB** | Dev database | Staging database | Production database |
| **Dati** | Seed data finti | Test data | Dati reali |
| **Chi lo usa** | Dev | Testing team | Utenti finali |
| **Deploy** | Manuale | Auto on push to staging branch | Auto on push to main |

---

## 1. LOCAL DEVELOPMENT

### 1.1 Setup

{{STACK_DESCRIPTION}}

### 1.2 File .env

Il `.env` e nella root del progetto. NON committarlo.

```bash
{{ENV_VARS_TABLE}}
```

### 1.3 Migrazioni Database

*Instructions for running migrations locally*

```bash
# Create migration
<command to create migration>

# Apply migrations
<command to apply migrations>

# Generate types (if applicable)
<command to generate types>
```

### 1.4 Seed Data

Per popolare il DB con dati di test:

```bash
# Run seed script
<command to run seed>
```

Dati di seed previsti:
*To be filled: what seed data should exist*

### 1.5 Avviare tutto

```bash
# Start development server
<command to start dev server>
```

---

## 2. STAGING (optional)

Staging environment for testing before production.

### 2.1 Setup

*Instructions for staging environment setup*

### 2.2 Deploy

*Instructions for deploying to staging*

---

## 3. PRODUCTION

### 3.1 Database Production

*Instructions for production database setup*

**Sicurezza**:
- Secret keys MAI esposte al client (solo server e CI/CD)
- Security policies abilitati
- SSL enforced
- Backups configurati

### 3.2 Deploy Produzione

*Instructions for production deployment*

### 3.3 Dominio Custom

*Instructions for custom domain setup*

---

## 4. GESTIONE MIGRAZIONI TRA AMBIENTI

Le migrazioni DB devono fluire: **dev → staging → production**.

### 4.1 Workflow Migrazioni

*Instructions for migration workflow*

### 4.2 CI/CD per Migrazioni

*Instructions for automated migrations via CI/CD*

### 4.3 Regole d'Oro Migrazioni

1. **Mai modificare** una migrazione gia pushata (creane una nuova)
2. **Mai** DROP TABLE in produzione senza backup
3. **Sempre** testare su dev/staging prima di pushare a production
4. **Sempre** migrazioni idempotenti dove possibile (IF NOT EXISTS)
5. **Sempre** backup prima di migrazioni distruttive

---

## 5. EXTERNAL SERVICES PER AMBIENTE

*Instructions for managing external services (email, auth, etc.) across environments*

| Servizio | Dev | Staging | Production |
|----------|-----|---------|------------|
| *Service* | *Dev config* | *Staging config* | *Prod config* |

---

## 6. CHECKLIST PRE-PRODUZIONE

Prima di andare in produzione, verifica:

### Database
- [ ] Security policies abilitati
- [ ] Indici sulle colonne piu query-ate
- [ ] Backup configurati
- [ ] Connection pooling configurato

### Auth
- [ ] OAuth providers configurati (se applicabile)
- [ ] Rate limiting su login attempts
- [ ] Redirect URLs configurate per dominio prod

### App
- [ ] Environment variables di produzione configurate
- [ ] Dominio custom configurato con SSL
- [ ] Error tracking configurato
- [ ] Analytics configurato

### Sicurezza
- [ ] .env NON committato (verificare .gitignore)
- [ ] Secret keys solo su server (mai client-side)
- [ ] CORS configurato correttamente
- [ ] HTTPS enforced
