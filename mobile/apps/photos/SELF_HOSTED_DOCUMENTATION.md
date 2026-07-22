# Self-Hosted Ente Photos Mobile Documentation

This is the starting point for building, operating, testing, or maintaining the
self-hosted Android and iOS applications in this fork. Choose the document by
role; do not copy deployment-specific values into this public repository.

## Current verified state

| Platform | Application identity | Source/release state | Acceptance state |
|---|---|---|---|
| Android | `me.vanton.ente.photos.selfhosted` | Source `1.3.59+2159`; Firebase build `2159` | Owner and non-owner installation, sign-in, upload/download, update, and persistence verified |
| iOS | `me.vanton.ente.photos.selfhosted` | Marketing version `1.3.59`; Firebase build `2161` | Owner installation, sign-in, upload/download, update, and persistence verified; no real non-owner iPhone/iPad acceptance yet |

Every later Android publication needs a version code higher than `2159`.
Every later iOS publication needs a `CFBundleVersion` higher than `2161`. The
iOS non-owner flow must begin with Firebase registration on a real tester
iPhone or iPad; do not reuse a copied, Mac, simulator, or otherwise unverified
device identifier.

Source compatibility was last audited on 2026-07-21 by merging official Ente
commit `383aa8a687cbf3224fe1c2f5c1f42e9ef0645309` through the guarded upstream
synchronization workflow. Full mobile analysis, focused self-hosted tests in
configurable and locked modes, dependency restoration, stable Rust generation,
CocoaPods deployment verification, and tracked-Dart formatting passed. Platform
builds were not requested, and no application was installed or published, so
the Firebase baselines in the table remain the current distributed releases
until a later release workflow uses higher build numbers.

Both applications compile a configurable HTTPS Museum default and provide the
guarded Server Settings flow. A stored binding survives an in-place update.
Changing server while signed in requires confirmed local logout before the new
binding and account flow become active.

## Choose the right guide

| I need to… | Audience | Canonical document |
|---|---|---|
| Configure toolchains, validate an endpoint, build, audit, or inspect an APK/IPA | Operator or maintainer | [Mobile build guide](SELF_HOSTED_BUILD_GUIDE.md) |
| Prepare, publish, update, offboard, or recover an Android Firebase release | Operator | [Android closed-beta operations](SELF_HOSTED_ANDROID_DISTRIBUTION_GUIDE.md) |
| Manage Apple devices/profiles and prepare, publish, update, offboard, or recover an iOS Firebase release | Operator | [iOS closed-beta operations](SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md) |
| Accept an invitation, install the app, connect Tailscale, select the server, or run the acceptance test | Android or iOS tester | [Tester onboarding guide](SELF_HOSTED_TESTER_ONBOARDING_GUIDE.md) |
| Understand endpoint modes, stored binding, switching, rollback, and network boundaries | Maintainer | [Configurable-server architecture](../../../living_docs/ConfigurableSelfHostedMobileServerArchitecture.md) |
| Understand Ad Hoc signing, immutable iOS preparation, Firebase evidence, and recovery boundaries | Maintainer or operator | [iOS distribution architecture](../../../living_docs/FirebaseIOSDistributionArchitecture.md) |
| Run, pause, recover, or review an official Ente synchronization | Maintainer or operator | [Upstream synchronization runbook](../../../UPSTREAM_SYNC.md) |
| Understand the synchronization state machine, permissions, provenance, and safety boundaries | Maintainer | [Upstream synchronization architecture](../../../living_docs/UpstreamEnteSynchronizationArchitecture.md) |
| Understand the fork workflow allowlist, checks, permissions, branch protection, and upstream adoption | Maintainer | [Fork GitHub Actions architecture](../../../living_docs/ForkGitHubActionsArchitecture.md) |

The tester guide is the only current document intended to be sent directly to
testers. The operator supplies the exact Firebase invitation, Tailscale access,
Museum origin, web-app origin, and account instructions privately.

## Document ownership

- The **build guide** owns build and audit command contracts, common endpoint
  behavior, and private-network prerequisites.
- The **Android and iOS operations guides** own operator-controlled release,
  access, update, offboarding, and recovery procedures.
- The **tester guide** owns everything a tester performs on a device.
- The **architecture documents** explain current system boundaries and settled
  behavior; they are not recurring release checklists.
- The **upstream synchronization runbook** owns current drift, integration,
  validation, publication, and recovery commands.
- The **fork GitHub Actions architecture** owns the current workflow allowlist,
  merge gates, permissions, path filtering, and automation adoption policy.
- The **living documents** preserve project decisions and acceptance evidence.
  They are historical implementation records, not current runbooks.
- The Photos [README](README.md) is a contributor entry point, not another
  self-hosted manual.

When the same subject crosses roles, the canonical guide contains the complete
procedure and the other documents contain only the handoff and a link.

## Historical implementation records

These records remain useful for provenance, rejected alternatives, version
cutovers, and acceptance evidence. Their task trackers and example paths are
historical; use the current guides above for operations.

| Record | What it preserves |
|---|---|
| [Configurable mobile server](../../../living_docs/ConfigurableSelfHostedMobileServer.md) | Endpoint-policy implementation, server-switch UX, upgrades, iOS recovery, and physical-device proof |
| [Firebase Android distribution](../../../living_docs/FirebaseAndroidDistribution.md) | Android identity cutover, guarded Firebase pipeline, receipts, owner/non-owner acceptance, and no-upload reconciliation |
| [Firebase iOS distribution](../../../living_docs/FirebaseIOSDistribution.md) | Apple/Firebase setup, builds `2160` and `2161`, owner acceptance, and the deferred non-owner device premise |
| [Locked self-hosted Android](../../../living_docs/LockedSelfHostedAndroid.md) | Superseded fixed-endpoint Android baseline and early device evidence |
| [Locked self-hosted iOS](../../../living_docs/LockedSelfHostedIOS.md) | Superseded fixed-endpoint iOS baseline, local-server setup, and backup-recovery proof |
| [Documentation consolidation](../../../living_docs/SelfHostedMobileDocumentationConsolidation.md) | Inventory, authority decisions, privacy cleanup, and final validation evidence for this documentation set |

## Private-state boundary

Keep these outside Git and public communication:

- real server and object-storage hostnames, local quickstart paths, and network
  policy details;
- Firebase project/App IDs when avoiding an operational binding, tester email
  addresses, invitation URLs, authentication state, and release receipts;
- Apple Team ID, device names and identifiers, provisioning profiles,
  certificates/private keys, and signing inputs;
- Museum credentials, recovery keys, verification codes, tester media, and
  screenshots containing identity or account data; and
- Android keystores/passwords plus private APK/IPA artifacts and manifests.

The public source commit URL, application identities, source version, build
number, and artifact hash may appear in generated release notes. Store the
private binding and immutable evidence ledger in operator-controlled storage.

## Maintenance checklist

When source or distribution behavior changes:

1. Update the canonical guide that owns the procedure, not every document that
   mentions it.
2. Update the current-state table after the corresponding owner or tester
   acceptance evidence exists; distinguish owner-only from non-owner proof.
3. Keep application identities, minimum/target SDK claims, build versions,
   script names, fixed Firebase group aliases, and compiled endpoint policy in
   sync with source.
4. Recheck external retention, invitation, Apple device/profile, Developer
   Mode, and Tailscale claims against their official documentation and record
   the verification date in the applicable guide.
5. Validate relative links, shell syntax, documented `--help` surfaces,
   Markdown whitespace, and the private-value scan before committing.

This index and the linked current guides were consolidated and checked on
2026-07-20.
