import Darwin
import Flutter
import Foundation

public final class EnteCastPlugin: NSObject, FlutterPlugin {
    private var discoveries: [UUID: BonjourDiscovery] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.cast/discovery",
            binaryMessenger: registrar.messenger()
        )
        let instance = EnteCastPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "searchDevices" else {
            result(FlutterMethodNotImplemented)
            return
        }

        let arguments = call.arguments as? [String: Any]
        let timeoutMilliseconds =
            (arguments?["timeoutMilliseconds"] as? NSNumber)?.doubleValue ?? 7_000
        let discoveryID = UUID()
        let discovery = BonjourDiscovery(
            timeout: max(timeoutMilliseconds / 1_000, 0.5)
        ) { [weak self] outcome in
            self?.discoveries.removeValue(forKey: discoveryID)
            switch outcome {
            case let .success(devices):
                result(devices)
            case let .failure(error):
                result(
                    FlutterError(
                        code: "BONJOUR_DISCOVERY_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
            }
        }
        discoveries[discoveryID] = discovery
        discovery.start()
    }
}

private final class BonjourDiscovery: NSObject {
    typealias Device = [String: Any]

    private let browser = NetServiceBrowser()
    private let timeout: TimeInterval
    private let completion: (Result<[Device], Error>) -> Void
    private var services: [String: NetService] = [:]
    private var devices: [String: Device] = [:]
    private var timer: Timer?
    private var isFinished = false

    init(
        timeout: TimeInterval,
        completion: @escaping (Result<[Device], Error>) -> Void
    ) {
        self.timeout = timeout
        self.completion = completion
    }

    func start() {
        browser.delegate = self
        browser.searchForServices(
            ofType: "_googlecast._tcp.",
            inDomain: "local."
        )
        timer = Timer.scheduledTimer(
            withTimeInterval: timeout,
            repeats: false
        ) { [weak self] _ in
            self?.finish(.success(self?.sortedDevices ?? []))
        }
    }

    private var sortedDevices: [Device] {
        devices.values.sorted {
            ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "")
        }
    }

    private func finish(_ result: Result<[Device], Error>) {
        guard !isFinished else {
            return
        }
        isFinished = true
        timer?.invalidate()
        timer = nil
        browser.stop()
        for service in services.values {
            service.stop()
            service.delegate = nil
        }
        services.removeAll()
        completion(result)
    }

    private func serviceKey(_ service: NetService) -> String {
        "\(service.name).\(service.type)\(service.domain)"
    }

    private func deviceName(
        for service: NetService,
        attributes: [String: String]
    ) -> String {
        if let friendlyName = attributes["fn"], !friendlyName.isEmpty {
            return friendlyName
        }
        if let model = attributes["md"], !model.isEmpty {
            return model
        }
        return service.name.replacingOccurrences(of: "-", with: " ")
    }

    private func textAttributes(for service: NetService) -> [String: String] {
        guard let data = service.txtRecordData() else {
            return [:]
        }
        return NetService.dictionary(fromTXTRecord: data).reduce(into: [:]) {
            attributes,
            entry in
            if let value = String(data: entry.value, encoding: .utf8) {
                attributes[entry.key] = value
            }
        }
    }

    private func numericAddresses(for service: NetService) -> [String] {
        guard let serviceAddresses = service.addresses else {
            return []
        }
        var hosts: [String] = []
        var seenHosts = Set<String>()
        for family in [AF_INET, AF_INET6] {
            for address in serviceAddresses {
                let host = address.withUnsafeBytes { bytes -> String? in
                    guard let socketAddress = bytes
                        .bindMemory(to: sockaddr.self)
                        .baseAddress,
                        Int32(socketAddress.pointee.sa_family) == family else {
                        return nil
                    }
                    var buffer = [CChar](
                        repeating: 0,
                        count: Int(NI_MAXHOST)
                    )
                    guard getnameinfo(
                        socketAddress,
                        socklen_t(address.count),
                        &buffer,
                        socklen_t(buffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 else {
                        return nil
                    }
                    return String(cString: buffer)
                }
                if let host, seenHosts.insert(host).inserted {
                    hosts.append(host)
                }
            }
        }
        if hosts.isEmpty, let hostName = service.hostName {
            hosts.append(hostName)
        }
        return hosts
    }
}

extension BonjourDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let key = serviceKey(service)
        services[key] = service
        service.delegate = self
        service.resolve(withTimeout: min(timeout, 5))
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        let error = NSError(
            domain: "io.ente.cast.bonjour",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Unable to browse for Cast devices on the local network."
            ]
        )
        finish(.failure(error))
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let key = serviceKey(service)
        services.removeValue(forKey: key)
        devices.removeValue(forKey: key)
    }
}

extension BonjourDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = serviceKey(sender)
        let addresses = numericAddresses(for: sender)
        guard !addresses.isEmpty, sender.port > 0 else {
            return
        }
        let attributes = textAttributes(for: sender)
        devices[key] = [
            "serviceName": key,
            "name": deviceName(for: sender, attributes: attributes),
            "addresses": addresses,
            "port": sender.port,
        ]
    }
}
