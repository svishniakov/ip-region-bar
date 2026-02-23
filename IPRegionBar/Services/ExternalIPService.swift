import Foundation

actor ExternalIPService {
    static let shared = ExternalIPService()

    private let ipifyURL = URL(string: "https://api64.ipify.org?format=json")!
    private let amazonURL = URL(string: "https://checkip.amazonaws.com")!

    func fetchIP() async throws -> String {
        let provider = currentProvider

        switch provider {
        case .ipify:
            do {
                return try await fetchFromIpify()
            } catch {
                return try await fetchFromAmazon()
            }
        case .amazon:
            do {
                return try await fetchFromAmazon()
            } catch {
                return try await fetchFromIpify()
            }
        }
    }

    private var currentProvider: IPProvider {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.ipProvider) ?? AppDefaults.ipProvider
        return IPProvider(rawValue: raw) ?? .ipify
    }

    private var timeout: TimeInterval {
        let value = UserDefaults.standard.double(forKey: SettingsKey.requestTimeout)
        if value > 0 {
            return value
        }

        return AppDefaults.requestTimeout
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    private func fetchFromIpify() async throws -> String {
        let request = URLRequest(url: ipifyURL, timeoutInterval: timeout)
        let (data, response) = try await session().data(for: request)
        try validateHTTP(response)

        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let ip = json["ip"]?.trimmingCharacters(in: .whitespacesAndNewlines), isValidIP(ip) else {
            throw IPError.parseError
        }

        return ip
    }

    private func fetchFromAmazon() async throws -> String {
        let request = URLRequest(url: amazonURL, timeoutInterval: timeout)
        let (data, response) = try await session().data(for: request)
        try validateHTTP(response)

        guard
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            isValidIP(ip)
        else {
            throw IPError.parseError
        }

        return ip
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IPError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw IPError.httpStatus(httpResponse.statusCode)
        }
    }

    private func isValidIP(_ ip: String) -> Bool {
        if ip.contains(":") {
            return ip.range(of: "^[0-9a-fA-F:]+$", options: .regularExpression) != nil
        }

        guard ip.range(of: "^(?:\\d{1,3}\\.){3}\\d{1,3}$", options: .regularExpression) != nil else {
            return false
        }

        return ip.split(separator: ".").allSatisfy {
            guard let octet = Int($0) else { return false }
            return (0 ... 255).contains(octet)
        }
    }
}

enum IPError: LocalizedError {
    case parseError
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .parseError:
            return "Unable to parse IP response"
        case .invalidResponse:
            return "Invalid IP provider response"
        case let .httpStatus(code):
            return "IP provider returned HTTP \(code)"
        }
    }
}
