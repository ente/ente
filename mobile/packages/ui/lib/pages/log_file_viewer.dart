import 'dart:io';
import 'dart:math';

import 'package:ente_components/components/popup_menu_component.dart';
import 'package:ente_logging/logging.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _foregroundSessionMessage = 'Starting app in foreground';

class LogFileViewer extends StatefulWidget {
  const LogFileViewer(this.file, {super.key});

  final File file;

  @override
  State<LogFileViewer> createState() => _LogFileViewerState();
}

class _LogFileViewerState extends State<LogFileViewer> {
  final _itemPositionsListener = ItemPositionsListener.create();
  final _itemScrollController = ItemScrollController();
  final _scrollMetrics = ValueNotifier((extent: 1.0, position: 1.0));
  final _entries = <LogFileEntry>[];
  Future<void>? _activeLoad;
  late final LogFileReader _reader;
  int _generation = 0;
  bool _loadFailed = false;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isSearching = false;
  bool _needsMatchJump = false;
  int _matchIndex = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reader = LogFileReader(widget.file);
    _itemPositionsListener.itemPositions.addListener(_handleItemPositions);
    _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _itemPositionsListener.itemPositions.removeListener(_handleItemPositions);
    _scrollMetrics.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    final generation = ++_generation;
    setState(() {
      _loadFailed = false;
      _isLoading = true;
      _isRefreshing = true;
    });
    final activeLoad = _activeLoad;
    if (activeLoad != null) await activeLoad;
    if (!mounted || generation != _generation) return;

