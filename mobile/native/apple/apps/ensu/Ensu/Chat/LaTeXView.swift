import SwiftUI
import SwiftMath

struct LaTeXView: View {
    let latex: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let sanitizedLatex = latex.replacingOccurrences(of: "\\boxed", with: "")
        MathLabelView(
            latex: sanitizedLatex,
            rawLatex: latex,
            textColor: colorScheme == .dark
                ? PlatformColor(hex: "#E8E4DF")
                : PlatformColor(hex: "#1A1A1A"),
            fontSize: 16,
            isInline: false
        )
    }
}

struct InlineLaTeXView: View {
    let latex: String
    let fontSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let sanitizedLatex = latex.replacingOccurrences(of: "\\boxed", with: "")
        MathLabelView(
            latex: sanitizedLatex,
            rawLatex: latex,
            textColor: colorScheme == .dark
                ? PlatformColor(hex: "#E8E4DF")
                : PlatformColor(hex: "#1A1A1A"),
            fontSize: fontSize,
            isInline: true
        )
    }
}

private struct MathLabelView: UIViewRepresentable {
    let latex: String
    let rawLatex: String
    let textColor: PlatformColor
    let fontSize: CGFloat
    let isInline: Bool

    func makeUIView(context: Context) -> MathLabelContainerView {
        MathLabelContainerView()
    }

    func updateUIView(_ view: MathLabelContainerView, context: Context) {
        view.update(latex: latex, rawLatex: rawLatex, textColor: textColor, fontSize: fontSize, isInline: isInline)
    }
}

private final class MathLabelContainerView: UIView {
    private let mathLabel = MTMathUILabel()
    private let fallbackLabel = UILabel()
    private var currentInsets = UIEdgeInsets.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        fallbackLabel.numberOfLines = 0
        addSubview(mathLabel)
        addSubview(fallbackLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        if !mathLabel.isHidden {
            let childSize = mathLabel.intrinsicContentSize
            return CGSize(
                width: childSize.width + currentInsets.left + currentInsets.right,
                height: childSize.height + currentInsets.top + currentInsets.bottom
            )
        }
        let maxLabelWidth = fallbackLabel.preferredMaxLayoutWidth > 0
            ? fallbackLabel.preferredMaxLayoutWidth
            : CGFloat.greatestFiniteMagnitude
        let labelSize = fallbackLabel.sizeThatFits(CGSize(width: maxLabelWidth, height: .greatestFiniteMagnitude))
        return CGSize(
            width: labelSize.width + currentInsets.left + currentInsets.right,
            height: labelSize.height + currentInsets.top + currentInsets.bottom
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insetBounds = bounds.inset(by: currentInsets)
        mathLabel.frame = insetBounds
        fallbackLabel.frame = insetBounds
        let maxWidth = max(0, insetBounds.width)
        if fallbackLabel.preferredMaxLayoutWidth != maxWidth {
            fallbackLabel.preferredMaxLayoutWidth = maxWidth
            invalidateIntrinsicContentSize()
        }
    }

    func update(latex: String, rawLatex: String, textColor: PlatformColor, fontSize: CGFloat, isInline: Bool) {
        currentInsets = isInline
            ? UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
            : UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        mathLabel.fontSize = fontSize
        mathLabel.textColor = textColor
        mathLabel.contentInsets = isInline ? .zero : currentInsets
        mathLabel.displayErrorInline = false
        mathLabel.latex = latex

        fallbackLabel.font = UIFont.systemFont(ofSize: fontSize)
        fallbackLabel.textColor = textColor
        fallbackLabel.text = rawLatex

        let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldFallback = trimmedLatex.isEmpty || mathLabel.error != nil
        mathLabel.isHidden = shouldFallback
        fallbackLabel.isHidden = !shouldFallback

        invalidateIntrinsicContentSize()
    }
}

