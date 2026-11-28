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
  static let track = Color(white: 62 / 255)
}

private struct WatchHome: View {
  @ObservedObject var companion: WatchCompanion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.isLuminanceReduced) private var dimmed
  @AppStorage("selectedTag") private var selectedTag: String?
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

  private var sharedPeriod: Int? {
    let periods = Set(filteredEntries.map(\.period))
    return companion.hideCodes || periods.count != 1 ? nil : periods.first
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
            Text("Use your codes offline on this watch. Needs a watch passcode.")
            Button("Set up watch", action: companion.enroll)
              .tint(WatchStyle.accent)
              .disabled(!companion.canEnroll)
            if !companion.canEnroll {
              Text("Open Ente Auth on your iPhone first.").foregroundStyle(.secondary)
            }
          } else if !companion.status.active {
            Text("On your iPhone, open Ente Auth → Settings → General → Watch and tap Share codes.")
          } else if companion.entries.isEmpty {
            Text("No accounts yet. Add one in Ente Auth on your iPhone.")
          }
          if !availableTags.isEmpty {
            TagFilterBar(tags: availableTags, selectedTag: $selectedTag)
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
          }
          ForEach(filteredEntries) { entry in
            if companion.hideCodes {
              EntryRowLink(entry: entry, code: nil, remaining: nil, showsBar: false)
            } else {
              TimelineView(
                .periodic(
                  from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)
              ) { timeline in
                let seconds = Int(floor(timeline.date.timeIntervalSince1970))
                let remaining = entry.period - seconds % entry.period
                let code = try? entry.code(at: timeline.date)
                EntryRowLink(
                  entry: entry, code: code, remaining: remaining, showsBar: sharedPeriod == nil)
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
      .padding(.horizontal, sharedPeriod == nil ? 0 : 5)
      .containerBackground(for: .navigation) {
        if visible, let period = sharedPeriod {
          TimelineView(
            .periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)
          ) { timeline in
            let remaining = period - Int(floor(timeline.date.timeIntervalSince1970)) % period
            Countdown(
              shape: ScreenEdge(), progress: Double(remaining) / Double(period),
              tint: remaining <= 5 ? WatchStyle.warning : WatchStyle.accent)
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
    case .syncFailed: return "Couldn't sync. Open Ente Auth on your iPhone and try again."
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
  let showsBar: Bool

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
          if showsBar {
            Countdown(
              shape: BarLine(), progress: Double(remaining) / Double(entry.period),
              tint: isWarning ? WatchStyle.warning : WatchStyle.accent
            )
            .frame(height: 4)
            .padding(.vertical, 4)
          }
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
      Text("Your phone keeps its accounts.")
    }
  }
}

private struct CodeDetail: View {
  let entry: Entry

  var body: some View {
    TimelineView(
      .periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)
    ) { timeline in
      CodeDetailContent(entry: entry, date: timeline.date)
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
    let nextCode = (try? entry.code(at: date.addingTimeInterval(TimeInterval(entry.period)))) ?? "—"

    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: 8) {
          if !entry.account.isEmpty {
            Text(entry.account).font(.caption).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.middle)
          }
          Text(formatCode(code))
            .font(.system(.title, design: .monospaced).bold())
            .foregroundStyle(isWarning ? WatchStyle.warning : .primary)
            .minimumScaleFactor(0.5).lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
            .privacySensitive()
            .accessibilityLabel("Code")
            .accessibilityValue(
              "\(code.map(String.init).joined(separator: " ")), \(remaining == 1 ? "1 second" : "\(remaining) seconds")"
            )
          Text("Next: \(formatCode(nextCode))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(isWarning ? .primary : .secondary)
            .environment(\.layoutDirection, .leftToRight)
            .privacySensitive()
            .accessibilityLabel("Next code \(nextCode.map(String.init).joined(separator: " "))")
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
      }
    }
    .containerBackground(for: .navigation) {
      Countdown(
        shape: ScreenEdge(), progress: Double(remaining) / Double(entry.period),
        tint: isWarning ? WatchStyle.warning : WatchStyle.accent)
    }
    .onChange(of: bucket) { _, _ in
      WKInterfaceDevice.current().play(.click)
    }
  }
}

private struct Countdown<S: Shape>: View {
  let shape: S
  let progress: Double
  let tint: Color

  var body: some View {
    let style = StrokeStyle(lineWidth: 4, lineCap: .round)
    ZStack {
      shape.stroke(WatchStyle.track, style: style)
      shape.trim(from: 0, to: progress).stroke(tint, style: style)
    }
    .accessibilityHidden(true)
  }
}

private struct BarLine: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX + 2, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
    }
  }
}

private struct ScreenEdge: Shape {
  private static let cornerRadii: [Int: CGFloat] = [
    162: 28.6, 176: 38.4, 184: 34.4, 187: 45.4, 198: 41.4, 205: 55.2, 208: 51.6, 211: 58,
  ]
  private static let inset: CGFloat = 3

  func path(in rect: CGRect) -> Path {
    let radius = (Self.cornerRadii[Int(rect.width)] ?? rect.width / 4) - Self.inset
    let edge = RoundedRectangle(cornerRadius: radius, style: .continuous)
      .path(in: rect.insetBy(dx: Self.inset, dy: Self.inset))
    var path = edge.trimmedPath(from: 0.75, to: 1)
    path.addPath(edge.trimmedPath(from: 0, to: 0.75))
    return path
  }
}
