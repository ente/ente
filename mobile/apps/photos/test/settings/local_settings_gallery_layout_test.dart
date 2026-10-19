import "package:flutter_test/flutter_test.dart";
import "package:photos/core/configuration.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("gallery layout defaults to grid", () async {
    SharedPreferences.setMockInitialValues({});
    final settings = LocalSettings(await SharedPreferences.getInstance());

    expect(settings.getGalleryLayoutType(), GalleryLayoutType.grid);
    expect(settings.getPhotoGridSize(), 3);
  });

  test(
    "migrates the two-column preference without changing other settings",
    () async {
      for (final count in [2, 3, 4, 5, 6]) {
        SharedPreferences.setMockInitialValues({
          LocalSettings.kPhotoGridSize: count,
          LocalSettings.kGalleryGroupType: GroupType.month.toString(),
          "album_sort_order": "oldest_first",
          "hide_shared_items_from_home_gallery": true,
        });
        final preferences = await SharedPreferences.getInstance();
        final settings = LocalSettings(preferences);
        await settings.migrateGalleryLayoutPreferences();
        expect(
          settings.getGalleryLayoutType(),
          count == 2 ? GalleryLayoutType.justified : GalleryLayoutType.grid,
        );
        expect(settings.getPhotoGridSize(), count == 2 ? 3 : count);
        expect(
          preferences.containsKey(LocalSettings.kPhotoGridSize),
          count != 2,
        );
        expect(settings.getGalleryGroupType(), GroupType.month);
        expect(preferences.getString("album_sort_order"), "oldest_first");
        expect(
          preferences.getBool("hide_shared_items_from_home_gallery"),
          isTrue,
        );
        await settings.setGalleryLayoutType(GalleryLayoutType.grid);
        await settings.migrateGalleryLayoutPreferences();
        expect(settings.getGalleryLayoutType(), GalleryLayoutType.grid);
        expect(settings.getPhotoGridSize(), count == 2 ? 3 : count);
      }
    },
  );

  test(
    "retains the old implicit default while new installs keep three",
    () async {
      SharedPreferences.setMockInitialValues({Configuration.userIDKey: 1});
      var preferences = await SharedPreferences.getInstance();
      var settings = LocalSettings(preferences);
      await settings.migrateGalleryLayoutPreferences();
      expect(settings.getPhotoGridSize(), 4);

      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      settings = LocalSettings(preferences);
      await settings.migrateGalleryLayoutPreferences();
      await preferences.setInt(Configuration.userIDKey, 1);
      await settings.migrateGalleryLayoutPreferences();
      expect(settings.getPhotoGridSize(), 3);
    },
  );

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
}
