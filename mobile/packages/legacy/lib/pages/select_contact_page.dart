import "package:email_validator/email_validator.dart";
import "package:ente_accounts/services/user_service.dart";
import "package:ente_configuration/base_configuration.dart";
import "package:ente_contacts/contacts.dart";
import "package:ente_legacy/components/gradient_button.dart";
import "package:ente_legacy/components/recovery_date_selector.dart";
import "package:ente_legacy/models/emergency_models.dart";
import "package:ente_legacy/services/emergency_service.dart";
import "package:ente_sharing/extensions/user_extension.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:ente_sharing/verify_identity_dialog.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/alert_bottom_sheet.dart";
import "package:ente_ui/components/base_bottom_sheet.dart";
import "package:ente_ui/components/captioned_text_widget_v2.dart";
import "package:ente_ui/components/divider_widget.dart";
import "package:ente_ui/components/menu_item_widget_v2.dart";
import "package:ente_ui/theme/colors.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:ente_ui/theme/text_style.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";

/// Shows the add contact bottom sheet and returns true if a contact was added
Future<bool?> showAddContactSheet(
  BuildContext context, {
  required EmergencyInfo emergencyInfo,
  required BaseConfiguration config,
}) {
  return showBaseBottomSheet<bool>(
    context,
    title: context.strings.addTrustedContact,
    headerSpacing: 20,
    isKeyboardAware: true,
    child: AddContactSheet(emergencyInfo: emergencyInfo, config: config),
  );
}

class AddContactSheet extends StatefulWidget {
  final EmergencyInfo emergencyInfo;
  final BaseConfiguration config;

  const AddContactSheet({
    required this.emergencyInfo,
    required this.config,
    super.key,
  });

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  String selectedEmail = "";
  String _email = "";
  bool _emailIsValid = false;
  int _selectedRecoveryDays = 14;
  late final Logger _logger = Logger("AddContactSheet");

