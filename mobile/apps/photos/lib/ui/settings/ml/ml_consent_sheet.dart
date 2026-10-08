import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/notification_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/ml_service.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/ui/common/web_page.dart";
import "package:styled_text/styled_text.dart";

Future<bool> showMLConsentSheet(BuildContext context) async {
  Future<void>? enabling;
  await showBottomSheetComponent<void>(
    context: context,
    builder: (_) =>
        _MLConsentSheet(onEnable: () => enabling = enableMLConsent()),
  );
  await enabling?.catchError((Object _) {});
  if (hasGrantedMLConsent) {
    return true;
  }
  await markMLConsentPromptSeen();
  return false;
}

Future<void> enableMLConsent() async {
  await setMLConsent(true);
  memoriesCacheService.queueUpdateCache();
  Bus.instance.fire(NotificationEvent());
  await MLService.instance.init();
  await SemanticSearchService.instance.init();
  unawaited(MLService.instance.runAllML(force: true));
}

Future<void> markMLConsentPromptSeen() async {
  if (hasGrantedMLConsent) {
    return;
  }
  await localSettings.setHasSeenMLEnablingBanner();
  Bus.instance.fire(NotificationEvent());
}

class _MLConsentSheet extends StatefulWidget {
  const _MLConsentSheet({required this.onEnable});

  final Future<void> Function() onEnable;

  @override
  State<_MLConsentSheet> createState() => _MLConsentSheetState();
}

class _MLConsentSheetState extends State<_MLConsentSheet> {
  bool _hasAcknowledged = false;
  bool _isEnabling = false;

  Future<void> _enable() async {
    setState(() => _isEnabling = true);
    try {
      await widget.onEnable();
    } finally {
      if (mounted) {
        setState(() => _isEnabling = false);
      }
    }
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: context.strings.machineLearning,
      closeTooltip: context.strings.close,
      borderSide: BorderSide(color: context.componentColors.strokeDark),
      actionsTopSpacing: Spacing.xxl,
      content: Flexible(
        fit: FlexFit.loose,
        child: IgnorePointer(
          ignoring: _isEnabling,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Image.asset(
                    "assets/ducky_ml.png",
                    height: 150,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),
                const MLConsentDescription(),
                const SizedBox(height: 20),
                MLConsentAcknowledgement(
                  selected: _hasAcknowledged,
                  onChanged: () {
                    setState(() => _hasAcknowledged = !_hasAcknowledged);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        ButtonComponent(
          label: context.strings.mlConsent,
          isDisabled: !_hasAcknowledged,
          onTap: _enable,
        ),
      ],
    );
  }
}

class MLConsentDescription extends StatelessWidget {
  const MLConsentDescription({super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyles.body.copyWith(
      color: context.componentColors.textLight,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paragraph in context.strings.mlConsentDescription.split(
          "\n\n",
        )) ...[Text(paragraph, style: textStyle), const SizedBox(height: 8)],
        StyledText(
          text: context.strings.mlConsentPrivacyDetails,
          style: textStyle,
          tags: {
            'policy': StyledTextActionTag(
              (String? text, Map<String?, String?> attrs) =>
                  _openPrivacyPolicy(context),
              style: textStyle.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: textStyle.color,
              ),
            ),
          },
        ),
      ],
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return WebPage(
            context.strings.privacyPolicyTitle,
            "https://ente.com/privacy",
          );
        },
      ),
    );
  }
}

class MLConsentAcknowledgement extends StatelessWidget {
  const MLConsentAcknowledgement({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxComponent(selected: selected, onChanged: (_) => onChanged()),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.strings.mlConsentConfirmation,
              style: TextStyles.body.copyWith(
                color: context.componentColors.textLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
