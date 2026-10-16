# Math and algorithms

Standards cited here were fetched and returned HTTP 200. Test values below are the public appendix vectors, copied as the short rows an implementer must match. Full documents:

- HOTP: [RFC 4226](https://www.rfc-editor.org/rfc/rfc4226) (also [datatracker HTML](https://datatracker.ietf.org/doc/html/rfc4226)). M'Raihi, Bellare, Hoornaert, Naccache, Ranen, 2005.
- TOTP: [RFC 6238](https://www.rfc-editor.org/rfc/rfc6238) (also [datatracker HTML](https://datatracker.ietf.org/doc/html/rfc6238)). M'Raihi, Machani, Pei, Rydell, 2011.
- Base 32: [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648).

NIST SP 800-63B is referenced at the end as authenticator guidance. This watch app is not claimed to meet AAL2.

## HOTP (RFC 4226)

Shared secret `K`. Counter `C` is an 8-byte big-endian integer.

```
HS = HMAC-SHA-1(K, C)          // 20 bytes
offset = HS[19] & 0x0f         // low 4 bits of the last byte
P = HS[offset..offset+4] as a 31-bit big-endian integer
HOTP = P mod 10^Digit
```

Bit layout of the 4-byte window:

```
byte0        byte1     byte2     byte3
0xxxxxxx     xxxxxxxx  xxxxxxxx  xxxxxxxx
^
high bit cleared (0x7fffffff) so P is treated as unsigned
```

The RFC clears that bit so a signed 32-bit interpretation cannot flip the value negative. That is a language-interop rule, not extra entropy.

### Public test vector (Appendix D)

`K` is the 20 ASCII bytes `12345678901234567890` (this is raw key material, not a base32 string). Digit = 6. Count 0:

| Count | Truncated hex | Decimal | HOTP |
| :---- | :---- | :---- | :---- |
| 0 | `4c93cf18` | 1284755224 | **755224** |

`1284755224 mod 1000000 = 755224`. The same appendix lists count 1 as **287082**. The watch engine must reproduce count 0 before any UI work.

The spec's `computeHOTP` is this function with the hash selected by `WatchToken.HashAlgorithm`. HMAC-SHA-1 uses `HMAC<Insecure.SHA1>`. SHA-256 and SHA-512 use `HMAC<SHA256>` and `HMAC<SHA512>`. CryptoKit's `Insecure.SHA1` is the API name for SHA-1; HOTP and TOTP still specify SHA-1 as a legal algorithm.

## TOTP (RFC 6238)

```
T = floor((CurrentUnixTime - T0) / X)
TOTP = HOTP(K, T)
```

`X` defaults to 30 seconds. `T0` defaults to 0. Digit is often 6 and sometimes 8. The RFC appendix uses 8 digits so the vectors are unambiguous.

`T` is an integer counter. Implement it with integer unix seconds:

```swift
let unix = UInt64(date.timeIntervalSince1970)
let counter = unix / UInt64(period)
let remaining = Double(period) - Double(unix % UInt64(period))
```

**INFERRED review comment** on the spec snippet, which divides `timeIntervalSince1970` in `Double`: integer division matches the RFC's floor definition and avoids a floating counter near large timestamps. The snippet is a proposal. It is not code in this repository.

### Public test vector (Appendix B)

`X = 30`, `T0 = 0`. For SHA-1, `K` is the same 20 ASCII bytes `12345678901234567890`. SHA-256 uses that string repeated to 32 bytes (`12345678901234567890123456789012`). SHA-512 uses it repeated to 64 bytes. These keys are raw, not base32.

At unix time 59, `T = floor(59 / 30) = 1` (`0x1`). Eight-digit TOTP:

| Mode | TOTP |
| :---- | :---- |
| SHA-1 | **94287082** |
| SHA-256 | **46119246** |
| SHA-512 | **90693936** |

The SHA-1 eight-digit value ends in the six-digit HOTP for counter 1 (`287082`). A test that hardcodes SHA-1, or that requests 6 digits against the 8-digit vector, will fail for the wrong reason. The watch `switch` must pass SHA-256 and SHA-512 through their own HMAC.

Phone path for decimal TOTP: `otp.OTP.generateTOTPCodeString` in `mobile/apps/auth/lib/utils/totp_util.dart`, with `algorithm` mapped from `Algorithm.sha1` / `sha256` / `sha512`, `isGoogle: true`, and the time from `millisecondsSinceEpoch()`. After the Swift engine matches the RFC vectors, add one cross-check: the same base32 secret and the same unix time produce the same digits as that Dart call. The phone package is `otp` 3.2.0 (`https://github.com/daegalus/dart-otp`).

## Dynamic truncation in the spec's CryptoKit shape

```swift
let offset = Int(hashData[hashData.count - 1] & 0x0f)
let slice = hashData.subdata(in: offset..<(offset + 4))
var number = slice.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
number &= 0x7fff_ffff
let otp = number % modulus
return String(format: "%0*u", digits, otp)
```

`load(as: UInt32.self)` assumes the platform endianness of the load, then `.bigEndian` swaps to host order. On little-endian Apple platforms that pair matches the RFC's big-endian window. The test vectors are the check. If a vector fails, fix the endian load before touching the HMAC.

### Review comment: floating-point modulus

The spec snippet contains:

```swift
let modulus = UInt32(pow(10.0, Double(digits)))
```

`pow` is a floating-point function. Casting a value that is even slightly under an exact power of ten truncates to the wrong modulus. **INFERRED recommendation:** compute the modulus with an integer loop into `UInt64` (10^9 fits in `UInt32` as well; `UInt64` leaves room if a URI asks for a longer code). `CodeWidget` already formats lengths 6 through 9, so do not assume every code is 6 digits.

```swift
func modulus(digits: Int) -> UInt64 {
    precondition(digits >= 1 && digits <= 10)
    var value: UInt64 = 1
    for _ in 0..<digits { value *= 10 }
    return value
}
```

This comment is about the proposal snippet. There is no production watch engine in the repo yet.

## Base32

otpauth secrets use the RFC 4648 base32 alphabet (`A`–`Z` and `2`–`7`). Padding is `=`. Many otpauth URIs omit the padding.

`getSanitizedSecret` in `totp_util.dart`:

```dart
secret.toUpperCase().trim().replaceAll(' ', '')
```

The watch decoder must accept that sanitized form, including a missing `=` pad. The spec example `JBSWY3DPEHPK3PXP` is unpadded base32 for `Hello!` and is a fixture, not a user secret.

RFC test keys in the appendices are ASCII, not base32. Unit tests should call `computeHOTP` with raw `Data` for those vectors, and call the base32 front door for otpauth secrets.

## Remaining time and the next code

```
remainingSeconds = X - (unixSeconds mod X)
```

Show the next code when `remainingSeconds <= 5`. The next code is HOTP at `T + 1`, which is the same as evaluating TOTP one period ahead. On the phone, `getNextTotp` adds `period * 1000` milliseconds before calling `generateTOTPCodeString`. For Steam, the phone adds `period` seconds and then calls `SteamTOTP.generate`. The watch's five-second rule is the spec. The phone shows the next code for the whole period (`CodeWidget`).

## Steam Guard

**EXTRACTED** from `steam_totp` 0.0.2, file `lib/src/steam_totp_base.dart` at tag `v0.0.2` of `https://github.com/elliotwutingfeng/steam_totp`. The phone depends on that version (`mobile/apps/auth/pubspec.yaml`).

```
steamChars = "23456789BCDFGHJKMNPQRTVWXY"   // 26 characters
timeStep = floor(unixSeconds / 30)          // the library hardcodes 30
HS = HMAC-SHA1(base32Decode(secret), timeStep as 8-byte big-endian)
offset = HS[19] & 0x0f
codePoint = 31-bit integer at that window
for i in 0..<5:
    char[i] = steamChars[codePoint % 26]
    codePoint = codePoint / 26
```

The result is 5 characters from that alphabet, not a decimal string. `SteamTOTP.generate` ignores any period other than 30 because it always does `time ~/= 30`. The phone's next-code path (`_getSteamCode`) adds `code.period` seconds to the unix time and then calls `generate`. `getOTP` uses this path when `type == Type.steam` or the issuer lowercased equals `steam`.

**Requirement R17:** Phase 1 does not port Steam. A decimal TOTP of a Steam secret is the wrong code. A later phase that adds Steam must match this package, including the alphabet and the hardcoded 30-second step, and must be tested against `SteamTOTP.generate` rather than against a guessed alphabet.

## HOTP counters

HOTP's `C` is an event counter stored on `Code.counter`, not a clock. The phone advances it when the person taps next (`CodeWidget`'s forward icon). If the phone and the watch both incremented, or if only one did, the codes would diverge with no clock to resynchronize them.

**INFERRED, and required for Phase 1 by R17:** do not sync HOTP. A later design would need a single writer for the counter and a way to push the new counter back to the vault. That is outside Phase 1.

## Clock skew

RFC 6238 section 6 (Resynchronization) describes a verifier checking a small window of neighboring counters, typically the previous and next step, when clocks drift.

**EXTRACTED phone behavior:** `millisecondsSinceEpoch()` returns `DateTime.now().millisecondsSinceEpoch + PreferenceService.instance.timeOffsetInMilliSeconds()`. The offset is stored under `local_time_offset` and set by `computeAndStoreTimeOffset` from a server epoch.

**INFERRED watch policy:** generate with the watch system clock. Do not import the phone offset. The offset corrects a wrong phone clock; applying a stale copy on the watch would shift a healthy watch. Residual risk: a watch whose clock is off by more than one period will not match the site. The user fixes that in Watch settings. Phase 1 does not implement a resync protocol.

`CodeTimerProgress` on the phone also adds `timeOffsetInMilliseconds` before taking the period modulo. The watch ring uses the same clock as `TOTPCalculator`, with no phone offset.

## Keychain constant

This is not an OTP formula. It is recorded here because the threat model points at it.

Apple's documentation for `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: the item can be accessed only while the device is unlocked by the user. Items with this attribute do not migrate to a new device. After restoring a backup onto a different device, those items are absent.

The spec also sets `SecAccessControlCreateFlags.devicePasscode` so the item requires a device passcode. If that flag cannot be created, the app stores nothing.

## Shoulder surfing and always-on display

Masking codes in ambient mode, and an optional tap-to-reveal shield, are UX controls. They are not a cryptographic proof and not a theorem. `.privacySensitive()` asks the system to redact the view. Anyone who can see an unlocked, raised wrist can still read the code. A rectangular complication that draws the live code widens that exposure to the watch face. See [THREAT-MODEL.md](THREAT-MODEL.md).

## Avatar color

**INFERRED design choice.** The spec says the fallback background comes from the SHA-256 of the issuer string and does not name bytes.

```
digest = SHA-256(UTF-8(issuer))     // issuer as stored, no case fold
red, green, blue = digest[0], digest[1], digest[2]
```

The two-character label is the first two Unicode scalars of the trimmed issuer, with ASCII letters uppercased. This is independent of the phone's `IconUtils._fallbackAvatar`, which uses one character and `providerTitle.hashCode % avatarColors.length`.

## NIST

[NIST SP 800-63B](https://pages.nist.gov/800-63-4/sp800-63b.html) (the 800-63-4 page returned HTTP 200; the older [800-63-3 page](https://pages.nist.gov/800-63-3/sp800-63b.html) also returned 200) discusses authenticator assurance levels, one-time passcodes, and throttling of authentication attempts. A watch that displays a code the user already enrolled in Ente Auth is an output device for that secret. Rate limiting belongs to the website that checks the code. This project does not claim the watch app meets AAL2.

No shoulder-surfing paper is cited. A candidate paper was not fetched, so none is listed.
