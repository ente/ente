import 'package:ente_components/ente_components.dart';
import 'package:ente_icons/ente_icons.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/file/file.dart";
import 'package:photos/models/file/trash_file.dart';
import 'package:photos/ui/sharing/user_avator_widget.dart';

class ThumbnailPlaceHolder extends StatelessWidget {
  const ThumbnailPlaceHolder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: context.componentColors.fillDark,
    );
  }
}

class UnSyncedIcon extends StatelessWidget {
  const UnSyncedIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const _BottomLeftOverlayIcon(Icons.cloud_off_outlined, baseSize: 18);
  }
}

class FavoriteOverlayIcon extends StatelessWidget {
  const FavoriteOverlayIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const _BottomLeftOverlayIcon(EnteIcons.favoriteFilled, baseSize: 22);
  }
}

class LivePhotoOverlayIcon extends StatelessWidget {
  const LivePhotoOverlayIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const _BottomRightOverlayIcon(Icons.album_outlined, baseSize: 18);
  }
}

class VideoOverlayIcon extends StatelessWidget {
  const VideoOverlayIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.play_circle_outline,
      size: 24,
      color: Colors.white70,
    );
  }
}

class VideoOverlayDuration extends StatelessWidget {
  final int? duration;
  const VideoOverlayDuration({super.key, required this.duration});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        late Widget onDarkBackground;
        final bool iconFallback = (duration == null || duration == 0);

        double inset = 4;
        double iconSize = 18;
        if (constraints.hasBoundedWidth) {
          final w = constraints.maxWidth;
          if (w > 120) {
            iconSize = 24;
          } else if (w < 75) {
            inset = 3;
            iconSize = 16;
          }
        }

        if (iconFallback) {
          onDarkBackground = Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: iconSize,
          );
        } else {
          final String formattedDuration = _getFormattedDuration(duration!);
          onDarkBackground = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              formattedDuration,
              style: TextStyles.tiny.copyWith(color: Colors.white),
            ),
          );
        }

        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.only(bottom: inset, right: inset),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: iconFallback ? null : BorderRadius.circular(8.0),
                shape: iconFallback ? BoxShape.circle : BoxShape.rectangle,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: onDarkBackground,
            ),
          ),
        );
      },
    );
  }

  String _getFormattedDuration(int duration) {
    final String formattedDuration = Duration(
      seconds: duration,
    ).toString().split('.').first;
    final List<String> separated = formattedDuration.split(':');
    final String hour = (separated[0] == '0') ? '' : separated[0] + ':';
    final String minute = int.parse(separated[1]).toString() + ':';
    final String second = separated[2];
    return hour + minute + second;
  }
}

class OwnerAvatarOverlayIcon extends StatelessWidget {
  final User user;
  final AvatarType type;
  const OwnerAvatarOverlayIcon(
    this.user, {
    super.key,
    this.type = AvatarType.small,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 4, top: 4),
        child: UserAvatarWidget(user, type: type, thumbnailView: true),
      ),
    );
  }
}

class TrashedFileOverlayText extends StatelessWidget {
  final TrashFile file;
  const TrashedFileOverlayText(this.file, {super.key});
  @override
  Widget build(BuildContext context) {
    final int daysLeft =
        ((file.deleteBy - DateTime.now().microsecondsSinceEpoch) /
                Duration.microsecondsPerDay)
            .ceil();
    final text = AppLocalizations.of(context).trashDaysLeft(count: daysLeft);
    return FileOverlayText(text);
  }
}

class FileSizeOverlayText extends StatelessWidget {
  final EnteFile file;
  const FileSizeOverlayText(this.file, {super.key});
  @override
  Widget build(BuildContext context) {
    if (file.fileSize == null) {
      return const SizedBox.shrink();
    }
    final text = convertBytesToReadableFormat(file.fileSize!);
    return FileOverlayText(text);
  }
}

class FileOverlayText extends StatelessWidget {
  final String text;

  const FileOverlayText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.33), Colors.transparent],
        ),
      ),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall!.copyWith(
          color: Colors.white,
        ), //same for both themes
      ),
    );
  }
}

// Base variations

/// Icon overlay in the bottom left.
///
/// This usually indicates ente specific state of a file, e.g. if it is
/// favorited/archived.
class _BottomLeftOverlayIcon extends StatelessWidget {
  final IconData icon;

  /// Overriddable default size. This is just the initial hint, the actual size
  /// is dynamic based on the widget's width (so that we show smaller icons in
  /// smaller thumbnails).
  final double baseSize;

  const _BottomLeftOverlayIcon(this.icon, {this.baseSize = 24});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double inset = 4;
        double size = baseSize;

        if (constraints.hasBoundedWidth) {
          final w = constraints.maxWidth;
          if (w > 125) {
            size = 24;
          } else if (w < 75) {
            inset = 3;
            size = 16;
          }
        }

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.center,
              colors: [
                Color.fromRGBO(0, 0, 0, 0.14),
                Color.fromRGBO(0, 0, 0, 0.05),
                Color.fromRGBO(0, 0, 0, 0.0),
              ],
              stops: [0, 0.6, 1],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.only(left: inset, bottom: inset),
              child: Icon(icon, size: size, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

/// Icon overlay in the bottom right.
///
/// This usually indicates information about the file itself, e.g. whether it is
/// a live photo, or the duration of the video.
class _BottomRightOverlayIcon extends StatelessWidget {
  final IconData icon;

  /// Overriddable default size. This is just the initial hint, the actual size
  /// is dynamic based on the widget's width (so that we show smaller icons in
  /// smaller thumbnails).
  final double baseSize;

  const _BottomRightOverlayIcon(this.icon, {this.baseSize = 24});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double inset = 4;
        double size = baseSize;

        if (constraints.hasBoundedWidth) {
          final w = constraints.maxWidth;
          if (w > 120) {
            size = 24;
          } else if (w < 75) {
            inset = 3;
            size = 16;
          }
        }

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomRight,
              end: Alignment.center,
              colors: [
                Color.fromRGBO(0, 0, 0, 0.14),
                Color.fromRGBO(0, 0, 0, 0.05),
                Color.fromRGBO(0, 0, 0, 0.0),
              ],
              stops: [0, 0.6, 1],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.only(bottom: inset, right: inset),
              child: Icon(icon, size: size, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}
