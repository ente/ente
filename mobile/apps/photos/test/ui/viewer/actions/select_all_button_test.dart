import "dart:collection";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

void main() {
  testWidgets("select-all status updates do not traverse file collections", (
    tester,
  ) async {
    final files = List.generate(
      10000,
      (index) => EnteFile()..generatedID = index,
    );
    final galleryFiles = _CountingFiles(files);
    final selectedFiles = _CountingSelectedFiles();
    selectedFiles.selectAll(files.toSet());

    void resetReads() {
      galleryFiles.reads = 0;
      selectedFiles.files.reads = 0;
    }

    void expectStatusWithoutTraversal(bool isSelected) {
      expect(
        tester
            .widget<SelectAllStatusIcon>(find.byType(SelectAllStatusIcon))
            .isSelected,
        isSelected,
      );
      expect(
        galleryFiles.reads,
        0,
        reason: "Status must only read file counts",
      );
      expect(
        selectedFiles.files.reads,
        0,
        reason: "Status must not traverse or copy the selection",
      );
    }

    final galleryState = GalleryFilesState(
      child: const Align(
        alignment: Alignment.topLeft,
        child: SelectAllButton(),
      ),
    )..setGalleryFiles = galleryFiles;

    resetReads();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: SelectionState(selectedFiles: selectedFiles, child: galleryState),
      ),
    );
    expectStatusWithoutTraversal(true);

    selectedFiles.unSelectAll({files.last});
    resetReads();
    await tester.pump();
    expectStatusWithoutTraversal(false);

    await tester.tap(find.byType(SelectAllButton));
    expect(selectedFiles.files.length, files.length);
    resetReads();
    await tester.pump();
    expectStatusWithoutTraversal(true);

    await tester.pumpWidget(const SizedBox.shrink());
    selectedFiles.dispose();
  });
}

class _CountingFiles extends ListBase<EnteFile> {
  _CountingFiles(this._files);

  final List<EnteFile> _files;
  int reads = 0;

  @override
  int get length => _files.length;

  @override
  set length(int value) => throw UnsupportedError("Read-only test list");

  @override
  EnteFile operator [](int index) {
    reads++;
    return _files[index];
  }

  @override
  void operator []=(int index, EnteFile value) {
    throw UnsupportedError("Read-only test list");
  }
}

class _CountingSelectedFiles extends SelectedFiles {
  final _files = _CountingSelection();

  @override
  _CountingSelection get files => _files;
}

class _CountingSelection extends SetBase<EnteFile> {
  final _files = <EnteFile>{};
  int reads = 0;

  @override
  int get length => _files.length;

  @override
  Iterator<EnteFile> get iterator {
    reads++;
    return _files.iterator;
  }

  @override
  bool contains(Object? element) {
    reads++;
    return _files.contains(element);
  }

  @override
  EnteFile? lookup(Object? element) {
    reads++;
    return _files.lookup(element);
  }

  @override
  Set<EnteFile> toSet() {
    reads++;
    return _files.toSet();
  }

  @override
  bool add(EnteFile value) => _files.add(value);

  @override
  bool remove(Object? value) => _files.remove(value);

  @override
  void clear() => _files.clear();
}
