import SwiftUI

struct StatusView: View {
    let status: StatusType
    let onRetry: (() -> Void)?
    let debugLogs: String?
    @State private var animationPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    
    enum StatusType {
        case loading(String)
        case error(String)
        case success(String)
        case empty(String)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // White background
                Color.white
                    .ignoresSafeArea()
                
                // Main content
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Status icon - clean display without backgrounds
                    StatusIcon(status: status)
                        .padding(.bottom, 16)
                    
                    // Title
                    Text(title)
                        .font(FontUtils.interSemiBold(size: 42))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                    
                    // Message (if not empty)
                    if !message.isEmpty {
                        Text(message)
                            .font(FontUtils.interRegular(size: 20))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 60)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                
                // Ente branding in top right corner
                VStack {
                    HStack {
                        Spacer()
                        EnteBranding()
                            .padding(.top, 30)
                            .padding(.trailing, 30)
                    }
                    Spacer()
                }
            }
        }
    }
    
    private var title: String {
        switch status {
        case .loading:
            return "Preparing Slideshow"
        case .error:
            return "Something went wrong"
        case .success:
            return "All set!"
        case .empty:
            return "No photos found"
        }
    }
    
    private var message: String {
        switch status {
        case .loading(let message):
            return message
        case .error(let message):
            return message
        case .success(let message):
            return message
        case .empty(let message):
            return message
        }
    }
}

struct StatusIcon: View {
    let status: StatusView.StatusType
    
    var body: some View {
        // Simple icon display without any backgrounds or effects
        iconView
            .frame(width: 400, height: 240)
    }
    
    @ViewBuilder
    private var iconView: some View {
        switch status {
        case .loading:
            Image("ducky_tv")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 300)
            
        case .error:
            Image("ducky_tv")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 300)
                .opacity(0.8)
            
        case .success:
            Image("ducky_tv")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 300)
            
        case .empty:
            Image("ducky_tv")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 300)
                .opacity(0.7)
        }
    }
}

#Preview {
    StatusView(status: .loading("Preparing your slideshow..."), onRetry: nil, debugLogs: nil)
   
}

#Preview {
    StatusView(status: .empty("This album has no photos that can be shown here"), onRetry: nil, debugLogs: nil)
      
}
