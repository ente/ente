import "dart:async";
import "dart:typed_data";

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_legacy/components/legacy_kit_card_preview.dart";
import "package:ente_legacy/components/legacy_kit_recovery_wait_time_sheet.dart";
import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_legacy/pages/legacy_congratulations_page.dart";
import "package:ente_legacy/services/legacy_kit_local_settings.dart";
import "package:ente_legacy/services/legacy_kit_pdf_service.dart";
import "package:ente_legacy/services/legacy_kit_service.dart";
import "package:ente_rust/ente_rust.dart" as rust;
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/alert_bottom_sheet.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:share_plus/share_plus.dart";

typedef LegacyKitAuthenticator =
    Future<bool> Function(BuildContext context, String reason);

const _partNameStyle = TextStyle(
  fontFamily: TextStyles.outfitFontFamily,
  package: TextStyles.fontPackage,
  fontSize: 24,
  fontWeight: FontWeight.w700,
  height: 28 / 24,
);

enum _KitMenuAction { revoke }

class ShareLegacyKitPage extends StatefulWidget {
  final LegacyKit kit;
  final List<LegacyKitShare>? initialShares;
  final String accountEmail;
  final LegacyKitAuthenticator? authenticator;
  final VoidCallback? onChanged;
  final bool isCreationFlow;
  final bool isFirstLegacyKit;

  const ShareLegacyKitPage({
    required this.kit,
    required this.accountEmail,
    this.initialShares,
    this.authenticator,
    this.onChanged,
    this.isCreationFlow = false,
    this.isFirstLegacyKit = false,
    super.key,
  });

  @override
  State<ShareLegacyKitPage> createState() => _ShareLegacyKitPageState();
}

class _ShareLegacyKitPageState extends State<ShareLegacyKitPage> {
  late LegacyKit _kit = widget.kit;
  late List<LegacyKitShare>? _shares = widget.initialShares;
  final Set<int> _sharedParts = {};
  int? _expandedIndex;
  bool _sharing = false;

  bool get _hasSharedAllParts =>
      _kit.parts.isNotEmpty &&
      _kit.parts.every((part) => _sharedParts.contains(part.index));

