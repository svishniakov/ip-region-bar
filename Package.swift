// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IPRegionBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "IPRegionBar", targets: ["IPRegionBar"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "libmaxminddb",
            path: "Vendor/MMDB-Swift/libmaxminddb",
            publicHeadersPath: "."
        ),
        .target(
            name: "MMDB",
            dependencies: ["libmaxminddb"],
            path: "Vendor/MMDB-Swift/Sources/MMDB"
        ),
        .executableTarget(
            name: "IPRegionBar",
            dependencies: ["MMDB"],
            path: "IPRegionBar",
            exclude: [
                "App/Info.plist",
                "IPRegionBar.entitlements",
            ],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Security"),
            ]
        ),
    ]
)
