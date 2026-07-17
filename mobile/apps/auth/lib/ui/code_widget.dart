import 'dart:async';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:clipboard/clipboard.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/events/multi_select_action_requested_event.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/onboarding/view/setup_enter_secret_key_page.dart';
import 'package:ente_auth/services/local_backup_service.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/store/code_display_store.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/code_timer_progress.dart';
import 'package:ente_auth/ui/code_widget_layout_utils.dart';
import 'package:ente_auth/ui/components/auth_qr_dialog.dart';
import 'package:ente_auth/ui/components/note_dialog.dart';
import 'package:ente_auth/ui/home/shortcuts.dart';
import 'package:ente_auth/ui/share/code_share.dart';
import 'package:ente_auth/ui/utils/icon_utils.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';
import 'package:move_to_background/move_to_background.dart';

class CodeWidget extends StatefulWidget {
  final Code code;
  final bool isCompactMode;
  final CodeSortKey? sortKey;
  final bool isReordering;
  final bool enableDesktopContextActions;
  final List<Code> Function()? selectedCodesBuilder;
  final FocusNode? focusNode;

  const CodeWidget(
    this.code, {
    super.key,
    required this.isCompactMode,
    this.sortKey,
    this.isReordering = false,
    this.enableDesktopContextActions = false,
    this.selectedCodesBuilder,
    this.focusNode,
  });

  @override
  State<CodeWidget> createState() => _CodeWidgetState();
}

class _CodeWidgetState extends State<CodeWidget> {
  Timer? _everySecondTimer;
  final ValueNotifier<String> _currentCode = ValueNotifier<String>("");
  final ValueNotifier<String> _nextCode = ValueNotifier<String>("");
  final Logger logger = Logger("_CodeWidgetState");
  bool _isInitialized = false;
  late bool hasConfiguredAccount;
  late bool _shouldShowLargeIcon;
  late bool _hideCode;
  bool isMaskingEnabled = false;
  int _codeTimeStep = -1;
  int lastRefreshTime = 0;
  bool ignorePin = false;
  // Cached localization string to avoid BuildContext access in async callbacks
  String _errorText = 'Error';
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    isMaskingEnabled = PreferenceService.instance.shouldHideCodes();

