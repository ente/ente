import 'dart:math';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/actions_bar_widget.dart';
import 'package:ente_auth/ui/components/code_selection_actions_widget.dart';
import 'package:ente_auth/ui/components/components_constants.dart';
import "package:ente_auth/ui/components/divider_widget.dart";
import 'package:flutter/material.dart';

class BottomActionBarWidget extends StatelessWidget {
  final Code code;
  final VoidCallback? onCancel;
  final Color? backgroundColor;
  final VoidCallback? onShare;
  final VoidCallback? onPin;
  final VoidCallback? onShowQR;
  final VoidCallback? onEdit;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final VoidCallback? onTrashed;
  final bool showPin;

  const BottomActionBarWidget({
    required this.code,
    this.onCancel,
    this.showPin = true,
    this.backgroundColor,
    super.key,
    this.onShare,
    this.onPin,
    this.onShowQR,
    this.onEdit,
    this.onRestore,
    this.onDelete,
    this.onTrashed,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final widthOfScreen = MediaQuery.of(context).size.width;
    final colorScheme = getEnteColorScheme(context);
    final double leftRightPadding = min(
      widthOfScreen > restrictedMaxWidth
          ? (widthOfScreen - restrictedMaxWidth) / 2
          : 0,
      20,
    );
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.backgroundElevated2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      padding: EdgeInsets.only(
        top: 4,
        bottom: bottomPadding,
        right: leftRightPadding,
        left: leftRightPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          CodeSelectionActionsWidget(
            code: code,
            showPin: showPin,
            onShare: onShare,
            onPin: onPin,
            onShowQR: onShowQR,
            onEdit: onEdit,
            onRestore: onRestore,
            onDelete: onDelete,
            onTrashed: onTrashed,
          ),
          const DividerWidget(dividerType: DividerType.bottomBar),
          ActionBarWidget(code: code, onCancel: onCancel),
          // const SizedBox(height: 2)
        ],
      ),
    );
  }
}
