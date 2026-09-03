//
//  RenderAttachment.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/28.
//

import UIKit
import Splash
public struct AttachmentMatch {
    public let attachment: AttachmentLoadable
    public let view: ViewLoadable
    public let matchedString: String
    public let matchedRange: NSRange
    public let pattern: String
    public let sourceText: String
    ///  代码块或数学公式匹配结果（如果是代码块或数学公式）。
    public let codeMathBlock: CodeBlockMatch?
}

private class PlaceholderAttachment: NSTextAttachment {
    let type: AttachmentType
    init(type: AttachmentType) {
        self.type = type
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct AttachmentType {
    let range: NSRange
    let pattern: String
    let attachType: AttachmentLoadable.Type
    let viewType: ViewLoadable.Type
    let matchedString: String
    ///  代码块或数学公式匹配结果（如果是代码块或数学公式）。
    public let codeMathBlock: CodeBlockMatch?
}

struct RenderAttachment {
     weak var markdownView: MarkdownView?
     let codeBlockFontSize: CGFloat = 16
     let codeBlockTextColor: UIColor = UIColor(white: 0.15, alpha: 1.0)
     let newlineAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 5)]
     func renderAttachment(_ attributedText: NSAttributedString?,options: MarkdownRenderOptions) -> NSAttributedString? {
         
         guard let  delegate = markdownView?.customViewDelegate else{
             return attributedText
         }
         guard let markdownView = markdownView else {
                return attributedText
            }
         guard let attributedText = attributedText else {
             return nil
         }
         var regexRange: [AttachmentMatch] = []
         let customViewTypes =  delegate.registerCustomViews(markdownView)
         let str = attributedText.string ?? ""
         let mAttr = NSMutableAttributedString(attributedString: attributedText)
         var attrRanges: [AttachmentType] = []
         customViewTypes.forEach { viewType in
             let regexStr = viewType.regex
             do {
                 let regex = try NSRegularExpression(pattern: regexStr, options: [.anchorsMatchLines])
                 let matches = regex.matches(in: str, range: NSRange(location: 0, length: str.count))
                 matches.forEach { match in
                     let attachmentType = viewType.attachment ?? BaseAttachment.self
                     attrRanges.append(AttachmentType(range: match.range, pattern: regexStr, attachType: attachmentType, viewType: viewType, matchedString: (str as NSString).substring(with: match.range), codeMathBlock: nil))
                 }
             }catch {
                 print("⚠️ regex error: \(error)")
             }
         }
         
         mAttr.enumerateAttribute(AttrKey.code, in: NSRange(location: 0, length: str.count), options: [.reverse], using: { value, range, stop in
             if let codeMatch = value as? CodeBlockMatch  {
                 attrRanges.append(AttachmentType(range: range, pattern: CodeBlockView.regex, attachType: CodeBlockView.attachment ?? BaseAttachment.self, viewType: CodeBlockView.self, matchedString: (str as NSString).substring(with: range), codeMathBlock: codeMatch))
             }
         })
         
         attrRanges.forEach { attach in
             let attr = NSAttributedString(attachment: PlaceholderAttachment(type: attach))
             mAttr.replaceCharacters(in: attach.range, with: attr)
         }
         
         
         var sortRanges: [(NSRange,PlaceholderAttachment)] = []
         mAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mAttr.length)) { value , range, _ in
             if let placeholder = value as? PlaceholderAttachment {
                 sortRanges.append((range,placeholder))
             }
         }
         
         sortRanges.sort { r1 , r2 in
             return r1.0.location > r2.0.location
         }
         
         sortRanges.forEach { tupe in
             let range = tupe.0
             let placeholder = tupe.1
             let attachmentType = placeholder.type.attachType
             let viewType = placeholder.type.viewType
             let attachment: AttachmentLoadable
             var view: ViewLoadable?
             let oldAttahcment = getAttachment(range: range, filter: { attach  in
                 return type(of: attach) == attachmentType
             })
             var hasOld = false
             if let oldAttahcment = oldAttahcment {
                 attachment = oldAttahcment
                 hasOld = true
                 view = attachment.view
             }else {
                 view = viewType.init()
                 attachment = attachmentType.init(view: view!)
             }
             
             var attchmentMatch = AttachmentMatch(
                attachment: attachment,
                view: attachment.view,
                matchedString: placeholder.type.matchedString,
                matchedRange: range,
                pattern: placeholder.type.pattern,
                sourceText: str,
                codeMathBlock: placeholder.type.codeMathBlock
             )
             
             if let view = view as? GridTableView {
                 delegate.configureGridTableView(markdownView, match: attchmentMatch)
             }else if let view = view as? CodeBlockView {
                 delegate.configureCodeBlockView(markdownView, match: attchmentMatch)
             }else {
                 delegate.configureCustomView(markdownView, match: attchmentMatch)
             }
             
             let attr = NSAttributedString(attachment: attachment)
             mAttr.replaceCharacters(in: range, with: attr)
             markdownView.textView.addSubview(view!)
             
             if hasOld {
                 view!.flushData()
             }
         }
         
        
