import 'dart:async';

import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2482-6644&m=dev
/// Section: Radio buttons, toggles and checkboxes / Toggle Switch
/// Specs: 31px by 18px switch with selected and unselected states.
class ToggleSwitchComponent extends StatefulWidget {
  const ToggleSwitchComponent({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showStateIcon = false,
    this.optimisticallyUpdate = true,
    this.loadingDelay = const Duration(milliseconds: 300),
    this.minimumFeedbackDuration = const Duration(milliseconds: 200),
    this.successDuration = const Duration(seconds: 2),
  }) : _value = null;

  ToggleSwitchComponent.async({
    super.key,
    required ValueGetter<bool> value,
    required FutureOr<void> Function() onChanged,
    this.showStateIcon = true,
    this.optimisticallyUpdate = true,
    this.loadingDelay = const Duration(milliseconds: 300),
    this.minimumFeedbackDuration = const Duration(milliseconds: 200),
    this.successDuration = const Duration(seconds: 2),
  }) : selected = value(),
       _value = value,
       onChanged = ((_) => onChanged());

  final bool selected;
  final FutureOr<void> Function(bool selected)? onChanged;
  final bool showStateIcon;

  /// Whether the thumb moves before the owner confirms a new [selected] value.
  /// Library sharing disables this while its enable action is a preview dialog.
  /// Source: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=15782-102259&m=dev
  final bool optimisticallyUpdate;
  final Duration loadingDelay;
  final Duration minimumFeedbackDuration;
  final Duration successDuration;
  final ValueGetter<bool>? _value;

  @override
  State<ToggleSwitchComponent> createState() => _ToggleSwitchComponentState();
}

class _ToggleSwitchComponentState extends State<ToggleSwitchComponent> {
  bool? _selected;
  _ToggleSwitchExecutionState _executionState =
      _ToggleSwitchExecutionState.idle;
  Timer? _loadingTimer;
  Timer? _successTimer;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _selected = _currentValue();
  }

  @override
  void didUpdateWidget(covariant ToggleSwitchComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newValue = _currentValue();
    if (_selected != newValue && !_isUpdating) {
      _selected = newValue;
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _successTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final enabled = widget.onChanged != null && !_isUpdating;
    final selected = _selected ?? widget.selected;
    final platform = Theme.of(context).platform;
    final isDarwin =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showStateIcon) ...[
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: AnimatedSwitcher(
              duration: Motion.standard,
              switchInCurve: Curves.easeInExpo,
              switchOutCurve: Curves.easeOutExpo,
              child: ExcludeSemantics(child: _stateIcon(colors)),
            ),
          ),
        ],
        SizedBox(
          height: 31,
          child: FittedBox(
            fit: BoxFit.contain,
            child: isDarwin
                ? CupertinoSwitch(
                    activeTrackColor: colors.primary,
                    inactiveTrackColor: colors.fillDark,
                    thumbColor: colors.specialWhite,
                    value: selected,
                    onChanged: enabled ? _handleChanged : null,
                  )
                : Switch(
                    inactiveTrackColor: colors.fillDark,
                    activeTrackColor: colors.primary,
                    activeThumbColor: colors.specialWhite,
                    inactiveThumbColor: colors.primary,
                    trackOutlineColor: WidgetStateColor.resolveWith(
                      (_) => enabled ? colors.primary : colors.strokeFaint,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: selected,
                    onChanged: enabled ? _handleChanged : null,
                  ),
          ),
        ),
      ],
    );
  }

  bool _currentValue() => widget._value?.call() ?? widget.selected;

  Widget _stateIcon(ColorTokens colors) {
    return switch (_executionState) {
      _ToggleSwitchExecutionState.idle => const SizedBox(
        key: ValueKey('toggle-state-idle'),
        width: 24,
      ),
      _ToggleSwitchExecutionState.inProgress => SizedBox.square(
        key: const ValueKey('toggle-state-loading'),
        dimension: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.strokeDark,
        ),
      ),
      _ToggleSwitchExecutionState.successful => Padding(
        key: const ValueKey('toggle-state-success'),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Icon(Icons.check_outlined, size: 22, color: colors.primary),
      ),
    };
  }

  Future<void> _handleChanged(bool nextValue) async {
    if (!mounted || widget.onChanged == null) {
      return;
    }

    _loadingTimer?.cancel();
    _successTimer?.cancel();
    setState(() {
      _isUpdating = true;
      if (widget.optimisticallyUpdate) {
        _selected = nextValue;
      }
      _executionState = _ToggleSwitchExecutionState.idle;
    });

    _loadingTimer = Timer(widget.loadingDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _executionState = _ToggleSwitchExecutionState.inProgress;
      });
    });

    final stopwatch = Stopwatch()..start();
    try {
      await widget.onChanged!(nextValue);
    } catch (_) {
      await _waitForMinimumFeedback(stopwatch);
      _loadingTimer?.cancel();
      if (!mounted) {
        return;
      }
      setState(() {
        _selected = _currentValue();
        _executionState = _ToggleSwitchExecutionState.idle;
        _isUpdating = false;
      });
      return;
    }

    await _waitForMinimumFeedback(stopwatch);
    _loadingTimer?.cancel();
    if (!mounted) {
      return;
    }

    final confirmedValue = _currentValue();
    setState(() {
      _selected = confirmedValue;
      if (confirmedValue == nextValue &&
          _executionState == _ToggleSwitchExecutionState.inProgress) {
        _executionState = _ToggleSwitchExecutionState.successful;
        _successTimer = Timer(widget.successDuration, () {
          if (!mounted) {
            return;
          }
          setState(() {
            _executionState = _ToggleSwitchExecutionState.idle;
          });
        });
      } else {
        _executionState = _ToggleSwitchExecutionState.idle;
      }
      _isUpdating = false;
    });
  }

  Future<void> _waitForMinimumFeedback(Stopwatch stopwatch) async {
    final remaining =
        widget.minimumFeedbackDuration -
        Duration(milliseconds: stopwatch.elapsedMilliseconds);
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }
}

enum _ToggleSwitchExecutionState { idle, inProgress, successful }
