import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/person_contact_linking_util.dart";

sealed class ContactPersonPickerCandidate {
  const ContactPersonPickerCandidate();
}

class ContactPersonPickerPersonCandidate extends ContactPersonPickerCandidate {
  const ContactPersonPickerPersonCandidate(this.person);

  final PersonEntity person;
}

class ContactPersonPickerClusterCandidate extends ContactPersonPickerCandidate {
  const ContactPersonPickerClusterCandidate(
    this.clusterID, {
    required this.fileCount,
  });

  final String clusterID;
  final int fileCount;
}

List<ContactPersonPickerCandidate> buildContactPersonPickerCandidates({
  required Iterable<GenericSearchResult> faceResults,
  required Iterable<PersonEntity> persons,
}) {
  final personsByID = {for (final person in persons) person.remoteID: person};
  final personCandidates = <ContactPersonPickerPersonCandidate>[];
  final clusterCandidates = <ContactPersonPickerClusterCandidate>[];

  for (final result in faceResults) {
    final params = result.params;
    final personID = params[kPersonParamID] as String?;
    if (personID != null) {
      final person = personsByID[personID];
      if (person != null) {
        personCandidates.add(ContactPersonPickerPersonCandidate(person));
      }
      continue;
    }

    final clusterID = params[kClusterParamId] as String?;
    if (clusterID != null) {
      clusterCandidates.add(
        ContactPersonPickerClusterCandidate(
          clusterID,
          fileCount: result.fileCount(),
        ),
      );
    }
  }

  clusterCandidates.sort(
    (first, second) => second.fileCount.compareTo(first.fileCount),
  );
  return [...personCandidates, ...clusterCandidates];
}

abstract class ContactPersonPickerResult {
  const ContactPersonPickerResult();
}

class ContactPersonPickerSelected extends ContactPersonPickerResult {
  const ContactPersonPickerSelected(this.candidate);

  final ContactPersonPickerCandidate candidate;
}

class ContactPersonPickerPickPhoto extends ContactPersonPickerResult {
  const ContactPersonPickerPickPhoto();
}

class ContactPersonPickerPage extends StatefulWidget {
  const ContactPersonPickerPage({
    required this.contactUserId,
    required this.contactEmail,
    required this.candidates,
    super.key,
  });

  final int contactUserId;
  final String contactEmail;
  final List<ContactPersonPickerCandidate> candidates;
  static const _horizontalPadding = 16.0;
  static const _gridGap = 10.0;

  @override
  State<ContactPersonPickerPage> createState() =>
      _ContactPersonPickerPageState();
}

