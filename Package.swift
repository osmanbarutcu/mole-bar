// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoleBar",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "MoleBar",
            path: "Sources/MoleBar"
        )
    ]
)
