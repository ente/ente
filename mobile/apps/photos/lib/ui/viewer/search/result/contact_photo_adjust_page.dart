import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/generated/l10n.dart";
import "package:pro_image_editor/pro_image_editor.dart";

class ContactPhotoAdjustPage extends StatefulWidget {
  final Uint8List imageBytes;

  const ContactPhotoAdjustPage({required this.imageBytes, super.key});

  @override
  State<ContactPhotoAdjustPage> createState() => _ContactPhotoAdjustPageState();
}

class _ContactPhotoAdjustPageState extends State<ContactPhotoAdjustPage> {
  bool _isReturningBytes = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final actionTextStyle = TextStyles.large.copyWith(color: colors.textBase);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: CropRotateEditor.memory(
        widget.imageBytes,
        initConfigs: CropRotateEditorInitConfigs(
          theme: ThemeData(
            scaffoldBackgroundColor: colors.backgroundBase,
            appBarTheme: AppBarTheme(
              titleTextStyle: actionTextStyle,
              backgroundColor: colors.backgroundBase,
            ),
            bottomAppBarTheme: BottomAppBarThemeData(
              color: colors.backgroundBase,
            ),
            brightness: isLightMode ? Brightness.light : Brightness.dark,
          ),
          convertToUint8List: true,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {
              if (mounted) {
                Navigator.of(context).pop(bytes);
              }
            },
          ),
          configs: ProImageEditorConfigs(
            imageGeneration: const ImageGenerationConfigs(
              jpegQuality: 100,
              enableIsolateGeneration: true,
              pngLevel: 0,
            ),
            cropRotateEditor: CropRotateEditorConfigs(
              tools: const [],
              initAspectRatio: 1.0,
              aspectRatios: const [AspectRatioItem(text: "1*1", value: 1.0)],
              style: CropRotateEditorStyle(
                background: colors.backgroundBase,
                cropCornerColor: colors.primary,
              ),
              widgets: CropRotateEditorWidgets(
                appBar: (editor, rebuildStream) => ReactiveAppbar(
                  stream: rebuildStream,
                  builder: (_) => AppBar(
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    backgroundColor: colors.backgroundBase,
                    titleSpacing: 0,
                    title: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            AppLocalizations.of(context).cancel,
                            style: actionTextStyle,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _isReturningBytes
                              ? null
                              : () async {
                                  setState(() {
                                    _isReturningBytes = true;
                                  });
                                  await editor.done();
                                },
                          child: Text(
                            AppLocalizations.of(context).useSelectedPhoto,
                            style: actionTextStyle.copyWith(
                              color: _isReturningBytes
                                  ? colors.textLight
                                  : colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                bottomBar: (_, rebuildStream) => ReactiveWidget<Widget>(
                  stream: rebuildStream,
                  builder: (_) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
