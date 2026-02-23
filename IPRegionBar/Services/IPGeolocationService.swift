import Foundation
import MMDB

actor IPGeolocationService {
    static let shared = IPGeolocationService()

    private var reader: MMDB?

    func loadDatabase() async throws {
        guard let dbURL = await DBIPDatabase.shared.activeDatabaseURL else {
            throw GeoError.databaseNotLoaded
        }
        guard let loaded = MMDB(dbURL.path) else {
            throw GeoError.databaseNotLoaded
        }
        reader = loaded
    }

    func reloadDatabase() async throws {
        reader = nil
        try await loadDatabase()
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

        var countryCode = record.firstNonEmptyValue(forPaths: [
            "country.iso_code",
            "country.code",
            "country.country_code",
            "countryCode",
            "country_code",
            "registered_country.iso_code",
            "registered_country.code",
        ]) ?? ""

        var countryName = record.firstNonEmptyValue(forPaths: [
            "country.names.en",
            "country.name",
            "country_name",
            "registered_country.names.en",
            "registered_country.name",
        ]) ?? ""

        if countryCode.isEmpty, let countryValue = record.value(forPath: "country"), countryValue.count == 2 {
            countryCode = countryValue
        }

        if countryName.isEmpty, let countryValue = record.value(forPath: "country"), countryValue.count > 2 {
            countryName = countryValue
        }

        countryCode = countryCode.uppercased()

        if countryName.isEmpty, countryCode.count == 2 {
            let locale = Locale(identifier: "en_US_POSIX")
            countryName = locale.localizedString(forRegionCode: countryCode) ?? ""
        }

        if countryName.isEmpty {
            countryName = "Unknown"
        }

        let city = record.firstNonEmptyValue(forPaths: [
            "city.names.en",
            "city.name",
            "city",
            "city_name",
        ]) ?? ""

        let region = record.firstNonEmptyValue(forPaths: [
            "subdivisions.0.names.en",
            "subdivisions.0.name",
            "stateProv",
            "state_prov",
            "region",
        ]) ?? ""

        let timezone = record.firstNonEmptyValue(forPaths: [
            "location.time_zone",
            "time_zone",
            "timezone",
        ]) ?? ""

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
    func firstNonEmptyValue(forPaths paths: [String]) -> String? {
        for path in paths {
            if let value = value(forPath: path), !value.isEmpty {
                return value
            }
        }
        return nil
    }

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

        if let value = current as? String {
            return value
        }
        if let value = current as? NSNumber {
            return value.stringValue
        }
        return nil
    }
}
