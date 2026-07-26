// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SystemPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SystemPulse", targets: ["SystemPulse"])
    ],
    targets: [
        .executableTarget(
            name: "SystemPulse",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
