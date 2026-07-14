# Configurable Server for Self-Hosted Ente Photos Mobile Apps

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-14
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/LockedSelfHostedIOS.md`, `living_docs/LockedSelfHostedAndroid.md`, `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md`, `mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md`, `docs/docs/self-hosting/administration/reverse-proxy.md`, `docs/docs/self-hosting/administration/object-storage.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Add configurable endpoint policy and migrate locked installations | M | 🟢 done | Added explicit standard, locked, and configurable modes with conflicting-define rejection. Configurable mode reuses valid locked bindings, accepts any canonical HTTPS origin, preserves its binding across logout, and enforces authenticated same-origin requests without enabling direct mutation. Passed the 29 focused tests under standard, locked, and configurable defines, all 275 Photos tests, the full analyzer, and the locked command-line validator. |
| 1 | 1.2 | Validate candidate servers and switch only after local logout | M | 🟢 done | Added a fresh credential-free, no-redirect Museum `/ping` probe with 15-second connection and response timeouts, an opaque validated-candidate handoff, and configurable-only activation that retains the old binding until local account preferences are cleared. Failed probes and premature activation leave account state and the binding untouched; successful activation emits the endpoint-update event. Passed all 37 focused endpoint tests, all 283 Photos tests, and the full analyzer. |
| 2 | 2.1 | Add guarded server controls to Settings and sign-in | M | 🟢 done | Added one localized Server Settings page, an authenticated Settings row, and current-origin links on landing, account creation, and login. The page validates before mutation, treats the active origin as a no-op, requires a scrollable signed-in confirmation naming both origins, runs local logout before activation, and returns successful changes to login. Standard and locked builds hide the control; both managed modes disable the legacy seven-tap editor. Passed 19 focused UI/network tests, compile-mode checks under standard, configurable, and locked defines, all 292 Photos tests, and the full analyzer. |
| 2 | 2.2 | Build, document, and verify configurable Android and iOS artifacts | M | 🟢 done | Changed both guarded wrappers and their shared validator to configurable mode, documented defaults, upgrades, switching, and rollback, and appended supersession notes to both locked-build records. Built and audited the arm64 iOS Simulator app and three-ABI Android debug APK. The iOS upgrade retained the local binding, exposed the signed-out Server link, and rejected the TLS-invalid Tailscale IP without switching. The resource-capped Android upgrade preserved its first-install record, signed-in session, photos, and local binding, and exposed the active Server page. The Android APK SHA-256 is `5d4613889a5fb8b72cd83f13e2aab50c3f7a9347589ff16a79584d9a6150e1aa`. Passed 45 configurable-define tests, all 292 Photos tests, the analyzer, wrapper guards, endpoint validation, signature/archive/identity audits, and `git diff --check`. |
| 3 | 3.1 | Document the as-built mobile endpoint architecture | S | 🟢 done | Added and linked the as-built architecture companion covering guarantees, component ownership, mode and persisted-state rules, fail-closed startup, network boundaries, the validated logout-before-switch sequence and failure states, packaging and rollback, verification evidence, and a maintenance checklist. Audited the description against the shipped implementation, resolved all 17 local document and source links, and passed heading-structure and `git diff --check` validation. |
| 4 | 4.1 | Recover server switching after an incomplete login | M | 🟢 done | Exposed one endpoint-level detector for complete or partial local account state and made the Server page require confirmed local cleanup whenever that state exists, including an email saved before a failed passkey login. Reproduced the email-without-token failure, recovered the dedicated simulator without deleting its binding, rebuilt and installed the configurable iOS artifact, and verified that switching logs out locally and continues at the new server's login flow. Passed 39 focused tests in each of standard, locked, and configurable modes, all 294 Photos tests, the focused analyzer, the embedded-kernel and signature audit, and `git diff --check`. |
| 4 | 4.2 | Verify a successful iOS server switch and restart | S | ⚪ not started | Use a certificate-valid HTTPS hostname, complete the guarded switch, sign in, verify photo transfer, restart the application, and confirm that the selected binding persists. |

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