  @override
  void initState() {
    super.initState();
    if (widget.isCreationFlow) {
      _expandedIndex = _firstUnsharedSectionIndex();
    }
    unawaited(_restoreShareProgress());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final contentBottomPadding = widget.isCreationFlow
        ? (_expandedIndex == null ? 0.0 : Spacing.xxl)
        : MediaQuery.paddingOf(context).bottom + Spacing.xxl;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: context.strings.shareYourLegacy,
        backgroundColor: colors.backgroundBase,
        actions: [
          EntePopupMenuButton<_KitMenuAction>(
            optionsBuilder: () => [
              EntePopupMenuOption(
                value: _KitMenuAction.revoke,
                label: context.strings.revokeLegacyKit,
                labelColor: colors.warning,
                leadingWidget: HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: colors.warning,
                ),
              ),
            ],
            onSelected: (action) => switch (action) {
              _KitMenuAction.revoke => _revokeKit(),
            },
          ),
        ],
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              contentBottomPadding,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.strings.shareLegacyDescription,
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                  if (_kit.hasActiveRecoverySession) ...[
                    const SizedBox(height: Spacing.xl),
                    _RecoveryBanner(
                      session: _kit.activeRecoverySession!,
                      onBlockRecovery: _blockRecovery,
                    ),
                  ],
                  const SizedBox(height: Spacing.xxl),
                  for (var i = 0; i < _kit.parts.length; i++) _partSection(i),
                  if (_hasSharedAllParts) ...[
                    const SizedBox(height: Spacing.xxl),
                    const _LegacyKitAllSetBanner(),
                  ],
                  if (!widget.isCreationFlow) ...[
                    const SizedBox(height: Spacing.xxl),
                    Text(
                      context.strings.settings,
                      style: TextStyles.display3.copyWith(
                        color: colors.textBase,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    MenuComponent(
                      title: context.strings.accountRecovery,
                      subtitle: formatLegacyKitNoticePeriod(
                        context,
                        _kit.noticePeriodInHours,
                      ),
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedRefresh,
                      ),
                      onTap: _editRecoveryWaitTime,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.isCreationFlow
          ? ColoredBox(
              color: colors.backgroundBase,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.xl,
                ),
                child: ButtonComponent(
                  label: context.strings.continueLabel,
                  size: ButtonComponentSize.large,
                  shouldSurfaceExecutionStates: false,
                  onTap: () {
                    if (widget.isFirstLegacyKit) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) =>
                              const LegacyCongratulationsPage(),
                        ),
                      );
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
            )
          : null,
    );
  }

  Widget _partSection(int index) {
    final colors = context.componentColors;
    final part = _kit.parts[index];
    final isExpanded = _expandedIndex == index;
    final isLast = index == _kit.parts.length - 1;
    final cardBottomInset = isLast ? Spacing.sm : Spacing.lg;
    return Stack(
      children: [
        if (!isLast || isExpanded)
          Positioned(
            left: 11.5,
            top: 37,
            bottom: isExpanded ? cardBottomInset : 3,
            child: Container(width: 1, color: colors.strokeDark),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StepBadge(
                  number: index + 1,
                  isShared: _sharedParts.contains(part.index),
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _expandedIndex = isExpanded ? null : index;
                    }),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            part.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _partNameStyle.copyWith(
                              color: colors.textBase,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(Spacing.sm),
                          child: Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: colors.textLighter,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                _SharePill(onTap: () => _sharePart(part, index)),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeInOutCubic,
              firstCurve: Curves.easeOutQuart,
              secondCurve: Curves.easeInQuart,
              alignment: Alignment.topCenter,
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: SizedBox(
                width: double.infinity,
                height: isLast ? 0 : 40,
              ),
              secondChild: Padding(
                padding: EdgeInsets.only(
                  left: 40,
                  top: Spacing.sm,
                  bottom: cardBottomInset,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (MediaQuery.sizeOf(context).width * 0.68).clamp(
                        240.0,
                        300.0,
                      ),
                    ),
                    child: LegacyKitCardPreview(kit: _kit, part: part),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<List<LegacyKitShare>?> _ensureShares() async {
    final existing = _shares;
    if (existing != null) {
      return existing;
    }
    if (!await _authenticate(context.strings.authToManageLegacyKit)) {
      return null;
    }
    if (!mounted) {
      return null;
    }
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final shares = await LegacyKitService.instance.downloadShares(_kit.id);
      await dialog.hide();
      if (mounted) {
        setState(() {
          _shares = shares;
        });
      }
      return shares;
    } catch (_) {
      await dialog.hide();
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
      return null;
    }
  }

  Future<void> _sharePart(LegacyKitPart part, int sectionIndex) async {
    if (_sharing) {
      return;
    }
    if (_expandedIndex != sectionIndex) {
      setState(() {
        _expandedIndex = sectionIndex;
      });
    }
    _sharing = true;
    try {
      final shares = await _ensureShares();
      if (shares == null || !mounted) {
        return;
      }
      final share = shares.firstWhereOrNull(
        (share) => share.shareIndex == part.index,
      );
      if (share == null) {
        showShortToast(context, context.strings.somethingWentWrong);
        return;
      }
      final dialog = createProgressDialog(context, context.strings.pleaseWait);
      await dialog.show();
      final Uint8List bytes;
      try {
        bytes = await const LegacyKitPdfService().buildRecoverySheet(
          accountEmail: widget.accountEmail,
          recoveryUrl: _kit.legacyUrl,
          share: share,
          allShares: shares,
        );
        await dialog.hide();
      } catch (_) {
        await dialog.hide();
        if (mounted) {
          showShortToast(context, context.strings.somethingWentWrong);
        }
        return;
      }
      if (!mounted) {
        return;
      }
      final size = MediaQuery.sizeOf(context);
      final ShareResult result;
      try {
        result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: "application/pdf")],
            fileNameOverrides: ["${_fileNameForPart(part)}.pdf"],
            sharePositionOrigin: Offset.zero & size,
          ),
        );
      } catch (_) {
        if (mounted) {
          showShortToast(context, context.strings.somethingWentWrong);
        }
        return;
      }
      if (result.status == ShareResultStatus.dismissed || !mounted) {
        return;
      }
      setState(() {
        _sharedParts.add(part.index);
        _expandedIndex = _firstUnsharedSectionIndex();
      });
      await _markPartShared(part.index);
    } finally {
      _sharing = false;
    }
  }

  Future<void> _editRecoveryWaitTime() async {
    final authReason = context.strings.authToManageLegacyKit;
    if (_kit.hasActiveRecoverySession) {
      await showAlertBottomSheet(
        context,
        title: context.strings.cannotUpdateRecoveryTime,
        message: context.strings.cannotUpdateRecoveryTimeMessage,
        assetPath: "assets/warning-blue.png",
      );
      return;
    }
    final selectedDays = await showLegacyKitRecoveryWaitTimeSheet(
      context,
      selectedDays: _kit.noticePeriodInHours ~/ 24,
    );
    if (selectedDays == null || selectedDays * 24 == _kit.noticePeriodInHours) {
      return;
    }
    if (!await _authenticate(authReason)) {
      return;
    }
    if (!mounted) {
      return;
    }
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    Object? updateError;
    try {
      await LegacyKitService.instance.updateRecoveryNotice(
        kitId: _kit.id,
        noticePeriodInHours: selectedDays * 24,
      );
      if (mounted) {
        setState(() {
          _kit = LegacyKit(
            id: _kit.id,
            noticePeriodInHours: selectedDays * 24,
            legacyUrl: _kit.legacyUrl,
            parts: _kit.parts,
            createdAt: _kit.createdAt,
            updatedAt: _kit.updatedAt,
            activeRecoverySession: _kit.activeRecoverySession,
          );
        });
      }
      try {
        await _refreshKit();
      } catch (_) {
        // The update has succeeded; the parent page will refresh as well.
      }
      widget.onChanged?.call();
    } catch (e) {
      updateError = e;
    } finally {
      await dialog.hide();
    }
    if (!mounted) {
      return;
    }
    if (updateError == null) {
      showShortToast(context, context.strings.recoveryTimeUpdated);
    } else if (updateError is rust.ContactsError_ActiveRecoverySession) {
      try {
        await _refreshKit();
      } catch (_) {
        // The backend rejection is enough to explain the failed update.
      }
      if (!mounted) {
        return;
      }
      await showAlertBottomSheet(
        context,
        title: context.strings.cannotUpdateRecoveryTime,
        message: context.strings.cannotUpdateRecoveryTimeMessage,
        assetPath: "assets/warning-blue.png",
      );
    } else {
      showShortToast(context, context.strings.somethingWentWrong);
    }
  }

  Future<void> _revokeKit() async {
    final confirmed = await _showConfirmationSheet(
      title: context.strings.revokeLegacyKit,
      message: context.strings.deleteLegacyKitMessage,
      actionLabel: context.strings.revokeLegacyKit,
      onConfirm: () async {
        if (!await _authenticate(context.strings.authToManageLegacyKit)) {
          return false;
        }
        try {
          await LegacyKitService.instance.deleteKit(_kit.id);
          return true;
        } catch (_) {
          if (mounted) {
            showShortToast(context, context.strings.somethingWentWrong);
          }
          return false;
        }
      },
    );
    if (confirmed) {
      await _clearShareProgress();
      widget.onChanged?.call();
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _markPartShared(int partIndex) async {
    try {
      await LegacyKitLocalSettings.markPartShared(_kit.id, partIndex);
    } catch (_) {
      // Local progress must not affect sharing the kit.
    }
  }

  Future<void> _clearShareProgress() async {
    try {
      await LegacyKitLocalSettings.clearShareProgress(_kit.id);
    } catch (_) {
      // Local progress must not affect revoking the kit.
    }
  }

  Future<void> _restoreShareProgress() async {
    try {
      final savedPartIndexes =
          await LegacyKitLocalSettings.getSharedPartIndexes(_kit.id);
      final validPartIndexes = _kit.parts.map((part) => part.index).toSet();
      savedPartIndexes.retainAll(validPartIndexes);
      if (mounted) {
        setState(() {
          _sharedParts.addAll(savedPartIndexes);
          _expandedIndex = _firstUnsharedSectionIndex();
        });
      }
    } catch (_) {
      // Missing local progress means every part starts unchecked.
    }
  }

  int? _firstUnsharedSectionIndex() {
    final index = _kit.parts.indexWhere(
      (part) => !_sharedParts.contains(part.index),
    );
    return index < 0 ? null : index;
  }

  Future<void> _blockRecovery() async {
    final confirmed = await _showConfirmationSheet(
      title: context.strings.rejectRecovery,
      message: context.strings.blockLegacyKitRecoveryMessage,
      actionLabel: context.strings.rejectRecovery,
      onConfirm: () async {
        if (!await _authenticate(context.strings.authToManageLegacyKit)) {
          return false;
        }
        try {
          await LegacyKitService.instance.blockRecovery(_kit.id);
          return true;
        } catch (_) {
          if (mounted) {
            showShortToast(context, context.strings.somethingWentWrong);
          }
          return false;
        }
      },
    );
    if (confirmed) {
      try {
        await _refreshKit();
      } catch (_) {
        // The parent page refresh via onChanged covers a failed local refresh.
      }
      widget.onChanged?.call();
    }
  }

  Future<bool> _showConfirmationSheet({
    required String title,
    required String message,
    required String actionLabel,
    required Future<bool> Function() onConfirm,
  }) async {
    Future<bool>? pending;
    final confirmed = await showBottomSheetComponent<bool>(
      context: context,
      builder: (context) => BottomSheetComponent(
        title: title,
        message: message,
        illustration: Image.asset("assets/warning-grey.png"),
        actions: [
          ButtonComponent(
            label: actionLabel,
            variant: ButtonComponentVariant.critical,
            size: ButtonComponentSize.large,
            shouldShowSuccessState: false,
            onTap: () async {
              final operation = pending ??= onConfirm();
              final succeeded = await operation;
              if (!succeeded) {
                if (identical(pending, operation)) {
                  pending = null;
                }
                return;
              }
              if (context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      ),
    );
    if (confirmed == true) {
      return true;
    }
    return pending != null && await pending!;
  }

  Future<bool> _authenticate(String reason) async {
    final authenticator = widget.authenticator;
    if (authenticator == null) {
      return true;
    }
    return authenticator(context, reason);
  }

  Future<void> _refreshKit() async {
    final refreshed = await LegacyKitService.instance.getKits();
    final current = refreshed.where((kit) => kit.id == _kit.id).firstOrNull;
    if (current != null && mounted) {
      setState(() {
        _kit = current;
      });
    }
  }

  String _fileNameForPart(LegacyKitPart part) {
    final sanitized = part.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"""[\\/:*?"<>|\x00-\x1F]+"""), "-")
        .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
        .replaceAll(RegExp(r"-+"), "-")
        .replaceAll(RegExp(r"^-+|-+$"), "");
    final name = sanitized.isEmpty ? "part-${part.index}" : sanitized;
    return "ente-legacy-kit-$name";
  }
}

class _LegacyKitAllSetBanner extends StatelessWidget {
  const _LegacyKitAllSetBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 114),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.blue,
        borderRadius: Radii.buttonBorder,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.52,
              child: SvgPicture.asset(
                "assets/legacy_kit_all_set_pattern.svg",
                package: "ente_legacy",
                fit: BoxFit.fill,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.strings.legacyKitAllSetTitle,
                  textAlign: TextAlign.center,
                  style: TextStyles.display3.copyWith(
                    color: colorTokensLight.backgroundBase,
                    fontSize: 16,
                    height: 22 / 16,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  context.strings.legacyKitAllSetDescription,
                  textAlign: TextAlign.center,
                  style: TextStyles.mini.copyWith(
                    color: colors.specialWhite.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  final int number;
  final bool isShared;

  const _StepBadge({required this.number, required this.isShared});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    if (isShared) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: colors.blue, shape: BoxShape.circle),
        child: Center(
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedTick02,
            color: colors.specialWhite,
            size: 14,
          ),
        ),
      );
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: colors.blueLightHover,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Center(
        child: Text(
          "$number",
          style: TextStyles.mini.copyWith(color: colors.blue),
        ),
      ),
    );
  }
}

