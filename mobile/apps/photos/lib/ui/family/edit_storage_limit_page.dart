import 'dart:math' as math;

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/services/family_service.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import 'package:photos/ui/family/family_ui.dart';
import 'package:photos/utils/dialog_util.dart';

class EditStorageLimitPage extends StatefulWidget {
  const EditStorageLimitPage({
    required this.member,
    required this.displayName,
    required this.totalStorageInBytes,
    required this.avatarColor,
    super.key,
  });

  final FamilyMember member;
  final String displayName;
  final int totalStorageInBytes;
  final Color avatarColor;

  @override
  State<EditStorageLimitPage> createState() => _EditStorageLimitPageState();
}

class _EditStorageLimitPageState extends State<EditStorageLimitPage> {
  static const _gigabyte = 1024 * 1024 * 1024;
  static const _sliderStepInGigabytes = 5;

  late final List<int> _sliderOptionsInGigabytes;
  late double _sliderIndex;

  int get _maxSliderValueInGigabytes =>
      math.max(1, (widget.totalStorageInBytes / _gigabyte).ceil());

  int get _minimumLimitedSliderValueInGigabytes =>
      (widget.member.usage / _gigabyte).ceil();

  int get _selectedSliderIndex =>
      _sliderIndex.round().clamp(0, _sliderOptionsInGigabytes.length - 1);

  int get _selectedSliderValueInGigabytes =>
      _sliderOptionsInGigabytes[_selectedSliderIndex];

  int? get _existingStorageLimitInGigabytes =>
      _storageLimitInGigabytes(widget.member.storageLimit);

  int? get _initialCustomSliderValueInGigabytes {
    final existingStorageLimitInGigabytes = _existingStorageLimitInGigabytes;
    if (existingStorageLimitInGigabytes == null ||
        _isStandardSliderValue(existingStorageLimitInGigabytes)) {
      return null;
    }
    return existingStorageLimitInGigabytes;
  }

  bool get _hasChangedStorageLimit =>
      _selectedSliderValueInGigabytes !=
      (_existingStorageLimitInGigabytes ?? 0);

  int? get _selectedStorageLimit {
    if (_selectedSliderValueInGigabytes <= 0) {
      return null;
    }
    return _selectedSliderValueInGigabytes * _gigabyte;
  }

  @override
  void initState() {
    super.initState();
    _sliderOptionsInGigabytes = _buildSliderOptionsInGigabytes();
    _sliderIndex = _indexForStorageLimit(widget.member.storageLimit).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return FamilyPageScaffold(
      title: l10n.storageLimit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: widget.avatarColor,
                        child: Text(
                          widget.displayName.substring(0, 1).toUpperCase(),
                          style: textTheme.bodyBold.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.displayName, style: textTheme.body),
                            const SizedBox(height: 2),
                            Text(
                              l10n.usingStorage(
                                amount: convertBytesToReadableFormat(
                                  widget.member.usage,
                                ),
                              ),
                              style: textTheme.smallMuted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.storageLimitExplanation,
                    style: textTheme.bodyMuted.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.fill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.limit, style: textTheme.bodyBold),
                            Text(
                              _selectedStorageLimit == null
                                  ? l10n.noLimit
                                  : convertBytesToReadableFormat(
                                      _selectedStorageLimit!,
                                    ),
                              style: textTheme.h3Bold.copyWith(
                                color: colorScheme.greenBase,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: colorScheme.greenBase,
                            inactiveTrackColor: colorScheme.fillMuted,
                            thumbColor: colorScheme.greenBase,
                            overlayColor: colorScheme.greenBase.withValues(
                              alpha: 0.14,
                            ),
                          ),
                          child: Slider(
                            value: _sliderIndex.clamp(
                              0,
                              (_sliderOptionsInGigabytes.length - 1).toDouble(),
                            ),
                            min: 0,
                            max: (_sliderOptionsInGigabytes.length - 1)
                                .toDouble(),
                            divisions: _sliderOptionsInGigabytes.length - 1,
                            onChanged: (value) {
                              final roundedIndex = value.round();
                              final roundedValue =
                                  _sliderOptionsInGigabytes[roundedIndex];
                              final effectiveIndex =
                                  roundedValue > 0 &&
                                      roundedValue <
                                          _minimumLimitedSliderValueInGigabytes
                                  ? _minimumSelectableIndex().toDouble()
                                  : roundedIndex.toDouble();
                              setState(() {
                                _sliderIndex = effectiveIndex;
                              });
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.noLimit, style: textTheme.miniMuted),
                            Text(
                              convertBytesToReadableFormat(
                                widget.totalStorageInBytes,
                              ),
                              style: textTheme.miniMuted,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      l10n.currentUsageNote(
                        amount: convertBytesToReadableFormat(
                          widget.member.usage,
                        ),
                      ),
                      style: textTheme.smallFaint.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.primary,
            labelText: l10n.save,
            isDisabled: !_hasChangedStorageLimit,
            onTap: _saveLimit,
          ),
        ],
      ),
    );
  }

  Future<void> _saveLimit() async {
    if (!_hasChangedStorageLimit) {
      return;
    }
    try {
      final updatedUserDetails = await FamilyService.instance
          .updateMemberStorageLimit(
            member: widget.member,
            storageLimit: _selectedStorageLimit,
          );
      if (mounted) {
        Navigator.of(context).pop(updatedUserDetails);
      }
    } catch (error) {
      if (!mounted) {
        throw const _HandledStorageLimitException();
      }
      await showGenericErrorDialog(context: context, error: error);
      throw const _HandledStorageLimitException();
    }
  }

  List<int> _buildSliderOptionsInGigabytes() {
    final options = <int>[0];
    for (
      var value = _sliderStepInGigabytes;
      value < _maxSliderValueInGigabytes;
      value += _sliderStepInGigabytes
    ) {
      options.add(value);
    }
    if (options.last != _maxSliderValueInGigabytes) {
      options.add(_maxSliderValueInGigabytes);
    }
    final initialCustomSliderValueInGigabytes =
        _initialCustomSliderValueInGigabytes;
    if (initialCustomSliderValueInGigabytes != null) {
      options.add(initialCustomSliderValueInGigabytes);
    }
    return options.toSet().toList()..sort();
  }

  int _indexForStorageLimit(int? storageLimit) {
    final limitInGigabytes = _storageLimitInGigabytes(storageLimit);
    if (limitInGigabytes == null) {
      return 0;
    }
    for (var index = 1; index < _sliderOptionsInGigabytes.length; index++) {
      if (_sliderOptionsInGigabytes[index] >= limitInGigabytes) {
        return index;
      }
    }

    return _sliderOptionsInGigabytes.length - 1;
  }

  int _minimumSelectableIndex() {
    for (var index = 1; index < _sliderOptionsInGigabytes.length; index++) {
      if (_sliderOptionsInGigabytes[index] >=
          _minimumLimitedSliderValueInGigabytes) {
        return index;
      }
    }

    return _sliderOptionsInGigabytes.length - 1;
  }

  int? _storageLimitInGigabytes(int? storageLimit) {
    if (storageLimit == null) {
      return null;
    }
    return (storageLimit / _gigabyte).ceil();
  }

  bool _isStandardSliderValue(int valueInGigabytes) {
    return valueInGigabytes == 0 ||
        valueInGigabytes == _maxSliderValueInGigabytes ||
        valueInGigabytes % _sliderStepInGigabytes == 0;
  }
}

class _HandledStorageLimitException implements Exception {
  const _HandledStorageLimitException();
}