  final textFieldFocusNode = FocusNode();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    textFieldFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ContactsDisplayService.instance.changes,
      builder: (context, _, _) {
        final colorScheme = getEnteColorScheme(context);
        final textTheme = getEnteTextTheme(context);
        final List<User> suggestedUsers = _getSuggestedUser();
        final bool canAdd = selectedEmail.isNotEmpty || _emailIsValid;

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEmailInputRow(colorScheme),
              if (suggestedUsers.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildExistingContactsSection(
                  suggestedUsers,
                  colorScheme,
                  textTheme,
                ),
              ],
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.strings.chooseARecoveryTime,
                    style: textTheme.bodyMuted,
                  ),
                  const SizedBox(height: 12),
                  RecoveryDateSelector(
                    selectedDays: _selectedRecoveryDays,
                    onDaysChanged: (days) {
                      setState(() {
                        _selectedRecoveryDays = days;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GradientButton(
                text: context.strings.addTrustedContact,
                onTap: canAdd ? _onAddContactTap : null,
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: _onVerifyTap,
                  child: Text(
                    context.strings.verifyIDLabel,
                    style: textTheme.bodyBold.copyWith(
                      color: canAdd
                          ? getEnteColorScheme(context).primary700
                          : getEnteColorScheme(context).textMuted,
                      decoration: TextDecoration.underline,
                      decorationColor: canAdd
                          ? getEnteColorScheme(context).primary700
                          : getEnteColorScheme(context).textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmailInputRow(EnteColorScheme colorScheme) {
    return TextFormField(
      controller: _textController,
      focusNode: textFieldFocusNode,
      decoration: InputDecoration(
        fillColor: colorScheme.fillFaint,
        filled: true,
        hintText: context.strings.enterEmail,
        hintStyle: TextStyle(color: colorScheme.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.strokeMuted),
        ),
      ),
      onChanged: (value) {
        if (selectedEmail != "") {
          selectedEmail = "";
        }
        _email = value.trim();
        _emailIsValid = EmailValidator.validate(_email);
        setState(() {});
      },
      autocorrect: false,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
    );
  }

  Widget _buildExistingContactsSection(
    List<User> suggestedUsers,
    EnteColorScheme colorScheme,
    EnteTextTheme textTheme,
  ) {
    const double maxVisibleHeight = 121.0;
    final showScrollbar = suggestedUsers.length > 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.chooseFromAnExistingContact,
          style: textTheme.bodyMuted,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: maxVisibleHeight),
                child: ListView.separated(
                  controller: _scrollController,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: suggestedUsers.length,
                  separatorBuilder: (context, index) => DividerWidget(
                    dividerType: DividerType.menu,
                    bgColor: colorScheme.fillFaint,
                  ),
                  itemBuilder: (context, index) {
                    final user = suggestedUsers[index];
                    final isFirst = index == 0;
                    final isLast = index == suggestedUsers.length - 1;
                    return MenuItemWidgetV2(
                      captionedTextWidget: CaptionedTextWidgetV2(
                        title: user.resolvedDisplayName,
                        textStyle: textTheme.small.copyWith(
                          color: colorScheme.textMuted,
                        ),
                      ),
                      leadingIconSize: 24.0,
                      leadingIconWidget: UserAvatarWidget(
                        user,
                        type: AvatarType.mini,
                        currentUserID: widget.config.getUserID()!,
                        config: widget.config,
                        thumbnailView: false,
                      ),
                      menuItemColor: colorScheme.fillFaint,
                      pressedColor: colorScheme.fillFaintPressed,
                      trailingIcon: (selectedEmail == user.email)
                          ? Icons.check
                          : null,
                      trailingIconColor: colorScheme.primary500,
                      surfaceExecutionStates: false,
                      onTap: () async {
                        textFieldFocusNode.unfocus();
                        if (selectedEmail == user.email) {
                          selectedEmail = "";
                        } else {
                          selectedEmail = user.email;
                        }
                        setState(() {});
                      },
                      isTopBorderRadiusRemoved: !isFirst,
                      isBottomBorderRadiusRemoved: !isLast,
                      isFirstItem: isFirst,
                      isLastItem: isLast,
                      singleBorderRadius: 20,
                      multipleBorderRadius: 20,
                    );
                  },
                ),
              ),
            ),
            if (showScrollbar) ...[
              const SizedBox(width: 4),
              _buildCustomScrollbar(
                suggestedUsers.length,
                maxVisibleHeight,
                colorScheme,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCustomScrollbar(
    int itemCount,
    double containerHeight,
    EnteColorScheme colorScheme,
  ) {
    const visibleItems = 2;
    final thumbHeightRatio = visibleItems / itemCount;
    final thumbHeight = containerHeight * thumbHeightRatio;

    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, child) {
        double thumbPosition = 0;
        if (_scrollController.hasClients) {
          final maxExtent = _scrollController.position.hasContentDimensions
              ? _scrollController.position.maxScrollExtent
              : 0.0;
          if (maxExtent > 0) {
            final scrollFraction = _scrollController.offset / maxExtent;
            thumbPosition = scrollFraction * (containerHeight - thumbHeight);
          }
        }

        return SizedBox(
          height: containerHeight,
          width: 5,
          child: Stack(
            children: [
              Container(
                width: 5,
                height: containerHeight,
                decoration: BoxDecoration(
                  color: colorScheme.strokeFaint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Positioned(
                top: thumbPosition,
                child: Container(
                  width: 5,
                  height: thumbHeight,
                  decoration: BoxDecoration(
                    color: colorScheme.strokeMuted,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onAddContactTap() async {
    final emailToAdd = selectedEmail.isNotEmpty ? selectedEmail : _email;
    final confirmed = await _showAddContactConfirmationSheet(
      emailToAdd,
      _selectedRecoveryDays,
    );
    if (confirmed == true) {
      try {
        final success = await EmergencyContactService.instance.addContact(
          mounted ? context : null,
          emailToAdd,
          _selectedRecoveryDays,
        );
        if (success && mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        _logger.severe("Failed to add contact", e);
        if (mounted) {
          await showAlertBottomSheet(
            context,
            title: context.strings.error,
            message: context.strings.somethingWentWrong,
            assetPath: "assets/warning-blue.png",
          );
        }
      }
    }
  }

  Future<bool?> _showAddContactConfirmationSheet(
    String email,
    int recoveryDays,
  ) {
    final colorScheme = getEnteColorScheme(context);

    return showAlertBottomSheet<bool>(
      context,
      title: context.strings.warning,
      message: context.strings.confirmAddingTrustedContact(email, recoveryDays),
      assetPath: "assets/warning-blue.png",
      buttons: [
        GradientButton(
          onTap: () => Navigator.of(context).pop(true),
          text: context.strings.proceed,
          backgroundColor: colorScheme.warning400,
        ),
      ],
    );
  }

  Future<void> _onVerifyTap() async {
    if (selectedEmail.isEmpty && !_emailIsValid) {
      await showAlertBottomSheet(
        context,
        title: context.strings.invalidEmailAddress,
        message: context.strings.enterValidEmail,
        assetPath: "assets/warning-blue.png",
      );
      return;
    }
    final emailToAdd = selectedEmail.isNotEmpty ? selectedEmail : _email;
    await showVerifyIdentitySheet(
      context,
      self: false,
      email: emailToAdd,
      config: widget.config,
    );
  }

  List<User> _getSuggestedUser() {
    final List<User> suggestedUsers = [];
    final Set<String> existingEmails = {};

    existingEmails.add(widget.config.getEmail() ?? "");

    // Get suggested users from othersEmergencyContact (people who added you)
    for (final contact in widget.emergencyInfo.othersEmergencyContact) {
      if (!existingEmails.contains(contact.user.email)) {
        existingEmails.add(contact.user.email);
        suggestedUsers.add(contact.user);
      }
    }

    final cachedUserDetails = UserService.instance.getCachedUserDetails();
    if (cachedUserDetails != null &&
        (cachedUserDetails.familyData?.members?.isNotEmpty ?? false)) {
      for (final member in cachedUserDetails.familyData!.members!) {
        if (!existingEmails.contains(member.email)) {
          existingEmails.add(member.email);
          suggestedUsers.add(User(email: member.email));
        }
      }
    }

    // Filter by search text
    if (_textController.text.trim().isNotEmpty) {
      suggestedUsers.removeWhere(
        (element) => !element.matchesResolvedNameOrEmail(_textController.text),
      );
    }
    suggestedUsers.sort(
      (a, b) => a.resolvedDisplayName.toLowerCase().compareTo(
        b.resolvedDisplayName.toLowerCase(),
      ),
    );

    return suggestedUsers;
  }
}
