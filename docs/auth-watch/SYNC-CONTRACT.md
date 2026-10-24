# Sync contract

Version 1 of the phone-to-watch payload. Field names match the architectural spec. Mapping rules match the Dart types that exist today. See [REQUIREMENTS.md](REQUIREMENTS.md) R12–R17 and R24–R25.

## Transport

| API | Apple's documented behavior (fetched from Apple's documentation JSON) | Phase 1 |
| :---- | :---- | :---- |
| `WCSession.updateApplicationContext` | Replaces the previous dictionary. May be called while the counterpart is unreachable. The counterpart receives the most recent context. | **Use this.** |
| `WCSession.transferUserInfo` | Queues dictionaries on the other device and delivers them in send order. A transfer that has started continues if the app is suspended. | Do not use in Phase 1. |

**INFERRED.** Each Phase 1 message is a complete picture of the eligible set. `updateApplicationContext` matches that, because a newer edit replaces an undelivered older edit. `transferUserInfo` is the right tool for a future mode that must deliver every incremental dictionary in order. Using both in one phase lets a queued dictionary land after a newer context.

The dictionary must contain property-list types. Send JSON object keys as strings, numbers as integers, and arrays as arrays. The base32 secret is a string. Apple carries the dictionary. The app does not wrap that string in a second cipher in Phase 1.

## Envelope

```json
{
  "version": 1,
  "timestamp": 1775736000,
  "syncType": "DELTA",
  "tokens": [],
  "deletedIds": []
}
```

| Field | Type | Meaning |
| :---- | :---- | :---- |
| `version` | int | `1`. The watch ignores unknown versions. |
| `timestamp` | int | Unix seconds when the phone built the payload. Informational. The watch does not set its clock from this field. |
| `syncType` | string | `"DELTA"`. **INFERRED definition for v1:** `tokens` is the full eligible set, not a sparse patch. `deletedIds` lists ids to remove. A watch that replaces its local set with `tokens` and then deletes `deletedIds` converges even if it missed an earlier message. |
| `tokens` | array | Eligible `WatchToken` objects. |
| `deletedIds` | array of strings | Ids that must not remain on the watch. |

`timestamp` in the spec example (`1775736000`) is only an example.

## Token object

```json
{
  "id": "42",
  "issuer": "GitHub",
  "account": "octocat@github.com",
  "secret": "JBSWY3DPEHPK3PXP",
  "algorithm": "SHA1",
  "digits": 6,
  "period": 30,
  "isFavorite": true,
  "sortOrder": 0
}
```

The sample secret `JBSWY3DPEHPK3PXP` is the spec's example (base32 for the ASCII bytes of `Hello!`). It is not a user seed. Production payloads contain real seeds in this same plaintext field.

## Field mapping

| JSON | Source | Notes |
| :---- | :---- | :---- |
| `id` | `code.generatedID.toString()` | Omit the code when `generatedID` is null. Never use `selectionKey` or `rawData`. |
| `issuer` | `code.issuer` | |
| `account` | `code.account` | |
| `secret` | `getSanitizedSecret(code.secret)` | Uppercase, trim, remove spaces (`totp_util.dart`). |
| `algorithm` | `code.algorithm.name.toUpperCase()` | `SHA1`, `SHA256`, or `SHA512`, matching `Algorithm` in `code.dart` and `WatchToken.HashAlgorithm`. |
| `digits` | `code.digits` | Default constant `Code.defaultDigits` is 6. Steam's constant is 5; Steam is not included. |
| `period` | `code.period` | Default `Code.defaultPeriod` is 30. |
| `isFavorite` | `code.display.pinned` | The Dart field is `pinned`, via `Code.isPinned`. |
| `sortOrder` | index after the home-screen sort | R16. |

Not transferred: `note`, `tags` (except as the `#watch` filter), `iconSrc`, `iconID`, `counter`, `rawData`, `tapCount`, `lastUsedAt`, `trashed`.

## Inclusion

Start from `List<Code>`. Drop, in order:

1. `hasError`
2. `generatedID == null`
3. `isTrashed`
4. `type == Type.hotp`
5. `type == Type.steam` or `issuer.toLowerCase() == 'steam'`
6. If `syncAll` is false: drop unless `isPinned` or a tag equals `#watch` after trim

Sort the survivors with the same rules as `HomePage.sortFilteredCodes` for the current `CodeSortKey`. Assign `sortOrder` from 0.

## deletedIds

The caller passes ids that were in the previous successful payload and are absent from this `tokens` array. The function also unions any ids the caller already put in `deletedIds` (explicit deletes it observed).

The watch:

1. Upserts every token in `tokens` (replace Keychain bytes and metadata on id collision).
2. Deletes every id in `deletedIds`.
3. Because v1 `tokens` is the full eligible set, also deletes any local id that is in neither list. Step 3 makes a lost `deletedIds` entry converge on the next successful context.

Ids are opaque strings. Apply deletions after upserts so an id cannot be both updated and removed in one message; builders must not place an id in both arrays. If they do, deletion wins.

## Idempotency

Applying the same dictionary twice leaves the same Keychain set. `updateApplicationContext` may deliver the same latest context again after relaunch (`receivedApplicationContext`). Handlers must tolerate that.

## Size

One token is a few hundred bytes. The default subset exists because people keep 30 to 100 accounts and because a full vault makes a larger dictionary. If `updateApplicationContext` fails, report failure without logging secrets. Do not fall back to writing the JSON into a file.

## Dart signature

**INFERRED**, recommended, not present in the repo:

```dart
WatchSyncPayload buildWatchPayload(
  List<Code> codes, {
  required bool syncAll,
  required Set<String> deletedIds,
  CodeSortKey sortKey = CodeSortKey.issuerName,
});
```

`WatchSyncPayload` is a small Dart class with `version`, `timestamp`, `syncType`, `tokens`, and `deletedIds`, and a `Map<String, Object?> toJson()`. The method channel sends `toJson()`.

The iOS side method name is `syncTokens`. It accepts that map and calls `WCSession.default.updateApplicationContext`. It does not compute OTP and does not call back into Dart with a code.

## Swift model

From the spec, to be added on the watch target:

```swift
public struct WatchToken: Identifiable, Codable, Sendable {
    public let id: String
    public let issuer: String
    public let account: String
    public let secret: String
    public let algorithm: HashAlgorithm
    public let digits: Int
    public let period: Int
    public let isFavorite: Bool
    public let sortOrder: Int

    public enum HashAlgorithm: String, Codable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }
}
```

Decode `secret` into the scrubbing buffer (R11) before HMAC. Persist the raw bytes in the Keychain under account `id`.

## Channel

| Direction | Mechanism | When |
| :---- | :---- | :---- |
| Flutter → iOS runner | `MethodChannel('io.ente.auth/watch')` method `syncTokens` | After `CodesUpdatedEvent`, debounced so a burst of edits sends one context. |
| iOS runner → watch | `WCSession.updateApplicationContext` | Inside `syncTokens`. |
| Watch → Flutter | none in Phase 1 | Codes are computed on the watch. |
