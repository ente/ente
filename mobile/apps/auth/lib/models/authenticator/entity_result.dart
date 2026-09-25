class EntityResult {
  final int generatedID;
  final String rawData;
  final bool hasSynced;
  final int createdAt;

  EntityResult(
    this.generatedID,
    this.rawData,
    this.hasSynced,
    this.createdAt,
  );
}
