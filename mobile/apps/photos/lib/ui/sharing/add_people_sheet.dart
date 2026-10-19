import "dart:math" as math;

import "package:collection/collection.dart";
import "package:email_validator/email_validator.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/sharing/choose_access_sheet.dart";
import "package:photos/ui/sharing/manage_links_widget.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/sharing/verify_identity_dialog.dart";
import "package:photos/ui/sharing/widgets/selected_person_chip.dart";
import "package:photos/ui/sharing/widgets/sharing_progress_sheet.dart";
import "package:photos/ui/sharing/widgets/sharing_role.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/share_util.dart";

Future<bool> showAddPeopleSheet(
  BuildContext context,
  List<Collection> collections,
) async {
  if (collections.isEmpty) {
    return false;
  }
  final selected = <UserSuggestion>[];
  late CollectionParticipantRole role;
  while (true) {
    final shouldContinue = await showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) =>
          _AddPeopleSheet(collections: collections, selected: selected),
    );
    if (shouldContinue != true || !context.mounted) {
      return false;
    }
    final selectedRole = await showChooseAccessSheet(
      context,
      selected: selected,
      initialRole: CollectionParticipantRole.viewer,
    );
    if (!context.mounted) {
      return false;
    }
    if (selectedRole == null) {
      continue;
    }
    role = selectedRole;
    break;
  }
  final actions = CollectionActions(CollectionsService.instance);
  AddEmailToCollectionResult? failure;
  final success = await showSharingProgressSheet(
    context,
    task: () async {
      final result = await actions.addEmailsToCollections(
        collections,
        selected.map((person) => normalizedSharingEmail(person.email)).toSet(),
        role,
      );
      if (!result.succeeded) failure = result;
      return result.succeeded;
    },
  );
  if (!success && failure != null && context.mounted) {
    await actions.showAddEmailToCollectionFailure(context, failure!);
  }
  return success;
}

bool _hasActiveLink(Collection collection) {
  final url = collection.publicURLs.firstOrNull;
  return url != null && !url.isExpired;
}

bool _canSharePublicLink(Collection collection, int currentUserID) {
  if (_hasActiveLink(collection)) {
    return true;
  }
  return collection.isOwner(currentUserID);
}

class _AddPeopleSheet extends StatefulWidget {
  const _AddPeopleSheet({required this.collections, required this.selected});

  final List<Collection> collections;
  final List<UserSuggestion> selected;

  @override
  State<_AddPeopleSheet> createState() => _AddPeopleSheetState();
}

