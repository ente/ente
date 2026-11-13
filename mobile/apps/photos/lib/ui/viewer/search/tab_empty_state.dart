import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/backup_flow_helper.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/empty_state_item_widget.dart";
import "package:photos/ui/components/models/button_type.dart";

class SearchTabEmptyState extends StatelessWidget {
  const SearchTabEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = getEnteTextTheme(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.strings.searchHint1, style: textStyle.h3Bold),
            const SizedBox(height: 24),
            EmptyStateItemWidget(context.strings.searchHint2),
            const SizedBox(height: 12),
            EmptyStateItemWidget(context.strings.searchHint3),
            const SizedBox(height: 12),
            EmptyStateItemWidget(context.strings.searchHint4),
            const SizedBox(height: 12),
            EmptyStateItemWidget(context.strings.searchHint5),
            const SizedBox(height: 32),
            ButtonWidget(
              buttonType: ButtonType.trailingIconPrimary,
              labelText: context.strings.addYourPhotosNow,
              icon: Icons.arrow_forward_outlined,
              onTap: () async {
                await handleFolderSelectionBackupFlow(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
