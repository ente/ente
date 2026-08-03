import "dart:ui" as ui;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/ui/home/memories/memory_cover_widget.dart";

Future<ui.FragmentProgram>? _craftMemoriesProgram;
final ui.ImageFilter _craftMemoriesBlur = ui.ImageFilter.blur(
  sigmaX: 0.01,
  sigmaY: 0.01,
);

Future<ui.FragmentProgram> _loadCraftMemoriesProgram() {
  return _craftMemoriesProgram ??= ui.FragmentProgram.fromAsset(
    "shaders/craft_memories.frag",
  );
}

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
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MemoryCoverWidget.gap / 2.0,
      ),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final permissionGranted = await NotificationService.instance
                        .requestPermissions(context);
                    if (!mounted || !permissionGranted) {
                      return;
                    }
                    widget.onNotificationsPermissionGranted?.call();
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ImageFiltered(
                          imageFilter: _craftMemoriesBlur,
                          child: const _CraftMemoriesBackground(),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(widget.width * 0.125),
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
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(74),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(64),
                                    offset: const Offset(0, 4),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: widget.width * 0.125,
                                  vertical: widget.width * 0.075,
                                ),
                                child: Text(
                                  l10n.notifyMe,
                                  style: TextStyle(
                                    fontFamily: TextStyles.outfitFontFamily,
                                    package: TextStyles.fontPackage,
                                    color: Colors.white,
                                    fontSize: widget.width * 0.11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Tooltip(
                  message: l10n.close,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      await localSettings.setCraftingMemoriesBannerDismissed();
                      if (!mounted) return;
                      widget.onNotificationsPermissionGranted?.call();
                    },
                    child: SizedBox.square(
                      dimension: 20,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x4AFFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: Transform.scale(
                          scale: 0.75,
                          child: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            color: Colors.white,
                            strokeWidth: 1.0 / 0.75,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CraftMemoriesBackground extends StatefulWidget {
  const _CraftMemoriesBackground();

  @override
  State<_CraftMemoriesBackground> createState() =>
      _CraftMemoriesBackgroundState();
}

class _CraftMemoriesBackgroundState extends State<_CraftMemoriesBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final Future<ui.FragmentProgram> _program;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _program = _loadCraftMemoriesProgram();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.FragmentProgram>(
      future: _program,
      builder: (context, snapshot) {
        if (snapshot.data case final program?) {
          return CustomPaint(
            painter: _CraftMemoriesPainter(
              animation: _animation,
              shader: program.fragmentShader(),
            ),
          );
        }
        return const ColoredBox(color: Color(0xFF1A451F));
      },
    );
  }
}

class _CraftMemoriesPainter extends CustomPainter {
  _CraftMemoriesPainter({required this.animation, required this.shader})
    : super(repaint: animation);

  final Animation<double> animation;
  final ui.FragmentShader shader;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, animation.value * 10);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_CraftMemoriesPainter oldDelegate) {
    return oldDelegate.shader != shader || oldDelegate.animation != animation;
  }
}
