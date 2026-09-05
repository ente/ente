import 'dart:math';

import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/tools/editor/image_editor/circular_icon_button.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_configs_mixin.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditorMainBottomBar extends StatefulWidget with SimpleConfigsAccess {
  const ImageEditorMainBottomBar({
    super.key,
    required this.configs,
    required this.callbacks,
    required this.editor,
  });

  final ProImageEditorState editor;

  @override
  final ProImageEditorConfigs configs;
  @override
  final ProImageEditorCallbacks callbacks;

  @override
  State<ImageEditorMainBottomBar> createState() =>
      ImageEditorMainBottomBarState();
}

class ImageEditorMainBottomBarState extends State<ImageEditorMainBottomBar>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildFunctions(constraints)],
        );
      },
    );
  }

  Widget _buildFunctions(BoxConstraints constraints) {
    return BottomAppBar(
      height: editorBottomBarHeight,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        layoutBuilder: (currentChild, previousChildren) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: <Widget>[...previousChildren, ?currentChild],
        ),
        duration: const Duration(milliseconds: 400),
        reverseDuration: const Duration(milliseconds: 0),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axis: Axis.vertical,
              alignment: AlignmentDirectional.topStart,
              child: child,
            ),
          );
        },
        switchInCurve: Curves.ease,
        child:
            widget.editor.isSubEditorOpen && !widget.editor.isSubEditorClosing
            ? const SizedBox.shrink()
            : Align(
                alignment: Alignment.center,
                child: SingleChildScrollView(
                  clipBehavior: Clip.none,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: min(constraints.maxWidth, 600),
                      maxWidth: 600,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircularIconButton(
                          hugeIcon: HugeIcons.strokeRoundedCrop,
                          label: context.strings.crop,
                          onTap: () {
                            widget.editor.openCropRotateEditor();
                          },
                        ),
                        CircularIconButton(
                          hugeIcon: HugeIcons.strokeRoundedFilter,
                          label: context.strings.filter,
                          onTap: () {
                            widget.editor.openFilterEditor();
                          },
                        ),
                        CircularIconButton(
                          hugeIcon: HugeIcons.strokeRoundedSlidersHorizontal,
                          label: context.strings.adjust,
                          onTap: () {
                            widget.editor.openTuneEditor();
                          },
                        ),
                        CircularIconButton(
                          hugeIcon: HugeIcons.strokeRoundedPaintBrush01,
                          label: context.strings.draw,
                          onTap: () {
                            widget.editor.openPaintEditor();
                          },
                        ),
                        CircularIconButton(
                          hugeIcon: HugeIcons.strokeRoundedSticker,
                          label: context.strings.sticker,
                          onTap: () {
                            widget.editor.openEmojiEditor();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
