# Configurable Server for Self-Hosted Ente Photos Mobile Apps

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-14
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/LockedSelfHostedIOS.md`, `living_docs/LockedSelfHostedAndroid.md`, `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md` (planned), `mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md`, `docs/docs/self-hosting/administration/reverse-proxy.md`, `docs/docs/self-hosting/administration/object-storage.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Add configurable endpoint policy and migrate locked installations | M | 🟢 done | Added explicit standard, locked, and configurable modes with conflicting-define rejection. Configurable mode reuses valid locked bindings, accepts any canonical HTTPS origin, preserves its binding across logout, and enforces authenticated same-origin requests without enabling direct mutation. Passed the 29 focused tests under standard, locked, and configurable defines, all 275 Photos tests, the full analyzer, and the locked command-line validator. |
| 1 | 1.2 | Validate candidate servers and switch only after local logout | M | ⚪ not started | Probe Museum without credentials or redirects, leave the account untouched on failure, and expose a guarded endpoint-change operation that can run only after account state is cleared. |
| 2 | 2.1 | Add guarded server controls to Settings and sign-in | M | ⚪ not started | Show the active origin in authenticated Settings and logged-out entry screens, require destructive confirmation while signed in, and return successful changes to sign-in. |
| 2 | 2.2 | Build, document, and verify configurable Android and iOS artifacts | M | ⚪ not started | Update both guarded wrappers, revise the build guide and earlier living docs without rewriting their history, audit both artifacts, and exercise the shared flow on the iOS simulator and resource-capped Android emulator. |
| 3 | 3.1 | Document the as-built mobile endpoint architecture | S | ⚪ not started | Write the settled component, state, and switch-flow explanation after implementation, then link it from this document. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting it and 🟢 done when it is complete. Keep task work within its row, describe the next task before starting it, and wait for the owner's approval.

Task naming convention: `Task <phase>.<sub> — <short imperative title>`. If a commit is opened for a task, mirror that title.

---

## 2. Goal

Allow the owner of the existing personal Ente Photos Android and iOS applications to move occasionally between Museum servers without rebuilding or reinstalling. V1 is complete when the active HTTPS origin is visible and editable from authenticated Settings and the logged-out entry flow; invalid or unreachable candidates leave the current account untouched; a confirmed valid change stops current work, clears local account state, persists the new origin, and returns to sign-in; a valid installation upgraded from the earlier locked build preserves its current server, session, and photos; and normal Ente application variants retain their current behavior.

The observable success metric is one successful in-place locked-to-configurable upgrade plus one successful server change and restart on each supported mobile build path, with automated evidence that rejected candidates and cross-origin authenticated requests cannot change or escape the active server.

---

## 3. Architecture / approach

The current application has normal and compile-time locked endpoint behavior. V1 extends that shared Dart implementation with three explicit modes rather than creating another application module:

- **Standard:** Preserve the official application's production and hidden developer-endpoint behavior.
- **Locked:** Preserve the existing immutable policy for compatibility and focused security tests.
- **Configurable:** Use the compiled endpoint as a clean-install default, store one active endpoint binding, and permit changes only through the guarded logout flow.

The existing self-hosted Android flavor and iOS target keep their current package and bundle identifiers. Their wrappers continue to require `ENTE_SELF_HOSTED_ENDPOINT`, own the flavor and Dart defines, and validate the value before building, but they compile `configurableEndpoint=true` instead of `lockedEndpoint=true`. The `lockedEndpoint` and `configurableEndpoint` defines are mutually exclusive.

### Endpoint state and upgrade behavior

Configurable endpoints are absolute HTTPS origins. They may point to a private Museum server or an official Ente origin. Credentials, non-root paths, queries, fragments, surrounding whitespace, malformed URLs, and HTTP are rejected. Accepted values are canonicalized to a lowercase scheme and host with an optional explicit port and no trailing slash.

The stored endpoint binding wins over the compiled default. On a clean installation, the canonical compiled default becomes the binding. On an upgrade from the locked application, its valid existing binding is reused without clearing account state, even if a rebuilt configurable artifact carries a different default. Account state without a valid binding continues to fail closed. Changing only the build environment never silently migrates an existing account.