class _SharePill extends StatelessWidget {
  final Future<void> Function() onTap;

  const _SharePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Material(
      color: colors.fillBase,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => unawaited(onTap()),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.strings.share,
                style: TextStyles.mini.copyWith(
                  color: colors.specialContentReverse,
                ),
              ),
              const SizedBox(width: Spacing.xs),
              HugeIcon(
                icon: HugeIcons.strokeRoundedShare05,
                color: colors.specialContentReverse,
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryBanner extends StatefulWidget {
  final LegacyKitRecoverySession session;
  final Future<void> Function() onBlockRecovery;

  const _RecoveryBanner({required this.session, required this.onBlockRecovery});

  @override
  State<_RecoveryBanner> createState() => _RecoveryBannerState();
}

class _RecoveryBannerState extends State<_RecoveryBanner> {
  late DateTime _availableAt = _resolveAvailableAt();

  @override
  void didUpdateWidget(_RecoveryBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.waitTill != widget.session.waitTill) {
      _availableAt = _resolveAvailableAt();
    }
  }

  DateTime _resolveAvailableAt() {
    return DateTime.now().add(Duration(microseconds: widget.session.waitTill));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final availableAt = DateFormat.yMMMMd().add_jm().format(_availableAt);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: colors.warningLight,
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedAlert02,
                color: colors.warning,
                size: 18,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  context.strings.legacyKitRecoveryAttemptInProgress,
                  style: TextStyles.bodyBold.copyWith(color: colors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.strings.legacyKitRecoveryAttemptMessage(availableAt),
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: Spacing.md),
          ButtonComponent(
            label: context.strings.rejectRecovery,
            variant: ButtonComponentVariant.critical,
            size: ButtonComponentSize.large,
            shouldSurfaceExecutionStates: false,
            onTap: widget.onBlockRecovery,
          ),
        ],
      ),
    );
  }
}
