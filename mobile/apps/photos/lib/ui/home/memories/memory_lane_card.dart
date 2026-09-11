import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/ui/home/memories/memory_card_constants.dart";

class MemoryLaneCardWidget extends StatelessWidget {
  final String id;
  final Uint8List oldestFace;
  final Uint8List face;
  final String personName;
  final Size size;
  final VoidCallback onTap;

  const MemoryLaneCardWidget({
    required this.id,
    required this.oldestFace,
    required this.face,
    required this.personName,
    required this.size,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final name = personName.trim();
    final title = name.isEmpty
        ? context.strings.facesTimelineAppBarTitle
        : context.strings.memoryLaneCardTitle(
            name: name,
            nameEndsWithS: name.toLowerCase().endsWith("s").toString(),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kMemoryCardStripGap / 2),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -size.width * 0.013513513514,
                top: size.height * 0.004651162791,
                width: size.width * 0.270270270270,
                height: size.width * 0.270270270270,
                child: ClipOval(
                  child: Image.memory(
                    face,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: size.width,
                child: ClipPath(
                  clipper: const _MemoryLaneBackgroundClipper(),
                  child: Container(
                    foregroundDecoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB8000000)],
                        stops: [0.53663, 0.89955],
                      ),
                    ),
                    child: Image.memory(
                      oldestFace,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: size.width * 0.081081081081,
                bottom: 16,
                width: size.width * 0.837837837838,
                child: Hero(
                  tag: 'memory-lane-title-$id',
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.body.copyWith(
                      inherit: false,
                      height: 16 / 14,
                      fontFamily: TextStyles.outfitFontFamily,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.left,
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

class _MemoryLaneBackgroundClipper extends CustomClipper<Path> {
  const _MemoryLaneBackgroundClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.891891891892, 0)
      ..cubicTo(
        size.width * 0.951598344595,
        0,
        size.width,
        size.height * 0.033318348837,
        size.width,
        size.height * 0.074418604651,
      )
      ..lineTo(size.width, size.height * 0.925581395349)
      ..cubicTo(
        size.width,
        size.height * 0.966681651163,
        size.width * 0.951598344595,
        size.height,
        size.width * 0.891891891892,
        size.height,
      )
      ..lineTo(size.width * 0.108108108108, size.height)
      ..cubicTo(
        size.width * 0.048401655405,
        size.height,
        0,
        size.height * 0.966681651163,
        0,
        size.height * 0.925581395349,
      )
      ..lineTo(0, size.height * 0.196098302326)
      ..arcToPoint(
        Offset(size.width * 0.023645925676, size.height * 0.189943265116),
        radius: Radius.elliptical(
          size.width * 0.013513513514,
          size.height * 0.009302325581,
        ),
      )
      ..cubicTo(
        size.width * 0.029714202703,
        size.height * 0.194676893023,
        size.width * 0.073182898649,
        size.height * 0.209302325581,
        size.width * 0.121621621622,
        size.height * 0.209302325581,
      )
      ..cubicTo(
        size.width * 0.211181310811,
        size.height * 0.209302325581,
        size.width * 0.283783783784,
        size.height * 0.159324809302,
        size.width * 0.283783783784,
        size.height * 0.097674418605,
      )
      ..cubicTo(
        size.width * 0.283783783784,
        size.height * 0.055641748837,
        size.width * 0.250030540541,
        size.height * 0.019041051163,
        size.width * 0.245829554054,
        size.height * 0.017436786047,
      )
      ..arcToPoint(
        Offset(size.width * 0.252385060811, 0),
        radius: Radius.elliptical(
          size.width * 0.013513513514,
          size.height * 0.009302325581,
        ),
      )
      ..close();
  }

  @override
  bool shouldReclip(_MemoryLaneBackgroundClipper oldClipper) => false;
}
