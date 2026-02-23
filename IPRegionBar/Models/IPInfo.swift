import Foundation

struct IPInfo: Codable {
    let ip: String
    let countryCode: String
    let countryName: String
    let city: String
    let region: String
    let timezone: String

    var flagEmoji: String {
        FlagEmoji.from(countryCode: countryCode)
    }

    var title: String {
        if city.isEmpty {
            return "\(flagEmoji) \(countryName)"
        }

        return "\(flagEmoji) \(city), \(countryName)"
    }
}
