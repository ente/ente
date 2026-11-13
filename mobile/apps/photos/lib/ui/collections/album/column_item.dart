import 'package:flutter/material.dart';
import 'package:photos/models/collection/collection.dart';
import "package:photos/ui/collections/album/list_item.dart";

class AlbumColumnItemWidget extends StatelessWidget {
  final Collection collection;
  final List<Collection> selectedCollections;

  const AlbumColumnItemWidget(
    this.collection, {
    super.key,
    this.selectedCollections = const [],
  });

  @override
  Widget build(BuildContext context) {
    return AlbumListItemWidget(
      collection,
      isSelected: selectedCollections.contains(collection),
    );
  }
}
