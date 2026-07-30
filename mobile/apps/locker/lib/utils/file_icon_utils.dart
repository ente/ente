import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum FileIconColorRole { warning, green, primary, neutral }

class FileIconConfig {
  final dynamic icon;
  final Set<String> extensions;
  final FileIconColorRole colorRole;

  const FileIconConfig({
    required this.icon,
    required this.extensions,
    required this.colorRole,
  });
}

class FileIconUtils {
  // Centralized configuration - change icons and colors here only
  static const Map<String, FileIconConfig> _fileTypeConfigs = {
    'pdf': FileIconConfig(
      extensions: {'.pdf'},
      icon: HugeIcons.strokeRoundedFile01,
      colorRole: FileIconColorRole.warning,
    ),
    'image': FileIconConfig(
      extensions: {'.jpg', '.png', '.heic'},
      icon: HugeIcons.strokeRoundedImage01,
      colorRole: FileIconColorRole.green,
    ),
    'presentation': FileIconConfig(
      extensions: {'.pptx'},
      icon: HugeIcons.strokeRoundedPresentation01,
      colorRole: FileIconColorRole.primary,
    ),
    'spreadsheet': FileIconConfig(
      extensions: {'.xlsx'},
      icon: HugeIcons.strokeRoundedTable01,
      colorRole: FileIconColorRole.green,
    ),
  };

  static const FileIconConfig _defaultConfig = FileIconConfig(
    extensions: {},
    icon: HugeIcons.strokeRoundedFile02,
    colorRole: FileIconColorRole.neutral,
  );

  static FileIconConfig _getFileConfig(String fileName) {
    final lowerFileName = fileName.toLowerCase();
    final lastDotIndex = lowerFileName.lastIndexOf('.');

    if (lastDotIndex == -1) {
      return _defaultConfig; // No extension found
    }

    final extension = lowerFileName.substring(lastDotIndex);

    for (final config in _fileTypeConfigs.values) {
      if (config.extensions.contains(extension)) {
        return config;
      }
    }

    return _defaultConfig;
  }

  static Widget getFileIcon(
    BuildContext context,
    String fileName, {
    required Color backgroundColor,
    double size = 24,
  }) {
    final colors = context.componentColors;
    final config = _getFileConfig(fileName);
    return buildRoleIcon(
      icon: config.icon,
      foregroundColor: _foregroundColor(config.colorRole, colors),
      backgroundColor: backgroundColor,
      size: size,
    );
  }

  static Color _foregroundColor(FileIconColorRole role, ColorTokens colors) {
    return switch (role) {
      FileIconColorRole.warning => colors.warning,
      FileIconColorRole.green => colors.green,
      FileIconColorRole.primary => colors.primary,
      FileIconColorRole.neutral => colors.textLight,
    };
  }
}

Widget buildRoleIcon({
  required dynamic icon,
  required Color foregroundColor,
  required Color backgroundColor,
  double size = 24,
}) {
  return IconTile(
    icon: HugeIcon(icon: icon, color: foregroundColor, size: size),
    backgroundColor: backgroundColor,
  );
}

class IconTile extends StatelessWidget {
  final Widget icon;
  final Color backgroundColor;

  const IconTile({
    super.key,
    required this.icon,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(padding: const EdgeInsets.all(8.0), child: icon),
    );
  }
}

class SelectionCheckBadge extends StatelessWidget {
  const SelectionCheckBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedTick02,
        color: colors.specialWhite,
        size: 12,
        strokeWidth: 2,
      ),
    );
  }
}
