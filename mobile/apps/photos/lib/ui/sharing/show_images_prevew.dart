import 'dart:math' as math;
import "dart:ui";

import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class LinkPlaceholder extends StatelessWidget {
  const LinkPlaceholder({required this.files, super.key});

  final List<EnteFile> files;

  @override
  Widget build(BuildContext context) {
    final int length = files.length;
    Widget placeholderWidget = const SizedBox(height: 300, width: 300);

    if (length == 1) {
      placeholderWidget = _BackDrop(
        backDropImage: files[0],
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final imageHeight = constraints.maxHeight * 0.9;
              return Center(
                child: _CustomImage(
                  width: imageHeight,
                  height: imageHeight,
                  file: files[0],
                  zIndex: 0,
                ),
              );
            },
          ),
        ],
      );
    } else if (length == 2) {
      placeholderWidget = _BackDrop(
        backDropImage: files[0],
        children: [
          LayoutBuilder(
            builder: ((context, constraints) {
              final imageHeight = constraints.maxHeight * 0.52;
              return Stack(
                children: [
                  Positioned(
                    top: 145,
                    left: 180,
                    child: _CustomImage(
                      height: imageHeight,
                      width: imageHeight,
                      file: files[1],
                      zIndex: 10 * math.pi / 180,
                    ),
                  ),
                  Positioned(
                    top: 45,
                    left: 3.2,
                    child: _CustomImage(
                      height: imageHeight,
                      width: imageHeight,
                      file: files[0],
                      zIndex: -(10 * math.pi / 180),
                      imageShadow: const [
                        BoxShadow(
                          offset: Offset(0, 0),
                          blurRadius: 0.84,
                          color: Color.fromRGBO(0, 0, 0, 0.11),
                        ),
                        BoxShadow(
                          offset: Offset(0.84, 0.84),
                          blurRadius: 1.68,
                          color: Color.fromRGBO(0, 0, 0, 0.09),
                        ),
                        BoxShadow(
                          offset: Offset(2.53, 2.53),
                          blurRadius: 2.53,
                          color: Color.fromRGBO(0, 0, 0, 0.05),
                        ),
                        BoxShadow(
                          offset: Offset(5.05, 4.21),
                          blurRadius: 2.53,
                          color: Color.fromRGBO(0, 0, 0, 0.02),
                        ),
                        BoxShadow(
                          offset: Offset(7.58, 6.74),
                          blurRadius: 2.53,
                          color: Color.fromRGBO(0, 0, 0, 0.0),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      );
    } else if (length == 3) {
      placeholderWidget = _BackDrop(
        backDropImage: files[0],
        children: [
          LayoutBuilder(
            builder: (context, constraint) {
              final imageHeightSmall = constraint.maxHeight * 0.43;
              final imageHeightLarge = constraint.maxHeight * 0.50;
              return Stack(
                children: [
                  Positioned(
                    top: 55,
                    child: _CustomImage(
                      height: imageHeightSmall,
                      width: imageHeightSmall,
                      file: files[1],
                      zIndex: -(20 * math.pi / 180),
                    ),
                  ),
                  Positioned(
                    bottom: 50,
                    right: -10,
                    child: _CustomImage(
                      height: imageHeightSmall,
                      width: imageHeightSmall,
                      file: files[2],
                      zIndex: 20 * math.pi / 180,
                    ),
                  ),
                  Center(
                    child: _CustomImage(
                      height: imageHeightLarge,
                      width: imageHeightLarge,
                      file: files[0],
                      zIndex: 0.0,
                      imageShadow: const [
                        BoxShadow(
                          offset: Offset(0, 1.02),
                          blurRadius: 2.04,
                          color: Color.fromRGBO(0, 0, 0, 0.23),
                        ),
                        BoxShadow(
                          offset: Offset(0, 3.06),
                          blurRadius: 3.06,
                          color: Color.fromRGBO(0, 0, 0, 0.2),
                        ),
                        BoxShadow(
                          offset: Offset(0, 6.12),
                          blurRadius: 4.08,
                          color: Color.fromRGBO(0, 0, 0, 0.12),
                        ),
                        BoxShadow(
                          offset: Offset(0, 11.22),
                          blurRadius: 5.1,
                          color: Color.fromRGBO(0, 0, 0, 0.04),
                        ),
                        BoxShadow(
                          offset: Offset(0, 18.36),
                          blurRadius: 5.1,
                          color: Color.fromRGBO(0, 0, 0, 0.0),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
    } else if (length > 3) {
      placeholderWidget = _BackDrop(
        backDropImage: files[0],
        children: [
          LayoutBuilder(
            builder: (context, constraint) {
              final imageHeightSmall = constraint.maxHeight * 0.43;
              final imageHeightLarge = constraint.maxHeight * 0.50;
              final boxHeight = constraint.maxHeight * 0.15;
              return Stack(
                children: [
                  Positioned(
                    top: 30,
                    left: 25,
                    child: _CustomImage(
                      height: imageHeightSmall,
                      width: imageHeightSmall,
                      file: files[1],
                      zIndex: 0.0,
                    ),
                  ),
                  Positioned(
                    top: 202,
                    left: 50,
                    child: _CustomImage(
                      height: imageHeightSmall,
                      width: imageHeightSmall,
                      file: files[2],
                      zIndex: 0.0,
                    ),
                  ),
                  Positioned(
                    top: 75,
                    right: 25,
                    child: _CustomImage(
                      height: imageHeightLarge,
                      width: imageHeightLarge,
                      file: files[0],
                      zIndex: 0.0,
                      imageShadow: const [
                        BoxShadow(
                          offset: Offset(0, 1.02),
                          blurRadius: 2.04,
                          color: Color.fromRGBO(0, 0, 0, 0.23),
                        ),
                        BoxShadow(
                          offset: Offset(0, 3.06),
                          blurRadius: 3.06,
                          color: Color.fromRGBO(0, 0, 0, 0.2),
                        ),
                        BoxShadow(
                          offset: Offset(0, 6.12),
                          blurRadius: 4.08,
                          color: Color.fromRGBO(0, 0, 0, 0.12),
                        ),
                        BoxShadow(
                          offset: Offset(0, 11.22),
                          blurRadius: 5.1,
                          color: Color.fromRGBO(0, 0, 0, 0.04),
                        ),
                        BoxShadow(
                          offset: Offset(0, 18.36),
                          blurRadius: 5.1,
                          color: Color.fromRGBO(0, 0, 0, 0.0),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 290,
                    left: 270,
                    child: Stack(
                      children: [
                        Center(
                          child: Container(
                            height: boxHeight + 1,
                            width: boxHeight + 1,
                            decoration: ShapeDecoration(
                              color: const Color.fromRGBO(129, 129, 129, 0.1),
                              shape: SmoothRectangleBorder(
                                borderRadius: SmoothBorderRadius(
                                  cornerRadius: 12.5,
                                  cornerSmoothing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: ClipSmoothRect(
                            radius: SmoothBorderRadius(
                              cornerRadius: 12,
                              cornerSmoothing: 1.0,
                            ),
                            child: Container(
                              height: boxHeight,
                              width: boxHeight,
                              color: const Color.fromRGBO(255, 255, 255, 1),
                              padding: const EdgeInsets.all(4),
                              child: Center(
                                child: FittedBox(
                                  child: Text(
                                    "+"
                                    "${length - 3}",
                                    style: getEnteTextTheme(context).h3Bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
    }

    return placeholderWidget;
  }
}

class _BackDrop extends StatelessWidget {
  const _BackDrop({required this.backDropImage, required this.children});

  final List<Widget> children;
  final EnteFile backDropImage;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          ThumbnailWidget(
            backDropImage,
            shouldShowSyncStatus: false,
            shouldShowFavoriteIcon: false,
            thumbnailSize: thumbnailLargeSize,
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _CustomImage extends StatelessWidget {
  const _CustomImage({
    required this.width,
    required this.height,
    required this.file,
    required this.zIndex,
    this.imageShadow,
  });
  final List<BoxShadow>? imageShadow;
  final EnteFile file;
  final double zIndex;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      transform: Matrix4.rotationZ(zIndex),
      height: height,
      width: width,
      child: Stack(
        children: [
          Center(
            child: Container(
              height: height,
              width: width,
              decoration: ShapeDecoration(
                color: const Color.fromRGBO(129, 129, 129, 0.1),
                shadows: imageShadow,
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 21.0,
                    cornerSmoothing: 1.0,
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              height: height - 2,
              width: width - 2,
              child: ClipSmoothRect(
                radius: SmoothBorderRadius(
                  cornerRadius: 20.0,
                  cornerSmoothing: 1,
                ),
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: Container(
                  decoration: BoxDecoration(boxShadow: imageShadow),
                  child: ThumbnailWidget(
                    file,
                    shouldShowSyncStatus: false,
                    shouldShowFavoriteIcon: false,
                    thumbnailSize: thumbnailLargeSize,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
