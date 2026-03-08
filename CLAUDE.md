# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This App Does

ETL Server is an **API-only Rails backend** that serves as the control plane for the ETL Engine (`../etl_engine`). It provides:
- JWT-authenticated REST API for managing ETL "flows" (workflow definitions stored as YAML files)
- Schema metadata endpoints describing available ETL commands and transforms
- User authentication (email/bcrypt/JWT)

It does **not** execute flows — that is delegated to the separate ETL Engine.

## Commands

```bash
# Setup
bin/setup                           # Full setup (bundle, db:setup, etc.)
bin/rails db:migrate                # Run pending migrations

# Run server
bin/rails server                    # Development server (port 3000)

# Test
bundle exec rspec                   # All tests
bundle exec rspec spec/path/to/spec.rb          # Single file
bundle exec rspec spec/path/to/spec.rb:42       # Single test at line

# Lint / security
bin/rubocop                         # Style checks (Rails Omakase)
bin/brakeman                        # Security scan
```

## Architecture

### Request Flow
```
HTTP → ApplicationController (CORS, JSON) → JwtAuthenticatable concern
     → FlowsController / SchemasController / Auth::SessionsController
     → Service modules (FlowStore, FlowChain, CommandSchema, TransformSchema)
     → storage/flows/*.yml  (flows)  or  storage/production.sqlite3  (users)
```

### Key Architectural Decisions

**File-based flow storage**: Flows are YAML files in `storage/flows/` (configurable via `ETL_FLOWS_DIR` env var), not database rows. `FlowStore` handles all CRUD operations on these files.

**Node-graph flow structure**: Each flow YAML has a required `START_NODE` key (with `name` and `description`) plus any number of named nodes. Nodes link via `next`, `on_success`/`on_failure` (branching), or `iterator` (looping). `FlowChain` resolves these into an ordered chain.

**Stateless JWT auth**: 24-hour tokens, Bearer scheme. The `JwtAuthenticatable` concern is included in any controller requiring auth. Sessions controller issues/invalidates tokens conceptually (logout is client-side).

**Schema-as-code**: `CommandSchema` and `TransformSchema` are plain Ruby modules (no DB) that define all valid ETL operations and their parameters. These are what the frontend uses to render flow-building UI.

### Service Modules (`app/services/`)

| Module | Responsibility |
|--------|---------------|
| `FlowStore` | YAML file I/O; raises `FlowNotFound`, `FlowAlreadyExists`, `InvalidFlowData` |
| `FlowChain` | Builds ordered step array from a flow's node graph; detects cycles |
| `CommandSchema` | Defines 8 command types (transform_data, check_data, for_each_item, respond_with_*, send_to_url, log_data, iterator returns) |
| `TransformSchema` | Defines 100+ transforms across categories: Math, Logic, Text, Lists, Maps, Type Conversions, Dates, Encoding |

### Routes

```
POST   /auth/login          # → Auth::SessionsController#create
DELETE /auth/logout         # → Auth::SessionsController#destroy
GET    /flows               # list
POST   /flows               # create
GET    /flows/:id           # show (includes FlowChain)
PUT/PATCH /flows/:id        # update
DELETE /flows/:id           # destroy
POST   /flows/copy          # copy a flow to a new ID
GET    /schema/commands     # CommandSchema metadata
GET    /schema/transforms   # TransformSchema metadata
GET    /up                  # health check
```

### Flow ID Rules
Flow IDs are DNS-safe hostname labels: must match `/\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?\z/`.
Lowercase letters, digits, and hyphens only. No underscores. Cannot start or end with a hyphen.
This ensures every flow ID is a valid `*.etl.cnxkit.com` subdomain.

### Testing Conventions
- Request specs live in `spec/requests/` mirroring controller namespacing
- `JwtHelpers` module in `spec/support/` generates tokens for authenticated requests; automatically included in request specs
- DatabaseCleaner uses transactional strategy
- Factories in `spec/factories/`

### Database
SQLite only. Users table has email (unique, case-insensitive via downcase in model) + bcrypt `password_digest`. Production uses separate SQLite files for cache, queue, and cable (Solid suite).

## Deployment

**Systemd (current):** `deploy.sh` pulls `main`, runs `bundle install` + `db:migrate`, restarts `etl_server.service`.

**Docker/Kamal (configured):** `config/deploy.yml` + `Dockerfile`. Persistent volume mounts `storage/` so flows and databases survive redeploys.
