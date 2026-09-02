import "package:flutter_test/flutter_test.dart";
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
}
