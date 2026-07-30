import 'dart:async';

import 'package:dio/dio.dart';
import 'package:ente_account_deletion/src/account_deletion_settings.dart';
import 'package:ente_account_deletion/src/models/account_deletion_summary.dart';
import 'package:ente_account_deletion/src/ui/delete_account_bottom_actions.dart';
import 'package:ente_account_deletion/src/ui/delete_account_confirmation_step.dart';
import 'package:ente_account_deletion/src/ui/delete_account_reason_step.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _logger = Logger('DeleteAccountPage');
  final _feedbackController = TextEditingController();
  DeleteAccountReason? _selectedReason;
  _DeleteAccountStep _step = _DeleteAccountStep.reason;
  bool _confirmationAccepted = false;
  bool _isDeleting = false;
  AccountDeletionSummary? _summary;
  bool _summaryUnsupported = false;
  bool _summaryLoading = false;

  AccountDeletionSettings get _settings => AccountDeletionSettings.instance;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isConfirmationStep = _step == _DeleteAccountStep.confirmation;
    final isActionEnabled = isConfirmationStep
        ? _confirmationAccepted &&
              (_summary != null || _summaryUnsupported) &&
              !_summaryLoading &&
              !_isDeleting
        : _selectedReason != null && !_isDeleting;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.xl,
        ),
        child: DeleteAccountBottomActions(
          isConfirmationStep: isConfirmationStep,
          isActionEnabled: isActionEnabled,
          onContinue: _goToConfirmation,
          onDelete: _deleteAccount,
        ),
      ),
      body: AppBarComponent(
        title: context.strings.deleteAccount,
        onBack: _handleBack,
        slivers: [
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              sliver: SliverToBoxAdapter(
                child: isConfirmationStep
                    ? DeleteAccountConfirmationStep(
                        summary: _summary,
                        summaryUnsupported: _summaryUnsupported,
                        isLoading: _summaryLoading,
                        confirmed: _confirmationAccepted,
                        onConfirmationChanged: (value) {
                          setState(() => _confirmationAccepted = value);
                        },
                        onRetrySummary: () => unawaited(_loadSummary()),
                      )
                    : DeleteAccountReasonStep(
                        selectedReason: _selectedReason,
                        feedbackController: _feedbackController,
                        onReasonChanged: (reason) {
                          setState(() => _selectedReason = reason);
                        },
                      ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Spacing.xl)),
        ],
      ),
    );
  }

  void _goToConfirmation() {
    setState(() => _step = _DeleteAccountStep.confirmation);
    if (_summary == null && !_summaryLoading) {
      unawaited(_loadSummary());
    }
  }

  void _handleBack() {
    if (_isDeleting) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
    });
    try {
      final summary = await _settings.service.getDeletionSummary();
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
        _summaryUnsupported = false;
        _summaryLoading = false;
      });
    } catch (e, s) {
      final summaryUnsupported =
          e is DioException && e.response?.statusCode == 404;
      if (!summaryUnsupported) {
        _logger.warning('Failed to load account deletion summary', e, s);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = null;
        _summaryUnsupported = summaryUnsupported;
        _summaryLoading = false;
      });
    }
  }

  Future<void> _deleteAccount() async {
    final reason = _selectedReason!;
    try {
      setState(() => _isDeleting = true);
      final encryptedChallenge = await _settings.service.getDeleteChallenge();
      final challenge = _settings.host.decryptDeleteChallenge(
        encryptedChallenge,
      );
      await _settings.service.deleteAccount(
        challenge: challenge,
        reasonCategory: reason.apiValue,
        feedback: _optionalFeedback,
      );
      await _settings.host.logout();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e, s) {
      _logger.severe('Failed to delete account', e, s);
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      await showErrorBottomSheetComponent<void>(
        context: context,
        title: context.strings.error,
        message: context.strings.somethingWentWrong,
      );
    }
  }

  String? get _optionalFeedback {
    final feedback = _feedbackController.text.trim();
    return feedback.isEmpty ? null : feedback;
  }
}

enum _DeleteAccountStep { reason, confirmation }
