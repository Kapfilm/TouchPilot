// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchPilot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TouchPilot", targets: ["TouchPilot"])
    ],
    targets: [
        .executableTarget(
            name: "TouchPilot",
            path: "Sources/TouchPilot",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "TouchPilotTests",
            dependencies: ["TouchPilot"],
            path: "Tests/TouchPilotTests"
        )
    ]
)
