import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/search/album_search_result.dart";
import "package:photos/models/search/device_album_search_result.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/services/search_query_service.dart";
import "package:photos/services/search_service.dart";

const _normalProviders = [
  #getHolidaySearchResults,
  #getFileTypeResults,
  #getCaptionAndNameResults,
  #getFileExtensionResults,
  #getLocationResults,
  #getAllFace,
  #getCollectionSearchResults,
  #getDeviceCollectionSearchResults,
  #getMonthSearchResults,
  #getDateResults,
  #getMagicSearchResults,
  #getContactSearchResults,
];

void main() {
  final context = _Context();

  test("empty and synchronous queries finish without losing batches", () async {
    final source = _SearchService(synchronous: true);
    final service = SearchQueryService(source);
    final empty = service.search(context, "");
    expect(await empty.toList(), [<SearchResult>[]]);
    expect(source.calls, isEmpty);
    expect(await service.search(context, "trip").length, 12);
  });

  test("ID queries preserve parsing and bypass other providers", () async {
    for (final scenario in [
      (
        query: "uploaded_ids:1, 2,-1,0,nope,2,3",
        provider: #getUploadedFileIDsSearchResults,
        ids: <Object>{1, 2, 3},
      ),
      (
        query: "local_ids:abc, def, ,abc",
        provider: #getLocalFileIDsSearchResults,
        ids: <Object>{"abc", "def"},
      ),
    ]) {
      final source = _SearchService();
      final stream = SearchQueryService(source).search(
        context,
        scenario.query,
        magicSearch: () => throw StateError("ID queries bypass magic search"),
      );
      final call = source.calls.single;
      expect(call.memberName, scenario.provider);
      expect(call.positionalArguments, [scenario.query, scenario.ids]);
      final result = _Result("matching file");
      source.generic[scenario.provider]!.single.complete([result]);
      expect(await stream.toList(), [
        <SearchResult>[result],
      ]);
    }
  });

  test("normal queries preserve providers and incremental results", () async {
    final source = _SearchService();
    final stream = SearchQueryService(source).search(context, "aLeX");
    expect(stream.isBroadcast, isTrue);
    expect(source.providers, _normalProviders);
    for (final call in source.calls) {
      if (call.memberName == #getAllFace) {
        expect(call.positionalArguments, [null]);
        expect(call.namedArguments, {
          #minClusterSize: 10,
          #fallbackMinClusterSize: null,
          #showIgnoredOnly: false,
          #includeEmptyPersons: false,
          #coverHeroTagPrefix: "people_search",
        });
      } else {
        expect(call.positionalArguments.last, "aLeX");
        if (call.positionalArguments.length == 2) {
          expect(call.positionalArguments.first, same(context));
        }
      }
    }
    final batches = <List<SearchResult>>[];
    final done = Completer<void>();
    stream.listen(batches.add, onDone: done.complete);
    final magic = _Result("magic");
    source.generic[#getMagicSearchResults]!.single.complete([magic]);
    await Future<void>.delayed(Duration.zero);
    expect(batches, [
      <SearchResult>[magic],
    ]);
    final alex = _Result("Alex");
    final alexander = _Result("Alexander");
    source.generic[#getAllFace]!.single.complete([
      alex,
      _Result("Sam"),
      alexander,
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(batches.last, [alex, alexander]);
    source.generic[#getCaptionAndNameResults]!.single.completeError(
      const FormatException("invalid regex"),
    );
    source.completeAll();
    await done.future;
    expect(batches, hasLength(12));
    expect(batches.expand((batch) => batch), [magic, alex, alexander]);
  });

  test("other providers stream while custom magic search waits", () async {
    final source = _SearchService();
    final magicResults = Completer<List<SearchResult>>();
    final stream = SearchQueryService(
      source,
    ).search(context, "trip", magicSearch: () => magicResults.future);
    expect(
      source.providers,
      _normalProviders.where((provider) => provider != #getMagicSearchResults),
    );
    final batches = <List<SearchResult>>[];
    final done = Completer<void>();
    stream.listen(batches.add, onDone: done.complete);
    final caption = _Result("caption");
    source.generic[#getCaptionAndNameResults]!.single.complete([caption]);
    await Future<void>.delayed(Duration.zero);
    expect(batches, [
      <SearchResult>[caption],
    ]);

    source.completeAll();
    await Future<void>.delayed(Duration.zero);
    expect(batches, hasLength(11));
    expect(done.isCompleted, isFalse);

    final magic = _Result("magic");
    magicResults.complete([magic]);
    await done.future;
    expect(batches, hasLength(12));
    expect(batches.last, [magic]);
  });

  test("year and device album queries use their providers", () async {
    for (final query in ["2024", "1899", "9999", "202", "word"]) {
      final source = _SearchService();
      final stream = SearchQueryService(source).search(context, query);
      expect(source.providers, [
        if (query == "2024") #getYearSearchResults,
        ..._normalProviders,
      ]);
      source.completeAll();
      expect(await stream.length, query == "2024" ? 13 : 12);
    }
    final source = _SearchService();
    final folder = _Result("device folder");
    final stream = SearchQueryService(
      source,
    ).search(context, "trip", deviceAlbumSearch: () async => [folder]);
    final expected = [..._normalProviders]
      ..remove(#getDeviceCollectionSearchResults);
    expect(source.providers, expected);
    source.completeAll();
    expect(await stream.expand((batch) => batch).toList(), [folder]);
  });

  test("buffered results survive late listeners and cancellation", () async {
    final source = _SearchService();
    final service = SearchQueryService(source);
    final early = service.search(context, "first");
    source.completeAll();
    await Future<void>.delayed(Duration.zero);
    expect(await early.length, 12);

    final canceled = service.search(context, "second");
    final canceledBatches = <List<SearchResult>>[];
    final subscription = canceled.listen(canceledBatches.add);
    final current = service.search(context, "third").toList();
    await subscription.cancel();
    source.generic[#getMagicSearchResults]![1].completeError(
      StateError("canceled request failed"),
    );
    final result = _Result("current result");
    source.generic[#getMagicSearchResults]![2].complete([result]);
    source.completeAll();
    final batches = await current;
    expect(batches, hasLength(12));
    expect(batches.expand((batch) => batch), [result]);
    expect(canceledBatches, isEmpty);
  });
}

class _Result extends Fake implements GenericSearchResult {
  _Result(this.value);

  final String value;

  @override
  String name() => value;
}

class _Context extends Fake implements BuildContext {}

class _SearchService implements SearchService {
  _SearchService({this.synchronous = false});

  final bool synchronous;
  final calls = <Invocation>[];
  final generic = <Symbol, List<Completer<List<GenericSearchResult>>>>{};
  final _complete = <VoidCallback>[];

  Iterable<Symbol> get providers => calls.map((call) => call.memberName);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    if (invocation.memberName == #getCollectionSearchResults) {
      return _response<AlbumSearchResult>();
    }
    if (invocation.memberName == #getDeviceCollectionSearchResults) {
      return _response<DeviceAlbumSearchResult>();
    }
    return _response<GenericSearchResult>(
      generic.putIfAbsent(invocation.memberName, () => []),
    );
  }

  Future<List<T>> _response<T extends SearchResult>([
    List<Completer<List<T>>>? pending,
  ]) {
    if (synchronous) return SynchronousFuture<List<T>>([]);
    final completer = Completer<List<T>>();
    pending?.add(completer);
    _complete.add(() {
      if (!completer.isCompleted) completer.complete([]);
    });
    return completer.future;
  }

  void completeAll() {
    for (final complete in _complete) {
      complete();
    }
  }
}
