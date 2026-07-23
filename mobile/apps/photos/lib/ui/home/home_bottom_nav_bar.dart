import 'dart:async';

import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/tab_changed_event.dart';
import "package:photos/models/selected_albums.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/ui/tabs/nav_bar.dart';

const double _homeNavContainerHeight = 70;
const double _homeNavButtonPadding = 10;
const double _homeNavItemSpacing = 22;

class HomeBottomNavigationBar extends StatefulWidget {
  const HomeBottomNavigationBar(
    this.selectedFiles,
    this.selectedAlbums, {
    required this.selectedTabIndex,
    super.key,
  });

  final SelectedFiles selectedFiles;
  final SelectedAlbums selectedAlbums;
  final int selectedTabIndex;

  @override
  State<HomeBottomNavigationBar> createState() =>
      _HomeBottomNavigationBarState();
}

class _HomeBottomNavigationBarState extends State<HomeBottomNavigationBar> {
  static const int _searchTabIndex = 3;
  static const Duration _doubleTapWindow = Duration(milliseconds: 350);
  late StreamSubscription<TabChangedEvent> _tabChangedEventSubscription;
  int currentTabIndex = 0;
  int? _lastTapIndex;
  DateTime? _lastTapAt;

  @override
  void initState() {
    super.initState();
    currentTabIndex = widget.selectedTabIndex;
    widget.selectedFiles.addListener(_selectedFilesListener);
    widget.selectedAlbums.addListener(_selectedAlbumsListener);
    _tabChangedEventSubscription = Bus.instance.on<TabChangedEvent>().listen((
      event,
    ) {
      if (event.source != TabChangedEventSource.tabBar) {
        debugPrint(
          '${(TabChangedEvent).toString()} index changed  from '
          '$currentTabIndex to ${event.selectedIndex} via ${event.source}',
        );
        if (mounted) {
          setState(() {
            currentTabIndex = event.selectedIndex;
          });
        }
      } else if (event.source == TabChangedEventSource.tabBar &&
          currentTabIndex == event.selectedIndex) {
        // user tapped on the currently selected index on the tapBar
        Bus.instance.fire(TabDoubleTapEvent(currentTabIndex));
      }
    });
  }

  @override
  void dispose() {
    _tabChangedEventSubscription.cancel();
    widget.selectedFiles.removeListener(_selectedFilesListener);
    widget.selectedAlbums.removeListener(_selectedAlbumsListener);
    super.dispose();
  }

  void _selectedFilesListener() {
    if (mounted) {
      setState(() {});
    }
  }

  void _selectedAlbumsListener() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTabChange(int index, {String mode = 'tabChanged'}) {
    if (mode == "OnPressed") {
      _handleSearchTabDoubleTap(index);
    }
    debugPrint("_TabChanged called via method $mode");
    Bus.instance.fire(TabChangedEvent(index, TabChangedEventSource.tabBar));
  }

  void _handleSearchTabDoubleTap(int index) {
    final now = DateTime.now();
    final isRepeatTap =
        _lastTapIndex == index &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= _doubleTapWindow;
    _lastTapIndex = index;
    _lastTapAt = now;
    if (index != _searchTabIndex || !isRepeatTap) {
      return;
    }
    if (currentTabIndex != _searchTabIndex) {
      Bus.instance.fire(TabDoubleTapEvent(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool filesAreSelected = widget.selectedFiles.files.isNotEmpty;
    final bool albumsAreSelected = widget.selectedAlbums.albums.isNotEmpty;

    return SafeArea(
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: filesAreSelected || albumsAreSelected
              ? 0
              : _homeNavContainerHeight,
          child: IgnorePointer(
            ignoring: filesAreSelected || albumsAreSelected,
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _HomeNavBar(
                      selectedIndex: currentTabIndex,
                      onTabChange: (index) {
                        _onTabChange(index, mode: "OnPressed");
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNavBar extends StatelessWidget {
  const _HomeNavBar({required this.selectedIndex, required this.onTabChange});

  static const _tabs = [
    _HomeNavTab(
      semanticLabel: 'Home',
      semanticIdentifier: 'ente.photos.tab.home',
      outlineAsset: 'assets/icons/nav_bar/home_outline.svg',
      filledAsset: 'assets/icons/nav_bar/home_filled.svg',
    ),
    _HomeNavTab(
      semanticLabel: 'Albums',
      semanticIdentifier: 'ente.photos.tab.albums',
      outlineAsset: 'assets/icons/nav_bar/albums_outline.svg',
      filledAsset: 'assets/icons/nav_bar/albums_filled.svg',
    ),
    _HomeNavTab(
      semanticLabel: 'Feed',
      semanticIdentifier: 'ente.photos.tab.feed',
      outlineAsset: 'assets/icons/nav_bar/feed_outline.svg',
      filledAsset: 'assets/icons/nav_bar/feed_filled.svg',
    ),
    _HomeNavTab(
      semanticLabel: 'Search',
      semanticIdentifier: 'ente.photos.tab.search',
      outlineAsset: 'assets/icons/nav_bar/search_outline.svg',
      filledAsset: 'assets/icons/nav_bar/search_filled.svg',
    ),
  ];

  final int selectedIndex;
  final ValueChanged<int> onTabChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return GNav(
      curve: Curves.easeOutExpo,
      backgroundColor: colors.fillLight,
      mainAxisAlignment: MainAxisAlignment.center,
      padding: const EdgeInsets.all(_homeNavButtonPadding),
      duration: const Duration(milliseconds: 200),
      gap: 0,
      borderRadius: Radii.button,
      boxShadow: const [
        BoxShadow(
          color: Color.fromRGBO(0, 0, 0, 0.25),
          offset: Offset(0, 4),
          blurRadius: 8.75,
        ),
      ],
      tabBorderRadius: Radii.md,
      tabBackgroundColor: colors.fillDark,
      haptic: false,
      selectedIndex: selectedIndex,
      onTabChange: onTabChange,
      tabs: List.generate(_tabs.length, (index) {
        return GButton(
          margin: EdgeInsets.only(
            left: index == 0 ? Spacing.lg : _homeNavItemSpacing,
            right: index == _tabs.length - 1 ? Spacing.lg : _homeNavItemSpacing,
            top: Spacing.md,
            bottom: Spacing.md,
          ),
          text: '',
          semanticLabel: _tabs[index].semanticLabel,
          semanticIdentifier: _tabs[index].semanticIdentifier,
          leading: SizedBox.square(
            dimension: IconSizes.small,
            child: _HomeNavIcon(
              tab: _tabs[index],
              selected: selectedIndex == index,
              color: colors.iconColor,
            ),
          ),
        );
      }),
    );
  }
}

class _HomeNavIcon extends StatelessWidget {
  const _HomeNavIcon({
    required this.tab,
    required this.selected,
    required this.color,
  });

  final _HomeNavTab tab;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
    return SvgPicture.asset(
      selected ? tab.filledAsset : tab.outlineAsset,
      width: IconSizes.small,
      height: IconSizes.small,
      colorFilter: colorFilter,
    );
  }
}

class _HomeNavTab {
  const _HomeNavTab({
    required this.semanticLabel,
    required this.semanticIdentifier,
    required this.outlineAsset,
    required this.filledAsset,
  });

  final String semanticLabel;
  final String semanticIdentifier;
  final String outlineAsset;
  final String filledAsset;
}
