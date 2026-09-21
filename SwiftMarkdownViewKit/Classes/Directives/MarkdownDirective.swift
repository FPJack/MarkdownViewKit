//
//  MarkdownDirective.swift
//  MarkdownKit
//
//  自定义指令扩展点。业务方可以注册新的行内 / 代码块指令，
//  无需修改渲染器核心，符合“开闭原则”，便于长期维护与扩展。
//

import UIKit

import Markdown


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


// MARK: - 注册表

/// 集中管理所有自定义指令。渲染器通过它查询可用的扩展。
public final class MarkdownDirectiveRegistry {

    private(set) var inlineDirectives: [String: InlineDirectiveRenderer] = [:]
    
    ///自定义代码块
    private(set) var codeBlockDirectives: [String: CodeBlockDirectiveRenderer] = [:]

    /// 自定义行内规则（自带正则），比 `[name:payload]` 更通用。
    private(set) var inlineRules: [InlineRule] = []

    /// 自定义段落（块级）规则（自带正则），命中则整段替换成自定义渲染。
    private(set) var blockRules: [BlockRule] = []

    private(set) var imageDirectives: [ImageDirectiveRenderer] = []
    
    /// 自定义表格渲染器。
    private(set) var table: TableDirectiveRenderer = TableRenderer()
    
    /// 自定义 HTML 渲染器。
    private(set) var htmlBlock: HtmlDirectiveRenderer = HtmlRenderer()
    
    ///自定义分割线渲染器
     
    
    

    /// 内置默认指令（提示、音频、视频、mermaid、echarts）的注册表。
    public static var `default`: MarkdownDirectiveRegistry {
        let registry = MarkdownDirectiveRegistry()
        // 自定义格式：[tip:文字] → 高亮提示徽标
        registry.register(inline: TipInlineDirective())
        registry.register(inline: BadgeInlineDirective(name: "music", symbol: "🎵", label: "音频"))
        registry.register(inline: BadgeInlineDirective(name: "video", symbol: "🎬", label: "视频"))
//        registry.register(codeBlock: PlaceholderCodeBlockDirective(language: "mermaid", title: "Mermaid 图表"))
        
        /// 注册自定义图片指令
        registry.register(image: ImageDirective())
        
        /// 注册自定义代码块指令)
    
        registry.register(codeBlock: CodeDirective())
        
        registry.register(codeBlock: MermaidDirectiveRenderer(language: "mermaid"))
        
        registry.register(codeBlock: EChartDirectiveRenderer(language: "echarts"))
        
        registry.register(table: TableRenderer())
        
        registry.register(rule: LatexDirectiveRenderer())
        
        registry.register(rule: MentionInlineRule() )
        
        registry.register(rule: YuanInlineRule() )
        
        registry.register(rule: ImageGroupRule())

        
        return registry
    }

    public init() {}

    public func register(inline directive: InlineDirectiveRenderer) {
        inlineDirectives[directive.name.lowercased()] = directive
    }
    
    
    /// 注册一条自定义图片指令。
    public func register(image directive: ImageDirectiveRenderer) {
        imageDirectives.append(directive)
    }
    
    func imageDirective(for title: String? ) -> ImageDirectiveRenderer {
        let title = title ?? ""
        for directive in imageDirectives {
            if directive.title.lowercased() == title.lowercased() {
                return directive
            }
        }
        return imageDirective(for: "")
    }

    
    /// 注册一条自定义代码块指令。
    public func register(codeBlock directive: CodeBlockDirectiveRenderer) {
        codeBlockDirectives[directive.language.lowercased()] = directive
    }
    func codeBlockDirective(for language: String?) -> CodeBlockDirectiveRenderer? {
        let language = language ?? ""
        if let directive = codeBlockDirectives[language.lowercased()] {
            return directive
        }
        return codeBlockDirective(for: "")
    }
    
    
    /// 注册一条自定义表格渲染器。
    public func register(table: TableDirectiveRenderer) {
        self.table = table
    }
    public func tableDirective() -> TableDirectiveRenderer {
        return table
    }
    
    public func register(htmlBlock: HtmlDirectiveRenderer) {
        self.htmlBlock = htmlBlock
    }
    public func htmlBlockDirective() -> HtmlDirectiveRenderer {
        return htmlBlock
    }
   
    /// 注册一条自定义行内规则（自带正则）。
    public func register(rule: InlineRule) {
        inlineRules.append(rule)
    }

    /// 注册一条自定义段落（块级）规则（自带正则）。
    public func register(rule: BlockRule) {
        blockRules.append(rule)
    }
    
    

    func inlineDirective(named name: String) -> InlineDirectiveRenderer? {
        inlineDirectives[name.lowercased()]
    }

   

    /// 渲染器实际使用的全部行内规则：自定义规则 + 兼容旧 `[name:payload]` 的规则。
    /// 旧指令的规则优先级最低（0），保证自定义规则可以覆盖它。
    var allInlineRules: [InlineRule] {
        var rules = inlineRules
        if let legacy = LegacyNamedInlineRule(names: Array(inlineDirectives.keys),
                                              lookup: { [weak self] in self?.inlineDirective(named: $0) }) {
            rules.append(legacy)
        }
        return rules
    }

    /// 渲染器实际使用的全部段落（块级）规则。
    var allBlockRules: [BlockRule] { blockRules }

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
                .font: UIFont.systemFont(ofSize: theme.fonts.body.pointSize, weight: .medium),
                .foregroundColor: theme.colors.link,
                .backgroundColor: theme.colors.inlineCodeBackground,
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
                .font: theme.fonts.body,
                .foregroundColor: theme.colors.link,
                .backgroundColor: theme.colors.inlineCodeBackground,
            ]
        )
        if let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)) {
            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
}
