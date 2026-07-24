import "dart:io";

import "package:ente_cast/src/cast/chromecast_device.dart";
import "package:ente_cast/src/cast/multicast_lock.dart";
import "package:flutter/services.dart";
import "package:multicast_dns/multicast_dns.dart";

const _serviceType = "_googlecast._tcp.local";
const _bonjourChannel = MethodChannel("io.ente.cast/discovery");

final class ChromecastDiscovery {
  const ChromecastDiscovery();

  Future<List<ChromecastDevice>> search({
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (Platform.isIOS) {
      return _searchWithBonjour(timeout);
    }
    return withMulticastLock(() => _searchWithMdns(timeout));
  }

  Future<List<ChromecastDevice>> _searchWithBonjour(Duration timeout) async {
    final results = await _bonjourChannel.invokeListMethod<Object?>(
      "searchDevices",
      {"timeoutMilliseconds": timeout.inMilliseconds},
    );
    if (results == null) {
      return [];
    }

    final devices = <ChromecastDevice>[];
    for (final result in results) {
      if (result is! Map) {
        continue;
      }
      final serviceName = result["serviceName"];
      final name = result["name"];
      final addresses = result["addresses"];
      final port = result["port"];
      if (serviceName is String &&
          name is String &&
          addresses is List &&
          port is int) {
        final validAddresses = addresses.whereType<String>().toList();
        if (validAddresses.isEmpty) {
          continue;
        }
        devices.add(
          ChromecastDevice(
            serviceName: serviceName,
            name: name,
            addresses: validAddresses,
            port: port,
          ),
        );
      }
    }
    return devices;
  }

  Future<List<ChromecastDevice>> _searchWithMdns(Duration timeout) async {
    final client = MDnsClient();
    final devices = <String, ChromecastDevice>{};
    final deadline = DateTime.now().add(timeout);

    await client.start();
    try {
      final pointerTasks = <Future<void>>[];
      await for (final pointer in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_serviceType),
        timeout: _remaining(deadline),
      )) {
        pointerTasks.add(_resolvePointer(client, pointer, deadline, devices));
      }
      await Future.wait(pointerTasks);
    } finally {
      client.stop();
    }

    return devices.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _resolvePointer(
    MDnsClient client,
    PtrResourceRecord pointer,
    DateTime deadline,
    Map<String, ChromecastDevice> devices,
  ) async {
    final serviceTasks = <Future<void>>[];
    await for (final service in client.lookup<SrvResourceRecord>(
      ResourceRecordQuery.service(pointer.domainName),
      timeout: _remaining(deadline),
    )) {
      serviceTasks.add(
        _resolveService(client, pointer, service, deadline, devices),
      );
    }
    await Future.wait(serviceTasks);
  }

  Future<void> _resolveService(
    MDnsClient client,
    PtrResourceRecord pointer,
    SrvResourceRecord service,
    DateTime deadline,
    Map<String, ChromecastDevice> devices,
  ) async {
    final attributesFuture = _readAttributes(
      client,
      pointer.domainName,
      deadline,
    );
    final addressesFuture = _resolveAddresses(client, service.target, deadline);
    final attributes = await attributesFuture;
    final addresses = await addressesFuture;
    devices[pointer.domainName] = ChromecastDevice(
      serviceName: pointer.domainName,
      name: _deviceName(pointer, attributes),
      addresses: addresses,
      port: service.port,
    );
  }

  Future<List<String>> _resolveAddresses(
    MDnsClient client,
    String target,
    DateTime deadline,
  ) async {
    final ipv4 = _lookupAddresses(
      client,
      ResourceRecordQuery.addressIPv4(target),
      deadline,
    );
    final ipv6 = _lookupAddresses(
      client,
      ResourceRecordQuery.addressIPv6(target),
      deadline,
    );
    final addresses = <String>{...await ipv4, ...await ipv6};
    if (addresses.isEmpty) {
      addresses.add(target);
    }
    return addresses.toList();
  }

  Future<Set<String>> _lookupAddresses(
    MDnsClient client,
    ResourceRecordQuery query,
    DateTime deadline,
  ) async {
    final addresses = <String>{};
    await for (final record in client.lookup<IPAddressResourceRecord>(
      query,
      timeout: _remaining(deadline),
    )) {
      addresses.add(record.address.address);
    }
    return addresses;
  }

  Future<Map<String, String>> _readAttributes(
    MDnsClient client,
    String serviceName,
    DateTime deadline,
  ) async {
    final attributes = <String, String>{};
    await for (final record in client.lookup<TxtResourceRecord>(
      ResourceRecordQuery.text(serviceName),
      timeout: _remaining(deadline),
    )) {
      for (final entry in record.text.split("\n")) {
        final separator = entry.indexOf("=");
        if (separator > 0) {
          attributes[entry.substring(0, separator)] = entry.substring(
            separator + 1,
          );
        }
      }
    }
    return attributes;
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  String _deviceName(
    PtrResourceRecord pointer,
    Map<String, String> attributes,
  ) {
    final friendlyName = attributes["fn"];
    if (friendlyName != null && friendlyName.isNotEmpty) {
      return friendlyName;
    }
    final model = attributes["md"];
    if (model != null && model.isNotEmpty) {
      return model;
    }
    return pointer.domainName
        .replaceAll(".$_serviceType", "")
        .replaceAll("-", " ")
        .trim();
  }
}
