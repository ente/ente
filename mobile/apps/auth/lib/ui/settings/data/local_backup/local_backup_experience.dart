import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/services/local_backup_service.dart';
import 'package:ente_auth/services/security_bookmark_service.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/button_widget.dart';
import 'package:ente_ui/components/buttons/models/button_type.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scoped_dir_access/scoped_dir_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef LocalBackupVariantBuilder =
    Widget Function(
      BuildContext context,
      LocalBackupExperienceController controller,
    );

class LocalBackupExperience extends StatefulWidget {
  const LocalBackupExperience({super.key, required this.builder});

  final LocalBackupVariantBuilder builder;

  @override
  State<LocalBackupExperience> createState() => _LocalBackupExperienceState();
}

class LocalBackupExperienceController {
  const LocalBackupExperienceController._(this._state);

  final _LocalBackupExperienceState _state;

  bool get hasLoaded => _state._hasLoaded;
  bool get isBusy => _state._isBusy;
  bool get isManualBackupRunning => _state._isManualBackupRunning;
  bool get shouldShowBusyOverlay => _state._shouldShowBusyOverlay;
  bool get isBackupEnabled => _state._isBackupEnabled;
  String? get backupPath => _state._backupPath;
  String? get backupTreeUri => _state._backupTreeUri;

  Future<void> toggleBackup(bool shouldEnable) =>
      _state._handleToggle(shouldEnable);

  Future<bool> changeLocation({String? successMessage}) =>
      _state._pickAndSaveBackupLocation(successMessage: successMessage);

  Future<bool> openLocationSetup() => _state._handleLocationSetup();

  Future<bool> resetBackupLocation() => _state._resetBackupLocation();

  Future<void> runManualBackup({bool showSnackBar = true}) =>
      _state._runManualBackup(showSnackBar: showSnackBar);

  Future<bool> updatePassword(BuildContext context) =>
      _state._updatePassword(context);

  Future<bool> hasPasswordConfigured() => _state._hasStoredPassword();

  Future<bool> clearBackupPassword() => _state._clearBackupPassword();

  String simplifyPath(String fullPath) => _state._simplifyPath(fullPath);

  void showSnackBar(String message) => _state._showSnackBar(message);

  Future<void> refreshState() => _state._loadSettings();
}

class _LocalBackupExperienceState extends State<LocalBackupExperience> {
  static const _locationConfiguredKey = 'hasConfiguredBackupLocation';
  static const _treeUriKey = 'autoBackupTreeUri';
  static const _iosBookmarkKey = 'autoBackupIosBookmark';
  final _logger = Logger('LocalBackupExperience');

  bool _isBackupEnabled = false;
  String? _backupPath;
  String? _backupTreeUri;
  bool _isBusy = false;
  bool _isManualBackupRunning = false;
  bool _shouldShowBusyOverlay = true;
  bool _hasLoaded = false;

