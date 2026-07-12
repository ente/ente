import 'dart:ui';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/code_widget.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class ReorderCodesPage extends StatefulWidget {
  const ReorderCodesPage({super.key, required this.codes});
  final List<Code> codes;

  @override
  State<ReorderCodesPage> createState() => _ReorderCodesPageState();
}

class _ReorderCodesPageState extends State<ReorderCodesPage> {
  bool hasChanged = false;
  final logger = Logger('ReorderCodesPage');

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompactMode = PreferenceService.instance.isCompactMode();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.customOrder),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            Navigator.of(context).pop();
          },
        ),
        actions: [
          GestureDetector(
            onTap: () async {
              final hasSaved = await saveUpadedIndexes();
              if (hasSaved) {
                if (!context.mounted) return;
                Navigator.of(context).pop();
              }
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(
                context.l10n.save,
                style: TextStyle(
                  color: hasChanged
                      ? getEnteColorScheme(context).textBase
                      : getEnteColorScheme(context).strokeMuted,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        interactive: true,
        child: ReorderableListView(
          scrollController: _scrollController,
          buildDefaultDragHandles: false,
          proxyDecorator:
              (Widget child, int index, Animation<double> animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (BuildContext context, _) {
                    final animValue = Curves.easeInOut.transform(
                      animation.value,
                    );
                    final scale = lerpDouble(1, 1.05, animValue)!;
                    return Transform.scale(scale: scale, child: child);
                  },
                );
              },
          children: [
            for (final code in widget.codes)
              ReorderableDragStartListener(
                key: ValueKey('${code.hashCode}_${code.generatedID}'),
                index: widget.codes.indexOf(code),
                child: CodeWidget(
                  key: ValueKey(code.generatedID),
                  code,
                  isCompactMode: isCompactMode,
                  isReordering: true,
                ),
              ),
          ],
          onReorder: (oldIndex, newIndex) {
            updateCodeIndex(oldIndex, newIndex);
          },
        ),
      ),
    );
  }

  Future<bool> saveUpadedIndexes() async {
    final result = await CodeStore.instance.saveUpadedIndexes(widget.codes);
    return result;
  }

  void updateCodeIndex(int oldIndex, int newIndex) {
    setState(() {
      // Adjust index when moving down the list
      // oldIndex = 2, newIndex = 0
      if (oldIndex < newIndex) newIndex -= 1;
      final Code code = widget.codes.removeAt(oldIndex);
      widget.codes.insert(newIndex, code);
      hasChanged = true;
    });
  }
}
