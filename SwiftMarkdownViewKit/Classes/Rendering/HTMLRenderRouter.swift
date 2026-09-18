//
//  HTMLRenderRouter.swift
//  SwiftMarkdownViewKit
//
//  HTML 分级路由：按复杂度决定用最轻量的方式渲染，只有复杂/带脚本的 HTML 才动用 WebView。
//
//  路由分档：
//    注释 / 空        → 丢弃
//    单媒体标签        → 原生 attachment（<img> 复用 AsyncImageTextAttachment；<audio>/<video> 徽标+链接）
//    简单内联标签      → NSAttributedString 属性（<b><i><u><sub>… 由段落层栈式配对，见 builder.renderInline）
//    简单静态 HTML     → NSAttributedString importer（系统 HTML 导入，无 JS）
//    复杂 / 带脚本     → WebView（仅此档创建 WKWebView）
//

import UIKit
import Markdown

// MARK: - 分档策略

enum HTMLRenderStrategy {
    case ignore
    case media(tag: String, attrs: [String: String])
    case attributedImporter
    case webView
}

// MARK: - 标签 token

struct HTMLTagToken {
    enum Kind { case open, close, selfClosing, comment }
    let name: String                       // 小写标签名
    let kind: Kind
    let attributes: [String: String]       // 属性（小写 key）
}

// MARK: - 行内样式（成对标签配对后应用到文字上）

enum HTMLInlineStyle {
    case bold, italic, underline, strikethrough, code
    case mark(UIColor)
    case color(UIColor)
    case sub, sup
    case link(URL)   // <a href="…">：蓝色可点击链接
}

// MARK: - 路由器

enum HTMLRouter {

    /// HTML5 void（自闭合）元素：即使没写 `/>` 也视为自闭合。
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    /// 触发“必须上 WebView”的复杂特征。
    private static let webViewTriggers = ["<script", "<iframe", "<style", "<svg", "<canvas", "onclick", "onload", "onerror"]

    // MARK: 标签解析

    /// 解析单个标签片段（swift-markdown 的 InlineHTML 每个节点就是一个这样的片段）。
    static func parseTag(_ raw: String) -> HTMLTagToken? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("<"), s.hasSuffix(">") else { return nil }

        if s.hasPrefix("<!--") { return HTMLTagToken(name: "", kind: .comment, attributes: [:]) }

        // 闭合标签 </name>
        if s.hasPrefix("</") {
            let name = s.dropFirst(2).dropLast()
                .trimmingCharacters(in: .whitespaces).lowercased()
            return HTMLTagToken(name: name, kind: .close, attributes: [:])
        }

