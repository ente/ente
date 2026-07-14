import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/events/event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/recent_searches.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/search/contact_avatar_widget.dart";
import "package:photos/ui/viewer/search/result/contact_result_page.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";
import "package:photos/ui/viewer/search_tab/section_header.dart";

class ContactsSectionLoader extends StatefulWidget {
  final int resultLimit;

  const ContactsSectionLoader({super.key, required this.resultLimit});

  @override
  State<ContactsSectionLoader> createState() => _ContactsSectionLoaderState();
}

class _ContactsSectionLoaderState extends State<ContactsSectionLoader> {
  Future<List<GenericSearchResult>>? _contactsFuture;

  @override
  Widget build(BuildContext context) {
    if (isLocalGalleryMode) {
      return const SizedBox.shrink();
    }
    _contactsFuture ??= SearchService.instance.getAllContactsSearchResults(
      widget.resultLimit + 1,
    );
    return FutureBuilder<List<GenericSearchResult>>(
      future: _contactsFuture!,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ContactsSection(
            snapshot.data!,
            resultLimit: widget.resultLimit,
          );
        }
        return const ContactsLoadingSection();
      },
    );
  }
}

class ContactsLoadingSection extends StatelessWidget {
  const ContactsLoadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(SectionType.contacts, hasMore: false),
          SizedBox(height: 92, child: EnteLoadingWidget()),
        ],
      ),
    );
  }
}

class ContactsSection extends StatefulWidget {
  final List<GenericSearchResult> contactSearchResults;
  final int resultLimit;

  const ContactsSection(
    this.contactSearchResults, {
    super.key,
    required this.resultLimit,
  });

  @override
  State<ContactsSection> createState() => _ContactsSectionState();
}

class _ContactsSectionState extends State<ContactsSection> {
  late List<GenericSearchResult> _contactSearchResults;
  final streamSubscriptions = <StreamSubscription>[];
  final _debouncer = Debouncer(const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    _contactSearchResults = widget.contactSearchResults;

    final streamsToListenTo = SectionType.contacts.sectionUpdateEvents();
    for (Stream<Event> stream in streamsToListenTo) {
      streamSubscriptions.add(
        stream.listen((event) async {
          _debouncer.run(() async {
            _contactSearchResults =
                (await SectionType.contacts.getData(
                      context,
                      limit: widget.resultLimit + 1,
                    ))
                    as List<GenericSearchResult>;
            if (!mounted) return;
            setState(() {});
          });
        }),
      );
    }
  }

  @override
  void dispose() {
    for (var subscriptions in streamSubscriptions) {
      subscriptions.cancel();
    }
    _debouncer.cancelDebounceTimer();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ContactsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _contactSearchResults = widget.contactSearchResults;
  }

  @override
  Widget build(BuildContext context) {
    if (_contactSearchResults.isEmpty) {
      final colors = context.componentColors;
      return Padding(
        padding: const EdgeInsets.only(
          left: searchTabSectionHorizontalPadding,
          right: searchTabSectionHorizontalPadding,
          bottom: 20,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SectionType.contacts.sectionTitle(context),
                    style: TextStyles.display3.copyWith(color: colors.textBase),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    SectionType.contacts.getEmptyStateText(context),
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: ContactCTA(),
            ),
          ],
        ),
      );
    } else {
      final visibleResults = _contactSearchResults
          .take(widget.resultLimit)
          .toList(growable: false);
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              SectionType.contacts,
              hasMore: _contactSearchResults.length > widget.resultLimit,
            ),
            const SizedBox(height: 4),
            SearchTabHorizontalRow(
              spacing: 12,
              children: [
                for (final contactSearchResult in visibleResults)
                  ContactRecommendation(
                    contactSearchResult,
                    key: ValueKey(contactSearchResult.name()),
                  ),
                const ContactCTA(),
              ],
            ),
          ],
        ),
      );
    }
  }
}

class ContactRecommendation extends StatefulWidget {
  static const _avatarSize = 62.0;

  final GenericSearchResult contactSearchResult;
  const ContactRecommendation(this.contactSearchResult, {super.key});

  @override
  State<ContactRecommendation> createState() => _ContactRecommendationState();
}

class _ContactRecommendationState extends State<ContactRecommendation> {
  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final personId =
        widget.contactSearchResult.params[kPersonParamID] as String?;
    final contactUserId =
        widget.contactSearchResult.params[kContactUserId] as int?;
    final contactEmail =
        widget.contactSearchResult.params[kContactEmail] as String;
    return GestureDetector(
      onTap: () {
        RecentSearches().add(widget.contactSearchResult.name());
        if (widget.contactSearchResult.onResultTap != null) {
          widget.contactSearchResult.onResultTap!(context);
        } else {
          routeToPage(context, ContactResultPage(widget.contactSearchResult));
        }
      },
      child: SizedBox(
        width: 92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipOval(
              child: SizedBox(
                width: ContactRecommendation._avatarSize,
                height: ContactRecommendation._avatarSize,
                child: ContactAvatarWidget(
                  contactUserId: contactUserId,
                  email: contactEmail,
                  personId: personId,
                  size: ContactRecommendation._avatarSize,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.contactSearchResult.name(),
              style: TextStyles.mini.copyWith(color: colors.textBase),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ContactCTA extends StatelessWidget {
  static const _inviteAsset = "assets/invite_contact.svg";
  static const _iconSize = 62.0;

  const ContactCTA({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return GestureDetector(
      onTap: SectionType.contacts.ctaOnTap(context),
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: _iconSize,
              height: _iconSize,
              decoration: BoxDecoration(
                color: colorScheme.fill,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(_inviteAsset, width: 24, height: 24),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).invite,
              style: TextStyles.mini.copyWith(color: colorScheme.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
