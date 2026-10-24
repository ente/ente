# References

Every GitHub URL below was returned by `gh` on 2026-10-10. Non-GitHub URLs were fetched with HTTP GET and returned 200. If a link is missing, it was not verified and must not be invented back into the docs.

## Verification method

| Check | Command or fetch | Result |
| :---- | :---- | :---- |
| Auth | `gh auth status` | Logged in to github.com (keyring), repo scope present |
| This repo | `gh repo view ente-io/ente --json name,url,description,defaultBranchRef` | 200 via `gh`. URL `https://github.com/ente/ente`, branch `main` |
| Discussion 485 | `gh api graphql` query `repository(owner:"ente-io", name:"ente") { discussion(number:485) { title url number } }` | Title `[Feature Request] Wear OS Support`, URL `https://github.com/ente/ente/discussions/485` |
| Issue 143 | `gh issue view 143 --repo ente-io/ente --json number,title,url,state` | CLOSED, same title, URL `https://github.com/ente/ente/issues/143` |
| Conversion | GraphQL `issue(number:143) { timelineItems { ... on ConvertedToDiscussionEvent { discussion { number url title } } } }` | `ConvertedToDiscussionEvent` at 2024-03-01T08:58:51Z, discussion 485, same title and URL |
| Search caveat | `gh search issues --repo ente-io/ente watch` | Failed: repository not searchable under `ente-io`. Retry with `--repo ente/ente` |
| `otp` repo | `gh repo view Daegalus/dart-otp --json url,description` | `https://github.com/daegalus/dart-otp` |
| `steam_totp` repo | `gh repo view elliotwutingfeng/steam_totp --json url,description` | `https://github.com/elliotwutingfeng/steam_totp` |
| Steam algorithm | `gh api -H "Accept: application/vnd.github.raw" "repos/elliotwutingfeng/steam_totp/contents/lib/src/steam_totp_base.dart?ref=v0.0.2"` | 200. Alphabet `23456789BCDFGHJKMNPQRTVWXY`. Tag `v0.0.2` matches the pubspec pin 0.0.2 |
| simple-icons | `gh repo view simple-icons/simple-icons --json url,description` | `https://github.com/simple-icons/simple-icons` |
| Org list | `gh repo list ente-io --limit 30` | Empty list |
| Canonical org | `gh repo list ente --limit 15` | Includes `ente/ente`. Also `ente/photos-desktop`, `ente/nightly`, and other non-Auth repos |

Local remote, from `git remote -v` in `/Volumes/MacExt/ente`: `https://github.com/ente-io/ente.git`.

## GitHub URLs safe to cite

- https://github.com/ente/ente
- https://github.com/ente/ente/discussions/485
- https://github.com/ente/ente/issues/143
- https://github.com/daegalus/dart-otp
- https://github.com/elliotwutingfeng/steam_totp
- https://github.com/simple-icons/simple-icons

`gh repo list ente` also returned these existing repos. They are out of scope for the Auth watch app: https://github.com/ente/photos-desktop , https://github.com/ente/nightly .

No Apple sample repository is listed. A Watch Connectivity sample was not verified with `gh repo view`, so none is recommended.

## Standards

Fetched as text; status 200. The RFC editor redirected `/rfc/rfc4226` to `/info/rfc4226` (and the same for 6238 and 4648). The `.txt` documents and the datatracker HTML returned 200 and contain the vectors cited in [MATH.md](MATH.md).

- https://www.rfc-editor.org/rfc/rfc4226
- https://www.rfc-editor.org/rfc/rfc4226.txt — contains Appendix D, HOTP `755224` at count 0
- https://datatracker.ietf.org/doc/html/rfc4226
- https://www.rfc-editor.org/rfc/rfc6238
- https://www.rfc-editor.org/rfc/rfc6238.txt — time 59, SHA-1 `94287082`, SHA-256 `46119246`, SHA-512 `90693936`
- https://datatracker.ietf.org/doc/html/rfc6238
- https://www.rfc-editor.org/rfc/rfc4648
- https://www.rfc-editor.org/rfc/rfc4648.txt

