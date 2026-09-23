import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photos/ente_theme_data.dart';
import 'package:photos/ui/tools/editor/image_editor/image_editor_main_bottom_bar.dart';
import 'package:photos/ui/tools/editor/image_editor/image_editor_text_bar.dart';
import 'package:pro_image_editor/features/text_editor/widgets/rounded_background_text/rounded_background_text.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('packages/ente_components/Inter')..addFont(
          rootBundle.load('packages/ente_components/fonts/Inter-Regular.ttf'),
        ))
        .load();
  });

  testWidgets('hue selection is explicit and colors stay independent', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    final text = tester.state<TextEditorState>(find.byType(TextEditor));
    const cyan = Color(0xFF00FFFF);

    await _tap(tester, find.text('Color'));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.5);
    expect(text.primaryColor, Colors.white);
    expect(find.byType(Slider), paints..circle(color: cyan));
    await _tap(tester, find.byType(Slider));
    expect(text.primaryColor, cyan);
    expect(text.secondaryColor, Colors.black);

    await _tap(tester, find.text('Background'));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.5);
    expect(text.secondaryColor, Colors.black);
    await _tap(tester, find.byType(Slider));
    expect(text.secondaryColor, cyan);
    await _tap(tester, find.byTooltip('White'));
    expect(text.primaryColor, cyan);
    expect(text.secondaryColor, Colors.white);
    expect(find.byType(Slider), paints..circle(color: cyan));
    await _tap(tester, find.text('Color'));
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    final chosenColor = text.primaryColor;
    expect(chosenColor, isNot(cyan));
    expect(text.secondaryColor, Colors.white);
    await _tap(tester, find.text('Done'));

    final layer = editor.activeLayers.single as TextLayer;
    await _tap(tester, find.byKey(layer.keyInternalSize));
    final reopened = tester.state<TextEditorState>(find.byType(TextEditor));
    expect(reopened.primaryColor, chosenColor);
    expect(reopened.secondaryColor, Colors.white);
    await _tap(tester, find.text('Color'));
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      closeTo(HSVColor.fromColor(chosenColor).hue / 360, 0.001),
    );
  });

  testWidgets('applied text renders each selected font', (tester) async {
    final editor = await _openEditor(tester);
    for (final font in ['Inter', 'Outfit', 'Gochi Hand']) {
      await _tap(tester, find.text('Font'));
      await _tap(tester, find.text(font));
      await _tap(tester, find.text('Done'));
      final rendered = tester.widget<RoundedBackgroundText>(
        find.byType(RoundedBackgroundText),
      );
      expect(rendered.text.style!.fontFamily, 'packages/ente_components/$font');
      if (font != 'Gochi Hand') {
        await _tap(
          tester,
          find.byKey(editor.activeLayers.single.keyInternalSize),
        );
      }
    }
  });

  for (final (style, opacity) in [
    ('No background', 0.0),
    ('Translucent background', 0.5),
  ]) {
    testWidgets('$style preserves the chosen background when reopened', (
      tester,
    ) async {
      final editor = await _openEditor(tester);
      await _tap(tester, find.text('Background'));
      await _tap(tester, find.byType(Slider));
      await _tap(tester, find.byTooltip(style));
      await _tap(tester, find.text('Done'));
      final layer = editor.activeLayers.single as TextLayer;
      expect(layer.background.a, closeTo(opacity, 1 / 255));
      expect(layer.background.withValues(alpha: 1), const Color(0xFF00FFFF));

      await _tap(tester, find.byKey(layer.keyInternalSize));
      final reopened = tester.state<TextEditorState>(find.byType(TextEditor));
      expect(reopened.secondaryColor, layer.background);
      await _tap(tester, find.text('Background'));
      await _tap(tester, find.byTooltip('Solid background'));
      expect(reopened.secondaryColor, const Color(0xFF00FFFF));
      expect(reopened.primaryColor, Colors.white);
    });
  }

  testWidgets('large text keeps the preview and controls usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final editor = await _openEditor(tester, textScale: 1.5);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(TextField))).scale(14),
      14,
    );
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('Font'))).scale(14),
      21,
    );
    await tester.ensureVisible(find.text('Background'));
    await _tap(tester, find.text('Background'));
    expect(
      tester
          .state<TextEditorState>(find.byType(TextEditor))
          .editorBodySize
          .height,
      greaterThanOrEqualTo(tester.getSize(find.byType(TextField)).height),
    );
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsOneWidget);
    expect(editor.activeLayers, isEmpty);
    await _tap(tester, find.text('Cancel'));
    await tester.ensureVisible(find.text('Filter'));
    await _tap(tester, find.text('Filter'));
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(FilterEditor)),
      ).scale(14),
      21,
    );
  });
}

Future<ProImageEditorState> _openEditor(
  WidgetTester tester, {
  double textScale = 1,
}) async {
  final key = GlobalKey<ProImageEditorState>();
  SubEditor? activeSubEditor;
  await tester.pumpWidget(
    MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => ProImageEditor.memory(
          Uint8List.fromList(img.encodePng(img.Image(width: 400, height: 300))),
          key: key,
          callbacks: ProImageEditorCallbacks(
            mainEditorCallbacks: MainEditorCallbacks(
              onOpenSubEditor: (editor) => activeSubEditor = editor,
            ),
          ),
          configs: ProImageEditorConfigs(
            theme: Theme.of(context),
            imageGeneration: const ImageGenerationConfigs(
              enableIsolateGeneration: false,
              enableBackgroundGeneration: false,
            ),
            layerInteraction: const LayerInteractionConfigs(
              selectable: LayerInteractionSelectable.disabled,
            ),
            textEditor: imageEditorTextConfigs(context),
            mainEditor: MainEditorConfigs(
              style: MainEditorStyle(
                subEditorPage: imageEditorSubEditorPageStyle(
                  () => activeSubEditor,
                ),
              ),
              widgets: MainEditorWidgets(
                bottomBar: (editor, stream, barKey) => ReactiveWidget(
                  key: barKey,
                  stream: stream,
                  builder: (_) => ImageEditorMainBottomBar(
                    editor: editor,
                    configs: editor.configs,
                    callbacks: editor.callbacks,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() => key.currentState!.decodeImage());
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Text').last);
  await _tap(tester, find.text('Text').last);
  await tester.enterText(find.byType(TextField), 'Hello');
  return key.currentState!;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