Authenticated Museum requests in locked and configurable modes must match the active origin's scheme, host, and effective port and must not follow redirects. Presigned object-storage clients remain outside this Museum-origin check because Museum intentionally supplies their destinations.

### Candidate validation and switch flow

Candidate validation uses a fresh network client that has no shared cookies, authentication token, Museum interceptor, or redirect handling. It sends `GET <candidate>/ping`, applies 15-second connection and response timeouts, and accepts only a successful JSON response whose `message` is `pong`.

```text
enter candidate
      |
      v
canonicalize HTTPS origin -- invalid --> show local error; change nothing
      |
      v
unauthenticated /ping ----- failure --> show local error; change nothing
      |
      v
same active origin -------- yes -----> report no change
      |
      v
signed in? -- no --> persist binding --> refresh client --> remain at sign-in
      |
     yes
      v
confirm old -> new origin and local clearing
      |
      +-- cancel ---------------------> change nothing
      |
      v
stop sync/uploads -> local logout -> persist binding -> return to sign-in
```

The authenticated flow uses local logout rather than depending on the old server's logout endpoint. The existing logout lifecycle stops synchronization, clears secure credentials, databases, caches, notifications, and queued application state, and fires the normal logout event. It does not delete photos from the device photo library. The old binding remains in place until cleanup succeeds; if persisting the new binding then fails, the application remains safely logged out on the old server and reports a recoverable error.

The endpoint layer exposes a dedicated configurable-mode activation operation that verifies account preferences have already been cleared. The existing generic developer mutation remains available only in standard mode. A successful activation emits the existing endpoint-update event so the Museum client refreshes its base URL.

### User surface, diagnostics, and constraints

Configurable builds show a Server row near Account in authenticated Settings and a visible current-server link on the landing, email-entry, and login screens. Both routes open the same Server Settings page. Standard and locked builds do not show this production control, and the hidden developer page's `offline` and `online` commands are not reused.

The signed-in confirmation names both origins and warns that backup and uploads stop and local account state and queued work are cleared. Validation, cleanup, and persistence failures use actionable local messages. Structured device logs and Museum logs are the diagnostic boundary; this personal sideloaded application adds no remote telemetry or alert service. No new regulatory or contractual compliance obligation is introduced.

The validation operation should complete within its explicit network timeouts and does not introduce a throughput or background-performance target. Dependencies are limited to Museum's `/ping`, operating-system-trusted HTTPS, shared preferences, the existing local logout lifecycle, and the existing network-client endpoint update event.

Rollback is straightforward before a successful switch: revert a task or reinstall the earlier artifact and retain the matching binding. After a user changes the binding, an earlier locked artifact compiled for a different server will fail closed and requires clearing or reinstalling the application. This one-way local-state boundary is communicated in the build guide.

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move from here to V1 only with explicit owner approval and a decision-log entry.

| Item | Status | Why |
|------|--------|-----|
| Physical Android device verification | V1.1 backlog | The signed release artifact can be audited now, while installation remains blocked until a device is available. |
| Named server profiles, history, or frequent account switching | Out of scope | The owner needs an occasional personal migration with one active origin, not a multi-server account manager. |
| HTTP or certificate-bypass support for local networks | Out of scope | Device-trusted HTTPS is the security boundary selected for both mobile platforms. |
| Changing servers while retaining credentials or local account databases | Out of scope | Server identity and encrypted account state must not be mixed across origins. |
| Saving a server that fails `/ping` | Out of scope | V1 leaves the current installation untouched until the new Museum origin proves reachable. |
| Remote endpoint telemetry, alerts, or a server-switch audit service | Out of scope | Device and Museum logs are sufficient for this personal application and avoid new infrastructure and privacy surface. |
| Automatic migration when only the compiled default changes | Out of scope | The stored binding remains authoritative so an application update cannot silently move an account. |
| Network-wide allowlisting or removal of ancillary Ente and third-party services | Out of scope | V1 governs authenticated Museum traffic and retains the security boundary of the earlier locked builds. |
| App Store, Google Play, TestFlight, or other managed distribution | Out of scope | The existing personal signing and sideloading workflow remains the supported path. |

