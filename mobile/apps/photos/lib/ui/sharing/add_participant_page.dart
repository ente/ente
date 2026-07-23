import 'package:email_validator/email_validator.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/collection/collection.dart';
import "package:photos/services/account/user_service.dart";
import 'package:photos/services/collections_service.dart';
import "package:photos/services/contacts/contact_identity_resolver.dart";
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import "package:photos/ui/notification/toast.dart";
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/ui/sharing/user_avator_widget.dart';
import "package:photos/ui/sharing/verify_identity_dialog.dart";

enum ActionTypesToShow { addViewer, addCollaborator, addAdmin }

class AddParticipantPage extends StatefulWidget {
  /// Cannot be empty
  final List<ActionTypesToShow> actionTypesToShow;
  final List<Collection> collections;

  AddParticipantPage(this.collections, this.actionTypesToShow, {super.key})
    : assert(actionTypesToShow.isNotEmpty, 'actionTypesToShow cannot be empty');

  @override
  State<StatefulWidget> createState() => _AddParticipantPage();
}

class _AddParticipantPage extends State<AddParticipantPage> {
  final _selectedEmails = <String>{};
  String _newEmail = '';
  bool _emailIsValid = false;
  bool isKeypadOpen = false;
  late CollectionActions collectionActions;
  late List<User> _suggestedUsers;

