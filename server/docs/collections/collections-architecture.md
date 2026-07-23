# Collections Architecture, Ownership, and E2EE

This document is the canonical overview for Ente's collections architecture. It explains shared rules around add/move/remove, required encryption envelopes, and how server APIs enforce behavior across mobile and server clients.

## System Overview

- Each file can belong to one or more collections at the same time.
- Collections are owned by a single user and may be shared with other users (viewer, collaborator, admin) or exposed via a public link.
- Files can participate in collections owned by other users, provided the necessary keys are shared.

## Keys & Encryption Model

- Account master key: derived client side from the user's credentials; never leaves the client.
- Collection key: unique per collection; encrypted to the owner's master key and re-encrypted to each sharee using the owner's public key.
- File key: encrypts the file and its metadata. For each membership, the file key is re-encrypted with that collection key and stored as `(encryptedKey, keyDecryptionNonce)` alongside the membership.
- Implications:
  - Clients must already possess the destination collection key to add files or move them into that collection.
  - The server only stores opaque key envelopes and performs access control; it never decrypts collection or file contents.

## Ownership & Permission Rules

### Add files

- Allowed when the actor's role supports adding (owner, collaborator, admin) and every file ID is owned by the actor.
- Actors may add their files into collections they do not own, as long as they have the collection key (e.g. collaborator).

### Move files

- Moves are permitted only between collections owned by the actor.
- All files being moved must be uploaded and owned by the actor, and must already belong to the source collection.

### Remove files

- Collection owners may remove any file from their collection.
- Non-owners may only remove the files they own from that collection.
- Mobile clients implement owner removals as "auto-move" into another actor-owned collection when possible; see the strategy below.

### Trash

- Trashing is scoped to files that the actor owns or memberships the actor is allowed to manage.
- Server endpoint: `POST /files/trash`.

## Auto-Move Strategy for Owner-Owned Collections

When a user removes their own files from a collection they own:

- For each file, prefer an existing collection owned by the user where the file is already present.
- Exclude Favorites and Uncategorized from the preferred set.
- If no owned collection contains the file, move it to the user's Uncategorized (or hidden default for specific flows).
- Reference implementations:
  - Locker: `apps/locker/lib/services/collections/collections_service.dart:428`, `apps/locker/lib/services/collections/collections_service.dart:583`.
  - Photos: `apps/photos/lib/ui/actions/collection/collection_sharing_actions.dart:578`, `apps/photos/lib/ui/actions/collection/collection_sharing_actions.dart:720`.

## Core Server APIs and Expected Enforcement

- `POST /collections/add-files`
  - Require `role.canAdd` and ownership of every file ID.
  - Validate encrypted key envelopes (re-encrypted with the destination collection key).
- `POST /collections/move-files`
  - Restrict to moves between collections owned by the actor.
  - Ensure `collectionOwner == fileOwner` before updating memberships (add to target, mark deleted in source).
- `POST /collections/v3/remove-files`
  - Reject attempts to remove files owned by the collection owner when the actor is not that owner.
  - Allow removal when the caller owns the file or owns the collection.
  - If an admin tries to remove files owned by the collection owner:
    - Set `collection_files.action='REMOVE'` with `action_user` to the admin.
    - Create a `pending_actions` entry for the owner with `action='REMOVE'` and `data={fileIDs: [...]}`.
- `POST /files/trash`
  - Restrict to actor-owned files or memberships the actor can manage; used after deletion workflows.
- `GET /collections/v2/diff`
  - Returns per-collection updates, membership deletion flags, and E2EE envelopes.
  - If a membership row has `action` in {`REMOVE`,`DELETE`} and `is_deleted=false`:
    - For non-owners and public/cast diffs, the server masks it as `isDeleted=true` and omits `action`/`actionUser`.
    - For the file owner, the server includes `action` and `actionUser` so the client can take follow-up action.
  - The same masking applies for `action='DELETE_SUGGESTED'`.
- `GET /trash/v2/diff`
  - Provides trash sync updates (Locker client: `apps/locker/lib/services/collections/collections_api_client.dart:270`; Photos trash sync at `apps/photos/lib/services/sync/trash_sync_service.dart:154`).
