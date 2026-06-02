// swift-tools-version: 6.2
// ConduitKit — modular engines + features for the Conduit iOS app.
// Engines are platform-agnostic (no UIKit/SwiftUI). Features depend on engines.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // Emit warnings for expressions/functions that take too long to type-check.
    // Fix the flagged sites with explicit type annotations to improve incremental build times.
    .unsafeFlags([
        "-Xfrontend", "-warn-long-function-bodies=300",
        "-Xfrontend", "-warn-long-expression-type-checking=300",
    ], .when(configuration: .debug)),
]

let package = Package(
    name: "ConduitKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
        .watchOS(.v26),
    ],
    products: [
        // ── Engines (no UIKit) ───────────────────────────────────────────
        .library(name: "ConduitCore",      targets: ["ConduitCore"]),
        .library(name: "SecurityKit",      targets: ["SecurityKit"]),
        .library(name: "SSHTransport",     targets: ["SSHTransport"]),
        .library(name: "TerminalEngine",   targets: ["TerminalEngine"]),
        .library(name: "AgentKit",         targets: ["AgentKit"]),
        .library(name: "NotificationsKit", targets: ["NotificationsKit"]),
        .library(name: "PersistenceKit",   targets: ["PersistenceKit"]),
        .library(name: "DiffKit",          targets: ["DiffKit"]),
        .library(name: "SyncKit",          targets: ["SyncKit"]),

        // ── UI-bearing modules ───────────────────────────────────────────
        .library(name: "DesignSystem",      targets: ["DesignSystem"]),
        .library(name: "PreviewKit",        targets: ["PreviewKit"]),
        .library(name: "AppFeature",        targets: ["AppFeature"]),
        .library(name: "WorkspacesFeature", targets: ["WorkspacesFeature"]),
        .library(name: "SessionFeature",    targets: ["SessionFeature"]),
        .library(name: "InboxFeature",      targets: ["InboxFeature"]),
        .library(name: "SettingsFeature",   targets: ["SettingsFeature"]),
        .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
        .library(name: "KeysFeature",       targets: ["KeysFeature"]),
        .library(name: "DiffFeature",       targets: ["DiffFeature"]),
        .library(name: "PreviewFeature",    targets: ["PreviewFeature"]),
        .library(name: "FilesFeature",      targets: ["FilesFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.9.0"),
        // Community fork of apple/swift-nio-ssh used transitively by Citadel.
        // Key patches absent from upstream: Mac Catalyst NIO product dependency fix,
        // SSH certificate authentication, visionOS/Musl compiler directives.
        // Switch back to apple/swift-nio-ssh once Citadel migrates and upstream
        // absorbs the Mac Catalyst fix. Tracked in ARCHITECTURE.md §19.
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        // SwiftTerm — iOS-only UI dep, isolated to TerminalEngine
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        // ── Engines ──────────────────────────────────────────────────────
        .target(
            name: "ConduitCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SecurityKit",
            dependencies: ["ConduitCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SSHTransport",
            dependencies: [
                "ConduitCore",
                "SecurityKit",
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TerminalEngine",
            dependencies: [
                "ConduitCore",
                "SSHTransport",
                .product(name: "SwiftTerm", package: "SwiftTerm", condition: .when(platforms: [.iOS])),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AgentKit",
            dependencies: ["ConduitCore", "SecurityKit", "SSHTransport"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "NotificationsKit",
            dependencies: ["ConduitCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PersistenceKit",
            dependencies: [
                "ConduitCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiffKit",
            dependencies: ["ConduitCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SyncKit",
            dependencies: ["ConduitCore", "PersistenceKit", "SecurityKit"],
            swiftSettings: swiftSettings
        ),

        // ── UI-bearing ───────────────────────────────────────────────────
        .target(
            name: "DesignSystem",
            dependencies: ["ConduitCore"],
            resources: [.process("Resources")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PreviewKit",
            dependencies: ["SSHTransport", "DesignSystem"],
            swiftSettings: swiftSettings
        ),

        // Features (UI). Each feature is one-screen-deep + view models.
        .target(
            name: "OnboardingFeature",
            dependencies: ["DesignSystem", "SecurityKit", "NotificationsKit", "PersistenceKit", "SSHTransport", "AgentKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "WorkspacesFeature",
            dependencies: ["DesignSystem", "PersistenceKit", "SecurityKit", "SSHTransport"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SessionFeature",
            dependencies: [
                "DesignSystem", "TerminalEngine", "SSHTransport",
                "AgentKit", "PersistenceKit", "SecurityKit",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "InboxFeature",
            dependencies: ["DesignSystem", "AgentKit", "NotificationsKit", "PersistenceKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiffFeature",
            dependencies: ["DesignSystem", "DiffKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PreviewFeature",
            dependencies: ["DesignSystem", "PreviewKit", "SSHTransport", "ConduitCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "FilesFeature",
            dependencies: ["DesignSystem", "SSHTransport"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "KeysFeature",
            dependencies: ["DesignSystem", "SecurityKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SettingsFeature",
            dependencies: ["DesignSystem", "PersistenceKit", "AgentKit", "SecurityKit", "SyncKit", "KeysFeature"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AppFeature",
            dependencies: [
                "DesignSystem",
                "AgentKit",
                "PersistenceKit",
                "NotificationsKit",
                "WorkspacesFeature",
                "SessionFeature",
                "InboxFeature",
                "OnboardingFeature",
                "SettingsFeature",
                "DiffFeature",
                "PreviewFeature",
                "FilesFeature",
                "KeysFeature",
                "SyncKit",
            ],
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedFramework("WatchConnectivity", .when(platforms: [.iOS])),
            ]
        ),

        // ── Tests ────────────────────────────────────────────────────────
        .testTarget(
            name: "ConduitKitTests",
            dependencies: [
                "ConduitCore",
                "SecurityKit",
                "SSHTransport",
                "TerminalEngine",
                "AgentKit",
                "DiffKit",
                "PersistenceKit",
                "SyncKit",
                "PreviewKit",
                "SessionFeature",
                "SettingsFeature",
                "AppFeature",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
