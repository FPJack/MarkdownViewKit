// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "MarkdownViewKit",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "MarkdownViewKit",
            targets: ["MarkdownViewKit"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/johnxnguyen/Down.git",
            from: "0.11.0"
        ),
        .package(
            url: "https://github.com/SDWebImage/SDWebImage.git",
            from: "5.21.7"
        ),
        .package(
            url: "https://github.com/JohnSundell/Splash.git",
            from: "0.16.0"
        )
    ],
    targets: [
        .target(
            name: "MarkdownViewKit",
            dependencies: [
                .product(name: "Down", package: "Down"),
                .product(name: "SDWebImage", package: "SDWebImage"),
                .product(name: "Splash", package: "Splash")
            ],
            path: "MarkdownViewKit/Classes"
        )
    ],
    swiftLanguageVersions: [.v5]
)
