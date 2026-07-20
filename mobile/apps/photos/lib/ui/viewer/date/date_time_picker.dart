import "package:ente_components/ente_components.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";

Future<DateTime?> showDatePickerSheet(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? maxDate,
  DateTime? minDate,
  bool startWithTime = false,
}) {
  bool showTimePicker = startWithTime;
  return showBottomSheetComponent<DateTime?>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return StatefulBuilder(
        builder: (context, setState) => BottomSheetComponent(
          title: showTimePicker ? l10n.selectTime : l10n.selectDate,
          showCloseButton: true,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          content: DateTimePickerWidget(
            (dateTime) => Navigator.of(context).pop(dateTime),
            () => Navigator.of(context).pop(null),
            initialDate,
            minDateTime: minDate,
            maxDateTime: maxDate,
            startWithTime: startWithTime,
            showTitle: false,
            onShowTimePickerChanged: (value) =>
                setState(() => showTimePicker = value),
          ),
        ),
      );
    },
  );
}

class DateTimePickerWidget extends StatefulWidget {
  final Function(DateTime) onDateTimeSelected;
  final Function() onCancel;
  final DateTime initialDateTime;
  final DateTime? maxDateTime;
  final DateTime? minDateTime;
  final bool startWithTime;
  final bool showTitle;
  final ValueChanged<bool>? onShowTimePickerChanged;

  const DateTimePickerWidget(
    this.onDateTimeSelected,
    this.onCancel,
    this.initialDateTime, {
    this.maxDateTime,
    this.minDateTime,
    this.startWithTime = false,
    this.showTitle = true,
    this.onShowTimePickerChanged,
    super.key,
  });

  @override
  State<DateTimePickerWidget> createState() => _DateTimePickerWidgetState();
}

class _DateTimePickerWidgetState extends State<DateTimePickerWidget> {
  late DateTime _selectedDateTime;
  bool _showTimePicker = false;

  @override
  void initState() {
    super.initState();
    _showTimePicker = widget.startWithTime;
    _selectedDateTime = widget.initialDateTime;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      color: colors.backgroundBase,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          if (widget.showTitle)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _showTimePicker
                      ? AppLocalizations.of(context).selectTime
                      : AppLocalizations.of(context).selectDate,
                  style: TextStyle(color: colors.textBase, fontSize: 16),
                ),
              ),
            ),

          // Date/Time Picker
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: colors.fillLight,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: Theme.of(context).brightness,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(
                    color: colors.textBase,
                    fontSize: 22,
                  ),
                ),
              ),
              child: CupertinoDatePicker(
                key: ValueKey(_showTimePicker),
                mode: _showTimePicker
                    ? CupertinoDatePickerMode.time
                    : CupertinoDatePickerMode.date,
                initialDateTime: _selectedDateTime,
                minimumDate: widget.minDateTime ?? DateTime(1800),
                maximumDate: widget.maxDateTime ?? DateTime(2200),
                use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
                showDayOfWeek: !_showTimePicker,
                onDateTimeChanged: (DateTime newDateTime) {
                  setState(() {
                    if (_showTimePicker) {
                      // Keep the date but update the time
                      _selectedDateTime = DateTime(
                        _selectedDateTime.year,
                        _selectedDateTime.month,
                        _selectedDateTime.day,
                        newDateTime.hour,
                        newDateTime.minute,
                      );
                    } else {
                      // Keep the time but update the date
                      _selectedDateTime = DateTime(
                        newDateTime.year,
                        newDateTime.month,
                        newDateTime.day,
                        _selectedDateTime.hour,
                        _selectedDateTime.minute,
                      );
                    }

                    // Ensure the selected date doesn't exceed maxDateTime or minDateTime
                    if (widget.minDateTime != null &&
                        _selectedDateTime.isBefore(widget.minDateTime!)) {
                      _selectedDateTime = widget.minDateTime!;
                    }
                    if (widget.maxDateTime != null &&
                        _selectedDateTime.isAfter(widget.maxDateTime!)) {
                      _selectedDateTime = widget.maxDateTime!;
                    }
                  });
                },
              ),
            ),
          ),

          // Buttons
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textBase,
                      textStyle: TextStyles.body,
                    ),
                    onPressed: () {
                      if (_showTimePicker) {
                        _setShowTimePicker(false);
                      } else {
                        widget.onCancel();
                      }
                    },
                    child: Text(
                      _showTimePicker
                          ? AppLocalizations.of(context).previous
                          : AppLocalizations.of(context).cancel,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      textStyle: TextStyles.bodyBold,
                    ),
                    onPressed: () {
                      if (_showTimePicker) {
                        widget.onDateTimeSelected(_selectedDateTime);
                      } else {
                        _setShowTimePicker(true);
                      }
                    },
                    child: Text(
                      _showTimePicker
                          ? AppLocalizations.of(context).done
                          : AppLocalizations.of(context).next,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setShowTimePicker(bool showTimePicker) {
    setState(() {
      _showTimePicker = showTimePicker;
    });
    widget.onShowTimePickerChanged?.call(showTimePicker);
  }
}
