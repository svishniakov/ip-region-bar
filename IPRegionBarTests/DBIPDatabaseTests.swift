import Foundation
import XCTest
@testable import IPRegionBar

final class DBIPDatabaseTests: XCTestCase {
    func testStatusIsNotInstalledWhenDatabaseFileMissing() async throws {
        let context = try TestContext()
        let database = context.makeDatabase()

        let status = await database.status()
        switch status {
        case .notInstalled:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected .notInstalled, got \(status)")
        }
    }

    func testInstallNowSetsInstalledFlagsAndWritesDatabase() async throws {
        let context = try TestContext(now: Self.fixedDate)

        let database = context.makeDatabase(
            downloadArchive: { _ in
                let tempGZ = context.tempDirectory.appendingPathComponent("archive.mmdb.gz")
                try Data("fake-gz".utf8).write(to: tempGZ)
                let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (tempGZ, response)
            },
            decompressArchive: { gzURL in
                let mmdbURL = gzURL.deletingPathExtension()
                try Data("fake-mmdb".utf8).write(to: mmdbURL)
                return mmdbURL
            },
            validateDatabase: { _ in true }
        )

        let didInstall = await database.installNow()
        let isInstalled = await database.isInstalled()
        XCTAssertTrue(didInstall)
        XCTAssertTrue(isInstalled)
        XCTAssertTrue(context.defaults.bool(forKey: SettingsKey.dbInstalledByUser))
        XCTAssertEqual(context.defaults.string(forKey: SettingsKey.dbMonth), "2026-02")
        XCTAssertNotNil(context.defaults.object(forKey: SettingsKey.dbLastUpdated) as? Date)

        let status = await database.status()
        switch status {
        case .installed(let month):
            XCTAssertEqual(month, "2026-02")
        default:
            XCTFail("Expected .installed, got \(status)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: context.expectedDatabaseURL.path))
    }

    func testUpdateIfNeededSkipsBeforeFirstManualInstall() async throws {
        let context = try TestContext(now: Self.fixedDate)
        try context.prepareInstalledDatabaseFile()
        context.defaults.set(true, forKey: SettingsKey.autoUpdateDB)
        context.defaults.set(false, forKey: SettingsKey.dbInstalledByUser)

        let counter = InvocationCounter()
        let database = context.makeDatabase(
            downloadArchive: { _ in
                counter.increment()
                throw DBIPDatabaseError.httpFailed(status: 500)
            },
            decompressArchive: { url in url.deletingPathExtension() },
            validateDatabase: { _ in true }
        )

        let didUpdate = await database.updateIfNeeded()
        XCTAssertFalse(didUpdate)
        XCTAssertEqual(counter.value, 0)
    }

    func testManualUpdateReminderDependsOnAutoUpdateAndAge() async throws {
        let context = try TestContext(now: Self.fixedDate)
        try context.prepareInstalledDatabaseFile()

        context.defaults.set(false, forKey: SettingsKey.autoUpdateDB)
        context.defaults.set(Self.oldDate, forKey: SettingsKey.dbLastUpdated)

        let database = context.makeDatabase()
        let reminderWhenAutoOff = await database.needsManualUpdateReminder()
        XCTAssertTrue(reminderWhenAutoOff)

        context.defaults.set(true, forKey: SettingsKey.autoUpdateDB)
        let reminderWhenAutoOn = await database.needsManualUpdateReminder()
        XCTAssertFalse(reminderWhenAutoOn)
    }

    private static var fixedDate: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: "2026-02-15T12:00:00Z") ?? Date(timeIntervalSince1970: 1_771_156_800)
    }

    private static var oldDate: Date {
        fixedDate.addingTimeInterval(-(31 * 24 * 3600))
    }
}

private final class InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct TestContext {
    let defaults: UserDefaults
    let tempDirectory: URL
    let appSupportRoot: URL
    let expectedDatabaseURL: URL
    let now: Date

    init(now: Date = Date()) throws {
        self.now = now

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ipregionbar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.tempDirectory = directory
        self.appSupportRoot = directory
        self.expectedDatabaseURL = directory
            .appendingPathComponent("IPRegionBar", isDirectory: true)
            .appendingPathComponent("dbip-city-lite.mmdb")

        let suiteName = "ipregionbar.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "DBIPDatabaseTests", code: 1, userInfo: nil)
        }
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults
    }

    func makeDatabase(
        downloadArchive: @escaping DBIPDatabase.DownloadArchive = { _ in
            throw DBIPDatabaseError.httpFailed(status: 500)
        },
        decompressArchive: @escaping DBIPDatabase.DecompressArchive = { url in
            throw DBIPDatabaseError.decompressionFailed
        },
        validateDatabase: @escaping DBIPDatabase.ValidateDatabase = { _ in false }
    ) -> DBIPDatabase {
        DBIPDatabase(
            fileManager: .default,
            defaults: defaults,
            appSupportRoot: appSupportRoot,
            nowProvider: { now },
            downloadArchive: downloadArchive,
            decompressArchive: decompressArchive,
            validateDatabase: validateDatabase
        )
    }

    func prepareInstalledDatabaseFile() throws {
        try FileManager.default.createDirectory(at: expectedDatabaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing-mmdb".utf8).write(to: expectedDatabaseURL)
        defaults.set("2026-01", forKey: SettingsKey.dbMonth)
    }
}
