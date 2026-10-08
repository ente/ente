// Tab events keep stable IDs: Search remains 3 when Feed is hidden.
List<int> homeTabIndices({required bool showFeed}) => [
  0,
  1,
  if (showFeed) 2,
  3,
];
