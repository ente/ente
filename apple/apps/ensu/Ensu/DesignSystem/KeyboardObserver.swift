import SwiftUI
import UIKit

@MainActor
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    @Published var isVisible: Bool = false

    private var showObserver: NSObjectProtocol?
    private var hideObserver: NSObjectProtocol?

    init() {
        showObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            MainActor.assumeIsolated {
                guard let self else { return }
                if let frame {
                    self.height = frame.height
                }
                self.isVisible = self.height > 100
            }
        }

        hideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.height = 0
                self?.isVisible = false
            }
        }
    }

    isolated deinit {
        if let showObserver { NotificationCenter.default.removeObserver(showObserver) }
        if let hideObserver { NotificationCenter.default.removeObserver(hideObserver) }
    }
}

extension View {
    @MainActor
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
