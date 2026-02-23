import Foundation
import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ipregionbar.network-monitor")
    private var lastInterfaceDescription: String?

    var onPathChange: ((NWPath, Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let interfaceDescription = self.interfaceSignature(for: path)
            let didInterfaceChange = interfaceDescription != self.lastInterfaceDescription
            self.lastInterfaceDescription = interfaceDescription
            self.onPathChange?(path, didInterfaceChange)
        }

        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    private func interfaceSignature(for path: NWPath) -> String {
        [NWInterface.InterfaceType.wifi, .wiredEthernet, .cellular, .loopback, .other]
            .filter { path.usesInterfaceType($0) }
            .map { String(describing: $0) }
            .joined(separator: "|")
    }
}
