# Design Document: Rails Hotwire × acts_as_tenant × OPA Multi-Tenant Task Management App

## 1. Project Overview

A B2B project and task management tool.  
An MVP focused on security (multi-tenant isolation, RLS, OPA authorization) and a modern UX powered by Hotwire.

### Screen Structure (3 Screens)

| #   | Screen       | Path                              | Description                              |
| --- | ------------ | --------------------------------- | ---------------------------------------- |
| 1   | Project list | `/projects` (root)                | Lists all projects within the tenant     |
| 2   | Task list    | `/projects/:project_id/tasks`     | Lists tasks under a project              |
| 3   | Task detail  | `/projects/:project_id/tasks/:id` | Task detail view and status update       |

---

## 2. Technology Stack

| Category              | Technology                           | Version / Details                    |
| --------------------- | ------------------------------------ | ------------------------------------ |
| Language              | Ruby                                 | 3.4.9                                |
| Framework             | Ruby on Rails                        | 8.1.3                                |
| Database              | PostgreSQL                           | 17                                   |
| Frontend              | Hotwire (Turbo Drive / Turbo Frames) | Via importmap                        |
| Asset pipeline        | Propshaft                            | -                                    |
| Authentication        | Devise + omniauth-auth0              | Designed for Auth0 Organizations     |
| Authorization         | Open Policy Agent (OPA)              | Runs as a Docker container           |
| Multi-tenancy         | acts_as_tenant                       | Application-layer scope control      |
| DB row-level security | PostgreSQL RLS                       | Defense in depth at the DB layer     |
| JWT                   | ruby-jwt                             | Token verification                   |
| Test acceleration     | test-prof                            | For authorization tests              |
| CI                    | GitHub Actions                       | Brakeman / importmap audit / RuboCop |

---

## 3. Architecture

### 3.1 Overall Structure

![architecture.png](images/architecture.png)

### 3.2 DevContainer Configuration

Three services are started via `docker-compose.yml`:

| Service | Image                         | Port | Role                  |
| ------- | ----------------------------- | ---- | --------------------- |
| app     | ruby:3.4 (custom Dockerfile)  | 8080 | Rails application     |
| db      | postgres:17                   | 5432 | Database              |
| opa     | openpolicyagent/opa:latest    | 8181 | Policy engine         |

### 3.3 Request Flow

![Request flow diagram](images/request_flow.png)

---

## 4. Database Design

### 4.1 ER Diagram

```
tenants 1──* users
tenants 1──* projects
tenants 1──* tasks
projects 1──* tasks
users 1──* tasks (optional)
```

### 4.2 Table Definitions

#### tenants

| Column     | Type     | Constraints      | Description          |
| ---------- | -------- | ---------------- | -------------------- |
| id         | bigint   | PK               |                      |
| name       | string   | NOT NULL         | Tenant name          |
| subdomain  | string   | NOT NULL, UNIQUE | Subdomain identifier |
| created_at | datetime | NOT NULL         |                      |
| updated_at | datetime | NOT NULL         |                      |

#### users

| Column     | Type     | Constraints                | Description     |
| ---------- | -------- | -------------------------- | --------------- |
| id         | bigint   | PK                         |                 |
| tenant_id  | bigint   | NOT NULL, FK(tenants)      | Owning tenant   |
| auth0_uid  | string   | NOT NULL, UNIQUE           | Auth0 user ID   |
| name       | string   | NOT NULL                   | Display name    |
| email      | string   | NOT NULL                   | Email address   |
| role       | string   | NOT NULL, DEFAULT 'member' | Permission role |
| created_at | datetime | NOT NULL                   |                 |
| updated_at | datetime | NOT NULL                   |                 |

Role types:

| Role   | Description                              |
| ------ | ---------------------------------------- |
| admin  | Administrator — full access              |
| member | Regular employee — read, create, update  |
| guest  | External collaborator — read only        |

#### projects

| Column     | Type     | Constraints           | Description  |
| ---------- | -------- | --------------------- | ------------ |
| id         | bigint   | PK                    |              |
| tenant_id  | bigint   | NOT NULL, FK(tenants) | Owning tenant |
| name       | string   | NOT NULL              | Project name |
| created_at | datetime | NOT NULL              |              |
| updated_at | datetime | NOT NULL              |              |

#### tasks

| Column     | Type     | Constraints              | Description                  |
| ---------- | -------- | ------------------------ | ---------------------------- |
| id         | bigint   | PK                       |                              |
| tenant_id  | bigint   | NOT NULL, FK(tenants)    | Owning tenant                |
| project_id | bigint   | NOT NULL, FK(projects)   | Owning project               |
| user_id    | bigint   | FK(users), nullable      | Assignee (can be unassigned) |
| name       | string   | NOT NULL                 | Task name                    |
| status     | string   | NOT NULL, DEFAULT 'todo' | Status                       |
| created_at | datetime | NOT NULL                 |                              |
| updated_at | datetime | NOT NULL                 |                              |

