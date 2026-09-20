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

        // 图片加载 / 缓存。
        .package(
            url: "https://github.com/onevcat/Kingfisher.git",
            from: "8.6.0"
        ),

        // 仅用于 SVG 解码。
        //
        // Kingfisher 不支持 SVG，而 Markdown 里的徽章（shields.io）、图标等大量
        // 使用 SVG，因此保留这个 coder，由 `MarkdownSVGProcessor` 调用。
        // 它只做「Data -> UIImage」的纯解码，不参与任何网络请求与缓存。
        //
        // 若业务方不需要 SVG，可直接删掉这条依赖：代码用 `canImport` 包住了，
        // 删除后仍能正常编译（届时如需 SVG，自行实现 `MarkdownSVGProcessor.decoder`）。
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
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "SDWebImageSVGCoder", package: "SDWebImageSVGCoder"),
                .product(name: "Splash", package: "Splash")
            ],
            path: "SwiftMarkdownViewKit/Classes"
        )
    ],
    swiftLanguageVersions: [.v5]
)
