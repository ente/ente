import "package:ente_components/ente_components.dart";
import "package:flutter/cupertino.dart";
import "package:locker/l10n/l10n.dart";

Future<DateTime?> showDatePickerSheet(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? maxDate,
  DateTime? minDate,
  bool startWithTime = false,
}) {
  final colors = context.componentColors;
  return showBottomSheetComponent<DateTime?>(
    context: context,
    builder: (sheetContext) => Container(
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: DateTimePickerWidget(
            (DateTime dateTime) {
              Navigator.of(sheetContext).pop(dateTime);
            },
            () {
              Navigator.of(sheetContext).pop(null);
            },
            initialDate,
            minDateTime: minDate,
            maxDateTime: maxDate,
            startWithTime: startWithTime,
          ),
        ),
      ),
    ),
  );
}

class DateTimePickerWidget extends StatefulWidget {
  final Function(DateTime) onDateTimeSelected;
  final Function() onCancel;
  final DateTime initialDateTime;
  final DateTime? maxDateTime;
  final DateTime? minDateTime;
  final bool startWithTime;

  const DateTimePickerWidget(
    this.onDateTimeSelected,
    this.onCancel,
    this.initialDateTime, {
    this.maxDateTime,
    this.minDateTime,
    this.startWithTime = false,
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
      color: colors.fillLight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _showTimePicker
                    ? context.l10n.selectTime
                    : context.l10n.selectDate,
                style: TextStyle(color: colors.textBase, fontSize: 16),
              ),
            ),
          ),

          // Date/Time Picker
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: colors.fillLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: Brightness.dark,
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Cancel Button
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text(
                    _showTimePicker
                        ? context.l10n.previous
                        : context.l10n.cancel,
                    style: TextStyle(color: colors.textBase, fontSize: 14),
                  ),
                  onPressed: () {
                    if (_showTimePicker) {
                      // Go back to date picker
                      setState(() {
                        _showTimePicker = false;
                      });
                    } else {
                      widget.onCancel();
                    }
                  },
                ),

                // Next/Done Button
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text(
                    _showTimePicker ? context.l10n.done : context.l10n.next,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    if (_showTimePicker) {
                      // We're done, call the callback
                      widget.onDateTimeSelected(_selectedDateTime);
                    } else {
                      // Move to time picker
                      setState(() {
                        _showTimePicker = true;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
