import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photos/ente_theme_data.dart';
import 'package:photos/ui/tools/editor/image_editor/image_editor_layer_selection.dart';
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

  testWidgets('font choices are exposed to screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openEditor(tester);
    await _tap(tester, find.text('Inter'));
    expect(find.semantics.byLabel('Outfit'), findsOne);
    semantics.dispose();
  });

  testWidgets('font menu stays on screen in RTL', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openEditor(tester, direction: TextDirection.rtl);
    await _tap(tester, find.text('Inter'));
    final menu = find
        .ancestor(of: find.text('Outfit'), matching: find.byType(Material))
        .first;
    expect(tester.getRect(menu).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(menu).right, lessThanOrEqualTo(320));
  });

  testWidgets('applied text renders the selected font and style', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    await _tap(tester, find.text('Inter'));
    await _tap(tester, find.text('Outfit'));
    await _tap(tester, find.byTooltip('Bold'));
    await _tap(tester, find.byTooltip('Italic'));
    await _tap(tester, find.text('Done'));
    final style = tester
        .widget<RoundedBackgroundText>(find.byType(RoundedBackgroundText))
        .text
        .style!;
    expect(style.fontFamily, 'packages/ente_components/Outfit');
    expect(style.fontWeight, FontWeight.w700);
    expect(style.fontStyle, FontStyle.italic);
    expect(editor.activeLayers, hasLength(1));
  });
  testWidgets('portrait text control rows stay separated on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openEditor(tester);
    await _tap(tester, find.text('Inter'));
    await _tap(tester, find.text('Gochi Hand'));
    await _tap(tester, find.byTooltip('Italic'));

    final styleRowBottom = tester.getRect(find.byTooltip('Italic')).bottom;
    final colorRowTop = tester.getRect(find.byTooltip('Text color')).top;
    expect(colorRowTop - styleRowBottom, greaterThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('applied text is selected and can be duplicated or deleted', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    await _tap(tester, find.text('Done'));
    expect(editor.activeLayers, hasLength(1));
    await _tap(tester, find.byTooltip('Duplicate'));
    expect(editor.activeLayers, hasLength(2));
    await _tap(tester, find.byTooltip('Delete'));
    expect(editor.activeLayers, hasLength(1));
  });

  testWidgets('each duplicate is selected on its own and drags alone', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    await _tap(tester, find.text('Done'));
    for (var i = 0; i < 3; i++) {
      await _tap(tester, find.byTooltip('Duplicate'));
      expect(editor.layerInteractionManager.selectedLayerIds, {
        editor.activeLayers.last.id,
      });
    }
    final offsets = [for (final layer in editor.activeLayers) layer.offset];

    await tester.drag(
      find.byKey(editor.activeLayers.last.keyInternalSize),
      const Offset(60, 40),
    );
    await tester.pumpAndSettle();

    final moved = [for (final layer in editor.activeLayers) layer.offset];
    expect(moved.take(3), offsets.take(3));
    expect(moved.last, isNot(offsets.last));
  });

  testWidgets('double tapping applied text reopens it for typing', (
    tester,
  ) async {
    var now = DateTime(2026);
    final editor = await _openEditor(tester, now: () => now);
    await _tap(tester, find.text('Done'));
    final layer = find.byKey(editor.activeLayers.single.keyInternalSize);

    await _tap(tester, layer);
    expect(find.bySubtype<TextEditor>(), findsNothing);
    now = now.add(kDoubleTapTimeout + const Duration(milliseconds: 1));
    await tester.tap(layer);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.bySubtype<TextEditor>(), findsNothing);
    now = now.add(const Duration(milliseconds: 50));
    await _tap(tester, layer);
    final reopened = tester.state<TextEditorState>(
      find.bySubtype<TextEditor>(),
    );
    expect(reopened.textCtrl.text, 'Hello');
    expect(reopened.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(find.byType(TextField), 'Hello again');
    await _tap(tester, find.text('Done'));
    expect((editor.activeLayers.single as TextLayer).text, 'Hello again');
  });

  testWidgets('text cannot reopen while the creation editor is closing', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(editor.isSubEditorOpen, isTrue);
    expect(editor.activeLayers, hasLength(1));
    final layer = find.byKey(editor.activeLayers.single.keyInternalSize);
    await tester.tap(layer);
    await tester.tap(layer);
    await tester.pumpAndSettle();
    expect(find.bySubtype<TextEditor>(), findsNothing);
    expect(editor.activeLayers, hasLength(1));

    editor.undoAction();
    await tester.pumpAndSettle();
    expect(editor.activeLayers, isEmpty);
  });

  testWidgets('editing text keeps undo and redo history in sync', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    await _tap(tester, find.text('Done'));

    final layer = editor.activeLayers.single as TextLayer;
    layer
      ..scale = 5
      ..rotation = 0.02;
    editor.setState(() {});
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Edit'));
    expect(find.byKey(layer.keyInternalSize), findsNothing);
    await _tap(tester, find.text('Cancel'));
    expect(find.byKey(layer.keyInternalSize), findsOneWidget);

    await tester.tap(find.byKey(layer.keyInternalSize));
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Edit'));
    await tester.enterText(find.byType(TextField), 'Changed');
    await _tap(tester, find.text('Done'));
    expect((editor.activeLayers.single as TextLayer).text, 'Changed');
    expect(editor.activeLayers.single.scale, 5);
    expect(editor.activeLayers.single.rotation, 0.02);

    editor.undoAction();
    await tester.pumpAndSettle();
    expect((editor.activeLayers.single as TextLayer).text, 'Hello');

    editor.redoAction();
    await tester.pumpAndSettle();
    expect((editor.activeLayers.single as TextLayer).text, 'Changed');
  });

  testWidgets('pinching and dragging text do not open the text editor', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    await _tap(tester, find.text('Done'));
    final layer = find.byKey(editor.activeLayers.single.keyInternalSize);
    final center = tester.getCenter(layer);
    final first = await tester.startGesture(center - const Offset(12, 0));
    final second = await tester.startGesture(center + const Offset(12, 0));
    await first.moveBy(const Offset(-20, 0));
    await second.moveBy(const Offset(20, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(find.bySubtype<TextEditor>(), findsNothing);

    await tester.tapAt(center);
    await tester.dragFrom(center, const Offset(45, 0));
    await tester.dragFrom(center + const Offset(45, 0), const Offset(-45, 0));
    await tester.pumpAndSettle();
    expect(find.bySubtype<TextEditor>(), findsNothing);
  });

  for (final cornerFirst in [true, false]) {
    testWidgets(
      'pinching text with one finger on a corner scales it like a pinch '
      '(${cornerFirst ? 'corner' : 'text'} touched first)',
      (tester) async {
        final editor = await _openEditor(tester);
        await _tap(tester, find.text('Done'));
        final rect = tester.getRect(
          find.byKey(editor.activeLayers.single.keyInternalSize),
        );
        final corner = rect.topRight + const Offset(6, -6);
        final anchor = rect.centerLeft + const Offset(8, 0);
        Offset cornerAt(double spread) => anchor + (corner - anchor) * spread;
        final first = await tester.startGesture(cornerFirst ? corner : anchor);
        if (cornerFirst) {
          expect(
            editor.layerInteractionManager.rotateScaleLayerSizeHelper,
            isNotNull,
          );
        }
        final second = await tester.startGesture(cornerFirst ? anchor : corner);
        final cornerGesture = cornerFirst ? first : second;
        var spread = 1.0;
        for (var i = 0; i < 10 && !editor.isLayerBeingTransformed; i++) {
          spread += 0.1;
          await cornerGesture.moveTo(cornerAt(spread));
          await tester.pump();
        }
        final startScale = editor.activeLayers.single.scale;
        await cornerGesture.moveTo(cornerAt(spread * 1.5));
        await tester.pump();

        final layer = editor.activeLayers.single;
        expect(layer.scale, closeTo(startScale * 1.5, 0.05));
        expect(layer.rotation, closeTo(0, 0.01));
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('a cancelled corner touch stops rotating and scaling', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    await _tap(tester, find.text('Done'));
    final rect = tester.getRect(
      find.byKey(editor.activeLayers.single.keyInternalSize),
    );
    final gesture = await tester.startGesture(
      rect.topRight + const Offset(6, -6),
    );
    expect(
      editor.layerInteractionManager.rotateScaleLayerSizeHelper,
      isNotNull,
    );
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(editor.layerInteractionManager.rotateScaleLayerSizeHelper, isNull);
  });

  testWidgets('typed text remains visible after rotating to landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openEditor(tester);
    tester.view.physicalSize = const Size(874, 402);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();

    final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    final barTop = tester.getTopLeft(find.byType(ImageEditorTextBar)).dy;
    expect(fieldBottom, lessThanOrEqualTo(barTop));
    expect(tester.takeException(), isNull);
  });
}

Future<ProImageEditorState> _openEditor(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  DateTime Function()? now,
}) async {
  final key = GlobalKey<ProImageEditorState>();
  SubEditor? activeSubEditor;
  final doubleTap = ImageEditorLayerDoubleTap(() => key.currentState, now: now);
  final scaleRotate = ImageEditorLayerScaleRotate();
  await tester.pumpWidget(
    MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: Builder(
        builder: (context) => Listener(
          onPointerDown: doubleTap.onPointerDown,
          onPointerMove: doubleTap.onPointerMove,
          onPointerUp: doubleTap.onPointerUp,
          onPointerCancel: doubleTap.onPointerCancel,
          child: ProImageEditor.memory(
            Uint8List.fromList(
              img.encodePng(img.Image(width: 400, height: 300)),
            ),
            key: key,
            callbacks: ProImageEditorCallbacks(
              mainEditorCallbacks: MainEditorCallbacks(
                onOpenSubEditor: (editor) => activeSubEditor = editor,
                onLayerTapDown: doubleTap.onLayerDown,
                onLayerTapUp: doubleTap.onLayerUp,
                onScaleStart: scaleRotate.onScaleStart,
                onCreateTextLayer: () =>
                    imageEditorCreateTextLayer(() => key.currentState),
              ),
            ),
            configs: ProImageEditorConfigs(
              theme: Theme.of(context),
              imageGeneration: const ImageGenerationConfigs(
                enableIsolateGeneration: false,
                enableBackgroundGeneration: false,
              ),
              layerInteraction: imageEditorLayerInteractionConfigs(
                context,
                () => key.currentState,
                scaleRotate,
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
