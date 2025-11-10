// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .macOS(.v11),
        .iOS(.v17),
        .macCatalyst(.v17),
    ],

    products: [
        .library(
            name: "Logger",
            targets: ["Logger"]
        ),
    ],
    targets: [
        .target(name: "Logger"),
    ]
)
