import Foundation

// The Ente server ("museum") this app talks to.
//
// Mirrors the developer settings in the Ente mobile and web apps: production by
// default, with a self-hosted instance settable at runtime rather than needing
// a custom build. The preference key matches the mobile app's.
enum EndpointConfig {
    static let productionAPIOrigin = "https://api.ente.com"
    static let productionDownloadOrigin = "https://cast-albums.ente.com"

    private static let preferencesKey = "endpoint"

    // The self-hosted origin, or nil when pointed at production.
    static var customAPIOrigin: String? {
        guard let value = UserDefaults.standard.string(forKey: preferencesKey),
              !value.isEmpty,
              value != productionAPIOrigin
        else { return nil }
        return value
    }

    static var apiOrigin: String {
        return customAPIOrigin ?? productionAPIOrigin
    }

    static var isSelfHosted: Bool {
        return customAPIOrigin != nil
    }

    static func setAPIOrigin(_ origin: String?) {
        if let origin = origin, !origin.isEmpty {
            UserDefaults.standard.set(origin, forKey: preferencesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferencesKey)
        }
    }

    // Trims whitespace and trailing slashes, so that "https://ente.example.org/"
    // and "https://ente.example.org" behave the same.
    static func normalize(_ input: String) -> String {
        var origin = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while origin.hasSuffix("/") {
            origin.removeLast()
        }
        return origin
    }

    // Museum's preferred route, which answers with the object storage URL to
    // fetch rather than with the encrypted bytes. Nil for production, whose
    // Cloudflare worker has no such indirection.
    static func fileDownloadV3URL(fileID: Int) -> URL? {
        guard let origin = customAPIOrigin else { return nil }
        return URL(string: "\(origin)/cast/files/download/v3/\(fileID)")
    }

    // Where the encrypted bytes themselves are fetched from.
    //
    // Production goes through a Cloudflare worker that takes the file ID as a
    // query parameter. Museum has no such route, so a self-hosted instance uses
    // the path parameter form instead - the same split the web cast app makes
    // between cast-albums and fetchCastFile(). On museum this is the pre-v3
    // route, kept as the fallback for deployments without fileDownloadV3URL.
    static func fileDownloadURL(fileID: Int) -> URL? {
        if let origin = customAPIOrigin {
            return URL(string: "\(origin)/cast/files/download/\(fileID)")
        }
        return URL(string: "\(productionDownloadOrigin)/download/?fileID=\(fileID)")
    }

    enum ValidationError: LocalizedError {
        case invalidURL
        case insecureURL
        case unreachable(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Enter a full URL, including https://"
            case .insecureURL:
                return "Only https:// endpoints are supported"
            case .unreachable(let detail):
                return detail
            }
        }
    }

    // Validates like the mobile app does: GET {origin}/ping must answer
    // {"message": "pong"}.
    //
    // Unlike the mobile app this rejects http, because the target ships no App
    // Transport Security exception. Accepting a cleartext endpoint would store
    // one that every later request fails on, so it is better refused here with
    // an explanation than accepted and then permanently unreachable.
    static func validate(_ origin: String) async throws {
        guard let url = URL(string: origin),
              let scheme = url.scheme?.lowercased(),
              url.host != nil,
              let pingURL = URL(string: "\(origin)/ping")
        else {
            throw ValidationError.invalidURL
        }

        guard scheme == "https" else {
            throw ValidationError.insecureURL
        }

        var request = URLRequest(url: pingURL)
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ValidationError.unreachable(
                "Could not reach \(origin): \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationError.unreachable("Invalid response from \(origin)")
        }

        guard httpResponse.statusCode == 200 else {
            throw ValidationError.unreachable(
                "\(origin)/ping returned HTTP \(httpResponse.statusCode)")
        }

        let ping = try? JSONDecoder().decode(PingResponse.self, from: data)
        guard ping?.message == "pong" else {
            throw ValidationError.unreachable("\(origin) is not an Ente server")
        }
    }

    private struct PingResponse: Decodable {
        let message: String
    }
}
