# Documentation

This directory contains detailed technical documentation for the Multi-Tenant Task Management App.

For a project overview and quick start guide, see the [root README](../README.md).

---

## Documents

| Document | Description |
|---|---|
| [design.md](design.md) | Full design document — architecture, database schema, routing, security layers, and more |
| [rls.md](rls.md) | PostgreSQL Row Level Security — concepts, how RLS works, and this project's implementation |
| [opa.md](opa.md) | Open Policy Agent — policy-based authorization, Rego language, and integration details |
| [auth0.md](auth0.md) | Authentication with Auth0 — OAuth2 flow, Devise integration, and multi-tenant auth |

---

## Diagrams

Architecture and request flow diagrams are stored in `docs/images/`:

| File | Description |
|---|---|
| [images/architecture.svg](images/architecture.svg) | Overall system architecture |
| [images/request_flow.svg](images/request_flow.svg) | Request processing flow |

---

## Recommended Reading Order

If you are new to this project:

1. [Root README](../README.md) — Project overview and setup
2. [design.md](design.md) — Architecture and design decisions
3. [rls.md](rls.md) — Understanding the database-layer security
4. [opa.md](opa.md) — Understanding the authorization model
5. [auth0.md](auth0.md) — Understanding the authentication flow
