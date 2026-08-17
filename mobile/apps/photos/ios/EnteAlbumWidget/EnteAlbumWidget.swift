import SwiftUI
import UIKit
import WidgetKit

private let widgetGroupId = "group.io.ente.frame.EnteMemoryWidget"

struct Provider: TimelineProvider {
    let minutes = 15
    let data = UserDefaults(suiteName: widgetGroupId)

    private func shouldHideTitle() -> Bool {
        let hideFlags = data?.integer(forKey: "widgetHideTitleFlags") ?? 0
        return (hideFlags & (1 << 1)) != 0
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
            date: Date(), index: -2, imageData: nil, title: "Favorites",
            subTitle: "May 3, 2021",
            generatedId: nil, mainKey: nil, hideTitle: hideTitle)
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        var entries: [FileEntry] = []

        let currentDate = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime,
            direction: .backward
        )!

        var totalAlbums =
            data?.integer(forKey: "totalAlbums")

        let hideTitle = shouldHideTitle()

        if totalAlbums != nil && totalAlbums! > 0 {
            let count = totalAlbums! > 5 ? 5 : totalAlbums
            for offset in 0..<count! {
                let randomInt = Int.random(in: 0..<totalAlbums!)
                let entryDate = Calendar.current.date(
                    byAdding: .minute, value: minutes * offset, to: currentDate
                )!
                let imageData =
                    data?.string(forKey: "albums_widget_" + String(randomInt))
                let dictionary = data?.dictionary(
                    forKey: "albums_widget_" + String(randomInt) + "_data")
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

struct EnteAlbumWidgetEntryView: View {
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
                    if let uiImage = UIImage(named: "AlbumsWidgetPreview") {
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
                } else if let uiImage = UIImage(named: "AlbumsWidgetDefault") {
                    VStack(spacing: 4) {
                        Spacer()
                        Image(uiImage: uiImage)
                            .resizable()
                            .backwardWidgetFullColorRenderingMode()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)

                        Text("Albums")
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
                        ? "albumwidget://message?generatedId=\(entry.generatedId!)&mainKey=\(entry.mainKey ?? "")&homeWidget"
                        : "albumwidget://configure?homeWidget"
                )
            )
        }
    }
}

struct EnteAlbumWidget: Widget {
    let kind: String = "EnteAlbumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                EnteAlbumWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                EnteAlbumWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Albums")
        .description("See photos from selected albums including your favorites")
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    EnteAlbumWidget()
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