Authors, as named on those RFCs: HOTP — M'Raihi, Bellare, Hoornaert, Naccache, Ranen (2005). TOTP — M'Raihi, Machani, Pei, Rydell (2011).

## NIST

Both pages returned HTTP 200. Cited as guidance only. The watch project is not an AAL2 claim.

- https://pages.nist.gov/800-63-4/sp800-63b.html
- https://pages.nist.gov/800-63-3/sp800-63b.html

## Apple documentation

HTML pages returned HTTP 200. Queue-versus-replace sentences were read from Apple's documentation JSON (`developer.apple.com/tutorials/data/documentation/...json`), which also returned 200.

| Topic | URL |
| :---- | :---- |
| Watch Connectivity | https://developer.apple.com/documentation/watchconnectivity |
| `transferUserInfo` | https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:) |
| `updateApplicationContext` | https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:) |
| WidgetKit | https://developer.apple.com/documentation/widgetkit |
| Accessory circular | https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycircular |
| Accessory rectangular | https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular |
| Accessory corner | https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycorner |
| `SecAccessControlCreateWithFlags` | https://developer.apple.com/documentation/security/secaccesscontrolcreatewithflags(_:_:_:_:) |
| `.devicePasscode` | https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/devicepasscode |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly |
| CryptoKit HMAC | https://developer.apple.com/documentation/cryptokit/hmac |
| `privacySensitive` | https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:) |
| `WKHapticType.directionDown` | https://developer.apple.com/documentation/watchkit/wkhaptictype/directiondown |

The three-argument documentation URL `secaccesscontrolcreatewithflags(_:_:_:)` returned HTTP 404. The four-argument URL in the table is the one that resolved. Do not cite the 404.

Apple's JSON for `updateApplicationContext` includes: "This method replaces the previous dictionary that was set" and "You may call this method when the counterpart is not currently reachable." The JSON for `transferUserInfo` includes: "Dictionaries sent using this method are queued on the other device and delivered in the order in which they were sent."

The spec's phrase "transport-layer AES-GCM" was not re-derived from those pages. [THREAT-MODEL.md](THREAT-MODEL.md) treats transport encryption as Apple's and treats the JSON secret field as plaintext at the application layer.

## Ente source (this checkout)

| Topic | Path |
| :---- | :---- |
| Code model | `mobile/apps/auth/lib/models/code.dart` |
| Display, pin, tags, position | `mobile/apps/auth/lib/models/code_display.dart` |
| OTP | `mobile/apps/auth/lib/utils/totp_util.dart` |
| Next code and masking | `mobile/apps/auth/lib/ui/code_widget.dart` |
| Sort | `mobile/apps/auth/lib/ui/home_page.dart` (`sortFilteredCodes`), `mobile/apps/auth/lib/store/code_store.dart` |
| Preferences and clock offset | `mobile/apps/auth/lib/services/preference_service.dart` |
| Encrypted vault | `mobile/apps/auth/lib/services/authenticator_service.dart`, `store/authenticator_db.dart`, `store/offline_authenticator_db.dart` |
| Account keys | `mobile/apps/auth/lib/core/configuration.dart` |
| iOS entry | `mobile/apps/auth/ios/Runner/AppDelegate.swift` |
| Method channel pattern | `mobile/apps/auth/lib/services/windows_window_placement.dart` |
| Icons | `mobile/apps/auth/lib/ui/utils/icon_utils.dart` |
| Aegis favorite → pinned | `mobile/apps/auth/lib/ui/settings/data/import/aegis_import.dart` |
| Tag chips | `mobile/apps/auth/lib/onboarding/view/common/tag_chip.dart` |
| Spec | `building the app for ente feels like a good idea....md` |
| Graph report | `graphify-out/GRAPH_REPORT.md` |

## Not cited

No academic shoulder-surfing paper. None was fetched. Display protection stays described as a UX control.
