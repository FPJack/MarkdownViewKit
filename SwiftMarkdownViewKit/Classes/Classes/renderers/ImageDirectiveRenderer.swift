//
//  ImageDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/11.
//

import UIKit
import Markdown
import SDWebImage
import SDWebImageSVGCoder
import Kingfisher
/// SVG 解码器注册。
///
/// `SDWebImageSVGCoder` 虽然被声明为依赖，但**必须显式注册**到
/// `SDImageCodersManager` 才会生效，否则所有 `.svg` 图片都会静默加载失败
/// （回调拿到的 image 为 nil，界面上什么都不显示）。
///
/// 用 `static let` 保证全进程只注册一次，且线程安全（Swift 的全局 / 静态
/// 属性初始化本身就是 lazy + once 的）。
private enum MarkdownImageCoders {
    static let registerOnce: Void = {
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
    }()
}

public class ImageView: UIImageView,ViewLoadable {
    public func updateData(data: MarkupContext<Markdown.Image>) {
        loadImage()
    }
    
    public func startStreaming(data: MarkupContext<Markdown.Image>, animation: Bool) {
        loadImage()
    }
    
    public func estimatedSize(for data: MarkupContext<Markdown.Image>) -> CGSize {
        viewOptions.estimedSize ?? .zero
    }
    
    
    public typealias MarkupType = Image
    public var viewOptions: ViewOption = ViewOption()
    
    public var onLoadImage: ((ImageView,UIImage?) -> Void)? = nil
    let url: URL?
    init(url: URL?) {
        self.url = url
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var onContentSizeChanged: ((CGSize) -> Void)?
    
    public var onStreamingFinished: (() -> Void)?

    /// 容器可用宽度变化（横竖屏 / 分屏）时，按新宽度重新等比缩放。
    public func updateViewOptions(_ options: ViewOption) {
        applyImageSizing(with: options)
    }
    public func attachmentContentInset() -> UIEdgeInsets {
        .zero
    }

    /// 按给定的宽度约束等比缩放当前图片，并在尺寸变化时上报。
    ///
    /// 图片未加载完成时直接返回——加载完成后 `loadImage` 会再调一次。
    private func applyImageSizing(with options: ViewOption) {
        guard let image = image, image.size.width > 0 else { return }
        let d = ViewOption.defaultValue
        let w = min(options.maxWidth ?? d, max(image.size.width, options.minWidth ?? d))
        let h = image.size.height * (w / image.size.width)
        let newBounds = CGRect(x: 0, y: 0, width: floor(w), height: floor(h))
        guard newBounds != bounds else { return }
        bounds = newBounds
        onContentSizeChanged?(bounds.size)
    }
    
    public func loadImage() {
        // 0) 确保 SVG 解码器已注册（全进程只会真正执行一次）。
        _ = MarkdownImageCoders.registerOnce

        // 2) 内部用 SDWebImage 异步下载（带缓存），完成回调已在主线程。
        SDWebImageManager.shared.loadImage(with: url, options: [], progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self = self else {return}
            self.onLoadImage?(self, image)
            guard let image = image else {
                return
            }
            // 3) 更新自身 image / bounds（按最大宽度等比缩放）。
            self.image = image
            self.applyImageSizing(with: self.viewOptions)
        }
        self.onStreamingFinished?()
    }
    
}
public protocol ImageDirectiveRenderer: DirectiveRenderer {
    typealias MarkupType = Image
    var title: String { get }
}

public struct ImageDirective: ImageDirectiveRenderer {
    public var viewType: any ViewLoadable.Type {
        ImageView.self
    }
    
    public var title: String = ""
    public func renderView(context: MarkupContext<Image>) -> (any ViewLoadable)? {
        let url = context.markup.source.flatMap { URL(string: $0) }
        let img = ImageView(url: url)
        return img
    }
}
