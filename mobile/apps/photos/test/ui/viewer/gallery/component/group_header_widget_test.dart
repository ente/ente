import "dart:collection";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";

void main() {
  testWidgets("unselected date headers do not traverse their file groups", (
    tester,
  ) async {
    final selectedFiles = SelectedFiles();
    final files = _CountingFiles(
      List.generate(1000, (index) => EnteFile()..generatedID = index),
    );
    await tester.pumpWidget(_header(files, selectedFiles, "First date"));
    expect(files.reads, 0);

    await tester.pumpWidget(_header(files, selectedFiles, "Next date"));
    expect(files.reads, 0);

    selectedFiles.selectAll({files.first});
    await tester.pump();
    expect(files.reads, greaterThan(0));
    files.reads = 0;
    selectedFiles.clearAll(fireEvent: false);
    await tester.pump();
    expect(files.reads, 0);
    expect(_isSelected(tester), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    selectedFiles.dispose();
  });

  testWidgets("group selection still ignores dummy cells", (tester) async {
    final selectedFiles = SelectedFiles();
    final first = EnteFile()..generatedID = 1;
    final second = EnteFile()..generatedID = 2;
    await tester.pumpWidget(
      _header(
        [first, second, DummyFile(groupID: "date", index: 0)],
        selectedFiles,
        "Date",
      ),
    );
    expect(_isSelected(tester), isFalse);
    selectedFiles.selectAll({first});
    await tester.pump();
    expect(_isSelected(tester), isFalse);
    selectedFiles.selectAll({second});
    await tester.pump();
    expect(_isSelected(tester), isTrue);
    selectedFiles.clearAll(fireEvent: false);
    await tester.pump();
    expect(_isSelected(tester), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    selectedFiles.dispose();
  });
}

bool _isSelected(WidgetTester tester) {
  return tester
      .widget<SelectAllStatusIcon>(find.byType(SelectAllStatusIcon))
      .isSelected;
}

Widget _header(
  List<EnteFile> files,
  SelectedFiles selectedFiles,
  String title,
) {
  return MaterialApp(
    theme: lightThemeData,
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    home: Align(
      alignment: Alignment.topLeft,
      child: GroupHeaderWidget(
        title: title,
        gridSize: 4,
        filesInGroup: files,
        selectedFiles: selectedFiles,
        showSelectAll: true,
      ),
    ),
  );
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
