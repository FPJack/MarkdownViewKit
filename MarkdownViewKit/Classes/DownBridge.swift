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
            
            let segments = MarkdownTableParser.parseSegments(markdown)
            
            
            // 2) 逐段渲染并拼接。
            let result = NSMutableAttributedString()
            
            let newlineAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16)]

            for segment in segments {
                switch segment {
                case .text(let text):
                    // 文本段：交给 Down 渲染。
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let down = Down(markdownString: text)
                    do {
                        let attributedText = try down.toAttributedString(styler: styler)
                        result.append(attributedText)
                    } catch {
                        // 渲染失败时，直接把原始文本附加上去。
                        result.append(NSAttributedString(string: text))
                    }
                case .table(let table):
                    // 优先使用外部传入的表格配置；未
                    let attachment = GridTableAttachment(rows: table, configuration: GridTableConfiguration())
                    // 表格自成一块，前后补换行，保证独占段落。
                    if result.length > 0 { result.append(NSAttributedString(string: "\n", attributes: newlineAttrs)) }
                    result.append(NSAttributedString(attachment: attachment))
                    result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                }
            }
            
            guard result.length > 0 else {
                complete(nil)
                return
            }
            
            
          let res = self.processImages(in: result) ?? result

          complete(res)
            
            
          
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