class _ContactPersonPickerPageState extends State<ContactPersonPickerPage> {
  String _searchQuery = "";
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    final personCandidates =
        widget.candidates
            .whereType<ContactPersonPickerPersonCandidate>()
            .where(
              (candidate) => !isLinkedToDifferentContact(
                candidate.person,
                contactUserId: widget.contactUserId,
                email: widget.contactEmail,
              ),
            )
            .where(
              (candidate) => candidate.person.data.name.toLowerCase().contains(
                _searchQuery,
              ),
            )
            .toList()
          ..sort((first, second) {
            final comparison = compareAsciiLowerCaseNatural(
              first.person.data.name,
              second.person.data.name,
            );
            return _sortAscending ? comparison : -comparison;
          });
    final candidates = <ContactPersonPickerCandidate>[
      ...personCandidates,
      if (_searchQuery.isEmpty)
        ...widget.candidates.whereType<ContactPersonPickerClusterCandidate>(),
    ];

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: l10n.selectPerson,
        subtitle: l10n.selectPersonToLinkToThisContact,
        actions: [
          IconButtonComponent(
            variant: IconButtonComponentVariant.primary,
            shouldSurfaceExecutionStates: false,
            tooltip: l10n.setAContactPhoto,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedImageAdd02),
            onTap: () {
              Navigator.of(context).pop(const ContactPersonPickerPickPhoto());
            },
          ),
        ],
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              ContactPersonPickerPage._horizontalPadding,
              0,
              ContactPersonPickerPage._horizontalPadding,
              Spacing.xl,
            ),
            sliver: SliverToBoxAdapter(child: _buildSearchRow(context)),
          ),
          _buildGrid(candidates),
        ],
      ),
    );
  }

  Widget _buildSearchRow(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: TextInputComponent(
            hintText: l10n.searchAllPeople,
            prefix: HugeIcon(
              icon: HugeIcons.strokeRoundedSearch01,
              size: IconSizes.small,
              color: colors.textLight,
            ),
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onChanged: (value) {
              setState(() => _searchQuery = value.trim().toLowerCase());
            },
          ),
        ),
        const SizedBox(width: Spacing.xl),
        Builder(
          builder: (buttonContext) => IconButtonComponent(
            tooltip: l10n.sort,
            variant: IconButtonComponentVariant.primary,
            shouldSurfaceExecutionStates: false,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilterHorizontal),
            onTap: () => _showSortMenu(buttonContext),
          ),
        ),
      ],
    );
  }

  Future<void> _showSortMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showEntePopupMenu<bool>(
      context: context,
      options: [
        EntePopupMenuOption(
          value: true,
          label: l10n.name,
          secondaryLabel: l10n.sortAToZ,
          isActive: _sortAscending,
          activeTrailingWidget: const Icon(Icons.check_rounded),
        ),
        EntePopupMenuOption(
          value: false,
          label: l10n.name,
          secondaryLabel: l10n.sortZToA,
          isActive: !_sortAscending,
          activeTrailingWidget: const Icon(Icons.check_rounded),
          showDivider: false,
        ),
      ],
    );
    if (selected != null && mounted) {
      setState(() => _sortAscending = selected);
    }
  }

  Widget _buildGrid(List<ContactPersonPickerCandidate> candidates) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        ContactPersonPickerPage._horizontalPadding,
        0,
        ContactPersonPickerPage._horizontalPadding,
        48,
      ),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const crossAxisCount = 3;
          final tileSize =
              (constraints.crossAxisExtent -
                  (ContactPersonPickerPage._gridGap * (crossAxisCount - 1))) /
              crossAxisCount;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 20,
              crossAxisSpacing: ContactPersonPickerPage._gridGap,
              childAspectRatio: tileSize / (tileSize + 28),
            ),
            delegate: SliverChildBuilderDelegate(
              childCount: candidates.length,
              (context, index) => _PersonTile(
                key: ValueKey(switch (candidates[index]) {
                  ContactPersonPickerPersonCandidate(:final person) =>
                    "person-${person.remoteID}",
                  ContactPersonPickerClusterCandidate(:final clusterID) =>
                    "cluster-$clusterID",
                }),
                candidate: candidates[index],
                size: tileSize,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({super.key, required this.candidate, required this.size});

  final ContactPersonPickerCandidate candidate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final pixelWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final person = switch (candidate) {
      ContactPersonPickerPersonCandidate(:final person) => person,
      ContactPersonPickerClusterCandidate() => null,
    };
    final clusterID = switch (candidate) {
      ContactPersonPickerPersonCandidate() => null,
      ContactPersonPickerClusterCandidate(:final clusterID) => clusterID,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          Navigator.of(context).pop(ContactPersonPickerSelected(candidate)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: size,
            child: FaceThumbnailSquircleClip(
              borderRadius: faceThumbnailSquircleBorderRadius(size),
              child: ColoredBox(
                color: colors.strokeFaint,
                child: PersonFaceWidget(
                  personId: person?.remoteID,
                  clusterID: clusterID,
                  keepAlive: true,
                  cachedPixelWidth: pixelWidth,
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            child: Text(
              person?.data.name ?? " ",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.body.copyWith(color: colors.textBase),
            ),
          ),
        ],
      ),
    );
  }
}
