# Multi-Tenant Task Management App (Rails, Hotwire, RLS, OPA, Auth0)

This repository contains a **B2B-oriented project and task management MVP** built with Ruby on Rails.  
It is a **technical demonstration project** that showcases multi-tenant data isolation, policy-based authorization with OPA, and a modern Hotwire-driven UI.

The application is intentionally minimal in features, but strong in **architecture, security, and explainability**, making it suitable for learning, experimentation, and portfolio use.

---

## Key Features

- **Multi-layer tenant isolation**  
  Dual protection using `acts_as_tenant` at the application layer and **PostgreSQL Row Level Security (RLS)** at the database layer.

- **Policy-based authorization**  
  Role-based access control is externalized to **Open Policy Agent (OPA)**, keeping authorization rules out of controllers.

- **SPA-like user experience**  
  Hotwire (Turbo Drive / Turbo Frames) enables seamless UI updates without full page reloads.

- **Auth0-ready authentication**  
  Authentication is implemented with Devise + OmniAuth (Auth0).  
  Full Auth0 integration is optional and can be enabled later.

---

## Technology Stack

| Category       | Technology                                            |
| -------------- | ----------------------------------------------------- |
| Backend        | Ruby 3.4 / Rails 8.1                                  |
| Database       | PostgreSQL 17 (RLS enabled)                           |
| Frontend       | Hotwire (Turbo Drive / Turbo Frames)                  |
| Authentication | Devise + omniauth-auth0                               |
| Authorization  | Open Policy Agent (OPA)                               |
| Multi-tenancy  | acts_as_tenant                                        |
| Environment    | DevContainer (Docker Compose)                         |
| CI             | GitHub Actions (Brakeman / RuboCop / importmap audit) |

---

## Architecture Overview

```
Browser (Hotwire)
        │
        ▼
Rails Application (Puma)
        │
        ├── Authorization Decision → OPA (Rego Policies)
        │
        ▼
PostgreSQL (Row Level Security enabled)
```

---

## Security Layers

| Layer                    | Implementation                          |
| ------------------------ | --------------------------------------- |
| Tenant identification    | Subdomain-based (`company-a.localhost`) |
| Authentication           | Devise + Auth0                          |
| App-layer isolation      | acts_as_tenant (automatic scoping)      |
| Role-based authorization | OPA (admin / member / guest)            |
| DB-layer isolation       | PostgreSQL RLS with `SET ROLE`          |

> For deeper design details, see [docs/design.md](docs/design.md).

---

## Screens / Routes

| Screen       | Path                      | Description                          |
| ------------ | ------------------------- | ------------------------------------ |
| Project list | `/projects`               | Lists all projects within the tenant |
| Task list    | `/projects/:id/tasks`     | Task list with inline status update  |
| Task detail  | `/projects/:id/tasks/:id` | Task detail and status update        |

---

## Setup

### Prerequisites

- [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/)
- [Visual Studio Code](https://code.visualstudio.com/) with the
  [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (recommended)

---

### 1. Clone the Repository

```bash
git clone <repository-url>
cd rails_hotwire_opa_tenant_manager
```

---

### 2. Start the Dev Container

Open the project in VS Code and select **Reopen in Container**.

The following services will be started:

| Service | Port | Purpose           |
| ------- | ---- | ----------------- |
| app     | 8080 | Rails application |
| db      | 5432 | PostgreSQL        |
| opa     | 8181 | OPA policy engine |

---

### 3. Database Setup

Inside the Dev Container:

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

---

### 4. (Optional) Auth0 Configuration

If you want to connect a real Auth0 tenant, set the following environment variables:

| Variable            | Description         |
| ------------------- | ------------------- |
| AUTH0_CLIENT_ID     | Auth0 client ID     |
| AUTH0_CLIENT_SECRET | Auth0 client secret |
| AUTH0_DOMAIN        | Auth0 domain        |

> If Auth0 is not configured, the development environment automatically logs in the first user in the tenant.

---

### 5. Start the Rails Server

```bash
bin/rails server -b 0.0.0.0 -p 8080
```

Access the application via subdomains:

- `http://company-a.localhost:8080` — Company A tenant
- `http://company-b.localhost:8080` — Company B tenant

---

## Seed Data

| Tenant    | Subdomain | Users                                               |
| --------- | --------- | --------------------------------------------------- |
| Company A | company-a | Admin A (admin), Member A (member), Guest A (guest) |
| Company B | company-b | Admin B (admin)                                     |

---

## Learning & Design Focus

This project intentionally focuses on:

- Correct and safe usage of PostgreSQL RLS
- Separation of authorization concerns via OPA
- Role-based access control without controller coupling
- Safe handling of database connection pooling when using `SET ROLE`
- Reproducible local development environments with Dev Containers

Feature scope is kept intentionally small to make the architecture easier to understand.

---

## Future Improvements

- Full Auth0 Organizations integration
- Admin UI for tenant and user management
- Automated tests for OPA policies
- Token-based API authorization using OPA

---

## Disclaimer

This project is a **learning and portfolio-oriented technical demo**.

- Auth0 production configuration is not included
- Not intended for direct production use without security review

---

## License

MIT License
