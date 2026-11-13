import Darwin
import Flutter
import Foundation
import Security

public final class EnteCastPlugin: NSObject, FlutterPlugin {
    private var discoveries: [UUID: BonjourDiscovery] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.cast/discovery",
            binaryMessenger: registrar.messenger()
        )
        let authChannel = FlutterMethodChannel(
            name: "io.ente.cast/auth",
            binaryMessenger: registrar.messenger()
        )
        let instance = EnteCastPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addMethodCallDelegate(instance, channel: authChannel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "searchDevices":
            searchDevices(call, result: result)
        case "verifyDeviceCredentials":
            do {
                try verifyDeviceCredentials(call)
                result(nil)
            } catch {
                result(
                    FlutterError(
                        code: "CAST_AUTH_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func searchDevices(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
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

    private func verifyDeviceCredentials(_ call: FlutterMethodCall) throws {
        guard let arguments = call.arguments as? [String: Any] else {
            throw CastAuthError("Missing authentication arguments")
        }
        let leafData = try bytes("clientAuthCertificate", in: arguments)
        let intermediateData = try byteArrays(
            "intermediateCertificates",
            in: arguments
        )
        let rootData = try byteArrays("trustAnchors", in: arguments)
        guard !rootData.isEmpty else {
            throw CastAuthError("Cast trust store is empty")
        }

        let roots = try rootData.map(certificate)
        let chainData = [leafData] + intermediateData.filter { candidate in
            !rootData.contains(candidate)
        }
        let certificates = try chainData.map(certificate)
        var trust: SecTrust?
        let createStatus = SecTrustCreateWithCertificates(
            certificates as CFArray,
            SecPolicyCreateSSL(false, nil),
            &trust
        )
        guard createStatus == errSecSuccess, let trust else {
            throw CastAuthError("Unable to create Cast certificate trust")
        }
        guard SecTrustSetAnchorCertificates(trust, roots as CFArray)
            == errSecSuccess else {
            throw CastAuthError("Unable to configure Cast trust anchors")
        }
        guard SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
            throw CastAuthError("Unable to restrict Cast trust anchors")
        }
        guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else {
            throw CastAuthError("Unable to disable certificate network fetches")
        }
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else {
            let message = trustError.map { CFErrorCopyDescription($0) as String }
                ?? "Cast certificate chain is untrusted"
            throw CastAuthError(message)
        }

        guard let publicKey = SecTrustCopyKey(trust) else {
            throw CastAuthError("Cast device certificate has no public key")
        }
        let hashAlgorithm =
            (arguments["hashAlgorithm"] as? NSNumber)?.intValue
        let algorithm: SecKeyAlgorithm
        switch hashAlgorithm {
        case 0:
            algorithm = .rsaSignatureMessagePKCS1v15SHA1
        case 1:
            algorithm = .rsaSignatureMessagePKCS1v15SHA256
        default:
            throw CastAuthError("Unsupported Cast signature hash algorithm")
        }
        guard SecKeyIsAlgorithmSupported(publicKey, .verify, algorithm) else {
            throw CastAuthError("Cast device authentication key is not RSA")
        }
        let keyAttributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any]
        let keySize = keyAttributes?[kSecAttrKeySizeInBits] as? NSNumber
        guard let keySize, keySize.intValue >= 2_048 else {
            throw CastAuthError("Cast device authentication key is too small")
        }

        let signature = try bytes("signature", in: arguments)
        let signatureInput = try bytes("signatureInput", in: arguments)
        var signatureError: Unmanaged<CFError>?
        guard SecKeyVerifySignature(
            publicKey,
            algorithm,
            signatureInput as CFData,
            signature as CFData,
            &signatureError
        ) else {
            let message = signatureError
                .map { CFErrorCopyDescription($0.takeRetainedValue()) as String }
                ?? "Cast device signature is invalid"
            throw CastAuthError(message)
        }
    }

    private func certificate(_ data: Data) throws -> SecCertificate {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData)
        else {
            throw CastAuthError("Unable to parse Cast certificate")
        }
        return certificate
    }

    private func bytes(
        _ name: String,
        in arguments: [String: Any]
    ) throws -> Data {
        guard let value = arguments[name] as? FlutterStandardTypedData else {
            throw CastAuthError("Missing \(name)")
        }
        return value.data
    }

    private func byteArrays(
        _ name: String,
        in arguments: [String: Any]
    ) throws -> [Data] {
        guard let values = arguments[name] as? [Any] else {
            throw CastAuthError("Missing \(name)")
        }
        return try values.map { value in
            guard let bytes = value as? FlutterStandardTypedData else {
                throw CastAuthError("\(name) contains a non-byte value")
            }
            return bytes.data
        }
    }
}

private struct CastAuthError: LocalizedError {
    init(_ message: String) {
        self.message = message
    }

    let message: String

    var errorDescription: String? {
        message
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
