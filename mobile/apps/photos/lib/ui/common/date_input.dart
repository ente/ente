import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import "package:photos/l10n/l10n.dart";
import "package:photos/theme/ente_theme.dart";

class DatePickerField extends StatefulWidget {
  final String? initialValue;
  final String? hintText;
  final void Function(DateTime?)? onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool isRequired; // New parameter for optional/required state

  const DatePickerField({
    super.key,
    this.initialValue,
    this.hintText,
    this.onChanged,
    this.firstDate,
    this.lastDate,
    this.isRequired = true, // Default to required for backward compatibility
  });

  @override
  State<DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<DatePickerField> {
  final TextEditingController _controller = TextEditingController();
  DateTime? _selectedDate;
  bool _hasError = false;
  bool isUSLocale = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
      _tryParseDate(widget.initialValue!, initialParse: true).ignore();
    }
  }

  Future<void> _tryParseDate(String value, {bool initialParse = false}) async {
    Locale? locale = await getLocale();
    locale ??= const Locale('en', 'US');
    isUSLocale = locale.toString().toLowerCase().contains('us');
    // If the field is empty and not required, reset error state and clear date
    if (value.isEmpty && !widget.isRequired) {
      setState(() {
        _selectedDate = null;
        _hasError = false;
      });
      widget.onChanged?.call(null);
      return;
    }

    // Skip validation for empty optional fields
    if (value.isEmpty) {
      return;
    }

    try {
      // Try parsing different date formats
      DateTime? parsed;
      final List<String> formats = isUSLocale
          ? [
              'MM/dd/yyyy',
              'MM-dd-yyyy',
              'yyyy-MM-dd', // Corrected format
            ]
          : [
              'dd/MM/yyyy',
              'dd-MM-yyyy',
              'yyyy-MM-dd', // Corrected format
            ];

      for (String format in formats) {
        try {
          parsed = DateFormat(format).parseStrict(value);
          break;
        } catch (_) {
          continue;
        }
      }

      if (parsed != null) {
        // Validate date range if specified
        bool isValid = true;
        if (widget.firstDate != null && parsed.isBefore(widget.firstDate!)) {
          isValid = false;
        }
        if (widget.lastDate != null && parsed.isAfter(widget.lastDate!)) {
          isValid = false;
        }

        setState(() {
          _selectedDate = isValid ? parsed : null;
          _hasError = !isValid;
        });

        if (isValid) {
          if (initialParse) {
            _controller.text = isUSLocale
                ? DateFormat('MM-dd-yyyy').format(parsed)
                : DateFormat('dd-MM-yyyy').format(parsed);
          }
          widget.onChanged?.call(parsed);
        }
      } else {
        setState(() {
          _selectedDate = null;
          _hasError = true;
        });
      }
    } catch (e) {
      setState(() {
        _selectedDate = null;
        _hasError = true;
      });
    }
  }

  Future<void> _showDatePicker() async {
    final Locale locale = await getFormatLocale();
    if (!mounted) return;
    final DateTime? picked = await showDatePicker(
      context: context,
      locale: locale,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: widget.firstDate ?? DateTime(1900),
      lastDate: widget.lastDate ?? DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _hasError = false;
        _controller.text = isUSLocale
            ? DateFormat('MM-dd-yyyy').format(picked)
            : DateFormat('dd-MM-yyyy').format(picked);
      });
      widget.onChanged?.call(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      onChanged: (value) => _tryParseDate(value),
      decoration: InputDecoration(
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          borderSide: BorderSide(
            color: getEnteColorScheme(context).strokeMuted,
          ),
        ),
        fillColor: getEnteColorScheme(context).fillFaint,
        filled: true,
        hintText:
            widget.hintText ??
            "Enter date (DD/MM/YYYY)${widget.isRequired ? '' : ' (optional)'}",
        hintStyle: getEnteTextTheme(context).bodyFaint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: UnderlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8),
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: _showDatePicker,
          color: _hasError
              ? getEnteColorScheme(context).warning500
              : getEnteColorScheme(context).strokeMuted,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
