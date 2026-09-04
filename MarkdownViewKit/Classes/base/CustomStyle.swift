//
//  CustomStyle.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit
import Down
import Splash


class CustomStyle: DownStyler {
   public var codeBlockCursor: Int = 0
    public var codeBlockMatches: [CodeBlockMatch] = [] {
        didSet {
            codeBlockCursor = 0
        }
    }
    /// 行内代码 `like this` 的高亮背景色。
    public var inlineCodeBackground: UIColor = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)

    /// 标记「行内代码」范围的自定义属性 key。
    /// 引用样式 `style(blockQuote:)` 会用 `colors.quote` 覆盖整段前景色，
    /// 从而抹掉行内代码的红色文字。用这个标记把行内代码的范围记下来，
    /// 便于在引用样式应用之后再把代码的前景 / 背景色还原回去。
    private static let inlineCodeMarkerKey = NSAttributedString.Key("ZLInlineCode")

    
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
    public override func style(image str: NSMutableAttributedString, title: String?, url: String?) {
        super.style(image: str, title: title, url: url)
        str.addAttribute(AttrKey.image, value: AttrValue(url), range: NSRange(location: 0, length: str.length))
        
    }
    public override func style(codeBlock str: NSMutableAttributedString, fenceInfo: String?) {
        if codeBlockCursor < codeBlockMatches.count {
            var match = codeBlockMatches[codeBlockCursor]
            if match.content != str.string {
                print("⚠️ codeBlockCursor \(codeBlockCursor) content mismatch: match.content=\(match.content ?? "") \n str.string=\(str.string)")
            }
            if match.hmtlKind != .code {
                var markdown = "```\(match.language)\n\(str.string)\n```"
                 markdown = markdown
                    .replacingOccurrences(of: "\u{2028}", with: "\n")
                    .replacingOccurrences(of: "\u{2029}", with: "\n")
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                match.content = markdown
            }else {
                match.content = str.string
            }
            codeBlockCursor += 1
            let lang = fenceInfo ?? match.language ?? ""
            let isClosed = match.isClosed ?? true
            super.style(codeBlock: str, fenceInfo: fenceInfo)
            str.addAttribute(AttrKey.code, value: match, range: NSRange(location: 0, length: str.length))

//            str.addAttribute(AttrKey.key(codeTitle: fenceInfo), value: AttrValue(match), range: NSRange(location: 0, length: str.length))
//            str.addAttribute(AttrKey.key(codeTitle: fenceInfo), value: AttrValue(fenceInfo), range: NSRange(location: 0, length: str.length))
        }
    }

}
