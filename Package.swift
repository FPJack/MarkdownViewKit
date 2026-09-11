// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SwiftMarkdownViewKit",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftMarkdownViewKit",
            targets: ["SwiftMarkdownViewKit"]
        )
    ],
    dependencies: [
       
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git", 
            from: "0.7.3"
        ),

        .package(
            url: "https://github.com/SDWebImage/SDWebImage.git",
            from: "5.21.7"
        ),
        .package(
            url: "https://github.com/SDWebImage/SDWebImageSVGCoder.git",
            from: "1.7.0"
        ),
        .package(
            url: "https://github.com/JohnSundell/Splash.git",
            from: "0.16.0"
        )
    ],
    targets: [
        .target(
            name: "SwiftMarkdownViewKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SDWebImage", package: "SDWebImage"),
                .product(name: "SDWebImageSVGCoder", package: "SDWebImageSVGCoder"),
                .product(name: "Splash", package: "Splash")
            ],
            path: "SwiftMarkdownViewKit/Classes"
        )
    ],
    swiftLanguageVersions: [.v5]
)
