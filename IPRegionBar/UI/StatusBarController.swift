import AppKit
import Foundation

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var refreshTimer: Timer?

    private(set) var currentInfo: IPInfo?
    private(set) var currentState: AppState = .loading
    private(set) var databaseStatus: DatabaseStatus = .bundled(month: "unknown")
    private(set) var needsDatabaseUpdateReminder = false

    var onRefreshRequest: (() -> Void)?
    var onPreferencesRequest: (() -> Void)?
    var onAboutRequest: (() -> Void)?

    override init() {
        super.init()
        setLabel(for: .loading)
        rebuildMenu()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func restoreLastKnownInfo() {
        guard
            let data = UserDefaults.standard.data(forKey: SettingsKey.lastKnownIPInfo),
            let info = try? JSONDecoder().decode(IPInfo.self, from: data)
        else {
            return
        }

        currentInfo = info
    }

    func setDatabaseStatus(_ status: DatabaseStatus) {
        databaseStatus = status
        rebuildMenu()
    }

    func setNeedsDatabaseUpdateReminder(_ needsReminder: Bool) {
        needsDatabaseUpdateReminder = needsReminder
        setLabel(for: currentState)
        rebuildMenu()
    }

    func scheduleRefresh() {
        refreshTimer?.invalidate()
        let interval = UserDefaults.standard.double(forKey: SettingsKey.refreshInterval)

        guard interval > 0 else {
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.onRefreshRequest?()
        }
    }

    func updateState(_ state: AppState) {
        currentState = state

        switch state {
        case .loaded(let info):
            currentInfo = info
            if let encoded = try? JSONEncoder().encode(info) {
                UserDefaults.standard.set(encoded, forKey: SettingsKey.lastKnownIPInfo)
            }
        case .offline(let last):
            if let last {
                currentInfo = last
            }
        case .loading, .error:
            break
        }

        setLabel(for: state)
        rebuildMenu()
    }

    private func setLabel(for state: AppState) {
        let reminderPrefix = needsDatabaseUpdateReminder ? "❗️ " : ""
        let text: String

        switch state {
        case .loading:
            text = "🌐 …"
        case .loaded(let info):
            switch DisplayMode.current {
            case .flagCityCountry:
                if info.city.isEmpty {
                    text = "\(reminderPrefix)\(info.flagEmoji) \(info.countryName)"
                } else {
                    text = "\(reminderPrefix)\(info.flagEmoji) \(info.city), \(info.countryName)"
                }
            case .flagCountry:
                text = "\(reminderPrefix)\(info.flagEmoji) \(info.countryName)"
            case .flagOnly:
                text = "\(reminderPrefix)\(info.flagEmoji)"
            case .ipOnly:
                text = "\(reminderPrefix)\(info.ip)"
            }
        case .offline(let last):
            if let last {
                text = "\(reminderPrefix)\(last.flagEmoji) \(last.city.isEmpty ? last.countryName : last.city) ⚠️"
            } else {
                text = "🌐 —"
            }
        case .error:
            text = "⚠️ Error"
        }

        statusItem.button?.title = text
    }

    private func rebuildMenu() {
        let menu = MenuBuilder.build(
            state: currentState,
            info: currentInfo,
            databaseStatus: databaseStatus,
            needsDatabaseUpdateReminder: needsDatabaseUpdateReminder
        )

        for item in menu.items {
            switch item.action {
            case #selector(refreshNow):
                item.target = self
            case #selector(openPreferences):
                item.target = self
            case #selector(openAbout):
                item.target = self
            case #selector(quitApp):
                item.target = self
            case #selector(copyIP):
                item.target = currentInfo == nil ? nil : self
                item.isEnabled = currentInfo != nil
            case #selector(copyCountry):
                item.target = currentInfo == nil ? nil : self
                item.isEnabled = currentInfo != nil
            case #selector(copyCity):
                item.target = currentInfo == nil ? nil : self
                item.isEnabled = currentInfo != nil
            default:
                break
            }
        }

        statusItem.menu = menu
    }

    @objc func refreshNow() {
        onRefreshRequest?()
    }

    @objc func openPreferences() {
        onPreferencesRequest?()
    }

    @objc func openAbout() {
        onAboutRequest?()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func copyIP() {
        copyIPValue()
    }

    @objc func copyCountry() {
        copyCountryValue()
    }

    @objc func copyCity() {
        copyCityValue()
    }

    private func copyIPValue() {
        guard let value = currentInfo?.ip else { return }
        ClipboardHelper.copyToPasteboard(value, fieldName: "IP")
    }

    private func copyCountryValue() {
        guard let value = currentInfo?.countryName else { return }
        ClipboardHelper.copyToPasteboard(value, fieldName: "Country")
    }

    private func copyCityValue() {
        guard let value = currentInfo?.city, !value.isEmpty else { return }
        ClipboardHelper.copyToPasteboard(value, fieldName: "City")
    }
}
