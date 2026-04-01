// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iPhotoManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "iPhotoManager", targets: ["iPhotoManager"])
    ],
    targets: [
        .executableTarget(
            name: "iPhotoManager",
            path: "iPhotoManager",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
