import "package:flutter/material.dart";
import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:photos/service_locator.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/debug/sample_reports.dart";
import "package:photos/ui/rewind/pages/art_twin_page.dart";
import "package:photos/ui/rewind/pages/badge_reveal_page.dart";
import "package:photos/ui/rewind/pages/colour_page.dart";
import "package:photos/ui/rewind/pages/cover_page.dart";
import "package:photos/ui/rewind/pages/ritual_streak_page.dart";
import "package:photos/ui/rewind/pages/setup_pages.dart";
import "package:photos/ui/rewind/pages/top_percent_page.dart";
import "package:photos/ui/rewind/pages/tour_page.dart";
import "package:photos/ui/rewind/reel/rewind_video_export.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_viewer.dart";
import "package:photos/ui/rewind/story/rewind_composer.dart";
import "package:photos/ui/rewind/story/rewind_media.dart";
import "package:photos/ui/rewind/story/rewind_rituals.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";
import "package:photos/ui/rewind/story/rewind_story_view.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";

final rewindDesignPages = <RewindPage>[
  const CoverPage(),
  ...setupPages,
  ritualStreakSetupPage(
    const RewindRituals(
      longestStreak: 12,
      checkIns: 40,
      busiestMonth: 3,
      continued: 1,
      built: 1,
      started: 1,
      icons: ["📸"],
    ),
  ),
];

const rewindSampleRituals = RewindRituals(
  longestStreak: 64,
  checkIns: 148,
  busiestMonth: 8,
  continued: 3,
  built: 3,
  started: 2,
  icons: ["🏃", "📚"],
);

const rewindTopPercentPages = <RewindPage>[
  TopPercentPage(percent: 1, count: 15059),
  TopPercentPage(percent: 8, count: 5765),
  TopPercentPage(percent: 13, count: 4170),
  TopPercentPage(percent: 19, count: 3286),
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

List<RewindPage> rewindTourPages(rust.RewindReport report) => [
  if (report.tour case final tour?) TourPage(tour),
];

Future<RewindStory> _sampleStory(rust.RewindReport report) async =>
    RewindStory.compose(
      rewindChapters(report, rewindSampleRituals),
      await RewindMedia.sampled(),
    );

RewindChapter _colourChapter(rust.ColourOfTheYear colour) =>
    RewindChapter([ColourPage.pageKey, ArtTwinPage.pageKey], (media) async {
      return [
        ColourPage(colour, media.photos(colour.fileIds, 9)),
        ArtTwinPage(colour.colour),
      ];
    });

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

    Future<void> openStory(Future<RewindStory> story) async {
      final ready = await story;
      if (!context.mounted || ready.pages.isEmpty) return;
      await Navigator.of(context).push(RewindStoryView(story: ready).route());
    }

    Future<void> openVideo(Future<RewindStory> story) async {
      final ready = await story;
      if (!context.mounted) return;
      try {
        await shareRewindVideo(
          context,
          pages: ready.pages,
          loadMedia: ready.loadPhotosOf,
        );
      } finally {
        for (final page in ready.pages) {
          page.release();
        }
      }
    }

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
          subtitle: const Text("1%, 8%, 13% and 19%"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => open(rewindTopPercentPages),
        ),
        ListTile(
          title: const Text("Colours of the year"),
          subtitle: const Text("All ten paint chips and art twins"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => openStory(
            RewindMedia.sampled().then(
              (media) => RewindStory.compose(rewindColourChapters, media),
            ),
          ),
        ),
        for (final sample in rewindSampleReports.entries)
          if (rewindTourPages(sample.value).isNotEmpty)
            ListTile(
              title: Text("Tour tee: ${sample.key}"),
              trailing: const Icon(Icons.chevron_right_outlined),
              onTap: () => open(rewindTourPages(sample.value)),
            ),
        if (rewindService.state.value?.status case rust.RewindStatus_Ready(
          :final report,
        ) when report.tour != null)
          ListTile(
            title: const Text("Tour tee: your library"),
            subtitle: const Text("From the computed Rewind"),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => open(rewindTourPages(report)),
          ),
        if (rewindService.state.value?.status case rust.RewindStatus_Ready(
          :final report,
        ))
          ListTile(
            title: const Text("Photo cards: your library"),
            subtitle: const Text("Tunnel, tower, globe, timelapse, mosaic"),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => openStory(
              RewindMedia.load().then(
                (media) =>
                    RewindStory.compose(rewindPhotoCardChapters(report), media),
              ),
            ),
          ),
        ListTile(
          title: const Text("Ritual streak: sample"),
          subtitle: const Text("64 days, 148 check-ins, 3 rituals"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => open([
            ritualStreakSetupPage(rewindSampleRituals),
            const RitualStreakPage(rewindSampleRituals),
          ]),
        ),
        ListTile(
          title: const Text("Ritual streak: your rituals"),
          subtitle: const Text("From the rituals on this device"),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => openStory(
            RewindMedia.sampled().then(
              (media) => RewindStory.compose([
                ritualStreakChapter(RewindRituals.current()),
              ], media),
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
            onTap: () => openStory(_sampleStory(sample.value)),
          ),
        for (final sample in rewindSampleReports.entries)
          ListTile(
            title: Text("${sample.key} video"),
            subtitle: const Text("Export the reel and open the share sheet"),
            trailing: const Icon(Icons.movie_outlined),
            onTap: () => openVideo(_sampleStory(sample.value)),
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
                BadgeRevealPage.backdrop,
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
