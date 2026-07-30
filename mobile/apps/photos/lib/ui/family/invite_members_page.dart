import 'dart:math' as math;

import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/family_service.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/base_bottom_sheet.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import 'package:photos/ui/family/family_ui.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/share_util.dart';

class InviteMembersPageResult {
  const InviteMembersPageResult._(this.sentCount);

  const InviteMembersPageResult.invitesSent(int sentCount) : this._(sentCount);

  final int sentCount;

  bool get invitesSent => sentCount > 0;
}

class InviteMembersPage extends StatefulWidget {
  const InviteMembersPage({
    required this.userDetails,
    required this.remainingSlots,
    super.key,
  });

  final UserDetails userDetails;
  final int remainingSlots;

  @override
  State<InviteMembersPage> createState() => _InviteMembersPageState();
}

class _InviteMembersPageState extends State<InviteMembersPage> {
  static const int _maxFamilyMembers = 5;

  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final List<String> _emails = [];
  late final Set<String> _existingEmails;
  late int _remainingSlots;

  String? _errorMessage;
  bool _isCheckingEmail = false;

  int get _inviteSlotsLeft => math.max(0, _remainingSlots - _emails.length);

  bool get _canAddMore => _inviteSlotsLeft > 0;

  bool get _showsInviteLimitHint =>
      !_canAddMore && _emailFocusNode.hasFocus && _errorMessage == null;

  @override
  void initState() {
    super.initState();
    _remainingSlots = widget.remainingSlots;
    _emailFocusNode.addListener(_handleFocusChange);
    _existingEmails = {
      for (final member in widget.userDetails.familyData?.members ?? [])
        member.email.trim().toLowerCase(),
    };
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);

