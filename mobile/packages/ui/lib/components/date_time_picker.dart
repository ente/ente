import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/cupertino.dart";

Future<DateTime?> showDateTimePickerSheet(
  BuildContext context, {
  required DateTime initialDateTime,
  DateTime? minDateTime,
  DateTime? maxDateTime,
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
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: DateTimePicker(
          initialDateTime: initialDateTime,
          onDateTimeSelected: (dateTime) =>
              Navigator.of(sheetContext).pop(dateTime),
          onCancel: () => Navigator.of(sheetContext).pop(),
          minDateTime: minDateTime,
          maxDateTime: maxDateTime,
          startWithTime: startWithTime,
        ),
      ),
    ),
  );
}

class DateTimePicker extends StatefulWidget {
  const DateTimePicker({
    required this.initialDateTime,
    required this.onDateTimeSelected,
    required this.onCancel,
    this.minDateTime,
    this.maxDateTime,
    this.startWithTime = false,
    super.key,
  });

  final ValueChanged<DateTime> onDateTimeSelected;
  final VoidCallback onCancel;
  final DateTime initialDateTime;
  final DateTime? maxDateTime;
  final DateTime? minDateTime;
  final bool startWithTime;

  @override
  State<DateTimePicker> createState() => _DateTimePickerState();
}

class _DateTimePickerState extends State<DateTimePicker> {
  late DateTime _selectedDateTime;
  late bool _showTimePicker;

  @override
  void initState() {
    super.initState();
    _showTimePicker = widget.startWithTime;
    _selectedDateTime = widget.initialDateTime;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return SafeArea(
      top: false,
      child: Container(
        color: colors.fillLight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _showTimePicker
                      ? context.strings.selectTime
                      : context.strings.selectDate,
                  style: TextStyle(color: colors.textBase, fontSize: 16),
                ),
              ),
            ),
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
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                  showDayOfWeek: !_showTimePicker,
                  onDateTimeChanged: _onDateTimeChanged,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _handleBackOrCancel,
                    child: Text(
                      _showTimePicker
                          ? context.strings.previous
                          : context.strings.cancel,
                      style: TextStyle(color: colors.textBase, fontSize: 14),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _handleNextOrDone,
                    child: Text(
                      _showTimePicker
                          ? context.strings.done
                          : context.strings.next,
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDateTimeChanged(DateTime dateTime) {
    setState(() {
      _selectedDateTime = _showTimePicker
          ? DateTime(
              _selectedDateTime.year,
              _selectedDateTime.month,
              _selectedDateTime.day,
              dateTime.hour,
              dateTime.minute,
            )
          : DateTime(
              dateTime.year,
              dateTime.month,
              dateTime.day,
              _selectedDateTime.hour,
              _selectedDateTime.minute,
            );

      final minDateTime = widget.minDateTime;
      if (minDateTime != null && _selectedDateTime.isBefore(minDateTime)) {
        _selectedDateTime = minDateTime;
      }
      final maxDateTime = widget.maxDateTime;
      if (maxDateTime != null && _selectedDateTime.isAfter(maxDateTime)) {
        _selectedDateTime = maxDateTime;
      }
    });
  }

  void _handleBackOrCancel() {
    if (_showTimePicker) {
      setState(() => _showTimePicker = false);
    } else {
      widget.onCancel();
    }
  }

  void _handleNextOrDone() {
    if (_showTimePicker) {
      widget.onDateTimeSelected(_selectedDateTime);
    } else {
      setState(() => _showTimePicker = true);
    }
  }
}
