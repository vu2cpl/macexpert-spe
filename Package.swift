// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacExpert",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacExpert", targets: ["MacExpert"]),
    ],
    dependencies: [
        .package(url: "https://github.com/armadsen/ORSSerialPort.git", from: "2.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacExpert",
            dependencies: [
                .product(name: "ORSSerial", package: "ORSSerialPort"),
            ],
            path: "MacExpert",
            exclude: ["Resources/Assets.xcassets"],
            resources: [
                .copy("Resources/ExpertIcon.icns"),
            ]
        ),
    ]
)
