import 'package:flutter/material.dart';

class FileIconConfig {
  final IconData icon;
  final Color color;
  final Set<String> extensions;

  const FileIconConfig({
    required this.icon,
    required this.color,
    required this.extensions,
  });
}

class FileIconUtils {
  static const Map<String, FileIconConfig> _fileTypeConfigs = {
    'pdf': FileIconConfig(
      extensions: {'.pdf'},
      icon: Icons.picture_as_pdf,
      color: Colors.red,
    ),
    'image': FileIconConfig(
      extensions: {'.jpg', '.png', '.heic'},
      icon: Icons.image,
      color: Colors.blue,
    ),
    'presentation': FileIconConfig(
      extensions: {'.pptx'},
      icon: Icons.slideshow,
      color: Colors.orange,
    ),
    'spreadsheet': FileIconConfig(
      extensions: {'.xlsx'},
      icon: Icons.table_chart,
      color: Colors.green,
    ),
  };

  static const FileIconConfig _defaultConfig = FileIconConfig(
    extensions: {},
    icon: Icons.insert_drive_file,
    color: Colors.grey,
  );

  static FileIconConfig _getFileConfig(String fileName) {
    final lowerFileName = fileName.toLowerCase();
    final lastDotIndex = lowerFileName.lastIndexOf('.');

    if (lastDotIndex == -1) {
      return _defaultConfig;
    }

    final extension = lowerFileName.substring(lastDotIndex);

    for (final config in _fileTypeConfigs.values) {
      if (config.extensions.contains(extension)) {
        return config;
      }
    }

    return _defaultConfig;
  }

  static IconData getFileIcon(String fileName) {
    return _getFileConfig(fileName).icon;
  }

  static Color getFileIconColor(String fileName) {
    return _getFileConfig(fileName).color;
  }
}
