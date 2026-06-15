import Foundation
import Network

/// Описание одного сетевого интерфейса, видимого в текущем пути.
///
/// Нужен отдельный тип, а не `NWInterface`, чтобы логику детектирования смены
/// сети можно было покрыть юнит-тестами без живого `NWPath`.
struct NetworkInterfaceDescriptor: Equatable {
    let name: String
    let type: NWInterface.InterfaceType
}

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ipregionbar.network-monitor")
    private var lastInterfaceDescription: String?

    var onPathChange: ((NWPath, Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let interfaceDescription = Self.signature(for: path.availableInterfaces)
            let didInterfaceChange = interfaceDescription != self.lastInterfaceDescription
            self.lastInterfaceDescription = interfaceDescription
            self.onPathChange?(path, didInterfaceChange)
        }

        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    /// Стабильная подпись набора интерфейсов: имя + тип, отсортировано по имени.
    ///
    /// Используем имена интерфейсов (`en0`, `utun4`, `pdcp_ip0`, …), а не только
    /// типы, потому что тип VPN-интерфейсов часто `.other`, и смена VPN не меняет
    /// набор типов — значит не менялась и старая сигнатура. Имена же уникальны для
    /// каждого интерфейса, поэтому появление/исчезновение VPN ловится надёжно.
    static func signature(for interfaces: [NWInterface]) -> String {
        interfaces
            .map { NetworkInterfaceDescriptor(name: $0.name, type: $0.type) }
            .signature()
    }

    /// Чистая, тестируемая версия сигнатуры поверх дескрипторов.
    static func signature(for descriptors: [NetworkInterfaceDescriptor]) -> String {
        descriptors.signature()
    }
}

private extension Sequence where Element == NetworkInterfaceDescriptor {
    func signature() -> String {
        sorted { $0.name < $1.name }
            .map { "\($0.name):\(String(describing: $0.type))" }
            .joined(separator: "|")
    }
}
