import AppKit
import Foundation
import Network
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var preferencesWindowController: PreferencesWindowController?

    private var networkDebounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        AppDefaults.register()
        statusBarController.restoreLastKnownInfo()

        statusBarController.onRefreshRequest = { [weak self] in
            self?.startFetch()
        }
        statusBarController.onPreferencesRequest = { [weak self] in
            self?.openPreferences()
        }
        statusBarController.onAboutRequest = { [weak self] in
            self?.showAbout()
        }

        requestNotificationPermission()
        setupNetworkMonitor()
        setupPreferencesController()

        Task { [weak self] in
            await self?.bootstrapApplication()
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        NetworkMonitor.shared.stop()
        networkDebounceTask?.cancel()
        fetchTask?.cancel()
    }

    @MainActor
    private func bootstrapApplication() async {
        do {
            try await IPGeolocationService.shared.loadDatabase()
        } catch {
            statusBarController.updateState(.error(error.localizedDescription))
            return
        }

        await syncDatabaseStatus()
        statusBarController.scheduleRefresh()
        startFetch()

        Task.detached { [weak self] in
            guard let self else { return }
            let didUpdate = await DBIPDatabase.shared.updateIfNeeded()
            if didUpdate {
                try? await IPGeolocationService.shared.reloadDatabase()
                await self.startFetch()
                await self.syncDatabaseStatus()
            } else {
                await self.syncDatabaseStatus()
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func setupNetworkMonitor() {
        NetworkMonitor.shared.onPathChange = { [weak self] path, didInterfaceChange in
            guard let self else { return }

            if path.status == .satisfied, didInterfaceChange {
                self.networkDebounceTask?.cancel()
                self.networkDebounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard let self else { return }
                    await self.startFetch()
                }
            }

            if path.status != .satisfied {
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateOfflineState()
                }
            }
        }

        NetworkMonitor.shared.start()
    }

    @MainActor
    private func startFetch() {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchAndUpdate()
        }
    }

    @MainActor
    private func fetchAndUpdate() async {
        statusBarController.updateState(.loading)

        do {
            let ip = try await ExternalIPService.shared.fetchIP()
            try await IPGeolocationService.shared.reloadDatabaseIfNeeded()
            let info = try await IPGeolocationService.shared.lookup(ip: ip)
            statusBarController.updateState(.loaded(info))
            statusBarController.scheduleRefresh()
        } catch {
            let current = statusBarController.currentInfo
            if current != nil {
                statusBarController.updateState(.offline(last: current))
            } else {
                statusBarController.updateState(.error(error.localizedDescription))
            }
        }

        await syncDatabaseStatus()
    }

    @MainActor
    private func setupPreferencesController() {
        let controller = PreferencesWindowController()

        controller.onDisplayModeChanged = { [weak self] mode in
            UserDefaults.standard.set(mode.rawValue, forKey: SettingsKey.displayMode)
            guard let self else { return }
            self.statusBarController.updateState(self.statusBarController.currentState)
        }

        controller.onRefreshIntervalChanged = { [weak self] interval in
            UserDefaults.standard.set(interval, forKey: SettingsKey.refreshInterval)
            self?.statusBarController.scheduleRefresh()
        }

        controller.onLaunchAtLoginChanged = { enabled in
            UserDefaults.standard.set(enabled, forKey: SettingsKey.launchAtLogin)
            LaunchAtLogin.setEnabled(enabled)
        }

        controller.onAutoUpdateChanged = { enabled in
            UserDefaults.standard.set(enabled, forKey: SettingsKey.autoUpdateDB)
            Task { [weak self] in
                await self?.syncDatabaseStatus()
            }
        }

        controller.onDatabaseUpdateRequested = { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                await self.performManualDatabaseUpdate()
            }
        }

        controller.onProviderChanged = { provider in
            UserDefaults.standard.set(provider.rawValue, forKey: SettingsKey.ipProvider)
        }

        controller.onRequestTimeoutChanged = { timeout in
            UserDefaults.standard.set(timeout, forKey: SettingsKey.requestTimeout)
        }

        controller.onResetDefaults = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(AppDefaults.displayMode, forKey: SettingsKey.displayMode)
            UserDefaults.standard.set(AppDefaults.refreshInterval, forKey: SettingsKey.refreshInterval)
            UserDefaults.standard.set(AppDefaults.launchAtLogin, forKey: SettingsKey.launchAtLogin)
            UserDefaults.standard.set(AppDefaults.autoUpdateDB, forKey: SettingsKey.autoUpdateDB)
            UserDefaults.standard.set(AppDefaults.ipProvider, forKey: SettingsKey.ipProvider)
            UserDefaults.standard.set(AppDefaults.requestTimeout, forKey: SettingsKey.requestTimeout)
            controller.reloadValues()
            self.statusBarController.scheduleRefresh()
            self.startFetch()
        }

        preferencesWindowController = controller
    }

    @MainActor
    private func syncDatabaseStatus() async {
        let status = await DBIPDatabase.shared.status()
        let needsReminder = await DBIPDatabase.shared.needsManualUpdateReminder()
        statusBarController.setDatabaseStatus(status)
        statusBarController.setNeedsDatabaseUpdateReminder(needsReminder)
        preferencesWindowController?.updateDatabaseStatus(status)
    }

    @MainActor
    private func openPreferences() {
        preferencesWindowController?.reloadValues()
        Task { [weak self] in
            await self?.syncDatabaseStatus()
        }
        preferencesWindowController?.showWindowAndActivate()
    }

    @MainActor
    private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        let alert = NSAlert()
        alert.messageText = "IP Region Bar v\(version)"
        alert.informativeText = """
        Developer: svishniakov
        GitHub: https://github.com/svishniakov/ip-region-bar

        Geolocation data: DB-IP.com (CC BY 4.0)
        https://db-ip.com
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Open DB-IP")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn,
           let url = URL(string: "https://github.com/svishniakov/ip-region-bar") {
            NSWorkspace.shared.open(url)
        } else if response == .alertThirdButtonReturn,
                  let url = URL(string: "https://db-ip.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func updateOfflineState() {
        statusBarController.updateState(.offline(last: statusBarController.currentInfo))
    }

    @MainActor
    private func performManualDatabaseUpdate() async {
        statusBarController.setDatabaseStatus(.updating)
        preferencesWindowController?.updateDatabaseStatus(.updating)

        let didUpdate = await DBIPDatabase.shared.updateNow()
        if didUpdate {
            try? await IPGeolocationService.shared.reloadDatabase()
            await fetchAndUpdate()
        } else {
            await syncDatabaseStatus()
        }
    }
}
