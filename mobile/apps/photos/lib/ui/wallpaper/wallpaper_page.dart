import 'dart:ui' as ui;

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/locale.dart';
import 'package:photos/ui/wallpaper/wallpaper_crop.dart';

Future<void> runWallpaperApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  ComponentTheme.configure(app: ComponentApp.photos);
  final theme = await AdaptiveTheme.getThemeMode();
  final locale = await getLocale(noFallback: true);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lightThemeData,
      darkTheme: darkThemeData,
      themeMode: switch (theme) {
        AdaptiveThemeMode.light => ThemeMode.light,
        AdaptiveThemeMode.dark => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: locale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      localeListResolutionCallback: localResolutionCallBack,
      home: const WallpaperPage(),
    ),
  );
}

class WallpaperPage extends StatefulWidget {
  const WallpaperPage({super.key});

  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  final _client = WallpaperClient();
  final _crop = WallpaperCrop();
  ui.Image? _image;
  Size? _wallpaperSize;
  String? _error;
  bool _applying = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.close,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
            onPressed: _applying ? null : SystemNavigator.pop,
          ),
          title: Text(l10n.wallpaper, style: TextStyles.h2),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _image == null
                    ? Center(
                        child: _error == null
                            ? const CircularProgressIndicator()
                            : Text(
                                _error == 'unavailable'
                                    ? l10n.wallpaperUnavailable
                                    : l10n.wallpaperFailed,
                                textAlign: TextAlign.center,
                              ),
                      )
                    : Center(
                        child: AspectRatio(
                          aspectRatio: _wallpaperSize!.aspectRatio,
                          child: WallpaperCropView(
                            image: _image!,
                            crop: _crop,
                            enabled: !_applying,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: ButtonComponent(
                  label: _done ? l10n.wallpaperSet : l10n.setWallpaper,
                  isDisabled: _image == null || _applying,
                  shouldSurfaceExecutionStates: false,
                  leading: _applying
                      ? _done
                            ? const Icon(Icons.check)
                            : const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                      : null,
                  onTap: _chooseDestination,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final preview = await _client.prepare();
      final image = await decodeImageFromList(preview.bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image = image;
        _wallpaperSize = preview.size;
      });
    } catch (error) {
      Logger('Wallpaper').warning('Could not load wallpaper', error);
      if (mounted) {
        setState(() {
          _error = error is PlatformException ? error.code : 'wallpaper_failed';
        });
      }
    }
  }

  Future<void> _chooseDestination() async {
    final l10n = context.strings;
    final destination = await showBottomSheetComponent<WallpaperDestination>(
      context: context,
      builder: (context) => BottomSheetComponent(
        title: l10n.setWallpaper,
        closeTooltip: l10n.close,
        actions: [
          for (final destination in WallpaperDestination.values)
            ButtonComponent(
              label: switch (destination) {
                WallpaperDestination.home => l10n.wallpaperHome,
                WallpaperDestination.lock => l10n.wallpaperLock,
                WallpaperDestination.both => l10n.wallpaperBoth,
              },
              variant: ButtonComponentVariant.neutral,
              shouldSurfaceExecutionStates: false,
              onTap: () => Navigator.of(context).pop(destination),
            ),
        ],
      ),
    );
    if (destination == null || !mounted) return;
    setState(() => _applying = true);
    try {
      await _client.apply(_crop.region, destination);
      if (!mounted) return;
      setState(() => _done = true);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) await SystemNavigator.pop();
    } catch (error) {
      Logger('Wallpaper').warning('Could not set wallpaper', error);
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.wallpaperFailed)));
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }
}
