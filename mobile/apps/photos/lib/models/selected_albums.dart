import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/events/clear_album_selections_event.dart";
import 'package:photos/models/collection/collection.dart';

class SelectedAlbums extends ChangeNotifier {
  final albums = <Collection>{};

  void toggleSelection(Collection albumToToggle) {
    final Collection? alreadySelected = albums.firstWhereOrNull(
      (element) => element.id == albumToToggle.id,
    );
    if (alreadySelected != null) {
      albums.remove(alreadySelected);
    } else {
      albums.add(albumToToggle);
    }
    notifyListeners();
  }

  void select(Set<Collection> albumsToSelect) {
    albums.addAll(albumsToSelect);
    notifyListeners();
  }

  void unSelect(Set<Collection> albumsToUnselect, {bool skipNotify = false}) {
    albums.removeWhere((album) => albumsToUnselect.contains(album));
    if (!skipNotify) {
      notifyListeners();
    }
  }

  bool isAlbumSelected(Collection album) {
    return albums.any((element) => element.id == album.id);
  }

  void clearAll() {
    Bus.instance.fire(ClearAlbumSelectionsEvent());
    albums.clear();
    notifyListeners();
  }
}
