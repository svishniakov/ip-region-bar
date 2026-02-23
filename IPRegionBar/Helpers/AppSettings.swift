import Foundation

enum SettingsKey {
    static let displayMode = "displayMode"
    static let refreshInterval = "refreshInterval"
    static let launchAtLogin = "launchAtLogin"
    static let autoUpdateDB = "autoUpdateDB"
    static let dbLastUpdated = "dbLastUpdated"
    static let ipProvider = "ipProvider"
    static let requestTimeout = "requestTimeout"
    static let lastKnownIPInfo = "lastKnownIPInfo"
}

enum AppDefaults {
    static let displayMode = DisplayMode.flagCityCountry.rawValue
    static let refreshInterval: TimeInterval = 300
    static let launchAtLogin = false
    static let autoUpdateDB = true
    static let ipProvider = IPProvider.ipify.rawValue
    static let requestTimeout: TimeInterval = 5

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.displayMode: displayMode,
            SettingsKey.refreshInterval: refreshInterval,
            SettingsKey.launchAtLogin: launchAtLogin,
            SettingsKey.autoUpdateDB: autoUpdateDB,
            SettingsKey.ipProvider: ipProvider,
            SettingsKey.requestTimeout: requestTimeout,
        ])
    }
}
