import AppKit
import Foundation
import Network
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var onboardingWindowController: OnboardingWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    private var networkDebounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

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

        requestNotificationPermission()
        setupNetworkMonitor()
        setupPreferencesController()

        Task { @MainActor [weak self] in
            await self?.bootstrapApplication()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetworkMonitor.shared.stop()
        networkDebounceTask?.cancel()
        fetchTask?.cancel()
    }

    @MainActor
    private func bootstrapApplication() async {
        let licenseKey = (try? KeychainHelper.readLicenseKey()) ?? nil
        let dbReady = await GeoLiteDatabase.shared.isReady

        if !dbReady {
            if let licenseKey, !licenseKey.isEmpty {
                do {
                    try await GeoLiteDatabase.shared.downloadOrUpdate(licenseKey: licenseKey) { [weak self] progress in
                        Task { @MainActor in
                            self?.statusBarController.setDatabaseStatus(.downloading(progress: progress))
                        }
                    }
                    try await IPGeolocationService.shared.loadDatabase()
                } catch {
                    statusBarController.updateState(.onboarding)
                    showOnboarding()
                    return
                }
            } else {
                statusBarController.updateState(.onboarding)
                showOnboarding()
                return
            }
        } else {
            do {
                try await IPGeolocationService.shared.loadDatabase()
            } catch {
                statusBarController.updateState(.error(error.localizedDescription))
                return
            }
        }

        let dbStatus = await GeoLiteDatabase.shared.status()
        statusBarController.setDatabaseStatus(dbStatus)
        preferencesWindowController?.updateDatabaseStatus(dbStatus)
        statusBarController.scheduleRefresh()
        startFetch()

        Task.detached {
            await GeoLiteDatabase.shared.checkAndUpdateIfNeeded(licenseKey: licenseKey)
        }
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController()

        controller.onDownloadRequested = { licenseKey, progress in
            try await GeoLiteDatabase.shared.downloadOrUpdate(licenseKey: licenseKey) { value in
                progress(value)
            }
            try await IPGeolocationService.shared.loadDatabase()

            let status = await GeoLiteDatabase.shared.status()
            await MainActor.run {
                self.statusBarController.setDatabaseStatus(status)
                self.preferencesWindowController?.updateDatabaseStatus(status)
            }
        }

        controller.onCompleted = { [weak self] in
            guard let self else { return }
            self.statusBarController.scheduleRefresh()
            self.startFetch()
        }

        onboardingWindowController = controller
        controller.showWindowAndActivate()
        statusBarController.updateState(.onboarding)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func setupNetworkMonitor() {
        NetworkMonitor.shared.onPathChange = { [weak self] path, didInterfaceChange in
            guard let self else { return }

            if path.status == .satisfied, didInterfaceChange {
                self.networkDebounceTask?.cancel()
                self.networkDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        self.startFetch()
                    }
                }
            }

            if path.status != .satisfied {
                Task { @MainActor in
                    self.statusBarController.updateState(.offline(last: self.statusBarController.currentInfo))
                }
            }
        }

        NetworkMonitor.shared.start()
    }

    private func startFetch() {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchAndUpdate()
        }
    }

    private func fetchAndUpdate() async {
        await MainActor.run {
            statusBarController.updateState(.loading)
        }

        do {
            let ip = try await ExternalIPService.shared.fetchIP()
            try await IPGeolocationService.shared.reloadDatabaseIfNeeded()
            let info = try await IPGeolocationService.shared.lookup(ip: ip)

            await MainActor.run {
                statusBarController.updateState(.loaded(info))
                statusBarController.scheduleRefresh()
            }
        } catch {
            await MainActor.run {
                let current = statusBarController.currentInfo
                if current != nil {
                    statusBarController.updateState(.offline(last: current))
                } else {
                    statusBarController.updateState(.error(error.localizedDescription))
                }
            }
        }

        let status = await GeoLiteDatabase.shared.status()
        await MainActor.run {
            statusBarController.setDatabaseStatus(status)
            preferencesWindowController?.updateDatabaseStatus(status)
        }
    }

    private func setupPreferencesController() {
        let controller = PreferencesWindowController()

        controller.onDisplayModeChanged = { mode in
            UserDefaults.standard.set(mode.rawValue, forKey: SettingsKey.displayMode)
            self.statusBarController.updateState(self.statusBarController.currentState)
        }

        controller.onRefreshIntervalChanged = { interval in
            UserDefaults.standard.set(interval, forKey: SettingsKey.refreshInterval)
            self.statusBarController.scheduleRefresh()
        }

        controller.onLaunchAtLoginChanged = { enabled in
            UserDefaults.standard.set(enabled, forKey: SettingsKey.launchAtLogin)
            LaunchAtLogin.setEnabled(enabled)
        }

        controller.onAutoUpdateChanged = { enabled in
            UserDefaults.standard.set(enabled, forKey: SettingsKey.autoUpdateDB)
        }

        controller.onDatabaseUpdateRequested = { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    guard let key = try KeychainHelper.readLicenseKey(), !key.isEmpty else {
                        await MainActor.run {
                            self.showOnboarding()
                        }
                        return
                    }

                    try await GeoLiteDatabase.shared.downloadOrUpdate(licenseKey: key) { progress in
                        Task { @MainActor in
                            self.statusBarController.setDatabaseStatus(.downloading(progress: progress))
                            self.preferencesWindowController?.updateDatabaseStatus(.downloading(progress: progress))
                        }
                    }

                    try await IPGeolocationService.shared.loadDatabase()
                    await self.fetchAndUpdate()
                } catch {
                    let failed = DatabaseStatus.updateFailed(error: error)
                    await MainActor.run {
                        self.statusBarController.setDatabaseStatus(failed)
                        self.preferencesWindowController?.updateDatabaseStatus(failed)
                    }
                }
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

    private func openPreferences() {
        preferencesWindowController?.reloadValues()
        preferencesWindowController?.showWindowAndActivate()
    }
}
