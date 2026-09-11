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
        GeometryReader { _ in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    StatusIcon(status: status)
                        .padding(.bottom, 16)

                    Text(title)
                        .font(FontUtils.interSemiBold(size: 42))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)

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
            "Preparing Slideshow"
        case .error:
            "Something went wrong"
        case .success:
            "All set!"
        case .empty:
            "No photos found"
        }
    }

    private var message: String {
        switch status {
        case let .loading(message):
            message
        case let .error(message):
            message
        case let .success(message):
            message
        case let .empty(message):
            message
        }
    }
}

struct StatusIcon: View {
    let status: StatusView.StatusType

    var body: some View {
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
    StatusView(
        status: .empty("This album has no photos that can be shown here"),
        onRetry: nil,
        debugLogs: nil,
    )
}
