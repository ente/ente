# Configurable Self-Hosted Mobile Server Architecture

**Status:** As built on 2026-07-14
**Scope:** Ente Photos mobile endpoint selection for the personal self-hosted
Android flavor and iOS target
**Living design:**
[ConfigurableSelfHostedMobileServer.md](ConfigurableSelfHostedMobileServer.md)
**Operator guide:**
[SELF_HOSTED_BUILD_GUIDE.md](../mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md)

---

## 1. What the implementation guarantees

The Android and iOS applications share one Dart endpoint implementation. Their
platform wrappers select configurable mode and supply a clean-install default;
they do not create separate networking stacks.

The implementation enforces these boundaries:

- One canonical HTTPS Museum origin is active at a time.
- A stored binding is authoritative after installation. Rebuilding with a new
  default does not silently move an existing account.
- A candidate is canonicalized and probed without credentials before any local
  state changes.
- A signed-in server change performs local logout before replacing the binding.
- Authenticated Museum requests can reach only the active origin and cannot
  follow redirects.
- Invalid managed state fails before the normal network client starts.
- Standard Ente builds retain their existing endpoint behavior.

Operating-system-trusted HTTPS remains the transport boundary. An IP address is
therefore not a substitute for a DNS name when the server certificate covers
only that name.

## 2. Components and ownership

```text
Android build wrapper ─┐
                      ├─ compile mode + clean-install default
iOS build wrapper ─────┘                 │
                                         v
                              EndpointPolicy (pure rules)
                                         │
                     stored binding ─> EndpointConfig
                                      /      |       \
                                     v       v        v
                           startup gate   switcher   NetworkClient
                                |         + probe         |
                                v            |            v
                         recovery screen     v       Museum interceptor
                                        Server page   same-origin guard
```

| Component | Responsibility |
|---|---|
| [Android wrapper](../mobile/apps/photos/scripts/build_self_hosted_android.sh) and [iOS wrapper](../mobile/apps/photos/scripts/build_self_hosted_ios.sh) | Require and validate `ENTE_SELF_HOSTED_ENDPOINT`, own flavor/target and Dart defines, and select configurable mode. |
| [EndpointPolicy](../mobile/apps/photos/lib/core/network/endpoint_policy.dart) | Resolve the compile-time mode, canonicalize origins, validate stored state, and compare request origins. It has no persistence or network I/O. |
| [EndpointConfig](../mobile/apps/photos/lib/core/network/endpoint_config.dart) | Own the shared-preferences binding, startup validation, logout preservation, guarded activation, and endpoint-update event. |
| [Application startup](../mobile/apps/photos/lib/main.dart) and [failure app](../mobile/apps/photos/lib/core/network/endpoint_policy_failure_app.dart) | Validate endpoint state before foreground or background initialization. Render a local recovery diagnostic instead of starting network services on failure. |
| [EndpointProbe and EndpointSwitcher](../mobile/apps/photos/lib/core/network/endpoint_switcher.dart) | Probe a canonical candidate with an isolated client and pass an opaque validated value into post-logout activation. |
| [Server Settings page](../mobile/apps/photos/lib/ui/settings/server/server_settings_page.dart) | Present the current origin, validation result, local-account-state confirmation, cleanup, activation, and return-to-login flow. |
| [NetworkClient](../mobile/apps/photos/lib/core/network/network.dart) | Build the Museum client from the effective endpoint and refresh its base URL after a successful activation. Keep generic and signed object-storage clients separate. |
| [EnteRequestInterceptor](../mobile/apps/photos/lib/core/network/ente_interceptor.dart) | Attach Museum authentication only after enforcing active-origin equality; disable redirects on authenticated managed requests. |
| [Configuration logout](../mobile/apps/photos/lib/core/configuration.dart) | Stop current work and clear credentials, databases, caches, notifications, and queued application state while the managed binding is preserved. |
| [Service locator](../mobile/apps/photos/lib/service_locator.dart) | Give startup, services, networking, and UI the same `EndpointConfig` instance. |

## 3. Modes and persistent state

`lockedEndpoint` and `configurableEndpoint` are mutually exclusive compile-time
booleans. Defining both is a startup error.

| Mode | Effective endpoint | Persistent binding | User switching | Production origin |
|---|---|---|---|---|
| Standard | Legacy runtime override, otherwise compiled default | No managed binding | Existing developer behavior | Allowed |
| Locked | Compiled endpoint, which must match the binding | Required | Disabled | Rejected |
| Configurable | Existing binding, otherwise compiled clean-install default | Required | Guarded Server Settings flow | Allowed |

Two preference names matter:

- `endpoint` is the legacy standard-mode runtime override. Its presence in a
  managed build is treated as unsafe state.
- `locked_endpoint_binding_v1` is the managed binding. The name intentionally
  remains stable so an earlier locked installation upgrades to configurable
  mode without migrating or losing its account.

The configurable compiled endpoint is only a clean-install default. Once a
valid binding exists, the binding wins even when the next artifact was built
with a different default.

### Startup state rules

```text
start
  |
  v
validate compile flags and endpoint syntax -- failure --> local recovery app
  |
  v
standard mode? -- yes --> use standard resolution
  |
  no
  v
legacy override present? -- yes --> fail closed
  |
  no
  v
binding present? -- no --> account state present? -- yes --> fail closed
  |                                      |
 yes                                     no
  |                                      v
  |                              bind managed default
  v
validate binding for current mode -- failure --> fail closed
  |
  v
start services and network clients
```

