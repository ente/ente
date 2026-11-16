import "dart:async";
import "dart:io";
import "dart:math";
import "dart:ui" show ImageFilter;

import "package:ente_components/hugeicons.dart";
import "package:ente_components/theme/text_styles.dart" as component;
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";
import "package:photos/ui/home/memories/memory_viewer_constants.dart";

abstract final class SpecialMemoryColors {
  static const ink = Color(0xFF151515);
  static const yellow = Color(0xFFFFC62B);
  static const photoPaper = Color(0xFFFFFDF8);
}

TextStyle specialDisplayStyle(double size, {Color color = Colors.white}) {
  return TextStyle(
    fontFamily: component.TextStyles.outfitFontFamily,
    package: component.TextStyles.fontPackage,
    fontSize: size,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: color,
  );
}

class SpecialMemoryScaffold extends StatelessWidget {
  final Widget child;

  const SpecialMemoryScaffold({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(backgroundColor: Colors.black, body: child),
    );
  }
}

class MemoryPhoto extends StatefulWidget {
  final EnteFile file;
  final bool loadsOriginal;
  final ValueChanged<Size>? onReady;
  final VoidCallback? onFailed;

  const MemoryPhoto(
    this.file, {
    this.loadsOriginal = false,
    this.onReady,
    this.onFailed,
    super.key,
  });

  @override
  State<MemoryPhoto> createState() => _MemoryPhotoState();
}

class _MemoryPhotoState extends State<MemoryPhoto> {
  static const _maximumOriginalSide = 2400;

  ImageProvider? _image;
  bool _showsOriginal = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final loadsOriginal =
        widget.loadsOriginal && widget.file.fileType != FileType.video;
    await Future.wait([_loadThumbnail(), if (loadsOriginal) _loadOriginal()]);
    if (mounted && _image == null) widget.onFailed?.call();
  }

  Future<void> _loadThumbnail() async {
    final Uint8List? bytes;
    try {
      bytes = await getThumbnail(widget.file);
    } catch (_) {
      return;
    }
    if (bytes == null) return;
    await _show(MemoryImage(bytes), isOriginal: false);
  }

  Future<void> _loadOriginal() async {
    final File? original;
    try {
      original = await getFile(widget.file);
    } catch (_) {
      return;
    }
    if (original == null) return;
    await _show(
      ResizeImage(
        FileImage(original),
        width: _maximumOriginalSide,
        height: _maximumOriginalSide,
        policy: ResizeImagePolicy.fit,
      ),
      isOriginal: true,
    );
  }

  Future<void> _show(ImageProvider image, {required bool isOriginal}) async {
    final size = await _decodedSize(image);
    if (size == null || !mounted || (_showsOriginal && !isOriginal)) return;
    final isFirst = _image == null;
    setState(() {
      _image = image;
      _showsOriginal = isOriginal;
    });
    if (isFirst) widget.onReady?.call(size);
  }

  Future<Size?> _decodedSize(ImageProvider image) {
    final decoded = Completer<Size?>();
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        decoded.complete(
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
        info.dispose();
      },
      onError: (_, _) {
        stream.removeListener(listener);
        decoded.complete(null);
      },
    );
    stream.addListener(listener);
    return decoded.future;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const ColoredBox(color: Color(0xFF1B1B1B));
    return Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

class SpecialMemoryBackdrop extends StatelessWidget {
  final EnteFile file;

  const SpecialMemoryBackdrop(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: ImageFiltered(
            key: ValueKey(file.tag),
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: MemoryPhoto(file),
          ),
        ),
        const ColoredBox(color: Color(0x73000000)),
      ],
    );
  }
}

class LeftPartClipper extends CustomClipper<Rect> {
  final double part;

  const LeftPartClipper(this.part);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * part, size.height);
  }

  @override
  bool shouldReclip(LeftPartClipper oldClipper) => oldClipper.part != part;
}

class SpecialMemoryGestures extends StatelessWidget {
  final ValueChanged<bool> onHold;
  final VoidCallback? onPreviousMemory;
  final VoidCallback? onNextMemory;
  final Widget child;

  const SpecialMemoryGestures({
    required this.onHold,
    required this.onPreviousMemory,
    required this.onNextMemory,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Listener(
      onPointerDown: (_) => onHold(true),
      onPointerUp: (_) => onHold(false),
      onPointerCancel: (_) => onHold(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {},
        onTapUp: (details) {
          final onMemory = details.localPosition.dx < screenWidth * 0.2
              ? onPreviousMemory
              : onNextMemory;
          onMemory?.call();
        },
        child: child,
      ),
    );
  }
}

class SpecialMemoryLoadFailure extends StatelessWidget {
  final VoidCallback onRetry;

  const SpecialMemoryLoadFailure({required this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.strings.couldNotLoadPhotos,
            textAlign: TextAlign.center,
            style: component.TextStyles.body.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(context.strings.retry),
          ),
        ],
      ),
    );
  }
}

String specialMemoryTitleHeroTag(String memoryID) {
  return "special-memory-title-$memoryID";
}

class SpecialMemoryHeader extends StatelessWidget {
  final String memoryID;
  final String title;
  final String? subtitle;
  final Widget progress;

  const SpecialMemoryHeader({
    required this.memoryID,
    required this.title,
    required this.progress,
    this.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    final subtitle = this.subtitle;
    return Stack(
      children: [
        IgnorePointer(
          child: SizedBox(
            width: double.infinity,
            height: safePadding.top + 124,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xB8000000),
                    Color(0x70000000),
                    Colors.transparent,
                  ],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: max(safePadding.top, 40)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  safePadding.left + 16,
                  0,
                  safePadding.right + 16,
                  0,
                ),
                child: progress,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  safePadding.left + 16,
                  0,
                  safePadding.right + 16,
                  0,
                ),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          tooltip: context.strings.close,
                          padding: const EdgeInsets.all(8),
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(48),
                            maximumSize: const Size.square(48),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            overlayColor: Colors.white.withValues(alpha: 0.08),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Hero(
                              tag: specialMemoryTitleHeroTag(memoryID),
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: component.TextStyles.display3.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: component.TextStyles.mini.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SpecialMemoryStoryScrim extends StatelessWidget {
  const SpecialMemoryStoryScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.paddingOf(context).bottom + 420,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xB3000000),
                Color(0x99000000),
                Color(0x4D000000),
                Colors.transparent,
              ],
              stops: [0, 0.45, 0.75, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class SpecialMemoryMuteButton extends StatelessWidget {
  const SpecialMemoryMuteButton({super.key});

  @override
  Widget build(BuildContext context) {
    final memoryAudio = MemoryAudioScope.maybeOf(context);
    if (memoryAudio == null) return const SizedBox.shrink();
    final safePadding = MediaQuery.paddingOf(context);
    return Positioned(
      left: safePadding.left + kMemoryOverlayHorizontalInset,
      bottom: safePadding.bottom + 24,
      child: MemoryAudioMuteButton(memoryAudio),
    );
  }
}

void tickHaptic() {
  unawaited(HapticFeedback.selectionClick());
}
