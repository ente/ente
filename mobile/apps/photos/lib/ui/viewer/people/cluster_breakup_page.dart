import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/people/cluster_page.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";

class ClusterBreakupPage extends StatefulWidget {
  final Map<String, List<EnteFile>> newClusterIDsToFiles;
  final String title;

  const ClusterBreakupPage(this.newClusterIDsToFiles, this.title, {super.key});

  @override
  State<ClusterBreakupPage> createState() => _ClusterBreakupPageState();
}

class _ClusterBreakupPageState extends State<ClusterBreakupPage> {
  @override
  Widget build(BuildContext context) {
    final keys = widget.newClusterIDsToFiles.keys.toList();
    final clusterIDsToFiles = widget.newClusterIDsToFiles;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView.builder(
        itemCount: widget.newClusterIDsToFiles.keys.length,
        itemBuilder: (context, index) {
          final String clusterID = keys[index];
          final List<EnteFile> files = clusterIDsToFiles[keys[index]]!;
          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ClusterPage(
                    files,
                    clusterID: clusterID,
                    appendTitle: "(Analysis)",
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: files.isNotEmpty
                        ? FaceThumbnailSquircleClip(
                            child: PersonFaceWidget(clusterID: clusterID),
                          )
                        : const FaceThumbnailSquircleClip(
                            child: NoThumbnailWidget(addBorder: false),
                          ),
                  ),
                  const SizedBox(
                    width: 8.0,
                  ), // Add some spacing between the thumbnail and the text
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            "${clusterIDsToFiles[keys[index]]!.length} photos",
                            style: getEnteTextTheme(context).body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
