import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/location/location.dart";
import "package:photos/service_locator.dart";
import "package:photos/states/location_state.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/viewer/location/pick_center_point_widget.dart";

class EditCenterPointTileWidget extends StatelessWidget {
  const EditCenterPointTileWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final centerPointInDMS = locationService.convertLocationToDMS(
      InheritedLocationTagData.of(context).centerPoint,
    );
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          color: colorScheme.fillFaint,
          child: Icon(
            Icons.location_on_outlined,
            color: colorScheme.strokeFaint,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4.5, 16, 4.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).centerPoint,
                  style: textTheme.body,
                ),
                const SizedBox(height: 4),
                Text(
                  "${centerPointInDMS![0]}, ${centerPointInDMS[1]}",
                  style: textTheme.miniMuted,
                ),
              ],
            ),
          ),
        ),
        IconButtonWidget(
          onTap: () async {
            final Location? centerPoint = await showPickCenterPointSheet(
              context,
              locationTagName: InheritedLocationTagData.of(
                context,
              ).locationTagEntity!.item.name,
            );
            if (centerPoint != null) {
              if (!context.mounted) return;
              InheritedLocationTagData.of(
                context,
              ).updateCenterPoint(centerPoint);
            }
          },
          icon: Icons.edit,
          iconButtonType: IconButtonType.secondary,
        ),
      ],
    );
  }
}
