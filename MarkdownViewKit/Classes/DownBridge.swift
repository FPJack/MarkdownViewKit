//
//  DownBridge.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit
import Down
/// Markdown 渲染配置：除 markdown 字符串外的所有参数都收拢到这个对象里。
@objcMembers
public class MarkdownRenderOptions: NSObject {
    
    public var imageOptions: ImageAttachmentOptions = ImageAttachmentOptions()
    
    /// 点击到链接时回调（参数为链接 URL）。
    public var onLinkTapped: ((URL) -> Void)?
}


@objcMembers
public class DownBridge: NSObject {
    var options: MarkdownRenderOptions = MarkdownRenderOptions()
    
    public func attributedString(
        fromMarkdown markdown: String,
        options: MarkdownRenderOptions,
        complete:@escaping (NSAttributedString?) -> Void)  {
            let styler = CustomStyle()
            styler.imageOptions = options.imageOptions
            self.options = options
            DispatchQueue.global().async {
                let down = Down(markdownString: markdown)
                DispatchQueue.main.async {
                    do {
                        var attributedString = try down.toAttributedString(styler: styler)
                        attributedString = self.processImages(in: attributedString) ?? attributedString
                        DispatchQueue.main.async {
                            complete(attributedString)
                        }
                    } catch {
                        complete(nil)
                    }
                }
            }
    }
    
    public  func processImages(in attributedText: NSAttributedString) -> NSAttributedString? {
        
        let mutableAttributedText = NSMutableAttributedString(attributedString: attributedText)
        
        let fullRange = NSRange(location: 0, length: mutableAttributedText.length)
        
        mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let attachment = value as? ImageAttachment {
                attachment.range = range
                attachment.loadImage()
            }
        }
        return mutableAttributedText
    }
    @MainActor
    @discardableResult
    public func bindGestures(to textView: UITextView) -> TapGesture? {
        // 先移除旧的同名手势（连带释放其持有的旧 manager），避免重复绑定。
        textView.gestureRecognizers?
            .filter { $0.name == TapGesture.gestureName }
            .forEach { textView.removeGestureRecognizer($0) }
        // 自动判断：没有任何点击回调时无需绑定。
        let manager = TapGesture(textView: textView)
        manager.onImageTapped = options.imageOptions.onImageTapped
        manager.onLinkTapped = options.onLinkTapped
        return manager
    }

}