//         mAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mAttr.length), options: [.reverse]) { value , range , _ in
//             if let placeholder = value as? PlaceholderAttachment {
//                 
//             }
//         }
         
         
        return mAttr
        
        
//        var ranges: [AttrRange] = []
//        
//        let res = NSMutableAttributedString(attributedString: attributedText)
//         
//         ///代码
//        res.enumerateAttribute(AttrKey.code, in: NSRange(location: 0, length: res.length), options: [.reverse], using: { value, range, stop in
//            if let value = value as? AttrValue {
//                ranges.append(AttrRange.code(range, value))
//            }
//        })
//         
//         ///图片
//        res.enumerateAttribute(AttrKey.image, in: NSRange(location: 0, length: res.length), options: [.reverse], using: { value, range, stop in
//             if let value = value as? AttrValue {
//                 ranges.append(AttrRange.image(range, value))
//             }
//        })
//
//         ///Web 渲染块（mermaid / echarts 等）
//        res.enumerateAttribute(AttrKey.web, in: NSRange(location: 0, length: res.length), options: [.reverse], using: { value, range, stop in
//             if let value = value as? AttrValue {
//                 ranges.append(AttrRange.web(range, value))
//             }
//        })
//         
//         let viewLoadables = markdownView?.loadableAttachments ?? []
//         
//         ///表格
//        let tableRangs = RegxParser.regxTable(attributex: res)
//         
//         
//         
//        ranges.append(contentsOf: tableRangs)
//
//         ///块级数学公式（$$ ... $$）
//        let latexMatches = RegxParser.regxLatex(attributex: res)
//        let latexRanges: [AttrRange] = latexMatches.map { m in
//            .latex(m.range, AttrValue(m))
//        }
//        ranges.append(contentsOf: latexRanges)
//
//         ///视频 `[video:URL]`
//        let videoMatches = RegxParser.regxVideo(attributex: res)
//        let videoRanges: [AttrRange] = videoMatches.map { m in
//            .video(m.range, AttrValue(m))
//        }
//        ranges.append(contentsOf: videoRanges)
//
//         ///音乐 `[music:URL]`
//        let musicMatches = RegxParser.regxMusic(attributex: res)
//        let musicRanges: [AttrRange] = musicMatches.map { m in
//            .music(m.range, AttrValue(m))
//        }
//        ranges.append(contentsOf: musicRanges)
//
//        
//        ranges.sort { r1 , r2 in
//            return r1.range.location > r2.range.location
//        }
//        
//        ranges.forEach { attr in
//            switch attr {
//            case .image(let range, let value):
//                if let imageURLString = value as? AttrValue {
//                    renderImageAttachment(res, range: range, value: value.value, options: options)
//                }
//            case .code(let range, let value):
//                
//                break
//            case .table(let range, let value):
//                if let tableText = value as? AttrValue {
//                    renderTableAttachment(res, range: range, value: value.value, options: options)
//                }
//            case .web(let range, let value):
//                break
//            case .latex(let range, let value):
//                break
//            case .video(let range, let value):
//                break
//            case .music(let range, let value):
//                break
//            default:
//                break
//            }
//        }
//         
//         
//         guard let mutableAttributedText = res.mutableCopy() as? NSMutableAttributedString else { return res}
//         let fullRange = NSRange(location: 0, length: mutableAttributedText.length)
//         mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: [.reverse]) {value, range, _ in
//             if let attachment = value as? GridTableAttachment {
//                 let old = getAttachment(range: range) {
//                     return $0 is AttachmentLoadable
//                 }
//                 if let old = old as? GridTableAttachment {
//                     old.rows = attachment.rows
//                     mutableAttributedText.replaceCharacters(in: range, with: NSAttributedString(attachment: old))
//                 }
//             }
//         }
//        return mutableAttributedText
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
     
     func renderTableAttachment(_ attributedText: NSMutableAttributedString,
                                 range: NSRange,
                                 value: Any,
                                 options: MarkdownRenderOptions,
    )  {
        
//        guard let text = value as? String else {return}
//        let rows = RegxParser.gridRows(from: text)
//        let attachment = GridTableAttachment(rows: rows, configuration: options.tableOptions)
//         
//        let mAttr = NSMutableAttributedString()
//        mAttr.append(NSMutableAttributedString(attachment: attachment))
//
//        ///再加个换行符号
//        attributedText.replaceCharacters(in: range, with: mAttr)
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
