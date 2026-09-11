import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/models/gallery/justified_layout_tuning.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/components/menu_section_title.dart";

class JustifiedLayoutTuningScreen extends StatefulWidget {
  const JustifiedLayoutTuningScreen({super.key});

  @override
  State<JustifiedLayoutTuningScreen> createState() =>
      _JustifiedLayoutTuningScreenState();
}

class _JustifiedLayoutTuningScreenState
    extends State<JustifiedLayoutTuningScreen> {
  @override
  Widget build(BuildContext context) {
    final flexTuning = localSettings.getFlexLayoutTuning();
    final flexFullRowsTuning = localSettings.getFlexFullRowsLayoutTuning();
    final comfortLargeTuning = localSettings.getComfortLargeLayoutTuning();

    return SettingsPageScaffold(
      title: "Justified layout tuning",
      children: [
        Text(
          "Height values are multipliers of the responsive target row height. "
          "Aspect ratio uses width ÷ height.",
          style: TextStyles.mini.copyWith(
            color: context.componentColors.textLight,
          ),
        ),
        const SizedBox(height: 16),
        const MenuSectionTitle(title: "Flex"),
        MenuGroupComponent(
          items: [
            for (final field in FlexLayoutTuningField.values)
              SettingsItem(
                title: _flexFieldLabel(field),
                trailing: _valueLabel(context, flexTuning.valueFor(field)),
                onTap: () => _editFlexValue(field),
              ),
            SettingsItem(
              title: "Reset all",
              showChevron: false,
              onTap: _resetFlexValues,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const MenuSectionTitle(title: "Flex Full Rows"),
        MenuGroupComponent(
          items: [
            for (final field in FlexFullRowsLayoutTuningField.values)
              SettingsItem(
                title: _flexFullRowsFieldLabel(field),
                trailing: _valueLabel(
                  context,
                  flexFullRowsTuning.valueFor(field),
                ),
                onTap: () => _editFlexFullRowsValue(field),
              ),
            SettingsItem(
              title: "Reset all",
              showChevron: false,
              onTap: _resetFlexFullRowsValues,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const MenuSectionTitle(title: "Comfort Large"),
        MenuGroupComponent(
          items: [
            for (final field in ComfortLargeLayoutTuningField.values)
              SettingsItem(
                title: _comfortLargeFieldLabel(field),
                trailing: _valueLabel(
                  context,
                  comfortLargeTuning.valueFor(field),
                ),
                onTap: () => _editComfortLargeValue(field),
              ),
            SettingsItem(
              title: "Reset all",
              showChevron: false,
              onTap: _resetComfortLargeValues,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editFlexFullRowsValue(
    FlexFullRowsLayoutTuningField field,
  ) async {
    final tuning = localSettings.getFlexFullRowsLayoutTuning();
    await _showValueSheet(
      title: _flexFullRowsFieldLabel(field),
      initialValue: tuning.valueFor(field),
      defaultValue: field.defaultValue,
      isValid: field.isValid,
      validRange: (field.minimumValue, field.maximumValue),
      onSave: (value) async {
        await localSettings.setFlexFullRowsLayoutTuningValue(field, value);
        _refreshGallery();
      },
      onReset: () async {
        await localSettings.resetFlexFullRowsLayoutTuningValue(field);
        _refreshGallery();
      },
    );
  }

  Widget _valueLabel(BuildContext context, double value) {
    return Text(
      _formatValue(value),
      style: TextStyles.mini.copyWith(color: context.componentColors.textLight),
    );
  }

  Future<void> _editFlexValue(FlexLayoutTuningField field) async {
    final tuning = localSettings.getFlexLayoutTuning();
    await _showValueSheet(
      title: _flexFieldLabel(field),
      initialValue: tuning.valueFor(field),
      defaultValue: field.defaultValue,
      isValid: field.isValid,
      validRange: (field.minimumValue, field.maximumValue),
      onSave: (value) async {
        await localSettings.setFlexLayoutTuningValue(field, value);
        _refreshGallery();
      },
      onReset: () async {
        await localSettings.resetFlexLayoutTuningValue(field);
        _refreshGallery();
      },
    );
  }

  Future<void> _editComfortLargeValue(
    ComfortLargeLayoutTuningField field,
  ) async {
    final tuning = localSettings.getComfortLargeLayoutTuning();
    await _showValueSheet(
      title: _comfortLargeFieldLabel(field),
      initialValue: tuning.valueFor(field),
      defaultValue: field.defaultValue,
      isValid: field.isValid,
      validRange: (field.minimumValue, field.maximumValue),
      onSave: (value) async {
        await localSettings.setComfortLargeLayoutTuningValue(field, value);
        _refreshGallery();
      },
      onReset: () async {
        await localSettings.resetComfortLargeLayoutTuningValue(field);
        _refreshGallery();
      },
    );
  }

  Future<void> _showValueSheet({
    required String title,
    required double initialValue,
    required double defaultValue,
    required bool Function(double) isValid,
    required (double, double) validRange,
    required Future<void> Function(double) onSave,
    required Future<void> Function() onReset,
  }) async {
    await showBottomSheetComponent<void>(
      context: context,
      builder: (_) => _TuningValueSheet(
        title: title,
        initialValue: initialValue,
        defaultValue: defaultValue,
        isValid: isValid,
        validRange: validRange,
        onSave: onSave,
        onReset: onReset,
      ),
    );
  }

  Future<void> _resetFlexValues() async {
    await localSettings.resetFlexLayoutTuning();
    _refreshGallery();
  }

  Future<void> _resetFlexFullRowsValues() async {
    await localSettings.resetFlexFullRowsLayoutTuning();
    _refreshGallery();
  }

  Future<void> _resetComfortLargeValues() async {
    await localSettings.resetComfortLargeLayoutTuning();
    _refreshGallery();
  }

  void _refreshGallery() {
    if (mounted) setState(() {});
    Bus.instance.fire(GalleryLayoutChangedEvent());
  }
}

class _TuningValueSheet extends StatefulWidget {
  const _TuningValueSheet({
    required this.title,
    required this.initialValue,
    required this.defaultValue,
    required this.isValid,
    required this.validRange,
    required this.onSave,
    required this.onReset,
  });

  final String title;
  final double initialValue;
  final double defaultValue;
  final bool Function(double) isValid;
  final (double, double) validRange;
  final Future<void> Function(double) onSave;
  final Future<void> Function() onReset;

  @override
  State<_TuningValueSheet> createState() => _TuningValueSheetState();
}

class _TuningValueSheetState extends State<_TuningValueSheet> {
  late final TextEditingController _controller;
  late bool _isValid;

  @override
  void initState() {
    super.initState();
    final text = _formatValue(widget.initialValue);
    _controller = TextEditingController(text: text);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
    _isValid = _validate(text) != null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: widget.title,
      isKeyboardAware: true,
      content: TextInputComponent(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        message: _isValid
            ? "Default: ${_formatValue(widget.defaultValue)}"
            : "Enter a value from ${_formatValue(widget.validRange.$1)} "
                  "to ${_formatValue(widget.validRange.$2)}",
        messageType: _isValid
            ? TextInputComponentMessageType.helper
            : TextInputComponentMessageType.error,
        onChanged: (value) {
          final isValid = _validate(value) != null;
          if (_isValid != isValid) setState(() => _isValid = isValid);
        },
        onSubmit: (_) => _save(),
      ),
      actions: [
        ButtonComponent(
          label: context.strings.save,
          isDisabled: !_isValid,
          onTap: _save,
        ),
        ButtonComponent(
          label: context.strings.resetToDefault,
          variant: ButtonComponentVariant.secondary,
          onTap: _reset,
        ),
      ],
    );
  }

  double? _validate(String text) {
    final value = double.tryParse(text.trim());
    return value != null && widget.isValid(value) ? value : null;
  }

  Future<void> _save() async {
    final value = _validate(_controller.text);
    if (value == null) return;
    await widget.onSave(value);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await widget.onReset();
    if (mounted) Navigator.of(context).pop();
  }
}

String _flexFieldLabel(FlexLayoutTuningField field) => switch (field) {
  FlexLayoutTuningField.targetHeightScale => "Target height scale",
  FlexLayoutTuningField.maximumHeightFactor => "Maximum height factor",
};

String _flexFullRowsFieldLabel(FlexFullRowsLayoutTuningField field) =>
    switch (field) {
      FlexFullRowsLayoutTuningField.targetHeightScale => "Target height scale",
      FlexFullRowsLayoutTuningField.maximumHeightFactor =>
        "Maximum height factor",
      FlexFullRowsLayoutTuningField.minimumNonFinalSingletonAspectRatio =>
        "Minimum non-final singleton aspect ratio",
    };

String _comfortLargeFieldLabel(ComfortLargeLayoutTuningField field) =>
    switch (field) {
      ComfortLargeLayoutTuningField.targetHeightScale => "Target height scale",
      ComfortLargeLayoutTuningField.maximumHeightFactor =>
        "Maximum height factor",
      ComfortLargeLayoutTuningField.wideFinalMaximumHeightFactor =>
        "Wide final maximum height factor",
      ComfortLargeLayoutTuningField.minimumLandscapeHeightFactor =>
        "Minimum landscape height factor",
    };

String _formatValue(double value) => value.toString();