- Sharing
  - Share collection: `POST /collections/share`.
  - Unshare: `POST /collections/unshare`.
  - Leave shared collection: `POST /collections/leave/{id}`.
  - Public link lifecycle: `POST /collections/share-url`, `PUT /collections/share-url`, `DELETE /collections/share-url/{id}`.

## Deletion Flows

- `DELETE /collections/v3/{collectionID}`
  - Owner-only; Favorites and Uncategorized cannot be deleted.
  - With `keepFiles=true`, the collection must already be empty.
  - With `keepFiles=false`, trash the owner's files, remove other users' memberships, revoke share URLs, and schedule deletion.
- Account deletion pipeline
  - Billing/family cleanup → token revocation → unshare shared collections → schedule deletion for owned collections → empty trash → remove table data, with retries and integrity checks.

## Client Behavior (Context)

- Mobile clients perform local validation before API calls: ownership checks, key availability, and E2EE re-encryption for add/move.
- Photos enforces that only actor-owned files can be added to non-owned collections.
- Clients use diff endpoints to keep local state in sync and trigger UI updates.

## Known Caveats and Validation

- "File must remain in at least one collection" is a client-side invariant; the server does not enforce it.
- Implement strict ownership checks before attempting moves; repositories also enforce the invariant.
- Perform basic validation on encrypted payload shape (length/base64) even though the server cannot decrypt content.

## References

- Server route registration: `ente/server/cmd/museum/main.go`.
- Access control: `ente/server/pkg/controller/access/collection.go`, `ente/server/pkg/controller/access/file.go`, roles in `ente/server/ente/access.go`.
- Collection controllers: `ente/server/pkg/controller/collections/file_action.go`, `ente/server/pkg/controller/collections/collection.go`, `ente/server/pkg/controller/collections/share.go`.
- Repositories: `ente/server/pkg/repo/collection.go`, membership helpers in `ente/server/pkg/repo/collection_files.go`.
- Locker client APIs: `apps/locker/lib/services/collections/collections_api_client.dart`, `apps/locker/lib/services/collections/collections_service.dart`.
- Photos clients: `apps/photos/lib/services/collections_service.dart`, `apps/photos/lib/ui/actions/collection/collection_sharing_actions.dart`, `apps/photos/lib/services/sync/trash_sync_service.dart`.
- Sharing package: `packages/sharing/lib/collection_sharing_service.dart`.

## Tips for New Developers

- Always re-encrypt the file key with the destination collection key when adding or moving files.
- Never attempt moves across collections you do not own; use copy plus add instead.
- Apply server-side ownership and role checks even if clients enforce them, to guard against legacy clients or misuse.
- Use diff endpoints (`/collections/v2/diff`, `/trash/v2/diff`) to drive sync loops and UI refreshes.
  - Suggest deletion: `POST /collections/suggest-delete` (owner or admin only). Suggests deleting files owned by others in the collection. The server sets `action='DELETE_SUGGESTED'` with `action_user=actor` and leaves `is_deleted=false`.
    - For owner-owned files, additionally set `action='REMOVE'` and create two `pending_actions` for the owner: one `REMOVE`, one `DELETE_SUGGESTED`.
    - For other users’ files, server removes the membership and creates a `pending_actions` entry for that user with `action='DELETE_SUGGESTED'`.

### Collection Actions

- Table: `collection_actions(id, user_id, actor_user_id, collection_id, file_id, data JSONB, action, is_pending, created_at, updated_at)`.
- ID uses nanoid (server/ente/base/id.go).
- `GET /collection-actions/pending-remove?sinceTime=<int64>` returns `REMOVE` actions for the authenticated owner so clients can guide the shared-collection workflow. Response: `{ "actions": [...], "hasMore": boolean }`.
- `GET /collection-actions/delete-suggestions?sinceTime=<int64>` returns `DELETE_SUGGESTED` actions; the server double-checks ownership and marks as resolved any entries whose files already exist as non-restored trash rows (either still in trash or already permanently deleted). Response: `{ "actions": [...], "hasMore": boolean }`.
- `POST /collection-actions/reject-delete-suggestions` accepts a list of file IDs and marks the matching pending delete suggestions as resolved for the caller.
- Clients act on these locally:
  - Owner processes `REMOVE` by ensuring file remains in at least one owned collection, then can finalize server-side removal.
  - `DELETE_SUGGESTED` prompts file owner to delete files locally if desired.
