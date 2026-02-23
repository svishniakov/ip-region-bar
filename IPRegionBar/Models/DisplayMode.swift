import Foundation

enum DisplayMode: String, CaseIterable {
    case flagCityCountry
    case flagCountry
    case flagOnly
    case ipOnly

    var title: String {
        switch self {
        case .flagCityCountry:
            return "Flag + City + Country"
        case .flagCountry:
            return "Flag + Country"
        case .flagOnly:
            return "Flag Only"
        case .ipOnly:
            return "IP Only"
        }
    }

    static var current: DisplayMode {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.displayMode) ?? AppDefaults.displayMode
        return DisplayMode(rawValue: raw) ?? .flagCityCountry
    }
}

enum RefreshIntervalOption: CaseIterable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case manual

    var seconds: TimeInterval {
        switch self {
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 300
        case .fifteenMinutes:
            return 900
        case .thirtyMinutes:
            return 1800
        case .manual:
            return 0
        }
    }

    var title: String {
        switch self {
        case .oneMinute:
            return "1 minute"
        case .fiveMinutes:
            return "5 minutes"
        case .fifteenMinutes:
            return "15 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        case .manual:
            return "Manual"
        }
    }

    static func from(seconds: TimeInterval) -> RefreshIntervalOption {
        RefreshIntervalOption.allCases.first { abs($0.seconds - seconds) < 1 } ?? .fiveMinutes
    }
}

enum IPProvider: String, CaseIterable {
    case ipify
    case amazon

    var title: String {
        switch self {
        case .ipify:
            return "ipify.org"
        case .amazon:
            return "checkip.amazonaws.com"
        }
    }
}