The settled implementation and maintenance invariants are documented in the
[as-built architecture companion](ConfigurableSelfHostedMobileServerArchitecture.md).
This section preserves the approach and boundaries selected during design.

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
local account state? -- no --> persist binding --> refresh client --> remain at sign-in
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

The cleanup flow applies to complete accounts and incomplete login state, such as an email saved before passkey authentication succeeds. It uses local logout rather than depending on the old server's logout endpoint. The existing logout lifecycle stops synchronization, clears secure credentials, databases, caches, notifications, and queued application state, and fires the normal logout event. It does not delete photos from the device photo library. The old binding remains in place until cleanup succeeds; if persisting the new binding then fails, the application remains safely logged out on the old server and reports a recoverable error.

The endpoint layer exposes a dedicated configurable-mode activation operation that verifies account preferences have already been cleared. The existing generic developer mutation remains available only in standard mode. A successful activation emits the existing endpoint-update event so the Museum client refreshes its base URL.

### User surface, diagnostics, and constraints

Configurable builds show a Server row near Account in authenticated Settings and a visible current-server link on the landing, email-entry, and login screens. Both routes open the same Server Settings page. Standard and locked builds do not show this production control, and the hidden developer page's `offline` and `online` commands are not reused. Both managed modes disable the seven-tap developer editor entirely; standard builds retain it.

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

### 2026-07-14 — Treat incomplete login preferences as cleanup-required account state

**Decision:** Use the endpoint layer's complete account-preference key set to
decide whether Server Settings must confirm and run local logout. Do not rely
only on the presence of an authentication token. Keep the activation guard as
the final check that all account preferences were removed before changing the
binding.

**Why:** The login flow saves the email before passkey or password
authentication completes. A failed login therefore has no token and appears
signed out, but still contains account state that activation correctly refuses
to carry to another server. Giving the UI the same state detector provides a
safe recovery path without weakening the server/account separation.

**Alternatives considered:** Ignore email-only state during activation, which
weakens the invariant and leaves other partial login combinations unresolved;
or silently discard incomplete state, which can erase local account material
without the existing confirmation.

### 2026-07-14 — Upgrade the existing personal artifacts in place

**Decision:** Change both guarded wrappers from `lockedEndpoint=true` to
`configurableEndpoint=true` while retaining their existing `selfhosted` flavor,
scheme, application IDs, bundle identifier, output paths, and signing inputs.
Treat `ENTE_SELF_HOSTED_ENDPOINT` as the clean-install default rather than a
forced migration value.

**Why:** Package identity continuity lets a valid locked installation reuse its
stored binding, account, and photos. The wrapper still owns and validates all
compile-time endpoint inputs, while runtime changes go exclusively through the
validated and confirmed Server Settings flow.

**Alternatives considered:** Ship a second configurable application alongside
the locked one, or make the wrapper's endpoint overwrite existing bindings.

### 2026-07-14 — Disable the legacy endpoint editor in managed builds

**Decision:** Remove the seven-tap developer-settings entry from locked and configurable modes while retaining it unchanged in standard builds. Configurable builds use only the guarded Server Settings page, and their old read-only developer endpoint label is replaced by the visible current-server link.

**Why:** The developer page accepts special `offline` and `online` commands and was designed for direct standard-mode mutation. Leaving it reachable in configurable mode creates a second, misleading route that cannot satisfy the required validation, confirmation, and logout sequence.

**Alternatives considered:** Leave the editor reachable and rely on the endpoint policy to reject writes, which presents a broken control; or retrofit the developer page, which would mix personal production behavior with unrelated debugging commands.

### 2026-07-14 — Route every configurable entry through one Server Settings page

**Decision:** Use one localized Server Settings page from the authenticated Settings row and reusable current-origin links on landing, account creation, and login. The page owns the isolated probe, uses a scrollable destructive confirmation only when signed in, calls the existing local logout lifecycle, activates the validated origin, and returns to login.

