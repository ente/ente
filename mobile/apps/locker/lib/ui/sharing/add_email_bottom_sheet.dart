import "package:ente_accounts/services/user_service.dart";
import "package:ente_components/ente_components.dart";
import 'package:ente_contacts/contacts.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_sharing/extensions/user_extension.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:ente_sharing/verify_identity_dialog.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/date_time_picker.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/configuration.dart";
import "package:locker/ui/components/custom_list_scrollbar.dart";
import "package:locker/utils/collection_actions.dart";

Future<void> showAddEmailSheet(
  BuildContext context, {
  required Collection collection,
  required VoidCallback onShareAdded,
}) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) =>
        AddEmailSheet(collection: collection, onShareAdded: onShareAdded),
  );
}

class AddEmailSheet extends StatefulWidget {
  final Collection collection;
  final VoidCallback onShareAdded;

  const AddEmailSheet({
    super.key,
    required this.collection,
    required this.onShareAdded,
  });

  @override
  State<AddEmailSheet> createState() => _AddEmailSheetState();
}

class _AddEmailSheetState extends State<AddEmailSheet> {
  final bool _shareLater = false;
  String _email = "";
  bool _emailIsValid = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  final CollectionParticipantRole _selectedRole =
      CollectionParticipantRole.viewer;

  final _textController = TextEditingController();
  final _textFieldFocusNode = FocusNode();
  final _scrollController = ScrollController();

  late CollectionActions _collectionActions;
  late List<UserSuggestion> _suggestedUsers;

