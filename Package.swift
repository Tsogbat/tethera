// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tethera",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tethera", targets: ["Tethera"]),
        // Named apart from the app: `tethera` and `Tethera` collide on a case-insensitive disk.
        // Packaging installs it as Contents/Helpers/tethera.
        .executable(name: "tethera-cli", targets: ["TetheraCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1")
    ],
    targets: [
        // forkpty with signal reset, in C because Swift can't run safely between fork and exec.
        .target(name: "CPTY", path: "Sources/CPTY"),
        // Wire protocol, models, shell launch: shared by the app, the CLI and the daemon.
        .target(name: "TetheraKit", path: "Sources/TetheraKit"),
        // The session daemon: owns every PTY so sessions outlive the app.
        .target(
            name: "TetheraDaemon",
            dependencies: ["TetheraKit", "CPTY", "SwiftTerm"],
            path: "Sources/TetheraDaemon"
        ),
        .executableTarget(
            name: "TetheraCLI",
            dependencies: ["TetheraKit", "TetheraDaemon"],
            path: "Sources/TetheraCLI"
        ),
        .executableTarget(
            name: "Tethera",
            dependencies: ["SwiftTerm", "TetheraKit"],
            path: "Tethera",
            exclude: [
                "Info.plist",
                "Preview Content"
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Fonts"),
                .copy("Resources/Brand"),
                .copy("Resources/Symbols")
            ]
        ),
        .testTarget(
            name: "TetheraTests",
            dependencies: ["Tethera", "TetheraKit", "TetheraDaemon"],
            path: "Tests/TetheraTests"
        )
    ]
)
