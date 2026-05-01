> 🇯🇵 [日本語版はこちら](testing.ja.md)

# Testing

This project uses **RSpec** as the test framework.

---

## Technology Stack

| Category        | Technology        | Purpose                                    |
| --------------- | ----------------- | ------------------------------------------ |
| Test framework  | rspec-rails       | RSpec integration with Rails               |
| Test data       | factory_bot_rails | Declarative test data generation           |
| Matchers        | shoulda-matchers  | One-liner tests for validations/associations |
| HTTP stubbing   | webmock           | Stub external HTTP requests (OPA, etc.)    |

---

## Directory Structure

```
spec/
├── factories/
│   └── factories.rb        # FactoryBot definitions (Tenant, User, Project, Task)
├── models/
│   ├── tenant_spec.rb      # Validations and associations
│   ├── user_spec.rb        # Validations, associations, and .from_omniauth
│   ├── project_spec.rb     # Validations and associations
│   └── task_spec.rb        # Validations and associations
├── services/
│   └── opa_client_spec.rb  # OPA allow / deny / unreachable
├── requests/
│   ├── projects_spec.rb    # GET /projects
│   └── tasks_spec.rb       # GET/PATCH tasks, OPA deny
├── support/
│   └── opa_helper.rb       # stub_opa_allow / stub_opa_deny helpers
├── rails_helper.rb
└── spec_helper.rb
```

---

## Running Tests

Inside the DevContainer:

```bash
# Full test suite
bundle exec rspec

# By category
bundle exec rspec spec/models/
bundle exec rspec spec/services/
bundle exec rspec spec/requests/

# Single file or line
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/models/user_spec.rb:30
```

---

## Test Design Decisions

### Multi-tenancy (acts_as_tenant)

`rails_helper.rb` includes an `around` hook that wraps examples in `ActsAsTenant.with_tenant` when the `:tenant` metadata is provided. For request specs, the tenant is resolved via subdomain (`host!`), matching the production behavior.

### OPA Authorization

All external HTTP calls to OPA are stubbed with WebMock. Two helpers are available in `spec/support/opa_helper.rb`:

| Helper           | Behavior                          |
| ---------------- | --------------------------------- |
| `stub_opa_allow` | OPA returns `{ "result": true }`  |
| `stub_opa_deny`  | OPA returns `{ "result": false }` |

The OpaClient service spec also covers the **fail-closed** case — when OPA is unreachable, access is denied.

### PostgreSQL RLS

In the test environment, the `SET ROLE` / `RESET ROLE` commands used for RLS are stubbed in request specs. This is because the `rails_user` role may not exist in the test database. Tenant isolation is still tested through `acts_as_tenant` scoping.

### Authentication (Devise)

Request specs use `Devise::Test::IntegrationHelpers` (included for `type: :request`) to call `sign_in` directly, bypassing the Auth0 OAuth flow.

---

## Test Coverage Summary

| Layer    | What is tested                                              |
| -------- | ----------------------------------------------------------- |
| Models   | Validations, associations, `User.from_omniauth`            |
| Services | OpaClient — allow, deny, connection failure (fail-closed)  |
| Requests | Authentication, OPA authorization, CRUD operations         |
