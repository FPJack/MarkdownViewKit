//
//  RenderAttachment.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/28.
//

import UIKit
import Splash

private class PlaceholderAttachment: NSTextAttachment {
    let viewType: ViewLoadable.Type
    let textMatch: TextMatch
    init(viewType: ViewLoadable.Type, textMatch: TextMatch) {
        self.viewType = viewType
        self.textMatch = textMatch
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
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
         
         var customViewTypes =  delegate.registerCustomViews(markdownView)
         
         customViewTypes.append(contentsOf: [MarkdownLatexWebView.self, CarouselView.self])
         
         let str = attributedText.string ?? ""
         let mAttr = NSMutableAttributedString(attributedString: attributedText)
         var attrRanges: [PlaceholderAttachment] = []
         customViewTypes.forEach { viewType in
             let regxRule = viewType.regxRule()
             let regexStr = regxRule.pattern
             do {
                 let regex = try NSRegularExpression(pattern: regexStr, options: regxRule.options)
                 let matches = regex.matches(in: str, range: NSRange(location: 0, length: str.count))
                 matches.forEach { match in
                     
                     let matchedStr = (str as NSString).substring(with: match.range)
                     let textMatch = TextMatch(view: nil,
                                               sourceText: str,
                                               pattern: regexStr,
                                               match: match,
                                               range: match.range,
                                               extraInfo: nil,
                                               content: matchedStr)
                     let pAttachment = PlaceholderAttachment(viewType: viewType, textMatch: textMatch)
                     attrRanges.append(pAttachment)
                 }
             }catch {
                 print("⚠️ regex error: \(error)")
             }
         }
        
         mAttr.enumerateAttribute(AttrKey.code, in: NSRange(location: 0, length: mAttr.length), options: [.reverse], using: { value, range, stop in
             if let codeMatch = value as? CodeBlockMatch  {
                 if codeMatch.hmtlKind == .code {
                     let matchedStr = (str as NSString).substring(with: range)
                     let textMatch = TextMatch(view: nil,
                                               sourceText: str,
                                               pattern: nil,
                                               match: nil,
                                               range: range,
                                               extraInfo: codeMatch.title,
                                               content: matchedStr,
                                               codeBlockMatch: codeMatch)
                     let pAttachment = PlaceholderAttachment(viewType: CodeBlockView.self, textMatch: textMatch)
                     attrRanges.append(pAttachment)
                 } else {
                     let matchedStr = (str as NSString).substring(with: range)
                     let textMatch = TextMatch(view: nil,
                                               sourceText: str,
                                               pattern: nil,
                                               match: nil,
                                               range: range,
                                               extraInfo: codeMatch.title,
                                               content: matchedStr,
                                               codeBlockMatch: codeMatch)
                     let pAttachment = PlaceholderAttachment(viewType: MarkdownWebBlockView.self, textMatch: textMatch)
                     attrRanges.append(pAttachment)
                 }
             }
         })
         
         ///图片
        mAttr.enumerateAttribute(AttrKey.image, in: NSRange(location: 0, length: mAttr.length), options: [.reverse], using: { value, range, stop in
             if let value = value as? AttrValue {
                 let url = value.value as? String ?? ""
                 let matchedStr = url
                 let textMatch = TextMatch(view: nil,
                                           sourceText: str,
                                           pattern: "",
                                           match: nil,
                                           range: range,
                                           extraInfo: nil,
                                           content: matchedStr)
                 // SVG 图片走原生 SVGImageView（CGSVGDocument 渲染）；其余走普通 ImageView（SDWebImage）。
                 let lowerURL = url.lowercased()
                 let isSVG = lowerURL.hasSuffix(".svg") || lowerURL.contains(".svg?") || lowerURL.contains(".svg#")
                 let viewType: ViewLoadable.Type = isSVG ? SVGImageView.self : ImageView.self
                 let pAttachment = PlaceholderAttachment(viewType: viewType, textMatch: textMatch)
                 attrRanges.append(pAttachment)
             }
        })
         
         
         attrRanges.sort { r1 , r2 in
             return r1.textMatch.range.location > r2.textMatch.range.location
         }

         // 判断是否为换行字符（LF / CR / 行分隔符 U+2028 / 段分隔符 U+2029）。
         func isNewlineChar(_ ch: unichar) -> Bool {
             return ch == 0x0A || ch == 0x0D || ch == 0x2028 || ch == 0x2029
         }
         let ns = str as NSString

         attrRanges.forEach { attachment in
             let r = attachment.textMatch.range

             // 只在附件前后「本来没有换行」时才补换行：既保证附件独占一行，
             // 又不会和 markdown 源码里已有的换行叠加成又高又空的空行。
             let needLeading: Bool = r.location > 0 && !isNewlineChar(ns.character(at: r.location - 1))
             let afterIndex = r.location + r.length
             let needTrailing: Bool = afterIndex < ns.length && !isNewlineChar(ns.character(at: afterIndex))
             // 段落样式：控制附件与上下内容的间距；补的换行用极小字号，避免自身占高。
             let newlineAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 1)]
             let attr = NSMutableAttributedString()
             if needLeading {
                 attr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
             }
             let body = NSMutableAttributedString(attachment: attachment)
             attr.append(body)
             if needTrailing {
                 attr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
             }
             mAttr.replaceCharacters(in: r, with: attr)
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
             let pAttachment = tupe.1
             let textMatch = pAttachment.textMatch
             let viewType = pAttachment.viewType
             let attachment: BaseAttachment
             var view: ViewLoadable?
             let oldAttahcment = getAttachment(range: range, filter: { attach  in
                 return true
             })
             var endTextMatch: TextMatch
             var diffContent = false
             if let oldAttahcment = oldAttahcment {
                 attachment = oldAttahcment
                 diffContent = textMatch.content != attachment.textMatch.content
                 view = attachment.view
                 endTextMatch = TextMatch(view: view,
                                               sourceText: textMatch.sourceText,
                                               pattern: textMatch.pattern,
                                               match: textMatch.match,
                                               range: range,
                                               extraInfo: textMatch.extraInfo,
                                               content: textMatch.content,
                                               codeBlockMatch: textMatch.codeBlockMatch)
                 endTextMatch = view!.convertTextMatch(markdownView, match: endTextMatch)
                 attachment.textMatch = endTextMatch
                 if diffContent,attachment.streamState != .none{
                     view!.updateData(data: endTextMatch)
                     if attachment.streamState == .streaming {
                         attachment.streamState = .finished
                     }
                 }
                 view?.viewOptions.textMatch = endTextMatch
             }else {
                 view = viewType.init()
                 endTextMatch = TextMatch(view: view,
                                              sourceText: textMatch.sourceText,
                                              pattern: textMatch.pattern,
                                              match: textMatch.match,
                                              range: range,
                                              extraInfo: textMatch.extraInfo,
                                              content: textMatch.content,
                                              codeBlockMatch: textMatch.codeBlockMatch)
                 
                 endTextMatch = view!.convertTextMatch(markdownView, match: endTextMatch)
                 confiureViewOptions(view: view!)
                 attachment = BaseAttachment.init(view: view!,
                                                  streamState: .none,
                                                  textMatch: endTextMatch)
                 view?.viewOptions.textMatch = endTextMatch

                 if let view = view as? GridTableView {
                     delegate.configureGridTableView(markdownView,gridView: view, match: endTextMatch)
                 } else if let view = view as? ImageView {
                     delegate.configureImageView(markdownView, imageView: view, match: endTextMatch)
                  }else if let view = view as? SVGImageView {
                      delegate.configureSVGImageView(markdownView, imageView: view, match: endTextMatch)
                  }else if let view = view as? CarouselView {
                      delegate.configureCarouselView(markdownView, carouselView: view, match: endTextMatch)
                  }else if let view = view as? CodeBlockView {
                     delegate.configureCodeBlockView(markdownView, codeView: view, match: endTextMatch)
                 }else if let view = view as? MarkdownWebBlockView {
                     delegate.configureWebView(markdownView, webView: view, match: endTextMatch)
                 }else if let view = view as? MarkdownLatexWebView {
                     delegate.configureLatexWebView(markdownView, webView: view, match: endTextMatch)
                 } else {
                     delegate.configureCustomView(markdownView, match: endTextMatch)
                 }
             }
             
             let attr = NSMutableAttributedString(attachment: attachment)
             mAttr.replaceCharacters(in: range, with: attr)
             if let view = view, view.superview !== markdownView.textView {
                 markdownView.textView.addSubview(view)
             }
         }
         
        return mAttr
    }
    
    func confiureViewOptions(view: ViewLoadable) {
        
        guard let markdownView = markdownView else {return}
        
        let inset = view.attachmentContentInset()
        let textViewInset = markdownView.textView.textContainerInset
        
        let w = textViewInset.left + textViewInset.right + markdownView.textView.textContainer.lineFragmentPadding * 2 + inset.left + inset.right
        
        view.viewOptions.maxWidth = markdownView.maxTextWidth - w
        
        view.viewOptions.minWidth = markdownView.minTextWidth - w
        
        view.viewOptions.estimedSize = CGSize(width: view.viewOptions.maxWidth, height: 100)
    }

    func getAttachment(range: NSRange,filter:(BaseAttachment) -> Bool) -> BaseAttachment? {
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
