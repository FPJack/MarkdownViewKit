//
//  LatexDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/14.
//

import UIKit
import Markdown

struct LatexDirectiveRenderer: BlockRule {
    public static let latexBlockPattern =
        #"^[ \t]*\$\$[ \t]*(?:(?:\r?\n|\u2028|\u2029)[ \t]*)?([\s\S]*?)(?:[ \t]*(\$\$)|\z)"#
    
    
    var identifier: String = "latex-block"
    
    static var regex = try! NSRegularExpression(pattern: latexBlockPattern)
    
    func renderView(match: NSTextCheckingResult, markup: Paragraph, visitor: MarkdownAttributedStringBuilder) -> (any ViewLoadable)? {
        let webView = LatexWebBlockView()
        return webView
    }
    func matches(in string: String, options: NSRegularExpression.MatchingOptions, range: NSRange) -> [NSTextCheckingResult]? {
        Self.regex.matches(in: string, options: options, range: range)
    }
}
public class LatexWebBlockView: BaseMarkdownWebBlockView,ViewLoadable {
    
    public typealias MarkupType = Paragraph

    public func updateData(data: MarkupContext<Markdown.Paragraph>) {
        resetWebBlockMatch(data: data)
        loadMarkdown(webBlockMatch.content, htmlKind: webBlockMatch.hmtlKind)

    }
    
    public func startStreaming(data: MarkupContext<Markdown.Paragraph>, animation: Bool) {
        resetWebBlockMatch(data: data)
        loadMarkdown(webBlockMatch.content, htmlKind: webBlockMatch.hmtlKind)
    }
    
    private func resetWebBlockMatch(data: MarkupContext<Markdown.Paragraph>){
        guard let match = data.match else {return}
        let text = data.markup.plainText as NSString
                let overall    = match.range
                let bodyRange  = match.range(at: 1)
                let closeRange = match.range(at: 2)
                let content  = (bodyRange.location != NSNotFound && bodyRange.length > 0)
                ? text.substring(with: bodyRange)
                    : ""
                let isClosed = (closeRange.location != NSNotFound && closeRange.length > 0)
        // 方向要从 visitor 透传，否则生成的 HTML 会漏掉 dir 属性。
        // （公式本身在模板里被强制 LTR，但外层 body 的方向仍需与正文一致。）
        webBlockMatch = WebBlockMatch(title: "latex",
                                      content: content,
                                      isClosed: isClosed,
                                      direction: data.visitor.theme.layoutDirection)
    }
    
    public func estimatedSize(for data: MarkupContext<Markdown.Paragraph>) -> CGSize {
        return viewOptions.estimedSize ?? .zero
    }
}
