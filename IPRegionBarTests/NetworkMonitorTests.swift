import Network
import XCTest
@testable import IPRegionBar

final class NetworkMonitorTests: XCTestCase {
    private func descriptor(_ name: String, _ type: NWInterface.InterfaceType) -> NetworkInterfaceDescriptor {
        NetworkInterfaceDescriptor(name: name, type: type)
    }

    func testSignatureIgnoresOrder() {
        let a = NetworkMonitor.signature(for: [
            descriptor("en0", .wifi),
            descriptor("utun4", .other)
        ])
        let b = NetworkMonitor.signature(for: [
            descriptor("utun4", .other),
            descriptor("en0", .wifi)
        ])
        XCTAssertEqual(a, b)
    }

    func testSignatureChangesWhenVpnInterfaceAppears() {
        // Wi-Fi без VPN.
        let before = NetworkMonitor.signature(for: [
            descriptor("en0", .wifi)
        ])
        // Поднялся VPN — появился utun-интерфейс типа .other.
        let after = NetworkMonitor.signature(for: [
            descriptor("en0", .wifi),
            descriptor("utun4", .other)
        ])
        XCTAssertNotEqual(before, after)
    }

    func testSignatureChangesWhenVpnProviderSwitches() {
        // Один VPN (провайдер A на utun3).
        let providerA = NetworkMonitor.signature(for: [
            descriptor("en0", .wifi),
            descriptor("utun3", .other)
        ])
        // Переключились на другого провайдера (utun3 исчез, utun5 появился).
        let providerB = NetworkMonitor.signature(for: [
            descriptor("en0", .wifi),
            descriptor("utun5", .other)
        ])
        XCTAssertNotEqual(providerA, providerB)
    }

    func testSignatureStableWhenOnlyTypeDescriptionWouldHaveMissedIt() {
        // Оба интерфейса типа .other: классическая маскировка VPN под «other».
        // Старая сигнатура (только по типам) дала бы "other" в обоих случаях —
        // и не заметила бы смену интерфейса. По именам — замечает.
        let first = NetworkMonitor.signature(for: [descriptor("utun3", .other)])
        let second = NetworkMonitor.signature(for: [descriptor("utun5", .other)])
        XCTAssertNotEqual(first, second)
    }

    func testSignatureDistinguishesByNameOnlyWhenNamesDiffer() {
        let s1 = NetworkMonitor.signature(for: [descriptor("en0", .wifi)])
        let s2 = NetworkMonitor.signature(for: [descriptor("en1", .wifi)])
        XCTAssertNotEqual(s1, s2)
    }
}
