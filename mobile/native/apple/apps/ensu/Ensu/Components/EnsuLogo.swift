import SwiftUI

struct EnsuLogo: View {
    var height: CGFloat = 24
    var horizontalPadding: CGFloat = 4
    var verticalPadding: CGFloat = 2
    var color: Color = EnsuColor.textPrimary

    var body: some View {
        Image("EnsuLogo")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(height: max(0, height - verticalPadding * 2))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(color)
            .accessibilityLabel("Ensu")
    }
}
