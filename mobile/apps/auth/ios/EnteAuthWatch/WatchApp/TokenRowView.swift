import SwiftUI

struct TokenRowView: View {
    let token: WatchTokenDisplay
    let shieldedMode: Bool
    let rolloverHaptic: Bool

    @State private var revealed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// Shielded rows stay hidden until tapped. Inactive and dimmed scenes hide every row.
    private var secretsHidden: Bool {
        WatchPrivacyMask.hidesSecrets(
            isActive: scenePhase == .active,
            isLuminanceReduced: isLuminanceReduced
        )
    }

    private var shielded: Bool {
        shieldedMode && !revealed
    }

    private var masked: Bool {
        secretsHidden || shielded
    }

    var body: some View {
        let palette = EnteWatchPalette(scheme: colorScheme)
        Button {
            guard shieldedMode, !secretsHidden else { return }
            revealed = true
        } label: {
            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                TokenRowTimelineBody(
                    token: token,
                    date: timeline.date,
                    masked: masked,
                    redactProgress: secretsHidden,
                    rolloverHaptic: rolloverHaptic,
                    palette: palette
                )
            }
        }
        .buttonStyle(.plain)
        .modifier(
            RowAccessibility(
                tapToReveal: shielded && !secretsHidden,
                hidden: masked,
                issuer: token.issuer,
                account: token.account
            )
        )
        .modifier(
            CopyToPhoneMenu(
                enabled: WatchPhoneCopy.allowsCopy(
                    shieldedMode: shieldedMode,
                    revealed: revealed,
                    secretsHidden: secretsHidden
                ),
                action: { copyVisibleCodeToiPhone() }
            )
        )
        .onChange(of: shieldedMode) { _, isOn in
            if isOn {
                revealed = false
            }
        }
        .onChange(of: token.id) { _, _ in
            revealed = false
        }
    }

    /// Copy is separate from tap-to-reveal. A shielded row that is still hidden
    /// does not send. The message is the token id only.
    private func copyVisibleCodeToiPhone() {
        guard WatchPhoneCopy.allowsCopy(
            shieldedMode: shieldedMode,
            revealed: revealed,
            secretsHidden: secretsHidden
        ) else { return }
        WatchSessionManager.shared.requestCopyToPhone(id: token.id)
    }
}

/// List swipe button. Hidden until the code itself is visible.
/// watchOS retired the long-press context menu, so the row uses the list's swipe action.
/// The system draws that action as a circle and does not fit a long title inside it,
/// so the circle shows an iPhone symbol. VoiceOver still uses the full title.
private struct CopyToPhoneMenu: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(action: action) {
                        Image(systemName: "iphone")
                    }
                    .accessibilityLabel(WatchPhoneCopy.title)
                }
                .accessibilityAction(named: Text(WatchPhoneCopy.title)) {
                    action()
                }
        } else {
            content
        }
    }
}

private struct TokenRowTimelineBody: View {
    let token: WatchTokenDisplay
    let date: Date
    let masked: Bool
    let redactProgress: Bool
    let rolloverHaptic: Bool
    let palette: EnteWatchPalette