class _AddPeopleSheetState extends State<_AddPeopleSheet> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _selectedPeopleScrollController = ScrollController();
  final _contactsScrollController = ScrollController();
  final _shareLinkKey = GlobalKey();
  late final List<UserSuggestion> _contacts;
  String _emailText = "";
  bool _emailIsValid = false;
  bool _emailHasNoAccount = false;

  @override
  void initState() {
    super.initState();
    _contacts = UserService.instance.getRelevantContacts().where((suggestion) {
      return widget.collections.any(
        (collection) => collectionNeedsShare(collection, suggestion.email),
      );
    }).toList()..sort((a, b) => a.email.compareTo(b.email));
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _selectedPeopleScrollController.dispose();
    _contactsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedEmails = {
      for (final suggestion in widget.selected)
        normalizedSharingEmail(suggestion.email),
    };
    final query = _emailHasNoAccount
        ? ""
        : _textController.text.trim().toLowerCase();
    final availableContacts = _contacts
        .where(
          (contact) =>
              !selectedEmails.contains(normalizedSharingEmail(contact.email)) &&
              matchesResolvedSuggestionQuery(contact, query),
        )
        .toList();
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.95,
      ),
      child: BottomSheetComponent(
        title: context.strings.addPeople,
        isKeyboardAware: true,
        content: Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectedRecipientChips(
                  suggestions: widget.selected,
                  scrollController: _selectedPeopleScrollController,
                  onRemove: _toggleSuggestion,
                  onLongPress: (suggestion) => showVerifyIdentitySheet(
                    context,
                    self: false,
                    email: suggestion.email,
                  ),
                ),
                _EmailField(
                  controller: _textController,
                  focusNode: _focusNode,
                  emailIsValid: _emailIsValid,
                  emailHasNoAccount: _emailHasNoAccount,
                  shareKey: _shareLinkKey,
                  onChanged: (value) {
                    if (value == _emailText) {
                      return;
                    }
                    _emailText = value;
                    if (_contactsScrollController.hasClients) {
                      _contactsScrollController.jumpTo(0);
                    }
                    setState(() {
                      _emailIsValid = EmailValidator.validate(value.trim());
                      _emailHasNoAccount = false;
                    });
                  },
                  onSubmit: _tryAddTypedEmail,
                  onShareLink: _sharePublicLink,
                ),
                if (availableContacts.isNotEmpty || query.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xl),
                  _ContactSuggestions(
                    contacts: availableContacts,
                    scrollController: _contactsScrollController,
                    onToggle: _toggleSuggestion,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: keyboardVisible && !_emailHasNoAccount
            ? const []
            : [
                ButtonComponent(
                  label: context.strings.continueLabel,
                  variant: ButtonComponentVariant.primary,
                  size: ButtonComponentSize.large,
                  isDisabled: widget.selected.isEmpty,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
      ),
    );
  }

  Future<void> _tryAddTypedEmail() async {
    final email = normalizedSharingEmail(_textController.text);
    final currentEmail = Configuration.instance.getEmail();
    if (!EmailValidator.validate(email)) {
      return;
    }
    if (currentEmail != null && email == normalizedSharingEmail(currentEmail)) {
      await showErrorDialog(
        context,
        context.strings.oops,
        context.strings.youCannotShareWithYourself,
      );
      return;
    }
    if (_isSelected(email)) {
      _clearEmail();
      return;
    }
    if (!widget.collections.any(
      (collection) => collectionNeedsShare(collection, email),
    )) {
      showShortToast(context, context.strings.personAlreadyHasAccess);
      _clearEmail();
      return;
    }
    setState(() => _emailHasNoAccount = false);
    try {
      final publicKey = await UserService.instance.getPublicKey(email);
      if (!mounted) {
        return;
      }
      if (normalizedSharingEmail(_textController.text) != email ||
          _isSelected(email)) {
        return;
      }
      if (publicKey == null || publicKey.isEmpty) {
        if (widget.collections.length != 1 ||
            !_canSharePublicLink(
              widget.collections.first,
              Configuration.instance.getUserID()!,
            )) {
          await CollectionActions(
            CollectionsService.instance,
          ).showAddEmailToCollectionFailure(
            context,
            AddEmailToCollectionResult.failure(
              failure: AddEmailToCollectionFailure.noAccount,
              email: email,
            ),
          );
          return;
        }
        setState(() => _emailHasNoAccount = true);
        return;
      }
      final suggestion = _contacts.firstWhereOrNull(
        (contact) => normalizedSharingEmail(contact.email) == email,
      );
      setState(() {
        widget.selected.add(suggestion ?? UserSuggestion(email));
      });
      _clearEmail();
      _scrollSelectedPeopleToEnd();
    } catch (error) {
      if (!mounted ||
          normalizedSharingEmail(_textController.text) != email ||
          _isSelected(email)) {
        return;
      }
      setState(() => _emailHasNoAccount = false);
      await showGenericErrorDialog(context: context, error: error);
    }
  }

  void _toggleSuggestion(UserSuggestion suggestion) {
    _focusNode.unfocus();
    var added = false;
    setState(() {
      final index = widget.selected.indexWhere(
        (selected) =>
            normalizedSharingEmail(selected.email) ==
            normalizedSharingEmail(suggestion.email),
      );
      if (index == -1) {
        widget.selected.add(suggestion);
        added = true;
      } else {
        widget.selected.removeAt(index);
      }
    });
    if (added) {
      _clearEmail();
      _scrollSelectedPeopleToEnd();
    }
  }

  void _scrollSelectedPeopleToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_selectedPeopleScrollController.hasClients) {
        return;
      }
      _selectedPeopleScrollController.animateTo(
        _selectedPeopleScrollController.position.maxScrollExtent,
        duration: Motion.quick,
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _isSelected(String email) {
    return widget.selected.any(
      (selected) =>
          normalizedSharingEmail(selected.email) ==
          normalizedSharingEmail(email),
    );
  }

  void _clearEmail() {
    _textController.clear();
    _focusNode.unfocus();
    setState(() {
      _emailIsValid = false;
      _emailHasNoAccount = false;
    });
  }

  Future<void> _sharePublicLink() async {
    if (widget.collections.length != 1) {
      return;
    }
    final collection = widget.collections.first;
    final currentUserID = Configuration.instance.getUserID()!;
    if (!_canSharePublicLink(collection, currentUserID)) {
      return;
    }
    if (collection.hasLink && !_hasActiveLink(collection)) {
      await routeToPage(
        context,
        ManageSharedLinkWidget(collection: collection),
      );
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (!_hasActiveLink(collection)) {
      final enabled = await CollectionActions(
        CollectionsService.instance,
      ).enableUrl(context, collection);
      if (!enabled || !mounted || !_hasActiveLink(collection)) {
        return;
      }
      setState(() {});
    }
    final url = CollectionsService.instance.getPublicUrl(collection);
    await shareAlbumLink(
      context,
      url,
      _shareLinkKey,
      albumName: collection.displayName,
      albumDescription: collection.displayDescription,
    );
  }
}

class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.focusNode,
    required this.emailIsValid,
    required this.emailHasNoAccount,
    required this.shareKey,
    required this.onChanged,
    required this.onSubmit,
    required this.onShareLink,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool emailIsValid;
  final bool emailHasNoAccount;
  final GlobalKey shareKey;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onShareLink;

  @override
  Widget build(BuildContext context) {
    final messageStyle = TextStyles.mini.copyWith(
      color: context.componentColors.textLighter,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextInputComponent(
                controller: controller,
                focusNode: focusNode,
                hintText: context.strings.enterAnEmailAddress,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                enableSuggestions: false,
                isClearable: !emailHasNoAccount,
                suffix: emailHasNoAccount
                    ? HugeIcon(
                        icon: HugeIcons.strokeRoundedAlert02,
                        size: IconSizes.small,
                        color: context.componentColors.textLight,
                      )
                    : null,
                onChanged: onChanged,
                onSubmit: (_) => onSubmit(),
              ),
            ),
            if (!emailHasNoAccount) ...[
              const SizedBox(width: Spacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: IconButtonComponent(
                  variant: IconButtonComponentVariant.green,
                  shouldSurfaceExecutionStates: false,
                  tooltip: context.strings.add,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedMailAdd01),
                  onTap: emailIsValid ? onSubmit : null,
                ),
              ),
            ],
          ],
        ),
        if (emailHasNoAccount) ...[
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            child: Text(
              context.strings.noEnteAccountWithThisEmail,
              textAlign: TextAlign.center,
              style: messageStyle,
            ),
          ),
          const SizedBox(height: Spacing.xl),
          ButtonComponent(
            key: shareKey,
            label: context.strings.shareALink,
            variant: ButtonComponentVariant.secondary,
            size: ButtonComponentSize.large,
            shouldShowSuccessState: false,
            onTap: onShareLink,
          ),
        ],
      ],
    );
  }
}

