//
//  RenderAttachment.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/28.
//

import UIKit
import Splash
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

struct RenderAttachment {
     var markdownView: MarkdownView
     let codeBlockFontSize: CGFloat = 16
     let codeBlockTextColor: UIColor = UIColor(white: 0.15, alpha: 1.0)
     let newlineAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 5)]
     func renderAttachment(_ attributedText: NSAttributedString?,options: MarkdownRenderOptions) -> NSAttributedString? {
        
        guard let attributedText = attributedText else {
            return nil
        }
        
        var ranges: [AttrRange] = []
        
        let res = NSMutableAttributedString(attributedString: attributedText)
         
         ///代码
        res.enumerateAttribute(AttrKey.code, in: NSRange(location: 0, length: res.length), options: [.reverse], using: { value, range, stop in
            if let value = value as? AttrValue {
                ranges.append(AttrRange.code(range, value))
            }
        })
         
         ///图片
        res.enumerateAttribute(AttrKey.image, in: NSRange(location: 0, length: res.length), options: [.reverse], using: { value, range, stop in
             if let value = value as? AttrValue {
                 ranges.append(AttrRange.image(range, value))
             }
        })
         
         ///表格
        let tableRangs = RegxParser.regxTable(attributex: res)
         
        ranges.append(contentsOf: tableRangs)
         
        
        ranges.sort { r1 , r2 in
             return r1.range.location > r2.range.location
        }
        
        ranges.forEach { attr in
            switch attr {
            case .image(let range, let value):
                if let imageURLString = value as? AttrValue {
                    renderImageAttachment(res, range: range, value: value.value, options: options)
                }
            case .code(let range, let value):
                if let code = value as? AttrValue {
                    renderCodeAttachment(res, range: range, value: value.value, options: options)
                }
            case .table(let range, let value):
                if let tableText = value as? AttrValue {
                    renderTableAttachment(res, range: range, value: value.value, options: options)
                }
            default:
                break
            }
        }
         
         
         guard let mutableAttributedText = res.mutableCopy() as? NSMutableAttributedString else { return res}
         let fullRange = NSRange(location: 0, length: mutableAttributedText.length)
         mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: [.reverse]) {value, range, _ in
             if let attachment = value as? GridTableAttachment {
                 let old = getAttachment(range: range) {
                     return $0 is AttachmentLoadable
                 }
                 if let old = old as? GridTableAttachment {
                     old.rows = attachment.rows
                     mutableAttributedText.replaceCharacters(in: range, with: NSAttributedString(attachment: old))
                 }
             }else if let attachment = value as? CodeBlockAttachment {
                 let old = getAttachment(range: range) {
                     return $0 is AttachmentLoadable
                 }
                 if let old = old as? CodeBlockAttachment {
                     old.code = attachment.code
                     mutableAttributedText.replaceCharacters(in: range, with: NSAttributedString(attachment: old))
                 }
             } else if let attachment = value as? ImageAttachment {
                 let old = getAttachment(range: range) {
                     return $0 is ImageAttachment
                 }
                 if let old = old {
                     mutableAttributedText.replaceCharacters(in: range, with: NSAttributedString(attachment: old))
                 }
             }
         }
        return mutableAttributedText
    }
    
     func renderImageAttachment(_ attributedText: NSMutableAttributedString,
                                 range: NSRange,
                                 value: Any,
                                 options: MarkdownRenderOptions,
    )  {
        guard let url = value as? String else {return}
        let attachment = ImageAttachment(imageURLString: url, options: options.imageOptions)
        let placeholder = NSMutableAttributedString(attachment: attachment)
        attributedText.replaceCharacters(in: range, with: placeholder)
    }
     func renderCodeAttachment(_ attributedText: NSMutableAttributedString,
                                 range: NSRange,
                                 value: Any,
                                 options: MarkdownRenderOptions,
    )  {
        guard let fenceInfo = value as? String else {return}
        let codeAttr = attributedText.attributedSubstring(from: range)
        var code = codeAttr.string
        
        if #available(iOS 13.0, *) {
            // 取代码原文，去掉尾部多余换行，避免多出一个空行号。
            while code.hasSuffix("\n") {
                code.removeLast()
            }
            
            let language = CodeBlockAttachment.detectLanguage(fromInfoString: fenceInfo)
            let highlighted = highlightedCode(code,
                                              language: language,
                                              fontSize: codeBlockFontSize,
                                              textColor: codeBlockTextColor)
            var config = CodeBlockOption()
            
            config.allowsVerticalScroll = false
            config.allowsHorizontalScroll = false
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
            attributedText.replaceCharacters(in: range, with: attributedString)
            
        }
        
    }
     func renderTableAttachment(_ attributedText: NSMutableAttributedString,
                                 range: NSRange,
                                 value: Any,
                                 options: MarkdownRenderOptions,
    )  {
        
        guard let text = value as? String else {return}
        let rows = RegxParser.gridRows(from: text)
        let attachment = GridTableAttachment(rows: rows, configuration: options.tableOptions)
        let mAttr = NSMutableAttributedString()
        mAttr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        mAttr.append(NSMutableAttributedString(attachment: attachment))

        ///再加个换行符号
        attributedText.replaceCharacters(in: range, with: mAttr)
    }
    
    func getAttachment(range: NSRange,filter:(AttachmentLoadable) -> Bool) -> AttachmentLoadable? {
       return markdownView.loadableAttachments.first {
            return $0.range?.location == range.location && filter($0)
       }
    }
}
