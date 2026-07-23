import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/people/cluster_page.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:visibility_detector/visibility_detector.dart";

class PersonClustersPage extends StatefulWidget {
  final PersonEntity person;
  const PersonClustersPage(this.person, {super.key});

  @override
  State<PersonClustersPage> createState() => _PersonClustersPageState();
}

class _PersonClustersPageState extends State<PersonClustersPage> {
  final Logger _logger = Logger("_PersonClustersState");
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.person.data.name)),
      body: FutureBuilder<Map<String, List<EnteFile>>>(
        future: SearchService.instance.getClusterFilesForPersonID(
          widget.person.remoteID,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final clusters = snapshot.data!;
            final List<String> keys = clusters.keys.toList();
            // Sort the clusters by the number of files in each cluster, largest first
            keys.sort(
              (b, a) => clusters[a]!.length.compareTo(clusters[b]!.length),
            );
            return ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final String clusterID = keys[index];
                final List<EnteFile> files = clusters[clusterID]!;
                return InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ClusterPage(
                          files,
                          personID: widget.person,
                          clusterID: clusterID,
                          showNamingBanner: false,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: FaceThumbnailSquircleClip(
                            child: files.isNotEmpty
                                ? PersonFaceWidget(clusterID: clusterID)
                                : const NoThumbnailWidget(addBorder: false),
                          ),
                        ),
                        const SizedBox(
                          width: 8.0,
                        ), // Add some spacing between the thumbnail and the text
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  ).photosCount(count: files.length),
                                  style: getEnteTextTheme(context).body,
                                ),
                                (index != 0)
                                    ? GestureDetector(
                                        onTap: () async {
                                          try {
                                            await PersonService.instance
                                                .removeClusterToPerson(
                                                  personID:
                                                      widget.person.remoteID,
                                                  clusterID: clusterID,
                                                );
                                            _logger.info(
                                              "Removed cluster $clusterID from person ${widget.person.remoteID}",
                                            );
                                            Bus.instance.fire(
                                              PeopleChangedEvent(),
                                            );
                                            setState(() {});
                                          } catch (e) {
                                            _logger.severe(
                                              "removing cluster from person,",
                                              e,
                                            );
                                          }
                                        },
                                        child: const Icon(
                                          CupertinoIcons.minus_circled,
                                          color: Colors.red,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          } else if (snapshot.hasError) {
            _logger.warning("Failed to get cluster", snapshot.error);
            return Center(child: Text(AppLocalizations.of(context).error));
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

class PersonClustersWidget extends StatefulWidget {
  final PersonEntity person;

  const PersonClustersWidget(this.person, {super.key});

  @override
  State<PersonClustersWidget> createState() => _PersonClustersWidgetState();
}

class _PersonClustersWidgetState extends State<PersonClustersWidget> {
  final Logger _logger = Logger("_PersonClustersWidgetState");

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<EnteFile>>>(
      future: SearchService.instance.getClusterFilesForPersonID(
        widget.person.remoteID,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final clusters = snapshot.data!;
          final List<String> keys = clusters.keys.toList();
          // Sort the clusters by the number of files in each cluster, largest first
          keys.sort(
            (b, a) => clusters[a]!.length.compareTo(clusters[b]!.length),
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              // Determine number of columns based on available width
              // Minimum column width of 150, maximum of 250
              final double columnWidth = MediaQuery.of(context).size.width > 600
                  ? 250
                  : 150;
              final int crossAxisCount = (constraints.maxWidth / columnWidth)
                  .floor()
                  .clamp(2, 5);

              return GridView.builder(
                shrinkWrap: true,
                physics:
                    const NeverScrollableScrollPhysics(), // Disable scrolling
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1, // Adjust this to control height vs width
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: keys.length,
                itemBuilder: (context, index) {
                  final String clusterID = keys[index];
                  final List<EnteFile> files = clusters[clusterID]!;

                  return _ClusterWrapperForGird(
                    files,
                    clusterID,
                    widget.person,
                    onClusterRemoved: () {
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  );
                },
              );
            },
          );
        } else if (snapshot.hasError) {
          _logger.warning("Failed to get cluster", snapshot.error);
          return Center(child: Text(AppLocalizations.of(context).error));
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}

class _ClusterWrapperForGird extends StatefulWidget {
  final List<EnteFile> files;
  final String clusterID;
  final PersonEntity person;
  final VoidCallback onClusterRemoved;

  const _ClusterWrapperForGird(
    this.files,
    this.clusterID,
    this.person, {
    required this.onClusterRemoved,
  });

  @override
  State<_ClusterWrapperForGird> createState() => __ClusterWrapperForGirdState();
}

class __ClusterWrapperForGirdState extends State<_ClusterWrapperForGird> {
  final Logger _logger = Logger("__ClusterWrapperForGirdState");
  bool _isVisible = false;
  bool _isRemoving = false;

  Future<void> _removeClusterFromPerson() async {
    if (_isRemoving) {
      return;
    }
    setState(() {
      _isRemoving = true;
    });
    try {
      await PersonService.instance.removeClusterToPerson(
        personID: widget.person.remoteID,
        clusterID: widget.clusterID,
      );
      _logger.info(
        "Removed cluster ${widget.clusterID} from person ${widget.person.remoteID}",
      );
      Bus.instance.fire(PeopleChangedEvent());
      if (mounted) {
        widget.onClusterRemoved();
      }
    } catch (e, s) {
      _logger.severe("removing cluster from person", e, s);
    } finally {
      if (mounted) {
        setState(() {
          _isRemoving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final loadingColor = colorScheme.strokeMuted;
    return VisibilityDetector(
      key: ValueKey(widget.clusterID),
      onVisibilityChanged: (info) {
        if (!_isVisible && info.visibleFraction >= 0.01) {
          setState(() {
            _isVisible = true;
          });
        }
      },
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ClusterPage(
                widget.files,
                personID: widget.person,
                clusterID: widget.clusterID,
                showNamingBanner: false,
              ),
            ),
          );
        },
        child: _isVisible
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: [
                        FaceThumbnailSquircleClip(
                          child: widget.files.isNotEmpty
                              ? PersonFaceWidget(clusterID: widget.clusterID)
                              : const NoThumbnailWidget(addBorder: false),
                        ),
                        Positioned(
                          top: -5,
                          right: -5,
                          child: AbsorbPointer(
                            absorbing: _isRemoving,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _removeClusterFromPerson,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 150),
                                opacity: _isRemoving ? 0.5 : 1,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: colorScheme.warning500,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colorScheme.backgroundColour,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.remove,
                                    size: 12,
                                    color: colorScheme.backgroundColour,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.memoryCount(
                      count: widget.files.length,
                      formattedCount: NumberFormat().format(
                        widget.files.length,
                      ),
                    ),
                    style: getEnteTextTheme(context).small,
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : SizedBox(
                width: 100,
                height: 100,
                child: EnteLoadingWidget(color: loadingColor),
              ),
      ),
    );
  }
}
