import "dart:async";

import "package:ente_components/components/app_bar_component.dart";
import "package:ente_components/components/buttons/icon_button_component.dart";
import "package:ente_components/components/menu_component.dart";
import "package:ente_contacts/contacts.dart" as contacts;
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/album/row_item.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/empty_state.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/hierarchical_search_gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";
import "package:photos/ui/viewer/hierarchicial_search/app_bar_filter_chips.dart";
import "package:photos/ui/viewer/search/contact_avatar_widget.dart";
import "package:photos/ui/viewer/search/result/edit_contact_page.dart";

class ContactResultPage extends StatefulWidget {
  final SearchResult searchResult;
  final bool enableGrouping;
  final String tagPrefix;

  static const GalleryType appBarType = GalleryType.searchResults;
  static const GalleryType overlayType = GalleryType.searchResults;

  const ContactResultPage(
    this.searchResult, {
    this.enableGrouping = true,
    this.tagPrefix = "",
    super.key,
  });

  @override
  State<ContactResultPage> createState() => _ContactResultPageState();
}

class _ContactResultPageState extends State<ContactResultPage> {
  final _selectedFiles = SelectedFiles();
  late final List<EnteFile> files;
  late final List<Collection> collections;
  late final StreamSubscription<LocalPhotosUpdatedEvent> _filesUpdatedEvent;
  late final StreamSubscription<ContactsChangedEvent> _contactsChangedEvent;
  late final String _searchResultName;
  late final String _contactEmail;
  late final int _contactUserId;
  late final SearchFilterDataProvider _searchFilterDataProvider;
  contacts.ContactRecord? _savedContact;
  String? _personId;
  bool _resolvedSavedContact = false;

  @override
  void initState() {
    super.initState();
    final params = (widget.searchResult as GenericSearchResult).params;
    files = widget.searchResult.resultFiles();
    collections = params[kContactCollections] ?? <Collection>[];
    _searchResultName = widget.searchResult.name();
    _contactEmail = params[kContactEmail] as String? ?? _searchResultName;
    _contactUserId = params[kContactUserId] as int;
    _personId = params[kPersonParamID] as String?;
    _filesUpdatedEvent = Bus.instance.on<LocalPhotosUpdatedEvent>().listen((
      event,
    ) {
      if (event.type == EventType.deletedFromDevice ||
          event.type == EventType.deletedFromEverywhere ||
          event.type == EventType.deletedFromRemote ||
          event.type == EventType.hide) {
        for (var updatedFile in event.updatedFiles) {
          files.remove(updatedFile);
        }
        setState(() {});
      }
    });

    _searchFilterDataProvider = SearchFilterDataProvider(
      initialGalleryFilter: widget.searchResult.getHierarchicalSearchFilter(),
    );

    _refreshSavedContact();
    _contactsChangedEvent = Bus.instance.on<ContactsChangedEvent>().listen((
      event,
    ) {
      if (event.matchesContactUserId(_contactUserId)) {
        _refreshSavedContact();
      }
    });
  }