    return FamilyPageScaffold(
      title: l10n.inviteMembers,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInputRow(context),
                  if (_fieldMessage(l10n) case final message?) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        message,
                        style: _errorMessage != null
                            ? textTheme.small.copyWith(
                                color: getEnteColorScheme(context).redBase,
                              )
                            : textTheme.smallMuted,
                      ),
                    ),
                  ],
                  _InviteEmailList(emails: _emails, onRemove: _removeEmail),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.primary,
            isDisabled: _emails.isEmpty,
            labelText: _sendInvitesLabel(l10n),
            onTap: _handleSendInvites,
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);
    final hasError = _errorMessage != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 58,
            decoration: BoxDecoration(
              color: colorScheme.fillFaint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasError ? colorScheme.redBase : colorScheme.strokeMuted,
              ),
            ),
            child: TextField(
              controller: _emailController,
              focusNode: _emailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofocus: _canAddMore,
              enabled: !_isCheckingEmail,
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage = null;
                  });
                }
              },
              onSubmitted: (_) => _addEmail(),
              decoration: InputDecoration(
                hintText: l10n.emailAddress,
                hintStyle: textTheme.bodyFaint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
              style: textTheme.body,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _isCheckingEmail ? null : _addEmail,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colorScheme.fillFaint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.strokeMuted),
            ),
            child: Center(
              child: _isCheckingEmail
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.greenBase,
                      ),
                    )
                  : Icon(Icons.add, size: 24, color: colorScheme.content),
            ),
          ),
        ),
      ],
    );
  }

  String _sendInvitesLabel(AppLocalizations l10n) {
    return l10n.sendCountInvites(count: _emails.length);
  }

  String? _fieldMessage(AppLocalizations l10n) {
    if (_errorMessage != null) {
      return _errorMessage;
    }
    if (_showsInviteLimitHint) {
      return l10n.inviteLimitReached;
    }
    return null;
  }

  void _handleFocusChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  int _remainingSlotsFor(UserDetails details) {
    final memberCount =
        details.familyData?.members
            ?.where(
              (member) =>
                  member.email.trim().toLowerCase() !=
                  details.email.trim().toLowerCase(),
            )
            .length ??
        0;
    return math.max(0, _maxFamilyMembers - memberCount);
  }

  Future<void> _addEmail() async {
    if (_isCheckingEmail) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim().toLowerCase();
    if (!_canAddMore) {
      setState(() => _errorMessage = l10n.inviteLimitReached);
      return;
    }
    if (email.isEmpty) {
      setState(() => _errorMessage = l10n.enterAnEmailAddress);
      return;
    }
    if (!EmailValidator.validate(email)) {
      setState(() => _errorMessage = l10n.enterAValidEmailAddress);
      return;
    }
    if (_emails.contains(email) || _existingEmails.contains(email)) {
      setState(() => _errorMessage = l10n.alreadyAdded);
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _errorMessage = null;
    });

    try {
      final publicKey = await UserService.instance.getPublicKey(email);
      if (publicKey == null) {
        if (!mounted) {
          return;
        }
        await _showInviteToEnteSheet(email);
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _emails.add(email);
        _emailController.clear();
        _errorMessage = null;
      });
      _emailFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await showGenericErrorDialog(context: context, error: error);
    } finally {
      if (mounted) {
        setState(() => _isCheckingEmail = false);
      }
    }
  }

  void _removeEmail(String email) {
    setState(() {
      _emails.remove(email);
      _errorMessage = null;
    });
  }

  Future<void> _handleSendInvites() async {
    try {
      final result = await FamilyService.instance.inviteMembers(
        userDetails: widget.userDetails,
        emails: List<String>.from(_emails),
      );
      if (!mounted) {
        return;
      }

      if (!result.hasFailures) {
        Navigator.of(
          context,
        ).pop(InviteMembersPageResult.invitesSent(_emails.length));
        return;
      }

      final hadAnySuccess = result.failures.length < _emails.length;
      final failedEmailSet = result.failures
          .map((failure) => failure.email)
          .toSet();
      final successfulEmails = _emails
          .where((email) => !failedEmailSet.contains(email))
          .toList();
      UserDetails? refreshedDetails;
      if (hadAnySuccess) {
        try {
          refreshedDetails = await FamilyService.instance.refreshUserDetails();
        } catch (_) {}
      }

      final failedEmails = result.failures
          .map((failure) => failure.email)
          .toList();
      setState(() {
        if (refreshedDetails != null) {
          final details = refreshedDetails;
          _remainingSlots = _remainingSlotsFor(details);
          _existingEmails
            ..clear()
            ..addAll({
              for (final member in details.familyData?.members ?? [])
                member.email.trim().toLowerCase(),
            });
        } else {
          _remainingSlots = math.max(
            0,
            _remainingSlots - successfulEmails.length,
          );
          _existingEmails.addAll(successfulEmails);
        }
        _emails
          ..clear()
          ..addAll(failedEmails);
      });
      if (mounted) {
        showToast(
          context,
          failedEmails.length == 1
              ? AppLocalizations.of(
                  context,
                ).failedToInvite(email: failedEmails.first)
              : AppLocalizations.of(
                  context,
                ).failedToInviteCount(count: failedEmails.length),
        );
      }
      throw const _HandledInviteActionException();
    } catch (error) {
      if (error is _HandledInviteActionException) {
        rethrow;
      }
      if (!mounted) {
        throw const _HandledInviteActionException();
      }
      await showGenericErrorDialog(context: context, error: error);
      throw const _HandledInviteActionException();
    }
  }

  Future<void> _showInviteToEnteSheet(String email) {
    final l10n = AppLocalizations.of(context);
    return showBaseBottomSheet<void>(
      context,
      title: l10n.inviteToEnte,
      headerSpacing: 20,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.emailNeedsEnteAccountForFamily(email: email),
            textAlign: TextAlign.start,
            style: getEnteTextTheme(context).smallMuted,
          ),
          const SizedBox(height: 20),
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.neutral,
            labelText: l10n.sendInvite,
            leadingWidget: const Icon(Icons.ios_share_outlined),
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              await shareText(l10n.shareTextRecommendUsingEnteForFamily);
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _InviteEmailList extends StatefulWidget {
  const _InviteEmailList({required this.emails, required this.onRemove});

  final List<String> emails;
  final ValueChanged<String> onRemove;

  @override
  State<_InviteEmailList> createState() => _InviteEmailListState();
}

class _InviteEmailListState extends State<_InviteEmailList> {
  static const _animationDuration = Duration(milliseconds: 200);

  final _listKey = GlobalKey<AnimatedListState>();
  late List<String> _displayedEmails = List<String>.from(widget.emails);

  @override
  void didUpdateWidget(covariant _InviteEmailList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncEmails();
  }

  void _syncEmails() {
    final nextEmails = List<String>.from(widget.emails);
    final nextEmailSet = nextEmails.toSet();

    if (_listKey.currentState == null) {
      setState(() {
        _displayedEmails = nextEmails;
      });
      return;
    }

    for (var i = _displayedEmails.length - 1; i >= 0; i--) {
      final email = _displayedEmails[i];
      if (nextEmailSet.contains(email)) {
        continue;
      }

      final removedEmail = _displayedEmails.removeAt(i);
      _listKey.currentState!.removeItem(
        i,
        (context, animation) =>
            _buildAnimatedEmailItem(removedEmail, animation),
        duration: _animationDuration,
      );
    }

    for (var i = 0; i < nextEmails.length; i++) {
      final nextEmail = nextEmails[i];
      if (i < _displayedEmails.length && _displayedEmails[i] == nextEmail) {
        continue;
      }

      final existingIndex = _displayedEmails.indexOf(nextEmail);
      if (existingIndex != -1) {
        setState(() {
          _displayedEmails = nextEmails;
        });
        return;
      }

      _displayedEmails.insert(i, nextEmail);
      _listKey.currentState!.insertItem(i, duration: _animationDuration);
    }

    setState(() {});
  }

  Widget _buildAnimatedEmailItem(String email, Animation<double> animation) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curvedAnimation,
      child: SizeTransition(
        sizeFactor: curvedAnimation,
        axisAlignment: -1,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.04),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EmailChip(
              email: email,
              onRemove: () => widget.onRemove(email),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _animationDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _displayedEmails.isEmpty
          ? const SizedBox(height: 0, width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AnimatedList(
                key: _listKey,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                initialItemCount: _displayedEmails.length,
                itemBuilder: (context, index, animation) {
                  return _buildAnimatedEmailItem(
                    _displayedEmails[index],
                    animation,
                  );
                },
              ),
            ),
    );
  }
}

class _EmailChip extends StatelessWidget {
  const _EmailChip({required this.email, required this.onRemove});

  final String email;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final rowTextStyle = textTheme.body.copyWith(
      fontSize: 15,
      height: 18.75 / 15,
    );
    final rowIconColor = textTheme.bodyFaint.color;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.fillFaint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(email, style: rowTextStyle)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Icon(Icons.close, size: 18, color: rowIconColor),
          ),
        ],
      ),
    );
  }
}

class _HandledInviteActionException implements Exception {
  const _HandledInviteActionException();
}
