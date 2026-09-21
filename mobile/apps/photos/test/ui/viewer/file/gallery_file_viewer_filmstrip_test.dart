import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/file/file_icons_widget.dart";
import "package:photos/ui/viewer/file/gallery_file_viewer_filmstrip.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      prefs,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
  });

  testWidgets("does not show trash expiry on unloaded filmstrip thumbnails", (
    tester,
  ) async {
    final files = [_trashFile(1), _trashFile(2)];
    final fullScreenNotifier = ValueNotifier(false);
    addTearDown(fullScreenNotifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: darkThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              GalleryFileViewerFilmstripOverlay(
                files: files,
                selectedIndex: 0,
                bottomControlsHeight: 0,
                findChildIndexCallback: (key) =>
                    files.indexWhere((file) => key == ObjectKey(file)),
                enableFullScreenNotifier: fullScreenNotifier,
                onEvent: (_) {},
                layout: GalleryFileViewerFilmstripLayout.compact,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ThumbnailPlaceHolder), findsNWidgets(2));
    expect(find.byType(TrashedFileOverlayText), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
  });
}

EnteTrashFile _trashFile(int id) {
  final file = EnteFile()
    ..generatedID = id
    ..uploadedFileID = id
    ..ownerID = 1
    ..collectionID = 1
    ..fileType = FileType.image;
  return EnteTrashFile.from(
    file,
    deleteBy: DateTime.now()
        .add(const Duration(days: 7))
        .microsecondsSinceEpoch,
    createdAt: 0,
    updateAt: 0,
  );
}
