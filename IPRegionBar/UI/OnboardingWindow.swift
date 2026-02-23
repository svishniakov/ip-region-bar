import AppKit
import Foundation

final class OnboardingWindowController: NSWindowController {
    var onDownloadRequested: ((String, @escaping @Sendable (Double) -> Void) async throws -> Void)?
    var onCompleted: (() -> Void)?

    private let instructionsLabel = NSTextField(labelWithString: "Для работы приложения нужна бесплатная база MaxMind GeoLite2.")
    private let secureField = NSSecureTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let downloadButton = NSButton(title: "Скачать базу →", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "IP Region Bar Setup"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "IP Region Bar Setup")
        title.font = .boldSystemFont(ofSize: 20)

        instructionsLabel.lineBreakMode = .byWordWrapping
        instructionsLabel.maximumNumberOfLines = 0

        let step1 = NSTextField(labelWithString: "1. Зарегистрируйтесь на maxmind.com")
        let openMaxMindButton = NSButton(title: "Открыть maxmind.com →", target: self, action: #selector(openMaxMind))
        openMaxMindButton.bezelStyle = .rounded

        let step2 = NSTextField(labelWithString: "2. Вставьте License Key:")

        secureField.placeholderString = "xxxxxxxxxxxxxxxx"

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.isHidden = true

        statusLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas

        let cancelButton = NSButton(title: "Отмена", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded

        downloadButton.target = self
        downloadButton.action = #selector(downloadTapped)
        downloadButton.bezelStyle = .rounded
        downloadButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(downloadButton)

        [
            title,
            instructionsLabel,
            step1,
            openMaxMindButton,
            step2,
            secureField,
            progressIndicator,
            statusLabel,
            buttonRow,
        ].forEach(stack.addArrangedSubview)

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            secureField.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    func showWindowAndActivate() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openMaxMind() {
        guard let url = URL(string: "https://www.maxmind.com/") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func cancelTapped() {
        close()
    }

    @objc private func downloadTapped() {
        let licenseKey = secureField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
            statusLabel.stringValue = "Введите License Key"
            statusLabel.textColor = .systemRed
            return
        }

        setBusy(true)
        statusLabel.stringValue = "Скачивание базы…"
        statusLabel.textColor = .secondaryLabelColor

        Task {
            do {
                try await onDownloadRequested?(licenseKey) { [weak self] progress in
                    Task { @MainActor in
                        self?.progressIndicator.doubleValue = progress
                        self?.statusLabel.stringValue = "Скачивание базы… \(Int(progress * 100))%"
                    }
                }

                try KeychainHelper.saveLicenseKey(licenseKey)
                statusLabel.stringValue = "Готово"
                close()
                onCompleted?()
            } catch {
                setBusy(false)
                statusLabel.stringValue = error.localizedDescription
                statusLabel.textColor = .systemRed
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        secureField.isEnabled = !busy
        downloadButton.isEnabled = !busy
        progressIndicator.isHidden = !busy
    }
}