**Status values:**
- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. Never delete an entry; if a decision changes, add a newer entry explaining the reversal.

### 2026-07-14 — Model endpoint behavior as one explicit mode

**Decision:** Represent endpoint behavior with `EndpointMode.standard`, `EndpointMode.locked`, or `EndpointMode.configurable`, derive the active mode from the two build flags, and fail startup if both managed flags are enabled.

**Why:** One mode gives endpoint resolution, persistence, mutation, and request enforcement a shared source of truth. Rejecting conflicting defines prevents build argument order from silently selecting a weaker or unintended policy.

**Alternatives considered:** Add independent `isLocked` and `isConfigurable` branches throughout the application, which permits contradictory states; or let one flag take precedence, which hides a packaging error.

### 2026-07-14 — Retain the locked binding key for configurable upgrades

**Decision:** Keep `locked_endpoint_binding_v1` as the persisted active-origin key in configurable mode and validate its value as a canonical HTTPS origin.

**Why:** Existing personal applications already store their server identity under this key. Reusing it lets the same package or bundle upgrade without copying preferences, clearing credentials, or losing the account-to-server association.

**Alternatives considered:** Rename the key and migrate it in multiple preference writes, which introduces a crash window; or ignore the old binding and seed the compiled default, which can silently move or invalidate an existing account.

### 2026-07-14 — Link focused endpoint and self-hosting references

**Decision:** Link the locked iOS and Android living docs, the mobile build guide, the reverse-proxy and object-storage references, and the planned as-built endpoint architecture companion. Record the planning document as `n/a` because the available Claude plans and general encryption architecture do not describe this feature.

**Why:** These sources explain the behavior being superseded, the supported build path, and the server reachability constraints without diluting the design with unrelated material.

**Alternatives considered:** Link only the existing living docs and build guide, which omits relevant server-networking context; or include Ente's general encryption architecture, which is unchanged by endpoint selection.

### 2026-07-14 — Use five reviewable tasks and finish with an architecture companion

**Decision:** Split the initiative into endpoint policy and migration, safe validation and switching, shared user interface, cross-platform build and verification, and a final as-built architecture companion. Size the first four tasks M and the companion S.

**Why:** The boundaries keep each change reviewable and pause-safe while preserving a settled explanation after the implementation diverges from the initial sketch.

**Alternatives considered:** Four larger tasks without a companion would bundle service and interface concerns; six tasks with separate platform validation would add checkpoints without reducing the main shared-Dart risk.

### 2026-07-14 — Diagnose personal builds locally

**Decision:** Use actionable application errors, structured device logs, artifact inspection, and Museum logs without adding remote telemetry, monitoring, or alerts.

**Why:** This is a personally distributed application with one owner. Local evidence covers its operational needs without adding infrastructure or disclosing endpoint information to another service.

**Alternatives considered:** Production-grade telemetry and server-switch audit events add privacy and operational cost; UI-only errors leave too little evidence when validation or migration fails.

### 2026-07-14 — Treat a completed server switch as the rollback boundary

**Decision:** Keep every implementation phase reversible, but document that installing an older locked artifact after the active binding changes may require clearing or reinstalling the application.

**Why:** The older artifact correctly rejects a binding for a different server. Silently rewriting it during rollback would violate the account-to-server safety invariant.

**Alternatives considered:** Make the old artifact accept the new binding, which weakens its immutable policy; or retain multiple bindings and account states, which expands V1 into profiles.

### 2026-07-14 — Require a successful unauthenticated Museum probe before clearing state

**Decision:** Canonicalize the candidate and require an unauthenticated, no-redirect `/ping` response before presenting or executing the destructive switch. Use explicit 15-second connection and response timeouts.

**Why:** A malformed, untrusted, or unavailable destination must not log the owner out or erase useful local state, and candidate validation must never expose the current authentication token.

