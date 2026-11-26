import AuthCore
import SwiftUI
import WatchKit

@main
struct AuthWatchApp: App {
  @StateObject private var companion = WatchCompanion()

  var body: some Scene {
    WindowGroup { WatchHome(companion: companion) }
  }
}

private enum WatchStyle {
  static let accent = Color(red: 150 / 255, green: 16 / 255, blue: 214 / 255)
  static let warning = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
}

private struct WatchHome: View {
  @ObservedObject var companion: WatchCompanion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.isLuminanceReduced) private var dimmed
  @State private var selectedTag: String?
  @State private var searchText = ""

  private var visible: Bool { scenePhase == .active && !dimmed }

  private var availableTags: [String] {
    Array(Set(companion.entries.flatMap(\.tags))).sorted()
  }

  private var filteredEntries: [Entry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return companion.entries.filter { entry in
      let matchesTag = selectedTag == nil || entry.tags.contains(selectedTag!)
      let matchesSearch =
        query.isEmpty
        || entry.issuer.localizedCaseInsensitiveContains(query)
        || entry.account.localizedCaseInsensitiveContains(query)
        || entry.tags.contains { $0.localizedCaseInsensitiveContains(query) }
      return matchesTag && matchesSearch
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if !visible {
          hiddenCodes
        } else {
          if let issue = companion.issue {
            Text(message(for: issue)).foregroundStyle(.secondary)
          }
          if companion.status.enrollment == nil {
            Text("Keep codes on this watch for offline use. A watch passcode is required.")
            Button("Set up watch", action: companion.enroll)
              .tint(WatchStyle.accent)
              .disabled(!companion.canEnroll)
            if !companion.canEnroll {
              Text("Open Auth on your iPhone to start.").foregroundStyle(.secondary)
            }
          } else if !companion.status.active {
            Text("On your iPhone, open Ente Auth → Settings → General → Watch to approve.")
          } else if companion.entries.isEmpty {
            Text("No shared accounts yet. Open Watch settings in Auth on your iPhone.")
          }
          if !availableTags.isEmpty {
            TagFilterBar(tags: availableTags, selectedTag: $selectedTag)
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
          }
          ForEach(filteredEntries) { entry in
            if companion.hideCodes {
              EntryRowLink(entry: entry, code: nil, remaining: nil)
            } else {
              TimelineView(
                .periodic(
                  from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)
              ) { timeline in
                let seconds = Int(floor(timeline.date.timeIntervalSince1970))
                let remaining = entry.period - seconds % entry.period
                let code = try? entry.code(at: timeline.date)
                EntryRowLink(entry: entry, code: code, remaining: remaining)
              }
            }
          }
          if companion.status.enrollment != nil || companion.issue == .syncFailed {
            NavigationLink {
              if visible { WatchManagement(companion: companion) } else { hiddenCodes }
            } label: {
              Text("Manage")
            }
          }
        }
      }
      .searchable(text: visible ? $searchText : .constant(""))
      .navigationTitle("Ente Auth")
      .navigationDestination(for: String.self) { id in
        if visible, let entry = companion.entries.first(where: { $0.id == id }) {
          CodeDetail(entry: entry)
        } else {
          hiddenCodes
        }
      }
    }
    .privacySensitive()
    .onAppear { companion.setVisible(visible) }
    .onChange(of: visible) { _, value in companion.setVisible(value) }
    .onChange(of: companion.entries) { _, _ in
      if visible, let selectedTag, !availableTags.contains(selectedTag) {
        self.selectedTag = nil
      }
    }
  }

  private var hiddenCodes: some View {
    Image(systemName: "lock.shield").font(.largeTitle).accessibilityLabel("Codes hidden")
  }

  private func message(for issue: WatchCompanion.Issue) -> LocalizedStringKey {
    switch issue {
    case .passcodeRequired: return "Set a passcode in watch Settings, then try again."
    case .unlockWatch: return "Unlock your watch to show codes."
    case .syncFailed: return "Could not sync. Open Auth on your iPhone and try again."
    }
  }
}

