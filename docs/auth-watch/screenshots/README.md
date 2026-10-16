# Ente Auth screenshots

Captured on 10 October 2026 from simulators. Populated code rows and cards were drawn by the real views. A temporary debug seed (public RFC 6238 test secret `JBSWY3DPEHPK3PXP` only) was used so the watch and phone could show the same three accounts, then removed. Those three accounts are pinned GitHub, Example Bank, and Google, so the digits match across issuers.

Watch shots: Apple Watch Series 11 (46mm), `BE1E9F01-2BC1-4E7F-983B-E3E6176E8FFC`, watchOS 26.5, `xcrun simctl io`.

iPhone shots: iPhone 17 Pro, `196B0230-00C2-4819-9F2B-116E25C647E7`, debug build of the Flutter Auth app.

## Watch

Directory: `/Volumes/MacExt/ente/docs/auth-watch/screenshots/watch/`

| File | State | Source |
| --- | --- | --- |
| `empty.png` | No accounts yet, with the Settings row | Simulator, cold list |
| `list-codes.png` | GitHub (pinned, monochrome mark on the right), Google (color mark on the right). Purple progress along the top edge, grouped code on the left. Dark appearance, matching the phone dark card token | Simulator after a temporary in-memory fixture, then removed |
| `pinned.png` | Same frame as `list-codes.png`. Pin triangle on the GitHub card | Copied from the refreshed list shot so it matches the new card |
| `next-code.png` | Last seconds of the period: orange bar and `Next:` line. The next code is not shown for the rest of the period | Simulator after a temporary in-memory fixture, then removed |
| `shielded.png` | Shield mode: bullets instead of digits. Pin and the Google color mark still visible | Simulator after a temporary in-memory fixture, then removed |
| `passcode-required.png` | Passcode required placeholder | Simulator after a temporary in-memory fixture |
| `wrist-locked.png` | Watch is locked placeholder | Simulator after a temporary in-memory fixture |
| `settings-toggles.png` | Shield codes and rollover haptic toggles, with the footer, before scrolling | Simulator |
| `settings.png` | Scrolled settings list: space under the footer, then the More from ente mark | Simulator |
| `copy-to-iphone.png` | GitHub row swiped open. The trailing action is the system swipe button named Copy to iPhone; the purple circle shows an iPhone symbol | Simulator after a temporary fixture, then removed |

Not captured: the watch home screen. This Xcode install has no Simulator.app, so the digital crown could not be pressed, and terminating the app shows the watch face rather than the app grid. The watch target now has an `AppIcon` set copied from the iOS Ente Auth icon.

## iPhone

Directory: `/Volumes/MacExt/ente/docs/auth-watch/screenshots/ios/`

| File | State | Source |
| --- | --- | --- |
| `onboarding.png` | Launch screen: sign up, log in, use without backups | Simulator, real app, no account |
| `empty.png` | Empty home after offline mode: scan, enter a setup key, import | Simulator, real app |
| `add-code.png` | Enter account details | Simulator, real app |
| `settings.png` | Settings home while signed out | Simulator, real app |
| `list-codes.png` | GitHub (pinned, icon), Example Bank (letter avatar), Google icon. Purple progress, grouped code, upcoming code on the right | Simulator. Accounts came from a temporary debug seed, removed afterward |
| `pinned.png` | Same three cards. Pin triangle on GitHub | Simulator. Temporary debug seed, removed afterward |
| `next-code.png` | Same three cards with the orange progress bar in the last seconds of the period | Simulator. Temporary debug seed, removed afterward |

The phone card always shows the upcoming code on the right. The watch shows `Next:` only in the last five seconds. `next-code.png` on the phone is the orange-bar moment; `next-code.png` on the watch is that same window with the `Next:` line.

Not captured: a masked phone card. Hiding codes is a preference and was not turned on in this pass. Passcode-required and wrist-locked are watch states.
