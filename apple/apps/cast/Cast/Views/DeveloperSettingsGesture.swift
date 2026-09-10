import SwiftUI

// Seven presses opens developer settings, matching the gesture in the Ente
// mobile apps.
//
// It is attached once, around the whole app, rather than to the pairing screen
// alone. A server that cannot be reached puts the app into a five second error
// and retry cycle, and an entry point that only existed while pairing would
// appear for a fraction of a second at a time - unusable for exactly the person
// who needs it, someone whose Apple TV cannot reach ente.com and has to point
// the app at a local server before anything else can work. Keeping the press
// count in one place also means it survives those state changes.
struct DeveloperSettingsGesture: ViewModifier {
    // False during the slideshow, where play/pause belongs to playback.
    let isEnabled: Bool
    let onEndpointChanged: () -> Void

    @State private var pressCount = 0
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            // tvOS has no touchscreen, and these screens have nothing else
            // focusable, so the select button is picked up through a focusable
            // overlay, with play/pause accepted as an alternative.
            .focusable(isEnabled)
            .onTapGesture {
                registerPress()
            }
            .onPlayPauseCommand {
                registerPress()
            }
            .sheet(isPresented: $isPresented) {
                DeveloperSettingsView(onSave: onEndpointChanged)
            }
    }

    private func registerPress() {
        guard isEnabled else { return }
        pressCount += 1
        guard pressCount >= 7 else { return }
        pressCount = 0
        isPresented = true
    }
}

extension View {
    func developerSettingsGesture(
        isEnabled: Bool,
        onEndpointChanged: @escaping () -> Void
    ) -> some View {
        modifier(
            DeveloperSettingsGesture(
                isEnabled: isEnabled,
                onEndpointChanged: onEndpointChanged
            )
        )
    }
}
