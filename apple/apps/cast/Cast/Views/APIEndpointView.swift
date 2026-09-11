import SwiftUI

struct APIEndpointView: View {
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = APIEndpoint.current.absoluteString
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 32) {
            Text("API server")
                .font(.title2.bold())

            Text("Enter your self-hosted API URL.")
                .foregroundStyle(.secondary)

            TextField("https://api.example.com", text: $endpoint)
                .keyboardType(.URL)
                .disableAutocorrection(true)

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            VStack(spacing: 16) {
                Button(action: save) { buttonLabel("Save") }
                    .disabled(isSaving)
                if !APIEndpoint.isProduction {
                    Button {
                        APIEndpoint.reset()
                        onSave()
                        dismiss()
                    } label: { buttonLabel("Use Ente") }
                        .disabled(isSaving)
                }
                Button(role: .cancel) { dismiss() } label: { buttonLabel("Cancel") }
                    .disabled(isSaving)
            }

            if isSaving {
                ProgressView()
            }
        }
        .frame(maxWidth: 720)
        .multilineTextAlignment(.center)
        .interactiveDismissDisabled(isSaving)
        .padding(80)
    }

    private func buttonLabel(_ title: String) -> some View {
        Text(title).frame(width: 240)
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            do {
                try await APIEndpoint.update(endpoint)
                onSave()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }
}
