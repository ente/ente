import "package:photos/models/collection/collection_invitation.dart";

class ShareInvitationFeedController {
  ShareInvitationFeedController({required this.load, required this.markSeen});

  final Future<List<CollectionInvitation>?> Function() load;
  final Future<void> Function(Iterable<CollectionInvitation>) markSeen;

  bool _visible = false;
  int _visibilityGeneration = 0;

  bool get visible => _visible;

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _visibilityGeneration++;
  }

  Future<void> refresh() async {
    final wasVisible = _visible;
    final generation = _visibilityGeneration;
    final snapshot = await load();
    if (snapshot != null &&
        wasVisible &&
        _visible &&
        generation == _visibilityGeneration) {
      await markSeen(snapshot);
    }
  }
}
