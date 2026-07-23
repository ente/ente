import "package:ente_components/ente_components.dart" as components;
import 'package:flutter/material.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/models/collection/collection.dart';
import "package:photos/models/gallery_type.dart";
import "package:photos/models/ml/face/person.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/ui/components/bottom_action_bar/action_bar_widget.dart';
import "package:photos/ui/components/divider_widget.dart";
import "package:photos/ui/viewer/actions/file_selection_actions_widget.dart";

class BottomActionBarWidget extends StatelessWidget {
  final GalleryType galleryType;
  final Collection? collection;
  final PersonEntity? person;
  final String? clusterID;
  final SelectedFiles selectedFiles;
  final VoidCallback? onCancel;
  final Color? backgroundColor;

  const BottomActionBarWidget({
    required this.galleryType,
    required this.selectedFiles,
    this.collection,
    this.person,
    this.clusterID,
    this.onCancel,
    this.backgroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final widthOfScreen = MediaQuery.of(context).size.width;
    final colors = components.ComponentTheme.colorsOf(context);
    final double leftRightPadding = widthOfScreen > restrictedMaxWidth
        ? (widthOfScreen - restrictedMaxWidth) / 2
        : 0;
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.backgroundBase,
        border: Border(top: BorderSide(color: colors.strokeDark)),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.only(
        top: 4,
        bottom: bottomPadding,
        right: leftRightPadding,
        left: leftRightPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          FileSelectionActionsWidget(
            galleryType,
            selectedFiles,
            collection: collection,
            person: person,
            clusterID: clusterID,
          ),
          const DividerWidget(dividerType: DividerType.bottomBar),
          ActionBarWidget(selectedFiles: selectedFiles, onCancel: onCancel),
          // const SizedBox(height: 2)
        ],
      ),
    );
  }
}
