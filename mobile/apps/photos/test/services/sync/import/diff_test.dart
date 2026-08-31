import 'package:flutter_test/flutter_test.dart';
import 'package:photos/services/sync/import/diff.dart';
import 'package:photos/services/sync/import/model.dart';

void main() {
  test('reports a folder membership move as an ordinary mapping change', () {
    final result = getLocalAssetsDiffForTesting(
      assets: [
        LocalPathAsset(
          pathID: 'destination',
          pathName: 'Destination',
          localIDs: {'file-1'},
        ),
      ],
      existingIDs: {'file-1'},
      pathToLocalIDs: {
        'source': {'file-1'},
      },
    );

    expect(result.newPathToLocalIDs, {
      'destination': {'file-1'},
    });
    expect(result.deletePathToLocalIDs, isEmpty);
  });

  test('does not mutate the prior folder-membership snapshot', () {
    final previousMappings = <String, Set<String>>{
      'source': {'file-1', 'file-2'},
    };

    getLocalAssetsDiffForTesting(
      assets: [
        LocalPathAsset(
          pathID: 'source',
          pathName: 'Source',
          localIDs: {'file-1'},
        ),
      ],
      existingIDs: {'file-1'},
      pathToLocalIDs: previousMappings,
    );

    expect(previousMappings, {
      'source': {'file-1', 'file-2'},
    });
  });

  test('does not infer removals for folders absent from a valid scan', () {
    final result = getLocalAssetsDiffForTesting(
      assets: [
        LocalPathAsset(
          pathID: 'another-folder',
          pathName: 'Another folder',
          localIDs: {'file-2'},
        ),
      ],
      existingIDs: const {},
      pathToLocalIDs: {
        'source': {'file-1'},
      },
    );

    expect(result.deletePathToLocalIDs, isEmpty);
  });
}