Locked mode additionally requires the binding to equal its compiled endpoint.
Configurable mode accepts any canonical HTTPS binding, including an official
Ente origin. Startup validation runs before the foreground client, before
background initialization, and again when `NetworkClient` initializes.

Managed logout preserves only the verified binding in shared preferences. A
new preference that represents signed-in account state must also be added to
`EndpointConfig`'s account-state key list; otherwise the pre-activation and
missing-binding guards would not know about it.

## 4. Network boundaries

The application uses two deliberately different HTTP paths.

The candidate probe creates a fresh client, attaches only an `Accept: application/json`
header, disables redirect following, and sends `GET <origin>/ping` with
15-second connection and response timeouts. Only a JSON object with
`message: pong` succeeds. The probe has no application cookies, token, shared
interceptor, or persistence access.

Normal Museum traffic uses the active origin as its base URL. When a managed
request carries authentication, the interceptor compares scheme, host, and
effective port with that origin. A mismatch is rejected locally, and redirect
following is disabled. The generic and download clients remain separate
because Museum intentionally supplies presigned object-storage destinations.

This feature does not attempt network-wide allowlisting. Ancillary Ente and
third-party services are outside its boundary; authenticated Museum traffic is
inside it.

## 5. Validated server-switch sequence

```text
User / Server page       Isolated probe        Local account       Binding / client
        |                      |                     |                    |
        | canonical candidate |                     |                    |
        |--------------------->|                     |                    |
        |                      | GET /ping, no auth  |                    |
        |<--- valid candidate -|                     |                    |
        |                      |                     |                    |
        | same as active? ----------------------------------------> no-op |
        |                      |                     |                    |
        | local account state: confirm old origin -> new origin        |
        |-------------------------------------------->| stop + logout     |
        |<--------------------------------------------| cleanup complete  |
        |---------------------------------------------------------------->|
        |                       activate validated binding; emit update   |
        |<---------------------------------------------------------------|
        |                         return to sign-in                       |
```

The ordering produces explicit failure states:

| Failure point | Result |
|---|---|
| Syntax or `/ping` validation | Account and old binding are unchanged. |
| User cancels confirmation | Account and old binding are unchanged. |
| Local logout fails | Old binding remains; activation is not attempted. |
| Binding write fails after logout | The user is logged out and the old binding remains. The page reports a recoverable error. |
| Successful activation | The new canonical binding is stored, one endpoint-update event refreshes the Museum base URL, and the user returns to sign-in. |

`ValidatedEndpoint` has a library-private constructor. This prevents the UI
from manufacturing a candidate and accidentally bypassing the isolated probe.
The Server page treats any known account preference as cleanup-required state,
including an email saved before passkey or password authentication completes.
It confirms and runs the same local logout path before activation even when no
token exists.
`EndpointConfig` independently rejects activation while known account
preferences or a legacy runtime override remain, so callback ordering is not
the only guard.

The Server control is shown only in configurable builds. Signed-in users reach
it from Settings; signed-out users can reach the same page from landing,
account creation, and login. Locked and configurable modes both disable the
legacy seven-tap developer endpoint editor.

## 6. Packaging, upgrades, and rollback

The wrappers preserve the existing personal `selfhosted` Android identity and
iOS target identity. A configurable artifact can therefore replace the earlier
locked artifact in place. If its existing binding is valid, the upgrade retains
the active origin, session, and local data even when the wrapper was given a
different default.

Before a successful server change, reverting to the matching locked artifact
is safe. After the binding changes, installing a locked artifact compiled for a
different origin fails closed; recovery requires clearing/reinstalling the app
or rebuilding the locked artifact for the stored origin. Build commands,
signing inputs, endpoint examples, and operator rollback steps live in the
[build guide](../mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md).

## 7. Verification and change checklist

The principal automated evidence lives in:

- [endpoint_policy_test.dart](../mobile/apps/photos/test/core/network/endpoint_policy_test.dart)
  for mode resolution, migration, startup state, logout preservation, and
  authenticated origin comparison;
- [endpoint_switcher_test.dart](../mobile/apps/photos/test/core/network/endpoint_switcher_test.dart)
  for isolated probes, redirect rejection, no-mutation failures, and guarded
  activation; and
- [server_settings_page_test.dart](../mobile/apps/photos/test/ui/settings/server_settings_page_test.dart)
  for visibility, confirmation, cancellation, ordering, navigation, and UI
  failure states.

The completed implementation was also checked with all Photos tests and the
analyzer, wrapper guard tests, endpoint validation, iOS and Android builds,
package/signature/archive inspection, an iOS Simulator recovery from an
email-without-token login state, and an in-place Android emulator upgrade that
retained account state.

When changing this area, preserve these invariants:

1. Do not rename or clear `locked_endpoint_binding_v1` during managed logout.
2. Do not write a candidate before its isolated probe and, whenever complete
   or partial local account state exists, successful local logout.
3. Do not attach authentication, shared cookies, or redirects to the probe.
4. Do not let authenticated Museum traffic escape the active origin.
5. Do not apply the Museum-origin rule to presigned object-storage clients.
6. Keep the build modes exclusive and the platform wrappers in control of
   their Dart defines.
7. Update the account-state key guard whenever persisted account state gains a
   new shared-preferences key.
8. Extend the focused tests before changing startup, logout, or activation
   ordering.
