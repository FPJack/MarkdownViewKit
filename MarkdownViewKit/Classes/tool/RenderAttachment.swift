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
         
         customViewTypes.append(contentsOf: [MarkdownLatexWebView.self])
         
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
                 let pAttachment = PlaceholderAttachment(viewType: ImageView.self, textMatch: textMatch)
                 attrRanges.append(pAttachment)
             }
        })
         
         
         attrRanges.sort { r1 , r2 in
             return r1.textMatch.range.location > r2.textMatch.range.location
         }
         
         attrRanges.forEach { attachment in
             let attr = NSAttributedString(attachment: attachment)
             mAttr.replaceCharacters(in: attachment.textMatch.range, with: attr)
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
                 attachment = BaseAttachment.init(view: view!,
                                                  streamState: .none,
                                                  textMatch: endTextMatch)
                 if let view = view as? GridTableView {
                     delegate.configureGridTableView(markdownView,gridView: view, match: endTextMatch)
                 } else if let view = view as? ImageView {
                     delegate.configureImageView(markdownView, imageView: view, match: endTextMatch)
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
             let attr = NSAttributedString(attachment: attachment)
             mAttr.replaceCharacters(in: range, with: attr)
             markdownView.textView.addSubview(view!)
            
         }
         
        return mAttr
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
