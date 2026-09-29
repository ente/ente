import EnteFonts
import SwiftUI

public struct VerificationCodeField: View {
    @Binding private var code: String
    @State private var input: String
    @FocusState private var focused: Bool
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let label: String
    private let error: String?

    public init(_ label: String, code: Binding<String>, error: String? = nil) {
        self.label = label
        _code = code
        _input = State(initialValue: code.wrappedValue)
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EnteSpacing.sm) {
            TextField("", text: $input)
                .onChange(of: input) { value in
                    let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    input = digits
                    code = digits
                }
                .onChange(of: code) { input = $0 }
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .font(EnteFont.inter(size: 20, weight: .bold, relativeTo: .title3))
                .frame(minHeight: 52)
                .accessibilityLabel(label)
                .accessibilityHint(error ?? "")
                .privacySensitive()
                .overlay {
                    HStack(spacing: 6) {
                        let digits = Array(code)
                        ForEach(0..<6) { index in
                            let filled = index < digits.count
                            let active = focused && index == min(code.count, 5)
                            Text(index < digits.count ? String(digits[index]) : " ")
                                .font(EnteFont.inter(size: 20, weight: .bold, relativeTo: .title3))
                                .foregroundStyle(
                                    !enabled
                                        ? palette.mutedText
                                        : error != nil ? palette.danger : palette.primary
                                )
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    !enabled
                                        ? palette.fill
                                        : filled && error == nil
                                            ? palette.primarySurface : palette.surface,
                                    in: RoundedRectangle(cornerRadius: EnteRadius.large)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: EnteRadius.large)
                                        .strokeBorder(
                                            borderColor(index: index),
                                            lineWidth: error != nil || filled || active ? 2 : 1)
                                }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: 324)
                .animation(.easeOut(duration: EnteMotion.quick), value: code)
                .animation(.easeOut(duration: EnteMotion.quick), value: focused)
            if let error {
                Text(error).font(EnteTypography.mini).foregroundStyle(palette.danger)
            }
        }
    }

    private func borderColor(index: Int) -> Color {
        if !enabled { return palette.faintBorder }
        if error != nil { return palette.danger }
        return index < code.count || focused && index == min(code.count, 5)
            ? palette.primary : palette.border
    }
}
