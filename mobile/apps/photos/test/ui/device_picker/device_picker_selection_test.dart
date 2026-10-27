import 'package:flutter_test/flutter_test.dart';
import 'package:photos/models/file/dummy_file.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/ui/device_picker/device_picker_selection.dart';
import 'package:photos/ui/viewer/gallery/swipe_to_select_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local assets toggle by identity without database IDs', () {
    final selection = DevicePickerSelectedFiles();
    addTearDown(selection.dispose);
    selection.toggleSelection(EnteFile()..localID = 'photo');
    expect(selection.isFileSelected(EnteFile()..localID = 'photo'), isTrue);
    expect(selection.isFileSelected(EnteFile()..localID = 'other'), isFalse);
    selection.toggleSelection(EnteFile()..localID = 'photo');
    expect(selection.files, isEmpty);
    final group = {EnteFile()..localID = 'a', EnteFile()..localID = 'b'};
    selection.toggleGroupSelection(group);
    expect(selection.files, group);
    selection.toggleGroupSelection(group);
    expect(selection.files, isEmpty);
  });

  test('shared swipe selection respects the cap and can deselect', () {
    final selection = DevicePickerSelectedFiles();
    final files = List.generate(70, (i) => EnteFile()..localID = '$i');
    final swipe = SwipeToSelectHelper(
      allFiles: files,
      selectedFiles: selection,
    );
    addTearDown(() {
      swipe.dispose();
      selection.dispose();
    });
    swipe.startSelection(files.first);
    swipe.updateSelection(files.last);
    expect(selection.files.length, 50);
    swipe.updateSelection(files[24]);
    expect(selection.files.length, 25);
    swipe.endSelection();
    swipe.startSelection(files.first);
    swipe.updateSelection(files[24]);
    swipe.endSelection();
    expect(selection.files, isEmpty);
    selection.selectAll({DummyFile(groupID: 'day', index: 0), ...files});
    expect(selection.files.length, 50);
    expect(selection.files.any((file) => file is DummyFile), isFalse);
  });

  test('uploaded files stay selected when their local ID is cleared', () {
    final selection = DevicePickerSelectedFiles();
    addTearDown(selection.dispose);
    final file = EnteFile()
      ..generatedID = 1
      ..uploadedFileID = 10
      ..localID = 'photo';
    selection.register(file, 'photo');
    selection.toggleSelection(file);
    file.localID = null;
    expect(selection.isFileSelected(file), isTrue);
    selection.toggleSelection(file);
    expect(selection.files, isEmpty);
    selection.toggleSelection(file);
    expect(selection.files.single, same(file));
    final refreshed = EnteFile()
      ..generatedID = 2
      ..localID = 'photo';
    selection.register(refreshed, 'photo');
    expect(selection.isFileSelected(refreshed), isTrue);
    selection.toggleGroupSelection({refreshed});
    expect(selection.files, isEmpty);
  });

  test('selection stays locked until confirmation finishes', () {
    final selection = DevicePickerSelectedFiles();
    addTearDown(selection.dispose);
    final file = EnteFile()..localID = 'photo';
    selection.toggleSelection(file);
    selection.locked = true;
    selection.toggleSelection(file);
    selection.selectAll({EnteFile()..localID = 'other'});
    selection.unSelectAll({file});
    selection.clearAll();
    expect(selection.files, {file});
    selection.locked = false;
    selection.clearAll();
    expect(selection.files, isEmpty);
  });
}