  // Focus nodes are necessary
  final textFieldFocusNode = FocusNode();
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    collectionActions = CollectionActions(CollectionsService.instance);
    _suggestedUsers = _getSuggestedUser();
  }

  @override
  void dispose() {
    _textController.dispose();
    textFieldFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filterSuggestedUsers = _suggestedUsers
        .where(
          (element) => _matchesUserQuery(
            element,
            _textController.text.trim().toLowerCase(),
          ),
        )
        .toList();
    isKeypadOpen = MediaQuery.viewInsetsOf(context).bottom > 100;

    return ShareScaffold(
      title: _getTitle(),
      subtitle: _getSubtitle(),
      resizeToAvoidBottomInset: isKeypadOpen,
      footer: _bottomActionBar(),
      slivers: _slivers(filterSuggestedUsers),
    );
  }

  List<Widget> _slivers(List<User> filterSuggestedUsers) {
    final footerDescriptions = [
      if (filterSuggestedUsers.isNotEmpty)
        ShareSectionDescription(
          AppLocalizations.of(
            context,
          ).longPressAnEmailToVerifyEndToEndEncryption,
        ),
      ..._roleDescriptionWidgets(),
    ];

    return [
      SliverSafeArea(
        top: false,
        bottom: false,
        sliver: SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          sliver: SliverList.list(
            children: [
              ShareSectionTitle(AppLocalizations.of(context).addANewEmail),
              _enterEmailField(),
              if (filterSuggestedUsers.isNotEmpty) ...[
                const SizedBox(height: Spacing.xxl),
                ShareSectionTitle(
                  AppLocalizations.of(context).orPickAnExistingOne,
                ),
              ],
            ],
          ),
        ),
      ),
      if (filterSuggestedUsers.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          sliver: SliverList.builder(
            itemCount: filterSuggestedUsers.length,
            itemBuilder: (context, index) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _suggestedUserItem(filterSuggestedUsers, index),
                  if (index < filterSuggestedUsers.length - 1)
                    _suggestedUserSeparator(),
                ],
              );
            },
          ),
        ),
      if (footerDescriptions.isNotEmpty)
        SliverSafeArea(
          top: false,
          bottom: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.sm,
            ),
            sliver: SliverList.list(children: footerDescriptions),
          ),
        ),
    ];
  }

  Widget _bottomActionBar() {
    final actionButtons = _actionButtons();
    final bottomPadding = isKeypadOpen ? Spacing.sm : Spacing.xl;
    return SafeArea(
      top: false,
      bottom: !isKeypadOpen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          bottomPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < actionButtons.length; index++) ...[
              actionButtons[index],
              if (index < actionButtons.length - 1)
                const SizedBox(height: Spacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _roleDescriptionWidgets() {
    if (widget.actionTypesToShow.length == 1) {
      return const [];
    }

    return [
      if (widget.actionTypesToShow.contains(ActionTypesToShow.addCollaborator))
        ShareSectionDescription(
          AppLocalizations.of(
            context,
          ).collaboratorsCanAddPhotosAndVideosToTheSharedAlbum,
        ),
      if (widget.actionTypesToShow.contains(ActionTypesToShow.addAdmin))
        ShareSectionDescription(
          AppLocalizations.of(context).adminsCanManagePhotosAndParticipants,
        ),
    ];
  }

  Widget _suggestedUserItem(List<User> users, int index) {
    final currentUser = users[index];
    final borderRadius = MenuGroupComponent.itemBorderRadius(
      index: index,
      itemCount: users.length,
      borderRadius: BorderRadius.circular(Radii.button),
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.componentColors.fillLight,
          borderRadius: borderRadius,
        ),
        child: ShareMenuItem(
          key: ValueKey(
            '${currentUser.email}-${resolveDisplayName(currentUser)}',
          ),
          title: resolveDisplayName(currentUser),
          titleColor: context.componentColors.textLight,
          leading: UserAvatarWidget(currentUser, type: AvatarType.medium),
          trailing: _selectedEmails.contains(currentUser.email)
              ? shareCheck(context)
              : null,
          onTap: () async {
            textFieldFocusNode.unfocus();
            if (_selectedEmails.contains(currentUser.email)) {
              _selectedEmails.remove(currentUser.email);
            } else {
              _selectedEmails.add(currentUser.email);
            }
            setState(() => {});
          },
          onLongPress: () {
            showDialog(
              useRootNavigator: false,
              context: context,
              builder: (BuildContext context) {
                return VerifyIdentifyDialog(
                  self: false,
                  email: currentUser.email,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _suggestedUserSeparator() {
    return ColoredBox(
      color: context.componentColors.fillLight,
      child: const DividerComponent(),
    );
  }

  List<Widget> _actionButtons() {
    final widgets = <Widget>[];
    if (widget.actionTypesToShow.contains(ActionTypesToShow.addCollaborator)) {
      widgets.add(
        ButtonComponent(
          variant:
              widget.actionTypesToShow.contains(ActionTypesToShow.addViewer)
              ? ButtonComponentVariant.neutral
              : ButtonComponentVariant.primary,
          size: ButtonComponentSize.large,
          label: AppLocalizations.of(
            context,
          ).addCollaborators(count: _selectedEmails.length),
          isDisabled: _selectedEmails.isEmpty,
          onTap: () async {
            final results = <bool>[];
            final collections = widget.collections;

            for (String email in _selectedEmails) {
              bool result = false;
              for (Collection collection in collections) {
                result = await collectionActions.addEmailToCollection(
                  context,
                  collection,
                  email,
                  CollectionParticipantRole.collaborator,
                );
              }
              results.add(result);
            }

            final noOfSuccessfullAdds = results.where((e) => e).length;
            if (!mounted) return;
            showToast(
              context,
              AppLocalizations.of(
                context,
              ).collaboratorsSuccessfullyAdded(count: noOfSuccessfullAdds),
            );

            if (!results.any((e) => e == false) && mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    }
    if (widget.actionTypesToShow.contains(ActionTypesToShow.addViewer)) {
      widgets.add(
        ButtonComponent(
          variant: ButtonComponentVariant.primary,
          size: ButtonComponentSize.large,
          label: AppLocalizations.of(
            context,
          ).addViewers(count: _selectedEmails.length),
          isDisabled: _selectedEmails.isEmpty,
          onTap: () async {
            final results = <bool>[];
            final collections = widget.collections;

            for (final email in _selectedEmails) {
              bool result = false;
              for (final collection in collections) {
                result = await collectionActions.addEmailToCollection(
                  context,
                  collection,
                  email,
                  CollectionParticipantRole.viewer,
                );
              }
              results.add(result);
            }

            final noOfSuccessfullAdds = results.where((e) => e).length;
            if (!mounted) return;
            showToast(
              context,
              AppLocalizations.of(
                context,
              ).viewersSuccessfullyAdded(count: noOfSuccessfullAdds),
            );

            if (!results.any((e) => e == false) && mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    }
    if (widget.actionTypesToShow.contains(ActionTypesToShow.addAdmin)) {
      widgets.add(
        ButtonComponent(
          variant: widget.actionTypesToShow.length == 1
              ? ButtonComponentVariant.primary
              : ButtonComponentVariant.neutral,
          size: ButtonComponentSize.large,
          label: AppLocalizations.of(
            context,
          ).addAdmins(count: _selectedEmails.length),
          isDisabled: _selectedEmails.isEmpty,
          onTap: () async {
            final results = <bool>[];
            final collections = widget.collections;

            for (final email in _selectedEmails) {
              bool result = false;
              for (final collection in collections) {
                result = await collectionActions.addEmailToCollection(
                  context,
                  collection,
                  email,
                  CollectionParticipantRole.admin,
                );
              }
              results.add(result);
            }

            final successful = results.where((e) => e).length;
            if (!mounted) return;
            showToast(
              context,
              AppLocalizations.of(
                context,
              ).adminsSuccessfullyAdded(count: successful),
            );

            if (!results.any((e) => e == false) && mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    }
    return widgets;
  }

  void clearFocus() {
    _clearEmailField();
    textFieldFocusNode.unfocus();
    setState(() => {});
  }

  void _clearEmailField() {
    _textController.clear();
    _newEmail = _textController.text;
    _emailIsValid = false;
  }

  Widget _enterEmailField() {
    return Row(
      children: [
        Expanded(
          child: TextInputComponent(
            controller: _textController,
            focusNode: textFieldFocusNode,
            hintText: AppLocalizations.of(context).enterAnEmailAddress,
            isClearable: true,
            shouldUnfocusOnClearOrSubmit: true,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            onChanged: (value) {
              _newEmail = value.trim();
              _emailIsValid = EmailValidator.validate(_newEmail);
              setState(() {});
            },
          ),
        ),
        const SizedBox(width: Spacing.sm),
        IconButtonComponent(
          variant: IconButtonComponentVariant.green,
          tooltip: AppLocalizations.of(context).add,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedMailAdd01),
          onTap: _emailIsValid ? _addNewEmail : null,
        ),
      ],
    );
  }

  Future<void> _addNewEmail() async {
    if (!_emailIsValid) {
      return;
    }
    final result = await collectionActions.doesEmailHaveAccount(
      context,
      _newEmail,
    );
    if (result && mounted) {
      setState(() {
        for (var suggestedUser in _suggestedUsers) {
          if (suggestedUser.email == _newEmail) {
            _selectedEmails.add(suggestedUser.email);
            _clearEmailField();
            textFieldFocusNode.unfocus();

            return;
          }
        }
        _suggestedUsers.insert(0, User(email: _newEmail));
        _selectedEmails.add(_newEmail);
        _clearEmailField();
        textFieldFocusNode.unfocus();
      });
    }
  }

  List<User> _getSuggestedUser() {
    final Set<String> existingEmails = {};
    final collections = widget.collections;
    if (collections.isEmpty) {
      return [];
    }
    final Set<String> ownerEmails = {};

    for (final Collection collection in collections) {
      for (final User u in collection.sharees) {
        if (u.id != null && u.email.isNotEmpty) {
          existingEmails.add(u.email);
        }
      }
      final ownerEmail = collection.owner.email;
      if (ownerEmail.isNotEmpty) {
        ownerEmails.add(ownerEmail);
        existingEmails.add(ownerEmail);
      }
    }

    final List<User> suggestedUsers = UserService.instance.getRelevantContacts()
      ..removeWhere((element) => existingEmails.contains(element.email));

    if (_textController.text.trim().isNotEmpty) {
      suggestedUsers.removeWhere(
        (element) => !_matchesUserQuery(
          element,
          _textController.text.trim().toLowerCase(),
        ),
      );
    }
    suggestedUsers.removeWhere(
      (element) => ownerEmails.contains(element.email),
    );
    suggestedUsers.sort((a, b) => a.email.compareTo(b.email));

    return suggestedUsers;
  }

  String _getTitle() {
    if (widget.actionTypesToShow.length > 1) {
      return AppLocalizations.of(context).addParticipants;
    }
    switch (widget.actionTypesToShow.first) {
      case ActionTypesToShow.addViewer:
        return AppLocalizations.of(context).addViewer;
      case ActionTypesToShow.addCollaborator:
        return AppLocalizations.of(context).addCollaborator;
      case ActionTypesToShow.addAdmin:
        return AppLocalizations.of(context).addAdmin;
    }
  }

  String? _getSubtitle() {
    if (widget.actionTypesToShow.length != 1) {
      return null;
    }
    switch (widget.actionTypesToShow.first) {
      case ActionTypesToShow.addCollaborator:
        return AppLocalizations.of(
          context,
        ).collaboratorsCanAddPhotosAndVideosToTheSharedAlbum;
      case ActionTypesToShow.addAdmin:
        return AppLocalizations.of(
          context,
        ).adminsCanManagePhotosAndParticipants;
      case ActionTypesToShow.addViewer:
        return null;
    }
  }

  bool _matchesUserQuery(User user, String lowerCaseQuery) {
    if (lowerCaseQuery.isEmpty) {
      return true;
    }
    final resolvedName = resolveDisplayName(user).toLowerCase();
    final resolvedEmail = (resolveKnownEmail(user) ?? user.email).toLowerCase();
    return resolvedName.contains(lowerCaseQuery) ||
        resolvedEmail.contains(lowerCaseQuery);
  }
}
