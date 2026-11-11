// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoleBar",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "MoleBar",
            path: "Sources/MoleBar"
        ),
        .testTarget(
            name: "MoleBarTests",
            dependencies: ["MoleBar"],
            path: "Tests/MoleBarTests",
            // Fixture dosyaları #filePath ile okunur. Paket kaynağı değildir.
            exclude: ["Fixtures"]
        )
    ]
)