  @override
  void dispose() {
    _filesUpdatedEvent.cancel();
    _contactsChangedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appBar = _buildAppBarConfig();
    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
        final result = files
            .where(
              (file) =>
                  file.creationTime! >= creationStartTime &&
                  file.creationTime! <= creationEndTime,
            )
            .toList();
        return Future.value(
          FileLoadResult(result, result.length < files.length),
        );
      },
      reloadEvent: Bus.instance.on<LocalPhotosUpdatedEvent>(),
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.hide,
      },
      tagPrefix: widget.tagPrefix + widget.searchResult.heroTag(),
      selectedFiles: _selectedFiles,
      enableFileGrouping: widget.enableGrouping,
      initialFiles: widget.searchResult.resultFiles().isNotEmpty
          ? [widget.searchResult.resultFiles().first]
          : null,
      header: _buildPageHeader(),
      emptyState: _shouldShowUnsavedContactEmptyState
          ? _UnsavedContactEmptyState(email: _contactEmail)
          : const EmptyState(),
    );

    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: InheritedSearchFilterDataWrapper(
          searchFilterDataProvider: _searchFilterDataProvider,
          child: Scaffold(
            backgroundColor: getEnteColorScheme(context).backgroundColour,
            body: SelectionState(
              selectedFiles: _selectedFiles,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Builder(
                    builder: (context) {
                      return ValueListenableBuilder(
                        valueListenable: InheritedSearchFilterData.of(
                          context,
                        ).searchFilterDataProvider!.isSearchingNotifier,
                        builder: (context, value, _) {
                          return value
                              ? HierarchicalSearchGallery(
                                  tagPrefix: widget.tagPrefix,
                                  selectedFiles: _selectedFiles,
                                  appBar: appBar,
                                )
                              : gallery;
                        },
                      );
                    },
                  ),
                  FileSelectionOverlayBar(
                    ContactResultPage.overlayType,
                    _selectedFiles,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  GalleryAppBarConfig _buildAppBarConfig() {
    if (_savedContact != null) {
      return GalleryAppBarConfig(
        sliverBuilder: (_) => _SavedContactAppBar(
          title: _savedContactDisplayName,
          email: _savedContactEmail,
          contactUserId: _contactUserId,
          personId: _personId,
          selectedFiles: _selectedFiles,
          onEdit: _openEditContactPage,
        ),
        geometryBuilder: (context) {
          final inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(
            context,
          );
          final isHierarchicalSearchable =
              inheritedSearchFilterData?.isHierarchicalSearchable ?? false;
          final bottomHeight = isHierarchicalSearchable
              ? AppBarFilterChips.preferredHeight(context)
              : 0.0;
          return SliverAppBarComponent.resolveGeometry(
            context,
            subtitle: _savedContactEmail,
            collapsedHeight: GalleryAppBarWidget.toolbarHeight,
            bottomHeight: bottomHeight,
          );
        },
      );
    }

    return GalleryAppBarWidget.sliverConfig(
      ContactResultPage.appBarType,
      _searchResultName,
      _selectedFiles,
    );
  }

  Widget? _buildContactHeader() {
    if (!_resolvedSavedContact) {
      return const Padding(
        padding: EdgeInsets.only(top: 20, bottom: 8),
        child: SizedBox(height: 88, child: Center(child: EnteLoadingWidget())),
      );
    }
    if (_savedContact == null) {
      return _UnsavedContactHeader(onTap: _openEditContactPage);
    }
    return null;
  }

  Widget? _buildPageHeader() {
    final sections = <Widget?>[
      _buildContactHeader(),
      if (collections.isNotEmpty) _AlbumsSection(collections: collections),
    ].whereType<Widget>().toList();
    if (sections.isEmpty) {
      return null;
    }
    return Column(children: sections);
  }

  bool get _shouldShowUnsavedContactEmptyState =>
      _resolvedSavedContact &&
      _savedContact == null &&
      files.isEmpty &&
      collections.isEmpty;

  Future<void> _refreshSavedContact() async {
    final saved = await PhotosContactsService.instance.getContact(
      contactUserId: _contactUserId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _savedContact = saved;
      _resolvedSavedContact = true;
    });
  }

  Future<void> _openEditContactPage() async {
    final updated = await routeToPage(
      context,
      EditContactPage(
        contactUserId: _contactUserId,
        email: _contactEmail,
        existingContact: _savedContact,
      ),
    );
    if (updated is contacts.ContactRecord && mounted) {
      final personData = PersonService.instance.getCachedPartialPersonData(
        userID: _contactUserId,
        email: _contactEmail,
      );
      setState(() {
        _savedContact = updated;
        _personId = personData?[PersonService.kPersonIDKey];
      });
    }
  }

  String get _savedContactDisplayName {
    final savedName = _savedContact?.data?.name.trim();
    if (savedName != null && savedName.isNotEmpty) {
      return savedName;
    }
    return _searchResultName;
  }

  String get _savedContactEmail {
    final savedEmail = _savedContact?.email?.trim();
    if (savedEmail != null && savedEmail.isNotEmpty) {
      return savedEmail;
    }
    return _contactEmail;
  }
}

class _SavedContactAppBar extends StatelessWidget {
  const _SavedContactAppBar({
    required this.title,
    required this.email,
    required this.contactUserId,
    required this.personId,
    required this.selectedFiles,
    required this.onEdit,
  });

  final String title;
  final String email;
  final int contactUserId;
  final String? personId;
  final SelectedFiles selectedFiles;
  final Future<void> Function() onEdit;

  @override
  Widget build(BuildContext context) {
    final inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(
      context,
    );
    final isHierarchicalSearchable =
        inheritedSearchFilterData?.isHierarchicalSearchable ?? false;

    if (!isHierarchicalSearchable) {
      return _buildSliverAppBar(context, isSearching: false);
    }

    return ValueListenableBuilder(
      valueListenable: inheritedSearchFilterData!
          .searchFilterDataProvider!
          .isSearchingNotifier,
      child: PreferredSize(
        preferredSize: Size.fromHeight(
          AppBarFilterChips.preferredHeight(context),
        ),
        child: const AppBarFilterChips(),
      ),
      builder: (context, isSearching, child) {
        return _buildSliverAppBar(
          context,
          isSearching: isSearching,
          bottom: child as PreferredSizeWidget,
        );
      },
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context, {
    required bool isSearching,
    PreferredSizeWidget? bottom,
  }) {
    return AnimatedBuilder(
      animation: selectedFiles,
      builder: (context, _) {
        return SliverAppBarComponent(
          title: title,
          subtitle: email,
          leading: Center(
            child: ContactAvatarWidget(
              contactUserId: contactUserId,
              email: email,
              personId: personId,
              size: 36,
            ),
          ),
          actions: isSearching || selectedFiles.files.isNotEmpty
              ? const []
              : [
                  IconButtonComponent(
                    tooltip: context.l10n.edit,
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit03),
                    variant: IconButtonComponentVariant.primary,
                    shouldSurfaceExecutionStates: false,
                    onTap: onEdit,
                  ),
                ],
          bottom: bottom,
          collapsedHeight: GalleryAppBarWidget.toolbarHeight,
          backgroundColor: GalleryAppBarWidget.backgroundColor(context),
        );
      },
    );
  }
}

class _AlbumsSection extends StatelessWidget {
  const _AlbumsSection({required this.collections});

  final List<Collection> collections;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              AppLocalizations.of(context).albums,
              style: getEnteTextTheme(context).largeBold,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 142,
              child: ListView.separated(
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                scrollDirection: Axis.horizontal,
                itemCount: collections.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) {
                  final item = collections[index];
                  return AlbumRowItemWidget(
                    item,
                    108,
                    key: ValueKey('contact_result_${item.id}'),
                    showFileCount: false,
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

class _UnsavedContactHeader extends StatelessWidget {
  const _UnsavedContactHeader({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        height: 60,
        child: MenuComponent(
          title: l10n.addANameAndPhoto,
          titleColor: colorScheme.textBase,
          leading: _AddContactMenuIcon(colorScheme: colorScheme),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.textMuted,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _AddContactMenuIcon extends StatelessWidget {
  const _AddContactMenuIcon({required this.colorScheme});

  final EnteColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.greenLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.person_add_alt_1_rounded,
        size: 18,
        color: colorScheme.greenBase,
      ),
    );
  }
}

class _UnsavedContactEmptyState extends StatelessWidget {
  const _UnsavedContactEmptyState({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 32, 36, 0),
      child: Column(
        children: [
          Image.asset(
            "assets/ducky_share.png",
            height: 180,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(height: 180);
            },
          ),
          const SizedBox(height: 12),
          Text(
            l10n.nothingToSeeHere,
            style: textTheme.largeBold.copyWith(fontSize: 18, height: 24 / 18),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.photosSharedByWillAppearHere(email: email),
            textAlign: TextAlign.center,
            style: textTheme.mini.copyWith(
              color: colorScheme.textMuted,
              height: 16 / 12,
            ),
          ),
        ],
      ),
    );
  }
}
