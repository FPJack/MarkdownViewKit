//
//  MarkdownDirective.swift
//  MarkdownKit
//
//  自定义指令扩展点。业务方可以注册新的行内 / 代码块指令，
//  无需修改渲染器核心，符合“开闭原则”，便于长期维护与扩展。
//

import UIKit




// MARK: - 行内指令

/// 行内自定义指令，用于处理形如 `[name:payload]` 的非标准语法。
///
/// 例如：`[music:https://a.mp3]`、`[video:https://b.mp4]`。
/// 实现该协议并注册到 `MarkdownDirectiveRegistry` 即可被渲染器识别。
public protocol InlineDirectiveRenderer {
    /// 指令名，对应 `[name:...]` 中的 name（小写）。
    var name: String { get }
    /// 将匹配到的 payload 渲染为富文本片段。
    /// - Parameters:
    ///   - payload: 冒号后面的内容（通常是 URL）。
    ///   - theme: 当前主题。
    func render(payload: String, theme: MarkdownTheme) -> NSAttributedString
}

// MARK: - 代码块指令

/// 代码块自定义指令，用于处理带特定语言标识的围栏代码块。
///
/// 例如：` ```mermaid `、` ```echarts `。
/// 若未命中任何指令，渲染器会退回到普通代码块样式。
public protocol CodeBlockDirectiveRenderer {
    /// 代码块语言标识（小写），如 "mermaid"、"echarts"。
    var language: String { get }
    /// 将代码块内容渲染为富文本片段。
    func render(code: String, theme: MarkdownTheme) -> NSAttributedString
}

// MARK: - 注册表

/// 集中管理所有自定义指令。渲染器通过它查询可用的扩展。
public final class MarkdownDirectiveRegistry {

    private(set) var inlineDirectives: [String: InlineDirectiveRenderer] = [:]
    private(set) var codeBlockDirectives: [String: CodeBlockDirectiveRenderer] = [:]
    
    private(set) var imageDirectives: [String: ImageDirectiveRenderer] = [:]

    /// 内置默认指令（提示、音频、视频、mermaid、echarts）的注册表。
    public static var `default`: MarkdownDirectiveRegistry {
        let registry = MarkdownDirectiveRegistry()
        // 自定义格式：[tip:文字] → 高亮提示徽标
        registry.register(inline: TipInlineDirective())
        registry.register(inline: BadgeInlineDirective(name: "music", symbol: "🎵", label: "音频"))
        registry.register(inline: BadgeInlineDirective(name: "video", symbol: "🎬", label: "视频"))
        registry.register(codeBlock: PlaceholderCodeBlockDirective(language: "mermaid", title: "Mermaid 图表"))
        registry.register(codeBlock: PlaceholderCodeBlockDirective(language: "echarts", title: "ECharts 图表"))
        
        
        return registry
    }

    public init() {}

    public func register(inline directive: InlineDirectiveRenderer) {
        inlineDirectives[directive.name.lowercased()] = directive
    }

    public func register(codeBlock directive: CodeBlockDirectiveRenderer) {
        codeBlockDirectives[directive.language.lowercased()] = directive
    }
    
   

    func inlineDirective(named name: String) -> InlineDirectiveRenderer? {
        inlineDirectives[name.lowercased()]
    }

    func codeBlockDirective(for language: String?) -> CodeBlockDirectiveRenderer? {
        guard let language else { return nil }
        return codeBlockDirectives[language.lowercased()]
    }

    /// 供渲染器构造匹配 `[name:payload]` 的正则表达式。
    var inlineDirectivePattern: NSRegularExpression? {
        guard !inlineDirectives.isEmpty else { return nil }
        let names = inlineDirectives.keys.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\[(\(names.joined(separator: "|"))):([^\\]]+)\\]"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

// MARK: - 内置默认实现

/// 自定义格式：`[tip:文字]` → 一个醒目的提示徽标（💡 + 高亮背景 + 圆角观感）。
///
/// 用法示例（写在 Markdown 里）：
///     [tip:这是我自定义的提示格式 ✨]
///
/// 它属于“行内指令”，会被渲染器在扫描文本时识别并替换成带样式的富文本。
public struct TipInlineDirective: InlineDirectiveRenderer {
    public let name = "tip"

    public init() {}

    public func render(payload: String, theme: MarkdownTheme) -> NSAttributedString {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        // 用不间断空格 \u{00A0} 在文字两侧留白，让高亮背景看起来像一个“药丸”标签。
        return NSAttributedString(
            string: "\u{00A0}💡 \(text)\u{00A0}",
            attributes: [
                .font: UIFont.systemFont(ofSize: theme.bodyFont.pointSize, weight: .medium),
                .foregroundColor: theme.linkColor,
                .backgroundColor: theme.codeBackgroundColor,
            ]
        )
    }
}

/// 通用“徽标”式行内指令：展示一个图标 + 标签 + 可点击链接。
public struct BadgeInlineDirective: InlineDirectiveRenderer {
    public let name: String
    public let symbol: String
    public let label: String

    public init(name: String, symbol: String, label: String) {
        self.name = name
        self.symbol = symbol
        self.label = label
    }

    public func render(payload: String, theme: MarkdownTheme) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "  \(symbol) \(label)  ",
            attributes: [
                .font: theme.bodyFont,
                .foregroundColor: theme.linkColor,
                .backgroundColor: theme.codeBackgroundColor,
            ]
        )
        if let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)) {
            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
}

/// 通用“占位卡片”式代码块指令：用于 mermaid / echarts 等无法直接渲染的图表，
/// 展示一个标题 + 原始内容，避免信息丢失。
public struct PlaceholderCodeBlockDirective: CodeBlockDirectiveRenderer {
    public let language: String
    public let title: String

    public init(language: String, title: String) {
        self.language = language
        self.title = title
    }

    public func render(code: String, theme: MarkdownTheme) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 10
        paragraph.headIndent = 10
        paragraph.tailIndent = -10
        paragraph.paragraphSpacing = theme.paragraphSpacing
        paragraph.paragraphSpacingBefore = 6
        paragraph.lineSpacing = 2

        let result = NSMutableAttributedString(
            string: "▦ \(title)\n",
            attributes: [
                .font: UIFont.systemFont(ofSize: theme.bodyFont.pointSize, weight: .semibold),
                .foregroundColor: theme.textColor,
                .backgroundColor: theme.codeBackgroundColor,
                .paragraphStyle: paragraph,
            ]
        )
        let body = NSAttributedString(
            string: code.trimmingCharacters(in: .whitespacesAndNewlines),
            attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.secondaryTextColor,
                .backgroundColor: theme.codeBackgroundColor,
                .paragraphStyle: paragraph,
            ]
        )
        result.append(body)
        return result
    }
}
