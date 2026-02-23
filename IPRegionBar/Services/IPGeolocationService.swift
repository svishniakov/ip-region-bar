import Foundation
import MMDB

actor IPGeolocationService {
    static let shared = IPGeolocationService()

    private var reader: MMDB?

    func loadDatabase() async throws {
        let dbURL = await GeoLiteDatabase.shared.databaseURL
        guard let loaded = MMDB(dbURL.path) else {
            throw GeoError.databaseNotLoaded
        }
        reader = loaded
    }

    func reloadDatabaseIfNeeded() async throws {
        if reader == nil {
            try await loadDatabase()
        }
    }

    func lookup(ip: String) throws -> IPInfo {
        guard let reader else {
            throw GeoError.databaseNotLoaded
        }

        guard let record = reader.lookup(ip: ip) else {
            throw GeoError.recordNotFound
        }
        let countryCode = record.value(forPath: "country.iso_code") ?? ""
        let countryName = record.value(forPath: "country.names.en") ?? "Unknown"
        let city = record.value(forPath: "city.names.en") ?? ""
        let region = record.value(forPath: "subdivisions.0.names.en") ?? ""
        let timezone = record.value(forPath: "location.time_zone") ?? ""

        return IPInfo(
            ip: ip,
            countryCode: countryCode,
            countryName: countryName,
            city: city,
            region: region,
            timezone: timezone
        )
    }
}

enum GeoError: LocalizedError {
    case databaseNotLoaded
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .databaseNotLoaded:
            return "Geo database is not loaded"
        case .recordNotFound:
            return "No geolocation data found for IP"
        }
    }
}

private extension NSDictionary {
    func value(forPath path: String) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = self

        for part in parts {
            if let index = Int(part), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
                continue
            }

            if let dictionary = current as? [String: Any], let next = dictionary[part] {
                current = next
                continue
            }

            if let dictionary = current as? NSDictionary, let next = dictionary[part] {
                current = next
                continue
            }

            return nil
        }

        return current as? String
    }
}
