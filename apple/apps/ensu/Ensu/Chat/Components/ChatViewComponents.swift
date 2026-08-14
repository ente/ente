import SwiftUI

struct DownloadOnboardingView: View {
    let isDownloading: Bool
    let downloadPercent: Int?
    let statusText: String?
    let isLoadingModel: Bool
    let totalBytes: Int64?
    let sizeText: String
    let onDownload: () -> Void

    var body: some View {
        VStack(spacing: EnsuSpacing.md) {
            Text("Download to begin using the Chat")
                .font(EnsuTypography.large)
                .foregroundStyle(EnsuColor.textPrimary)
                .multilineTextAlignment(.center)

            if isDownloading {
                let statusLine: String = {
                    if let statusText, isLoadingModel {
                        return statusText
                    }
                    if let totalBytes, let percent = downloadPercent {
                        let clamped = min(max(percent, 0), 100)
                        let downloaded = Int64(Double(totalBytes) * Double(clamped) / 100.0)
                        return "Downloading... \(downloaded.formattedFileSize) / \(totalBytes.formattedFileSize)"
                    }
                    if let statusText, !statusText.isEmpty {
                        return statusText
                    }
                    return "Downloading..."
                }()

                StableDownloadStatusText(
                    text: statusLine,
                    font: EnsuTypography.body,
                    color: EnsuColor.textMuted
                )

                progressView
            } else {
                Button("Download") {
                    hapticMedium()
                    onDownload()
                }
                .font(EnsuTypography.body)
                .foregroundStyle(Color.black)
                .frame(maxWidth: 200)
                .padding(.vertical, EnsuSpacing.md)
                .background(EnsuColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.button))

                Text(sizeText)
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, EnsuSpacing.pageHorizontal)
    }

    @ViewBuilder
    private var progressView: some View {
        if let percent = downloadPercent {
            let clamped = min(max(percent, 0), 100)
            ProgressView(value: Double(clamped), total: 100)
                .progressViewStyle(.linear)
                .tint(EnsuColor.action)
                .frame(maxWidth: 240)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(EnsuColor.action)
                .frame(maxWidth: 240)
        }
    }

}

struct UnsupportedChatInputNotice: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: EnsuSpacing.xs) {
            Text("Chat unavailable on this device")
                .font(EnsuTypography.large)
                .foregroundStyle(EnsuColor.textPrimary)

            Text(message)
                .font(EnsuTypography.body)
                .foregroundStyle(EnsuColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EnsuSpacing.md)
        .background(EnsuColor.fillFaint)
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card))
        .padding(.horizontal, EnsuSpacing.pageHorizontal)
        .padding(.vertical, EnsuSpacing.md)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: InputBarHeightKey.self, value: proxy.size.height)
            }
        )
        .background(EnsuColor.backgroundBase)
    }
}

struct SignInComingSoonDialog: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: EnsuSpacing.lg) {
                Image("EnsuDucky")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)

                Text(title)
                    .font(EnsuTypography.large)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textMuted)
                    .multilineTextAlignment(.center)

                Button(action: {
                    hapticTap()
                    onDismiss()
                }) {
                    Text("Got it")
                        .font(EnsuTypography.body)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, EnsuSpacing.md)
                        .background(EnsuColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.button, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(EnsuSpacing.lg)
            .frame(maxWidth: 360)
            .background(EnsuColor.backgroundBase)
            .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous))
            .padding(.horizontal, EnsuSpacing.pageHorizontal)
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        }
    }
}

struct ChatAppBar: View {
    let sessionTitle: String
    let showBrand: Bool
    let showSignIn: Bool
    let showsMenuButton: Bool
    let modelDownloadState: DownloadToastState?
    let onMenu: () -> Void
    let onSignIn: () -> Void
    let onNewChat: () -> Void

    private let centerInset: CGFloat = 72

    private var modelProgressState: DownloadToastState? {
        guard let modelDownloadState else { return nil }
        switch modelDownloadState.phase {
        case .loading, .downloading:
            return modelDownloadState
        default:
            return nil
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: EnsuSpacing.md) {
                if showsMenuButton {
                    Button(action: {
                        hapticTap()
                        onMenu()
                    }) {
                        Image("Menu01Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 40, height: 40)
                }

                Spacer()

                HStack(spacing: EnsuSpacing.md) {
                    if showSignIn {
                        if let progress = modelProgressState {
                            ModelProgressIndicator(state: progress)
                        }
                        Button(action: {
                            hapticTap()
                            onSignIn()
                        }) {
                            Text("Sign In")
                                .font(EnsuTypography.small)
                                .foregroundStyle(EnsuColor.action)
                        }
                        .buttonStyle(.plain)
                    } else {
                        if let progress = modelProgressState {
                            ModelProgressIndicator(state: progress)
                        }
                    }

                    Button(action: {
                        hapticTap()
                        onNewChat()
                    }) {
                        Image("PlusSignIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(EnsuColor.textPrimary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showBrand {
                EnsuLogo(height: 21)
                    .padding(.horizontal, centerInset)
            } else {
                Text(sessionTitle)
                    .font(EnsuTypography.large)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, centerInset)
            }
        }
        .padding(.horizontal, EnsuSpacing.pageHorizontal)
        .padding(.vertical, EnsuSpacing.sm)
        .background(EnsuColor.backgroundBase)
    }
}

struct ModelProgressIndicator: View {
    let state: DownloadToastState

    var body: some View {
        let clamped = min(max(state.percent ?? 0, 0), 100)
        if state.phase == .downloading {
            ProgressView(value: Double(clamped), total: 100)
                .progressViewStyle(.circular)
                .tint(EnsuColor.action)
                .frame(width: 16, height: 16)
        } else {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(EnsuColor.action)
                .frame(width: 16, height: 16)
        }
    }
}
