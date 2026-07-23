import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:log_viewer/src/core/log_models.dart';

/// Detailed view of a single log entry
class LogDetailPage extends StatelessWidget {
  final LogEntry log;

  const LogDetailPage({super.key, required this.log});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required String content,
    bool isMonospace = true,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copyToClipboard(context, content, title),
                tooltip: 'Copy $title',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor, width: 1),
            ),
            child: SelectableText(
              content,
              style: TextStyle(
                fontFamily: isMonospace ? 'monospace' : null,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.disabledColor),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: valueColor != null ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Details'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () =>
                _copyToClipboard(context, log.toString(), 'Complete log'),
            tooltip: 'Copy all',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Log metadata
            Container(
              width: double.infinity,
              color: theme.appBarTheme.backgroundColor,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  _buildInfoRow(
                    context: context,
                    icon: Icons.access_time,
                    label: 'Time',
                    value: '${log.timestamp.toLocal()}',
                  ),
                  _buildInfoRow(
                    context: context,
                    icon: Icons.flag,
                    label: 'Level',
                    value: log.level,
                    valueColor: log.levelColor,
                  ),
                  _buildInfoRow(
                    context: context,
                    icon: Icons.source,
                    label: 'Logger',
                    value: log.loggerName,
                  ),
                ],
              ),
            ),

            // Message section
            _buildSection(
              context: context,
              title: 'MESSAGE',
              content: log.message,
            ),

            // Error section (if present)
            if (log.error != null)
              _buildSection(
                context: context,
                title: 'ERROR',
                content: log.error!,
              ),

            // Stack trace section (if present)
            if (log.stackTrace != null)
              _buildSection(
                context: context,
                title: 'STACK TRACE',
                content: log.stackTrace!,
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
