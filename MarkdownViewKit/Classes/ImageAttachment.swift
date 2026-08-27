//
//  ImageAttachment.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit
import SDWebImage

/// 自定义 NSTextAttachment：内部用 SDWebImage 下载网络图片，
/// 下载完成后自动更新自身 image / bounds，并回调通知外部刷新 UI。
///

@objcMembers
public class ImageAttachmentOptions: NSObject {
    /// 图片显示的最大宽度（按比例缩放）。<=0 表示不限制。
    public var maxImageWidth: CGFloat = 300

    /// 下载前占位高度（预留排版空间），默认 120。
    public var placeholderHeight: CGFloat = 120

    /// 图片下载完成（成功）后回调，外部据此刷新对应区域 / 高度。
    public var onImageLoaded: ((ImageAttachment) -> Void)?
    
    /// 图片被点击后回调，外部据此做预览 / 跳转等操作。
    public var onImageTapped: ((ImageAttachment, [ImageAttachment]) -> Void)?
}


@objcMembers
public class ImageAttachment: NSTextAttachment {

    /// 网络图片地址。
    public var imageURLString: String?
    
    public var options: ImageAttachmentOptions

    public var range: NSRange = NSRange(location: 0, length: 0)
    
    private var imageLoaded = false
    
    var onImageLoaded: ((ImageAttachment) -> Void)? {
        didSet {
            if imageLoaded {
                if let onImageLoaded = onImageLoaded {
                    onImageLoaded(self)
                }
            }
        }
    }

    
    init(imageURLString: String? = nil, options: ImageAttachmentOptions) {
        self.imageURLString = imageURLString
        self.options = options
        super.init(data: nil, ofType: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 开始异步下载图片（会先设置占位图，完成后替换并回调）。
    public func loadImage() {
        // 1) 先放一个占位图，保证排版预留空间。
        let placeholderWidth = options.maxImageWidth > 0 ? options.maxImageWidth : 200
        if image == nil {
            image = ImageAttachment.placeholderImage(of: CGSize(width: placeholderWidth, height: options.placeholderHeight))
            bounds = CGRect(x: 0, y: 0, width: placeholderWidth, height: options.placeholderHeight)
        }

        guard let urlString = imageURLString, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }

        // 2) 内部用 SDWebImage 异步下载（带缓存），完成回调已在主线程。
        SDWebImageManager.shared.loadImage(with: url, options: [], progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self = self, let image = image else { return }

            // 3) 更新自身 image / bounds（按最大宽度等比缩放）。
            self.image = image
            let w = options.maxImageWidth > 0 ? min(image.size.width, options.maxImageWidth) : image.size.width
            let h = image.size.width > 0 ? image.size.height * (w / image.size.width) : image.size.height
            self.bounds = CGRect(x: 0, y: 0, width: floor(w), height: floor(h))
            self.imageLoaded = true
            // 4) 通知外部刷新。
            options.onImageLoaded?(self)
            self.onImageLoaded?(self)
        }
    }

    /// 生成一个纯色占位图，用于图片下载前预留空间。
    private static func placeholderImage(of size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor(white: 0.92, alpha: 1.0).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

