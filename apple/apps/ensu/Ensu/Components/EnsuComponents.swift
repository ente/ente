import SwiftUI
import UIKit

struct PrimaryButton: View {
    let text: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            hapticMedium()
            action()
        }) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(Color.black)
                } else {
                    Text(text)
                        .font(EnsuFont.ui(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled || isLoading)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, EnsuSpacing.buttonVertical)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(EnsuColor.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.button, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct StyledTextField: View {
    let hint: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(hint, text: $text)
            .font(EnsuTypography.body)
            .foregroundStyle(EnsuColor.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboardType)
            .padding(.horizontal, EnsuSpacing.inputHorizontal)
            .padding(.vertical, EnsuSpacing.inputVertical)
            .background(EnsuColor.fillFaint)
            .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.input, style: .continuous))
    }
}

struct ActionButton: View {
    let icon: String
    var isSystemSymbol: Bool = false
    var tooltip: String? = nil
    var color: Color = EnsuColor.textMuted
    let action: () -> Void

    var body: some View {
        Button(action: {
            hapticTap()
            action()
        }) {
            Group {
                if isSystemSymbol {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .regular))
                } else {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(ActionButtonStyle(color: color))
        .accessibilityLabel(tooltip ?? "")
    }
}

struct TextActionButton: View {
    let text: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: {
            hapticTap()
            action()
        }) {
            Text(text)
                .font(EnsuTypography.small)
                .foregroundStyle(isEnabled ? EnsuColor.textMuted : EnsuColor.textMuted.opacity(0.4))
                .padding(.horizontal, 4)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isPressed ? EnsuColor.fillFaint : Color.clear)
            )
    }
}

struct AttachmentChip: View {
    let name: String
    let size: String
    let icon: String
    var isUploading: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(EnsuColor.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .lineLimit(1)
                Text(size)
                    .font(EnsuTypography.mini)
                    .foregroundStyle(EnsuColor.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: 180, alignment: .leading)

            if isUploading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            if let onDelete {
                Button(action: {
                    hapticTap()
                    onDelete()
                }) {
                    Image("Cancel01Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(EnsuColor.fillFaint)
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.input, style: .continuous))
    }
}

struct ImageAttachmentThumbnail: View {
    let url: URL?
    let accessibilityLabel: String
    var width: CGFloat
    var height: CGFloat
    var portraitWidth: CGFloat? = nil
    var portraitHeight: CGFloat? = nil
    var squareSize: CGFloat? = nil
    var isUploading: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        let loadedImage = platformImage(from: url)
        let size = thumbnailSize(for: loadedImage)

        ZStack(alignment: .topTrailing) {
            thumbnailContent(loadedImage)
                .frame(width: size.width, height: size.height)
                .background(EnsuColor.fillFaint)
                .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous))

            if isUploading {
                RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous)
                    .fill(.black.opacity(0.18))
                    .frame(width: size.width, height: size.height)

                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: size.width, height: size.height)
            }

            if let onDelete {
                Button(action: {
                    hapticTap()
                    onDelete()
                }) {
                    Image("Cancel01Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.45))
                .clipShape(Circle())
                .padding(4)
                .accessibilityLabel("Remove image")
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func thumbnailContent(_ loadedImage: PlatformImageContent?) -> some View {
        if let loadedImage {
            loadedImage.image
                .resizable()
                .scaledToFill()
        } else {
            Image("Attachment01Icon")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(EnsuColor.textMuted)
        }
    }

    private func thumbnailSize(for loadedImage: PlatformImageContent?) -> CGSize {
        guard let loadedImage else {
            return CGSize(width: width, height: height)
        }
        if loadedImage.pixelHeight > loadedImage.pixelWidth,
           let portraitWidth,
           let portraitHeight {
            return CGSize(width: portraitWidth, height: portraitHeight)
        }
        if loadedImage.pixelHeight == loadedImage.pixelWidth,
           let squareSize {
            return CGSize(width: squareSize, height: squareSize)
        }
        return CGSize(width: width, height: height)
    }

    private func platformImage(from url: URL?) -> PlatformImageContent? {
        guard let url else {
            return nil
        }

        guard let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return PlatformImageContent(
            image: Image(uiImage: image),
            pixelWidth: image.size.width,
            pixelHeight: image.size.height
        )
    }
}

private struct PlatformImageContent {
    let image: Image
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(EnsuTypography.body)
            .foregroundStyle(EnsuColor.toastText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(EnsuColor.toastBackground)
            .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.toast, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

@MainActor
func presentToast(
    _ message: String,
    setToastMessage: @escaping (String?) -> Void,
    duration: TimeInterval = 1.5
) -> Task<Void, Never> {
    withAnimation(.easeOut(duration: 0.2)) {
        setToastMessage(message)
    }
    let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
    return Task { @MainActor in
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            setToastMessage(nil)
        }
    }
}

struct MacSheetHeader<Leading: View, Center: View, Trailing: View>: View {
    let leading: Leading
    let center: Center
    let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            center

            HStack {
                leading
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, EnsuSpacing.pageHorizontal)
        .padding(.vertical, EnsuSpacing.sm)
        .background(EnsuColor.backgroundBase)
    }
}
