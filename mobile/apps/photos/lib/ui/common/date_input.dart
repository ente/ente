import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/l10n/l10n.dart";

class DatePickerField extends StatefulWidget {
  const DatePickerField({
    super.key,
    this.initialValue,
    this.label,
    this.hintText,
    this.onChanged,
    this.onValidityChanged,
    this.firstDate,
    this.lastDate,
    this.isRequired = true,
  });

  final String? initialValue;
  final String? label;
  final String? hintText;
  final ValueChanged<DateTime?>? onChanged;
  final ValueChanged<bool>? onValidityChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool isRequired;

  @override
  State<DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<DatePickerField> {
  final _controller = TextEditingController();
  DateTime? _selectedDate;
  bool _hasError = false;
  bool _initialized = false;
  bool _isUSLocale = false;

  String get _displayFormat => _isUSLocale ? 'MM/dd/yyyy' : 'dd/MM/yyyy';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final locale = Localizations.localeOf(context);
    Locale? formatLocale;
    for (final deviceLocale
        in WidgetsBinding.instance.platformDispatcher.locales) {
      if (deviceLocale.languageCode == locale.languageCode) {
        if (deviceLocale.countryCode == locale.countryCode) {
          formatLocale = deviceLocale;
          break;
        }
        formatLocale ??= deviceLocale;
      }
    }
    _isUSLocale = (formatLocale ?? locale).countryCode == 'US';
    _selectedDate = _parseDate(widget.initialValue ?? '');
    _controller.text = _selectedDate == null
        ? widget.initialValue ?? ''
        : _formatDate(_selectedDate!);
    _hasError = _controller.text.isNotEmpty && _selectedDate == null;
    _initialized = true;
  }

  DateTime? _parseDate(String value) {
    final formats = _isUSLocale
        ? const ['MM/dd/yyyy', 'MM-dd-yyyy', 'yyyy-MM-dd']
        : const ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd'];
    for (final format in formats) {
      try {
        return DateFormat(format).parseStrict(value.trim());
      } catch (_) {}
    }
    return null;
  }

  String _formatDate(DateTime date) => DateFormat(_displayFormat).format(date);

  void _onTextChanged(String value) {
    final trimmedValue = value.trim();
    final parsed = trimmedValue.isEmpty ? null : _parseDate(trimmedValue);
    final isValid = trimmedValue.isEmpty
        ? !widget.isRequired
        : parsed != null &&
              (widget.firstDate == null ||
                  !parsed.isBefore(widget.firstDate!)) &&
              (widget.lastDate == null || !parsed.isAfter(widget.lastDate!));

    setState(() {
      if (isValid) {
        _selectedDate = parsed;
      }
      _hasError = !isValid;
    });
    widget.onValidityChanged?.call(isValid);
    if (isValid) {
      widget.onChanged?.call(parsed);
    }
  }

  Future<void> _showDatePicker() async {
    final locale = await getFormatLocale();
    if (!mounted) return;
    final firstDate = widget.firstDate ?? DateTime(1900);
    final lastDate = widget.lastDate ?? DateTime(2100);
    final selectedDate = _selectedDate ?? DateTime.now();
    final initialDate = selectedDate.isBefore(firstDate)
        ? firstDate
        : selectedDate.isAfter(lastDate)
        ? lastDate
        : selectedDate;
    final picked = await showDatePicker(
      context: context,
      locale: locale,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null && mounted) {
      _controller.text = _formatDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextInputComponent(
      controller: _controller,
      label: widget.label,
      hintText: widget.hintText,
      keyboardType: TextInputType.datetime,
      autocorrect: false,
      enableSuggestions: false,
      isRequired: widget.isRequired,
      message: _hasError ? _displayFormat.toUpperCase() : null,
      messageType: _hasError
          ? TextInputComponentMessageType.error
          : TextInputComponentMessageType.helper,
      suffix: HugeIcon(
        icon: HugeIcons.strokeRoundedCalendar03,
        color: context.componentColors.textLighter,
        size: IconSizes.small,
      ),
      onSuffixTap: _showDatePicker,
      onChanged: _onTextChanged,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
