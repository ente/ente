import SwiftUI

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss
    let embeddedInNavigation: Bool

    @State private var entries: [EnsuLogEntry] = []
    @State private var query: String = ""
    @State private var selectedEntry: EnsuLogEntry?

    @State private var shareArchive: LogArchive?
    @State private var exportArchive: LogArchive?

    private let logger = EnsuLogging.shared.logger("LogsView")

    init(embeddedInNavigation: Bool = false) {
        self.embeddedInNavigation = embeddedInNavigation
    }

    var body: some View {
        Group {
            if embeddedInNavigation {
                VStack(spacing: 0) {
                    content
                }
                .background(EnsuColor.backgroundBase)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        content
                    }
                    .background(EnsuColor.backgroundBase)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        toolbarContent
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                }
            }
        }
        .task {
            refreshEntries()
        }
        .sheet(item: $shareArchive) { archive in
            ActivityView(activityItems: [archive.url])
        }
        .sheet(item: $exportArchive) { archive in
            ExportDocumentPicker(urls: [archive.url])
        }
        .sheet(item: $selectedEntry) { entry in
            LogDetailView(entry: entry)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Logs")
                .font(EnsuTypography.large)
                .foregroundStyle(EnsuColor.textPrimary)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Share") { shareTapped() }
                Button("Export") { exportTapped() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
            searchField

            if filteredEntries.isEmpty {
                Text("No logs available")
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: EnsuSpacing.sm) {
                        ForEach(filteredEntries) { entry in
                            LogCard(entry: entry) {
                                selectedEntry = entry
                            }
                        }
                    }
                    .padding(.bottom, EnsuSpacing.lg)
                }
            }
        }
        .padding(EnsuSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var searchField: some View {
        TextField("Search logs", text: $query)
            .font(EnsuTypography.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, EnsuSpacing.inputHorizontal)
            .padding(.vertical, EnsuSpacing.inputVertical)
            .background(EnsuColor.fillFaint)
            .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.input, style: .continuous))
    }

    private var filteredEntries: [EnsuLogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        let lower = trimmed.lowercased()
        return entries.filter { entry in
            entry.message.lowercased().contains(lower)
                || entry.tag.lowercased().contains(lower)
                || entry.level.rawValue.lowercased().contains(lower)
                || (entry.details?.lowercased().contains(lower) == true)
        }
    }

    private func refreshEntries() {
        entries = parseLogText(EnsuLogging.shared.readLogText())
    }

    private func parseLogText(_ text: String) -> [EnsuLogEntry] {
        var entries: [EnsuLogEntry] = []
        for line in text.components(separatedBy: .newlines) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if let match = logLineRegex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
               let tagRange = Range(match.range(at: 1), in: line),
               let levelRange = Range(match.range(at: 2), in: line),
               let timestampRange = Range(match.range(at: 3), in: line),
               let messageRange = Range(match.range(at: 4), in: line) {
                entries.append(
                    EnsuLogEntry(
                        timestamp: logLineFormatter.date(from: String(line[timestampRange])) ?? Date(),
                        level: EnsuLogLevel(rawValue: String(line[levelRange])) ?? .info,
                        tag: String(line[tagRange]),
                        message: String(line[messageRange]),
                        details: nil
                    )
                )
            } else if let last = entries.last {
                entries[entries.count - 1] = EnsuLogEntry(
                    timestamp: last.timestamp,
                    level: last.level,
                    tag: last.tag,
                    message: last.message,
                    details: last.details.map { $0 + "\n" + line } ?? line
                )
            } else {
                entries.append(
                    EnsuLogEntry(timestamp: Date(), level: .info, tag: "Log", message: line, details: nil)
                )
            }
        }
        return entries.reversed()
    }

    private func shareTapped() {
        do {
            let archiveURL = try EnsuLogging.shared.createLogsArchive()
            shareArchive = LogArchive(url: archiveURL)
        } catch {
            logger.error("Failed to create logs archive", error)
        }
    }

    private func exportTapped() {
        do {
            let archiveURL = try EnsuLogging.shared.createLogsArchive()
            exportArchive = LogArchive(url: archiveURL)
        } catch {
            logger.error("Failed to create logs archive", error)
        }
    }

}

private struct LogArchive: Identifiable {
    let id = UUID()
    let url: URL
}

private struct LogCard: View {
    let entry: EnsuLogEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: EnsuSpacing.xs) {
                HStack(spacing: EnsuSpacing.sm) {
                    Circle()
                        .fill(levelColor(entry.level))
                        .frame(width: 7, height: 7)

                    Text(entry.tag)
                        .font(EnsuTypography.mini)
                        .foregroundStyle(EnsuColor.textMuted)
                        .lineLimit(1)

                    Spacer(minLength: EnsuSpacing.sm)

                    Text(logTimestampFormatter.string(from: entry.timestamp))
                        .font(EnsuTypography.mini)
                        .foregroundStyle(EnsuColor.textMuted)

                    ZStack {
                        if entry.details?.isEmpty == false {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(EnsuColor.textMuted)
                        }
                    }
                    .frame(width: 12)
                }

                Text(entry.message)
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, EnsuSpacing.xs)
        }
        .buttonStyle(.plain)
    }

    private func levelColor(_ level: EnsuLogLevel) -> Color {
        switch level {
        case .info:
            return EnsuColor.textMuted
        case .warning:
            return EnsuColor.accent
        case .error:
            return EnsuColor.error
        }
    }
}

private struct LogDetailView: View {
    let entry: EnsuLogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EnsuSpacing.md) {
                    Text("Level: \(entry.level.rawValue)")
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textMuted)

                    Text("Tag: \(entry.tag)")
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textMuted)

                    Text("Time: \(logTimestampFormatter.string(from: entry.timestamp))")
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textMuted)

                    Divider()

                    Text(entry.message)
                        .font(EnsuTypography.body)
                        .foregroundStyle(EnsuColor.textPrimary)

                    if let details = entry.details, !details.isEmpty {
                        Text("Details")
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)

                        Text(details)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(EnsuColor.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(EnsuSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Log details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") { UIPasteboard.general.string = copyText }
                }
            }
        }
    }

    private var copyText: String {
        var out = "Level: \(entry.level.rawValue)\nTag: \(entry.tag)\n\n\(entry.message)"
        if let details = entry.details, !details.isEmpty {
            out += "\n\nDetails:\n\(details)"
        }
        return out
    }
}

private let logTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "MMM d, h:mm:ss a"
    return formatter
}()

private let logLineFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
}()

private let logLineRegex: NSRegularExpression = {
    let pattern = "^\\[(.+?)\\]\\[(.+?)\\] \\[(.+?)\\] (.*)$"
    return try! NSRegularExpression(pattern: pattern, options: [])
}()

import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ExportDocumentPicker: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

