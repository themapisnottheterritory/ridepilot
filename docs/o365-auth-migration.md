# Office 365 / Entra ID Authentication — Discovery & Plan

**Status:** Explored & planned. **NOT started. No active demand** — no one is currently
requesting SSO or external access. This document exists so the analysis isn't lost; pick it
back up if/when there's a real driver for it.

**Last updated:** 2026-07-13
**Author of discovery:** design session (philz@gcrpc.org)

---

## 1. Why this came up

Interest in leveraging existing Office 365 licenses for RidePilot login instead of app-local
passwords. The governing concern from the outset: **do not get drivers "stuck."** Drivers hold
O365 licenses but have never actually signed in, so a first-ever O365 sign-in could force MFA
enrollment or a password reset — a bad thing to hit a driver with on a tablet mid-shift.

That concern is what shaped the whole plan: keep drivers away from the risky path.

---

## 2. Current authentication architecture (as verified 2026-07-13)

> Verify against code before building — these are point-in-time observations.

- **One Devise `User` table for everyone** (dispatchers, admins, drivers). No separate driver
  Devise model — a driver is a `User` that also `has_one :driver` (`app/models/user.rb`).
- **Login key is `username`, NOT email** (`config.authentication_keys = [:username]`,
  `config/initializers/devise.rb`). This matters: O365 identifies people by email/UPN, so any
  SSO needs a deliberate username → UPN mapping.
- **Devise modules:** `database_authenticatable, recoverable, trackable, validatable,
  timeoutable, password_expirable, password_archivable, account_expireable`. **No
  `omniauthable`.** No omniauth/oauth/saml/azure gems in the Gemfile today.
- **Two login paths, same table:**
  - **Dispatchers/admins** — Devise web session (username + password).
  - **Drivers** — token API: `POST /api/v1/driver_sign_in`
    (`Api::V1::Driver::DriverSessionsController`) and `Api::V2::SessionsController`,
    username+password → `authentication_token` (`simple_token_authentication` gem). The
    RideAVL tablet app uses `X-User-Username` + `X-User-Token` headers thereafter.
  - **ActionCable** websockets authenticate on that same token
    (`app/channels/application_cable/connection.rb`).
- **Separate passwordless "my-ride" magic-link client portal** (`client_portal#show`) — out of
  scope, don't conflate with either path above.

---

## 3. How multi-tenancy / "contractors" work today (verified 2026-07-13)

**RidePilot has NO first-class concept of an external contractor/partner org.**

- `Provider` **is** the tenant/agency running the software. It has **zero self-references** — no
  parent/child, no broker/sub, no internal-vs-external flag, no `type`/`category` column.
- ~40 tables carry `provider_id`. Tenant isolation is **manual** via `current_provider` +
  CanCanCan rules (`app/models/ability.rb`) — **not** Rails `default_scope` or row-level security.
- A **`User` is NOT owned by a Provider.** `username` is globally unique; a user belongs to
  providers through `Role` (many-to-many) and can hold roles in **multiple** providers;
  `current_provider` is selected **after** login (the `change_provider` feature).
- The only "send a ride to an outside operator" mechanism is the **`cab` boolean** on `Trip`/`Run`
  — a status label ("Scheduled to Cab") + `cab_notified` flag, with **no company record, no
  handoff, no billing link.** The taxi service is not a RidePilot user at all.
- Only genuine cross-provider linkage: **customer-record sharing** between tenant providers
  (`customers_providers` HABTM) — rider data sharing, not subcontracting.

**Implication:** taxi/contractor farm-outs don't involve auth at all. The only thing "auth an
outside contractor" could mean is "another transit outfit that will actually *operate*
RidePilot" — see the instance decision below.

---

## 4. Confirmed decisions

1. **`gcrpc.org` is the one and only Entra tenant.** → The Azure app registration is
   **single-tenant** (accept only `gcrpc.org` accounts). Simpler and more secure: no multi-tenant
   consent, no guest-account handling.
2. **Future outside orgs get a SEPARATE RidePilot INSTANCE**, not multi-tenant Entra and not a new
   Provider row. Rationale: the app has no inter-org modeling to lose by splitting; separate
   instance gives hard data isolation and a dead-simple single-tenant auth config per instance.
3. **Web-first, drivers untouched, password kept as permanent fallback** (see §5). Zero driver risk.

---

## 5. Chosen approach — phased, web-users-first

Principles: **web users only** (driver token API untouched), **password stays as fallback the
whole way** (no lockouts), **match on Azure's immutable `oid` claim**, not email.

- **Phase 0 — Discovery / Azure setup (no code):** register a single-tenant Azure app (redirect
  `https://<host>/users/auth/entra_id/callback`, scopes `openid profile email`); audit web-user
  email quality (see §7); confirm MFA/conditional-access posture with whoever runs O365.
