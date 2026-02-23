import Foundation
import MMDB

actor DBIPDatabase {
    typealias DownloadArchive = (URLRequest) async throws -> (URL, URLResponse)
    typealias DecompressArchive = (URL) throws -> URL
    typealias ValidateDatabase = (URL) -> Bool
    typealias NowProvider = () -> Date

    static let shared = DBIPDatabase()

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let appSupportRoot: URL
    private let updateInterval: TimeInterval = 30 * 24 * 3600
    private let databaseFilename = "dbip-city-lite.mmdb"
    private let downloadArchive: DownloadArchive
    private let decompressArchiveFn: DecompressArchive
    private let validateDatabaseFn: ValidateDatabase
    private let nowProvider: NowProvider

    private var transientStatus: DatabaseStatus?

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        appSupportRoot: URL? = nil,
        nowProvider: @escaping NowProvider = Date.init,
        downloadArchive: @escaping DownloadArchive = { request in
            try await URLSession.shared.download(for: request)
        },
        decompressArchive: @escaping DecompressArchive = DBIPDatabase.defaultDecompressArchive,
        validateDatabase: @escaping ValidateDatabase = DBIPDatabase.defaultValidateDatabase
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.appSupportRoot = appSupportRoot ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.nowProvider = nowProvider
        self.downloadArchive = downloadArchive
        self.decompressArchiveFn = decompressArchive
        self.validateDatabaseFn = validateDatabase
    }

    var userDBURL: URL {
        appSupportRoot
            .appendingPathComponent("IPRegionBar", isDirectory: true)
            .appendingPathComponent(databaseFilename)
    }

    var activeDatabaseURL: URL? {
        fileManager.fileExists(atPath: userDBURL.path) ? userDBURL : nil
    }

    func isInstalled() -> Bool {
        fileManager.fileExists(atPath: userDBURL.path)
    }

    func status() -> DatabaseStatus {
        if let transientStatus {
            return transientStatus
        }

        guard isInstalled() else {
            return .notInstalled
        }

        return .installed(month: resolveInstalledMonth())
    }

    func resolveActiveMonth() -> String {
        guard isInstalled() else {
            return "unknown"
        }
        return resolveInstalledMonth()
    }

    func installNow() async -> Bool {
        await performUpdate()
    }

    func updateNow() async -> Bool {
        await performUpdate()
    }

    func updateIfNeeded() async -> Bool {
        guard isAutoUpdateEnabled() else {
            return false
        }

        guard isUserInstalled() else {
            return false
        }

        guard isInstalled() else {
            return false
        }

        guard shouldUpdate() else {
            return false
        }

        return await performUpdate()
    }

    func needsManualUpdateReminder() -> Bool {
        guard isAutoUpdateEnabled() == false else {
            return false
        }

        guard isInstalled() else {
            return false
        }

        guard let referenceDate = reminderReferenceDate() else {
            return false
        }

        return nowProvider().timeIntervalSince(referenceDate) > updateInterval
    }

    private func performUpdate() async -> Bool {
        transientStatus = .updating

        do {
            let installedMonth = try await downloadAndInstall(usingCandidateMonths: candidateMonths())
            defaults.set(nowProvider(), forKey: SettingsKey.dbLastUpdated)
            defaults.set(installedMonth, forKey: SettingsKey.dbMonth)
            defaults.set(true, forKey: SettingsKey.dbInstalledByUser)
            transientStatus = nil
            return true
        } catch {
            transientStatus = .updateFailed
            return false
        }
    }

    private func downloadAndInstall(usingCandidateMonths months: [String]) async throws -> String {
        for month in months {
            do {
                let downloadURL = try downloadURL(for: month)
                let tempGZ = try await downloadDatabaseArchive(from: downloadURL, yearMonth: month)
                let tempMMDB = try decompressArchive(tempGZ)
                try validateDatabase(at: tempMMDB)
                try installDatabase(from: tempMMDB)
                return month
            } catch DBIPDatabaseError.httpFailed(status: 404) {
                continue
            }
        }

        throw DBIPDatabaseError.notFoundForCandidateMonths
    }

    private func downloadURL(for yearMonth: String) throws -> URL {
        guard let url = URL(string: "https://download.db-ip.com/free/dbip-city-lite-\(yearMonth).mmdb.gz") else {
            throw DBIPDatabaseError.invalidURL
        }

        return url
    }

    private func downloadDatabaseArchive(from url: URL, yearMonth: String) async throws -> URL {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (tempURL, response) = try await downloadArchive(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DBIPDatabaseError.httpFailed(status: -1)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DBIPDatabaseError.httpFailed(status: httpResponse.statusCode)
        }

        let destination = fileManager.temporaryDirectory
            .appendingPathComponent("dbip-city-lite-\(yearMonth)-\(UUID().uuidString).mmdb.gz")

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func decompressArchive(_ gzURL: URL) throws -> URL {
        try decompressArchiveFn(gzURL)
    }

    private func validateDatabase(at fileURL: URL) throws {
        guard validateDatabaseFn(fileURL) else {
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
        guard let lastUpdate = defaults.object(forKey: SettingsKey.dbLastUpdated) as? Date else {
            return true
        }

        return nowProvider().timeIntervalSince(lastUpdate) > updateInterval
    }

    private func reminderReferenceDate() -> Date? {
        if let lastUpdate = defaults.object(forKey: SettingsKey.dbLastUpdated) as? Date {
            return lastUpdate
        }

        let month = resolveInstalledMonth()
        guard month != "unknown" else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.date(from: month)
    }

    private func resolveInstalledMonth() -> String {
        guard let month = defaults.string(forKey: SettingsKey.dbMonth), !month.isEmpty else {
            return "unknown"
        }
        return month
    }

    private func isAutoUpdateEnabled() -> Bool {
        if defaults.object(forKey: SettingsKey.autoUpdateDB) == nil {
            return AppDefaults.autoUpdateDB
        }
        return defaults.bool(forKey: SettingsKey.autoUpdateDB)
    }

    private func isUserInstalled() -> Bool {
        defaults.bool(forKey: SettingsKey.dbInstalledByUser)
    }

    private func candidateMonths() -> [String] {
        let current = currentYearMonth()
        let previous = previousYearMonth()

        if previous == current {
            return [current]
        }

        return [current, previous]
    }

    private func currentYearMonth() -> String {
        formatMonth(nowProvider())
    }

    private func previousYearMonth() -> String {
        let calendar = Calendar(identifier: .gregorian)
        let previous = calendar.date(byAdding: .month, value: -1, to: nowProvider()) ?? nowProvider()
        return formatMonth(previous)
    }

    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private static func defaultDecompressArchive(_ gzURL: URL) throws -> URL {
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

    private static func defaultValidateDatabase(_ fileURL: URL) -> Bool {
        MMDB(fileURL.path) != nil
    }
}

enum DBIPDatabaseError: Error {
    case invalidURL
    case httpFailed(status: Int)
    case decompressionFailed
    case validationFailed
    case notFoundForCandidateMonths
}
