// swift-tools-version: 6.2
// LancerKit — modular engines + features for the Lancer iOS app.
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
    name: "LancerKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
        .watchOS(.v26),
    ],
    products: [
        // ── Engines (no UIKit) ───────────────────────────────────────────
        .library(name: "LancerCore",      targets: ["LancerCore"]),
        .library(name: "SecurityKit",      targets: ["SecurityKit"]),
        .library(name: "AccountKit",       targets: ["AccountKit"]),
        .library(name: "SSHTransport",     targets: ["SSHTransport"]),
        .library(name: "TerminalEngine",   targets: ["TerminalEngine"]),
        .library(name: "AgentKit",         targets: ["AgentKit"]),
        .library(name: "NotificationsKit", targets: ["NotificationsKit"]),
        .library(name: "PersistenceKit",   targets: ["PersistenceKit"]),
        .library(name: "DiffKit",          targets: ["DiffKit"]),
        .library(name: "SyncKit",          targets: ["SyncKit"]),
        .library(name: "HostControlKit",   targets: ["HostControlKit"]),
        .library(name: "IntentsKit",       targets: ["IntentsKit"]),

        // ── UI-bearing modules ───────────────────────────────────────────
        .library(name: "DesignSystem",      targets: ["DesignSystem"]),
        .library(name: "PreviewKit",        targets: ["PreviewKit"]),
        .library(name: "AppFeature",        targets: ["AppFeature"]),
        .library(name: "WorkspacesFeature", targets: ["WorkspacesFeature"]),
        .library(name: "SessionFeature",    targets: ["SessionFeature"]),
        .library(name: "InboxFeature",      targets: ["InboxFeature"]),
        .library(name: "SettingsFeature",   targets: ["SettingsFeature"]),
        .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
        .library(name: "DiffFeature",       targets: ["DiffFeature"]),
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
            name: "LancerCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SecurityKit",
            dependencies: [
                "LancerCore",
                .product(name: "Citadel", package: "Citadel"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AccountKit",
            dependencies: ["LancerCore", "SecurityKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SSHTransport",
            dependencies: [
                "LancerCore",
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
                "LancerCore",
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
            dependencies: ["LancerCore", "SecurityKit", "SSHTransport"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "NotificationsKit",
            dependencies: ["LancerCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PersistenceKit",
            dependencies: [
                "LancerCore",
                "AgentKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiffKit",
            dependencies: ["LancerCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SyncKit",
            dependencies: ["LancerCore", "PersistenceKit", "SecurityKit", "NotificationsKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "HostControlKit",
            dependencies: ["LancerCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "IntentsKit",
            dependencies: ["LancerCore", "PersistenceKit", "SSHTransport"],
            swiftSettings: swiftSettings
        ),

        // ── UI-bearing ───────────────────────────────────────────────────
        .target(
            name: "DesignSystem",
            dependencies: ["LancerCore"],
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
            dependencies: ["DesignSystem", "SecurityKit", "AccountKit", "NotificationsKit", "PersistenceKit", "SSHTransport", "AgentKit"],
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
                "LancerCore",
                "DesignSystem", "TerminalEngine", "SSHTransport",
                "AgentKit", "PersistenceKit", "SecurityKit", "NotificationsKit",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "InboxFeature",
            dependencies: [
                "DesignSystem",
                "AgentKit",
                "NotificationsKit",
                "PersistenceKit",
                "DiffKit",
                "DiffFeature",
                "SSHTransport",
                "SecurityKit",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiffFeature",
            dependencies: ["DesignSystem", "DiffKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "FilesFeature",
            dependencies: ["DesignSystem", "SSHTransport"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SettingsFeature",
            dependencies: [
                "LancerCore",
                "AccountKit",
                "DesignSystem",
                "PersistenceKit",
                "AgentKit",
                "SecurityKit",
                "SyncKit",
                "NotificationsKit",
                "SSHTransport",
            ],
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
                "DiffKit",
                "PreviewKit",
                "SSHTransport",
                "FilesFeature",
                "SyncKit",
            ],
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedFramework("WatchConnectivity", .when(platforms: [.iOS])),
                .linkedFramework("WebKit", .when(platforms: [.iOS])),
            ]
        ),

        // ── Tests ────────────────────────────────────────────────────────
        .testTarget(
            name: "LancerKitTests",
            dependencies: [
                "LancerCore",
                "AccountKit",
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
                "DesignSystem",
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HostControlKitTests",
            dependencies: ["HostControlKit", "LancerCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "IntentsKitTests",
            dependencies: ["IntentsKit", "LancerCore", "PersistenceKit", "SSHTransport", "SessionFeature"],
            swiftSettings: swiftSettings
        ),
    ]
)