    _hideCode = isMaskingEnabled;
    _everySecondTimer = Timer.periodic(const Duration(milliseconds: 500), (
      Timer t,
    ) {
      if (!mounted) return;
      int newStep = 0;
      int epochSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (widget.code.type != Type.hotp) {
        newStep = ((epochSeconds.round()) ~/ widget.code.period).floor();
      } else {
        newStep = widget.code.counter;
      }
      if (_codeTimeStep != newStep ||
          epochSeconds - lastRefreshTime > widget.code.period) {
        String newCode = _getCurrentOTP();
        if (newCode != _currentCode.value && mounted) {
          _currentCode.value = newCode;
          if (widget.code.type.isTOTPCompatible) {
            _nextCode.value = _getNextTotp();
          }
          _codeTimeStep = newStep;
          lastRefreshTime = epochSeconds;
        }
      }
    });
    hasConfiguredAccount = Configuration.instance.hasConfiguredAccount();
  }

  @override
  void dispose() {
    _everySecondTimer?.cancel();
    _currentCode.dispose();
    _nextCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ignorePin = widget.sortKey != null && widget.sortKey == CodeSortKey.manual;
    if (isMaskingEnabled != PreferenceService.instance.shouldHideCodes()) {
      isMaskingEnabled = PreferenceService.instance.shouldHideCodes();
      _hideCode = isMaskingEnabled;
    }
    _shouldShowLargeIcon = PreferenceService.instance.shouldShowLargeIcons();
    if (!_isInitialized) {
      _currentCode.value = _getCurrentOTP();
      if (widget.code.type.isTOTPCompatible) {
        _nextCode.value = _getNextTotp();
      }
      _isInitialized = true;
    }
    final l10n = context.l10n;
    // Cache the localized error label for use in timer callbacks
    _errorText = l10n.error;

    Widget getCardContents(AppLocalizations l10n, {required bool isSelected}) {
      final colorScheme = getEnteColorScheme(context);
      final isSelectionActive =
          CodeDisplayStore.instance.isSelectionModeActive.value;

      return Stack(
        children: [
          if (!ignorePin && widget.code.isPinned)
            Align(
              alignment: Alignment.topRight,
              child: CustomPaint(
                painter: PinBgPainter(color: colorScheme.pinnedBgColor),
                size: widget.isCompactMode
                    ? const Size(24, 24)
                    : const Size(39, 39),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.code.type.isTOTPCompatible)
                SizedBox(
                  height: widget.isCompactMode ? 1 : 3,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeIn,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: isSelectionActive
                        ? const SizedBox.shrink()
                        : CodeTimerProgress(
                            key: ValueKey('period_${widget.code.period}'),
                            period: widget.code.period,
                            isCompactMode: widget.isCompactMode,
                            timeOffsetInMilliseconds: PreferenceService.instance
                                .timeOffsetInMilliSeconds(),
                          ),
                  ),
                ),
              widget.isCompactMode
                  ? const SizedBox(height: 4)
                  : const SizedBox(height: 28),
              Row(
                children: [
                  _shouldShowLargeIcon ? _getIcon() : const SizedBox.shrink(),
                  Expanded(
                    child: Column(
                      children: [
                        _getTopRow(isSelected: isSelected),
                        widget.isCompactMode
                            ? const SizedBox.shrink()
                            : const SizedBox(height: 4),
                        _getBottomRow(l10n),
                      ],
                    ),
                  ),
                ],
              ),
              widget.isCompactMode
                  ? const SizedBox(height: 4)
                  : const SizedBox(height: 32),
            ],
          ),
          if (!ignorePin && widget.code.isPinned) ...[
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: widget.isCompactMode
                    ? const EdgeInsets.only(right: 4, top: 4)
                    : const EdgeInsets.only(right: 6, top: 6),
                child: SvgPicture.asset(
                  "assets/svg/pin-card.svg",
                  width: widget.isCompactMode ? 8 : null,
                  height: widget.isCompactMode ? 8 : null,
                ),
              ),
            ),
          ],
        ],
      );
    }

    Widget clippedCard(AppLocalizations l10n) {
      final colorScheme = getEnteColorScheme(context);

      return ValueListenableBuilder<Set<String>>(
        valueListenable: CodeDisplayStore.instance.selectedCodeIds,
        builder: (context, selectedIds, child) {
          final isSelected = selectedIds.contains(widget.code.selectionKey);

          return Stack(
            children: [
              Actions(
                actions: {
                  CopyIntent: CallbackAction<CopyIntent>(
                    onInvoke: (intent) => _copyCurrentOTPToClipboard(),
                  ),
                  CopyNextIntent: CallbackAction<CopyNextIntent>(
                    onInvoke: (intent) {
                      if (!widget.code.type.isTOTPCompatible) {
                        showToast(context, context.l10n.notSupportedForHOTP);
                        return null;
                      }
                      _copyNextToClipboard();
                      return null;
                    },
                  ),
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isSelected
                        ? colorScheme.primary400.withValues(alpha: 0.10)
                        : Theme.of(context).colorScheme.codeCardBackgroundColor,
                    boxShadow: (widget.code.isPinned && !isSelected)
                        ? colorScheme.pinnedCardBoxShadow
                        : [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        focusNode: widget.focusNode,
                        customBorder: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        // InkWell handles focus natively.
                        canRequestFocus: true,
                        onFocusChange: (hasFocus) {
                          if (_isFocused != hasFocus) {
                            setState(() {
                              _isFocused = hasFocus;
                            });
                          }
                        },
                        onTap: () {
                          final store = CodeDisplayStore.instance;
                          if (store.isSelectionModeActive.value) {
                            store.toggleSelection(widget.code.selectionKey);
                          } else {
                            _copyCurrentOTPToClipboard();
                          }
                        },
                        onDoubleTap: isMaskingEnabled
                            ? () {
                                setState(() {
                                  _hideCode = !_hideCode;
                                });
                              }
                            : null,
                        onLongPress: widget.isReordering
                            ? null
                            : () {
                                CodeDisplayStore.instance.toggleSelection(
                                  widget.code.selectionKey,
                                );
                              },
                        child: getCardContents(l10n, isSelected: isSelected),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    opacity: isSelected ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.primary400,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    final bool isIOS = !kIsWeb && Platform.isIOS;
    final Widget content = Container(
      margin: widget.isCompactMode
          ? const EdgeInsets.only(left: 16, right: 16, bottom: 6, top: 6)
          : const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 8),
      child: Builder(
        builder: (context) {
          if (PlatformDetector.isDesktop()) {
            return ValueListenableBuilder<Set<String>>(
              valueListenable: CodeDisplayStore.instance.selectedCodeIds,
              builder: (context, selectedIds, _) {
                final menuEntries = _buildContextMenuEntries(
                  context,
                  l10n,
                  selectedIds,
                );

                return ContextMenuRegion(
                  contextMenu: ContextMenu(
                    entries: menuEntries,
                    padding: const EdgeInsets.all(8.0),
                  ),
                  child: clippedCard(l10n),
                );
              },
            );
          }

          return clippedCard(l10n);
        },
      ),
    );
    final Widget scaledContent;
    if (isIOS) {
      final double scale = capCodeWidgetTextScaleForIOS(
        MediaQuery.textScalerOf(context).scale(1.0),
      );
      scaledContent = MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: content,
      );
    } else {
      scaledContent = content;
    }

    return Semantics(
      container: true,
      identifier: 'auth_code_item',
      label: [
        widget.code.issuer,
        widget.code.account,
      ].where((value) => value.isNotEmpty).join(', '),
      child: scaledContent,
    );
  }

  Widget _getBottomRow(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: _currentCode,
              builder: (context, value, child) {
                return Material(
                  type: MaterialType.transparency,
                  child: AutoSizeText(
                    _getFormattedCode(value),
                    style: TextStyle(fontSize: widget.isCompactMode ? 14 : 24),
                    maxLines: 1,
                    textDirection: TextDirection.ltr,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          widget.code.type.isTOTPCompatible
              ? IgnorePointer(
                  ignoring:
                      CodeDisplayStore.instance.isSelectionModeActive.value,
                  child: GestureDetector(
                    onTap: () {
                      _copyNextToClipboard();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          l10n.nextTotpTitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ValueListenableBuilder<String>(
                          valueListenable: _nextCode,
                          builder: (context, value, child) {
                            return Material(
                              type: MaterialType.transparency,
                              child: Text(
                                _getFormattedCode(value),
                                style: TextStyle(
                                  fontSize: widget.isCompactMode ? 12 : 18,
                                  color: Colors.grey,
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                )
              : IgnorePointer(
                  ignoring:
                      CodeDisplayStore.instance.isSelectionModeActive.value,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l10n.nextTotpTitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      InkWell(
                        onTap: _onNextHotpTapped,
                        child: const Icon(
                          Icons.forward_outlined,
                          size: 32,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _getTopRow({required bool isSelected}) {
    final colorScheme = getEnteColorScheme(context);
    final bool isCompactMode = widget.isCompactMode;
    final double indicatorSize = isCompactMode ? 16 : 20;
    const double indicatorPadding = 4;
    final double indicatorSlotWidth = indicatorSize + indicatorPadding;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      width: isSelected ? indicatorSlotWidth : 0,
                      alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeIn,
                        switchOutCurve: Curves.easeOut,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: isSelected
                            ? Align(
                                key: const ValueKey('selected-indicator'),
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: indicatorPadding,
                                  ),
                                  child: SizedBox(
                                    width: indicatorSize,
                                    height: indicatorSize,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          color: colorScheme.primary400,
                                          size: indicatorSize,
                                        ),
                                        Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: isCompactMode ? 8 : 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        safeDecode(widget.code.issuer).trim(),
                        style: isCompactMode
                            ? Theme.of(context).textTheme.bodyMedium
                            : Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (!isCompactMode) const SizedBox(height: 2),
                Text(
                  safeDecode(widget.code.account).trim(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: isCompactMode ? 12 : 12,
                    color: Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              (widget.code.hasSynced != null && widget.code.hasSynced!) ||
                      !hasConfiguredAccount
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.sync_disabled,
                      size: 20,
                      color: Colors.amber,
                    ),
              const SizedBox(width: 12),
              _shouldShowLargeIcon ? const SizedBox.shrink() : _getIcon(),
            ],
          ),
        ],
      ),
    );
  }

  List<ContextMenuEntry> _buildContextMenuEntries(
    BuildContext context,
    AppLocalizations l10n,
    Set<String> selectedIds,
  ) {
    if (!widget.enableDesktopContextActions) {
      return _buildSingleSelectionMenu(l10n);
    }

    final multiEntries = _buildMultiSelectionContextMenu(l10n, selectedIds);
    if (multiEntries != null) {
      return multiEntries;
    }

    return _buildSingleSelectionMenu(l10n);
  }

  List<ContextMenuEntry> _buildSingleSelectionMenu(AppLocalizations l10n) {
    final entries = <ContextMenuEntry>[];

    _addNonTrashedMenuItems(entries, l10n);
    _addEditOrRestoreMenuItem(entries, l10n);
    entries.add(const MenuDivider());
    _addDeleteOrTrashMenuItem(entries, l10n);

    return entries;
  }

  /// Adds menu items for non-trashed codes (share, QR, tag, notes, pin).
  void _addNonTrashedMenuItems(
    List<ContextMenuEntry> entries,
    AppLocalizations l10n,
  ) {
    if (widget.code.isTrashed) return;

    if (widget.code.type.canShareCodes) {
      entries.add(
        MenuItem(
          label: l10n.share,
          icon: Icons.adaptive.share_outlined,
          onSelected: () => _onSharePressed(null),
        ),
      );
    }

    entries.add(
      MenuItem(
        label: l10n.qr,
        icon: Icons.qr_code_2_outlined,
        onSelected: () => _onShowQrPressed(null),
      ),
    );

    entries.add(
      MenuItem(
        label: l10n.addTag,
        icon: Icons.local_offer_outlined,
        onSelected: () {
          CodeDisplayStore.instance.selectedCodeIds.value = {
            widget.code.selectionKey,
          };
          _triggerMultiAction(MultiSelectAction.addTag);
        },
      ),
    );

    if (widget.code.note.isNotEmpty) {
      entries.add(
        MenuItem(
          label: l10n.notes,
          icon: Icons.notes_outlined,
          onSelected: () => _onShowNotesPressed(null),
        ),
      );
    }

    if (!ignorePin) {
      entries.add(
        MenuItem(
          label: widget.code.isPinned ? l10n.unpinText : l10n.pinText,
          icon: widget.code.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          onSelected: () => _onPinPressed(null),
        ),
      );
    }
  }

  /// Adds edit menu item for non-trashed codes or restore for trashed codes.
  void _addEditOrRestoreMenuItem(
    List<ContextMenuEntry> entries,
    AppLocalizations l10n,
  ) {
    if (!widget.code.isTrashed) {
      entries.add(
        MenuItem(
          label: l10n.edit,
          icon: Icons.edit,
          onSelected: () => _onEditPressed(null),
        ),
      );
    } else {
      entries.add(
        MenuItem(
          label: l10n.restore,
          icon: Icons.restore_outlined,
          onSelected: () => _onRestoreClicked(null),
        ),
      );
    }
  }

  /// Adds delete (forever) or trash menu item based on code state.
  void _addDeleteOrTrashMenuItem(
    List<ContextMenuEntry> entries,
    AppLocalizations l10n,
  ) {
    entries.add(
      MenuItem(
        label: widget.code.isTrashed ? l10n.delete : l10n.trash,
        value: l10n.delete,
        icon: widget.code.isTrashed ? Icons.delete_forever : Icons.delete,
        onSelected: () => widget.code.isTrashed
            ? _onDeletePressed(null)
            : _onTrashPressed(null),
      ),
    );
  }

  List<ContextMenuEntry>? _buildMultiSelectionContextMenu(
    AppLocalizations l10n,
    Set<String> selectedIds,
  ) {
    if (selectedIds.length <= 1 ||
        !selectedIds.contains(widget.code.selectionKey)) {
      return null;
    }

    final selectedCodes = widget.selectedCodesBuilder?.call() ?? const <Code>[];
    if (selectedCodes.isEmpty) {
      return null;
    }

    final entries = <ContextMenuEntry>[];
    final bool allTrashed = selectedCodes.every((code) => code.isTrashed);

    if (allTrashed) {
      _addTrashedMultiSelectMenuItems(entries, l10n);
      return entries.isEmpty ? null : entries;
    }

    _addPinMenuItems(entries, l10n, selectedCodes);
    _addTagAndTrashMenuItems(entries, l10n);

    return entries.isEmpty ? null : entries;
  }

  /// Adds menu items for multi-selected trashed codes (restore, delete).
  void _addTrashedMultiSelectMenuItems(
    List<ContextMenuEntry> entries,
    AppLocalizations l10n,
  ) {
    entries.add(
      MenuItem(
        label: l10n.restore,
        icon: Icons.restore_outlined,
        onSelected: () => _triggerMultiAction(MultiSelectAction.restore),
      ),
    );
    entries.add(
      MenuItem(
        label: l10n.delete,
        icon: Icons.delete_forever,
        onSelected: () => _triggerMultiAction(MultiSelectAction.deleteForever),
      ),
    );
  }

  /// Adds pin/unpin menu items based on selection pin state.
  void _addPinMenuItems(
    List<ContextMenuEntry> entries,
    AppLocalizations l10n,
    List<Code> selectedCodes,
  ) {
    final bool allPinned = selectedCodes.every((code) => code.isPinned);
    final bool anyPinned = selectedCodes.any((code) => code.isPinned);
    final bool isMixedPinned = anyPinned && !allPinned;

    if (isMixedPinned) {
      // Show both pin and unpin options for mixed state
      entries.add(
        MenuItem(
          label: l10n.pinText,
          icon: Icons.push_pin_outlined,
          onSelected: () => _triggerMultiAction(MultiSelectAction.pinToggle),
        ),
      );
      entries.add(
        MenuItem(
          label: l10n.unpinText,
          icon: Icons.push_pin,
          onSelected: () => _triggerMultiAction(MultiSelectAction.unpin),
        ),
      );
    } else {
      // Show single toggle option for uniform state
      entries.add(
        MenuItem(
          label: allPinned ? l10n.unpinText : l10n.pinText,
          icon: allPinned ? Icons.push_pin : Icons.push_pin_outlined,
          onSelected: () => _triggerMultiAction(MultiSelectAction.pinToggle),
        ),
      );
    }
  }

  /// Adds tag and trash menu items for multi-selection.
  void _addTagAndTrashMenuItems(
    List<ContextMenuEntry> entries,
    AppLocalizations l10n,
  ) {
    entries.add(
      MenuItem(
        label: l10n.addTag,
        icon: Icons.local_offer_outlined,
        onSelected: () => _triggerMultiAction(MultiSelectAction.addTag),
      ),
    );

    entries.add(
      MenuItem(
        label: l10n.trash,
        icon: Icons.delete_outline,
        onSelected: () => _triggerMultiAction(MultiSelectAction.trash),
      ),
    );
  }

  void _triggerMultiAction(MultiSelectAction action) {
    Bus.instance.fire(MultiSelectActionRequestedEvent(action));
  }

  Widget _getIcon() {
    final String iconData;
    if (widget.code.display.isCustomIcon) {
      iconData = widget.code.display.iconID;
    } else {
      iconData = widget.code.issuer;
    }
    return Padding(
      padding: _shouldShowLargeIcon
          ? EdgeInsets.only(left: widget.isCompactMode ? 12 : 16)
          : const EdgeInsets.all(0),
      child: IconUtils.instance.getIcon(
        context,
        safeDecode(iconData).trim(),
        width: widget.isCompactMode
            ? (_shouldShowLargeIcon ? 32 : 24)
            : (_shouldShowLargeIcon ? 42 : 24),
      ),
    );
  }

  void _copyCurrentOTPToClipboard() {
    _copyToClipboard(
      _getCurrentOTP(),
      confirmationMessage: context.l10n.copiedToClipboard,
    );
    _updateCodeMetadata().ignore();
  }

  void _copyNextToClipboard() {
    _copyToClipboard(
      _getNextTotp(),
      confirmationMessage: context.l10n.copiedNextToClipboard,
    );
    _updateCodeMetadata().ignore();
  }

  void _onNextHotpTapped() {
    if (widget.code.type == Type.hotp) {
      CodeStore.instance
          .addCode(
            widget.code.copyWith(counter: widget.code.counter + 1),
            shouldSync: true,
          )
          .ignore();
    }
  }

  Future<void> _updateCodeMetadata() async {
    if (widget.sortKey == null) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        if (widget.sortKey == CodeSortKey.mostFrequentlyUsed ||
            widget.sortKey == CodeSortKey.recentlyUsed) {
          final display = widget.code.display;
          final Code code = widget.code.copyWith(
            display: display.copyWith(
              tapCount: display.tapCount + 1,
              lastUsedAt: DateTime.now().microsecondsSinceEpoch,
            ),
          );
          unawaited(CodeStore.instance.addCode(code));
        }
      }
    });
  }

  void _copyToClipboard(
    String content, {
    required String confirmationMessage,
  }) async {
    final shouldMinimizeOnCopy = PreferenceService.instance
        .shouldMinimizeOnCopy();

    await FlutterClipboard.copy(content);
    if (!mounted) return;
    showToast(context, confirmationMessage);
    if (Platform.isAndroid && shouldMinimizeOnCopy) {
      // ignore: unawaited_futures
      MoveToBackground.moveTaskToBack();
    }
  }

  Future<void> _onShowNotesPressed([bool? pop]) async {
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    await showNotesDialog(context, widget.code.note);
  }

  Future<void> _onEditPressed([bool? pop]) async {
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    bool isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(context, context.l10n.editCodeAuthMessage);
    if (!isAuthSuccessful) {
      return;
    }
    if (!mounted) return;
    final Code? code = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return SetupEnterSecretKeyPage(code: widget.code);
        },
      ),
    );
    if (code != null) {
      await CodeStore.instance.addCode(code);
    }
  }

  Future<void> _onShowQrPressed([bool? pop]) async {
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    bool isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(context, context.l10n.showQRAuthMessage);
    if (!isAuthSuccessful) {
      return;
    }
    final qrData = widget.code.rawData
        .replaceAll('algorithm=Algorithm.', 'algorithm=')
        .replaceAll('algorithm=sha1', 'algorithm=SHA1')
        .replaceAll('algorithm=sha256', 'algorithm=SHA256')
        .replaceAll('algorithm=sha512', 'algorithm=SHA512');

    if (!mounted) return;
    await showBottomSheetComponent<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) {
        return AuthQrDialog(
          data: qrData,
          title: widget.code.issuer,
          subtitle: widget.code.account,
          shareFileName: 'ente_auth_qr_${widget.code.account}.png',
          shareText: 'QR code for ${widget.code.account}',
          dialogTitle: context.l10n.qrCode,
          shareButtonText: context.l10n.share,
        );
      },
    );
  }

  Future<void> _onSharePressed([bool? pop]) async {
    if (!widget.code.type.canShareCodes) {
      return;
    }
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    bool isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(context, context.l10n.authenticateGeneric);
    if (!isAuthSuccessful) {
      return;
    }
    if (!mounted) return;
    showShareDialog(context, widget.code);
  }

  Future<void> _onPinPressed([bool? pop]) async {
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    bool currentlyPinned = widget.code.isPinned;
    final display = widget.code.display;
    final Code code = widget.code.copyWith(
      display: display.copyWith(pinned: !currentlyPinned),
    );
    if (!mounted) return;
    unawaited(
      CodeStore.instance.addCode(code).then((value) {
        if (!mounted) return;
        showToast(
          context,
          !currentlyPinned
              ? context.l10n.pinnedCodeMessage(widget.code.issuer)
              : context.l10n.unpinnedCodeMessage(widget.code.issuer),
        );
      }),
    );
  }

  void _onDeletePressed([bool? pop]) async {
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    if (!widget.code.isTrashed) {
      showToast(context, 'Code can only be deleted from trash');
      return;
    }
    bool isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.deleteCodeAuthMessage,
        );
    if (!isAuthSuccessful) {
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).requestFocus();
    final l10n = context.l10n;
    if (!mounted) return;
    await showChoiceActionSheet(
      context,
      title: l10n.deleteCodeTitle,
      body: l10n.deleteCodeMessage,
      firstButtonLabel: l10n.delete,
      isCritical: true,
      firstButtonOnTap: () async {
        try {
          await CodeStore.instance.removeCode(widget.code);
          LocalBackupService.instance.triggerDailyBackupIfNeeded().ignore();
        } catch (e, s) {
          logger.severe('Failed to delete code', e, s);
          if (!mounted) return;
          showGenericErrorDialog(context: context, error: e).ignore();
        }
      },
    );
  }

  void _onTrashPressed([bool? pop]) async {
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    if (widget.code.isTrashed) {
      showToast(context, 'Code is already trashed');
      return;
    }
    bool isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.deleteCodeAuthMessage,
        );
    if (!isAuthSuccessful) {
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).requestFocus();
    final l10n = context.l10n;
    final String issuerAccount = widget.code.account.isNotEmpty
        ? '${widget.code.issuer} (${widget.code.account})'
        : widget.code.issuer;
    if (!mounted) return;
    await showChoiceActionSheet(
      context,
      title: l10n.trashCode,
      body: l10n.trashCodeMessage(issuerAccount),
      firstButtonLabel: l10n.trash,
      isCritical: true,
      firstButtonOnTap: () async {
        try {
          final display = widget.code.display;
          final Code code = widget.code.copyWith(
            display: display.copyWith(trashed: true),
          );
          await CodeStore.instance.addCode(code);
        } catch (e) {
          logger.severe('Failed to trash code: ${e.toString()}');
          if (!mounted) return;
          showGenericErrorDialog(context: context, error: e).ignore();
        }
      },
    );
  }

  void _onRestoreClicked([bool? pop]) async {
    if (mounted && pop == true) {
      Navigator.of(context).pop();
    }
    if (!widget.code.isTrashed) {
      showToast(context, 'Code is already restored');
      return;
    }
    FocusScope.of(context).requestFocus();

    try {
      final display = widget.code.display;
      final Code code = widget.code.copyWith(
        display: display.copyWith(trashed: false),
      );
      await CodeStore.instance.addCode(code);
    } catch (e) {
      logger.severe('Failed to restore code: ${e.toString()}');
      if (mounted) {
        showGenericErrorDialog(context: context, error: e).ignore();
      }
    }
  }

  String _getCurrentOTP() {
    try {
      return getOTP(widget.code);
    } catch (e) {
      // Avoid accessing BuildContext from async timer callbacks
      return _errorText;
    }
  }

  String _getNextTotp() {
    try {
      assert(widget.code.type.isTOTPCompatible);
      return getNextTotp(widget.code);
    } catch (e) {
      // Avoid accessing BuildContext from async timer callbacks
      return _errorText;
    }
  }

  String _getFormattedCode(String code) {
    if (_hideCode) {
      // replace all digits with •
      code = code.replaceAll(RegExp(r'\S'), '•');
    }
    switch (code.length) {
      case 6:
        return "${code.substring(0, 3)} ${code.substring(3, 6)}";
      case 7:
        return "${code.substring(0, 3)} ${code.substring(3, 4)} ${code.substring(4, 7)}";
      case 8:
        return "${code.substring(0, 3)} ${code.substring(3, 5)} ${code.substring(5, 8)}";
      case 9:
        return "${code.substring(0, 3)} ${code.substring(3, 6)} ${code.substring(6, 9)}";
      default:
        return code;
    }
  }
}

class PinBgPainter extends CustomPainter {
  final Color color;
  final PaintingStyle paintingStyle;

  PinBgPainter({
    this.color = Colors.black,
    this.paintingStyle = PaintingStyle.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..style = paintingStyle;

    canvas.drawPath(getTrianglePath(size.width, size.height), paint);
  }

  Path getTrianglePath(double x, double y) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(x, 0)
      ..lineTo(x, y)
      ..lineTo(0, 0);
  }

  @override
  bool shouldRepaint(PinBgPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.paintingStyle != paintingStyle;
  }
}
