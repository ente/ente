typedef HasInstallSource = Future<bool> Function();
typedef AutoAttributeSource = Future<void> Function({required bool isSignUp});
typedef AutoAttributePendingSource = Future<void> Function();

class InstallSourceHandler {
  const InstallSourceHandler({
    required this.hasInstallSource,
    required this.autoAttributeSource,
    required this.autoAttributePendingSource,
  });

  final HasInstallSource hasInstallSource;
  final AutoAttributeSource autoAttributeSource;
  final AutoAttributePendingSource autoAttributePendingSource;
}