- **Phase 1 — Plumbing, dark (behind a flag, zero user impact):**
  - Gemfile: `omniauth-entra-id` (formerly `omniauth-azure-activedirectory-v2`) +
    `omniauth-rails_csrf_protection` (required for OmniAuth 2.x request-phase CSRF).
  - Migration: add `provider` + `uid` to `users` (uid = Azure `oid`), unique index on `[provider, uid]`.
  - `config/initializers/devise.rb`: `config.omniauth :entra_id, ...` reading creds from Rails
    credentials (single-tenant → set the specific `tenant_id`).
  - `app/models/user.rb`: add `:omniauthable, omniauth_providers: [:entra_id]` and a
    `User.from_omniauth(auth)` that **only links/finds, never creates** (RBAC lives in `Role`;
    auto-provisioning would be a security hole → unknown identity = login denied).
  - `config/routes.rb`: `devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }`.
  - `app/controllers/users/omniauth_callbacks_controller.rb`: the callback handler.
- **Phase 2 — Self-service linking:** while logged in by password, a user connects their O365
  account → stamps `provider`/`uid` on their own record. Sidesteps the username↔UPN mapping
  problem entirely (each user proves both identities).
- **Phase 3 — Pilot SSO login:** "Sign in with Microsoft" button for a few admins; unlinked users
  get a friendly "sign in with your password and link" message (never a dead end). Password still
  works for everyone.
- **Phase 4 — Broad web rollout:** SSO preferred, **password remains the fallback** (hybrid
  steady state — recommended resting point).
- **Phase 5 — Optional hardening (future, deliberate):** optionally disable web passwords
  per-provider (keep a break-glass local admin). **Drivers are a separate project entirely**, if
  ever — the token API keeps working untouched throughout.

**Untouched the whole time:** the driver token API, `authentication_token`, and ActionCable auth.

**Residual risk even for web users:** first-ever O365 sign-in triggering MFA enrollment / forced
reset — same failure mode as the driver worry, just lower stakes (a dispatcher at a desk who can
call you). Phase 2's opt-in linking surfaces it early with tolerant users.

---

## 6. Explored and PARKED — per-provider auth strategy

**Idea:** since RidePilot is already multi-tenant, isolate the auth *mechanism* per Provider —
gcrpc uses O365, another provider uses Google, another uses local password.

**Verdict: parked. Technically possible, but too complex for zero current use case.**

- OmniAuth/Devise *can* run multiple strategies at once, so the mechanics aren't the blocker.
- The real friction is **§3's fact that a `User` is not owned by a Provider**: username is global,
  a user can span multiple providers, and `current_provider` is chosen *after* login. So "use this
  provider's auth method" is ambiguous at the login screen for any shared user (e.g. a system admin
  in every provider).
- Breaking that chicken-and-egg needs one of: (a) **host/subdomain per provider** (net-new provider
  resolution from URL); (b) **identity-linked auth** — auth mechanism attached to the User's linked
  identities, Provider carries only a *policy* (`allowed`/`required` methods) enforced post-login;
  or (c) both. Option (b)+(c) fits the codebase best.
- **Trade vs. the "separate instance" decision:** one instance + per-provider auth = one deployment
  but weaker isolation (only as strong as manual `current_provider` scoping), bigger blast radius,
  and the shared-user edge cases above. Separate instance = hard isolation + trivial auth config, at
  the cost of N deployments. Rule of thumb if revisited: *same-trust-domain partners → providers in
  one instance with per-provider policy; arm's-length vendors → their own instance.*

**Revisit only if** there's a concrete request to onboard a friendly org into the *same* instance
where standing up a separate instance is genuinely too heavy.

---

## 7. Phase 0 audit tooling

Read-only script: `scratchpad/phase0_email_audit.rb` (session scratchpad; promote to
`lib/tasks/o365_audit.rake` as `rake o365:email_audit` before running on prod). It counts web
users, email quality (blank/placeholder/malformed vs real), duplicate emails, and domain
distribution.

Run inside Docker (host RVM ruby is the wrong 2.4.5; the app runs in the `ridepilot_app_1`
container):

```
docker exec ridepilot_app_1 bundle exec rails runner /path/to/phase0_email_audit.rb
```

**Ran 2026-07-13 against the DEV DB only (7 users — smoke test, NOT real signal):** all 7 real
emails, 6 @gcrpc.org + 1 @gmail.com, 0 placeholders, no dupes. The lone gmail account is the
archetype "can't SSO, needs a mapping decision / stays password-only" case.

**MUST be re-run against PRODUCTION** to size the real non-`gcrpc.org` + placeholder tail before
committing to Phase 1. That tail = the set of web users who stay password-only.

---

## 8. Open questions

- Are driver tablets **ever** in scope? (The web-first plan does not need this answered to start.)
- Production email-quality numbers (§7) — unknown until the audit runs on prod.

---

## 9. First concrete moves, when resumed

1. Promote the audit to `rake o365:email_audit`, run on prod, size the password-only tail.
2. Spike Phase 1 plumbing (gems + migration + single-tenant initializer + callback controller)
   behind a flag — produces a real, reviewable diff with no user impact.
