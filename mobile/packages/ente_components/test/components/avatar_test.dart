import 'dart:convert';
import 'dart:typed_data';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avatar identity seeds are stable and normalized', () {
    expect(
      avatarSeedForIdentity(' Alice@Example.com '),
      avatarSeedForIdentity('alice@example.com'),
    );
    expect(avatarSeedForIdentity('alice@example.com'), 2493822278);
  });

  test('component identity colors use the Figma avatar palette', () {
    final color = avatarComponentColorForIdentity('email:alice@example.com');

    expect(avatarComponentColorForIdentity(' EMAIL:ALICE@EXAMPLE.COM '), color);
    expect(color, isIn(avatarComponentIdentityPalette));
    expect(avatarComponentIdentityPalette, const [
      AvatarComponentColor.yellow,
      AvatarComponentColor.green,
      AvatarComponentColor.orange,
      AvatarComponentColor.pink,
      AvatarComponentColor.purple,
      AvatarComponentColor.blue,
      AvatarComponentColor.cyan,
    ]);
  });

  testWidgets('AvatarComponent renders the Figma sizes', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            AvatarComponent(initials: 'E', size: AvatarComponentSize.xs),
            AvatarComponent(initials: 'E', size: AvatarComponentSize.small),
            AvatarComponent(initials: 'E'),
            AvatarComponent(initials: 'E', size: AvatarComponentSize.medium),
            AvatarComponent(initials: 'E', size: AvatarComponentSize.large),
            AvatarComponent(
              initials: 'E',
              size: AvatarComponentSize.contactHuge,
            ),
          ],
        ),
      ),
    );

    final surfaces = find.byKey(const ValueKey('avatar-surface'));
    expect(tester.getSize(surfaces.at(0)), const Size(16, 16));
    expect(tester.getSize(surfaces.at(1)), const Size(20, 20));
    expect(tester.getSize(surfaces.at(2)), const Size(24, 24));
    expect(tester.getSize(surfaces.at(3)), const Size(28, 28));
    expect(tester.getSize(surfaces.at(4)), const Size(32, 32));
    expect(tester.getSize(surfaces.at(5)), const Size(56, 56));
    for (final text in tester.widgetList<Text>(find.text('E'))) {
      expect(text.style?.fontFamily, TextStyles.body.fontFamily);
    }
  });

  testWidgets(
    'AvatarComponent supports image, icon, named colors, and seed colors',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              AvatarComponent.image(image: MemoryImage(_transparentPng)),
              const AvatarComponent.icon(),
              const AvatarComponent(
                initials: 'K',
                color: AvatarComponentColor.green,
              ),
              const AvatarComponent(
                initials: 'C',
                color: AvatarComponentColor.cyan,
              ),
              const AvatarComponent.seeded(initials: 'A', seed: 0),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.text('K'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(avatarLight.length, avatarDark.length);

      final cyanAvatar = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text('C'), matching: find.byType(DecoratedBox))
            .first,
      );
      expect((cyanAvatar.decoration as BoxDecoration).color, avatarCyan);
    },
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ComponentTheme.lightTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);
