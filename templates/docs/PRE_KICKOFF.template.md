# Azioni Pre-Kickoff

> Checklist delle azioni fisiche da compiere prima di avviare la Fase 0.
> Questo documento e un **blueprint riutilizzabile**: contiene le istruzioni complete per ogni step,
> anche quelli gia completati. Non rimuovere le istruzioni quando uno step e fatto.

---

## PANORAMICA

{{PRE_KICKOFF_STEPS}}

---

## STATO ATTUALE

- [ ] Step 1: ...
- [ ] Step 2: ...
- [ ] Step 3: ...

*To be filled during setup*

---

## COMMON SETUP TASKS

### Database Setup

*Instructions for setting up database (local or cloud)*

1. Create database instance
2. Configure credentials
3. Set up environment variables
4. Initialize schema

### External Services

*Instructions for any external services (email, auth, etc.)*

1. Create account on service
2. Generate API keys
3. Configure webhooks (if needed)
4. Add credentials to .env

### Environment Variables

Create `.env` file in project root with required variables:

```bash
# Database
DATABASE_URL=...

# External Services
API_KEY_X=...

# App
APP_URL=http://localhost:3000
APP_NAME={{PROJECT_NAME}}
```

### DNS Configuration (if using custom domain)

1. Configure nameservers
2. Add required DNS records
3. Verify propagation

### Development Tools

*CLI tools that need to be installed globally*

```bash
# Example
npm install -g some-cli-tool

# Verify installation
some-cli-tool --version
```

---

## VERIFICATION CHECKLIST

Before starting Phase 0, verify:

- [ ] All external services configured
- [ ] API keys and secrets in .env
- [ ] .env file in .gitignore
- [ ] Database accessible
- [ ] Development tools installed
- [ ] DNS configured (if applicable)

---

## TROUBLESHOOTING

### Common Issues

**Issue**: Cannot connect to database
**Solution**: Check connection string format and firewall settings

**Issue**: API keys not working
**Solution**: Verify keys are correct and not expired, check environment variable names

**Issue**: DNS not propagating
**Solution**: Can take up to 24h, use online DNS checker tools
