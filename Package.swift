// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "sdi.coach",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "sdi.coach", targets: ["SDICoach"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-testing", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "SDICoach",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/SDICoach"
        ),
        .testTarget(
            name: "SDICoachTests",
            dependencies: [
                "SDICoach",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/SDICoachTests"
        )
    ]
)
