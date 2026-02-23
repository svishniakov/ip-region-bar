import Foundation
import MMDB

actor DBIPDatabase {
    static let shared = DBIPDatabase()

    private let fileManager = FileManager.default
    private let updateInterval: TimeInterval = 30 * 24 * 3600
    private let databaseFilename = "dbip-city-lite.mmdb"
    private let metadataFilename = "dbip-city-lite.meta"

    private var transientStatus: DatabaseStatus?

    var bundleDBURL: URL {
        guard let url = resourceURL(for: "dbip-city-lite", withExtension: "mmdb") else {
            fatalError("Bundled DB-IP database is missing")
        }
        return url
    }

    var userDBURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPRegionBar", isDirectory: true)
            .appendingPathComponent(databaseFilename)
    }

    var activeDatabaseURL: URL {
        fileManager.fileExists(atPath: userDBURL.path) ? userDBURL : bundleDBURL
    }

    func status() -> DatabaseStatus {
        if let transientStatus {
            return transientStatus
        }

        if fileManager.fileExists(atPath: userDBURL.path), let month = UserDefaults.standard.string(forKey: SettingsKey.dbMonth), !month.isEmpty {
            return .updated(month: month)
        }

        return .bundled(month: bundledMonth())
    }

    func resolveActiveMonth() -> String {
        if fileManager.fileExists(atPath: userDBURL.path),
           let month = UserDefaults.standard.string(forKey: SettingsKey.dbMonth),
           !month.isEmpty {
            return month
        }

        return bundledMonth()
    }

    func updateIfNeeded() async -> Bool {
        guard isAutoUpdateEnabled() else {
            return false
        }

        guard shouldUpdate() else {
            return false
        }

        return await performUpdate(for: currentYearMonth())
    }

    func updateNow() async -> Bool {
        await performUpdate(for: currentYearMonth())
    }

    func needsManualUpdateReminder() -> Bool {
        guard isAutoUpdateEnabled() == false else {
            return false
        }

        guard let referenceDate = reminderReferenceDate() else {
            return false
        }

        return Date().timeIntervalSince(referenceDate) > updateInterval
    }

    private func performUpdate(for yearMonth: String) async -> Bool {
        transientStatus = .updating

        do {
            let downloadURL = try downloadURL(for: yearMonth)
            let tempGZ = try await downloadDatabaseArchive(from: downloadURL, yearMonth: yearMonth)
            let tempMMDB = try decompressArchive(tempGZ)
            try validateDatabase(at: tempMMDB)
            try installDatabase(from: tempMMDB)

            UserDefaults.standard.set(Date(), forKey: SettingsKey.dbLastUpdated)
            UserDefaults.standard.set(yearMonth, forKey: SettingsKey.dbMonth)
            transientStatus = nil
            return true
        } catch {
            transientStatus = .updateFailed
            return false
        }
    }

    private func downloadURL(for yearMonth: String) throws -> URL {
        guard let url = URL(string: "https://download.db-ip.com/free/dbip-city-lite-\(yearMonth).mmdb.gz") else {
            throw DBIPDatabaseError.invalidURL
        }

        return url
    }

    private func downloadDatabaseArchive(from url: URL, yearMonth: String) async throws -> URL {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DBIPDatabaseError.httpFailed
        }

        let destination = fileManager.temporaryDirectory.appendingPathComponent("dbip-city-lite-\(yearMonth)-\(UUID().uuidString).mmdb.gz")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func decompressArchive(_ gzURL: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-f", gzURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DBIPDatabaseError.decompressionFailed
        }

        return gzURL.deletingPathExtension()
    }

    private func validateDatabase(at fileURL: URL) throws {
        guard MMDB(fileURL.path) != nil else {
            throw DBIPDatabaseError.validationFailed
        }
    }

    private func installDatabase(from sourceURL: URL) throws {
        let parent = userDBURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: userDBURL.path) {
            _ = try fileManager.replaceItemAt(
                userDBURL,
                withItemAt: sourceURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
            return
        }

        try fileManager.moveItem(at: sourceURL, to: userDBURL)
    }

    private func shouldUpdate() -> Bool {
        guard let lastUpdate = UserDefaults.standard.object(forKey: SettingsKey.dbLastUpdated) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastUpdate) > updateInterval
    }

    private func bundledMonth() -> String {
        guard let url = resourceURL(for: metadataFilename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(DBIPMetadata.self, from: data),
              !metadata.month.isEmpty
        else {
            return "unknown"
        }

        return metadata.month
    }

    private func currentYearMonth() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func reminderReferenceDate() -> Date? {
        if let lastUpdate = UserDefaults.standard.object(forKey: SettingsKey.dbLastUpdated) as? Date {
            return lastUpdate
        }

        let month = resolveActiveMonth()
        guard month != "unknown" else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.date(from: month)
    }

    private func isAutoUpdateEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKey.autoUpdateDB) == nil {
            return AppDefaults.autoUpdateDB
        }
        return defaults.bool(forKey: SettingsKey.autoUpdateDB)
    }

    private func resourceURL(for name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

#if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }
#endif

        return nil
    }
}

private struct DBIPMetadata: Codable {
    let month: String
    let source: String
}

enum DBIPDatabaseError: Error {
    case invalidURL
    case httpFailed
    case decompressionFailed
    case validationFailed
}
