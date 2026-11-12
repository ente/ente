import "package:flutter/material.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/ui/viewer/file/hero_image.dart";
import 'package:photos/ui/viewer/file/no_thumbnail_widget.dart';
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/ui/viewer/people/person_face_widget.dart';
import "package:photos/ui/viewer/search/contact_avatar_widget.dart";

class SearchThumbnailWidget extends StatefulWidget {
  final EnteFile? file;
  final SearchResult? searchResult;
  final String tagPrefix;
  final double size;
  final double borderRadius;

  const SearchThumbnailWidget(
    this.file,
    this.tagPrefix, {
    this.searchResult,
    this.size = 56,
    this.borderRadius = 12,
    super.key,
  });

  @override
  State<SearchThumbnailWidget> createState() => _SearchThumbnailWidgetState();
}

class _SearchThumbnailWidgetState extends State<SearchThumbnailWidget> {
  late final _heroChildKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isLocation =
        widget.searchResult?.type() == ResultType.location ||
        widget.searchResult?.type() == ResultType.locationSuggestion;
    final result = widget.searchResult;
    final isPerson =
        result is GenericSearchResult && result.type() == ResultType.faces;
    final hasCover =
        isLocation || isPerson || result?.type() == ResultType.magic;
    return Hero(
      tag: isPerson
          ? PersonFaceWidget.coverHeroTag(
              tagPrefix: "people_search",
              personId: result.params[kPersonParamID],
              clusterID: result.params[kClusterParamId],
            )
          : isLocation
          ? widget.tagPrefix
          : widget.tagPrefix + (widget.file?.tag ?? ""),
      createRectTween: hasCover
          ? (begin, end) => RectTween(begin: begin, end: end)
          : null,
      transitionOnUserGestures: hasCover,
      placeholderBuilder: isPerson ? imageHeroPlaceholderBuilder : null,
      child: SizedBox(
        key: isPerson ? _heroChildKey : null,
        height: widget.size,
        width: widget.size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: widget.file != null
              ? (widget.searchResult != null &&
                        widget.searchResult!.type() == ResultType.faces)
                    ? PersonFaceWidget(
                        personId: (widget.searchResult as GenericSearchResult)
                            .params[kPersonParamID],
                        clusterID: (widget.searchResult as GenericSearchResult)
                            .params[kClusterParamId],
                      )
                    : ThumbnailWidget(widget.file!)
              : const NoThumbnailWidget(addBorder: false),
        ),
      ),
    );
  }
}

class ContactSearchThumbnailWidget extends StatelessWidget {
  final GenericSearchResult searchResult;
  final String tagPrefix;
  final double size;
  final double borderRadius;

  const ContactSearchThumbnailWidget(
    this.tagPrefix, {
    required this.searchResult,
    this.size = 56,
    this.borderRadius = 12,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ContactAvatarWidget(
      contactUserId: searchResult.params[kContactUserId] as int,
      email: searchResult.params[kContactEmail] as String,
      personId: searchResult.params[kPersonParamID] as String?,
      size: size,
      borderRadius: borderRadius,
    );
  }
}
