import 'dart:async';

import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/onboarding/view/common/tag_chip.dart';
import 'package:ente_auth/store/code_display_store.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

class EditTagsPage extends StatefulWidget {
  const EditTagsPage({super.key});

  @override
  State<EditTagsPage> createState() => _EditTagsPageState();
}

class _EditTagsPageState extends State<EditTagsPage> {
  final _scrollController = ScrollController();
  late final StreamSubscription<CodesUpdatedEvent> _subscription;
  List<String> _tags = [];
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _subscription = Bus.instance.on<CodesUpdatedEvent>().listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final codes = await CodeStore.instance.getAllCodes(sortCodes: false);
    final tags = await CodeDisplayStore.instance.getAllTags(allCodes: codes);
    final counts = <String, int>{};
    for (final code in codes) {
      if (code.hasError || code.isTrashed) continue;
      for (final tag in code.display.tags.toSet()) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _counts = counts;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() => _tags.insert(newIndex, _tags.removeAt(oldIndex)));
    unawaited(CodeDisplayStore.instance.saveTagOrder(_tags));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.componentColors.backgroundBase,
      body: AppBarComponent(
        title: pendingTranslation("Edit tags"),
        controller: _scrollController,
        slivers: [
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              sliver: SliverReorderableList(
                itemCount: _tags.length,
                onReorderItem: _reorder,
                itemBuilder: (context, index) {
                  final tag = _tags[index];
                  return _TagRow(
                    key: ValueKey(tag),
                    tag: tag,
                    count: _counts[tag] ?? 0,
                    index: index,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    super.key,
    required this.tag,
    required this.count,
    required this.index,
  });

  final String tag;
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: MenuComponent(
        title: tag,
        subtitle: count == 1
            ? pendingTranslation("1 code")
            : pendingTranslation("$count codes"),
        onTap: () => showTagActions(context, tag),
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle_rounded),
        ),
      ),
    );
  }
}
