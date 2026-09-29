// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonalControlCenter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PersonalControlCenter", targets: ["PersonalControlCenter"])
    ],
    targets: [
        .executableTarget(
            name: "PersonalControlCenter",
            path: "PersonalControlCenter",
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PersonalControlCenterTests",
            dependencies: ["PersonalControlCenter"],
            path: "Tests",
            exclude: ["ModeReapplyTests.swift", "RefreshPulseTests.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