**Why:** One page keeps validation, failure messaging, cancellation, cleanup order, and navigation consistent while leaving recovery reachable without an account. Dependency injection at the page boundary permits widget tests without weakening the opaque validated-endpoint handoff.

**Alternatives considered:** Build separate authenticated and logged-out forms, which duplicates the highest-risk transition logic; or expose the control only in Settings, which becomes inaccessible after logout or an unavailable-server failure.

### 2026-07-14 — Activate only an opaque validated candidate

**Decision:** Return a library-constructed `ValidatedEndpoint` from the isolated `/ping` probe and require that value for the high-level switch operation instead of accepting another raw string at the call site.

**Why:** The upcoming interface cannot accidentally skip canonicalization and reachability checks between validation and activation. The probe remains separately testable through an injected transport adapter without sharing the application's authenticated network client.

**Alternatives considered:** Pass a canonical string between the interface and endpoint configuration, which makes validation easier to bypass; or let the endpoint configuration perform network I/O, which couples persistence to transport behavior and makes failure-state testing less focused.

### 2026-07-14 — Keep the old binding until local logout completes

**Decision:** Reject configurable endpoint activation while known account preferences or a legacy runtime override remain, require a valid current binding, and write the replacement only after local logout has cleared preferences. A same-origin activation is an event-free no-op.

**Why:** Validation failure and interrupted cleanup cannot mix an old account with a new server. If the final binding write fails, the application remains logged out but still points safely at the old server.

**Alternatives considered:** Write the candidate before logout, which exposes old credentials and local state to a new origin after interruption; or clear the binding during logout and restore it later, which introduces an avoidable invalid-state window.

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

### Phase 1 — Endpoint policy and safe transition

- Reusing the locked binding key made the locked-to-configurable upgrade a validation-only transition: a valid installation keeps its session without a preference migration or crash window.
- Separating the flow into a mutation-free network probe and a guarded post-logout write makes every failure boundary explicit. Phase 2 should preserve that order rather than embedding persistence in interface callbacks.
- The library-private validated-candidate type narrows the interface's safe path. Phase 2 should keep one `EndpointSwitcher` alive only for the Server Settings page, close it with the page lifecycle, and translate typed policy and probe failures into local messages.
- Endpoint behavior is shared Dart code, so focused adapter and preference tests cover the main safety invariants before either platform UI is installed. Phase 2 still needs widget coverage for confirmation, cancellation, progress, failure recovery, and return-to-sign-in behavior.

### Phase 2 — Interface and cross-platform artifacts

- Reusing the existing package and bundle identifiers lets the configurable
  artifacts replace the locked applications in place. Android retained its
  original first-install record, signed-in session, photos, and active binding;
  iOS retained its active local binding and opened without a startup diagnostic.
- A Tailscale IP is not interchangeable with its MagicDNS hostname for HTTPS.
  Museum remained healthy through the `.ts.net` origin while the app correctly
  rejected `100.100.190.42` because Tailscale Serve could not establish trusted
  TLS for the bare IP.
- Artifact verification needs both compile-time and runtime evidence. Wrapper
  guard tests and kernel inspection establish the build inputs; package,
  signature, ABI, and archive audits establish identity; visible Server controls
  plus retained account state establish that the installed mode and migration
  behavior match those inputs.
- The Android image enforces roughly 2.5 GiB of guest RAM even when launched with
  a 2 GiB request. Two cores, host graphics, no audio or boot animation, and
  disabled snapshots kept the host responsive during the preserved-state test.

### Phase 3 — As-built handoff

- Describing the isolated candidate probe separately from authenticated Museum
  traffic makes the credential and redirect boundaries easier to review than a
  single generic networking diagram.
- Configurable startup detects account state through an explicit preference-key
  list. Future shared-preferences account keys must extend that list so a
  missing binding continues to fail closed and activation remains post-logout.
- The companion's maintenance checklist now holds the cross-component
  invariants that would be easy to miss when changing only a wrapper, UI page,
  interceptor, or logout implementation.
