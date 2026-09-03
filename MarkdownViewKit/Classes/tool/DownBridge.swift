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
    
    ///down 库配置
    public var downOptions: DownStylerConfiguration = makeConfiguration(fontSize: 15, textColor: .black)
    
    ///图片配置
    public var imageOptions: ImageAttachmentOptions = ImageAttachmentOptions()
    
    ///表格配置
    public var tableOptions: GridTableOptions = GridTableOptions()

//    /// 视频占位块（`[video:URL]`）配置。
//    @available(iOS 13.0, *)
//    public var videoOptions: VideoOption {
//        get { _videoOptions as? VideoOption ?? VideoOption() }
//        set { _videoOptions = newValue }
//    }
//    private var _videoOptions: Any = {
//        if #available(iOS 13.0, *) { return VideoOption() }
//        return NSNull()
//    }()
//
//    /// 音乐占位块（`[music:URL]`）配置。
//    @available(iOS 13.0, *)
//    public var musicOptions: MusicOption {
//        get { _musicOptions as? MusicOption ?? MusicOption() }
//        set { _musicOptions = newValue }
//    }
//    private var _musicOptions: Any = {
//        if #available(iOS 13.0, *) { return MusicOption() }
//        return NSNull()
//    }()
//
//
//    /// Web 渲染块（mermaid / echarts /Latex公式等）配置。
//    @available(iOS 13.0, *)
//    public var webOptions: WebViewOption {
//        get { _webOptions as? WebViewOption ?? WebViewOption() }
//        set { _webOptions = newValue }
//    }
//    private var _webOptions: Any = {
//        if #available(iOS 13.0, *) { return WebViewOption() }
//        return NSNull()
//    }()
    
    /// 点击到链接时回调（参数为链接 URL）。
    public var onLinkTapped: ((URL) -> Void)?
}


@objcMembers
public class DownBridge: NSObject {
    
    private var customViewDelegate: CustomViewDelegate? {
        markdownView?.customViewDelegate
    }

    
    var options: MarkdownRenderOptions = MarkdownRenderOptions()
    
    lazy var renderAttachment: RenderAttachment = RenderAttachment(markdownView: markdownView)
    
    weak var markdownView: MarkdownView?
    
    public init( markdownView: MarkdownView) {
        self.markdownView = markdownView
    }
    
    var originMarkdown: String = ""
    
    public func appendAttributedString(
        fromMarkdown markdown: String,
        complete:@escaping (NSAttributedString?) -> Void)  {
        let newMarkdown = originMarkdown + markdown
        attributedString(fromMarkdown: newMarkdown, options: options, complete: complete)
    }
    
    public func attributedString(
        fromMarkdown markdown: String,
        options: MarkdownRenderOptions,
        complete:@escaping (NSAttributedString?) -> Void)  {
           
            
            DispatchQueue.global().async {[weak self] in
                
                self?.originMarkdown = markdown
                let styler = CustomStyle(configuration: options.downOptions)
                styler.codeBlockMatches = RegxParser.matchCodeBlocks(in: markdown)
                self?.options = options
                
                // 2) 逐段渲染并拼接。
                let result = NSMutableAttributedString()
                let down = Down(markdownString: markdown)
                let attributedText = try? down.toAttributedString([.hardBreaks],styler: styler)
                result.append(attributedText!)
                DispatchQueue.main.async {[weak self] in
                    guard result.length > 0 else {
                        complete(nil)
                        return
                    }
                    let res =  self?.renderAttachment.renderAttachment(attributedText, options: options)
                    if let res = res {
                        _ = self?.handleAttachments(in: res)
                    }
                    complete(res)
                }
            }
    }
    
    public  func handleAttachments(in attributedText: NSAttributedString) -> NSAttributedString? {
        let mutableAttributedText = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: mutableAttributedText.length)
        mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let attachment = value as? ImageAttachment {
                attachment.range = range
                attachment.loadImage()
            } else if let attachment = value as? AttachmentLoadable {
                attachment.range = range
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
/// 构建 Down 的样式配置（字体 / 颜色 / 段落样式 / 代码块选项）。
private  func makeConfiguration(fontSize: CGFloat, textColor: UIColor) -> DownStylerConfiguration {
    var fonts = StaticFontCollection()
    fonts.body = UIFont.systemFont(ofSize: fontSize)
    fonts.heading1 = UIFont.boldSystemFont(ofSize: fontSize + 12)
    fonts.heading2 = UIFont.boldSystemFont(ofSize: fontSize + 9)
    fonts.heading3 = UIFont.boldSystemFont(ofSize: fontSize + 6)
    fonts.heading4 = UIFont.boldSystemFont(ofSize: fontSize + 4)
    fonts.heading5 = UIFont.boldSystemFont(ofSize: fontSize + 2)
    fonts.heading6 = UIFont.boldSystemFont(ofSize: fontSize)
    // 行内代码 + 代码块的字体（等宽字体）。
    fonts.code = UIFont(name: "Menlo", size: fontSize - 1) ?? UIFont.systemFont(ofSize: fontSize - 1)

    var colors = StaticColorCollection()
    colors.body = textColor
    colors.heading1 = textColor
    colors.heading2 = textColor
    colors.heading3 = textColor
    // 代码文字颜色 + 代码块背景色（背景色由 codeBlockBackground 控制）。
    colors.code = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1.0) // 深红色
    colors.codeBlockBackground = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1) // 浅灰蓝色

    // 代码块段落样式：行距、首行/整体缩进。
    var paragraphStyles = StaticParagraphStyleCollection()
    let codeParagraph = NSMutableParagraphStyle()
    codeParagraph.lineSpacing = 10
    codeParagraph.paragraphSpacingBefore = 6
    codeParagraph.paragraphSpacing = 6
    codeParagraph.firstLineHeadIndent = 8
    codeParagraph.headIndent = 8
    codeParagraph.tailIndent = -8
    paragraphStyles.code = codeParagraph
    
    // 标题段落样式：加大标题上下间距。
    let makeHeadingStyle: (CGFloat, CGFloat) -> NSParagraphStyle = { before, after in
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before   // 标题前留白
        style.paragraphSpacing = after          // 标题后留白
        style.lineSpacing = after
        return style
    }
    paragraphStyles.heading1 = makeHeadingStyle(24, 12)
    paragraphStyles.heading2 = makeHeadingStyle(20, 10)
    paragraphStyles.heading3 = makeHeadingStyle(16, 8)
    paragraphStyles.heading4 = makeHeadingStyle(14, 8)
    paragraphStyles.heading5 = makeHeadingStyle(12, 6)
    paragraphStyles.heading6 = makeHeadingStyle(12, 6)

    // 代码块背景容器的内边距。
    let codeBlockOptions = CodeBlockOptions(containerInset: 8)

    return DownStylerConfiguration(fonts: fonts,
                                   colors: colors,
                                   paragraphStyles: paragraphStyles,
                                   codeBlockOptions: codeBlockOptions)
}
