//
//  ImageView.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/9/7.
//

import UIKit
import SDWebImage

public class ImageView:UIImageView,ViewLoadable {
    private var url: String? = nil
    
    public static func regxRule() -> RegxRule {
        return RegxRule(pattern: "\\[image:(.*?)\\]", options: .caseInsensitive)
    }
    
    public var onContentSizeChanged: ((CGSize) -> Void)? = nil
    
    public var onStreamingFinished: (() -> Void)? = nil
    
    public func updateData(data: TextMatch) {
        self.url = data.content
        loadImage()
    }
    
    public func startStreaming(data: TextMatch, animation: Bool) {
        self.url = data.content
        loadImage()
    }
    
    public func estimatedSize(for data: TextMatch) -> CGSize {
        return CGSize(width: 100, height: 100)
    }
    
    public func loadImage() {
        let maxImageWidth: CGFloat = 290
       
        guard let urlString = url, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        
        // 2) 内部用 SDWebImage 异步下载（带缓存），完成回调已在主线程。
        SDWebImageManager.shared.loadImage(with: url, options: [], progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self = self else {return}
            guard let image = image else {
                return
            }

            // 3) 更新自身 image / bounds（按最大宽度等比缩放）。
            self.image = image
            let w = maxImageWidth > 0 ? min(image.size.width, maxImageWidth) : image.size.width
            let h = image.size.width > 0 ? image.size.height * (w / image.size.width) : image.size.height
            self.bounds = CGRect(x: 0, y: 0, width: floor(w), height: floor(h))
            self.onContentSizeChanged?(self.bounds.size)
        }
        self.onStreamingFinished?()
    }
}
