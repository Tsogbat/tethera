// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Terminal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Terminal",
            targets: ["Terminal"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Terminal",
            dependencies: ["SwiftTerm"],
            path: "Terminal",
            sources: [
                "TerminalApp.swift",
                "ContentView.swift", 
                "TerminalSession.swift",
                "TerminalBuffer.swift",
                "TerminalView.swift",
                "MetalRenderer.swift",
                "SimpleTerminalView.swift"
            ],
            resources: [
                .process("Shaders.metal"),
                .process("Assets.xcassets")
            ]
        )
    ]
)