private struct TagFilterBar: View {
  let tags: [String]
  @Binding var selectedTag: String?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          tagButton(title: "All", isSelected: selectedTag == nil) { selectedTag = nil }
            .id(String?.none)
          ForEach(tags, id: \.self) { tag in
            tagButton(title: tag, isSelected: selectedTag == tag) {
              selectedTag = selectedTag == tag ? nil : tag
            }
            .id(String?.some(tag))
          }
        }
        .padding(.vertical, 2)
      }
      .onChange(of: selectedTag) { _, tag in
        withAnimation { proxy.scrollTo(tag, anchor: .center) }
      }
    }
  }

  private func tagButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View
  {
    Button(action: action) {
      Text(title)
        .font(.footnote.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isSelected ? WatchStyle.accent : Color.white.opacity(0.18), in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct EntryRowLink: View {
  let entry: Entry
  let code: String?
  let remaining: Int?

  var body: some View {
    NavigationLink(value: entry.id) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Text(entry.issuer.isEmpty ? entry.account : entry.issuer)
            .font(.headline).lineLimit(1)
          if entry.pinned {
            Image(systemName: "pin.fill")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        if !entry.issuer.isEmpty && !entry.account.isEmpty {
          Text(entry.account).font(.caption).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.middle)
        }
        if let code, let remaining {
          let isWarning = remaining <= 5
          Text(formatCode(code))
            .font(.system(.title3, design: .monospaced).bold())
            .foregroundStyle(isWarning ? WatchStyle.warning : .primary)
            .environment(\.layoutDirection, .leftToRight)
            .privacySensitive()
          ProgressView(value: Double(remaining), total: Double(entry.period))
            .tint(isWarning ? WatchStyle.warning : WatchStyle.accent)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityLabel(
      [entry.issuer, entry.account].filter { !$0.isEmpty }.joined(separator: ", ")
    )
    .accessibilityValue(
      code.map { $0.map(String.init).joined(separator: " ") } ?? "")
  }
}

private struct WatchManagement: View {
  @ObservedObject var companion: WatchCompanion
  @Environment(\.dismiss) private var dismiss
  @State private var confirmErase = false

  var body: some View {
    List {
      Button("Erase watch data", role: .destructive) { confirmErase = true }
    }
    .navigationTitle("Manage")
    .confirmationDialog(
      "Erase all codes from this watch?", isPresented: $confirmErase, titleVisibility: .visible
    ) {
      Button("Erase watch data", role: .destructive) {
        companion.erase()
        dismiss()
      }
    } message: {
      Text("Your phone keeps its accounts. You must approve this watch again to sync codes.")
    }
  }
}

private struct CodeDetail: View {
  let entry: Entry

  var body: some View {
    ScrollView {
      if !entry.account.isEmpty {
        Text(entry.account).font(.caption).foregroundStyle(.secondary)
          .lineLimit(1).truncationMode(.middle)
          .padding(.horizontal)
      }
      TimelineView(
        .periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)
      ) { timeline in
        CodeDetailContent(entry: entry, date: timeline.date)
      }
    }
    .navigationTitle(entry.issuer.isEmpty ? "Code" : entry.issuer)
    .privacySensitive()
  }
}

private struct CodeDetailContent: View {
  let entry: Entry
  let date: Date
  var body: some View {
    let seconds = Int(floor(date.timeIntervalSince1970))
    let bucket = seconds / entry.period
    let remaining = entry.period - seconds % entry.period
    let isWarning = remaining <= 5
    let code = (try? entry.code(at: date)) ?? "—"

    VStack(spacing: 10) {
      Text(formatCode(code))
        .font(.system(.title2, design: .monospaced).bold())
        .foregroundStyle(isWarning ? WatchStyle.warning : .primary)
        .minimumScaleFactor(0.6).lineLimit(1)
        .environment(\.layoutDirection, .leftToRight)
        .privacySensitive()
        .accessibilityLabel("Code")
        .accessibilityValue(code.map(String.init).joined(separator: " "))
      ProgressView(value: Double(remaining), total: Double(entry.period))
        .tint(isWarning ? WatchStyle.warning : WatchStyle.accent)
        .accessibilityHidden(true)
      Text(remaining == 1 ? "1 second" : "\(remaining) seconds")
        .font(.caption).foregroundStyle(.secondary)
      if isWarning {
        let nextCode =
          (try? entry.code(at: date.addingTimeInterval(TimeInterval(entry.period)))) ?? "—"
        Text("Next: \(formatCode(nextCode))")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .environment(\.layoutDirection, .leftToRight)
          .privacySensitive()
          .accessibilityLabel("Next code \(nextCode.map(String.init).joined(separator: " "))")
      }
    }
    .padding(.horizontal)
    .padding(.bottom, 16)
    .onChange(of: bucket) { _, _ in
      WKInterfaceDevice.current().play(.click)
    }
  }
}
