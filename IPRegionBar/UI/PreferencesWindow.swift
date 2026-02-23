import AppKit
import Foundation

final class PreferencesWindowController: NSWindowController {
    var onDisplayModeChanged: ((DisplayMode) -> Void)?
    var onRefreshIntervalChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onAutoUpdateChanged: ((Bool) -> Void)?
    var onDatabaseUpdateRequested: (() -> Void)?
    var onProviderChanged: ((IPProvider) -> Void)?
    var onRequestTimeoutChanged: ((TimeInterval) -> Void)?
    var onResetDefaults: (() -> Void)?

    private let displayModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)

    private let dbVersionLabel = NSTextField(labelWithString: "Database version: DB-IP Lite · unknown")
    private let lastUpdatedLabel = NSTextField(labelWithString: "Last updated: never")
    private let updateDBButton = NSButton(title: "Update database now", target: nil, action: nil)
    private let updateProgressBar = NSProgressIndicator()
    private let updateProgressLabel = NSTextField(labelWithString: "Updating database…")
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "Enable monthly auto-update", target: nil, action: nil)
    private let attributionButton = NSButton(title: "IP geolocation by DB-IP.com", target: nil, action: nil)

    private let ipProviderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let timeoutField = NSTextField(string: "")
    private let resetButton = NSButton(title: "Reset to Defaults", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
        reloadValues()
    }

    func showWindowAndActivate() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateDatabaseStatus(_ status: DatabaseStatus) {
        let isUpdating: Bool
        switch status {
        case .bundled(let month):
            dbVersionLabel.stringValue = "Database version: DB-IP Lite · \(month)"
            isUpdating = false
        case .updated(let month):
            dbVersionLabel.stringValue = "Database version: DB-IP Lite · \(month)"
            isUpdating = false
        case .updating:
            dbVersionLabel.stringValue = "Database version: updating…"
            isUpdating = true
        case .updateFailed:
            dbVersionLabel.stringValue = "Database version: update failed"
            isUpdating = false
        }

        updateDBButton.isEnabled = !isUpdating
        autoUpdateCheckbox.isEnabled = !isUpdating
        updateProgressBar.isHidden = !isUpdating
        updateProgressLabel.isHidden = !isUpdating
        if isUpdating {
            updateProgressBar.startAnimation(nil)
        } else {
            updateProgressBar.stopAnimation(nil)
        }

        if let updatedAt = UserDefaults.standard.object(forKey: SettingsKey.dbLastUpdated) as? Date {
            lastUpdatedLabel.stringValue = "Last updated: \(formatted(updatedAt))"
        } else {
            lastUpdatedLabel.stringValue = "Last updated: bundled with app"
        }
    }

    func reloadValues() {
        displayModePopup.removeAllItems()
        DisplayMode.allCases.forEach { displayModePopup.addItem(withTitle: $0.title) }
        displayModePopup.selectItem(at: DisplayMode.allCases.firstIndex(of: DisplayMode.current) ?? 0)

        let refreshInterval = UserDefaults.standard.double(forKey: SettingsKey.refreshInterval)
        let currentRefresh = RefreshIntervalOption.from(seconds: refreshInterval == 0 ? AppDefaults.refreshInterval : refreshInterval)
        refreshPopup.removeAllItems()
        RefreshIntervalOption.allCases.forEach { refreshPopup.addItem(withTitle: $0.title) }
        refreshPopup.selectItem(at: RefreshIntervalOption.allCases.firstIndex(of: currentRefresh) ?? 1)

        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        let autoUpdateEnabled: Bool
        if UserDefaults.standard.object(forKey: SettingsKey.autoUpdateDB) == nil {
            autoUpdateEnabled = AppDefaults.autoUpdateDB
        } else {
            autoUpdateEnabled = UserDefaults.standard.bool(forKey: SettingsKey.autoUpdateDB)
        }
        autoUpdateCheckbox.state = autoUpdateEnabled ? .on : .off
        if updateProgressBar.isHidden {
            autoUpdateCheckbox.isEnabled = true
            updateDBButton.isEnabled = true
        }

        ipProviderPopup.removeAllItems()
        IPProvider.allCases.forEach { ipProviderPopup.addItem(withTitle: $0.title) }
        let providerRaw = UserDefaults.standard.string(forKey: SettingsKey.ipProvider) ?? AppDefaults.ipProvider
        let provider = IPProvider(rawValue: providerRaw) ?? .ipify
        ipProviderPopup.selectItem(at: IPProvider.allCases.firstIndex(of: provider) ?? 0)

        let timeout = UserDefaults.standard.double(forKey: SettingsKey.requestTimeout)
        timeoutField.stringValue = String(format: "%.0f", timeout == 0 ? AppDefaults.requestTimeout : timeout)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false

        tabs.addTabViewItem(NSTabViewItem(identifier: "general"))
        tabs.addTabViewItem(NSTabViewItem(identifier: "database"))
        tabs.addTabViewItem(NSTabViewItem(identifier: "advanced"))

        tabs.tabViewItems[0].label = "General"
        tabs.tabViewItems[1].label = "Database"
        tabs.tabViewItems[2].label = "Advanced"

        tabs.tabViewItems[0].view = makeGeneralTab()
        tabs.tabViewItems[1].view = makeDatabaseTab()
        tabs.tabViewItems[2].view = makeAdvancedTab()

        contentView.addSubview(tabs)

        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            tabs.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            tabs.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    private func makeGeneralTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let displayRow = labeledRow(label: "Display Mode", control: displayModePopup)
        let refreshRow = labeledRow(label: "Refresh Interval", control: refreshPopup)

        displayModePopup.target = self
        displayModePopup.action = #selector(displayModeChanged)

        refreshPopup.target = self
        refreshPopup.action = #selector(refreshChanged)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

        [displayRow, refreshRow, launchAtLoginCheckbox].forEach(stack.addArrangedSubview)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        ])

        return view
    }

    private func makeDatabaseTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))

        dbVersionLabel.alignment = .center
        lastUpdatedLabel.alignment = .center

        attributionButton.isBordered = false
        attributionButton.contentTintColor = .linkColor
        attributionButton.alignment = .center
        attributionButton.target = self
        attributionButton.action = #selector(openAttribution)

        updateDBButton.target = self
        updateDBButton.action = #selector(updateDatabase)

        updateProgressBar.style = .bar
        updateProgressBar.isIndeterminate = true
        updateProgressBar.controlSize = .regular
        updateProgressBar.translatesAutoresizingMaskIntoConstraints = false
        updateProgressBar.isHidden = true

        updateProgressLabel.alignment = .center
        updateProgressLabel.textColor = .secondaryLabelColor
        updateProgressLabel.isHidden = true

        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        [dbVersionLabel, lastUpdatedLabel, updateDBButton, updateProgressBar, updateProgressLabel, autoUpdateCheckbox, attributionButton].forEach(stack.addArrangedSubview)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            updateProgressBar.widthAnchor.constraint(equalToConstant: 320),
        ])

        return view
    }

    private func makeAdvancedTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let providerRow = labeledRow(label: "IP Provider", control: ipProviderPopup)
        let timeoutRow = labeledRow(label: "Request timeout (sec)", control: timeoutField)

        ipProviderPopup.target = self
        ipProviderPopup.action = #selector(providerChanged)

        timeoutField.target = self
        timeoutField.action = #selector(timeoutChanged)

        resetButton.target = self
        resetButton.action = #selector(resetDefaults)

        [providerRow, timeoutRow, resetButton].forEach(stack.addArrangedSubview)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        ])

        return view
    }

    private func labeledRow(label: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(control)

        return row
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @objc private func displayModeChanged() {
        let selected = DisplayMode.allCases[max(displayModePopup.indexOfSelectedItem, 0)]
        onDisplayModeChanged?(selected)
    }

    @objc private func refreshChanged() {
        let selected = RefreshIntervalOption.allCases[max(refreshPopup.indexOfSelectedItem, 0)]
        onRefreshIntervalChanged?(selected.seconds)
    }

    @objc private func launchAtLoginChanged() {
        onLaunchAtLoginChanged?(launchAtLoginCheckbox.state == .on)
    }

    @objc private func updateDatabase() {
        onDatabaseUpdateRequested?()
    }

    @objc private func autoUpdateChanged() {
        onAutoUpdateChanged?(autoUpdateCheckbox.state == .on)
    }

    @objc private func providerChanged() {
        let selected = IPProvider.allCases[max(ipProviderPopup.indexOfSelectedItem, 0)]
        onProviderChanged?(selected)
    }

    @objc private func timeoutChanged() {
        let timeout = Double(timeoutField.stringValue) ?? AppDefaults.requestTimeout
        onRequestTimeoutChanged?(max(1, timeout))
    }

    @objc private func resetDefaults() {
        onResetDefaults?()
        reloadValues()
    }

    @objc private func openAttribution() {
        guard let url = URL(string: "https://db-ip.com") else { return }
        NSWorkspace.shared.open(url)
    }
}