    var body: some View {
        let face = face(at: date)

        VStack(alignment: .leading, spacing: 0) {
            if token.period > 0 {
                CodeTimerProgressBar(
                    remainingSeconds: face.remainingSeconds,
                    period: token.period,
                    redacted: redactProgress
                )
            }
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(titleText)
                        .font(EnteWatchType.semibold(14))
                        .foregroundStyle(palette.textBase)
                        .lineLimit(1)
                    if showsAccount {
                        Text(trimmedAccount)
                            .font(EnteWatchType.body(11))
                            .foregroundStyle(EnteWatchColor.grey)
                            .lineLimit(1)
                    }
                    codeLabel(face)
                        .padding(.top, 2)
                    if face.showsNext, case .open(_, let next, _) = face {
                        Text(verbatim: "Next: \(CodeFormatting.display(next, digits: token.digits))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(EnteWatchColor.grey)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .privacySensitive()
                            .accessibilityLabel("Next \(next)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IssuerAvatarView(issuer: token.issuer)
                    .padding(.top, 1)
                    .padding(.trailing, 2)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.codeCard)
        .clipShape(RoundedRectangle(cornerRadius: EnteWatchColor.cardCornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if token.isFavorite {
                PinMark(fill: palette.pinnedFill)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: EnteWatchColor.cardCornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: face.showsNext)
        .task(id: periodIndex) {
            RolloverHapticGate.shared.note(
                period: token.period,
                periodIndex: periodIndex,
                enabled: rolloverHaptic
            )
        }
    }

    private var periodIndex: Int {
        WatchPeriodClock.index(at: date, period: token.period)
    }

    private var trimmedIssuer: String {
        token.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAccount: String {
        token.account.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var titleText: String {
        if !trimmedIssuer.isEmpty { return trimmedIssuer }
        if !trimmedAccount.isEmpty { return trimmedAccount }
        return "Account"
    }

    private var showsAccount: Bool {
        !trimmedAccount.isEmpty && trimmedAccount != titleText
    }

    @ViewBuilder
    private func codeLabel(_ face: RowFace) -> some View {
        switch face {
        case .locked:
            Label {
                Text(verbatim: WatchListCopy.lockedTitle)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(EnteWatchType.body(12))
            .foregroundStyle(EnteWatchColor.grey)
            .accessibilityLabel(WatchListCopy.lockedTitle)
        case .shielded:
            Text(verbatim: CodeFormatting.masked(digits: token.digits))
                .font(codeFont)
                .foregroundStyle(palette.textBase)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .privacySensitive()
                .accessibilityLabel(TokenRowAccessibility.codeLabel(masked: true, code: ""))
        case .open(let current, _, _):
            Text(verbatim: CodeFormatting.display(current, digits: token.digits))
                .font(codeFont)
                .foregroundStyle(palette.textBase)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .privacySensitive()
                .accessibilityLabel(TokenRowAccessibility.codeLabel(masked: false, code: current))
        }
    }

    private var codeFont: Font {
        let size: CGFloat = token.digits > 8 ? 15 : (token.digits > 6 ? 17 : 20)
        return .system(size: size, weight: .medium, design: .monospaced)
    }

    /// Loads the seed, generates for `date`, and drops the buffer before returning.
    /// Shielded rows discard the digits after reading `remainingSeconds`, so the
    /// view never holds a code until that row is revealed. Nothing is written to
    /// `UserDefaults` or stored on the row.
    private func face(at date: Date) -> RowFace {
        let fallback = WatchPeriodClock.remainingSeconds(at: date, period: token.period)
        guard token.period > 0, token.digits > 0 else {
            return .locked(remaining: fallback)
        }
        guard let secret = WatchKeychainManager.shared.load(id: token.id) else {
            return .locked(remaining: fallback)
        }
        let code = TOTPCalculator.generateCode(
            secret: secret,
            algorithm: token.algorithm,
            digits: token.digits,
            period: token.period,
            date: date
        )
        let remaining = code.remainingSeconds
        if code.current.isEmpty {
            return .locked(remaining: remaining)
        }
        if masked {
            return .shielded(remaining: remaining)
        }
        return .open(current: code.current, next: code.next, remaining: remaining)
    }
}

private struct RowAccessibility: ViewModifier {
    let tapToReveal: Bool
    let hidden: Bool
    let issuer: String
    let account: String

    func body(content: Content) -> some View {
        if tapToReveal {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TokenRowAccessibility.shieldedLabel(issuer: issuer, account: account))
                .accessibilityHint("Reveals this code")
        } else if hidden {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TokenRowAccessibility.shieldedLabel(issuer: issuer, account: account))
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

private struct PinMark: View {
    let fill: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PinCorner()
                .fill(fill)
                .frame(width: 20, height: 20)
            Image(systemName: "pin.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(EnteWatchColor.pinGlyph)
                .padding(.top, 2)
                .padding(.trailing, 2)
        }
        .accessibilityHidden(true)
    }
}

/// Top-right triangle from `PinBgPainter` in `code_widget.dart`.
private struct PinCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private enum RowFace {
    case locked(remaining: Int)
    case shielded(remaining: Int)
    case open(current: String, next: String, remaining: Int)

    var remainingSeconds: Int {
        switch self {
        case .locked(let remaining), .shielded(let remaining):
            return remaining
        case .open(_, _, let remaining):
            return remaining
        }
    }

    var showsNext: Bool {
        guard case .open(_, let next, let remaining) = self else { return false }
        return NextCodeHint.isVisible(remainingSeconds: remaining, nextIsEmpty: next.isEmpty)
    }
}