  @override
  void initState() {
    super.initState();
    _collectionActions = CollectionActions();
    _suggestedUsers = _getSuggestedUsers();
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFieldFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: context.strings.addNewEmail,
      isKeyboardAware: true,
      content: ValueListenableBuilder<int>(
        valueListenable: ContactsDisplayService.instance.changes,
        builder: (context, _, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEmailInputField(),
              if (_suggestedUsers.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildExistingContactsSection(),
              ],
              if (_shareLater) ...[
                const SizedBox(height: 12),
                _buildScheduleDateTimeRow(),
              ],
            ],
          );
        },
      ),
      actions: [_buildShareButton()],
    );
  }

  Widget _buildEmailInputField() {
    return TextInputComponent(
      controller: _textController,
      focusNode: _textFieldFocusNode,
      hintText: context.strings.enterNameOrEmailToShareWith,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      shouldUnfocusOnClearOrSubmit: true,
      onChanged: (value) {
        _email = value.trim();
        _emailIsValid = isValidEmail(_email);
        setState(() {});
      },
    );
  }

  Widget _buildExistingContactsSection() {
    final colors = context.componentColors;
    final filteredUsers =
        _suggestedUsers
            .where(
              (user) => user.matchesResolvedNameOrEmail(_textController.text),
            )
            .toList()
          ..sort(
            (a, b) => a.resolvedDisplayName.toLowerCase().compareTo(
              b.resolvedDisplayName.toLowerCase(),
            ),
          );

    if (filteredUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    const double maxVisibleHeight = 121.0;
    final showScrollbar = filteredUsers.length > 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.chooseFromAnExistingContact,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: maxVisibleHeight,
                  ),
                  child: ListView.separated(
                    controller: _scrollController,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: filteredUsers.length,
                    separatorBuilder: (_, _) => ColoredBox(
                      color: colors.fillLight,
                      child: const DividerComponent(
                        padding: EdgeInsets.only(left: 48),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      return MenuGroupComponent(
                        backgroundColor: colors.fillLight,
                        borderRadius: MenuGroupComponent.itemBorderRadius(
                          index: index,
                          itemCount: filteredUsers.length,
                        ),
                        items: [
                          MenuComponent(
                            title: user.resolvedDisplayName,
                            leading: UserAvatarWidget.suggestion(
                              user,
                              type: AvatarType.mini,
                              config: Configuration.instance,
                            ),
                            onTap: () async {
                              _textFieldFocusNode.unfocus();
                              _textController.text = user.email;
                              _email = user.email;
                              _emailIsValid = true;
                              setState(() {});
                            },
                            onLongPress: () {
                              showVerifyIdentitySheet(
                                context,
                                self: false,
                                config: Configuration.instance,
                                email: user.email,
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            if (showScrollbar) ...[
              const SizedBox(width: 4),
              CustomListScrollbar(
                scrollController: _scrollController,
                itemCount: filteredUsers.length,
                visibleItems: 2,
                containerHeight: maxVisibleHeight,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildScheduleDateTimeRow() {
    final colors = context.componentColors;
    final dateText = _scheduledDate != null
        ? DateFormat("dd/MM/yy").format(_scheduledDate!)
        : "DD/MM/YY";
    final timeText = _scheduledTime != null
        ? "${_scheduledTime!.hour.toString().padLeft(2, '0')}:${_scheduledTime!.minute.toString().padLeft(2, '0')}"
        : "00:00";

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: colors.fillLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: colors.textLight,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateText,
                    style: TextStyles.body.copyWith(
                      color: _scheduledDate != null
                          ? colors.textBase
                          : colors.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _selectTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: colors.fillLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_outlined,
                    size: 18,
                    color: colors.textLight,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeText,
                    style: TextStyles.body.copyWith(
                      color: _scheduledTime != null
                          ? colors.textBase
                          : colors.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final initialDate =
        _scheduledDate ?? DateTime.now().add(const Duration(days: 1));
    final pickedDate = await showDateTimePickerSheet(
      context,
      initialDateTime: initialDate,
      minDateTime: DateTime.now(),
    );
    if (pickedDate != null && mounted) {
      setState(() {
        _scheduledDate = pickedDate;
      });
    }
  }

  Future<void> _selectTime() async {
    final initialTime = _scheduledTime ?? TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime != null && mounted) {
      setState(() {
        _scheduledTime = pickedTime;
      });
    }
  }

  Widget _buildShareButton() {
    final bool canShare =
        _emailIsValid && (!_shareLater || _isScheduledDateTimeValid());
    final buttonText = _shareLater
        ? context.strings.scheduleShare
        : context.strings.share;
    return ButtonComponent(
      label: buttonText,
      onTap: canShare ? _onShareTap : null,
    );
  }

  Future<void> _onShareTap() async {
    final success = await _collectionActions.addEmailToCollection(
      context,
      widget.collection,
      _email,
      _selectedRole,
      showProgress: true,
    );

    if (success) {
      widget.onShareAdded();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  List<UserSuggestion> _getSuggestedUsers() {
    final int ownerID = Configuration.instance.getUserID()!;
    final suggestedUsers = <UserSuggestion>[];
    final existingEmails = <String>{Configuration.instance.getEmail() ?? ""};

    void add(String email, {int? userID}) {
      if (email.isNotEmpty && existingEmails.add(email)) {
        suggestedUsers.add(UserSuggestion(email, userID: userID));
      }
    }

    for (final c in CollectionService.instance.getActiveCollections()) {
      if (c.owner.id == ownerID) {
        for (final User u in c.sharees) {
          add(u.email, userID: u.id);
        }
      } else {
        add(c.owner.email, userID: c.owner.id);
      }
    }

    final familyMembers =
        UserService.instance.getCachedUserDetails()?.familyData?.members ?? [];
    for (final member in familyMembers) {
      add(member.email, userID: member.userID);
    }

    suggestedUsers.sort((a, b) {
      final byName = a.resolvedDisplayName.toLowerCase().compareTo(
        b.resolvedDisplayName.toLowerCase(),
      );
      return byName != 0 ? byName : a.email.compareTo(b.email);
    });
    return suggestedUsers;
  }

  bool _isScheduledDateTimeValid() {
    if (_scheduledDate == null || _scheduledTime == null) {
      return false;
    }
    final scheduledDateTime = DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      _scheduledTime!.hour,
      _scheduledTime!.minute,
    );
    return scheduledDateTime.isAfter(DateTime.now());
  }
}
