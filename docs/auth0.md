# Authentication with Auth0

This document explains how authentication works in this project using Devise and Auth0, and how it integrates with the multi-tenant architecture.

---

## What Is Auth0?

Auth0 is a cloud-based **identity platform** that handles user authentication on your behalf. Instead of building login forms, password hashing, and session management from scratch, you delegate these responsibilities to Auth0.

Auth0 supports:
- Social logins (Google, GitHub, etc.)
- Username/password authentication
- Multi-factor authentication (MFA)
- Organization-based multi-tenancy (Auth0 Organizations)

In this project, Auth0 is used as the **sole authentication provider** — the Rails application does not store passwords.

---

## How Auth0 Authentication Works (OAuth2 Flow)

```
1. User visits company-a.localhost:8080
2. Rails detects no session → redirects to Auth0 login page
3. User authenticates on Auth0
4. Auth0 redirects back to /auth/auth0/callback with user info
5. Rails finds or creates the user, establishes a session
6. User is now authenticated
```

This is a standard **OAuth2 Authorization Code flow**. The Rails application never sees the user's password — Auth0 handles all credential verification.

---

## Key Concepts

### Devise

Devise is the most widely used authentication library for Rails. In this project, it provides:
- Session management (sign in / sign out)
- The `current_user` helper
- The `authenticate_user!` before action
- OmniAuth integration for external providers

### OmniAuth

OmniAuth is a Rack middleware that standardizes multi-provider authentication. The `omniauth-auth0` gem adds Auth0 as a provider, handling the OAuth2 handshake automatically.

### Auth0 Organizations

Auth0 Organizations is a feature designed for B2B applications. It allows you to group users by organization (tenant) and apply different login policies per organization. This project is designed with Auth0 Organizations in mind, though it can work without it.

---

## How This Project Implements Authentication

### Devise + Auth0 Configuration

Auth0 is configured as an OmniAuth provider in the Devise initializer:

```ruby
# config/initializers/devise.rb
config.omniauth :auth0,
  ENV.fetch("AUTH0_CLIENT_ID", "your_client_id"),
  ENV.fetch("AUTH0_CLIENT_SECRET", "your_client_secret"),
  ENV.fetch("AUTH0_DOMAIN", "your_tenant.auth0.com"),
  callback_path: "/auth/auth0/callback",
  authorize_params: { scope: "openid profile email" }
```

| Parameter | Description |
|---|---|
| `AUTH0_CLIENT_ID` | Identifies this application to Auth0 |
| `AUTH0_CLIENT_SECRET` | Secret key for secure communication with Auth0 |
| `AUTH0_DOMAIN` | Your Auth0 tenant domain (e.g. `example.auth0.com`) |
| `callback_path` | Where Auth0 redirects after authentication |
| `scope` | Requested user information: OpenID identity, profile, and email |

### User Model

The User model is configured for OmniAuth-only authentication (no password-based login):

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :omniauthable, omniauth_providers: [:auth0]

  acts_as_tenant :tenant

  ROLES = %w[admin member guest].freeze

  validates :auth0_uid, presence: true, uniqueness: true
  validates :name, presence: true
  validates :email, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  def self.from_omniauth(auth, tenant)
    where(auth0_uid: auth.uid, tenant: tenant).first_or_create! do |user|
      user.email = auth.info.email
      user.name  = auth.info.name || auth.info.email
      user.role  = "member"
    end
  end
end
```

Key points:
- `devise :omniauthable` — Only OmniAuth is enabled; no database_authenticatable (no passwords stored)
- `auth0_uid` — The unique identifier from Auth0, used to match returning users
- `from_omniauth` — Finds an existing user or creates a new one with the `member` role

### Routing

```ruby
# config/routes.rb
devise_for :users,
  controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions"
  },
  skip: [:registrations, :passwords, :confirmations]

devise_scope :user do
  delete "sign_out", to: "users/sessions#destroy", as: :destroy_user_session
end

