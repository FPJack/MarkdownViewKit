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
    
    public func updateData(data: TextMatch) {
        loadImage()
    }
    
    public func startStreaming(data: TextMatch, animation: Bool) {
        loadImage()
    }
    
    public func estimatedSize(for data: TextMatch) -> CGSize {
        viewOptions.estimedSize
    }
    
    public func convertTextMatch(_ markdownView: UIView, match: TextMatch) -> TextMatch {
        match
    }
    
    
    public func loadImage() {
       
        // 2) 内部用 SDWebImage 异步下载（带缓存），完成回调已在主线程。
        SDWebImageManager.shared.loadImage(with: url, options: [], progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self = self else {return}
            self.onLoadImage?(self, image)
            guard let image = image else {
                return
            }
            // 3) 更新自身 image / bounds（按最大宽度等比缩放）。
            self.image = image
            let w = min(self.viewOptions.maxWidth, max(image.size.width, self.viewOptions.minWidth))
            let h = image.size.height * (w / image.size.width)
            self.bounds = CGRect(x: 0, y: 0, width: floor(w), height: floor(h))
            self.onContentSizeChanged?(self.bounds.size)
        }
        self.onStreamingFinished?()
    }
}
public protocol ImageDirectiveRenderer {
    func render(_ image: Image, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString
}
public struct ImageDirective: ImageDirectiveRenderer {
    public func render(_ image: Image, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString {
        let url = image.source.flatMap { URL(string: $0) }
        let attachment = BaseAttachment {
            print("创建view")
            return ImageView(url: url)
        }
        let attributed = NSMutableAttributedString(attachment: attachment)
        return attributed
    }
}
