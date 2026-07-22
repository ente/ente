import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/date/edit_date_sheet.dart";
import "package:photos/ui/viewer/file_details_new/file_details_info_item.dart";
import "package:photos/ui/viewer/gallery/jump_to_date_gallery.dart";

class CreationTimeItemNew extends StatefulWidget {
  const CreationTimeItemNew(this.file, this.currentUserID, {super.key});

  final EnteFile file;
  final int currentUserID;

  @override
  State<CreationTimeItemNew> createState() => _CreationTimeItemNewState();
}

class _CreationTimeItemNewState extends State<CreationTimeItemNew> {
  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final dateTime = _dateTimeForDisplay(widget.file);
    final canEdit =
        (widget.file.ownerID == null ||
            widget.file.ownerID == widget.currentUserID) &&
        widget.file.uploadedFileID != null &&
        !widget.file.isTrash;
    return FileDetailsInfoItemNew(
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedCalendar04,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: DateFormat.yMMMEd(
        Localizations.localeOf(context).languageCode,
      ).format(dateTime),
      subtitles: [
        Text(
          getTimeIn12hrFormat(dateTime),
          style: TextStyles.mini.copyWith(color: colors.textLight),
        ),
      ],
      onTap: () {
        Bus.instance.fire(PauseVideoEvent());
        routeToPage(context, JumpToDateGallery(fileToJumpTo: widget.file));
      },
      onEdit: canEdit ? _showDateTimePicker : null,
    );
  }

  Future<void> _showDateTimePicker() async {
    final newDate = await showEditDateSheet(context, [
      widget.file,
    ], showHeader: false);
    if (newDate != null && mounted) {
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