get "/auth/auth0/callback" => "users/omniauth_callbacks#auth0"
```

Skipped Devise modules:
- `registrations` — Users are created via Auth0 callback, not self-registration
- `passwords` — Password management is handled by Auth0
- `confirmations` — Email confirmation is handled by Auth0

### OmniAuth Callback Controller

When Auth0 redirects back after authentication, this controller handles the callback:

```ruby
# app/controllers/users/omniauth_callbacks_controller.rb
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :auth0

  def auth0
    auth = request.env["omniauth.auth"]
    tenant = Tenant.find_by!(subdomain: request.subdomain)

    @user = User.from_omniauth(auth, tenant)
    sign_in_and_redirect @user, event: :authentication
  end

  def failure
    redirect_to root_path, alert: "Authentication failed."
  end
end
```

The flow:
1. Extract Auth0 user info from `request.env["omniauth.auth"]`
2. Resolve the tenant from the subdomain
3. Find or create the user within that tenant
4. Sign in and redirect to the application

### Sessions Controller

Sign-out is handled by a custom sessions controller:

```ruby
# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    redirect_to root_path, notice: "Signed out." if signed_out
  end
end
```

### Authentication Enforcement

Every request requires authentication via `before_action :authenticate_user!` in `ApplicationController`:

```ruby
# app/controllers/application_controller.rb
before_action :authenticate_user!

def authenticate_user!
  if Rails.env.development? && current_user.nil?
    user = ActsAsTenant.current_tenant&.users&.first
    sign_in(user) if user
  end

  super unless user_signed_in?
end
```

In development, if Auth0 is not configured, the first user in the current tenant is automatically signed in. This fallback is intended to be removed before production deployment.

---

## Multi-Tenant Authentication Flow

The subdomain plays a critical role in connecting authentication to the correct tenant:

```
1. User visits company-a.localhost:8080
                    ↓
2. scope_to_tenant resolves "company-a" → Tenant (id: 1)
                    ↓
3. authenticate_user! checks for a session
                    ↓
4. No session → redirect to Auth0 login
                    ↓
5. Auth0 authenticates → redirects to /auth/auth0/callback
                    ↓
6. OmniauthCallbacksController#auth0:
   - Resolves tenant from subdomain again
   - Calls User.from_omniauth(auth, tenant)
   - User is scoped to the correct tenant
                    ↓
7. Session established → user sees only their tenant's data
```

This ensures that even if two tenants have a user with the same email, they are treated as **separate users** because `from_omniauth` scopes the lookup by both `auth0_uid` and `tenant`.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `AUTH0_CLIENT_ID` | `your_client_id` | Auth0 application client ID |
| `AUTH0_CLIENT_SECRET` | `your_client_secret` | Auth0 application client secret |
| `AUTH0_DOMAIN` | `your_tenant.auth0.com` | Auth0 tenant domain |

These are set in `.devcontainer/docker-compose.yml` and can be overridden with real values when connecting to an Auth0 tenant.

---

## Development Without Auth0

Auth0 integration is **optional** for local development. When the environment variables are left at their default placeholder values:

1. The OAuth2 flow will not work (no real Auth0 tenant)
2. The fallback in `authenticate_user!` activates automatically
3. The first user in the tenant (from seed data) is signed in
4. You can develop and test without any Auth0 configuration

This makes it easy to get started immediately after running `bin/rails db:seed`.

---

## Summary

| Concept | This Project's Implementation |
|---|---|
| Authentication provider | Auth0 (via OAuth2) |
| Rails integration | Devise + omniauth-auth0 |
| User identification | `auth0_uid` (unique per user) |
| Tenant scoping | Subdomain → Tenant lookup in callback |
| Auto user creation | `User.from_omniauth` creates with `member` role |
| Password storage | None — delegated entirely to Auth0 |
| Session management | Server-side via Devise |
| Skipped Devise modules | registrations, passwords, confirmations |
| Development fallback | Auto sign-in as first tenant user |
