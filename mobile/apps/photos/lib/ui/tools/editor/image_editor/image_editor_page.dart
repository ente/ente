import "dart:async";
import "dart:io";
import "dart:math";
import 'dart:ui' as ui show Image, ImageByteFormat;

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:flutter_image_compress/flutter_image_compress.dart";
import "package:hugeicons/hugeicons.dart";
import 'package:image/image.dart' as img;
import "package:logging/logging.dart";
import 'package:path/path.dart' as path;
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart' as ente;
import "package:photos/models/location/location.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_app_bar.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_crop_rotate.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_filter_bar.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_main_bottom_bar.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_paint_bar.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_text_bar.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_tune_bar.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/image_util.dart";
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditorPage extends StatefulWidget {
  final ente.EnteFile originalFile;
  final File file;
  final DetailPageConfiguration detailPageConfig;

  const ImageEditorPage({
    super.key,
    required this.file,
    required this.originalFile,
    required this.detailPageConfig,
  });

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  final _mainEditorBarKey = GlobalKey<ImageEditorMainBottomBarState>();
  final editorKey = GlobalKey<ProImageEditorState>();
  final _logger = Logger("ImageEditor");

  Future<void> saveImage(Uint8List? bytes) async {
    if (bytes == null) return;

    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).saving,
    );
    await dialog.show();

    debugPrint("Image saved with size: ${bytes.length} bytes");
    final DateTime start = DateTime.now();
    bool hasStoppedChangeNotify = false;

    try {
      final ui.Image decodedResult = await decodeImageFromList(bytes);
      var result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: decodedResult.width,
        minHeight: decodedResult.height,
        quality: 95,
        format: CompressFormat.jpeg,
      );
      if (flagService.internalUser) {
        try {
          final image = img.decodePng(bytes);
          if (image != null) {
            await copyEXIF(
              widget.originalFile,
              image,
              copyRenderingFields: false,
            );
            result = img.encodeJpg(image, quality: 95);
          }
        } catch (e, s) {
          _logger.warning("Image Editor: copyEXIF failed", e, s);
        }
      }
      _logger.info('Size after compression = ${result.length}');
      final Duration diff = DateTime.now().difference(start);
      _logger.info('image_editor time : $diff');

      final fileName =
          path.basenameWithoutExtension(widget.originalFile.title!) +
          "_edited_" +
          DateTime.now().microsecondsSinceEpoch.toString() +
          ".JPEG";
      //Disabling notifications for assets changing to insert the file into
      //files db before triggering a sync.
      await PhotoManager.stopChangeNotify();
      hasStoppedChangeNotify = true;
      final AssetEntity newAsset = await (PhotoManager.editor.saveImage(
        result,
        filename: fileName,
      ));
      final newFile = await ente.EnteFile.fromAsset(
        widget.originalFile.deviceFolder ?? '',
        newAsset,
      );

      newFile.creationTime = widget.originalFile.creationTime;
      newFile.collectionID = widget.originalFile.collectionID;
      newFile.location = widget.originalFile.location;
      if (!newFile.hasLocation && widget.originalFile.localID != null) {
        final assetEntity = await widget.originalFile.getAsset;
        if (assetEntity != null) {
          final latLong = await assetEntity.latlngAsync();
          newFile.location = Location(
            latitude: latLong.latitude,
            longitude: latLong.longitude,
          );
        }
      }
      newFile.generatedID = await FilesDB.instance.insertAndGetId(newFile);
      Bus.instance.fire(LocalPhotosUpdatedEvent([newFile], source: "editSave"));
      unawaited(SyncService.instance.sync());
      showShortToast(context, AppLocalizations.of(context).editsSaved);
      _logger.info("Original file " + widget.originalFile.toString());
      _logger.info("Saved edits to file " + newFile.toString());
      final files = widget.detailPageConfig.files;

      // the index could be -1 if the files fetched doesn't contain the newly
      // edited files
      int selectionIndex = files.indexWhere(
        (file) => file.generatedID == newFile.generatedID,
      );
      if (selectionIndex == -1) {
        files.add(newFile);
        selectionIndex = files.length - 1;
      }
      await dialog.hide();
      replacePage(
        context,
        DetailPage(
          widget.detailPageConfig.copyWith(
            files: files,
            selectedIndex: min(selectionIndex, files.length - 1),
          ),
        ),
      );
    } catch (e, s) {
      await dialog.hide();
      showToast(context, AppLocalizations.of(context).oopsCouldNotSaveEdits);
      _logger.severe("Failed to save image edits", e, s);
    } finally {
      if (hasStoppedChangeNotify) {
        await PhotoManager.startChangeNotify();
      }
    }
  }

  Future<void> _showExitConfirmationDialog(BuildContext context) async {
    final actionResult = await showActionSheet(
      context: context,
      title: AppLocalizations.of(context).discardEditsQuestion,
      buttons: [
        ButtonWidget(
          labelText: AppLocalizations.of(context).yesDiscardChanges,
          buttonType: ButtonType.critical,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          isInAlert: true,
        ),
        ButtonWidget(
          labelText: AppLocalizations.of(context).no,
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          buttonAction: ButtonAction.second,
          shouldStickToDarkTheme: true,
          isInAlert: true,
        ),
      ],
      body: AppLocalizations.of(context).doYouWantToDiscardTheEditsYouHaveMade,
      actionSheetType: ActionSheetType.defaultActionSheet,
    );
    if (actionResult?.action != null &&
        actionResult!.action == ButtonAction.first) {
      replacePage(context, DetailPage(widget.detailPageConfig));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final colors = context.componentColors;
    final actionTextStyle = TextStyles.large.copyWith(color: colors.textBase);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        editorKey.currentState?.isPopScopeDisabled = true;
        _showExitConfirmationDialog(context);
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        backgroundColor: colors.backgroundBase,
        body: ProImageEditor.file(
          key: editorKey,
          widget.file,
          callbacks: ProImageEditorCallbacks(
            onCloseEditor: (_) {
              editorKey.currentState?.isPopScopeDisabled = true;
              _showExitConfirmationDialog(context);
            },
            mainEditorCallbacks: MainEditorCallbacks(
              onStartCloseSubEditor: (value) {
                _mainEditorBarKey.currentState?.setState(() {});
              },
              onPopInvoked: (didPop, result) {
                editorKey.currentState?.isPopScopeDisabled = false;
              },
            ),
          ),
          configs: ProImageEditorConfigs(
            imageGeneration: const ImageGenerationConfigs(
              jpegQuality: 100,
              enableIsolateGeneration: true,
              captureImageByteFormat: ui.ImageByteFormat.rawStraightRgba,
              outputFormat: OutputFormat.png,
              pngLevel: 0,
            ),
            layerInteraction: const LayerInteractionConfigs(
              hideToolbarOnInteraction: false,
            ),
            theme: ThemeData(
              scaffoldBackgroundColor: colors.backgroundBase,
              appBarTheme: AppBarTheme(
                titleTextStyle: actionTextStyle,
                backgroundColor: colors.backgroundBase,
              ),
              bottomAppBarTheme: BottomAppBarThemeData(
                color: colors.backgroundBase,
              ),
              brightness: isLightMode ? Brightness.light : Brightness.dark,
            ),
            mainEditor: MainEditorConfigs(
              enableZoom: true,
              tools: const [
                SubEditorMode.cropRotate,
                SubEditorMode.filter,
                SubEditorMode.tune,
                SubEditorMode.paint,
                SubEditorMode.emoji,
              ],
              style: MainEditorStyle(
                uiOverlayStyle: SystemUiOverlayStyle(
                  systemNavigationBarContrastEnforced: true,
                  systemNavigationBarColor: Colors.transparent,
                  statusBarBrightness: isLightMode
                      ? Brightness.dark
                      : Brightness.light,
                  statusBarIconBrightness: isLightMode
                      ? Brightness.dark
                      : Brightness.light,
                ),
                appBarBackground: colors.backgroundBase,
                background: colors.backgroundBase,
                bottomBarBackground: colors.backgroundBase,
              ),
              widgets: MainEditorWidgets(
                removeLayerArea:
                    (removeAreaKey, _, rebuildStream, isLayerBeingTransformed) {
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: StreamBuilder(
                          stream: rebuildStream,
                          builder: (context, snapshot) {
                            final isHovered = editorKey
                                .currentState!
                                .layerInteractionManager
                                .hoverRemoveBtn;

                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: isLayerBeingTransformed
                                  ? Container(
                                      key: removeAreaKey,
                                      height: 56,
                                      width: 56,
                                      margin: const EdgeInsets.only(bottom: 24),
                                      decoration: BoxDecoration(
                                        color: isHovered
                                            ? colors.warning.withValues(
                                                alpha: 0.8,
                                              )
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Center(
                                        child: HugeIcon(
                                          icon: HugeIcons.strokeRoundedDelete02,
                                          color: isHovered
                                              ? Colors.white
                                              : colors.warning.withValues(
                                                  alpha: 0.8,
                                                ),
                                        ),
                                      ),
                                    )
                                  : SizedBox.shrink(
                                      // When hidden, key still needed for hit
                                      // detection to work (returns empty bounds)
                                      key: removeAreaKey,
                                    ),
                            );
                          },
                        ),
                      );
                    },
                appBar: (editor, rebuildStream) {
                  return ReactiveAppbar(
                    builder: (context) {
                      return ImageEditorAppBar(
                        enableRedo: editor.canRedo,
                        enableUndo: editor.canUndo,
                        key: const Key('image_editor_app_bar'),
                        redo: () => editor.redoAction(),
                        undo: () => editor.undoAction(),
                        configs: editor.configs,
                        done: () async {
                          final Uint8List bytes = await editorKey.currentState!
                              .captureEditorImage();
                          await saveImage(bytes);
                        },
                        close: () {
                          _showExitConfirmationDialog(context);
                        },
                        isMainEditor: true,
                      );
                    },
                    stream: rebuildStream,
                  );
                },
                bottomBar: (editor, rebuildStream, key) => ReactiveWidget(
                  key: key,
                  builder: (context) {
                    return ImageEditorMainBottomBar(
                      key: _mainEditorBarKey,
                      editor: editor,
                      configs: editor.configs,
                      callbacks: editor.callbacks,
                    );
                  },
                  stream: rebuildStream,
                ),
              ),
            ),
            paintEditor: PaintEditorConfigs(
              style: PaintEditorStyle(
                initialColor: const Color(0xFF00FFFF),
                background: colors.backgroundBase,
              ),
              widgets: PaintEditorWidgets(
                appBar: (editor, rebuildStream) {
                  return ReactiveAppbar(
                    builder: (context) {
                      return ImageEditorAppBar(
                        enableRedo: editor.canRedo,
                        enableUndo: editor.canUndo,
                        key: const Key('image_editor_app_bar'),
                        redo: () => editor.redoAction(),
                        undo: () => editor.undoAction(),
                        configs: editor.configs,
                        done: () => editor.done(),
                        close: () => editor.close(),
                      );
                    },
                    stream: rebuildStream,
                  );
                },
                colorPicker:
                    (paintEditor, rebuildStream, currentColor, setColor) =>
                        null,
                bottomBar: (editorState, rebuildStream) {
                  return ReactiveWidget(
                    builder: (context) {
                      return ImageEditorPaintBar(
                        configs: editorState.configs,
                        callbacks: editorState.callbacks,
                        editor: editorState,
                        i18nColor: 'Color',
                      );
                    },
                    stream: rebuildStream,
                  );
                },
              ),
            ),
            textEditor: TextEditorConfigs(
              showBackgroundModeButton: true,
              showTextAlignButton: true,
              style: const TextEditorStyle(
                background: Colors.transparent,
                textFieldMargin: EdgeInsets.only(top: kToolbarHeight),
              ),
              widgets: TextEditorWidgets(
                appBar: (textEditor, rebuildStream) => ReactiveAppbar(
                  builder: (context) {
                    return ImageEditorAppBar(
                      key: const Key('image_editor_app_bar'),
                      configs: textEditor.configs,
                      done: () => textEditor.done(),
                      close: () => textEditor.close(),
                    );
                  },
                  stream: rebuildStream,
                ),
                bodyItems: (editor, rebuildStream) {
                  return [
                    ReactiveWidget(
                      builder: (context) {
                        return Positioned.fill(
                          child: GestureDetector(
                            onTap: () {},
                            child: Container(color: Colors.transparent),
                          ),
                        );
                      },
                      stream: rebuildStream,
                    ),
                  ];
                },
                colorPicker:
                    (textEditor, rebuildStream, currentColor, setColor) => null,
                bottomBar: (editorState, rebuildStream) {
                  return ReactiveWidget(
                    builder: (context) {
                      return ImageEditorTextBar(
                        configs: editorState.configs,
                        callbacks: editorState.callbacks,
                        editor: editorState,
                      );
                    },
                    stream: rebuildStream,
                  );
                },
              ),
            ),
            cropRotateEditor: CropRotateEditorConfigs(
              style: CropRotateEditorStyle(
                background: colors.backgroundBase,
                cropCornerColor: colors.primary,
              ),
              widgets: CropRotateEditorWidgets(
                appBar: (editor, rebuildStream) {
                  return ReactiveAppbar(
                    builder: (context) {
                      return ImageEditorAppBar(
                        key: const Key('image_editor_app_bar'),
                        configs: editor.configs,
                        done: () => editor.done(),
                        close: () => editor.close(),
                        enableRedo: editor.canRedo,
                        enableUndo: editor.canUndo,
                        redo: () => editor.redoAction(),
                        undo: () => editor.undoAction(),
                      );
                    },
                    stream: rebuildStream,
                  );
                },
                bottomBar: (cropRotateEditor, rebuildStream) => ReactiveWidget(
                  stream: rebuildStream,
                  builder: (_) => ImageEditorCropRotateBar(
                    configs: cropRotateEditor.configs,
                    callbacks: cropRotateEditor.callbacks,
                    editor: cropRotateEditor,
                  ),
                ),
              ),
            ),
            filterEditor: FilterEditorConfigs(
              fadeInUpDuration: fadeInDuration,
              fadeInUpStaggerDelayDuration: fadeInDelay,
              filterList: filterList,
              style: FilterEditorStyle(background: colors.backgroundBase),
              widgets: FilterEditorWidgets(
                slider:
                    (
                      editorState,
                      rebuildStream,
                      value,
                      onChanged,
                      onChangeEnd,
                    ) => ReactiveWidget(
                      builder: (context) {
                        return const SizedBox.shrink();
                      },
                      stream: rebuildStream,
                    ),
                filterButton:
                    (
                      filter,
                      isSelected,
                      scaleFactor,
                      onSelectFilter,
                      editorImage,
                      filterKey,
                    ) {
                      return ImageEditorFilterBar(
                        filterModel: filter,
                        isSelected: isSelected,
                        onSelectFilter: () {
                          onSelectFilter.call();
                          editorKey.currentState?.setState(() {});
                        },
                        editorImage: editorImage,
                        filterKey: filterKey,
                      );
                    },
                appBar: (editor, rebuildStream) {
                  return ReactiveAppbar(
                    builder: (context) {
                      return ImageEditorAppBar(
                        key: const Key('image_editor_app_bar'),
                        configs: editor.configs,
                        done: () => editor.done(),
                        close: () => editor.close(),
                      );
                    },
                    stream: rebuildStream,
                  );
                },
              ),
            ),
            tuneEditor: TuneEditorConfigs(
              style: TuneEditorStyle(background: colors.backgroundBase),
              widgets: TuneEditorWidgets(
                appBar: (editor, rebuildStream) {
                  return ReactiveAppbar(
                    builder: (context) {
                      return ImageEditorAppBar(
                        enableRedo: editor.canRedo,
                        enableUndo: editor.canUndo,
                        key: const Key('image_editor_app_bar'),
                        redo: () => editor.redo(),
                        undo: () => editor.undo(),
                        configs: editor.configs,
                        done: () => editor.done(),
                        close: () => editor.close(),
                      );
                    },
                    stream: rebuildStream,
                  );
                },
                bottomBar: (editorState, rebuildStream) {
                  return ReactiveWidget(
                    builder: (context) {
                      return ImageEditorTuneBar(
                        configs: editorState.configs,
                        callbacks: editorState.callbacks,
                        editor: editorState,
                      );
                    },
                    stream: rebuildStream,
                  );
                },
              ),
            ),
            blurEditor: const BlurEditorConfigs(),
            emojiEditor: EmojiEditorConfigs(
              checkPlatformCompatibility: true,
              style: EmojiEditorStyle(
                bottomActionBarConfig: BottomActionBarConfig(
                  showSearchViewButton: true,
                  buttonColor: colors.backgroundBase,
                  buttonIconColor: colors.iconColor,
                  backgroundColor: colors.backgroundBase,
                ),
                backgroundColor: colors.backgroundBase,
              ),
            ),
            stickerEditor: StickerEditorConfigs(
              builder: (setLayer, scrollController) {
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }
}
