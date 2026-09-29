import SwiftUI
import UIKit

struct CollapsingScrollView<Content: View>: UIViewControllerRepresentable {
    let expansion: CGFloat
    let identifier: String?
    let onScroll: (CGFloat) -> Void
    @ViewBuilder var content: Content

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content, environment: context.environment)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.expansion = expansion
        controller.scrollView.accessibilityIdentifier = identifier
        controller.scrollView.isScrollEnabled = context.environment.isScrollEnabled
        controller.onScroll = { offset in
            onScroll(min(1, max(0, offset / expansion)))
        }
        controller.host.rootView = HostedContent(content: content, environment: context.environment)
    }

    struct HostedContent: View {
        let content: Content
        let environment: EnvironmentValues

        var body: some View {
            content.environment(\.self, environment).ignoresSafeArea()
        }
    }

    final class Controller: UIViewController, UIScrollViewDelegate {
        let scrollView = UIScrollView()
        let host: UIHostingController<HostedContent>
        var expansion: CGFloat = 0
        var onScroll: (CGFloat) -> Void = { _ in }

        init(content: Content, environment: EnvironmentValues) {
            host = UIHostingController(
                rootView: HostedContent(content: content, environment: environment))
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        override func loadView() {
            view = scrollView
            scrollView.delegate = self
            scrollView.contentInsetAdjustmentBehavior = .always
            addChild(host)
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(
                    equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                host.view.trailingAnchor.constraint(
                    equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                host.view.bottomAnchor.constraint(
                    equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                host.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            ])
            host.didMove(toParent: self)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.y)
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView, withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            targetContentOffset.pointee.y = snappedOffset(targetContentOffset.pointee.y)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            let target = snappedOffset(scrollView.contentOffset.y)
            if !decelerate && target != scrollView.contentOffset.y {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: target), animated: true)
            }
        }

        private func snappedOffset(_ offset: CGFloat) -> CGFloat {
            offset > 1 && offset < expansion ? expansion : offset
        }
    }
}