Status types: `todo` / `doing` / `done`

---

## 5. Multi-Tenant Design

### 5.1 Tenant Isolation Strategy

**Column-based isolation** — All tables include a `tenant_id` column, with dual isolation at both the application and database layers.

### 5.2 Tenant Identification

Subdomain-based identification is used. The tenant is resolved from `request.subdomain`.

- Local: `company-a.localhost:8080`
- `config.action_dispatch.tld_length = 0` is set in the development environment to enable subdomain recognition on localhost

### 5.3 acts_as_tenant (Application Layer)

`set_current_tenant_through_filter` is declared in `ApplicationController`, and `around_action :scope_to_tenant` sets the tenant on each request.

Each model declares `acts_as_tenant :tenant`, which automatically appends `WHERE tenant_id = ?` to Active Record queries.

Target models: `User`, `Project`, `Task`

### 5.4 Temporarily Disabling Tenant Scope

`ActsAsTenant.without_tenant` is used only in `db/seeds.rb` to bypass tenant scoping. It is never used in production request paths.

---

## 6. PostgreSQL RLS (Row Level Security) Design

> For a detailed explanation of RLS concepts and implementation, see [docs/rls.md](rls.md).

### 6.1 Design Philosophy

In addition to application-layer isolation via acts_as_tenant, RLS provides defense in depth at the database layer. Even if a bug exists in the application-layer scoping, the database prevents access to other tenants' data.

### 6.2 Database Role Design

| User                        | Purpose                                    | Privilege   |
| --------------------------- | ------------------------------------------ | ----------- |
| postgres (superuser)        | Migration execution, default DB connection | BYPASSRLS   |
| rails_user (regular user)   | Request processing at runtime              | NOBYPASSRLS |

### 6.3 Role Switching Strategy

`database.yml` always connects as postgres (superuser). During request processing, the role is dynamically switched within an `around_action`:

```ruby
# At request start
conn.execute("SET ROLE rails_user")
conn.execute("SET app.current_tenant_id = '#{tenant.id}'")

# At request end (ensure)
conn.execute("RESET ROLE")
conn.execute("RESET app.current_tenant_id")
```

This approach ensures:

- Migrations run with superuser privileges
- RLS is correctly applied during application execution
- The ensure block guarantees the role is always reset

### 6.4 RLS Policies

`users`, `projects`, `tasks` tables:

```sql
CREATE POLICY {table}_tenant_isolation ON {table}
  FOR ALL
  USING (tenant_id = current_setting('app.current_tenant_id')::bigint);
```

`tenants` table:

```sql
CREATE POLICY tenants_isolation ON tenants
  FOR ALL
  USING (id = current_setting('app.current_tenant_id')::bigint);
```

### 6.5 Tables Excluded from RLS

`schema_migrations`, `ar_internal_metadata` — These are required for migration execution and are not subject to RLS.

### 6.6 Migration Order

1. `CreateTenants` — Create tenants table
2. `CreateUsers` — Create users table
3. `CreateProjects` — Create projects table
4. `CreateTasks` — Create tasks table
5. `CreateRlsRole` — Create rails_user role + GRANT permissions
6. `EnableRlsPolicies` — Enable RLS on all tables + create policies

---

## 7. OPA Authorization Design

> For a detailed explanation of OPA concepts and implementation, see [docs/opa.md](opa.md).

### 7.1 Separation of Concerns

| Layer                | Responsibility                                            |
| -------------------- | --------------------------------------------------------- |
| acts_as_tenant + RLS | **Horizontal control** — Data isolation between tenants   |
| OPA                  | **Vertical control** — Role-based access within a tenant  |

### 7.2 OPA Service Configuration

OPA runs as a Docker container, serving policies mounted from `opa/policy/authz.rego`.

```
OPA_URL: http://opa:8181/v1/data/authz/allow
```

### 7.3 Request / Response

Rails → OPA request:

```json
{
  "input": {
    "user": { "role": "member" },
    "action": "read",
    "resource": "task"
  }
}
```

OPA → Rails response:

```json
{ "result": true }
```

### 7.4 Action Mapping

`ApplicationController#opa_action_for` maps Rails actions to OPA actions:

| Rails action | OPA action |
| ------------ | ---------- |
| index, show  | read       |
| new, create  | create     |
| edit, update | update     |
| destroy      | delete     |

### 7.5 Rego Policy

```rego
package authz

default allow = false

# admin: full access to all operations
allow if input.user.role == "admin"

# member: read, create, and update
allow if {
    input.user.role == "member"
    input.action in ["read", "create", "update"]
}

# guest: read only
allow if {
    input.user.role == "guest"
    input.action == "read"
}
```

