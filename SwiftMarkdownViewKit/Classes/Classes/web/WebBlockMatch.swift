//
//  WebBlockMatch.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/14.
//

import UIKit
public extension CodeBlockContext {
    public func webBlockMatch() -> WebBlockMatch {
        WebBlockMatch(title: codeBlock.language ?? "",
                      content: codeBlock.code,
                      isClosed: isClosed,
                      direction: visitor.theme.layoutDirection)
    }
}
public struct WebBlockMatch {
    /// 语言标识（```之后的 info 字符串，如 `swift`）；未提供时为空串。
    let title: String
    /// 代码正文（不含定界行）。
    var content: String
    /// 代码块是否已闭合（即是否遇到收尾的 ``` ）。
    let isClosed: Bool
    /// 排版方向：决定生成的 HTML 用 `dir="rtl"` 还是 `dir="ltr"`。
    ///
    /// - Important: **故意不给默认值**。
    ///   这个字段必须从 `visitor.theme.layoutDirection` 透传，
    ///   一旦给了默认值，新增构造点时很容易忘记传，
    ///   结果 RTL 内容会静默退化成 LTR（表格列序不镜像、文字左对齐），
    ///   而且不报错、很难排查。去掉默认值可以让编译器帮忙兜底。
    var direction: MarkdownLayoutDirection
    
    var hmtlKind: Html.ContentKind {
        switch title.lowercased() {
        case "mermaid":
                .mermaid
        case "latex":
                .latex
        case "echarts":
                .echarts
        case "html":
                .html
        default:
                .code
        }
    }
    var htmlContent: String {
        var markdown = content
           .replacingOccurrences(of: "\u{2028}", with: "\n")
           .replacingOccurrences(of: "\u{2029}", with: "\n")
           .replacingOccurrences(of: "\r\n", with: "\n")
           .replacingOccurrences(of: "\r", with: "\n")
        switch title.lowercased() {
        case "echarts":
            let prefix = "```\(title.lowercased())\n"
            let suffix = "\n```"
            if !markdown.hasPrefix(prefix) { markdown = prefix + markdown }
            if !markdown.hasSuffix(suffix) { markdown = markdown + suffix }
            return Html.makeHTML(from: markdown, kind: .echarts, direction: direction)
        case "mermaid":
            let prefix = "```\(title.lowercased())\n"
            let suffix = "\n```"
            if !markdown.hasPrefix(prefix) { markdown = prefix + markdown }
            if !markdown.hasSuffix(suffix) { markdown = markdown + suffix }
            return Html.makeHTML(from: markdown, kind: .mermaid, direction: direction)
        case "latex":
            // 保底：如果正则切出来的是没有 `$$` 定界的裸公式，帮它补上；
            // 这样 KaTeX 的 auto-render 才能扫描到公式。
            while markdown.hasSuffix("\n") { markdown.removeLast() }
            if !markdown.hasPrefix("$$") { markdown = "$$\n" + markdown }
            if !markdown.hasSuffix("$$") { markdown = markdown + "\n$$" }
            return Html.makeHTML(from: markdown, kind: .latex, direction: direction)
        case "html":
            // 原始 HTML：直接作为 body 注入，不做任何转换。
            return Html.makeHTML(from: markdown, kind: .html, direction: direction)
        default:
            return ""
        }
    }
    var placeholderHtml: String {
        switch title.lowercased() {
        case "echarts":
            let htmlStr = """
                ```echarts
                {}
                ```
                """
            let html = Html.makeHTML(from: htmlStr, kind: .echarts, direction: direction)
            return html
        default:
            let emptyHTML = """
            <!doctype html><html lang="\(direction.isRightToLeft ? "ar" : "en")" dir="\(direction.isRightToLeft ? "rtl" : "ltr")"><head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>html,body{margin:0;padding:0;background:transparent;}</style>
            </head><body></body></html>
            """
            return emptyHTML
        }
    }
}

