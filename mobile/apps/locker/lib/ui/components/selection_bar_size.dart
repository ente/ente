import 'package:flutter/material.dart';

class SelectionBarSize extends StatefulWidget {
  final Widget child;
  final ValueChanged<double>? onHeightChanged;

  const SelectionBarSize({
    required this.child,
    this.onHeightChanged,
    super.key,
  });

  @override
  State<SelectionBarSize> createState() => _SelectionBarSizeState();
}

class _SelectionBarSizeState extends State<SelectionBarSize> {
  final _sizeKey = GlobalKey();
  bool _scheduled = false;

  void _reportHeight() {
    if (widget.onHeightChanged == null || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final height = _sizeKey.currentContext?.size?.height;
      if (height != null) widget.onHeightChanged!(height);
    });
  }

  @override
  Widget build(BuildContext context) {
    _reportHeight();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _reportHeight();
        return true;
      },
      child: SizeChangedLayoutNotifier(key: _sizeKey, child: widget.child),
    );
  }
}
