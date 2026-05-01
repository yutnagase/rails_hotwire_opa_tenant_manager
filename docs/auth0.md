> 🇯🇵 [日本語版はこちら](auth0.ja.md)

# Authentication with Auth0

This document explains how authentication works in this project using Devise and Auth0, and how it integrates with the multi-tenant architecture.


## What Is Auth0?

Auth0 is a cloud-based **identity platform** that handles user authentication on your behalf. Instead of building login forms, password hashing, and session management from scratch, you delegate these responsibilities to Auth0.

Auth0 supports:
- Social logins (Google, GitHub, etc.)
- Username/password authentication
- Multi-factor authentication (MFA)
- Organization-based multi-tenancy (Auth0 Organizations)

In this project, Auth0 is used **solely for authentication (identity verification)**. Role management is handled entirely within Rails.


## Design Principles

| Concern | Responsibility |
|---|---|
| Authentication (who is this user?) | Auth0 |
| Role management (what can this user do?) | Rails DB (`users.role`) |
| Authorization enforcement | OPA |

Auth0 does not manage roles, permissions, or tenant membership. It only verifies that the user is who they claim to be (e.g. via Google OAuth). All business-level access control is managed within the Rails application.


## How Auth0 Authentication Works (OAuth2 Flow)

```
1. User visits company-a.localhost:8080
2. Rails detects no session → shows login page
3. User clicks "Sign in with Auth0" (POST to /users/auth/auth0)
4. Browser redirects to Auth0 Universal Login
5. User authenticates (e.g. "Continue with Google")
6. Auth0 redirects back to /users/auth/auth0/callback with user info
7. Rails finds or creates the user, establishes a session
8. User is now authenticated
```

This is a standard **OAuth2 Authorization Code flow**. The Rails application never sees the user's password — Auth0 handles all credential verification.


## User Lifecycle

### Seed Admin Users

Initial admin users are pre-created via `db/seeds.rb` with:
- `role: "admin"`
- `seed_admin: true` (role cannot be changed)
- `auth0_uid: "seed|admin_a"` (placeholder, updated on first login)
- `email` set from environment variables (`SEED_ADMIN_EMAIL_COMPANY_A`, etc.)

### First Login (Email-Based Linking)

When a user logs in via Auth0 for the first time, `User.from_omniauth` performs the following:

1. Search by `auth0_uid` — if found, return the existing user (returning user)
2. Search by `email` within the tenant — if found, update `auth0_uid` and link (seed user first login)
3. If not found, create a new user with `role: "guest"`

This allows seed admin users to be linked to their Auth0 identity on first login, based on email match.

### Role Assignment

| Scenario | Role |
|---|---|
| Seed admin (pre-created) | `admin` (immutable, `seed_admin: true`) |
| New user (first Auth0 login) | `guest` |
| Role change by admin | Admin can change other users' roles (future feature) |


## Key Concepts

### Devise

Devise is the most widely used authentication library for Rails. In this project, it provides:
- Session management (sign in / sign out)
- The `current_user` helper
- The `authenticate_user!` before action
- OmniAuth integration for external providers

### OmniAuth

OmniAuth is a Rack middleware that standardizes multi-provider authentication. The `omniauth-auth0` gem adds Auth0 as a provider, handling the OAuth2 handshake automatically.

The `omniauth-rails_csrf_protection` gem is required to bridge Rails CSRF tokens with OmniAuth's middleware-level CSRF verification (required since OmniAuth 2.x).


## How This Project Implements Authentication

### Devise + Auth0 Configuration

Auth0 is configured as an OmniAuth provider in the Devise initializer:

```ruby
# config/initializers/devise.rb
config.omniauth :auth0,
  ENV.fetch("AUTH0_CLIENT_ID", "your_client_id"),
  ENV.fetch("AUTH0_CLIENT_SECRET", "your_client_secret"),
  ENV.fetch("AUTH0_DOMAIN", "your_tenant.auth0.com"),
  callback_path: "/users/auth/auth0/callback",
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

  validates :auth0_uid, presence: true, uniqueness: { scope: :tenant_id }
  validates :name, presence: true
  validates :email, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  def self.from_omniauth(auth, tenant)
    # 1. Already linked by auth0_uid
    user = find_by(auth0_uid: auth.uid, tenant: tenant)
    return user if user

    # 2. Link seed user by email match
    user = find_by(email: auth.info.email, tenant: tenant)
    if user
      user.update!(auth0_uid: auth.uid, name: auth.info.name || user.name)
      return user
    end

    # 3. Create new user as guest
    create!(
      tenant: tenant,
      auth0_uid: auth.uid,
      email: auth.info.email,
      name: auth.info.name || auth.info.email,
      role: "guest"
    )
  end
end
```

Key points:
- `devise :omniauthable` — Only OmniAuth is enabled; no passwords stored
- `auth0_uid` — Unique per tenant (composite unique index on `auth0_uid` + `tenant_id`)
- `seed_admin` — Boolean flag; when `true`, the user's role cannot be changed
- `from_omniauth` — Three-step lookup: auth0_uid → email → new guest

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

