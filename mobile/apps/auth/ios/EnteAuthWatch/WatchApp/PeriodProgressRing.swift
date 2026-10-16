import SwiftUI

enum WatchPeriodClock {
    /// `period - (unixSeconds mod period)`. A zero remainder is a full new period.
    static func remainingSeconds(at date: Date, period: Int) -> Int {
        guard period > 0 else { return 0 }
        let remainder = Int(date.timeIntervalSince1970) % period
        guard remainder >= 0 else { return period }
        return remainder == 0 ? period : period - remainder
    }

    static func index(at date: Date, period: Int) -> Int {
        guard period > 0 else { return 0 }
        return Int(date.timeIntervalSince1970) / period
    }
}

/// Top edge bar from `CodeTimerProgress`: height 3, corner radius 2,
/// `primary700` while the remaining fraction is above 0.4, otherwise orange.
/// The phone painter does not draw a track behind the bar.
struct CodeTimerProgressBar: View {
    let remainingSeconds: Int
    let period: Int
    var redacted: Bool = false

    var body: some View {
        GeometryReader { geo in
            let fraction = redacted
                ? CGFloat(0)
                : CodeTimerStyle.fraction(remainingSeconds: remainingSeconds, period: period)
            let width = geo.size.width * fraction
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CodeTimerStyle.color(remainingSeconds: remainingSeconds, period: period))
                .frame(width: max(width, 0), height: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
        .privacySensitive()
    }
}
