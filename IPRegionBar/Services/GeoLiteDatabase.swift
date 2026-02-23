import Foundation

actor GeoLiteDatabase {
    static let shared = GeoLiteDatabase()

    private let folderName = "IPRegionBar"
    private let databaseFilename = "GeoLite2-City.mmdb"
    private let maxAge: TimeInterval = 7 * 24 * 3600

    private var currentStatus: DatabaseStatus = .missing

    var databaseURL: URL {
        appSupportDirectory.appendingPathComponent(databaseFilename)
    }

    var isReady: Bool {
        FileManager.default.fileExists(atPath: databaseURL.path)
    }

    func status() -> DatabaseStatus {
        if !isReady {
            return .missing
        }

        guard let updatedAt = UserDefaults.standard.object(forKey: SettingsKey.dbLastUpdated) as? Date else {
            return .outdated(updatedAt: .distantPast)
        }

        if Date().timeIntervalSince(updatedAt) > maxAge {
            return .outdated(updatedAt: updatedAt)
        }

        return .ready(updatedAt: updatedAt)
    }

    func checkAndUpdateIfNeeded(licenseKey: String?) async {
        guard UserDefaults.standard.bool(forKey: SettingsKey.autoUpdateDB) else {
            currentStatus = status()
            return
        }

        guard let licenseKey, !licenseKey.isEmpty else {
            currentStatus = isReady ? status() : .missing
            return
        }

        switch status() {
        case .missing, .outdated:
            do {
                try await downloadOrUpdate(licenseKey: licenseKey)
            } catch {
                currentStatus = .updateFailed(error: error)
            }
        case .ready, .downloading, .updateFailed:
            currentStatus = status()
        }
    }

    func downloadOrUpdate(
        licenseKey: String,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        currentStatus = .downloading(progress: 0)

        let downloadURL = try buildDownloadURL(licenseKey: licenseKey)
        let archiveURL = try await downloadArchive(from: downloadURL) { progress in
            progressHandler?(progress)
        }

        do {
            let mmdbURL = try extractDatabase(fromArchive: archiveURL)
            try persistDatabase(mmdbURL)
            let now = Date()
            UserDefaults.standard.set(now, forKey: SettingsKey.dbLastUpdated)
            currentStatus = .ready(updatedAt: now)
        } catch {
            currentStatus = .updateFailed(error: error)
            throw error
        }
    }

    private func buildDownloadURL(licenseKey: String) throws -> URL {
        guard var components = URLComponents(string: "https://download.maxmind.com/app/geoip_download") else {
            throw GeoDatabaseError.invalidURL
        }

        components.queryItems = [
            .init(name: "edition_id", value: "GeoLite2-City"),
            .init(name: "license_key", value: licenseKey),
            .init(name: "suffix", value: "tar.gz"),
        ]

        guard let url = components.url else {
            throw GeoDatabaseError.invalidURL
        }

        return url
    }

    private func downloadArchive(
        from remoteURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let delegate = DownloadDelegate(progressHandler: progressHandler)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        return try await withCheckedThrowingContinuation { continuation in
            delegate.onFinished = { result in
                session.invalidateAndCancel()
                continuation.resume(with: result)
            }

            let task = session.downloadTask(with: remoteURL)
            task.resume()
        }
    }

    private func extractDatabase(fromArchive archiveURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let copiedArchiveURL = workingDirectory.appendingPathComponent("GeoLite2-City.tar.gz")

        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: archiveURL, to: copiedArchiveURL)

        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", copiedArchiveURL.path, "-C", workingDirectory.path]

        let outputPipe = Pipe()
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "tar exited with \(process.terminationStatus)"
            throw GeoDatabaseError.extractFailed(message)
        }

        let enumerator = fileManager.enumerator(at: workingDirectory, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == databaseFilename {
                return fileURL
            }
        }

        throw GeoDatabaseError.databaseFileMissing
    }

    private func persistDatabase(_ sourceURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: databaseURL.path) {
            try fileManager.removeItem(at: databaseURL)
        }

        try fileManager.copyItem(at: sourceURL, to: databaseURL)
    }

    private var appSupportDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent(folderName, isDirectory: true)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: @Sendable (Double) -> Void

    var onFinished: ((Result<URL, Error>) -> Void)?

    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            progressHandler(0)
            return
        }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(max(0, min(progress, 1)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            onFinished?(.failure(GeoDatabaseError.invalidResponse))
            return
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            onFinished?(.failure(GeoDatabaseError.httpStatus(response.statusCode)))
            return
        }

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: destination)
            onFinished?(.success(destination))
        } catch {
            onFinished?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        onFinished?(.failure(error))
    }
}

enum GeoDatabaseError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case extractFailed(String)
    case databaseFileMissing

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid MaxMind download URL"
        case .invalidResponse:
            return "Invalid MaxMind response"
        case let .httpStatus(code):
            return "MaxMind returned HTTP \(code)"
        case let .extractFailed(message):
            return "Unable to extract GeoLite archive: \(message)"
        case .databaseFileMissing:
            return "GeoLite2-City.mmdb not found in archive"
        }
    }
}
