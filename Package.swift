// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tethera",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Tethera",
            targets: ["Tethera"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Tethera",
            dependencies: ["SwiftTerm"],
            path: "Terminal",
            sources: [
                "TerminalApp.swift",
                "ContentView.swift",
                "TerminalSession.swift",
                "TerminalBuffer.swift",
                "TerminalView.swift",
                "MetalRenderer.swift",
                "SimpleTerminalView.swift",
                "BlockTerminalView.swift",
                "BlockTerminalViewModel.swift",
                "TerminalBlock.swift",
                "TerminalTheme.swift",
                "CommandPaletteView.swift",
                "TerminalSettingsView.swift",
                "FontLoader.swift"
            ],
            resources: [
                .process("Shaders.metal"),
                .process("Assets.xcassets"),
                .process("Fonts") 
            ]
        )
    ]
)
