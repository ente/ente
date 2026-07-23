import 'dart:async';

import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/local_backup_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/platform_util.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class RawCodesViewer extends StatefulWidget {
  final List<Code> errors;

  const RawCodesViewer(this.errors, {super.key});

  @override
  State<RawCodesViewer> createState() => _RawCodesViewerState();
}

class _RawCodesViewerState extends State<RawCodesViewer> {
  final Logger _logger = Logger('RawCodesViewer');
  late final List<Code> _errors;

  @override
  void initState() {
    super.initState();
    _errors = List.of(widget.errors);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(elevation: 0, title: Text(context.l10n.rawCodeData)),
      body: _getBody(),
    );
  }

  Widget _getBody() {
    if (_errors.isEmpty) {
      return Center(child: Text(context.l10n.noResult));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _errors.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _RawCodeCard(
          code: _errors[index],
          index: index,
          onDelete: _errors[index].generatedID == null
              ? null
              : () => _confirmDelete(_errors[index]),
        );
      },
    );
  }

  Future<void> _confirmDelete(Code code) async {
    FocusScope.of(context).requestFocus();
    final l10n = context.l10n;
    final result = await showChoiceActionSheet(
      context,
      title: l10n.deleteUnparseableCodeTitle,
      body: l10n.deleteUnparseableCodeMessage,
      firstButtonLabel: l10n.delete,
      isCritical: true,
    );
    if (result?.action != ButtonAction.first || !mounted) {
      return;
    }
    final isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(context, l10n.deleteCodeAuthMessage);
    if (!isAuthSuccessful) {
      return;
    }
    await _deleteCode(code);
  }

  Future<void> _deleteCode(Code code) async {
    try {
      await CodeStore.instance.removeCode(code);
      LocalBackupService.instance.triggerDailyBackupIfNeeded().ignore();
      if (!mounted) {
        return;
      }
      setState(() {
        _errors.removeWhere((error) => error.generatedID == code.generatedID);
      });
    } catch (e, s) {
      _logger.severe('Failed to delete unparseable code', e, s);
      if (mounted) {
        showGenericErrorDialog(context: context, error: e).ignore();
      }
    }
  }
}

class _RawCodeCard extends StatelessWidget {
  const _RawCodeCard({
    required this.code,
    required this.index,
    required this.onDelete,
  });

  final Code code;
  final int index;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final parseError = code.err?.toString();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.codeCardBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.l10n.rawCodeData} ${index + 1}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.delete,
                visualDensity: VisualDensity.compact,
                color: colorScheme.warning700,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          if (parseError != null && parseError.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.parsingError,
              style: TextStyle(
                color: colorScheme.warning700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              parseError,
              selectionControls: PlatformUtil.selectionControls,
              style: TextStyle(
                color: colorScheme.warning700,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ],
          const SizedBox(height: 6),
          SelectableText(
            code.rawData,
            selectionControls: PlatformUtil.selectionControls,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1.2,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
