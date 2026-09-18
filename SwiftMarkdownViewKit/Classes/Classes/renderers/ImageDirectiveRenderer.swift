//
//  ImageDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/11.
//

import UIKit
import Markdown
import SDWebImage
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
    
    public func loadImage() {
       
        // 2) 内部用 SDWebImage 异步下载（带缓存），完成回调已在主线程。
        SDWebImageManager.shared.loadImage(with: url, options: [], progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self = self else {return}
            self.onLoadImage?(self, image)
            guard let image = image else {
                return
            }
            let d = ViewOption.defaultValue
            // 3) 更新自身 image / bounds（按最大宽度等比缩放）。
            self.image = image
            let w = min(self.viewOptions.maxWidth ?? d, max(image.size.width, self.viewOptions.minWidth ?? d))
            let h = image.size.height * (w / image.size.width)
            self.bounds = CGRect(x: 0, y: 0, width: floor(w), height: floor(h))
            self.onContentSizeChanged?(self.bounds.size)
        }
        self.onStreamingFinished?()
    }
    
}
public protocol ImageDirectiveRenderer {
    var title: String { get }
    func renderView(image: Image, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable?
    func renderAttr(image: Image, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?
    func render(_ image: Image, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString
}
public extension ImageDirectiveRenderer {
    public func renderView(image: Image, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable? {
        return nil
    }
    public func renderAttr(image: Image, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString? {
        return nil
    }
    public func render(_ image: Image, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString {
        if let attributed = renderAttr(image: image, visitor: visitor) {
            return attributed
        }else {
            let attachment = BaseAttachment(markup: MarkupContext(markup: image, visitor: visitor), viewBlock: {
            let view = renderView(image: image, visitor: visitor)
                return view ?? PlaceholdView()
            })
            let attributed = NSAttributedString(attachment: attachment)
            return attributed
        }
    }
}
public struct ImageDirective: ImageDirectiveRenderer {
    public var title: String = ""
    public func renderView(image: Image, visitor: MarkdownAttributedStringBuilder) -> (any ViewLoadable)? {
        let url = image.source.flatMap { URL(string: $0) }
        let img = ImageView(url: url)
        return img
    }
}