resource :dev_session, only: [:new, :create]
```

Skipped Devise modules:
- `registrations` — Users are created via Auth0 callback, not self-registration
- `passwords` — Password management is handled by Auth0
- `confirmations` — Email confirmation is handled by Auth0

### Login Page (DevSessionsController)

A unified login page at `/dev_session/new` handles both modes:

- **Auth0 configured** — Shows a "Sign in with Auth0" button that POSTs to `/users/auth/auth0` (Turbo disabled to allow external redirect)
- **Auth0 not configured** — Shows a user selection list for development convenience

```ruby
# app/controllers/dev_sessions_controller.rb
class DevSessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :authorize_with_opa

  def new
    @auth0_configured = auth0_configured?
    @users = ActsAsTenant.current_tenant.users unless @auth0_configured
  end
end
```

### OmniAuth Callback Controller

When Auth0 redirects back after authentication, this controller handles the callback:

```ruby
# app/controllers/users/omniauth_callbacks_controller.rb
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :auth0
  skip_before_action :authenticate_user!
  skip_before_action :authorize_with_opa

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
3. Find or create the user within that tenant (with email-based linking)
4. Sign in and redirect to the application

### Sessions Controller

Sign-out redirects to the login page or root depending on Auth0 configuration:

```ruby
# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  skip_before_action :authorize_with_opa, only: :destroy

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    if signed_out
      path = (!auth0_configured? && Rails.env.development?) ? new_dev_session_path : root_path
      redirect_to path, notice: "Signed out."
    end
  end
end
```

### Authentication Enforcement

Every request requires authentication via `before_action :authenticate_user!` in `ApplicationController`:

```ruby
# app/controllers/application_controller.rb
def authenticate_user!
  return if user_signed_in?

  redirect_to new_dev_session_path
end

def auth0_configured?
  ENV["AUTH0_CLIENT_ID"].present? && ENV["AUTH0_CLIENT_ID"] != "your_client_id"
end
```

Unauthenticated users are always redirected to the login page, which shows the appropriate login method based on Auth0 configuration.


## Multi-Tenant Authentication Flow

The subdomain plays a critical role in connecting authentication to the correct tenant:

```
1. User visits company-a.localhost:8080
                    ↓
2. scope_to_tenant resolves "company-a" → Tenant (id: 1)
                    ↓
3. authenticate_user! checks for a session
                    ↓
4. No session → redirect to /dev_session/new (login page)
                    ↓
5. User clicks "Sign in with Auth0" (POST)
                    ↓
6. Auth0 authenticates → redirects to /users/auth/auth0/callback
                    ↓
7. OmniauthCallbacksController#auth0:
   - Resolves tenant from subdomain
   - Calls User.from_omniauth(auth, tenant)
   - Links by auth0_uid, email, or creates new guest
                    ↓
8. Session established → user sees only their tenant's data
```

This ensures that even if two tenants have a user with the same email, they are treated as **separate users** because `from_omniauth` scopes the lookup by `tenant`.


## Environment Variables

| Variable | Description |
|---|---|
| `AUTH0_CLIENT_ID` | Auth0 application client ID |
| `AUTH0_CLIENT_SECRET` | Auth0 application client secret |
| `AUTH0_DOMAIN` | Auth0 tenant domain |
| `SEED_ADMIN_EMAIL_COMPANY_A` | Email for Company A initial admin (must match Auth0 login email) |
| `SEED_ADMIN_EMAIL_COMPANY_B` | Email for Company B initial admin (must match Auth0 login email) |

These are set in `.devcontainer/.env` (git-ignored) and loaded via `docker-compose.yml`.


## Auth0 Setup Requirements

On the Auth0 dashboard, configure the following for your application:

| Setting | Value |
|---|---|
| Application Type | Regular Web Application |
| Allowed Callback URLs | `http://company-a.localhost:8080/users/auth/auth0/callback, http://company-b.localhost:8080/users/auth/auth0/callback` |
| Allowed Logout URLs | `http://company-a.localhost:8080, http://company-b.localhost:8080` |
| Allowed Web Origins | `http://company-a.localhost:8080, http://company-b.localhost:8080` |

Enable at least one Social Connection (e.g. Google) under Authentication → Social.


## Development Without Auth0

When Auth0 environment variables are not set (or left at placeholder values):

1. The login page shows a user selection list instead of the Auth0 button
2. You can select any seed user to sign in directly
3. No external authentication service is required

This makes it easy to get started immediately after running `bin/rails db:seed`.


## Summary

| Concept | This Project's Implementation |
|---|---|
| Authentication provider | Auth0 (via OAuth2) |
| Rails integration | Devise + omniauth-auth0 + omniauth-rails_csrf_protection |
| User identification | `auth0_uid` (unique per tenant) |
| Tenant scoping | Subdomain → Tenant lookup in callback |
| Seed user linking | Email-based matching on first Auth0 login |
| New user default role | `guest` |
| Role management | Rails DB only (Auth0 is not used for roles) |
| Seed admin protection | `seed_admin: true` prevents role changes |
| Password storage | None — delegated entirely to Auth0 |
| Session management | Server-side via Devise |
| Login page | `/dev_session/new` — Auth0 button or dev user selection |
| Turbo compatibility | Auth0 button uses `data-turbo="false"` to avoid CORS issues |
