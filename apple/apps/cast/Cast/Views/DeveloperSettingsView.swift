import SwiftUI

// Runtime server configuration, opened from the pairing screen by pressing the
// remote seven times - the tvOS counterpart of the seven-tap developer
// settings in the Ente mobile apps, so that pointing this app at a self-hosted
// instance does not require building it from source.
struct DeveloperSettingsView: View {
    // Called once the endpoint has changed, so that pairing can restart.
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var endpoint: String = EndpointConfig.customAPIOrigin ?? ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Developer settings")
                    .font(.system(size: 56, weight: .bold))

                Text("Point this Apple TV at a self-hosted Ente server, reachable over https. Leave this empty to use ente.com.")
                    .font(.system(size: 26))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Server endpoint")
                    .font(.system(size: 28, weight: .semibold))

                TextField("https://ente.example.org", text: $endpoint)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 24))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isValidating {
                ProgressView()
            }

            HStack(spacing: 32) {
                Button("Save") {
                    save()
                }
                .disabled(isValidating)

                Button("Use ente.com") {
                    useProduction()
                }
                .disabled(isValidating)

                Button("Cancel") {
                    dismiss()
                }
                .disabled(isValidating)
            }

            Spacer()
        }
        .padding(80)
    }

    private func save() {
        let origin = EndpointConfig.normalize(endpoint)
        guard !origin.isEmpty else {
            useProduction()
            return
        }

        errorMessage = nil
        isValidating = true

        Task {
            do {
                try await EndpointConfig.validate(origin)
                await MainActor.run {
                    EndpointConfig.setAPIOrigin(origin)
                    isValidating = false
                    onSave()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func useProduction() {
        EndpointConfig.setAPIOrigin(nil)
        onSave()
        dismiss()
    }
}

#Preview {
    DeveloperSettingsView(onSave: {})
}
