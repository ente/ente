import "package:flutter_test/flutter_test.dart";
import "package:photos/models/gallery/justified_layout_strategy.dart";
import "package:photos/models/gallery/justified_layout_tuning.dart";
import "package:photos/settings/local_settings.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("gallery layout defaults to grid", () async {
    SharedPreferences.setMockInitialValues({});
    final settings = LocalSettings(await SharedPreferences.getInstance());

    expect(settings.getGalleryLayoutType(), GalleryLayoutType.grid);
  });

  test("gallery layout persists justified", () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = LocalSettings(preferences);

    await settings.setGalleryLayoutType(GalleryLayoutType.justified);

    expect(settings.getGalleryLayoutType(), GalleryLayoutType.justified);
    expect(
      preferences.getString(LocalSettings.kGalleryLayoutType),
      "justified",
    );
  });

  test(
    "justified strategy defaults to Comfort Large and persists alternatives",
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = LocalSettings(preferences);
      expect(
        settings.getJustifiedLayoutStrategy(),
        JustifiedLayoutStrategy.comfortLarge,
      );
      for (final strategy in [
        JustifiedLayoutStrategy.flex,
        JustifiedLayoutStrategy.flexFullRows,
      ]) {
        await settings.setJustifiedLayoutStrategy(strategy);
        expect(
          LocalSettings(preferences).getJustifiedLayoutStrategy(),
          strategy,
        );
      }
    },
  );

  group("justified layout tuning", () {
    test("uses defaults when tuning values are absent", () async {
      SharedPreferences.setMockInitialValues({});
      final settings = LocalSettings(await SharedPreferences.getInstance());

      final flex = settings.getFlexLayoutTuning();
      for (final field in FlexLayoutTuningField.values) {
        expect(flex.valueFor(field), FlexLayoutTuning.defaults.valueFor(field));
      }

      final flexFullRows = settings.getFlexFullRowsLayoutTuning();
      for (final field in FlexFullRowsLayoutTuningField.values) {
        expect(
          flexFullRows.valueFor(field),
          FlexFullRowsLayoutTuning.defaults.valueFor(field),
        );
      }

      final comfortLarge = settings.getComfortLargeLayoutTuning();
      for (final field in ComfortLargeLayoutTuningField.values) {
        expect(
          comfortLarge.valueFor(field),
          ComfortLargeLayoutTuning.defaults.valueFor(field),
        );
      }
    });

    test("persists arbitrary valid decimal values", () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = LocalSettings(preferences);
      const flexValues = <FlexLayoutTuningField, double>{
        FlexLayoutTuningField.targetHeightScale: 2.718281828,
        FlexLayoutTuningField.maximumHeightFactor: 9.125,
      };
      const flexFullRowsValues = <FlexFullRowsLayoutTuningField, double>{
        FlexFullRowsLayoutTuningField.targetHeightScale: 1.23456789,
        FlexFullRowsLayoutTuningField.maximumHeightFactor: 7.25,
        FlexFullRowsLayoutTuningField.minimumNonFinalSingletonAspectRatio:
            0.8125,
      };
      const comfortLargeValues = <ComfortLargeLayoutTuningField, double>{
        ComfortLargeLayoutTuningField.targetHeightScale: 0.123456789,
        ComfortLargeLayoutTuningField.maximumHeightFactor: 8.75,
        ComfortLargeLayoutTuningField.wideFinalMaximumHeightFactor: 3.14159,
        ComfortLargeLayoutTuningField.minimumLandscapeHeightFactor: 5.625,
      };

      for (final entry in flexValues.entries) {
        await settings.setFlexLayoutTuningValue(entry.key, entry.value);
      }
      for (final entry in flexFullRowsValues.entries) {
        await settings.setFlexFullRowsLayoutTuningValue(entry.key, entry.value);
      }
      for (final entry in comfortLargeValues.entries) {
        await settings.setComfortLargeLayoutTuningValue(entry.key, entry.value);
      }

      final reloadedSettings = LocalSettings(preferences);
      final flex = reloadedSettings.getFlexLayoutTuning();
      for (final entry in flexValues.entries) {
        expect(flex.valueFor(entry.key), entry.value);
      }
      final flexFullRows = reloadedSettings.getFlexFullRowsLayoutTuning();
      for (final entry in flexFullRowsValues.entries) {
        expect(flexFullRows.valueFor(entry.key), entry.value);
      }
      final comfortLarge = reloadedSettings.getComfortLargeLayoutTuning();
      for (final entry in comfortLargeValues.entries) {
        expect(comfortLarge.valueFor(entry.key), entry.value);
      }
    });

    test("falls back independently for corrupt tuning values", () async {
      SharedPreferences.setMockInitialValues({
        LocalSettings.kFlexLayoutTuningTargetHeightScale: "invalid",
        LocalSettings.kFlexLayoutTuningMaximumHeightFactor: double.nan,
        LocalSettings.kFlexFullRowsLayoutTuningTargetHeightScale: 0.0,
        LocalSettings.kFlexFullRowsLayoutTuningMaximumHeightFactor: 0.99,
        LocalSettings
                .kFlexFullRowsLayoutTuningMinimumNonFinalSingletonAspectRatio:
            "invalid",
        LocalSettings.kComfortLargeLayoutTuningTargetHeightScale: 0.0,
        LocalSettings.kComfortLargeLayoutTuningMaximumHeightFactor: 0.99,
        LocalSettings.kComfortLargeLayoutTuningWideFinalMaximumHeightFactor:
            double.infinity,
        LocalSettings.kComfortLargeLayoutTuningMinimumLandscapeHeightFactor:
            10.5,
      });
      final settings = LocalSettings(await SharedPreferences.getInstance());

      final flex = settings.getFlexLayoutTuning();
      for (final field in FlexLayoutTuningField.values) {
        expect(flex.valueFor(field), FlexLayoutTuning.defaults.valueFor(field));
      }
      final flexFullRows = settings.getFlexFullRowsLayoutTuning();
      for (final field in FlexFullRowsLayoutTuningField.values) {
        expect(
          flexFullRows.valueFor(field),
          FlexFullRowsLayoutTuning.defaults.valueFor(field),
        );
      }
      final comfortLarge = settings.getComfortLargeLayoutTuning();
      for (final field in ComfortLargeLayoutTuningField.values) {
        expect(
          comfortLarge.valueFor(field),
          ComfortLargeLayoutTuning.defaults.valueFor(field),
        );
      }
    });

    test("keeps strategy tuning isolated", () async {
      SharedPreferences.setMockInitialValues({});
      final settings = LocalSettings(await SharedPreferences.getInstance());

      await settings.setFlexLayoutTuningValue(
        FlexLayoutTuningField.targetHeightScale,
        1.91,
      );
      expect(
        settings.getComfortLargeLayoutTuning().valueFor(
          ComfortLargeLayoutTuningField.targetHeightScale,
        ),
        ComfortLargeLayoutTuning.defaults.targetHeightScale,
      );
      expect(
        settings.getFlexFullRowsLayoutTuning().targetHeightScale,
        FlexFullRowsLayoutTuning.defaults.targetHeightScale,
      );

      await settings.setFlexFullRowsLayoutTuningValue(
        FlexFullRowsLayoutTuningField.targetHeightScale,
        2.17,
      );
      expect(settings.getFlexLayoutTuning().targetHeightScale, 1.91);

      await settings.setComfortLargeLayoutTuningValue(
        ComfortLargeLayoutTuningField.targetHeightScale,
        2.73,
      );
      expect(
        settings.getFlexLayoutTuning().valueFor(
          FlexLayoutTuningField.targetHeightScale,
        ),
        1.91,
      );
      expect(settings.getFlexFullRowsLayoutTuning().targetHeightScale, 2.17);
    });

    test("resets one field without changing its siblings", () async {
      SharedPreferences.setMockInitialValues({});
      final settings = LocalSettings(await SharedPreferences.getInstance());
      await settings.setFlexLayoutTuningValue(
        FlexLayoutTuningField.targetHeightScale,
        1.91,
      );
      await settings.setFlexLayoutTuningValue(
        FlexLayoutTuningField.maximumHeightFactor,
        2.73,
      );
      await settings.setComfortLargeLayoutTuningValue(
        ComfortLargeLayoutTuningField.targetHeightScale,
        1.41,
      );
      await settings.setComfortLargeLayoutTuningValue(
        ComfortLargeLayoutTuningField.maximumHeightFactor,
        3.41,
      );
      await settings.setFlexFullRowsLayoutTuningValue(
        FlexFullRowsLayoutTuningField.targetHeightScale,
        1.71,
      );
      await settings.setFlexFullRowsLayoutTuningValue(
        FlexFullRowsLayoutTuningField.maximumHeightFactor,
        2.41,
      );

      await settings.resetFlexLayoutTuningValue(
        FlexLayoutTuningField.targetHeightScale,
      );
      await settings.resetComfortLargeLayoutTuningValue(
        ComfortLargeLayoutTuningField.targetHeightScale,
      );
      await settings.resetFlexFullRowsLayoutTuningValue(
        FlexFullRowsLayoutTuningField.targetHeightScale,
      );

      final flex = settings.getFlexLayoutTuning();
      expect(
        flex.targetHeightScale,
        FlexLayoutTuning.defaults.targetHeightScale,
      );
      expect(flex.maximumHeightFactor, 2.73);
      final comfortLarge = settings.getComfortLargeLayoutTuning();
      expect(
        comfortLarge.targetHeightScale,
        ComfortLargeLayoutTuning.defaults.targetHeightScale,
      );
      expect(comfortLarge.maximumHeightFactor, 3.41);
      final flexFullRows = settings.getFlexFullRowsLayoutTuning();
      expect(
        flexFullRows.targetHeightScale,
        FlexFullRowsLayoutTuning.defaults.targetHeightScale,
      );
      expect(flexFullRows.maximumHeightFactor, 2.41);
    });

    test("reset all removes only the selected strategy keys", () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = LocalSettings(preferences);
      for (final field in FlexLayoutTuningField.values) {
        await settings.setFlexLayoutTuningValue(
          field,
          field == FlexLayoutTuningField.maximumHeightFactor ? 2.0 : 1.5,
        );
      }
      for (final field in FlexFullRowsLayoutTuningField.values) {
        await settings.setFlexFullRowsLayoutTuningValue(
          field,
          field == FlexFullRowsLayoutTuningField.maximumHeightFactor
              ? 2.0
              : 1.5,
        );
      }
      for (final field in ComfortLargeLayoutTuningField.values) {
        await settings.setComfortLargeLayoutTuningValue(field, switch (field) {
          ComfortLargeLayoutTuningField.maximumHeightFactor ||
          ComfortLargeLayoutTuningField.wideFinalMaximumHeightFactor => 2.0,
          _ => 1.5,
        });
      }

      await settings.resetFlexLayoutTuning();

      expect(
        preferences.getKeys().where((key) => key.contains(".flex.")),
        isEmpty,
      );
      expect(
        preferences.getKeys().where((key) => key.contains(".comfort_large.")),
        isNotEmpty,
      );
      expect(
        preferences.getKeys().where((key) => key.contains(".flex_full_rows.")),
        isNotEmpty,
      );

      await settings.resetFlexFullRowsLayoutTuning();

      expect(
        preferences.getKeys().where((key) => key.contains(".flex_full_rows.")),
        isEmpty,
      );

      await settings.resetComfortLargeLayoutTuning();

      expect(
        preferences.getKeys().where((key) => key.contains(".comfort_large.")),
        isEmpty,
      );
    });

    test("rejects invalid values without persisting them", () async {
      SharedPreferences.setMockInitialValues({});
      final settings = LocalSettings(await SharedPreferences.getInstance());

      await expectLater(
        settings.setFlexLayoutTuningValue(
          FlexLayoutTuningField.targetHeightScale,
          0,
        ),
        throwsArgumentError,
      );
      await expectLater(
        settings.setComfortLargeLayoutTuningValue(
          ComfortLargeLayoutTuningField.maximumHeightFactor,
          0.999,
        ),
        throwsArgumentError,
      );
      await expectLater(
        settings.setFlexFullRowsLayoutTuningValue(
          FlexFullRowsLayoutTuningField.minimumNonFinalSingletonAspectRatio,
          0,
        ),
        throwsArgumentError,
      );

      expect(
        settings.getFlexLayoutTuning().targetHeightScale,
        FlexLayoutTuning.defaults.targetHeightScale,
      );
      expect(
        settings.getComfortLargeLayoutTuning().maximumHeightFactor,
        ComfortLargeLayoutTuning.defaults.maximumHeightFactor,
      );
      expect(
        settings
            .getFlexFullRowsLayoutTuning()
            .minimumNonFinalSingletonAspectRatio,
        FlexFullRowsLayoutTuning.defaults.minimumNonFinalSingletonAspectRatio,
      );
    });
  });
}
