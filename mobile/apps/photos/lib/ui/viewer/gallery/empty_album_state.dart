import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/ui/collections/album/smart_album_people.dart";
import "package:photos/ui/viewer/gallery/hooks/add_photos_sheet.dart";
import "package:photos/utils/dialog_util.dart";

class EmptyAlbumState extends StatelessWidget {
  final Collection c;
  final VoidCallback? onAddPhotos;

  const EmptyAlbumState(this.c, {super.key, this.onAddPhotos});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset("assets/albums-widget-static.png", height: 160),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(
                  context,
                ).startWithAddingPhotosOrFamiliarFaces,
                style: TextStyles.display2.copyWith(color: colors.textBase),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 200),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ButtonComponent(
                variant: ButtonComponentVariant.primary,
                label: AppLocalizations.of(context).addPhotos,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  try {
                    await showAddPhotosSheet(context, c);
                  } catch (e) {
                    if (!context.mounted) return;
                    await showGenericErrorDialog(context: context, error: e);
                  }
                },
              ),
              const SizedBox(height: 12),
              ButtonComponent(
                variant: ButtonComponentVariant.neutral,
                label: AppLocalizations.of(context).autoAddPeople,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  await routeToPage(
                    context,
                    SmartAlbumPeople(collectionId: c.id),
                  );
                  onAddPhotos?.call();
                },
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ],
    );
  }
}
