import AppKit
import Foundation

enum MenuBuilder {
    static func build(
        state: AppState,
        info: IPInfo?,
        databaseStatus: DatabaseStatus
    ) -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: menuHeaderTitle(state: state, info: info), action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        titleItem.attributedTitle = NSAttributedString(
            string: titleItem.title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(titleItem)
        menu.addItem(.separator())

        if let info {
            menu.addItem(copyableItem(label: "IP", value: info.ip, action: #selector(StatusBarController.copyIP), target: nil))
            menu.addItem(copyableItem(label: "Country", value: info.countryName, action: #selector(StatusBarController.copyCountry), target: nil))
            menu.addItem(copyableItem(label: "City", value: info.city.isEmpty ? "Unknown" : info.city, action: #selector(StatusBarController.copyCity), target: nil))

            if !info.region.isEmpty {
                menu.addItem(readOnlyItem(label: "Region", value: info.region))
            }

            if !info.timezone.isEmpty {
                menu.addItem(readOnlyItem(label: "Timezone", value: info.timezone))
            }
            menu.addItem(.separator())
        }

        let dbItem = NSMenuItem(title: databaseStatusTitle(databaseStatus), action: nil, keyEquivalent: "")
        dbItem.isEnabled = false
        dbItem.attributedTitle = NSAttributedString(
            string: dbItem.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(dbItem)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(StatusBarController.refreshNow), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command]
        menu.addItem(refresh)

        menu.addItem(.separator())

        let preferences = NSMenuItem(title: "Preferences…", action: #selector(StatusBarController.openPreferences), keyEquivalent: ",")
        preferences.keyEquivalentModifierMask = [.command]
        menu.addItem(preferences)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(StatusBarController.quitApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        // Targets are set by StatusBarController after building the menu.
        return menu
    }

    private static func menuHeaderTitle(state: AppState, info: IPInfo?) -> String {
        switch state {
        case .loading:
            return "Loading…"
        case .onboarding:
            return "Setup required"
        case .error(let message):
            return "Error: \(message)"
        case .offline(let last):
            if let last {
                return "\(last.title) ⚠️"
            }
            return "Offline"
        case .loaded(let info):
            return info.title
        }
    }

    private static func databaseStatusTitle(_ status: DatabaseStatus) -> String {
        switch status {
        case .missing:
            return "Database: missing"
        case let .downloading(progress):
            return "Database: downloading \(Int(progress * 100))%"
        case let .ready(updatedAt):
            return "Database: updated \(relativeDate(updatedAt))"
        case let .outdated(updatedAt):
            return "Database: outdated (\(relativeDate(updatedAt)))"
        case let .updateFailed(error):
            return "Database: update failed (\(error.localizedDescription))"
        }
    }

    private static func relativeDate(_ date: Date) -> String {
        if date == .distantPast {
            return "unknown"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func copyableItem(label: String, value: String, action: Selector, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: "\(label): \(value)", action: action, keyEquivalent: "")
        item.target = target
        item.toolTip = "Click to copy"
        return item
    }

    private static func readOnlyItem(label: String, value: String) -> NSMenuItem {
        let item = NSMenuItem(title: "\(label): \(value)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
