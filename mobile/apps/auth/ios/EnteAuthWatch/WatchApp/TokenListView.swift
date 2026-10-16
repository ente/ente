import SwiftUI

struct TokenListView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(WatchDisplayPreference.shieldedModeKey) private var shieldedMode = false
    @AppStorage(WatchDisplayPreference.rolloverHapticKey) private var rolloverHaptic = false

    var body: some View {
        let palette = EnteWatchPalette(scheme: colorScheme)
        NavigationStack {
            List {
                if session.passcodeRequired {
                    WatchStatePlaceholder(
                        title: WatchListCopy.passcodeTitle,
                        detail: WatchKeychainManager.passcodeRequiredMessage,
                        systemImage: "lock.fill"
                    )
                } else if sortedTokens.isEmpty && session.wristLocked {
                    WatchStatePlaceholder(
                        title: WatchListCopy.lockedTitle,
                        detail: WatchListCopy.lockedDetail,
                        systemImage: "lock.fill"
                    )
                } else if sortedTokens.isEmpty {
                    WatchEmptyState()
                } else {
                    ForEach(sortedTokens) { token in
                        TokenRowView(
                            token: token,
                            shieldedMode: rowShielded,
                            rolloverHaptic: rolloverHaptic
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
                        .listRowBackground(Color.clear)
                    }
                }

                if let statusLine {
                    Section {
                        Text(statusLine)
                            .font(EnteWatchType.body(11))
                            .foregroundStyle(EnteWatchColor.grey)
                            .lineLimit(3)
                    }
                }

                Section {
                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .font(EnteWatchType.body(16))
                    }
                }
            }
            // Plain list: the Digital Crown scrolls the rows. Crown scrolling stays on.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.backgroundBase)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    AuthWordmark(height: 12)
                        .foregroundStyle(palette.textBase)
                }
            }
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.backgroundBase, for: .navigationBar)
        }
        .tint(EnteWatchColor.primary700)
        .containerBackground(palette.backgroundBase, for: .navigation)
        .onAppear {
            #if DEBUG
            _ = session.installScreenshotFixtureIfNeeded()
            #endif
            session.activate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                session.reapplyFromSession()
            }
        }
    }

    private var sortedTokens: [WatchTokenDisplay] {
        session.tokens.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Shield is the saved display flag. A debug screenshot launch can force it
    /// for that process without writing the flag.
    private var rowShielded: Bool {
        #if DEBUG
        if ScreenshotLaunch.shieldsCodes { return true }
        #endif
        return shieldedMode
    }

    private var statusLine: String? {
        guard !session.passcodeRequired else { return nil }
        guard
            let message = session.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        else { return nil }
        return message
    }
}

/// Phone empty home (`home_empty_state.dart`): the same chick PNG
/// (`assets/onboarding-2.png`) over the light or dark halo SVG.
/// Copy stays about pinning or `#watch`. The watch cannot scan or import.
private struct WatchEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = EnteWatchPalette(scheme: colorScheme)
        VStack(spacing: 4) {
            EmptyChickArt()
            Text(WatchListCopy.emptyTitle)
                .font(EnteWatchType.headline())
                .foregroundStyle(palette.textBase)
                .multilineTextAlignment(.center)
            Text(WatchListCopy.emptyDetail)
                .font(EnteWatchType.body())
                .foregroundStyle(EnteWatchColor.grey)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

/// Phone stack in `home_empty_state.dart`: chick height 188, halo 224×142, `bottom: 6`.
/// Scaled with that ratio so the headline and the Settings row both fit the face.
private struct EmptyChickArt: View {
    @Environment(\.colorScheme) private var colorScheme

    private let chickHeight: CGFloat = 64
    private var blobName: String {
        colorScheme == .dark ? "EmptyStateBlobDark" : "EmptyStateBlobLight"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(blobName)
                .resizable()
                .scaledToFit()
                .frame(width: chickHeight * 224 / 188, height: chickHeight * 142 / 188)
                .padding(.bottom, chickHeight * 6 / 188)
            Image("EmptyChick")
                .resizable()
                .scaledToFit()
                .frame(height: chickHeight)
        }
        .frame(height: chickHeight)
        .accessibilityHidden(true)
    }
}

private struct WatchStatePlaceholder: View {
    let title: String
    let detail: String
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = EnteWatchPalette(scheme: colorScheme)
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textBase.opacity(0.7))
            Text(title)
                .font(EnteWatchType.headline(15))
                .foregroundStyle(palette.textBase)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(EnteWatchType.body(12))
                .foregroundStyle(EnteWatchColor.grey)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .listRowBackground(Color.clear)
    }
}

struct WatchSettingsView: View {
    @AppStorage(WatchDisplayPreference.shieldedModeKey) private var shieldedMode = false
    @AppStorage(WatchDisplayPreference.rolloverHapticKey) private var rolloverHaptic = false
    @Environment(\.colorScheme) private var colorScheme

    /// Gap under the toggle footer. Large enough that the mark is past the
    /// first screen on a 46mm face, and still visible as empty space once
    /// the list is scrolled to the mark.
    private let markTopSpace: CGFloat = 96

    var body: some View {
        let palette = EnteWatchPalette(scheme: colorScheme)
        List {
            Section {
                Toggle("Shield codes", isOn: $shieldedMode)
                    .font(EnteWatchType.body(16))
                Toggle("Rollover haptic", isOn: $rolloverHaptic)
                    .font(EnteWatchType.body(16))
            } footer: {
                Text("Shield hides each code until you tap its row. Haptic is one pulse when a code rolls over.")
                    .font(EnteWatchType.body(13))
            }

            MoreFromEnteMark()
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: markTopSpace, leading: 4, bottom: 16, trailing: 4))
                .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(palette.backgroundBase)
        .navigationTitle("Settings")
    }
}