### 7.6 Permission Matrix

| Role \ Action | read | create | update | delete |
| ------------- | ---- | ------ | ------ | ------ |
| admin         | ✅   | ✅     | ✅     | ✅     |
| member        | ✅   | ✅     | ✅     | ❌     |
| guest         | ✅   | ❌     | ❌     | ❌     |

### 7.7 OpaClient

`app/services/opa_client.rb` — A service class responsible for HTTP requests to OPA.

- Synchronous requests via `Net::HTTP.post`
- Fail-safe design: returns `false` (deny) on communication failure
- Error tracking via log output

---

## 8. Authentication Design

### 8.1 Auth0 Integration

OAuth2 authentication via Devise + omniauth-auth0. Designed for Auth0 Organizations.

- Callback path: `/auth/auth0/callback`
- Scopes: `openid profile email`
- Session management: Server-side (Devise default)

### 8.2 Authentication Flow

```
1. User → Auth0 login page
2. Auth0 → Redirects to /auth/auth0/callback
3. OmniauthCallbacksController#auth0
   ├─ Resolves tenant from subdomain
   └─ Finds or creates user via User.from_omniauth
4. sign_in_and_redirect establishes the session
```

### 8.3 Automatic User Creation

`User.from_omniauth(auth, tenant)` — Searches for a user within the tenant during the Auth0 callback. If not found, automatically creates one with `role: "member"`.

### 8.4 Development Environment Fallback Authentication

As a development fallback when Auth0 is not connected, `ApplicationController#authenticate_user!` automatically signs in the first user in the tenant. This is intended to be removed for production.

### 8.5 Routing

```ruby
devise_for :users,
  controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions"
  },
  skip: [:registrations, :passwords, :confirmations]
```

registrations / passwords / confirmations are skipped because they are managed on the Auth0 side.

---

## 9. Hotwire Design

### 9.1 Turbo Drive

Turbo Drive is enabled for all page navigations. It replaces the `<body>` to achieve SPA-like smooth transitions. Loaded via importmap with `@hotwired/turbo-rails`.

### 9.2 Turbo Frames

Turbo Frames are used for task status updates, enabling partial page updates without full reloads.

#### Status Update on Task List

Each task row is wrapped in `turbo_frame_tag dom_id(task)`. When the status select box changes, `requestSubmit()` submits the form. The server returns the `_task.html.erb` partial, updating only the affected row.

#### Status Update on Task Detail

The status section is wrapped in `turbo_frame_tag "task_status"`. On change, the server returns the `_task_status.html.erb` partial. `TasksController#update` checks `turbo_frame_request_id` to determine which partial to render.

### 9.3 Stimulus

The Stimulus controller foundation is configured (`app/javascript/controllers/`). No custom controllers are implemented yet; status changes use inline JS (`onchange: "this.form.requestSubmit()"`).

---

## 10. Routing

```ruby
root "projects#index"

resources :projects, only: [:index] do
  resources :tasks, only: [:index, :show, :update]
end
```

| Method | Path                            | Action         | Description          |
| ------ | ------------------------------- | -------------- | -------------------- |
| GET    | /projects                       | projects#index | Project list         |
| GET    | /projects/:project_id/tasks     | tasks#index    | Task list            |
| GET    | /projects/:project_id/tasks/:id | tasks#show     | Task detail          |
| PATCH  | /projects/:project_id/tasks/:id | tasks#update   | Task status update   |

Only minimal CRUD is exposed for the MVP. create / destroy are currently out of scope.

---

## 11. Directory Structure

