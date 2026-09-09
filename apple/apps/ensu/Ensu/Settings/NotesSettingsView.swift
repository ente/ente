import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct NotesSettingsView: View {
    @ObservedObject var store: NotesStore
    @State private var showPicker = false
    @State private var removing: NoteCollectionState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EnsuSpacing.md) {
                ForEach(store.collections) { collection in
                    EnsuCard {
                        HStack {
                            VStack(alignment: .leading, spacing: EnsuSpacing.xs) {
                                Text(collection.label)
                                    .font(EnsuTypography.large)
                                    .foregroundStyle(EnsuColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(summary(collection))
                                    .font(EnsuTypography.mini)
                                    .foregroundStyle(EnsuColor.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            ActionButton(icon: "Delete01Icon", tooltip: "Remove \(collection.label)", size: 44) {
                                removing = collection
                            }
                        }
                        if let progress = collection.progress {
                            HStack(spacing: EnsuSpacing.sm) {
                                ProgressView(value: Double(progress), total: 100)
                                    .tint(EnsuColor.action)
                                Text("\(progress)%")
                                    .font(EnsuTypography.mini)
                                    .foregroundStyle(EnsuColor.textMuted)
                            }
                        } else if collection.status == .indexing || collection.status == .updating {
                            ProgressView().tint(EnsuColor.action)
                        }
                        if collection.status == .pending {
                            Text("Indexing will continue when the app and model are ready.")
                                .font(EnsuTypography.small)
                                .foregroundStyle(EnsuColor.textMuted)
                        }
                        if let error = collection.error {
                            Text(error)
                                .font(EnsuTypography.small)
                                .foregroundStyle(EnsuColor.error)
                        }
                        if collection.status == .error || collection.status == .unavailable {
                            CompactButton(text: "Retry") {
                                store.retry(collection.id)
                            }
                        }
                    }
                }
                CompactButton(text: "Add notes folder") {
                    showPicker = true
                }
                Text("Ensu reads and indexes markdown files in the selected folder. Source files are never modified.")
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)
                if let error = store.operationError {
                    Text(error)
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.error)
                }
            }
            .padding(EnsuSpacing.lg)
        }
        .background(EnsuColor.backgroundBase)
        .navigationTitle("Your Notes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) { NotesFolderPicker { store.add($0) } }
        .alert("Remove folder?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let collection = removing { store.remove(collection.id) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Remove this folder from Your Notes? Your original files will be kept.") }
    }

    private func summary(_ collection: NoteCollectionState) -> String {
        let count = collection.documentCount
        let indexing = collection.status == .indexing || collection.status == .updating
        var text = indexing && count == 0 ? "Preparing notes…" : "\(count) \(count == 1 ? "note indexed" : "notes indexed")"
        if let timestamp = collection.lastUpdatedAtMs {
            let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
            text += " · Updated at \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return text
    }
}

private struct NotesFolderPicker: UIViewControllerRepresentable {
    let selected: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL) -> Void
        init(selected: @escaping (URL) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { selected(url) }
        }
    }
}

struct NotesPreviewView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return preview
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    static func dismantleUIViewController(_ controller: QLPreviewController, coordinator: Coordinator) {
        controller.dataSource = nil
        try? FileManager.default.removeItem(at: coordinator.url.deletingLastPathComponent())
    }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
