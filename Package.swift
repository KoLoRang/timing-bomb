// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Tests are kept locally and are not included in source distributions.
// Use an explicit environment flag because SwiftPM caches manifest results
// and does not invalidate them when a local test directory is added or removed.
let includeLocalTests = ProcessInfo.processInfo.environment["TIMINGBOMB_INCLUDE_TESTS"] == "1"
let localTestTargets: [Target] = [
    .testTarget(
        name: "TimingBombCoreTests",
        dependencies: ["TimingBombCore", "TimingBombL10n"]),
    .testTarget(
        name: "TimingBombRunnerTests",
        dependencies: ["TimingBombRunner", "TimingBombL10n", "jsrunner"]),
    .testTarget(
        name: "TimingBombDaemonTests",
        dependencies: ["TimingBombDaemon", "TimingBombL10n"]),
]

let package = Package(
    name: "timing-bomb",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "TimingBombL10n"),
        .target(
            name: "TimingBombCore",
            dependencies: [
                .product(name: "GRDB", package: "grdb.swift"),
                "TimingBombL10n",
            ]),
        .target(name: "TimingBombRunner", dependencies: ["TimingBombCore", "TimingBombL10n"]),
        .target(
            name: "TimingBombDaemon",
            dependencies: ["TimingBombCore", "TimingBombRunner", "TimingBombL10n"]
        ),
        .executableTarget(name: "timingbombd", dependencies: ["TimingBombDaemon"]),
        .executableTarget(name: "jsrunner", dependencies: ["TimingBombRunner"]),
        .executableTarget(
            name: "TimingBombApp",
            dependencies: ["TimingBombCore", "TimingBombDaemon", "TimingBombL10n"]),
    ] + (includeLocalTests ? localTestTargets : []),
    swiftLanguageModes: [.v5]
)
