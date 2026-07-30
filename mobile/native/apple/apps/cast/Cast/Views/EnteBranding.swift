import SwiftUI

struct EnteBranding: View {
    var body: some View {
        VStack(alignment: .leading, spacing: -4) {
            Text("ente")
                .font(FontUtils.montserratExtraBold(size: 40))
                
                .foregroundColor(.black)
            
            Text("photos")
                .font(FontUtils.montserratBold(size: 20))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0/255, green: 179/255, blue: 61/255))
                )
                .rotationEffect(.degrees(-8))
                .offset(x: 20, y: -2)
        }
    }
}

#Preview {
    ZStack {
        Color.white
        EnteBranding()
    }
}
