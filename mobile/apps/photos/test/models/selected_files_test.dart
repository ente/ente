import 'package:flutter_test/flutter_test.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/selected_files.dart';

void main() {
  for (final isLocal in [false, true]) {
    test('${isLocal ? 'Local' : 'Album'} aliases share selection identity', () {
      final selection = SelectedFiles(dedupeByUploadID: true);
      addTearDown(selection.dispose);
      final first = EnteFile()
        ..generatedID = 1
        ..localID = 'photo'
        ..uploadedFileID = isLocal ? null : 10;
      final alias = EnteFile()
        ..generatedID = 2
        ..localID = isLocal ? 'photo' : 'other'
        ..uploadedFileID = 10;

      selection.selectAll({first, alias});
      expect(selection.files, {first});
      expect(selection.isFileSelected(alias), isTrue);
      selection.selectAll({alias});
      selection.retainFiles({alias});
      expect(selection.files, {first});
      selection.toggleSelection(alias);
      expect(selection.files, isEmpty);
      selection.replaceSelection({first, alias});
      expect(selection.files, {first});
      selection.toggleGroupSelection({alias});
      expect(selection.files, isEmpty);
      selection.selectAll({first});
      selection.unSelectAll({alias});
      expect(selection.files, isEmpty);
    });
  }

  test('default selection keeps separate database rows', () {
    final selection = SelectedFiles();
    addTearDown(selection.dispose);
    final first = EnteFile()
      ..generatedID = 1
      ..uploadedFileID = 10;
    final other = EnteFile()
      ..generatedID = 2
      ..uploadedFileID = 10;

    selection.toggleSelection(first);
    selection.toggleSelection(other);
    expect(selection.files, {first, other});
  });

  test(
    'upload IDs take precedence while local and generated aliases match',
    () {
      final selection = SelectedFiles(dedupeByUploadID: true);
      addTearDown(selection.dispose);
      final first = EnteFile()
        ..generatedID = 1
        ..localID = 'photo'
        ..uploadedFileID = 10;
      final second = EnteFile()
        ..generatedID = 1
        ..localID = 'photo'
        ..uploadedFileID = 20;
      final localAlias = EnteFile()..localID = 'photo';
      final generatedAlias = EnteFile()..generatedID = 1;
      final differentUpload = EnteFile()
        ..generatedID = 1
        ..localID = 'photo'
        ..uploadedFileID = 30;

      selection.selectAll({first, second});
      expect(selection.files.toList(), [first, second]);
      expect(selection.isFileSelected(localAlias), isTrue);
      expect(selection.isFileSelected(generatedAlias), isTrue);
      expect(selection.isFileSelected(differentUpload), isFalse);
      selection.toggleSelection(localAlias);
      expect(selection.files, {second});
      expect(selection.isFileSelected(localAlias), isTrue);
      selection.unSelectAll({first});
      expect(selection.files, {second});
      selection.retainFiles({first});
      expect(selection.files, isEmpty);

      selection.selectAll({localAlias});
      expect(selection.isFileSelected(differentUpload), isTrue);
    },
  );

  test('public set edits and identity mutations keep membership current', () {
    final selection = SelectedFiles(dedupeByUploadID: true);
    addTearDown(selection.dispose);
    final first = EnteFile()
      ..generatedID = 1
      ..localID = 'photo'
      ..uploadedFileID = 10;
    final second = EnteFile()
      ..generatedID = 2
      ..uploadedFileID = 10;
    final alias = EnteFile()..uploadedFileID = 10;

    selection.files.addAll({first, second});
    selection.files.remove(first);
    expect(selection.isFileSelected(alias), isTrue);
    selection.files.retainAll({first});
    expect(selection.isFileSelected(alias), isFalse);
    selection.files.add(first);
    selection.mutateFile(first, () {
      first.uploadedFileID = 20;
      first.localID = null;
    });
    expect(selection.isFileSelected(alias), isFalse);
    expect(selection.isFileSelected(EnteFile()..localID = 'photo'), isFalse);
    expect(selection.isFileSelected(EnteFile()..uploadedFileID = 20), isTrue);
    expect(selection.files.first, first);
    expect(selection.files.last, first);
    selection.files.removeWhere((file) => file.uploadedFileID == 20);
    expect(selection.isFileSelected(first), isFalse);
    selection.files.add(first);
    selection.files.clear();
    expect(selection.isFileSelected(first), isFalse);
  });
}