**Alternatives considered:** Allow an override after a failed probe, which makes misconfiguration easier; or validate only URL syntax, which cannot establish that the destination is a reachable Museum server.

### 2026-07-14 — Stop active work and warn before clearing queued state

**Decision:** A confirmed signed-in switch stops synchronization and uploads through the existing local logout lifecycle and warns that queued application work will be cleared.

**Why:** Waiting for every upload can trap migration when the old server is unavailable, while immediate clearing without a specific warning hides a meaningful consequence.

**Alternatives considered:** Block until every pending upload completes, which may make migration impossible; or switch immediately with only a generic logout message, which provides insufficient warning.

### 2026-07-14 — Make the server control recoverable from Settings and sign-in

**Decision:** Expose one Server Settings page from authenticated Settings and all logged-out entry screens.

**Why:** Settings is the natural signed-in location, while a logged-out route prevents a stale or unavailable endpoint from locking the owner out of the control needed to recover.

**Alternatives considered:** Settings-only access becomes unreachable after switching or logout; sign-in-only access forces a logout before the owner can inspect or prepare a migration.

### 2026-07-14 — Implement policy and migration before the interface

**Decision:** Sequence the feature policy-first: establish the new mode, binding migration, and switch invariants before exposing the user control, then update packaging and validate artifacts.

**Why:** Endpoint identity and account migration are the highest-risk pieces. A user interface must not exist before its safe state transition is testable.

**Alternatives considered:** An Android-first vertical slice duplicates uncertainty before the shared policy settles; a UI-first sequence creates a control whose safety contract is unfinished.

### 2026-07-14 — Permit any valid HTTPS Museum origin

**Decision:** Configurable mode may use any conforming HTTPS origin, including official Ente hosts, while immutable locked mode retains its production-host rejection.

**Why:** The owner wants control of the personal application endpoint rather than a permanent classification of allowed providers. HTTPS and the guarded logout boundary protect the transition.

**Alternatives considered:** Continue rejecting official hosts, which prevents an intentional migration; or compile an allowlist, which reintroduces rebuilding for each new destination.

### 2026-07-14 — Use a compiled default plus one guarded stored binding

**Decision:** Keep `ENTE_SELF_HOSTED_ENDPOINT` as the clean-install default and store one canonical active binding that can change only after local account cleanup.

**Why:** The existing build workflow remains useful, upgrades preserve the account-server relationship, and the design avoids mixing credentials or databases between origins.

**Alternatives considered:** A first-run chooser removes a dependable default and adds onboarding scope; reusing the hidden developer editor permits mutation without the required cleanup and confirmation.

### 2026-07-14 — Convert the existing personal applications in place

**Decision:** Retain the current self-hosted Android package and iOS bundle identifiers and change their endpoint mode instead of creating another installed application.

**Why:** The owner wants the current personal applications to gain migration capability and preserve their sessions during upgrade.

**Alternatives considered:** A second configurable application avoids changing the locked artifact but duplicates identities and local state; a build-time toggle creates two subtly different artifacts under the same personal workflow.

### 2026-07-14 — Ship a guarded migration flow rather than profiles

**Decision:** V1 shows the current server, validates a replacement, confirms the destructive transition, clears local account state, and returns to sign-in.

**Why:** This covers the expected occasional move while making the account-server boundary explicit.

**Alternatives considered:** A first-launch-only choice does not solve later migration; server profiles require multiple account states, selection semantics, and a much larger security surface.

### 2026-07-14 — Optimize for an owner's occasional server migration

**Decision:** Frame the problem around one owner moving a personal Android or iOS application to another server occasionally.

**Why:** This keeps the feature focused on recovery and safe clearing rather than rapid switching or contributor-only developer convenience.

**Alternatives considered:** Frequent multi-server switching requires profiles and retained state; a developer-only shortcut would not provide the visible, supported Settings workflow requested by the owner.

---

## 6. Open questions

_None._

---

## 7. Lessons learned

> Populated at the end of each phase. Record surprises, anti-patterns, and improvements for the next phase.

_Empty until the first phase completes._