class _ContactSuggestions extends StatefulWidget {
  const _ContactSuggestions({
    required this.contacts,
    required this.scrollController,
    required this.onToggle,
  });

  static double rowExtent(BuildContext context) {
    const textStyle = TextStyles.mini;
    final lineExtent =
        (MediaQuery.textScalerOf(context).scale(textStyle.fontSize!) *
                textStyle.height!)
            .ceilToDouble();
    return math.max(
      104.0,
      getAvatarSize(AvatarType.huge) + Spacing.sm + lineExtent * 2,
    );
  }

  final List<UserSuggestion> contacts;
  final ScrollController scrollController;
  final ValueChanged<UserSuggestion> onToggle;

  @override
  State<_ContactSuggestions> createState() => _ContactSuggestionsState();
}

class _ContactSuggestionsState extends State<_ContactSuggestions> {
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  Widget build(BuildContext context) {
    final rowExtent = _ContactSuggestions.rowExtent(context);
    if (widget.contacts.isEmpty) {
      return SizedBox(
        height: rowExtent,
        width: double.infinity,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedAlert02,
                size: 33,
                color: context.componentColors.textLighter,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                context.strings.noMatchingResultsFound,
                textAlign: TextAlign.center,
                style: TextStyles.body.copyWith(
                  color: context.componentColors.textLight,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final avatarSize = getAvatarSize(AvatarType.huge);
    const arrowSize = 36.0;
    final itemWidth = avatarSize + Spacing.lg;
    final scrollStep = (itemWidth + Spacing.lg) * 3;

    return SizedBox(
      height: rowExtent,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _updateScrollEdges(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _updateScrollEdges(notification.metrics);
            return false;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView.separated(
                  key: const ValueKey("contact-suggestions-scroll"),
                  controller: widget.scrollController,
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.only(end: arrowSize),
                  itemCount: widget.contacts.length,
                  itemBuilder: (context, index) {
                    final contact = widget.contacts[index];
                    return SizedBox(
                      width: itemWidth,
                      child: _ContactSuggestion(
                        key: ValueKey(
                          "contact-${contact.email.trim().toLowerCase()}",
                        ),
                        suggestion: contact,
                        onTap: () => widget.onToggle(contact),
                        onLongPress: () => showVerifyIdentitySheet(
                          context,
                          self: false,
                          email: contact.email,
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(width: Spacing.lg),
                ),
              ),
              if (_canScrollBack)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: arrowSize,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [
                            context.componentColors.backgroundBase,
                            context.componentColors.backgroundBase.withValues(
                              alpha: 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                width: arrowSize,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          context.componentColors.backgroundBase.withValues(
                            alpha: 0,
                          ),
                          context.componentColors.backgroundBase,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_canScrollBack)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  child: SizedBox(
                    height: avatarSize,
                    child: Center(
                      child: IconButtonComponent(
                        size: arrowSize,
                        variant: IconButtonComponentVariant.primary,
                        shouldSurfaceExecutionStates: false,
                        tooltip: context.strings.previous,
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowLeft01,
                        ),
                        onTap: () => _scroll(context, -scrollStep),
                      ),
                    ),
                  ),
                ),
              if (_canScrollForward)
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  child: SizedBox(
                    height: avatarSize,
                    child: Center(
                      child: IconButtonComponent(
                        size: arrowSize,
                        variant: IconButtonComponentVariant.primary,
                        shouldSurfaceExecutionStates: false,
                        tooltip: context.strings.next,
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                        ),
                        onTap: () => _scroll(context, scrollStep),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateScrollEdges(ScrollMetrics metrics) {
    final canScrollBack = metrics.extentBefore > 0;
    final canScrollForward = metrics.extentAfter > 0;
    if (canScrollBack == _canScrollBack &&
        canScrollForward == _canScrollForward) {
      return;
    }
    setState(() {
      _canScrollBack = canScrollBack;
      _canScrollForward = canScrollForward;
    });
  }

  Future<void> _scroll(BuildContext context, double offset) async {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    final target = (position.pixels + offset)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.scrollController.jumpTo(target);
      return;
    }
    await widget.scrollController.animateTo(
      target,
      duration: Motion.slow,
      curve: Curves.easeOutCubic,
    );
  }
}

class _ContactSuggestion extends StatelessWidget {
  const _ContactSuggestion({
    super.key,
    required this.suggestion,
    required this.onTap,
    required this.onLongPress,
  });

  final UserSuggestion suggestion;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final label = resolveSuggestionDisplayName(suggestion);
    return InkWell(
      key: ValueKey(
        "contact-suggestion-${suggestion.email.trim().toLowerCase()}",
      ),
      borderRadius: BorderRadius.circular(Radii.button),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        children: [
          UserAvatarWidget.suggestion(suggestion, type: AvatarType.huge),
          const SizedBox(height: Spacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.mini.copyWith(
              color: context.componentColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}
