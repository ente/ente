final class ChromecastDevice {
  final String serviceName;
  final String name;
  final List<String> addresses;
  final int port;

  ChromecastDevice({
    required this.serviceName,
    required this.name,
    required Iterable<String> addresses,
    required this.port,
  }) : addresses = List.unmodifiable(addresses);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChromecastDevice && other.serviceName == serviceName;

  @override
  int get hashCode => serviceName.hashCode;
}