  late final LocalBackupExperienceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LocalBackupExperienceController._(this);
    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPath = prefs.getString('autoBackupPath');
    final storedTreeUri = prefs.getString(_treeUriKey);
    if (!mounted) return;
    setState(() {
      _isBackupEnabled = prefs.getBool('isAutoBackupEnabled') ?? false;
      _backupPath = storedPath;
      _backupTreeUri = storedTreeUri;
      _hasLoaded = true;
    });
  }

  Future<void> _handleToggle(bool shouldEnable) async {
    await _withBusyGuard(() async {
      if (shouldEnable) {
        final success = await _startEnableFlow();
        if (!success) {
          return;
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isAutoBackupEnabled', false);
        if (!mounted) return;
        setState(() {
          _isBackupEnabled = false;
        });
      }
    }, showOverlay: false);
  }

  Future<bool> _startEnableFlow() async {
    final hasPassword = await _ensurePasswordConfigured(disableOnCancel: true);
    // Re-enabling skips password re-entry when one is already stored.
    if (!hasPassword) {
      return false;
    }

    final hasLocation = await _ensureBackupLocationSelected();
    if (!hasLocation) {
      return false;
    }
    if (Platform.isAndroid &&
        (_backupTreeUri == null || _backupTreeUri!.isEmpty) &&
        (_backupPath == null || _backupPath!.isEmpty)) {
      if (!mounted) return false;
      _showSnackBar(context.strings.noDefaultBackupFolder);
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAutoBackupEnabled', true);
    if (!mounted) return false;
    setState(() {
      _isBackupEnabled = true;
    });
    await LocalBackupService.instance.triggerAutomaticBackup(isManual: false);
    return true;
  }

  Future<void> _runManualBackup({bool showSnackBar = true}) async {
    if (_isManualBackupRunning) return;

    setState(() {
      _isManualBackupRunning = true;
    });

    try {
      final hasPassword = await _ensurePasswordConfigured(
        disableOnCancel: false,
      );
      if (!hasPassword) {
        _logger.info('Manual backup cancelled: no password configured');
        return;
      }

      final hasLocation = await _ensureBackupLocationSelected();
      if (!hasLocation) {
        _logger.info('Manual backup cancelled: no location selected');
        return;
      }

      // A saved path is unusable on iOS/macOS without its security bookmark.
      if (Platform.isIOS || Platform.isMacOS) {
        final prefs = await SharedPreferences.getInstance();
        final bookmark = prefs.getString(_iosBookmarkKey);
        if (bookmark == null || bookmark.isEmpty) {
          _logger.warning(
            '${Platform.operatingSystem}: No bookmark found, need to re-select backup location',
          );
          if (showSnackBar) {
            if (!mounted) return;
            _showSnackBar(context.strings.selectFolderToContinue);
          }
          await prefs.remove('autoBackupPath');
          if (mounted) {
            setState(() {
              _backupPath = null;
            });
          }
          final saved = await _pickAndSaveBackupLocation(
            requireSelection: true,
            shouldTriggerBackup: false,
          );
          if (!saved) {
            _logger.info('Manual backup cancelled: user did not select folder');
            return;
          }
        }
      }

      try {
        final success = await LocalBackupService.instance
            .triggerAutomaticBackup(isManual: true);
        if (showSnackBar) {
          if (!mounted) return;
          _showSnackBar(
            success
                ? context.strings.backupCreated
                : context.strings.somethingWentWrongPleaseTryAgain,
          );
        }
      } catch (e) {
        _logger.severe('Manual backup failed with error: $e');
        if (showSnackBar) {
          if (!mounted) return;
          _showSnackBar(context.strings.somethingWentWrongPleaseTryAgain);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isManualBackupRunning = false;
        });
      }
    }
  }

  Future<bool> _ensurePasswordConfigured({
    required bool disableOnCancel,
  }) async {
    if (await _hasStoredPassword()) {
      return true;
    }
    return _promptPassword(
      forcePrompt: true,
      disableOnCancel: disableOnCancel,
      isUpdateFlow: false,
    );
  }

  Future<bool> _ensureBackupLocationSelected() async {
    if (Platform.isAndroid) {
      if ((_backupTreeUri == null || _backupTreeUri!.isEmpty) &&
          (_backupPath == null || _backupPath!.isEmpty)) {
        return _pickAndSaveBackupLocation(
          requireSelection: true,
          shouldTriggerBackup: false,
        );
      }
      return true;
    }

    var resolvedPath = _backupPath;
    if (resolvedPath == null || resolvedPath.isEmpty) {
      final saved = await _pickAndSaveBackupLocation(
        requireSelection: true,
        shouldTriggerBackup: false,
      );
      if (!saved) {
        return false;
      }
      resolvedPath = _backupPath;
    }
    // The backup service creates iOS/macOS directories with scoped access.
    if (!Platform.isIOS &&
        !Platform.isMacOS &&
        resolvedPath != null &&
        resolvedPath.isNotEmpty) {
      await Directory(resolvedPath).create(recursive: true);
    }
    return true;
  }

  Future<bool> _authenticateForBackupAction(
    String reason, {
    bool forceAuthPrompt = false,
  }) async {
    if (forceAuthPrompt) {
      // Reset cached auth window to force a fresh prompt for sensitive flows.
      LocalAuthenticationService.instance.lastAuthTime = 0;
    }
    return LocalAuthenticationService.instance.requestLocalAuthentication(
      context,
      reason,
    );
  }

  Future<void> _withBusyGuard(
    Future<void> Function() action, {
    bool showOverlay = true,
  }) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _shouldShowBusyOverlay = showOverlay;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _shouldShowBusyOverlay = true;
        });
      }
    }
  }

  Future<bool> _updatePassword(BuildContext context) async => _promptPassword(
    forcePrompt: true,
    disableOnCancel: false,
    isUpdateFlow: true,
  );

  Future<bool> _promptPassword({
    required bool forcePrompt,
    bool disableOnCancel = false,
    bool isUpdateFlow = false,
  }) async {
    final hasAuthenticated = await _authenticateForBackupAction(
      isUpdateFlow
          ? context.strings.authToUpdateBackupPassword
          : context.strings.authToSetBackupPassword,
      forceAuthPrompt: true,
    );
    if (!hasAuthenticated) {
      if (disableOnCancel && mounted) {
        setState(() {
          _isBackupEnabled = false;
        });
      }
      return false;
    }

    if (!forcePrompt) {
      final stored = await _readStoredPassword();
      if (stored != null && stored.isNotEmpty) {
        return true;
      }
    }

    final String? password = await _showCustomPasswordDialog(
      isUpdateFlow: isUpdateFlow,
    );
    if (password == null) {
      if (disableOnCancel && mounted) {
        setState(() {
          _isBackupEnabled = false;
        });
      }
      return false;
    }

    await Configuration.instance.setBackupPassword(password);
    return true;
  }

  Future<bool> _hasStoredPassword() async {
    final stored = await _readStoredPassword();
    return stored != null && stored.isNotEmpty;
  }

  Future<bool> _clearBackupPassword() async {
    if (_isBackupEnabled) {
      return false;
    }
    await Configuration.instance.clearBackupPassword();
    if (!mounted) return false;
    _showSnackBar(context.strings.backupPasswordCleared);
    return true;
  }

  Future<String?> _readStoredPassword() async {
    try {
      return await Configuration.instance.getBackupPassword();
    } catch (e) {
      _logger.severe('Failed to read backup password: $e');
      return null;
    }
  }

  Future<bool> _resetBackupLocation() async {
    if (_isBackupEnabled) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('autoBackupPath');
    await prefs.remove(_treeUriKey);
    await prefs.remove(_iosBookmarkKey);
    await prefs.remove(_locationConfiguredKey);
    if (!mounted) return false;
    setState(() {
      _backupPath = null;
      _backupTreeUri = null;
    });
    return true;
  }

  Future<String?> _showCustomPasswordDialog({
    required bool isUpdateFlow,
  }) async {
    final l10n = context.strings;
    final textController = TextEditingController();
    bool isPasswordHidden = true;
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                isUpdateFlow
                    ? l10n.updateBackupPassword
                    : l10n.setBackupPassword,
                style: getEnteTextTheme(context).largeBold,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.backupPasswordHint,
                    style: getEnteTextTheme(context).smallFaint,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    obscureText: isPasswordHidden,
                    decoration: InputDecoration(
                      hintText: l10n.enterPassword,
                      hintStyle: getEnteTextTheme(context).mini,
                      suffixIcon: IconButton(
                        icon: Icon(
                          isPasswordHidden
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            isPasswordHidden = !isPasswordHidden;
                          });
                        },
                      ),
                      errorText: errorText,
                    ),
                    onChanged: (text) {
                      setState(() {
                        if (text.length >= 8 && errorText != null) {
                          errorText = null;
                        }
                      });
                    },
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: errorText == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(errorText),
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              errorText!,
                              style: getEnteTextTheme(
                                context,
                              ).mini.copyWith(color: Colors.redAccent),
                            ),
                          ),
                  ),
                ],
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: ButtonWidget(
                        buttonType: ButtonType.secondary,
                        labelText: l10n.cancel,
                        onTap: () async => Navigator.of(context).pop(null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ButtonWidget(
                        buttonType: ButtonType.primary,
                        labelText: l10n.save,
                        isDisabled: textController.text.isEmpty,
                        onTap: () async {
                          if (textController.text.length < 8) {
                            setState(() {
                              errorText = l10n.passwordTooShort;
                            });
                            return;
                          }
                          Navigator.of(context).pop(textController.text.trim());
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _handleLocationSetup() async {
    if (Platform.isAndroid) {
      return _pickAndPersistAndroidLocation();
    }

    if (Platform.isIOS) {
      final l10n = context.strings;
      final dialogBody = StringBuffer()
        ..writeln(l10n.backupLocationChoiceDescription)
        ..writeln()
        ..writeln(l10n.enableBackupsIosInstruction)
        ..writeln()
        ..writeAll(
          _backupPath != null && _backupPath!.isNotEmpty
              ? [l10n.currentBackupFolder, _simplifyPath(_backupPath!)]
              : const [],
          '\n',
        );

      final result = await showDialogWidget(
        title: l10n.chooseBackupLocation,
        context: context,
        body: dialogBody.toString(),
        buttons: [
          ButtonWidget(
            buttonType: ButtonType.primary,
            labelText: l10n.selectFolder,
            isInAlert: true,
            buttonSize: ButtonSize.large,
            buttonAction: ButtonAction.second,
          ),
          ButtonWidget(
            buttonType: ButtonType.secondary,
            labelText: l10n.cancel,
            isInAlert: true,
            buttonSize: ButtonSize.large,
            buttonAction: ButtonAction.first,
          ),
        ],
      );

      if (result?.action == ButtonAction.second) {
        final pickResult = await SecurityBookmarkService.instance
            .pickDirectoryAndCreateBookmark();
        if (!mounted) return false;
        if (pickResult != null) {
          if (_isInvalidIosPath(pickResult.path)) {
            _showSnackBar(context.strings.iosOnMyDeviceNotSupported);
            return false;
          }
          return _persistLocationWithBookmark(
            pickResult.path,
            pickResult.bookmark,
            successMessage: context.strings.initialBackupCreated,
          );
        }
      }
      return false;
    }

    if (Platform.isMacOS) {
      final picked = await DirUtils.instance.pickDirectory();
      if (picked != null && picked.path.isNotEmpty && picked.bookmark != null) {
        if (!mounted) return false;
        return _persistLocationWithBookmark(
          picked.path,
          picked.bookmark!,
          successMessage: context.strings.initialBackupCreated,
        );
      }
      return false;
    }

    final picked = await DirUtils.instance.pickDirectory();
    if (picked != null && picked.path.isNotEmpty) {
      if (!mounted) return false;
      return _persistLocation(
        picked.path,
        successMessage: context.strings.initialBackupCreated,
      );
    }
    return false;
  }

  String _simplifyPath(String fullPath) {
    if (fullPath.isEmpty) {
      return fullPath;
    }

    if (Platform.isAndroid) {
      if (fullPath.startsWith('content://')) {
        final decoded = Uri.decodeComponent(fullPath.split('/').last);
        return decoded.replaceFirst('primary:', '');
      }

      const rootsToRemove = <String>[
        '/storage/emulated/0/',
        '/storage/self/primary/',
      ];

      for (final root in rootsToRemove) {
        if (fullPath.startsWith(root)) {
          return fullPath.substring(root.length);
        }
      }
      return fullPath.split('/').last;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      var simplified = fullPath;
      const fileScheme = 'file://';
      if (simplified.startsWith(fileScheme)) {
        simplified = simplified.substring(fileScheme.length);
      }
      final homePath = Platform.environment['HOME'];
      if (homePath != null && simplified.startsWith(homePath)) {
        simplified = simplified.replaceFirst(homePath, '~');
      }
      // iOS often prepends /private when surfacing sandboxed locations.
      const privatePrefix = '/private';
      if (simplified.startsWith(privatePrefix)) {
        simplified = simplified.substring(privatePrefix.length);
      }

      const icloudMarker = '/Mobile Documents/';
      if (simplified.contains(icloudMarker)) {
        final afterMarker = simplified.split(icloudMarker).last;
        const cloudDocsPrefix = 'com~apple~CloudDocs/';
        if (afterMarker.startsWith(cloudDocsPrefix)) {
          final remaining = afterMarker.substring(cloudDocsPrefix.length);
          return remaining.isNotEmpty
              ? 'iCloud Drive/$remaining'
              : 'iCloud Drive';
        }
        if (afterMarker.isNotEmpty) {
          return afterMarker;
        }
      }

      const markers = <String>[
        '/File Provider Storage/',
        '/Documents/',
        '/tmp/',
      ];

      for (final marker in markers) {
        final index = simplified.indexOf(marker);
        if (index != -1) {
          final afterMarker = simplified.substring(index + marker.length);
          if (afterMarker.isNotEmpty) {
            return afterMarker;
          }
          final fallbackSegments = marker
              .split('/')
              .where((segment) => segment.isNotEmpty)
              .toList();
          if (fallbackSegments.isNotEmpty) {
            return fallbackSegments.last;
          }
          return simplified;
        }
      }

      final segments = simplified
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.length >= 2) {
        return segments.sublist(segments.length - 2).join('/');
      }
      if (segments.isNotEmpty) {
        return segments.last;
      }
      return simplified;
    }

    return fullPath;
  }

  Future<bool> _pickAndSaveBackupLocation({
    String? successMessage,
    bool requireSelection = false,
    bool shouldTriggerBackup = true,
  }) async {
    if (Platform.isAndroid) {
      final saved = await _pickAndPersistAndroidLocation(
        successMessage: successMessage,
        shouldTriggerBackup: shouldTriggerBackup,
      );
      if (saved) {
      } else if (requireSelection) {
        if (!mounted) return false;
        _showSnackBar(context.strings.selectFolderToContinue);
      }
      return saved;
    } else if (Platform.isIOS) {
      final result = await SecurityBookmarkService.instance
          .pickDirectoryAndCreateBookmark();
      if (result != null) {
        if (_isInvalidIosPath(result.path)) {
          if (!mounted) return false;
          _showSnackBar(context.strings.iosOnMyDeviceNotSupported);
          return false;
        }
        if (!mounted) return false;
        final saved = await _persistLocationWithBookmark(
          result.path,
          result.bookmark,
          successMessage:
              successMessage ?? context.strings.locationUpdatedAndBackupCreated,
        );
        return saved;
      }
      if (requireSelection) {
        if (!mounted) return false;
        _showSnackBar(context.strings.selectFolderToContinue);
      }
      return false;
    } else if (Platform.isMacOS) {
      final picked = await DirUtils.instance.pickDirectory();
      if (picked != null && picked.path.isNotEmpty && picked.bookmark != null) {
        if (!mounted) return false;
        final saved = await _persistLocationWithBookmark(
          picked.path,
          picked.bookmark!,
          successMessage:
              successMessage ?? context.strings.locationUpdatedAndBackupCreated,
        );
        return saved;
      }
      if (requireSelection) {
        if (!mounted) return false;
        _showSnackBar(context.strings.selectFolderToContinue);
      }
      return false;
    } else {
      final picked = await DirUtils.instance.pickDirectory();

      if (picked != null && picked.path.isNotEmpty) {
        if (!mounted) return false;
        final saved = await _persistLocation(
          picked.path,
          successMessage:
              successMessage ?? context.strings.locationUpdatedAndBackupCreated,
        );
        if (saved) {
          if (shouldTriggerBackup) {
            await LocalBackupService.instance.triggerAutomaticBackup(
              isManual: true,
            );
          }
        }
        return saved;
      }
      if (requireSelection) {
        if (!mounted) return false;
        _showSnackBar(context.strings.selectFolderToContinue);
      }
      return false;
    }
  }

  Future<bool> _persistLocationWithBookmark(
    String path,
    String bookmark, {
    String? successMessage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final dirUtils = DirUtils.instance;
    final pickedDir = PickedDirectory(path: path, bookmark: bookmark);

    try {
      final accessResult = await dirUtils.startAccess(pickedDir);
      if (accessResult == null || !accessResult.success) {
        _logger.severe(
          '${Platform.operatingSystem}: Failed to start accessing bookmark for: $path',
        );
        return false;
      }

      try {
        await LocalBackupService.instance.writeBackupToDirectory(path);
      } finally {
        await dirUtils.stopAccess(pickedDir);
      }

      await prefs.setString('autoBackupPath', path);
      await prefs.setString(_iosBookmarkKey, bookmark);
      await prefs.remove(_treeUriKey);
      await prefs.setBool(_locationConfiguredKey, true);
      if (!mounted) return false;
      setState(() {
        _backupPath = path;
        _backupTreeUri = null;
      });

      if (successMessage != null) {
        _showSnackBar(successMessage);
      }
      return true;
    } catch (e, s) {
      _logger.severe(
        'Failed to persist ${Platform.operatingSystem} location with bookmark',
        e,
        s,
      );
      return false;
    }
  }

  Future<bool> _persistLocation(String path, {String? successMessage}) async {
    final prefs = await SharedPreferences.getInstance();
    Future<bool> savePath(String target) async {
      try {
        if (Platform.isIOS || Platform.isMacOS) {
          _logger.warning(
            '${Platform.operatingSystem}: _persistLocation called without bookmark. '
            'Use native picker for ${Platform.operatingSystem}.',
          );
          return false;
        } else {
          await Directory(target).create(recursive: true);
          await prefs.setString('autoBackupPath', target);
          await prefs.remove(_treeUriKey);
          await prefs.setBool(_locationConfiguredKey, true);
          if (!mounted) return false;
          setState(() {
            _backupPath = target;
            _backupTreeUri = null;
          });
        }

        if (successMessage != null) {
          _showSnackBar(successMessage);
        }
        return true;
      } catch (e, s) {
        _logger.severe('Failed to save backup path: $target', e, s);
        return false;
      }
    }

    if (await savePath(path)) {
      return true;
    }

    if (Platform.isAndroid) {
      final fallbackPath = await _androidPrivateBackupPath();
      if (fallbackPath != null && fallbackPath != path) {
        _logger.info('Primary path failed, trying fallback: $fallbackPath');
        final savedFallback = await savePath(fallbackPath);
        if (savedFallback) {
          return true;
        }
      }
    }

    _logger.warning('All backup path options failed for: $path');
    if (!mounted) return false;
    _showSnackBar(context.strings.noDefaultBackupFolder);
    return false;
  }

  Future<String?> _androidPrivateBackupPath() async {
    final androidBasePath = await _androidBackupBasePath();
    return androidBasePath != null ? '$androidBasePath/EnteAuthBackups' : null;
  }

  Future<bool> _pickAndPersistAndroidLocation({
    String? successMessage,
    bool shouldTriggerBackup = true,
  }) async {
    final picked = await DirUtils.instance.pickDirectory();
    final treeUri = picked?.treeUri;
    if (treeUri == null || treeUri.isEmpty) {
      return false;
    }
    return _persistAndroidLocation(
      treeUri,
      successMessage: successMessage,
      shouldTriggerBackup: shouldTriggerBackup,
    );
  }

  Future<bool> _persistAndroidLocation(
    String treeUri, {
    String? successMessage,
    bool shouldTriggerBackup = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(_treeUriKey, treeUri);
      await prefs.setBool(_locationConfiguredKey, true);
      if (!mounted) return false;
      setState(() {
        _backupTreeUri = treeUri;
        _backupPath = null;
      });
      if (shouldTriggerBackup) {
        final backupSuccess = await LocalBackupService.instance
            .triggerAutomaticBackup(isManual: true);
        if (!mounted) return false;
        _showSnackBar(
          backupSuccess
              ? (successMessage ??
                    context.strings.locationUpdatedAndBackupCreated)
              : context.strings.somethingWentWrongPleaseTryAgain,
        );
        return backupSuccess;
      }
      if (successMessage != null) {
        _showSnackBar(successMessage);
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      _showSnackBar(context.strings.noDefaultBackupFolder);
      return false;
    }
  }

  Future<String?> _androidBackupBasePath() async {
    Directory directory = Directory('/storage/emulated/0/Download');
    if (await directory.exists()) {
      return directory.path;
    }

    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      return externalDir.path;
    }

    return null;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // The "On My iPhone" root cannot store files; require a subfolder.
  bool _isInvalidIosPath(String path) {
    if (!Platform.isIOS) return false;
    if (path.isEmpty) return true;

    var normalized = path;
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring(7);
    }

    // Only reject the actual iOS File Provider Storage root.
    // Pattern: .../AppGroup/UUID/File Provider Storage
    // UUID format: 8-4-4-4-12 hex characters
    final iosRootPattern = RegExp(
      r'/AppGroup/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/File Provider Storage/?$',
    );

    if (iosRootPattern.hasMatch(normalized)) {
      _logger.warning('iOS: Path is File Provider Storage root: $path');
      return true;
    }

    return false;
  }
}
