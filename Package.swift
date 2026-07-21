// swift-tools-version: 6.0

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
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
