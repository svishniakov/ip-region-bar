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

    private let licenseKeySecureField = NSSecureTextField(string: "")
    private let licenseKeyPlainField = NSTextField(string: "")
    private let showLicenseButton = NSButton(checkboxWithTitle: "Show", target: nil, action: nil)
    private let dbStatusLabel = NSTextField(labelWithString: "Database status: —")
    private let updateDBButton = NSButton(title: "Update database now", target: nil, action: nil)
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "Enable weekly auto-update", target: nil, action: nil)

    private let ipProviderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let timeoutField = NSTextField(string: "")
    private let resetButton = NSButton(title: "Reset to Defaults", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
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
        dbStatusLabel.stringValue = switch status {
        case .missing:
            "Database status: missing"
        case let .downloading(progress):
            "Database status: downloading \(Int(progress * 100))%"
        case let .ready(updatedAt):
            "Database status: updated \(formatted(updatedAt))"
        case let .outdated(updatedAt):
            "Database status: outdated (\(formatted(updatedAt)))"
        case let .updateFailed(error):
            "Database status: failed (\(error.localizedDescription))"
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

        let licenseKey = (try? KeychainHelper.readLicenseKey()) ?? nil
        licenseKeySecureField.stringValue = licenseKey ?? ""
        licenseKeyPlainField.stringValue = licenseKey ?? ""

        autoUpdateCheckbox.state = UserDefaults.standard.bool(forKey: SettingsKey.autoUpdateDB) ? .on : .off

        ipProviderPopup.removeAllItems()
        IPProvider.allCases.forEach { ipProviderPopup.addItem(withTitle: $0.title) }
        let providerRaw = UserDefaults.standard.string(forKey: SettingsKey.ipProvider) ?? AppDefaults.ipProvider
        let provider = IPProvider(rawValue: providerRaw) ?? .ipify
        ipProviderPopup.selectItem(at: IPProvider.allCases.firstIndex(of: provider) ?? 0)

        let timeout = UserDefaults.standard.double(forKey: SettingsKey.requestTimeout)
        timeoutField.stringValue = String(format: "%.0f", timeout == 0 ? AppDefaults.requestTimeout : timeout)

        if let updatedAt = UserDefaults.standard.object(forKey: SettingsKey.dbLastUpdated) as? Date {
            updateDatabaseStatus(.ready(updatedAt: updatedAt))
        } else {
            updateDatabaseStatus(.missing)
        }
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
        let view = NSView()

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
        let view = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "License Key")

        let keyRow = NSStackView()
        keyRow.orientation = .horizontal
        keyRow.spacing = 8

        licenseKeyPlainField.isHidden = true
        licenseKeySecureField.placeholderString = "MaxMind License Key"
        licenseKeyPlainField.placeholderString = "MaxMind License Key"

        showLicenseButton.target = self
        showLicenseButton.action = #selector(toggleShowLicense)

        keyRow.addArrangedSubview(licenseKeySecureField)
        keyRow.addArrangedSubview(licenseKeyPlainField)
        keyRow.addArrangedSubview(showLicenseButton)

        licenseKeySecureField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        updateDBButton.target = self
        updateDBButton.action = #selector(updateDatabase)

        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged)

        [label, keyRow, dbStatusLabel, updateDBButton, autoUpdateCheckbox].forEach(stack.addArrangedSubview)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        ])

        return view
    }

    private func makeAdvancedTab() -> NSView {
        let view = NSView()

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

    @objc private func toggleShowLicense() {
        let show = showLicenseButton.state == .on
        if show {
            licenseKeyPlainField.stringValue = licenseKeySecureField.stringValue
        } else {
            licenseKeySecureField.stringValue = licenseKeyPlainField.stringValue
        }
        licenseKeySecureField.isHidden = show
        licenseKeyPlainField.isHidden = !show
    }

    @objc private func updateDatabase() {
        let visibleValue = showLicenseButton.state == .on ? licenseKeyPlainField.stringValue : licenseKeySecureField.stringValue
        if !visibleValue.isEmpty {
            try? KeychainHelper.saveLicenseKey(visibleValue)
        }
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
}
