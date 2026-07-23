import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/ui/viewer/people/memory_lane_banner.dart";

void main() {
  group("MemoryLaneBannerSection", () {
    late PersonEntity person;

    setUp(() {
      person = PersonEntity("person-1", PersonData(name: "Alex"));
    });

    testWidgets("renders banner when timeline is ready", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MemoryLaneBannerSection(
            showBanner: true,
            person: person,
            onTap: () {},
            loadTimeline: (_) async => null,
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(MemoryLaneBanner), findsOneWidget);
      final context = tester.element(find.byType(MemoryLaneBanner));
      final l10n = AppLocalizations.of(context)!;
      expect(find.text(l10n.facesTimelineBannerTitle), findsOneWidget);
    });

    testWidgets("hides banner when timeline is unavailable", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MemoryLaneBannerSection(
            showBanner: false,
            person: person,
            onTap: () {},
            loadTimeline: (_) async => null,
          ),
        ),
      );

      expect(find.byType(MemoryLaneBanner), findsNothing);
    });

    testWidgets("hides banner when tap callback is missing", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MemoryLaneBannerSection(
            showBanner: true,
            person: person,
            onTap: null,
            loadTimeline: (_) async => null,
          ),
        ),
      );

      expect(find.byType(MemoryLaneBanner), findsNothing);
    });
  });
}
