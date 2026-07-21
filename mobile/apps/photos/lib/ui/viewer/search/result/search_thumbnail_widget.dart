import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import 'package:photos/ui/viewer/file/no_thumbnail_widget.dart';
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/ui/viewer/people/person_face_widget.dart';

class SearchThumbnailWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Hero(
      tag: tagPrefix + (file?.tag ?? ""),
      child: SizedBox(
        height: size,
        width: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: file != null
              ? (searchResult != null &&
                        searchResult!.type() == ResultType.faces)
                    ? PersonFaceWidget(
                        personId: (searchResult as GenericSearchResult)
                            .params[kPersonParamID],
                        clusterID: (searchResult as GenericSearchResult)
                            .params[kClusterParamId],
                      )
                    : ThumbnailWidget(file!)
              : const NoThumbnailWidget(addBorder: false),
        ),
      ),
    );
  }
}

class ContactSearchThumbnailWidget extends StatefulWidget {
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
  State<ContactSearchThumbnailWidget> createState() =>
      _ContactSearchThumbnailWidgetState();
}

class _ContactSearchThumbnailWidgetState
    extends State<ContactSearchThumbnailWidget> {
  bool _canUsePersonFaceWidget = true;
  late String? _personID;
  late String _email;
  final _logger = Logger("_ContactSearchThumbnailWidgetState");

  @override
  void initState() {
    super.initState();
    _personID = widget.searchResult.params[kPersonParamID];
    _email = widget.searchResult.params[kContactEmail];
    _canUsePersonFaceWidget = _personID != null;
  }

  @override
  void didUpdateWidget(covariant ContactSearchThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newPersonID = widget.searchResult.params[kPersonParamID];
    final newEmail = widget.searchResult.params[kContactEmail];
    if (newPersonID != _personID) {
      _personID = newPersonID;
      _canUsePersonFaceWidget = newPersonID != null;
    }
    if (newEmail != _email) {
      _email = newEmail;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      width: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: _canUsePersonFaceWidget
            ? PersonFaceWidget(
                personId: _personID,
                onErrorCallback: () {
                  if (mounted) {
                    _logger.severe(
                      "Failed to load face for person with ID: $_personID",
                    );
                    setState(() {
                      _canUsePersonFaceWidget = false;
                    });
                  }
                },
              )
            : NoFaceForContactWidget(user: User(email: _email)),
      ),
    );
  }
}

class NoFaceForContactWidget extends StatelessWidget {
  final User user;
  final bool addBorder;
  const NoFaceForContactWidget({
    this.addBorder = true,
    required this.user,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final enteColorScheme = getEnteColorScheme(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: addBorder
            ? Border.all(color: enteColorScheme.strokeFaint, width: 1)
            : null,
        color: enteColorScheme.fillFaint,
      ),
      child: Center(child: UserInitialsAvatar(user)),
    );
  }
}
