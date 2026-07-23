extension ListExtension<E> on List<E> {
  List<List<E>> chunks(int chunkSize) {
    final List<List<E>> result = <List<E>>[];
    for (var i = 0; i < length; i += chunkSize) {
      result.add(sublist(i, i + chunkSize > length ? length : i + chunkSize));
    }
    return result;
  }

  // splitMatch, based on the matchFunction, split the input list in two
  // lists. result.matched contains items which matched and result.unmatched
  // contains remaining items.
  ListMatch<E> splitMatch(bool Function(E e) matchFunction) {
    final listMatch = ListMatch<E>();
    for (final element in this) {
      if (matchFunction(element)) {
        listMatch.matched.add(element);
      } else {
        listMatch.unmatched.add(element);
      }
    }
    return listMatch;
  }

  Iterable<E> interleave(E separator) sync* {
    for (int i = 0; i < length; i++) {
      yield this[i];
      if (i < length) yield separator;
    }
  }
}

class ListMatch<T> {
  List<T> matched = <T>[];
  List<T> unmatched = <T>[];
}
