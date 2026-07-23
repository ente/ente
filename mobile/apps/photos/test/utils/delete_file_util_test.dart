import 'package:dio/dio.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photos/app_mode.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/generated/intl/app_localizations.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/files_split.dart';
import 'package:photos/models/selected_files.dart';
import 'package:photos/settings/local_settings.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/utils/delete_file_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        appName: 'Photos',
        packageName: 'photos',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );
  });

  setUp(() async {
    await localSettings.setAppMode(AppMode.enteGallery);
    await localSettings.setDeletePreference(null);
  });

  group('deleteFromTrash', () {
    testWidgets('uses the migrated warning delete sheet', (tester) async {
      final file = _file(generatedID: 21, uploadedID: 31);
      bool? result;

      await tester.pumpWidget(
        _TestApp(
          onOpen: (context) async {
            result = await deleteFromTrash(context, [file]);
          },
        ),
      );

      await tester.tap(find.text('Open delete sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheetComponent), findsOneWidget);
      _expectDeleteWarningIllustration();
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(
        find.text(
          'Selected items will be permanently deleted and cannot be recovered.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      _expectVisibleButtonsInOrder(tester, ['Yes, delete']);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(result, false);
    });
  });

  group('showDeleteSheet', () {
    testWidgets(
      'mixed local and remote delete sheet shows mixed component actions',
      (tester) async {
        final file = _file(generatedID: 1, uploadedID: 11, localID: 'local-1');
        final selectedFiles = SelectedFiles()..selectAll({file});

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
        );

        expect(find.byType(BottomSheetComponent), findsOneWidget);
        _expectDeleteWarningIllustration('assets/warning-red.png');
        expect(
          find.text('This item is available on your device and Ente.'),
          findsOneWidget,
        );
        expect(find.text('Delete item?'), findsOneWidget);
        expect(find.byType(RadioComponent), findsNothing);
        expect(find.byType(MenuGroupComponent), findsNothing);
        expect(find.byType(MenuComponent), findsNothing);

        expect(find.byType(ButtonComponent), findsNWidgets(3));
        final buttons = tester.widgetList<ButtonComponent>(
          find.byType(ButtonComponent),
        );
        expect(buttons.map((button) => button.variant), [
          ButtonComponentVariant.secondary,
          ButtonComponentVariant.secondary,
          ButtonComponentVariant.critical,
        ]);
        expect(find.text('Set as my default choice'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(LabeledControlComponent),
            matching: find.byType(Center),
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        _expectVisibleButtonsInOrder(tester, [
          'Delete from device',
          'Delete from Ente',
          'Delete from both',
        ]);
      },
    );

    testWidgets('mixed delete sheet with saved default starts collapsed', (
      tester,
    ) async {
      await localSettings.setDeletePreference(DeletePreference.DeleteFromBoth);
      final file = _file(generatedID: 22, uploadedID: 32, localID: 'local-22');
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: [file],
          ownedByOtherUsers: const [],
        ),
      );

      expect(find.byType(ButtonComponent), findsOneWidget);
      expect(find.text('Delete from both'), findsOneWidget);
      expect(find.text('More options'), findsOneWidget);
      expect(find.text('Set as my default choice'), findsNothing);
    });

    testWidgets('plural delete sheet copy matches deletion context', (
      tester,
    ) async {
      final mixedFiles = [
        _file(generatedID: 17, uploadedID: 27, localID: 'local-17'),
        _file(generatedID: 18, uploadedID: 28, localID: 'local-18'),
      ];
      final mixedSelection = SelectedFiles()..selectAll(mixedFiles.toSet());
      await _pumpDeleteSheet(
        tester,
        selectedFiles: mixedSelection,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: mixedFiles,
          ownedByOtherUsers: const [],
        ),
      );
      expect(find.text('Delete 2 items?'), findsOneWidget);
      expect(
        find.text('These items are available on device and Ente.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      final remoteFiles = [
        _file(generatedID: 19, uploadedID: 29),
        _file(generatedID: 20, uploadedID: 30),
      ];
      final remoteSelection = SelectedFiles()..selectAll(remoteFiles.toSet());
      await _pumpDeleteSheet(
        tester,
        selectedFiles: remoteSelection,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: remoteFiles,
          ownedByOtherUsers: const [],
        ),
      );
      expect(find.text('Delete 2 items?'), findsOneWidget);
      expect(
        find.text(
          'These items will be deleted from all albums. '
          'You can recover them from Trash.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'mixed delete from Ente choice uses the remote delete path and clears selection',
      (tester) async {
        final file = _file(
          generatedID: 14,
          uploadedID: 24,
          localID: 'local-14',
        );
        final selectedFiles = SelectedFiles()..selectAll({file});
        var remoteDeleteCalls = 0;
        List<EnteFile>? remoteDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteFromRemoteOnlyOverride: (context, files) async {
            remoteDeleteCalls++;
            remoteDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from Ente'));
        await tester.pumpAndSettle();

        expect(remoteDeleteCalls, 1);
        expect(remoteDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);

        await _settleToast(tester);
      },
    );

    testWidgets('mixed delete sheet close keeps selection', (tester) async {
      final file = _file(generatedID: 16, uploadedID: 26, localID: 'local-16');
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: [file],
          ownedByOtherUsers: const [],
        ),
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheetComponent), findsNothing);
      expect(selectedFiles.files, contains(file));
    });

    testWidgets(
      'mixed delete from device choice uses the device delete path and clears selection',
      (tester) async {
        final file = _file(
          generatedID: 15,
          uploadedID: 25,
          localID: 'local-15',
        );
        final selectedFiles = SelectedFiles()..selectAll({file});
        var deviceDeleteCalls = 0;
        List<EnteFile>? deviceDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteOnDeviceOnlyOverride: (context, files) async {
            deviceDeleteCalls++;
            deviceDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from device'));
        await tester.pumpAndSettle();

        expect(deviceDeleteCalls, 1);
        expect(deviceDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);
      },
    );

    testWidgets('remote-only delete sheet uses title and critical action', (
      tester,
    ) async {
      final file = _file(generatedID: 2, uploadedID: 12);
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: [file],
          ownedByOtherUsers: const [],
        ),
      );

      expect(
        find.text(
          'This item will be deleted from all albums. '
          'You can recover it from Trash.',
        ),
        findsOneWidget,
      );
      _expectDeleteWarningIllustration('assets/warning-red.png');
      expect(find.text('Delete item?'), findsOneWidget);
      expect(find.text('They will be deleted from all albums.'), findsNothing);
      expect(find.byType(ButtonComponent), findsOneWidget);
      final deleteButton = tester.widget<ButtonComponent>(
        find.byType(ButtonComponent),
      );
      expect(deleteButton.variant, ButtonComponentVariant.critical);
      expect(find.text('Delete from device'), findsNothing);
      expect(find.text('Delete from both'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      _expectVisibleButtonsInOrder(tester, ['Delete from Ente']);
    });

    testWidgets('local-only delete sheet uses title and critical action', (
      tester,
    ) async {
      final file = _file(generatedID: 3, localID: 'local-3');
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: [file],
          ownedByCurrentUser: const [],
          ownedByOtherUsers: const [],
        ),
      );

      expect(
        find.text('Item not backed up. Permanently delete from device?'),
        findsOneWidget,
      );
      _expectDeleteWarningIllustration('assets/warning-red.png');
      expect(find.text('Delete item?'), findsOneWidget);
      expect(find.text('They will be deleted from all albums.'), findsNothing);
      expect(find.byType(ButtonComponent), findsOneWidget);
      final deleteButton = tester.widget<ButtonComponent>(
        find.byType(ButtonComponent),
      );
      expect(deleteButton.variant, ButtonComponentVariant.critical);
      expect(find.text('Delete from Ente'), findsNothing);
      expect(find.text('Delete from both'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      _expectVisibleButtonsInOrder(tester, ['Delete from device']);
    });

    testWidgets('cancel keeps the selection', (tester) async {
      final file = _file(generatedID: 4, uploadedID: 14);
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: [file],
          ownedByOtherUsers: const [],
        ),
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheetComponent), findsNothing);
      expect(selectedFiles.files, contains(file));
    });

    testWidgets(
      'remote delete action uses the legacy remote delete path and clears selection',
      (tester) async {
        final file = _file(generatedID: 7, uploadedID: 17);
        final selectedFiles = SelectedFiles()..selectAll({file});
        var remoteDeleteCalls = 0;
        List<EnteFile>? remoteDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteFromRemoteOnlyOverride: (context, files) async {
            remoteDeleteCalls++;
            remoteDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from Ente'));
        await tester.pumpAndSettle();

        expect(remoteDeleteCalls, 1);
        expect(remoteDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);

        await _settleToast(tester);
      },
    );

    testWidgets(
      'device delete action uses the legacy device delete path and clears selection',
      (tester) async {
        final file = _file(generatedID: 8, localID: 'local-8');
        final selectedFiles = SelectedFiles()..selectAll({file});
        var deviceDeleteCalls = 0;
        List<EnteFile>? deviceDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: [file],
            ownedByCurrentUser: const [],
            ownedByOtherUsers: const [],
          ),
          deleteOnDeviceOnlyOverride: (context, files) async {
            deviceDeleteCalls++;
            deviceDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from device'));
        await tester.pumpAndSettle();

        expect(deviceDeleteCalls, 1);
        expect(deviceDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);
      },
    );

    testWidgets(
      'delete from both uses the legacy everywhere delete path and clears selection',
      (tester) async {
        final file = _file(generatedID: 9, uploadedID: 19, localID: 'local-9');
        final selectedFiles = SelectedFiles()..selectAll({file});
        var everywhereDeleteCalls = 0;
        List<EnteFile>? everywhereDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteFromEverywhereOverride: (context, files) async {
            everywhereDeleteCalls++;
            everywhereDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from both'));
        await tester.pumpAndSettle();

        expect(everywhereDeleteCalls, 1);
        expect(everywhereDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);
      },
    );

    testWidgets('barrier dismissal keeps the selection', (tester) async {
      final file = _file(generatedID: 5, uploadedID: 15);
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: [file],
          ownedByOtherUsers: const [],
        ),
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheetComponent), findsNothing);
      expect(selectedFiles.files, contains(file));
    });

    testWidgets('only other-user files keep the legacy no-sheet behavior', (
      tester,
    ) async {
      final file = _file(generatedID: 6, uploadedID: 16, ownerID: 2);
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: const [],
          ownedByOtherUsers: [file],
        ),
      );

      expect(find.byType(BottomSheetComponent), findsNothing);
      expect(selectedFiles.files, contains(file));

      await _settleToast(tester);
    });

    testWidgets(
      'local gallery mode deletes device files without showing a confirmation sheet',
      (tester) async {
        await localSettings.setAppMode(AppMode.localGallery);
        final file = _file(generatedID: 10, localID: 'local-10');
        final selectedFiles = SelectedFiles()..selectAll({file});
        var deviceDeleteCalls = 0;
        List<EnteFile>? deviceDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: [file],
            ownedByCurrentUser: const [],
            ownedByOtherUsers: const [],
          ),
          deleteOnDeviceOnlyOverride: (context, files) async {
            deviceDeleteCalls++;
            deviceDeleteFiles = List.of(files);
          },
        );

        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(deviceDeleteCalls, 1);
        expect(deviceDeleteFiles, [file]);
        expect(selectedFiles.files, isEmpty);
      },
    );

    testWidgets(
      'local gallery mode with no device files keeps the legacy no-sheet behavior',
      (tester) async {
        await localSettings.setAppMode(AppMode.localGallery);
        final file = _file(generatedID: 11, uploadedID: 21);
        final selectedFiles = SelectedFiles()..selectAll({file});
        var deviceDeleteCalls = 0;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteOnDeviceOnlyOverride: (context, files) async {
            deviceDeleteCalls++;
          },
        );

        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(deviceDeleteCalls, 0);
        expect(selectedFiles.files, contains(file));

        await _settleToast(tester);
      },
    );

    testWidgets('mismatched selection and split counts still assert', (
      tester,
    ) async {
      final selectedFile = _file(generatedID: 12, uploadedID: 22);
      final splitFile = _file(generatedID: 13, uploadedID: 23);
      final selectedFiles = SelectedFiles()..selectAll({selectedFile});
      late BuildContext context;

      await tester.pumpWidget(
        MaterialApp(
          theme: darkThemeData,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await expectLater(
        showDeleteSheet(
          context,
          selectedFiles,
          FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [selectedFile, splitFile],
            ownedByOtherUsers: const [],
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

Future<void> _pumpDeleteSheet(
  WidgetTester tester, {
  required SelectedFiles selectedFiles,
  required FilesSplit split,
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteFromRemoteOnlyOverride,
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteOnDeviceOnlyOverride,
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteFromEverywhereOverride,
}) async {
  await tester.pumpWidget(
    _TestApp(
      onOpen: (context) async {
        await showDeleteSheet(
          context,
          selectedFiles,
          split,
          deleteFromRemoteOnlyOverride: deleteFromRemoteOnlyOverride,
          deleteOnDeviceOnlyOverride: deleteOnDeviceOnlyOverride,
          deleteFromEverywhereOverride: deleteFromEverywhereOverride,
        );
      },
    ),
  );

  await tester.tap(find.text('Open delete sheet'));
  await tester.pumpAndSettle();
}

EnteFile _file({
  required int generatedID,
  int? uploadedID,
  int ownerID = 1,
  String? localID,
  FileType fileType = FileType.image,
}) {
  return EnteFile()
    ..generatedID = generatedID
    ..uploadedFileID = uploadedID
    ..ownerID = ownerID
    ..collectionID = uploadedID == null ? null : 100
    ..localID = localID
    ..fileType = fileType;
}

Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void _expectVisibleButtonsInOrder(WidgetTester tester, List<String> labels) {
  for (final label in labels) {
    expect(find.text(label), findsOneWidget);
  }

  for (var i = 0; i < labels.length - 1; i++) {
    final firstTop = tester.getTopLeft(find.text(labels[i])).dy;
    final secondTop = tester.getTopLeft(find.text(labels[i + 1])).dy;
    expect(
      firstTop,
      lessThan(secondTop),
      reason: '${labels[i]} should appear above ${labels[i + 1]}',
    );
  }
}

void _expectDeleteWarningIllustration([
  String assetName = 'assets/warning-grey.png',
]) {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == assetName,
    ),
    findsOneWidget,
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.onOpen});

  final Future<void> Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: EasyLoading.init(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                await onOpen(context);
              },
              child: const Text('Open delete sheet'),
            );
          },
        ),
      ),
    );
  }
}
