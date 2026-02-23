import AppKit
import XCTest
@testable import IPRegionBar

final class MenuBuilderTests: XCTestCase {
    func testSetupRequiredMenuContainsDownloadAction() {
        let menu = MenuBuilder.build(
            state: .setupRequired,
            info: nil,
            databaseStatus: .notInstalled,
            needsDatabaseUpdateReminder: false
        )

        XCTAssertTrue(menu.items.contains { $0.title == "Download DB-IP database now" })
        XCTAssertTrue(menu.items.contains { $0.title == "Database: not installed" })
        XCTAssertFalse(menu.items.contains { $0.title.hasPrefix("Country:") })
        XCTAssertFalse(menu.items.contains { $0.title.hasPrefix("City:") })
    }

    func testReminderIsHiddenWhenDatabaseNotInstalled() {
        let menu = MenuBuilder.build(
            state: .setupRequired,
            info: nil,
            databaseStatus: .notInstalled,
            needsDatabaseUpdateReminder: true
        )

        XCTAssertFalse(menu.items.contains { $0.title.contains("Need to update GeoIP database") })
    }

    func testReminderIsVisibleWhenInstalledAndReminderRequested() {
        let info = IPInfo(
            ip: "1.1.1.1",
            countryCode: "US",
            countryName: "United States",
            city: "Santa Clara",
            region: "California",
            timezone: "America/Los_Angeles"
        )

        let menu = MenuBuilder.build(
            state: .loaded(info),
            info: info,
            databaseStatus: .installed(month: "2026-02"),
            needsDatabaseUpdateReminder: true
        )

        XCTAssertTrue(menu.items.contains { $0.title.contains("Need to update GeoIP database") })
    }
}
