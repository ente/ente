import "package:flutter/material.dart";
import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:photos/service_locator.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/debug/sample_reports.dart";
import "package:photos/ui/rewind/pages/colour_page.dart";
import "package:photos/ui/rewind/pages/cover_page.dart";
import "package:photos/ui/rewind/pages/setup_pages.dart";
import "package:photos/ui/rewind/pages/top_percent_page.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_viewer.dart";
import "package:photos/ui/rewind/story/rewind_composer.dart";
import "package:photos/ui/rewind/story/rewind_media.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";
import "package:photos/ui/rewind/story/rewind_story_view.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";

const rewindDesignPages = <RewindPage>[CoverPage(), ...setupPages];

const rewindTopPercentPages = <RewindPage>[
  TopPercentPage(percent: 1, count: 12480),
  TopPercentPage(percent: 10, count: 4826),
  TopPercentPage(percent: 25, count: 1712),
];

final rewindColourChapters = [
  for (final (i, colour) in rust.RewindColour.values.indexed)
    _colourChapter(
      rust.ColourOfTheYear(
        colour: colour,
        percent: 17 + 3 * i,
        fileIds: Int64List.fromList([
          for (var photo = 0; photo < 9; photo++) 500000 + 9 * i + photo,
        ]),
      ),
    ),
];

RewindChapter _colourChapter(rust.ColourOfTheYear colour) => RewindChapter([
  ColourPage.pageKey,
], (media) async => [ColourPage(colour, media.photos(colour.fileIds, 9))]);

class RewindGalleryPage extends StatefulWidget {
  const RewindGalleryPage({super.key});

  @override
  State<RewindGalleryPage> createState() => _RewindGalleryPageState();
}

class _RewindGalleryPageState extends State<RewindGalleryPage> {
  late final _assetsReady = rewindService.assets.prepare();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ente Rewind gallery")),
      body: FutureBuilder<bool>(
        future: _assetsReady,
        builder: (context, ready) => switch (ready.data) {
          null => const Center(child: CircularProgressIndicator()),
          false => const Center(child: Text("Rewind assets are unavailable")),
          true => _list(context),
        },
      ),
    );
  }

  Widget _list(BuildContext context) {
    void open(List<RewindPage> pages) =>
        Navigator.of(context).push(RewindViewer(pages: pages).route());

    void openStory(Future<RewindStory> story) =>
        Navigator.of(context).push(RewindStoryView(story: story).route());

    return ListView(
      children: [
        ListTile(
          title: const Text("Design pages"),
          subtitle: const Text("Cover and every chapter setup"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => open(rewindDesignPages),
        ),
        ListTile(
          title: const Text("Top % bands"),
          subtitle: const Text("1%, 10% and 25%"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => open(rewindTopPercentPages),
        ),
        ListTile(
          title: const Text("Colours of the year"),
          subtitle: const Text("All ten paint chips, library photos"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => openStory(
            RewindMedia.sampled().then(
              (media) => RewindStory.compose(rewindColourChapters, media),
            ),
          ),
        ),
        ListTile(
          title: const Text("Badge"),
          subtitle: const Text("Fire each Rive badge trigger"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _BadgePreview()),
          ),
        ),
        for (final sample in rewindSampleReports.entries)
          ListTile(
            title: Text(sample.key),
            subtitle: const Text("Sample report, library photos and people"),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => openStory(
              RewindStory.prepare(sample.value, media: RewindMedia.sampled),
            ),
          ),
      ],
    );
  }
}

class _BadgePreview extends StatefulWidget {
  const _BadgePreview();

  @override
  State<_BadgePreview> createState() => _BadgePreviewState();
}

class _BadgePreviewState extends State<_BadgePreview> {
  var _badge = RewindBadge.defaultBadge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_badge)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const RewindBackdrop(
                  color: Color(0xFF12BB2C),
                  pattern: RewindRays(Color(0xFF16B42E)),
                ),
                RewindBadge(badge: _badge, active: true),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final id in RewindBadge.ids)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: ChoiceChip(
                      label: Text(id),
                      selected: id == _badge,
                      onSelected: (_) => setState(() => _badge = id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
