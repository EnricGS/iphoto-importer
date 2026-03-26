// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iPhotoViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "iPhotoViewer", targets: ["iPhotoViewer"])
    ],
    targets: [
        .executableTarget(
            name: "iPhotoViewer",
            path: "iPhotoViewer",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
