import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/album_home_widget_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/home_widget_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/flex_grid_view.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import 'package:photos/ui/components/buttons/icon_button_widget.dart';
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/components/models/button_type.dart";
import 'package:photos/ui/components/title_bar_title_widget.dart';
import 'package:photos/ui/components/title_bar_widget.dart';
import "package:photos/ui/components/toggle_switch_widget.dart";

class AlbumsWidgetSettings extends StatefulWidget {
  const AlbumsWidgetSettings({super.key});

  @override
  State<AlbumsWidgetSettings> createState() => _AlbumsWidgetSettingsState();
}

class _AlbumsWidgetSettingsState extends State<AlbumsWidgetSettings> {
  final _selectedAlbums = SelectedAlbums();
  bool hasInstalledAny = false;
  late bool _showText;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _showText = !localSettings.isWidgetTextHidden(WidgetHideTextFlag.album);
    checkIfAnyWidgetInstalled();
    selectExisting();
  }

  Future<void> checkIfAnyWidgetInstalled() async {
    final count = await AlbumHomeWidgetService.instance.countHomeWidgets();
    setState(() {
      hasInstalledAny = count > 0;
    });
  }

  Future<void> selectExisting() async {
    final selectedAlbums = AlbumHomeWidgetService.instance
        .getSelectedAlbumIds();
    final albums = <Collection>{};

    if (selectedAlbums != null) {
      for (final collectionID in selectedAlbums) {
        final collection = CollectionsService.instance.getCollectionByID(
          collectionID,
        );

        if (collection != null) {
          albums.add(collection);
        }
      }
    }

    if (albums.isEmpty) {
      final favorites = await FavoritesService.instance
          .getFavoritesCollection();

      if (favorites == null) {
        return;
      }

      albums.add(favorites);
    }

    _selectedAlbums.select(albums);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      bottomNavigationBar: hasInstalledAny
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                8 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: ListenableBuilder(
                listenable: _selectedAlbums,
                builder: (context, _) {
                  return ButtonWidget(
                    buttonType: ButtonType.primary,
                    buttonSize: ButtonSize.large,
                    labelText: AppLocalizations.of(context).save,
                    shouldSurfaceExecutionStates: false,
                    onTap: _selectedAlbums.albums.isNotEmpty
                        ? () async {
                            final albums = _selectedAlbums.albums
                                .map((e) => e.id.toString())
                                .toList();
                            await AlbumHomeWidgetService.instance
                                .updateSelectedAlbums(albums);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                          }
                        : null,
                    isDisabled: _selectedAlbums.albums.isEmpty,
                  );
                },
              ),
            )
          : null,
      body: Scrollbar(
        interactive: true,
        controller: _scrollController,
        child: CustomScrollView(
          controller: _scrollController,
          primary: false,
          slivers: <Widget>[
            TitleBarWidget(
              backgroundColor: colorScheme.backgroundColour,
              flexibleSpaceTitle: TitleBarTitleWidget(
                title: AppLocalizations.of(context).albums,
              ),
              expandedHeight: MediaQuery.textScalerOf(context).scale(136),
              flexibleSpaceCaption: hasInstalledAny
                  ? AppLocalizations.of(context).albumsWidgetDesc
                  : context.l10n.addAlbumWidgetPrompt,
              actionIcons: [
                IconButtonWidget(
                  icon: Icons.close_outlined,
                  iconButtonType: IconButtonType.secondary,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            if (!hasInstalledAny)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5 - 200,
                      ),
                      Image.asset(
                        "assets/albums-widget-static.png",
                        height: 160,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (kDebugMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
                    child: MenuItemWidgetNew(
                      title: AppLocalizations.of(context).showTextOnWidget,
                      trailingWidget: ToggleSwitchWidget(
                        value: () => _showText,
                        onChanged: () async {
                          final next = !_showText;
                          setState(() => _showText = next);
                          await localSettings.setWidgetTextHidden(
                            WidgetHideTextFlag.album,
                            !next,
                          );
                          await HomeWidgetService.instance.updateWidget(
                            androidClass:
                                AlbumHomeWidgetService.ANDROID_CLASS_NAME,
                            iOSClass: AlbumHomeWidgetService.IOS_CLASS_NAME,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              FutureBuilder<List<Collection>>(
                future: CollectionsService.instance
                    .getCollectionForWidgetSelection(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final data = snapshot.data!;
                    for (final collection in snapshot.data!) {
                      if (_selectedAlbums.albums.contains(collection)) {
                        data.remove(collection);
                        data.insert(0, collection);
                      }
                    }

                    return CollectionsFlexiGridViewWidget(
                      data,
                      shrinkWrap: false,
                      selectedAlbums: _selectedAlbums,
                      shouldShowCreateAlbum: false,
                      enableSelectionMode: true,
                      onlyAllowSelection: true,
                    );
                  } else if (snapshot.hasError) {
                    return SliverToBoxAdapter(
                      child: Text(snapshot.error.toString()),
                    );
                  } else {
                    return const SliverToBoxAdapter(child: EnteLoadingWidget());
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
