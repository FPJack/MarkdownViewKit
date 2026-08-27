//
//  CustomStyle.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit
import Down
import Splash

/// 对代码做语法高亮：Swift 用 Splash 着色（浅色主题），其它 / 未知语言退化为纯等宽文本。
private  func highlightedCode(_ code: String,
                                    language: String?,
                                    fontSize: CGFloat,
                                    textColor: UIColor) -> NSAttributedString {
    let monoFont = UIFont(name: "Menlo", size: fontSize - 1) ?? .systemFont(ofSize: fontSize - 1)
    let plain = NSAttributedString(string: code, attributes: [.font: monoFont, .foregroundColor: textColor])

    guard language?.lowercased() == "swift" else { return plain }

    let theme = Theme(font: Splash.Font(size: Double(fontSize - 1)),
                      plainTextColor: textColor,
                      tokenColors: [
                        .keyword: UIColor.systemPink,
                        .string: UIColor.systemRed,
                        .type: UIColor(red: 0.4, green: 0.2, blue: 0.7, alpha: 1),
                        .call: UIColor.systemBlue,
                        .number: UIColor.systemOrange,
                        .comment: UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 1),
                        .property: UIColor.systemTeal,
                        .dotAccess: UIColor.systemBlue,
                        .preprocessing: UIColor.systemBrown
                      ],
                      backgroundColor: .clear)
    let highlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: theme))
    let highlighted = highlighter.highlight(code)
    return highlighted.length > 0 ? highlighted : plain
}

class CustomStyle: DownStyler {
    
    public var imageOptions: ImageAttachmentOptions = ImageAttachmentOptions()

    /// 行内代码 `like this` 的高亮背景色。
    public var inlineCodeBackground: UIColor = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)

    /// 标记「行内代码」范围的自定义属性 key。
    /// 引用样式 `style(blockQuote:)` 会用 `colors.quote` 覆盖整段前景色，
    /// 从而抹掉行内代码的红色文字。用这个标记把行内代码的范围记下来，
    /// 便于在引用样式应用之后再把代码的前景 / 背景色还原回去。
    private static let inlineCodeMarkerKey = NSAttributedString.Key("ZLInlineCode")
    


    /// 重写行内代码样式：在父类（等宽字体 + 文字颜色）基础上，追加背景高亮色，
    /// 并打上标记，供引用场景还原样式。
    /// 注意 NSAttributedString 的 `.backgroundColor` 是矩形填充（无圆角），
    /// 但对行内代码的视觉区分已经足够。
    public override func style(code str: NSMutableAttributedString) {
        super.style(code: str)
        let range = NSRange(location: 0, length: str.length)
        str.addAttribute(.backgroundColor, value: inlineCodeBackground, range: range)
        str.addAttribute(CustomStyle.inlineCodeMarkerKey, value: true, range: range)
    }

    /// 重写引用样式：父类会用 `colors.quote` 覆盖整段前景色，抹掉引用内行内代码的红字。
    /// 这里在父类处理完之后，找出被标记为行内代码的范围，重新还原它的前景色和背景高亮，
    /// 保证「引用内的行内代码」和「普通行内代码」外观一致。
    public override func style(blockQuote str: NSMutableAttributedString, nestDepth: Int) {
        super.style(blockQuote: str, nestDepth: nestDepth)
        let fullRange = NSRange(location: 0, length: str.length)
        str.enumerateAttribute(CustomStyle.inlineCodeMarkerKey, in: fullRange, options: []) { value, range, _ in
            guard value != nil else { return }
            str.addAttribute(.foregroundColor, value: colors.code, range: range)
            str.addAttribute(.backgroundColor, value: inlineCodeBackground, range: range)
        }
    }
    /// 代码块渲染参数（由 `DownBridge` 构建 styler 时注入）：
    /// 用于把 Markdown 围栏代码块渲染成自定义「代码块视图」附件（`CodeBlockAttachment`）。
    public var codeBlockMaxWidth: CGFloat = 0
    public var codeBlockFontSize: CGFloat = 16
    public var codeBlockTextColor: UIColor = UIColor(white: 0.15, alpha: 1.0)

    public override func style(image str: NSMutableAttributedString, title: String?, url: String?) {
        let attachment = ImageAttachment(imageURLString: url, options: imageOptions)
        let placeholder = NSMutableAttributedString(attachment: attachment)
        placeholder.addAttribute(AttrKey.image, value: url ?? "", range: NSRange(location: 0, length: placeholder.length))
        str.setAttributedString(placeholder)
    }
    public override func style(codeBlock str: NSMutableAttributedString, fenceInfo: String?) {
        if #available(iOS 13.0, *) {
            // 取代码原文，去掉尾部多余换行，避免多出一个空行号。
            var code = str.string
            while code.hasSuffix("\n") {
                code.removeLast()
            }

            let language = CodeBlockAttachment.detectLanguage(fromInfoString: fenceInfo)
            let highlighted = highlightedCode(code,
                                                          language: language,
                                                          fontSize: codeBlockFontSize,
                                                          textColor: codeBlockTextColor)
            var config = CodeBlockConfiguration()
            config.maxWidth = codeBlockMaxWidth
            config.allowsVerticalScroll = false
            config.codeFont = UIFont(name: "Menlo", size: codeBlockFontSize - 1)
                ?? .systemFont(ofSize: codeBlockFontSize - 1)
            config.lineNumberFont = config.codeFont
            config.maxWidth = 290
            
            let attachment = CodeBlockAttachment(code: highlighted,
                                                 language: language,
                                                 configuration: config)
            let newlineAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16)]
            
            let attributedString = NSMutableAttributedString()
            attributedString.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
            attributedString.append(NSMutableAttributedString(attachment: attachment))
            ///再加个换行符号
            attributedString.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
            str.setAttributedString(attributedString)
        } else {
            super.style(codeBlock: str, fenceInfo: fenceInfo)
        }
    }

}