        // 取标签名
        let inner = s.dropFirst().dropLast() // 去掉 < >
        guard let firstToken = inner.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "/" }).first else {
            return nil
        }
        let name = String(firstToken).lowercased()
        guard !name.isEmpty, name.first?.isLetter == true else { return nil }

        let attrs = parseAttributes(String(inner))
        let selfClosing = s.hasSuffix("/>") || voidTags.contains(name)
        return HTMLTagToken(name: name, kind: selfClosing ? .selfClosing : .open, attributes: attrs)
    }

    private static func parseAttributes(_ inner: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)')"#) else {
            return result
        }
        let ns = inner as NSString
        regex.enumerateMatches(in: inner, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            let dq = m.range(at: 3)
            let sq = m.range(at: 4)
            let value = dq.location != NSNotFound ? ns.substring(with: dq)
                       : (sq.location != NSNotFound ? ns.substring(with: sq) : "")
            result[key] = value
        }
        return result
    }

    // MARK: 块级分类

    static func classifyBlock(_ rawHTML: String) -> HTMLRenderStrategy {
        let html = rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if html.isEmpty || html.hasPrefix("<!--") { return .ignore }

        let lower = html.lowercased()
        if webViewTriggers.contains(where: { lower.contains($0) }) { return .webView }

        // 整块就是单个媒体标签（<img>/<audio>/<video>）
        if let token = parseTag(html),
           token.kind == .selfClosing || isSingleTag(html),
           ["img", "audio", "video"].contains(token.name) {
            return .media(tag: token.name, attrs: token.attributes)
        }

        // 标签数量少、纯静态 → importer
        if tagCount(lower) <= 8 { return .attributedImporter }

        return .webView
    }

    private static func isSingleTag(_ html: String) -> Bool {
        // 只有一个 `<...>`，后面没有其它标签
        guard let firstClose = html.firstIndex(of: ">") else { return false }
        let rest = html[html.index(after: firstClose)...]
        return !rest.contains("<")
    }

    private static func tagCount(_ lower: String) -> Int {
        lower.components(separatedBy: "<").count - 1
    }

    // MARK: 块级渲染入口

    static func renderBlock(_ html: HTMLBlock, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString {
        let theme = visitor.theme
        switch classifyBlock(html.rawHTML) {
        case .ignore:
            return NSAttributedString()
        case .media(let tag, let attrs):
            return renderMedia(tag: tag, attrs: attrs, theme: theme)
        case .attributedImporter:
            return renderViaImporter(html.rawHTML, theme: theme) ?? plainFallback(html.rawHTML, theme: theme)
        case .webView:
            // 复杂 / 带脚本 HTML → WKWebView（仅此档创建 WebView）。
            if #available(iOS 13.0, *) {
                let attachment = BaseAttachment(
                    markup: MarkupContext(markup: html as Markup, visitor: visitor),
                    viewBlock: { HTMLWebBlockView() }
                )
                return NSMutableAttributedString(attachment: attachment)
            } else {
                // iOS 13 以下兜底：用 importer 展示静态内容。
                return renderViaImporter(html.rawHTML, theme: theme) ?? plainFallback(html.rawHTML, theme: theme)
            }
        }
    }

    // MARK: 媒体标签 → 原生

    static func renderMedia(tag: String, attrs: [String: String], theme: MarkdownTheme) -> NSAttributedString {
        let src = attrs["src"] ?? attrs["data-src"] ?? ""
        let url = URL(string: src.trimmingCharacters(in: .whitespacesAndNewlines))

        switch tag {
        case "img":
            let attachment = AsyncImageTextAttachment(url: url, placeholderHeight: 180)
            attachment.startLoadingIfNeeded()
            return NSAttributedString(attachment: attachment)
        case "audio", "video":
            let symbol = tag == "audio" ? "🎵" : "🎬"
            let label = URL(string: src)?.lastPathComponent ?? src
            let result = NSMutableAttributedString(
                string: "  \(symbol) \(label)  ",
                attributes: [.font: theme.bodyFont,
                             .foregroundColor: theme.linkColor,
                             .backgroundColor: theme.codeBackgroundColor]
            )
            if let url { result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length)) }
            return result
        default:
            return NSAttributedString()
        }
    }

    // MARK: 简单静态 HTML → NSAttributedString importer

    static func renderViaImporter(_ raw: String, theme: MarkdownTheme) -> NSAttributedString? {
        guard let data = raw.data(using: .utf8) else { return nil }
        // NSAttributedString 的 HTML 导入必须在主线程。
        var result: NSAttributedString?
        let work = {
            result = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return result
    }

    private static func plainFallback(_ raw: String, theme: MarkdownTheme) -> NSAttributedString {
        NSAttributedString(string: raw,
                           attributes: [.font: theme.codeFont, .foregroundColor: theme.secondaryTextColor])
    }

    // MARK: 行内：open 标签 → 样式

    static func inlineStyle(forOpenTag name: String, attrs: [String: String], theme: MarkdownTheme) -> HTMLInlineStyle? {
        switch name {
        case "b", "strong":     return .bold
        case "i", "em":         return .italic
        case "u", "ins":        return .underline
        case "del", "s", "strike": return .strikethrough
        case "code", "kbd", "tt":  return .code
        case "mark":            return .mark(UIColor.systemYellow.withAlphaComponent(0.4))
        case "sub":             return .sub
        case "sup":             return .sup
        case "a":
            // <a href="…">：解析目标地址，命中则渲染成可点击链接。
            let href = (attrs["href"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: href) { return .link(url) }
            return nil
        case "span", "font":
            if let color = attrs["color"].flatMap(color(from:))
                ?? cssColor(fromStyle: attrs["style"]) {
                return .color(color)
            }
            return nil
        default:
            return nil
        }
    }

    /// 行内自闭合标签（<br>/<img> 等）直接产出富文本片段。
    static func renderInlineSelfClosing(_ token: HTMLTagToken, theme: MarkdownTheme) -> NSAttributedString {
        switch token.name {
        case "br":
            return NSAttributedString(string: "\n", attributes: [.font: theme.bodyFont])
        case "img":
            return renderMedia(tag: "img", attrs: token.attributes, theme: theme)
        case "wbr":
            return NSAttributedString(string: "\u{200B}") // 零宽空格，允许换行
        default:
            return NSAttributedString()
        }
    }

    // MARK: 把样式栈应用到一段文字

    static func apply(_ styles: [HTMLInlineStyle?], to att: NSMutableAttributedString, theme: MarkdownTheme) {
        for style in styles.compactMap({ $0 }) {
            let whole = NSRange(location: 0, length: att.length)
            switch style {
            case .bold:          addTrait(.traitBold, to: att, theme: theme)
            case .italic:        addTrait(.traitItalic, to: att, theme: theme)
            case .underline:     att.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
            case .strikethrough: att.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
            case .code:
                att.addAttribute(.font, value: theme.codeFont, range: whole)
                att.addAttribute(.backgroundColor, value: theme.codeBackgroundColor, range: whole)
            case .mark(let c):   att.addAttribute(.backgroundColor, value: c, range: whole)
            case .color(let c):  att.addAttribute(.foregroundColor, value: c, range: whole)
            case .link(let url):
                att.addAttribute(.link, value: url, range: whole)
                att.addAttribute(.foregroundColor, value: theme.linkColor, range: whole)
            case .sub:           applyBaseline(att, factor: -0.25, theme: theme)
            case .sup:           applyBaseline(att, factor: 0.35, theme: theme)
            }
        }
    }

    // MARK: 辅助

    private static func addTrait(_ trait: UIFontDescriptor.SymbolicTraits, to att: NSMutableAttributedString, theme: MarkdownTheme) {
        let whole = NSRange(location: 0, length: att.length)
        att.enumerateAttribute(.font, in: whole, options: []) { value, range, _ in
            let base = (value as? UIFont) ?? theme.bodyFont
            var traits = base.fontDescriptor.symbolicTraits
            traits.insert(trait)
            if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                att.addAttribute(.font, value: UIFont(descriptor: descriptor, size: base.pointSize), range: range)
            }
        }
    }

    private static func applyBaseline(_ att: NSMutableAttributedString, factor: CGFloat, theme: MarkdownTheme) {
        let whole = NSRange(location: 0, length: att.length)
        att.enumerateAttribute(.font, in: whole, options: []) { value, range, _ in
            let base = (value as? UIFont) ?? theme.bodyFont
            let small = base.withSize(base.pointSize * 0.7)
            att.addAttribute(.font, value: small, range: range)
            att.addAttribute(.baselineOffset, value: base.pointSize * factor, range: range)
        }
    }

    private static func color(from name: String) -> UIColor? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        if n.hasPrefix("#") { return UIColor(hex: n) }
        switch n {
        case "red": return .systemRed
        case "green": return .systemGreen
        case "blue": return .systemBlue
        case "orange": return .systemOrange
        case "gray", "grey": return .systemGray
        case "black": return .black
        case "white": return .white
        default: return nil
        }
    }

    private static func cssColor(fromStyle style: String?) -> UIColor? {
        guard let style else { return nil }
        guard let range = style.range(of: #"color\s*:\s*([^;]+)"#, options: .regularExpression) else { return nil }
        let raw = style[range].components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
        return color(from: raw)
    }
}

// MARK: - Hex 颜色

private extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 3 else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else { return nil }
        self.init(red: CGFloat((rgb & 0xFF0000) >> 16) / 255,
                  green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
                  blue: CGFloat(rgb & 0x0000FF) / 255,
                  alpha: 1)
    }
}
