// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Chatty",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "Chatty",
            dependencies: ["SwiftTerm", "Yams"],
            path: "src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
