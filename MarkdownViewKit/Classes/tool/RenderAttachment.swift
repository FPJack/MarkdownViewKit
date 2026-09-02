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
     weak var markdownView: MarkdownView?
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

         ///Web 渲染块（mermaid / echarts 等）
        res.enumerateAttribute(AttrKey.web, in: NSRange(location: 0, length: res.length), options: [.reverse], using: { value, range, stop in
             if let value = value as? AttrValue {
                 ranges.append(AttrRange.web(range, value))
             }
        })
         
         ///表格
        let tableRangs = RegxParser.regxTable(attributex: res)
         
         
         
        ranges.append(contentsOf: tableRangs)

         ///块级数学公式（$$ ... $$）
        let latexMatches = RegxParser.regxLatex(attributex: res)
        let latexRanges: [AttrRange] = latexMatches.map { m in
            .latex(m.range, AttrValue(m))
        }
        ranges.append(contentsOf: latexRanges)

         ///视频 `[video:URL]`
        let videoMatches = RegxParser.regxVideo(attributex: res)
        let videoRanges: [AttrRange] = videoMatches.map { m in
            .video(m.range, AttrValue(m))
        }
        ranges.append(contentsOf: videoRanges)

        
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
            case .web(let range, let value):
                renderWebAttachment(res, range: range, value: value.value, options: options)
            case .latex(let range, let value):
                renderLatexAttachment(res, range: range, value: value.value, options: options)
            case .video(let range, let value):
                renderVideoAttachment(res, range: range, value: value.value, options: options)
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
             } else if #available(iOS 13.0, *), let attachment = value as? WebViewAttachment {
                 let old = getAttachment(range: range) {
                     return $0 is AttachmentLoadable
                 }
                 if let old = old as? WebViewAttachment {
                     old.codeBlockMatch = attachment.codeBlockMatch
                     mutableAttributedText.replaceCharacters(in: range, with: NSAttributedString(attachment: old))
                 }
             } else if #available(iOS 13.0, *), let attachment = value as? VideoAttachment {
                 let old = getAttachment(range: range) {
                     return $0 is AttachmentLoadable
                 }
                 if let old = old as? VideoAttachment {
                     // 只有真的变化了才赋值，避免 didSet 反复触发封面抓取 / 视图重建。
                     if old.urlString != attachment.urlString {
                         old.urlString = attachment.urlString
                     }
                     if old.title != attachment.title {
                         old.title = attachment.title
                     }
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
         guard let codeMatch = value as? CodeBlockMatch else {return}
         guard let fenceInfo = codeMatch.language as? String else {return}
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

    func renderWebAttachment(_ attributedText: NSMutableAttributedString,
                             range: NSRange,
                             value: Any,
                             options: MarkdownRenderOptions)  {
        guard #available(iOS 13.0, *) else { return }
        guard var value = value as? CodeBlockMatch else { return }
        let fenceInfo = value.language ?? ""
        let codeAttr = attributedText.attributedSubstring(from: range)
        // Down 生成 attributedString 时会把代码块内的换行替换成 U+2028（LINE SEPARATOR），
        // 直接把这段字符串塞回 markdown 会让 mermaid / echarts 拿到「没有真正换行」的源码，
        // JSON.parse / mermaid 解析都会报语法错误。这里统一归一化为 \n。
        var code = codeAttr.string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while code.hasSuffix("\n") { code.removeLast() }

        // 重新拼装成围栏代码块 markdown，交给 Html.makeHTML 转成 mermaid / echarts HTML。
        let markdown = "```\(fenceInfo)\n\(code)\n```"
        
        value.content = markdown

        let attachment = WebViewAttachment(codeMatch: value, configuration: options.webOptions)

        let mAttr = NSMutableAttributedString()
        mAttr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        mAttr.append(NSAttributedString(attachment: attachment))
        mAttr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        attributedText.replaceCharacters(in: range, with: mAttr)
    }

    /// 渲染块级数学公式（`$$ ... $$`）：整段原样交给 `Html.makeHTML`，
    /// 让 KaTeX 的 auto-render 扫描 `$$...$$` 定界符渲染公式，
    /// 用 `WebViewAttachment` 占位承载 WebView。
    func renderLatexAttachment(_ attributedText: NSMutableAttributedString,
                               range: NSRange,
                               value: Any,
                               options: MarkdownRenderOptions) {
        guard #available(iOS 13.0, *) else { return }
        guard var value = value as? CodeBlockMatch else { return }

        // 直接从原始富文本切片，避免 value 里的字符串已经被规范化过导致对不上。
        let raw = attributedText.attributedSubstring(from: range).string
        // Down 会把公式内部的换行替换成 U+2028 / U+2029，归一化成 \n 以保证 KaTeX 解析正常。
        var latex = raw
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while latex.hasSuffix("\n") { latex.removeLast() }
        // 保底：如果正则切出来的是没有 `$$` 定界的裸公式，帮它补上；
        // 这样 KaTeX 的 auto-render 才能扫描到公式。
        if !latex.hasPrefix("$$") { latex = "$$\n" + latex }
        if !latex.hasSuffix("$$") { latex = latex + "\n$$" }

        // 关键：把补好定界符的 markdown 写回 value.content，
        // WebViewAttachment.markdown 的 getter 就是取 codeBlockMatch.content。
        value.content = latex

        let attachment = WebViewAttachment(codeMatch: value, configuration: options.webOptions)

        let mAttr = NSMutableAttributedString()
        mAttr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        mAttr.append(NSAttributedString(attachment: attachment))
        mAttr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        attributedText.replaceCharacters(in: range, with: mAttr)
    }
    
    /// 渲染 `[video:URL]` 视频占位块：用 `VideoAttachment` 替换标记文本。
    func renderVideoAttachment(_ attributedText: NSMutableAttributedString,
                               range: NSRange,
                               value: Any,
                               options: MarkdownRenderOptions) {
        guard #available(iOS 13.0, *) else { return }
        guard let match = value as? RegxParser.VideoMatch else { return }

        let attachment = VideoAttachment(urlString: match.urlString,
                                         title: match.title,
                                         configuration: options.videoOptions)

        let mAttr = NSMutableAttributedString()
        mAttr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        mAttr.append(NSAttributedString(attachment: attachment))
        mAttr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        attributedText.replaceCharacters(in: range, with: mAttr)
    }

    func getAttachment(range: NSRange,filter:(AttachmentLoadable) -> Bool) -> AttachmentLoadable? {
        guard let markdownView = markdownView else {
            return nil
        }
        let attachments = markdownView.loadableAttachments
        let old = attachments.first {
                return $0.range?.location == range.location && filter($0)
        }
        return old
    }
}
