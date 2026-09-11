//
//  AsyncImageTextAttachment.swift
//  MarkdownKit
//
//  支持异步下载 + 内存缓存的图片附件。图片加载完成后自动通知宿主刷新排版，
//  并根据文本容器宽度等比缩放，保证图文混排的正确显示。
//

import UIKit

/// 简单的图片内存缓存，避免同一张图片重复下载。
final class MarkdownImageCache {
    static let shared = MarkdownImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() {}

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// 异步加载网络图片的 `NSTextAttachment`。
///
/// - 加载前使用占位尺寸；
/// - 通过重写 `attachmentBounds` 按文本容器宽度等比缩放；
/// - 加载完成后调用 `onImageLoaded` 让宿主刷新布局。
public final class AsyncImageTextAttachment: NSTextAttachment {

    /// 图片地址。
    public let url: URL?
    /// 占位高度（未加载完成时）。
    public var placeholderHeight: CGFloat
    /// 图片加载完成回调，用于触发文本重新排版。
    public var onImageLoaded: (() -> Void)?

    private var isLoading = false

    public init(url: URL?, placeholderHeight: CGFloat) {
        self.url = url
        self.placeholderHeight = placeholderHeight
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        self.url = nil
        self.placeholderHeight = 180
        super.init(coder: coder)
    }

    /// 开始异步加载（若尚未加载）。可安全重复调用。
    public func startLoadingIfNeeded() {
        guard image == nil, !isLoading, let url else { return }

        if let cached = MarkdownImageCache.shared.image(for: url) {
            image = cached
            onImageLoaded?()
            return
        }

        isLoading = true
        Task { [weak self] in
            guard let data = await Self.fetchData(url) else {
                self?.isLoading = false
                return
            }
            guard let self, let loaded = UIImage(data: data) else {
                self?.isLoading = false
                return
            }
            MarkdownImageCache.shared.store(loaded, for: url)
            self.image = loaded
            self.isLoading = false
            self.onImageLoaded?()
        }
    }

    /// 在后台线程下载图片数据（`Data` 可安全跨隔离域传递）。
    private nonisolated static func fetchData(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }

    public override func attachmentBounds(for textContainer: NSTextContainer?,
                                          proposedLineFragment lineFrag: CGRect,
                                          glyphPosition position: CGPoint,
                                          characterIndex charIndex: Int) -> CGRect {
        let maxWidth = availableWidth(textContainer: textContainer, lineFragment: lineFrag)

        guard let image, image.size.width > 0 else {
            return CGRect(x: 0, y: 0, width: maxWidth, height: placeholderHeight)
        }

        let aspect = image.size.height / image.size.width
        let width = min(image.size.width, maxWidth)
        return CGRect(x: 0, y: 0, width: width, height: width * aspect)
    }

    private func availableWidth(textContainer: NSTextContainer?, lineFragment: CGRect) -> CGFloat {
        if let container = textContainer {
            let inset = container.lineFragmentPadding * 2
            let width = container.size.width - inset
            if width > 0 { return width }
        }
        return lineFragment.width > 0 ? lineFragment.width : 300
    }
}