    try {
      await _reader.reset();
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries.clear();
        _matchIndex = 0;
        _needsMatchJump = _query.isNotEmpty;
        _isLoading = _reader.hasMore;
        _isRefreshing = false;
      });
      await _loadOlder();
      if (_query.isNotEmpty) await _loadAllEntries();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadOlder() {
    if (_isRefreshing || _loadFailed || !_reader.hasMore) {
      return Future.value();
    }
    final activeLoad = _activeLoad;
    if (activeLoad != null) return activeLoad;

    final generation = _generation;
    late final Future<void> load;
    load = _performLoad(generation).whenComplete(() {
      if (identical(_activeLoad, load)) _activeLoad = null;
    });
    _activeLoad = load;
    return load;
  }

  Future<void> _performLoad(int generation) async {
    setState(() => _isLoading = true);
    try {
      final entries = await _reader.readPreviousPage();
      if (!mounted || generation != _generation) return;
      setState(() => _entries.addAll(entries));
      _jumpToFirstMatchIfNeeded();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAllEntries() async {
    final generation = _generation;
    while (mounted &&
        generation == _generation &&
        _isSearching &&
        _query.isNotEmpty &&
        !_isRefreshing &&
        !_loadFailed &&
        _reader.hasMore) {
      await _loadOlder();
    }
  }

  void _handleItemPositions() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final oldestVisible = positions
        .map((position) => position.index)
        .reduce(max);
    if (_entries.length - oldestVisible < 5) _loadOlder();

    final logPositions = positions.where(
      (position) => position.index < _entries.length,
    );
    if (logPositions.isEmpty) return;
    final newestVisible = logPositions
        .map((position) => position.index)
        .reduce(min);
    final oldestLogVisible = logPositions
        .map((position) => position.index)
        .reduce(max);
    final denominator = max(_entries.length - 1, 1);
    _scrollMetrics.value = (
      extent: ((oldestLogVisible - newestVisible + 1) / _entries.length).clamp(
        0.04,
        1.0,
      ),
      position:
          1 -
          ((newestVisible + oldestLogVisible) / 2 / denominator).clamp(0, 1),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _needsMatchJump = false;
        _matchIndex = 0;
        _query = '';
      }
    });
  }

  void _moveToMatch(int offset, List<int> matches) {
    setState(() => _matchIndex = (_matchIndex + offset) % matches.length);
    _scrollToEntry(matches[_matchIndex]);
  }

  void _jumpToFirstMatchIfNeeded() {
    if (!_needsMatchJump || _query.isEmpty) return;
    final matches = _matchingEntryIndices(
      RegExp(RegExp.escape(_query), caseSensitive: false),
    );
    if (matches.isEmpty) return;
    _needsMatchJump = false;
    _scrollToEntry(matches.first);
  }

  List<int> _matchingEntryIndices(RegExp searchPattern) {
    return [
      for (var index = 0; index < _entries.length; index++)
        if (searchPattern.hasMatch(_entries[index].text)) index,
    ];
  }

  List<int> _sessionEntryIndices() {
    return [
      for (var index = 0; index < _entries.length; index++)
        if (_entries[index].isForegroundSession) index,
    ];
  }

  void _scrollToEntry(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(index: index, alignment: 0.5);
    });
  }

  String _formatSessionTime(BuildContext context, LogFileEntry entry) {
    final date = entry.timestamp?.toLocal();
    if (date == null) return _foregroundSessionMessage;
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatCompactDate(date)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  Future<List<EntePopupMenuOption<int>>> _sessionOptions() async {
    final generation = _generation;
    while (mounted &&
        generation == _generation &&
        !_isRefreshing &&
        !_loadFailed &&
        _reader.hasMore) {
      await _loadOlder();
    }
    if (!mounted || generation != _generation) return [];
    return [
      for (final index in _sessionEntryIndices())
        EntePopupMenuOption(
          value: index,
          label: _formatSessionTime(context, _entries[index]),
          leadingWidget: const Icon(Icons.play_circle_outline, size: 18),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final searchPattern = _query.isEmpty
        ? null
        : RegExp(RegExp.escape(_query), caseSensitive: false);
    final matches = searchPattern == null
        ? const <int>[]
        : _matchingEntryIndices(searchPattern);
    final sessions = _sessionEntryIndices();
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: _isSearching
            ? TextField(
                autofocus: true,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: context.strings.search,
                  suffixText: _query.isEmpty
                      ? null
                      : matches.isEmpty
                      ? '0'
                      : '${_matchIndex + 1}/${matches.length}',
                ),
                onChanged: (query) {
                  setState(() {
                    _matchIndex = 0;
                    _needsMatchJump = query.isNotEmpty;
                    _query = query;
                  });
                  if (query.isNotEmpty) _loadAllEntries();
                  _jumpToFirstMatchIfNeeded();
                },
              )
            : Text(context.strings.todaysLogs),
        actions: [
          if (_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: context.strings.previous,
              onPressed: matches.length > 1
                  ? () => _moveToMatch(1, matches)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: context.strings.next,
              onPressed: matches.length > 1
                  ? () => _moveToMatch(-1, matches)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: _toggleSearch,
            ),
          ] else ...[
            if (sessions.length > 1 || (!_loadFailed && _reader.hasMore))
              EntePopupMenuButton<int>(
                optionsBuilder: _sessionOptions,
                onSelected: _scrollToEntry,
                child: Tooltip(
                  message: context.strings.logs,
                  child: const SizedBox.square(
                    dimension: kMinInteractiveDimension,
                    child: Icon(Icons.history),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: context.strings.search,
              onPressed: _toggleSearch,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _refresh,
            ),
          ],
        ],
      ),
      body: _buildLogList(context, searchPattern, sessions),
    );
  }

  Widget _buildLogList(
    BuildContext context,
    RegExp? searchPattern,
    List<int> sessions,
  ) {
    if (_loadFailed && _entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.strings.somethingWentWrong),
            TextButton(onPressed: _refresh, child: Text(context.strings.retry)),
          ],
        ),
      );
    }

    if (_entries.isEmpty) {
      if (_isLoading) return const EnteLoadingWidget();
      return Center(child: Text(context.strings.noResultsFound));
    }

    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
      fontWeight: FontWeight.w400,
      height: 1.35,
    );
    return SafeArea(
      top: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SelectionArea(
            child: ScrollablePositionedList.builder(
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 18, 16),
              itemCount: _entries.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _entries.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: EnteLoadingWidget()),
                  );
                }
                return _buildLogEntry(
                  context,
                  _entries[index],
                  searchPattern,
                  style,
                );
              },
            ),
          ),
          Positioned(
            top: 4,
            right: 0,
            bottom: 4,
            width: 14,
            child: _LogScrollbar(
              itemCount: _entries.length,
              metrics: _scrollMetrics,
              sessionIndices: sessions,
              onJump: _scrollToEntry,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(
    BuildContext context,
    LogFileEntry entry,
    RegExp? searchPattern,
    TextStyle? style,
  ) {
    if (entry.isForegroundSession) {
      final colors = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Divider(color: colors.outlineVariant)),
            const SizedBox(width: 8),
            Icon(Icons.play_circle_outline, size: 16, color: colors.primary),
            const SizedBox(width: 4),
            Text(
              _formatSessionTime(context, entry),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 8),
            Expanded(child: Divider(color: colors.outlineVariant)),
          ],
        ),
      );
    }

    return searchPattern == null
        ? Text(entry.text, style: style)
        : Text.rich(
            _highlightMatches(context, entry.text, searchPattern, style),
          );
  }

  TextSpan _highlightMatches(
    BuildContext context,
    String text,
    RegExp searchPattern,
    TextStyle? style,
  ) {
    final spans = <TextSpan>[];
    final colors = Theme.of(context).colorScheme;
    final highlightStyle = TextStyle(
      backgroundColor: colors.primaryContainer,
      color: colors.onPrimaryContainer,
    );
    var start = 0;
    for (final match in searchPattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: highlightStyle,
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(style: style, children: spans);
  }
}

extension on LogFileEntry {
  bool get isForegroundSession =>
      loggerName == 'main' && message == _foregroundSessionMessage;
}

class _LogScrollbar extends StatelessWidget {
  const _LogScrollbar({
    required this.itemCount,
    required this.metrics,
    required this.sessionIndices,
    required this.onJump,
  });

  final int itemCount;
  final ValueListenable<({double extent, double position})> metrics;
  final List<int> sessionIndices;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: metrics,
      builder: (context, value, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final thumbHeight = min(height, max(32.0, height * value.extent));
            final thumbTop = (height - thumbHeight) * value.position;
            final colors = Theme.of(context).colorScheme;

            void jumpTo(Offset position) {
              final fraction = (position.dy / height).clamp(0.0, 1.0);
              onJump(((1 - fraction) * (itemCount - 1)).round());
            }

            return MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => jumpTo(details.localPosition),
                onVerticalDragStart: (details) => jumpTo(details.localPosition),
                onVerticalDragUpdate: (details) =>
                    jumpTo(details.localPosition),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 2,
                        color: colors.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    for (final index in sessionIndices)
                      Positioned(
                        top: (height - 2) * (1 - index / max(itemCount - 1, 1)),
                        right: 1,
                        child: Container(
                          width: 5,
                          height: 1,
                          color: colors.primary.withValues(alpha: 0.8),
                        ),
                      ),
                    Positioned(
                      top: thumbTop,
                      right: 0,
                      child: Container(
                        width: 5,
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
