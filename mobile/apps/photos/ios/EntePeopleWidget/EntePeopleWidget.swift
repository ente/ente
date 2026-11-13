import SwiftUI
import UIKit
import WidgetKit

private let widgetGroupId = "group.io.ente.frame.EnteMemoryWidget"

struct Provider: TimelineProvider {
    let minutes = 15
    let data = UserDefaults(suiteName: widgetGroupId)

    private func shouldHideTitle() -> Bool {
        let hideFlags = data?.integer(forKey: "widgetHideTitleFlags") ?? 0
        return (hideFlags & (1 << 2)) != 0
    }

    func placeholder(in _: Context) -> FileEntry {
        let hideTitle = shouldHideTitle()
        return FileEntry(
            date: Date(), index: nil, imageData: nil, title: "Title", subTitle: "Sub Title",
            generatedId: nil, mainKey: nil, hideTitle: hideTitle)
    }

    func getSnapshot(in _: Context, completion: @escaping (FileEntry) -> Void) {
        let hideTitle = shouldHideTitle()
        let entry = FileEntry(
            date: Date(), index: -2, imageData: nil, title: "Jane Fonda",
            subTitle: "Sep 23, 2021",
            generatedId: nil, mainKey: nil, hideTitle: hideTitle)
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        var entries: [FileEntry] = []

        let currentDate = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime,
            direction: .backward
        )!

        var totalPeople =
            data?.integer(forKey: "totalPeople")

        let hideTitle = shouldHideTitle()

        if totalPeople != nil && totalPeople! > 0 {
            let count = totalPeople! > 5 ? 5 : totalPeople
            for offset in 0..<count! {
                let randomInt = Int.random(in: 0..<totalPeople!)
                let entryDate = Calendar.current.date(
                    byAdding: .minute, value: minutes * offset, to: currentDate
                )!
                let imageData =
                    data?.string(forKey: "people_widget_" + String(randomInt))
                let dictionary = data?.dictionary(
                    forKey: "people_widget_" + String(randomInt) + "_data")
                let generatedId = dictionary?["generatedId"] as? Int
                let subTitle = dictionary?["subText"] as? String
                let title = dictionary?["title"] as? String
                let mainKey = dictionary?["mainKey"] as? String

                let entry = FileEntry(
                    date: entryDate, index: randomInt, imageData: imageData, title: title,
                    subTitle: subTitle, generatedId: generatedId, mainKey: mainKey,
                    hideTitle: hideTitle)
                entries.append(entry)
            }
        } else {
            let entry = FileEntry(
                date: Date(), index: -1, imageData: nil, title: nil, subTitle: nil,
                generatedId: nil, mainKey: nil, hideTitle: hideTitle
            )
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

}

struct FileEntry: TimelineEntry {
    let date: Date
    let index: Int?
    let imageData: String?
    let title: String?
    let subTitle: String?
    var generatedId: Int?
    var mainKey: String?
    var hideTitle: Bool = false
}

struct EntePeopleWidgetEntryView: View {
    var entry: Provider.Entry
    let data = UserDefaults.init(suiteName: widgetGroupId)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let imageData = entry.imageData,
                    let uiImage = UIImage(contentsOfFile: imageData)
                {
                    Image(uiImage: uiImage)
                        .resizable()
                        .backwardWidgetFullColorRenderingMode()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            Group {
                                if !entry.hideTitle {
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.black.opacity(0.7), Color.clear,
                                        ]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                    .frame(height: geometry.size.height * 0.4)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                    .backwardWidgetAccentable(true)
                                }
                            }
                        )
                        .overlay(
                            Group {
                                if !entry.hideTitle {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title ?? "").font(
                                            .custom("Inter", size: 14, relativeTo: .caption)
                                        )
                                        .bold()
                                        .foregroundStyle(.white)
                                        .shadow(radius: 20)
                                        Text(entry.subTitle ?? "")
                                            .font(.custom("Inter", size: 12, relativeTo: .caption2))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 20)
                                    }
                                    .padding(.leading, geometry.size.width * 0.05)
                                    .padding(.bottom, geometry.size.height * 0.05)
                                }
                            },
                            alignment: .bottomLeading
                        )
                } else if entry.index == -2 {
                    if let uiImage = UIImage(named: "PeopleWidgetPreview") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .backwardWidgetFullColorRenderingMode()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .overlay(
                                Group {
                                    if !entry.hideTitle {
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.black.opacity(0.7), Color.clear,
                                            ]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                        .frame(height: geometry.size.height * 0.4)
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                        .backwardWidgetAccentable(true)
                                    }
                                }
                            )
                            .overlay(
                                Group {
                                    if !entry.hideTitle {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title ?? "").font(
                                                .custom("Inter", size: 14, relativeTo: .caption)
                                            )
                                            .bold()
                                            .foregroundStyle(.white)
                                            .shadow(radius: 20)
                                            Text(entry.subTitle ?? "")
                                                .font(
                                                    .custom(
                                                        "Inter", size: 12, relativeTo: .caption2)
                                                )
                                                .foregroundStyle(.white)
                                                .shadow(radius: 20)
                                        }
                                        .padding(.leading, geometry.size.width * 0.05)
                                        .padding(.bottom, geometry.size.height * 0.05)
                                    }
                                },
                                alignment: .bottomLeading
                            )
                    }
                } else if let uiImage = UIImage(named: "PeopleWidgetDefault") {
                    VStack(spacing: 4) {
                        Spacer()
                        Image(uiImage: uiImage)
                            .resizable()
                            .backwardWidgetFullColorRenderingMode()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)

                        Text("People")
                            .font(.custom("Inter", size: 14, relativeTo: .caption))
                            .bold()
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .backwardWidgetAccentable(true)

                        Text("Click to customise")
                            .font(.custom("Inter", size: 12, relativeTo: .caption2))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 8)
                            .backwardWidgetAccentable(true)
                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Color.gray
                }
            }
            .clipped()
            .edgesIgnoringSafeArea(.all)
            .widgetURL(
                URL(
                    string: entry.generatedId != nil
                        ? "peoplewidget://message?generatedId=\(entry.generatedId!)&mainKey=\(entry.mainKey ?? "")&homeWidget"
                        : "peoplewidget://configure?homeWidget"
                )
            )
        }
    }
}

struct EntePeopleWidget: Widget {
    let kind: String = "EntePeopleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                EntePeopleWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                EntePeopleWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("People")
        .description("See photos of your favorite people")
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    EntePeopleWidget()
} timeline: {
    FileEntry(
        date: .now, index: -2, imageData: nil, title: nil, subTitle: nil, generatedId: nil,
        mainKey: nil)
    FileEntry(
        date: .now, index: -2, imageData: nil, title: nil, subTitle: nil, generatedId: nil,
        mainKey: nil)
}

extension View {
    @ViewBuilder
    func backwardWidgetAccentable(_ accentable: Bool = true) -> some View {
        if #available(iOS 16.0, *) {
            self.widgetAccentable(accentable)
        } else {
            self
        }
    }
}

extension Image {
    @ViewBuilder
    func backwardWidgetAccentedRenderingMode(_ isAccentedRenderingMode: Bool = true) -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(isAccentedRenderingMode ? .accented : .fullColor)
        } else {
            self
        }
    }

    @ViewBuilder
    func backwardWidgetFullColorRenderingMode() -> some View {
        backwardWidgetAccentedRenderingMode(false)
    }
}
