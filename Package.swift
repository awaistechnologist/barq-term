// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Barq",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Barq",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Barq"
        ),
        .executableTarget(
            name: "barq-mcp",
            path: "Sources/BarqMCP"
        ),
        .testTarget(
            name: "BarqTests",
            dependencies: ["Barq"],
            path: "Tests/BarqTests"
        )
    ]
)
