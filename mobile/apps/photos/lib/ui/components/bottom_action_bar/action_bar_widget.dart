import 'package:ente_components/ente_components.dart' as components;
import 'package:flutter/material.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/selected_files.dart';

class ActionBarWidget extends StatefulWidget {
  final SelectedFiles? selectedFiles;
  final VoidCallback? onCancel;

  const ActionBarWidget({
    required this.onCancel,
    this.selectedFiles,
    super.key,
  });

  @override
  State<ActionBarWidget> createState() => _ActionBarWidgetState();
}

class _ActionBarWidgetState extends State<ActionBarWidget> {
  final ValueNotifier<int> _selectedFilesNotifier = ValueNotifier(0);
  final ValueNotifier<int> _selectedOwnedFilesNotifier = ValueNotifier(0);

  //User ID will be null if the user is not logged in (links-in-app)
  final int currentUserID = Configuration.instance.getUserID() ?? -1;

  @override
  void initState() {
    super.initState();
    widget.selectedFiles?.addListener(_selectedFilesListener);
    _selectedFilesListener();
  }

  @override
  void dispose() {
    _selectedFilesNotifier.dispose();
    _selectedOwnedFilesNotifier.dispose();
    widget.selectedFiles?.removeListener(_selectedFilesListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = components.ComponentTheme.colorsOf(context);
    final miniStyle = components.TextStyles.mini.copyWith(
      color: colors.textBase,
    );
    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              flex: 1,
              child: ValueListenableBuilder(
                valueListenable: _selectedFilesNotifier,
                builder: (context, value, child) {
                  return Text(
                    _selectedOwnedFilesNotifier.value !=
                            _selectedFilesNotifier.value
                        ? AppLocalizations.of(context).selectedPhotosWithYours(
                            count: _selectedFilesNotifier.value,
                            yourCount: _selectedOwnedFilesNotifier.value,
                          )
                        : AppLocalizations.of(
                            context,
                          ).selectedPhotos(count: _selectedFilesNotifier.value),
                    style: miniStyle,
                  );
                },
              ),
            ),
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onCancel?.call();
                  },
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      AppLocalizations.of(context).cancel,
                      style: miniStyle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectedFilesListener() {
    if (widget.selectedFiles?.files.isNotEmpty ?? false) {
      _selectedFilesNotifier.value = widget.selectedFiles!.files.length;
      _selectedOwnedFilesNotifier.value = widget.selectedFiles!.files
          .where((f) => f.ownerID == null || f.ownerID! == currentUserID)
          .length;
    }
  }
}
