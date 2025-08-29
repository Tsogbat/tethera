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
            path: "Tethera",
            resources: [
                .process("Core/Shaders.metal"),
                .process("Assets.xcassets"),
                .process("Fonts") 
            ]
        )
    ]
)
