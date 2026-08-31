import "dart:async";
import "dart:convert";

import "package:ente_components/ente_components.dart";
import "package:ente_legacy/components/legacy_kit_recovery_wait_time_sheet.dart";
import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_legacy/pages/share_legacy_kit_page.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/buttons/dynamic_fab.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";

const _legacyKitPartNameMaxBytes = 50;

typedef CreateLegacyKit =
    Future<LegacyKitCreateResult> Function(
      List<String> partNames,
      int noticePeriodInHours,
    );

Future<void> showCreateLegacyKitPage(
  BuildContext context, {
  required String accountEmail,
  required bool isFirstLegacyKit,
  required CreateLegacyKit createKit,
  required GetLegacyKits getKits,
  required DownloadLegacyKitShares downloadShares,
  required UpdateLegacyKitRecoveryNotice updateRecoveryNotice,
  required BlockLegacyKitRecovery blockRecovery,
  required DeleteLegacyKit deleteKit,
  LegacyKitAuthenticator? authenticator,
  ValueChanged<LegacyKit>? onCreated,
  VoidCallback? onChanged,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => CreateLegacyKitPage(
        accountEmail: accountEmail,
        isFirstLegacyKit: isFirstLegacyKit,
        createKit: createKit,
        getKits: getKits,
        downloadShares: downloadShares,
        updateRecoveryNotice: updateRecoveryNotice,
        blockRecovery: blockRecovery,
        deleteKit: deleteKit,
        authenticator: authenticator,
        onCreated: onCreated,
        onChanged: onChanged,
      ),
    ),
  );
}

class CreateLegacyKitPage extends StatefulWidget {
  final String accountEmail;
  final bool isFirstLegacyKit;
  final CreateLegacyKit createKit;
  final GetLegacyKits getKits;
  final DownloadLegacyKitShares downloadShares;
  final UpdateLegacyKitRecoveryNotice updateRecoveryNotice;
  final BlockLegacyKitRecovery blockRecovery;
  final DeleteLegacyKit deleteKit;
  final LegacyKitAuthenticator? authenticator;
  final ValueChanged<LegacyKit>? onCreated;
  final VoidCallback? onChanged;

  const CreateLegacyKitPage({
    required this.accountEmail,
    required this.isFirstLegacyKit,
    required this.createKit,
    required this.getKits,
    required this.downloadShares,
    required this.updateRecoveryNotice,
    required this.blockRecovery,
    required this.deleteKit,
    this.authenticator,
    this.onCreated,
    this.onChanged,
    super.key,
  });

  @override
  State<CreateLegacyKitPage> createState() => _CreateLegacyKitPageState();
}

class _CreateLegacyKitPageState extends State<CreateLegacyKitPage> {
  final List<TextEditingController> _controllers = List.generate(
    3,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(3, (_) => FocusNode());
  int _selectedDays = 7;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: context.strings.setupYourLegacy,
        backgroundColor: colors.backgroundBase,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.xxl,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.strings.setupLegacyDescription,
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                  const SizedBox(height: Spacing.lg),
                  for (var index = 0; index < _controllers.length; index++) ...[
                    TextInputComponent(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      hintText: context.strings.addTrustedPerson,
                      inputFormatters: [
                        _Utf8LengthLimitingTextInputFormatter(
                          _legacyKitPartNameMaxBytes,
                        ),
                      ],
                      textCapitalization: TextCapitalization.words,
                      textInputAction: index < _controllers.length - 1
                          ? TextInputAction.next
                          : TextInputAction.done,
                      shouldUnfocusOnClearOrSubmit:
                          index == _controllers.length - 1,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (index < _controllers.length - 1)
                      const SizedBox(height: Spacing.md),
                  ],
                  const SizedBox(height: Spacing.xxl),
                  Text(
                    context.strings.settings,
                    style: TextStyles.display3.copyWith(color: colors.textBase),
                  ),
                  const SizedBox(height: Spacing.md),
                  MenuComponent(
                    title: context.strings.accountRecovery,
                    subtitle: formatLegacyKitNoticePeriod(
                      context,
                      _selectedDays * 24,
                    ),
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                    ),
                    onTap: _editRecoveryWaitTime,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButtonAnimator: NoScalingAnimation(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: SizedBox(
          width: double.infinity,
          child: ButtonComponent(
            label: context.strings.createKit,
            size: ButtonComponentSize.large,
            isDisabled: !_isValid,
            shouldSurfaceExecutionStates: true,
            shouldShowSuccessState: false,
            onTap: _submit,
          ),
        ),
      ),
    );
  }

  Future<void> _editRecoveryWaitTime() async {
    final selectedDays = await showLegacyKitRecoveryWaitTimeSheet(
      context,
      selectedDays: _selectedDays,
      showCancellationWarning: false,
      requireChange: false,
    );
    if (selectedDays != null && mounted) {
      setState(() {
        _selectedDays = selectedDays;
      });
    }
  }

  bool get _isValid {
    final names = _partNames;
    return names.length == 3 && names.toSet().length == 3;
  }

  List<String> get _partNames {
    return _controllers
        .map((controller) => controller.text.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    try {
      final authenticator = widget.authenticator;
      if (authenticator != null &&
          !await authenticator(
            context,
            context.strings.authToManageLegacyKit,
          )) {
        return;
      }
      if (!mounted) {
        return;
      }
      final result = await widget.createKit(_partNames, _selectedDays * 24);
      widget.onCreated?.call(result.kit);
      if (!mounted) {
        return;
      }
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ShareLegacyKitPage(
              kit: result.kit,
              initialShares: result.shares,
              accountEmail: widget.accountEmail,
              getKits: widget.getKits,
              downloadShares: widget.downloadShares,
              updateRecoveryNotice: widget.updateRecoveryNotice,
              blockRecovery: widget.blockRecovery,
              deleteKit: widget.deleteKit,
              authenticator: widget.authenticator,
              onChanged: widget.onChanged,
              isCreationFlow: true,
              isFirstLegacyKit: widget.isFirstLegacyKit,
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    }
  }
}

class _Utf8LengthLimitingTextInputFormatter extends TextInputFormatter {
  final int maxBytes;

  _Utf8LengthLimitingTextInputFormatter(this.maxBytes) : assert(maxBytes > 0);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return utf8.encode(newValue.text).length <= maxBytes ? newValue : oldValue;
  }
}
