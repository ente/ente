import Foundation

enum APIEndpoint {
    static let production = URL(string: "https://api.ente.com")!

    static var current: URL {
        UserDefaults.standard.url(forKey: "endpoint") ?? production
    }

    static var isProduction: Bool {
        current == production
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: "endpoint")
    }

    static func update(_ value: String) async throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { throw EndpointError.invalidURL }
        components.scheme = "https"
        components.path = ""
        guard let url = components.url else { throw EndpointError.invalidURL }

        var request = URLRequest(url: url.appendingPathComponent("ping"))
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder().decode(Ping.self, from: data).message) == "pong"
        else { throw EndpointError.invalidServer }

        url == production ? reset() : UserDefaults.standard.set(url, forKey: "endpoint")
    }

    private struct Ping: Decodable { let message: String }

    private enum EndpointError: String, LocalizedError {
        case invalidURL = "Enter a valid HTTPS API URL"
        case invalidServer = "The URL is not an Ente API server"
        var errorDescription: String? {
            rawValue
        }
    }
}
