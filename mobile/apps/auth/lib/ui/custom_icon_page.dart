import 'dart:io';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/all_icon_data.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/ui/utils/icon_utils.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomIconPage extends StatefulWidget {
  const CustomIconPage({
    super.key,
    required this.allIcons,
    required this.currentIcon,
  });

  final Map<String, AllIconData> allIcons;
  final String currentIcon;

  @override
  State<CustomIconPage> createState() => _CustomIconPageState();
}

class _CustomIconPageState extends State<CustomIconPage> {
  final bool _autoFocusSearch = PreferenceService.instance
      .shouldAutoFocusOnSearchBar();
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  late final FocusNode searchBoxFocusNode;
  late Map<String, AllIconData> _filteredIcons;
  bool _showSearchBox = false;
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _filteredIcons = widget.allIcons;
    _showSearchBox = _autoFocusSearch;
    searchBoxFocusNode = FocusNode();
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    _textController.dispose();
    searchBoxFocusNode.dispose();
    _scrollController.dispose();
    ServicesBinding.instance.keyboard.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Semantics(
      container: true,
      identifier: 'auth_custom_icon_page',
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          child: AppBarComponent(
            title: context.l10n.chooseIcon,
            controller: _scrollController,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: Semantics(
                  button: true,
                  identifier: 'auth_icon_search_toggle',
                  child: IconButtonComponent(
                    variant: IconButtonComponentVariant.unfilled,
                    tooltip: context.l10n.search,
                    icon: Icon(
                      _showSearchBox ? Icons.close : Icons.search,
                      size: IconSizes.medium,
                    ),
                    onTap: _toggleSearch,
                  ),
                ),
              ),
            ],
            slivers: [
              if (_showSearchBox)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      0,
                      Spacing.lg,
                      Spacing.xl,
                    ),
                    child: Semantics(
                      textField: true,
                      identifier: 'auth_icon_search',
                      child: TextInputComponent(
                        controller: _textController,
                        focusNode: searchBoxFocusNode,
                        hintText: context.l10n.searchHint,
                        autofocus: _autoFocusSearch,
                        isClearable: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        prefix: Icon(
                          Icons.search,
                          size: IconSizes.small,
                          color: colors.textLight,
                        ),
                        onChanged: (value) {
                          _searchText = value;
                          _applyFilteringAndRefresh();
                        },
                      ),
                    ),
                  ),
                ),
              if (_filteredIcons.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      context.l10n.noResult,
                      style: TextStyles.body.copyWith(color: colors.textLight),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.xl,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: (MediaQuery.sizeOf(context).width ~/ 104)
                          .clamp(2, 8),
                      crossAxisSpacing: Spacing.sm,
                      mainAxisSpacing: Spacing.sm,
                      mainAxisExtent: 104,
                    ),
                    itemCount: _filteredIcons.length,
                    itemBuilder: _buildIconChoice,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconChoice(BuildContext context, int index) {
    final colors = context.componentColors;
    final title = _filteredIcons.keys.elementAt(index);
    final iconData = _filteredIcons[title]!;
    final selected = title.toLowerCase() == widget.currentIcon.toLowerCase();
    final iconWidget = _buildIcon(context, title, iconData);

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      identifier: 'auth_icon_choice',
      child: Material(
        color: selected ? colors.primaryLight : colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(iconData),
          child: Container(
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colors.primary : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Column(
              children: [
                Expanded(child: Center(child: iconWidget)),
                const SizedBox(height: Spacing.sm),
                Text(
                  '${title[0].toUpperCase()}${title.substring(1)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyles.mini.copyWith(color: colors.textBase),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context, String title, AllIconData iconData) {
    final iconPath = iconData.type == IconType.simpleIcon
        ? 'assets/simple-icons/icons/${simpleIconAssetStem(title, iconData.slug)}.svg'
        : 'assets/custom-icons/icons/${iconData.slug ?? title}.svg';
    return IconUtils.instance.getSVGIcon(
      iconPath,
      title,
      iconData.color,
      40,
      context,
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearchBox = !_showSearchBox;
      if (_showSearchBox) {
        searchBoxFocusNode.requestFocus();
      } else {
        _textController.clear();
        _searchText = '';
        _applyFiltering();
      }
    });
  }

  void _applyFilteringAndRefresh() {
    setState(_applyFiltering);
  }

  void _applyFiltering() {
    if (_searchText.isEmpty) {
      _filteredIcons = widget.allIcons;
      return;
    }
    final query = _searchText.toLowerCase();
    _filteredIcons = {
      for (final entry in widget.allIcons.entries)
        if (entry.key.toLowerCase().contains(query)) entry.key: entry.value,
    };
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
    }

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final primaryFocus = FocusManager.instance.primaryFocus;
    final isEditableTextFocused = primaryFocus?.context?.widget is EditableText;
    if (isEditableTextFocused && !searchBoxFocusNode.hasFocus) return false;

    if (event is! KeyDownEvent) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isModifierPressed = Platform.isMacOS || Platform.isIOS
        ? pressed.any(
            {
              LogicalKeyboardKey.metaLeft,
              LogicalKeyboardKey.meta,
              LogicalKeyboardKey.metaRight,
            }.contains,
          )
        : pressed.any(
            {
              LogicalKeyboardKey.controlLeft,
              LogicalKeyboardKey.control,
              LogicalKeyboardKey.controlRight,
            }.contains,
          );

    if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
      if (!_showSearchBox) _toggleSearch();
      _textController.clear();
      _searchText = '';
      _applyFilteringAndRefresh();
      searchBoxFocusNode.requestFocus();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _showSearchBox) {
      _toggleSearch();
      return true;
    }
    return false;
  }
}
