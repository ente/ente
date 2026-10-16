# Ente Auth watchOS companion — documentation index

This folder is the full specification for a native Apple Watch companion to Ente Auth. The implementation is the Swift target `mobile/apps/auth/ios/EnteAuthWatch`, the phone bridge `EnteWatchBridgePlugin.swift`, and `watch_sync_service.dart`. These files live under `docs/auth-watch/` on purpose, so they do not become the monorepo's agent instructions. Do not edit the repository-root `AGENTS.md` or `CLAUDE.md`, and do not edit `/Volumes/MacExt/ente/docs/CLAUDE.md` or `/Volumes/MacExt/ente/docs/README.md`. Those files are unrelated Ente docs.

A coding agent with no prior chat can implement Phase 1 from this folder alone. Read in this order:

1. [REQUIREMENTS.md](REQUIREMENTS.md) — numbered requirements, acceptance criteria, and the mapping from spec words to symbols that exist today.
2. [PROPOSAL.md](PROPOSAL.md) — the product proposal: problem, autonomous watch node, phasing, non-goals.
3. [architecture.md](architecture.md) — topology, process boundaries, data flow, failure modes, graphify scope.
4. [DESIGN.md](DESIGN.md) — watch UI states, crown, haptics, complications, phone settings.
5. [SYNC-CONTRACT.md](SYNC-CONTRACT.md) — versioned JSON, field mapping, delta rules, WCSession choice.
6. [MATH.md](MATH.md) — HOTP, TOTP, base32, Steam, clock skew, the integer-modulus review comment.
7. [THREAT-MODEL.md](THREAT-MODEL.md) — seeds, adversaries, Keychain, residual risks.
8. [PLAN.md](PLAN.md) — three pull-request phases, proposed file paths, test plan.
9. [INTEGRATION.md](INTEGRATION.md) — where code lands in this checkout, `gh` commands, Xcode wiring.
10. [AGENTS.md](AGENTS.md), [CLAUDE.md](CLAUDE.md), and [SKILL.md](SKILL.md) — constraints for the coding agent. Read these before editing Swift or Dart.

[REFERENCES.md](REFERENCES.md) records which URLs were verified and how. [prd.md](prd.md) is the product requirements view (personas, stories, metrics, open questions) and sits beside REQUIREMENTS.md.

## Fact labels

- **EXTRACTED** — present in the Ente Auth source, the architectural spec, Apple's or the RFC's text, or a `gh` response.
- **INFERRED** — a recommendation added so an implementer can choose. It is not an existing module, call, or setting.

Graphify semantic edges are similarities inferred by the graph tool. They are not call edges. See [architecture.md](architecture.md).

## Workspace

This documentation assumes the checkout at `/Volumes/MacExt/ente`, which is already [ente](https://github.com/ente/ente). Do not clone a second copy over that path. Auth code is `mobile/apps/auth` (`ente_auth` 4.4.27+1007). There is no separate Auth GitHub repository.
