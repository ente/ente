import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/album/row_item.dart";
import "package:photos/ui/common/loading_widget.dart";

class AlbumHorizontalList extends StatefulWidget {
  final Future<List<Collection>> Function() collectionsFuture;
  final bool? hasVerifiedLock;
  final VoidCallback? onViewAllTapped;

  const AlbumHorizontalList(
    this.collectionsFuture, {
    this.hasVerifiedLock,
    this.onViewAllTapped,
    super.key,
  });

  @override
  State<AlbumHorizontalList> createState() => _AlbumHorizontalListState();
}

class _AlbumHorizontalListState extends State<AlbumHorizontalList> {
  late StreamSubscription<CollectionUpdatedEvent>
  _collectionUpdatesSubscription;
  late Logger _logger;

  static const maxThumbnailWidth = 224.0;
  static const crossAxisSpacing = 8.0;
  static const horizontalPadding = 16.0;
  static const sectionBottomPadding = 16.0;
  static const titleVerticalPadding = 8.0;
  static const listTopPadding = 8.0;
  static const gridItemTextHeight = 52.0;

  @override
  void initState() {
    super.initState();
    _collectionUpdatesSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .listen((event) {
          setState(() {});
        });
    _logger = Logger((_AlbumHorizontalListState).toString());
  }

  @override
  void dispose() {
    _collectionUpdatesSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final int albumsCountInRow = max(screenWidth ~/ maxThumbnailWidth, 3);
    final totalHorizontalPadding = (albumsCountInRow - 1) * crossAxisSpacing;
    final sideOfThumbnail =
        (screenWidth - totalHorizontalPadding - horizontalPadding) /
        albumsCountInRow;
    debugPrint('$runtimeType widget build');
    return FutureBuilder<List<Collection>>(
      future: widget.collectionsFuture(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _logger.severe("failed to fetch albums", snapshot.error);
          return Text(AppLocalizations.of(context).somethingWentWrong);
        } else if (snapshot.hasData) {
          if (snapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }
          final allCollections = snapshot.data as List<Collection>;

          return Padding(
            padding: const EdgeInsets.only(bottom: sectionBottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: widget.onViewAllTapped,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: titleVerticalPadding,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context).albums,
                          style: getEnteTextTheme(context).large,
                        ),
                        if (widget.onViewAllTapped != null)
                          Container(
                            color: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 0, 0),
                              child: Icon(
                                Icons.chevron_right_outlined,
                                color: getEnteColorScheme(
                                  context,
                                ).blurStrokePressed,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height:
                        sideOfThumbnail + gridItemTextHeight + listTopPadding,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: allCollections.length,
                      padding: const EdgeInsets.only(
                        left: horizontalPadding / 2,
                        right: horizontalPadding / 2,
                        top: listTopPadding,
                      ),
                      itemBuilder: (context, index) {
                        final item = allCollections[index];
                        return Padding(
                          key: ValueKey('horizontal_list_${item.id}'),
                          padding: const EdgeInsets.only(
                            right: horizontalPadding / 2,
                          ),
                          child: AlbumRowItemWidget(
                            item,
                            sideOfThumbnail,
                            showFileCount: true,
                            hasVerifiedLock: widget.hasVerifiedLock,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return const Padding(
            padding: EdgeInsets.only(bottom: 24, top: 8),
            child: EnteLoadingWidget(),
          );
        }
      },
    );
  }
}
