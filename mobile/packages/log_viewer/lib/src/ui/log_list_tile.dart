import 'package:flutter/material.dart';
import 'package:log_viewer/src/core/log_models.dart';

/// Individual log item widget
class LogListTile extends StatelessWidget {
  final LogEntry log;
  final VoidCallback onTap;

  const LogListTile({super.key, required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      tileColor: log.backgroundColor,
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: log.levelColor,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(
        log.truncatedMessage,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: theme.textTheme.bodyLarge?.color,
        ),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              size: 12,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 4),
            Text(
              log.formattedTime,
              style: TextStyle(
                fontSize: 11,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.source,
              size: 12,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                log.loggerName,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.textTheme.bodySmall?.color,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (log.error != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
            ],
          ],
        ),
      ),
      trailing: Icon(Icons.chevron_right, size: 20, color: theme.disabledColor),
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
