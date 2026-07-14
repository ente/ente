import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_image_compress/flutter_image_compress.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/module/metadata/local_file.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/tools/collage/collage_app_bar.dart";
import "package:photos/ui/tools/collage/collage_test_grid.dart";
import "package:photos/ui/tools/collage/collage_with_five_items.dart";
import "package:photos/ui/tools/collage/collage_with_four_items.dart";
import "package:photos/ui/tools/collage/collage_with_six_items.dart";
import "package:photos/ui/tools/collage/collage_with_three_items.dart";
import "package:photos/ui/tools/collage/collage_with_two_items.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:widgets_to_image/widgets_to_image.dart";

class CollageCreatorPage extends StatefulWidget {
  static const int _collageItemsMin = 2;
  static const int _collageItemsMax = 6;
  static bool isValidCount(int count) {
    return count >= _collageItemsMin && count <= _collageItemsMax;
  }

  final List<EnteFile> files;

  const CollageCreatorPage(this.files, {super.key});

  @override
  State<CollageCreatorPage> createState() => _CollageCreatorPageState();
}

class _CollageCreatorPageState extends State<CollageCreatorPage> {
  final _logger = Logger("CollageCreatorPage");
  WidgetsToImageController? _controller;
  bool _isSaving = false;
  VoidCallback? _clearSwapSelection;

  void _onControllerReady(WidgetsToImageController controller) {
    setState(() {
      _controller = controller;
    });
  }

  Future<void> _saveCollage() async {
    if (_controller == null || _isSaving) return;

    _clearSwapSelection?.call();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final bytes = await _controller!.capture();
      _logger.info('Size before compression = ${bytes!.length}');
      final compressedBytes = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 80,
      );
      _logger.info('Size after compression = ${compressedBytes.length}');
      final fileName =
          "ente_collage_" +
          DateTime.now().microsecondsSinceEpoch.toString() +
          ".jpeg";
      final newAsset = await (PhotoManager.editor
          .saveImage(
            compressedBytes,
            filename: fileName,
            relativePath: "ente Collages",
          )
          .onError((err, st) async {
            return await (PhotoManager.editor.saveImage(
              compressedBytes,
              filename: fileName,
            ));
          }));
      final newFile = fileFromAsset("ente Collages", newAsset);
      SyncService.instance.sync().ignore();
      if (!mounted) return;
      showShortToast(context, AppLocalizations.of(context).collageSaved);
      replacePage(
        context,
        DetailPage(DetailPageConfiguration([newFile], 0, "collage")),
        result: true,
      );
    } catch (e, s) {
      _logger.severe("Failed to create collage", e, s);
      if (!mounted) return;
      showShortToast(context, AppLocalizations.of(context).somethingWentWrong);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CollageAppBar(
        onSave: _saveCollage,
        isSaveEnabled: _controller != null && !_isSaving,
      ),
      body: _getBody(context),
    );
  }

  Widget _getBody(BuildContext context) {
    final count = widget.files.length;
    Widget collage;
    switch (count) {
      case 2:
        collage = CollageWithTwoItems(
          widget.files[0],
          widget.files[1],
          onControllerReady: _onControllerReady,
          onSelectionClearSetter: (fn) => _clearSwapSelection = fn,
        );
        break;
      case 3:
        collage = CollageWithThreeItems(
          widget.files[0],
          widget.files[1],
          widget.files[2],
          onControllerReady: _onControllerReady,
          onSelectionClearSetter: (fn) => _clearSwapSelection = fn,
        );
        break;
      case 4:
        collage = CollageWithFourItems(
          widget.files[0],
          widget.files[1],
          widget.files[2],
          widget.files[3],
          onControllerReady: _onControllerReady,
          onSelectionClearSetter: (fn) => _clearSwapSelection = fn,
        );
        break;
      case 5:
        collage = CollageWithFiveItems(
          widget.files[0],
          widget.files[1],
          widget.files[2],
          widget.files[3],
          widget.files[4],
          onControllerReady: _onControllerReady,
          onSelectionClearSetter: (fn) => _clearSwapSelection = fn,
        );
        break;
      case 6:
        collage = CollageWithSixItems(
          widget.files[0],
          widget.files[1],
          widget.files[2],
          widget.files[3],
          widget.files[4],
          widget.files[5],
          onControllerReady: _onControllerReady,
          onSelectionClearSetter: (fn) => _clearSwapSelection = fn,
        );
        break;
      default:
        collage = const TestGrid();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: collage,
    );
  }
}
