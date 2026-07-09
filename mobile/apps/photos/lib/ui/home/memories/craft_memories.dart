import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
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
      "assets/ente_rewind_banner.riv",
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
                    const Text(
                      "Crafting",
                      style: TextStyle(
                        fontFamily: "Outfit",
                        package: TextStyles.fontPackage,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      "memories",
                      style: TextStyle(
                        fontFamily: "Outfit",
                        package: TextStyles.fontPackage,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
    return GestureDetector(
      onTap: _requestPermissions,
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
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              "Notify me",
              style: TextStyle(
                fontFamily: "Outfit",
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

  Future<void> _requestPermissions() async {
    await NotificationService.instance.requestPermissions();
    if (await NotificationService.instance.hasGrantedPermissions()) {
      widget.onNotificationsPermissionGranted?.call();
    }
  }
}
