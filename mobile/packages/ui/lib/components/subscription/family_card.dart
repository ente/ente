import 'dart:async';

import 'package:ente_components/components/navigation_card_component.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class FamilyCard extends StatelessWidget {
  const FamilyCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) => NavigationCardComponent(
    title: title,
    subtitle: subtitle,
    leading: HugeIcon(
      icon: HugeIcons.strokeRoundedHouseHeart,
      size: NavigationCardComponent.leadingSize,
      color: context.componentColors.textLight,
    ),
    onTap: onTap,
  );
}
