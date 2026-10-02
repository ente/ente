import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class DocumentViewerPage extends StatelessWidget {
  const DocumentViewerPage({super.key, required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: fileName,
        actions: [
          IconButtonComponent(
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedShare08),
            variant: IconButtonComponentVariant.unfilled,
            tooltip: l10n.share,
          ),
          IconButtonComponent(
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
            variant: IconButtonComponentVariant.unfilled,
            tooltip: l10n.more,
          ),
        ],
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: AspectRatio(
                      aspectRatio: 1 / 1.414,
                      child: ColoredBox(
                        color: colors.fillLight,
                        child: Center(
                          child: Semantics(
                            label: l10n.preview,
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedFile02,
                              color: colors.textLighter,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
