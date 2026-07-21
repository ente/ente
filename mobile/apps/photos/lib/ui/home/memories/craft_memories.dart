import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/ui/home/memories/memory_cover_widget.dart";
import "package:rive/rive.dart" as rive;

class CraftMemories extends StatefulWidget {
  final double width;
  final double height;
  final VoidCallback? onNotificationsPermissionGranted;

  const CraftMemories({
    super.key,
    required this.width,
    required this.height,
    this.onNotificationsPermissionGranted,
  });

  @override
  State<CraftMemories> createState() => _CraftMemoriesState();
}

class _CraftMemoriesState extends State<CraftMemories> {
  late final rive.FileLoader _riveFileLoader;
  bool _isButtonPressed = false;

  @override
  void initState() {
    super.initState();
    _riveFileLoader = rive.FileLoader.fromAsset(
      "assets/memories.riv",
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void dispose() {
    _riveFileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(MemoryCoverWidget.gap / 2.0),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: rive.RiveWidgetBuilder(
                  fileLoader: _riveFileLoader,
                  builder: (BuildContext context, rive.RiveState state) {
                    if (state is rive.RiveLoaded) {
                      return rive.RiveWidget(
                        controller: state.controller,
                        fit: rive.Fit.cover,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.craftingMemoriesFirstHalf,
                      style: TextStyle(
                        fontFamily: TextStyles.outfitFontFamily,
                        package: TextStyles.fontPackage,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: widget.width * 0.115,
                        height: 1,
                      ),
                    ),
                    Text(
                      l10n.craftingMemoriesSecondHalf,
                      style: TextStyle(
                        fontFamily: "Gochi Hand",
                        package: TextStyles.fontPackage,
                        color: Colors.white,
                        fontSize: widget.width * 0.175,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton() {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () async {
        if (await NotificationService.instance.requestPermissions(context) &&
            mounted) {
          widget.onNotificationsPermissionGranted?.call();
        }
      },
      onTapDown: (_) => setState(() => _isButtonPressed = true),
      onTapUp: (_) => setState(() => _isButtonPressed = false),
      onTapCancel: () => setState(() => _isButtonPressed = false),
      child: AnimatedScale(
        scale: _isButtonPressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(128),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              l10n.notifyMe,
              style: const TextStyle(
                fontFamily: TextStyles.outfitFontFamily,
                package: TextStyles.fontPackage,
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