```
rails_hotwire_opa_tenant_manager/
├── .devcontainer/
│   ├── Dockerfile          # Ruby 3.4 + PostgreSQL client
│   ├── devcontainer.json   # VS Code DevContainer configuration
│   └── docker-compose.yml  # 3 services: app / db / opa
├── .github/
│   └── workflows/
│       └── ci.yml          # Brakeman / importmap audit / RuboCop
├── app/
│   ├── controllers/
│   │   ├── concerns/
│   │   ├── users/
│   │   │   ├── omniauth_callbacks_controller.rb  # Auth0 callback
│   │   │   └── sessions_controller.rb            # Sign out
│   │   ├── application_controller.rb  # Tenant control, auth, OPA authz
│   │   ├── projects_controller.rb
│   │   └── tasks_controller.rb
│   ├── models/
│   │   ├── tenant.rb       # has_many :users, :projects, :tasks
│   │   ├── user.rb         # acts_as_tenant, devise :omniauthable
│   │   ├── project.rb      # acts_as_tenant
│   │   └── task.rb         # acts_as_tenant, belongs_to :project/:user
│   ├── services/
│   │   └── opa_client.rb   # OPA HTTP client
│   └── views/
│       ├── layouts/
│       │   └── application.html.erb
│       ├── projects/
│       │   └── index.html.erb
│       └── tasks/
│           ├── _task.html.erb          # Task row partial (Turbo Frame)
│           ├── _task_status.html.erb   # Status partial (Turbo Frame)
│           ├── index.html.erb
│           └── show.html.erb
├── config/
│   ├── database.yml        # Connects as postgres (superuser)
│   ├── initializers/
│   │   └── devise.rb       # Auth0 OmniAuth configuration
│   └── routes.rb
├── db/
│   ├── migrate/
│   │   ├── *_create_tenants.rb
│   │   ├── *_create_users.rb
│   │   ├── *_create_projects.rb
│   │   ├── *_create_tasks.rb
│   │   ├── *_create_rls_role.rb        # rails_user role creation
│   │   └── *_enable_rls_policies.rb    # RLS activation + policy creation
│   ├── schema.rb
│   └── seeds.rb            # Development seed data
├── docs/
│   ├── design.md           # This design document
│   ├── rls.md              # RLS detailed documentation
│   └── opa.md              # OPA detailed documentation
└── opa/
    └── policy/
        └── authz.rego      # OPA authorization policy
```

---

## 12. Security Design Summary

### Defense in Depth Architecture

```
[Layer 1] Tenant identification via subdomain
    ↓
[Layer 2] Authentication via Devise + Auth0
    ↓
[Layer 3] Application-layer tenant isolation via acts_as_tenant
    ↓
[Layer 4] Role-based authorization via OPA
    ↓
[Layer 5] Database-layer tenant isolation via PostgreSQL RLS
```

| Layer                 | Protects Against                  | Implementation                       |
| --------------------- | --------------------------------- | ------------------------------------ |
| Tenant identification | Wrong tenant access               | Subdomain → Tenant lookup            |
| Authentication        | Unauthenticated access            | Devise + Auth0                       |
| App-layer isolation   | Cross-tenant queries              | acts_as_tenant (automatic WHERE)     |
| Role authorization    | Unauthorized operations           | OPA (Rego policies)                  |
| DB-layer isolation    | Data leaks from application bugs  | PostgreSQL RLS                       |

---

## 13. Environment Variables

| Variable              | Default                             | Description                          |
| --------------------- | ----------------------------------- | ------------------------------------ |
| DB_HOST               | db                                  | PostgreSQL host                      |
| DB_PORT               | 5432                                | PostgreSQL port                      |
| DB_SUPERUSER          | postgres                            | DB connection user (superuser)       |
| DB_SUPERUSER_PASSWORD | password                            | DB connection password               |
| RLS_ROLE              | rails_user                          | RLS-restricted role name             |
| RLS_ROLE_PASSWORD     | rails_password                      | RLS role password                    |
| OPA_URL               | http://opa:8181/v1/data/authz/allow | OPA endpoint                         |
| AUTH0_CLIENT_ID       | -                                   | Auth0 client ID                      |
| AUTH0_CLIENT_SECRET   | -                                   | Auth0 client secret                  |
| AUTH0_DOMAIN          | -                                   | Auth0 domain                         |

---

## 14. Seed Data

Two tenants of development and testing data are seeded:

| Tenant    | Subdomain | Users                                               | Projects                          | Tasks   |
| --------- | --------- | --------------------------------------------------- | --------------------------------- | ------- |
| Company A | company-a | Admin A (admin), Member A (member), Guest A (guest) | Website Redesign, API Development | 5 tasks |
| Company B | company-b | Admin B (admin)                                     | Mobile App                        | 2 tasks |

---

## 15. CI/CD

The following jobs run automatically via GitHub Actions:

| Job       | Description                                          |
| --------- | ---------------------------------------------------- |
| scan_ruby | Security static analysis with Brakeman               |
| scan_js   | JS dependency vulnerability check with importmap audit |
| lint      | Code style check with RuboCop                        |

---

## 16. Deviations from Original Specification

| Item               | Original Specification                          | Implementation                                                                                              |
| ------------------ | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Puma port          | 8080                                            | 3000 (Puma default). Port mapping 8080:8080 is configured in docker-compose                                 |
| DB connection      | Separate users for migration and runtime        | Single connection (postgres) + dynamic switching via `SET ROLE`. Simplifies connection pool management       |
| Stimulus           | Mentioned as a usage target                     | Foundation only. Status changes use inline JS (`onchange="this.form.requestSubmit()"`)                      |
| Task CRUD          | No specific restrictions                        | MVP exposes only index / show / update. create / destroy are not implemented                                |
| Rails module name  | Not specified                                   | Generated as `Workspace` (`config/application.rb`)                                                          |
