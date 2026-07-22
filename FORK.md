# About This Fork

This repository is an independently maintained fork of the official
[`ente/ente`](https://github.com/ente/ente) monorepo. Its purpose is to build
and privately distribute Ente Photos applications for Android and iOS that can
connect safely to a self-hosted Ente server.

The fork preserves Ente's source and Git history and regularly incorporates
official upstream changes. It is not affiliated with, endorsed by, or
supported by Ente, and its mobile builds are not official Ente releases.

## Differences at a glance

| Area | Official upstream | This fork |
|---|---|---|
| Primary mobile service | Official Ente Photos applications and service | Dedicated Ente Photos applications intended for a privately operated, self-hosted Ente deployment |
| Server selection | Existing upstream endpoint behavior | A supported configurable mode with a compiled clean-install default and guarded **Server Settings** flow |
| Server switching | Upstream behavior | The candidate HTTPS server is validated without credentials; changing servers with local account state requires confirmation and local logout before activation |
| Application identity | Official Ente package and bundle identities | Android package and iOS bundle identifier `me.vanton.ente.photos.selfhosted`, allowing the fork to coexist with official applications |
| Mobile packaging | Upstream Android flavors and iOS targets | An additive Android `selfhosted` flavor and core-only iOS `SelfHostedRunner` target; existing upstream variants remain unchanged |
| Distribution | Ente's official distribution channels | Closed-group Android and iOS distribution through guarded Firebase App Distribution workflows; iOS uses Apple Ad Hoc device provisioning |
| Release tooling | Upstream release processes | Fork-specific build, audit, immutable preparation, confirmation, publication, receipt, and recovery scripts |
| Upstream maintenance | Source of official Ente development | Daily/manual drift reporting plus a guarded local synchronization command that opens a reviewable pull request and never merges it automatically |
| GitHub Actions | Official Ente production, product, deployment, and release automation | An exact fork-owned allowlist for self-hosted mobile, dependency/workflow security, and upstream drift; no signing, publication, deployment, or operational secrets |

Most fork-specific runtime changes are limited to Ente Photos mobile. The rest
of the monorepo follows upstream unless a compatibility, documentation, test,
or maintenance change is required to support those applications.

## Self-hosted server behavior

Both mobile applications use the same Dart endpoint implementation. A
self-hosted build receives a default Museum HTTPS origin at build time. On a
clean installation that becomes the stored server binding; afterward, the
stored binding remains authoritative across application updates.

The guarded server flow provides these protections:

- only a canonical HTTPS origin is accepted;
- a candidate must return the expected response from `/ping` before it can be
  selected;
- validation uses an isolated request without application credentials and
  without following redirects;
- authenticated Museum requests are restricted to the active origin and do
  not follow redirects;
- changing servers while signed in, or during an incomplete login, requires
  local account cleanup before the new binding is activated; and
- invalid managed endpoint state stops startup with a local recovery message
  instead of silently falling back to another server.

The endpoint feature controls Museum API traffic. It is not a network-wide
allowlist: presigned object-storage downloads and ancillary Ente or third-party
services retain their separate upstream networking behavior. Devices must
trust the server's TLS certificate; using a raw IP address does not work when
the certificate covers only a DNS name.

For the implementation details and threat boundaries, see the
[configurable-server architecture](living_docs/ConfigurableSelfHostedMobileServerArchitecture.md).

## Application identity and private distribution

The self-hosted applications use identities separate from the official Ente
applications:

- Android release package: `me.vanton.ente.photos.selfhosted`
- Android debug package: `me.vanton.ente.photos.selfhosted.debug`
- iOS bundle identifier: `me.vanton.ente.photos.selfhosted`

Android releases are signed with fork-owner material kept outside Git. iOS
releases use an Apple Ad Hoc provisioning profile containing the authorized
tester devices. Both platforms are delivered to a closed tester group through
Firebase App Distribution. Signing material, Firebase bindings, tester
identities, device identifiers, private server addresses, and release
artifacts are deliberately excluded from this public repository.

These workflows are intended for a private testing group, not for the Google
Play Store or Apple App Store.

## Relationship with upstream Ente

The `upstream` Git remote fetches official `ente/ente` and has pushing disabled.
A scheduled GitHub workflow reports when upstream is ahead but cannot modify
source history. The fork owner then runs the guarded local synchronization
command, which:

1. verifies the fork, upstream, branch, and worktree state;
2. merges an exact official upstream commit on an isolated sync branch while
   preserving both histories;
3. restores dependencies and validates generation, focused self-hosted tests,
   formatting, and full mobile analysis;
4. optionally performs guarded Android and iOS builds;
5. requires an exact owner confirmation before pushing; and
6. opens a pull request into this fork's `main` branch without approving or
   merging it.

This process keeps upstream catch-up reviewable and prevents synchronization
from publishing applications, changing the private server, or modifying Apple,
Firebase, Tailscale, signing, tester, or device state.

See [Synchronize This Fork with Official Ente](UPSTREAM_SYNC.md) for the
operator procedure and the
[upstream synchronization architecture](living_docs/UpstreamEnteSynchronizationArchitecture.md)
for its provenance and safety model.

Pull requests into fork `main` must pass five fork-owned GitHub Actions gates.
Expensive mobile and CodeQL work runs only for relevant changes, while stable
checks still report for documentation-only pull requests. See the
[fork GitHub Actions architecture](living_docs/ForkGitHubActionsArchitecture.md)
for the exact allowlist, permissions, branch protection, and upstream-adoption
procedure.

## Documentation map

Start with the
[self-hosted mobile documentation index](mobile/apps/photos/SELF_HOSTED_DOCUMENTATION.md).
It routes each audience to the current canonical guide:

- [build and artifact auditing](mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md);
- [Android closed-beta operations](mobile/apps/photos/SELF_HOSTED_ANDROID_DISTRIBUTION_GUIDE.md);
- [iOS closed-beta operations](mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md);
- [Android and iOS tester onboarding](mobile/apps/photos/SELF_HOSTED_TESTER_ONBOARDING_GUIDE.md);
- [configurable-server architecture](living_docs/ConfigurableSelfHostedMobileServerArchitecture.md); and
- [upstream synchronization](UPSTREAM_SYNC.md); and
- [fork GitHub Actions architecture](living_docs/ForkGitHubActionsArchitecture.md).

Files under `living_docs/` preserve implementation decisions and acceptance
evidence. Unless explicitly marked as current architecture, they are historical
project records rather than operational instructions.

## Scope and non-goals

This fork is intentionally focused. It does not claim to:

- replace or represent the official Ente project or service;
- provide official Ente support;
- operate a public multi-tenant Ente service;
- publish these fork-specific applications through public app stores;
- make every ancillary mobile dependency or network service self-hosted;
- embed deployment credentials or private infrastructure details in Git; or
- automatically merge upstream changes or publish mobile releases.

General Ente server installation and administration remain documented by the
upstream project. This fork adds mobile-client, private-distribution, and
maintenance guidance specific to its self-hosted applications.

## License and attribution

Ente is the upstream project and retains its applicable names, trademarks, and
copyrights. This fork keeps the repository's GNU Affero General Public License
Version 3; see [LICENSE](LICENSE) for the complete terms. Source links included
with privately distributed builds point to the exact public commit from which
the artifact was produced.
