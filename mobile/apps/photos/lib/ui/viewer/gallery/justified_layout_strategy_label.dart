import "package:ente_strings/ente_strings.dart";
import "package:flutter/widgets.dart";
import "package:photos/models/gallery/justified_layout_strategy.dart";

extension JustifiedLayoutStrategyLabel on JustifiedLayoutStrategy {
  String label(BuildContext context) => switch (this) {
    JustifiedLayoutStrategy.comfortLarge =>
      "${context.strings.layoutJustifiedComfort} Large (i)",
    JustifiedLayoutStrategy.flex =>
      "${context.strings.layoutJustifiedFlex} (i)",
  };
}
