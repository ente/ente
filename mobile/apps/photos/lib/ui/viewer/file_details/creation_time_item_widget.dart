import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/ui/viewer/date/edit_date_sheet.dart";
import "package:photos/ui/viewer/gallery/jump_to_date_gallery.dart";

class CreationTimeItem extends StatefulWidget {
  final EnteFile file;
  final int currentUserID;
  const CreationTimeItem(this.file, this.currentUserID, {super.key});

  @override
  State<CreationTimeItem> createState() => _CreationTimeItemState();
}

class _CreationTimeItemState extends State<CreationTimeItem> {
  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final dateTime = _dateTimeForDisplay(widget.file);
    final canEdit =
        (widget.file.ownerID == null ||
            widget.file.ownerID == widget.currentUserID) &&
        widget.file.uploadedFileID != null &&
        !widget.file.isTrash;
    return MenuComponent(
      key: const ValueKey("Creation time"),
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedCalendar04,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: DateFormat.yMMMEd(
        Localizations.localeOf(context).languageCode,
      ).format(dateTime),
      subtitle: getTimeIn12hrFormat(dateTime),
      onTap: () {
        Bus.instance.fire(PauseVideoEvent());
        routeToPage(context, JumpToDateGallery(fileToJumpTo: widget.file));
      },
      trailing: canEdit
          ? IconButtonComponent(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedEdit03,
                size: IconSizes.small,
                color: colors.textLight,
              ),
              variant: IconButtonComponentVariant.secondary,
              shouldSurfaceExecutionStates: false,
              onTap: () => _showDateTimePicker(widget.file),
            )
          : null,
    );
  }

  void _showDateTimePicker(EnteFile file) async {
    final DateTime? newDate = await showEditDateSheet(context, [
      file,
    ], showHeader: false);
    if (newDate != null) {
      widget.file.creationTime = newDate.microsecondsSinceEpoch;
      setState(() {});
    }
  }

  DateTime _dateTimeForDisplay(EnteFile file) {
    final editedTime = file.pubMagicMetadata?.editedTime;
    if (editedTime != null && editedTime != 0) {
      return DateTime.fromMicrosecondsSinceEpoch(
        editedTime,
        isUtc: true,
      ).toLocal();
    }

    final dateTime = file.pubMagicMetadata?.dateTime;
    if (dateTime != null && dateTime.isNotEmpty) {
      final parsedDateTime = DateTime.tryParse(dateTime);
      if (parsedDateTime != null) return parsedDateTime;
    }

    return DateTime.fromMicrosecondsSinceEpoch(
      file.creationTime!,
      isUtc: true,
    ).toLocal();
  }
}
