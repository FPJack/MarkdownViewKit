//
//  BlockRule.swift
//  MarkdownKit
//
//  段落（块级）“规则”扩展点：与 `InlineRule` 对称，但作用于整段。
//
//  区别：
//  - `InlineRule` 在一段文字**内部**做局部替换（如 `@某人`、`¥9.9`）。
//  - `BlockRule`  作用于**整段纯文本**，命中的片段替换成自定义渲染
//    （如把 `::warning 文案` 渲染成一张警告卡片）。
//
//  冲突处理与 `InlineRuleScanner` 完全一致：收集所有命中 → 排序（位置→优先级→长度）
//  → 游标跳过重叠 → 命中之间的普通文字按默认属性填充后拼接。
//
//  用法：实现 `BlockRule` 并 `registry.register(rule:)` 注册即可，不改渲染器核心。
//

import UIKit

import Markdown

// MARK: - 规则协议

/// 段落级自定义规则：自带正则，命中整段后渲染成你想展示的富文本。
public protocol BlockRule: DirectiveRenderer {
    
    typealias MarkupType = Paragraph

    /// 唯一标识（用于去重 / 覆盖 / 调试）。
    var identifier: String { get }

    /// 优先级：多个规则命中同一段时，数值大者胜出。默认 100。
    var priority: Int { get }
    
    func matches(in string: String, options: NSRegularExpression.MatchingOptions , range: NSRange) -> [NSTextCheckingResult]?
    
}
public extension BlockRule {
    
    var priority: Int { 100 }
    public var viewType: any ViewLoadable.Type { PlaceholdView.self }
}



// MARK: - 解析器

/// 段落规则解析器：采用与 `InlineRuleScanner` **完全一致**的冲突处理逻辑。
///
/// 流程：收集所有规则的全部命中 → 排序（位置靠前 → 优先级高 → 匹配更长）
///      → 从左到右拼接，已占用区间内的命中被跳过、命中之间的普通文字按默认属性填充。
///
/// 返回值：
/// - 若整段没有任何命中，返回 `nil`（让渲染器走默认段落渲染）。
/// - 否则返回拼接后的整段富文本。
struct BlockRuleResolver {

    let rules: [BlockRule]

    func render(_ markup: Paragraph, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString? {
        let text = markup.format()
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: visitor.theme.fonts.body,
            .foregroundColor: visitor.theme.colors.body,
        ]

        // 命中之外的“空隙”文字：交给 Inline 规则渲染，实现 Block + Inline 组合
        // （否则 `$$...$$ @某人` 里的 `@某人` 会退化成纯文本，丢失行内高亮）。
        let inlineScanner = InlineRuleScanner(rules: visitor.directives.allInlineRules)
        func renderGap(_ gap: String) -> NSAttributedString {
            guard !gap.isEmpty else { return NSAttributedString() }
            guard !inlineScanner.rules.isEmpty else {
                return NSAttributedString(string: gap, attributes: baseAttributes)
            }
            return inlineScanner.render(Text(gap), visitor: visitor, baseAttributes: baseAttributes)
        }

        // 1) 收集所有规则命中的片段
        struct Hit { let range: NSRange; let priority: Int; let attributed: NSAttributedString }
        var hits: [Hit] = []
        for rule in rules {
            guard let matches = rule.matches(in: text, options: [], range: fullRange) else { continue }
            for match in matches {
                guard let attributed = rule.render(context: MarkupContext(markup: markup, visitor: visitor, match: match)) else { continue }
                hits.append(Hit(range: match.range, priority: rule.priority, attributed: attributed))
            }
        }
        guard !hits.isEmpty else { return nil } // 无命中 → 交给默认段落渲染

        // 2) 排序：位置升序 → 优先级降序 → 长度降序
        hits.sort { a, b in
            if a.range.location != b.range.location { return a.range.location < b.range.location }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.range.length > b.range.length
        }

        // 3) 从左到右拼接，填充普通文字，跳过重叠区间
        let result = NSMutableAttributedString()
        var cursor = 0
        for hit in hits {
            if hit.range.location < cursor { continue }
            if hit.range.location > cursor {
                let plain = source.substring(with: NSRange(location: cursor,
                                                           length: hit.range.location - cursor))
                result.append(renderGap(plain))
            }
            result.append(hit.attributed)
            cursor = hit.range.location + hit.range.length
        }
        if cursor < source.length {
            result.append(renderGap(source.substring(from: cursor)))
        }
        return result
    }
}

// MARK: - 取整段纯文本

extension Markup {
    /// 递归拼出该节点的纯文本内容（用于段落级正则匹配）。
    ///
    /// 只取“可见文字”，忽略样式标记本身：
    /// `**粗体**` → `粗体`；`[文字](url)` → `文字`；软/硬换行转成空格/换行。
    var plainTextContent: String {
        if let text = self as? Text { return text.string }
        if let code = self as? InlineCode { return code.code }
        if let inlineHTML = self as? InlineHTML { return inlineHTML.rawHTML }
        if self is SoftBreak { return " " }
        if self is LineBreak { return "\n" }
        return children.map { $0.plainTextContent }.joined()
    }
}

// MARK: - 示例：把 `::类型 文案` 整段渲染成一张 Callout 卡片

/// 示例规则：整段形如 `::warning 这是提醒` / `::info 说明` 时，
/// 渲染成一张带图标 + 背景色的提示卡片。业务方可仿此实现自己的段落规则。
public struct CalloutBlockRule: BlockRule {
    
    

    public let identifier = "callout"
    public let priority = 200

    // 整段：`::类型 剩余文案`，group1 = 类型，group2 = 文案
    private let regex = try! NSRegularExpression(pattern: "^::(\\w+)\\s+([\\s\\S]+)$")

    public init() {}

    public func matches(in string: String,
                        options: NSRegularExpression.MatchingOptions,
                        range: NSRange) -> [NSTextCheckingResult]? {
        regex.matches(in: string, options: options, range: range)
    }
    
    public func renderAttr(context: MarkupContext<Paragraph>) -> NSAttributedString? {
        guard let match = context.match else { return nil }
        let visitor = context.visitor
        let source = context.markup.plainText as NSString
        let type = source.substring(with: match.range(at: 1)).lowercased()
        let body = source.substring(with: match.range(at: 2))
        let theme = visitor.theme

        let icon: String
        let tint: UIColor
        switch type {
        case "warning": icon = "⚠️"; tint = .systemOrange
        case "danger", "error": icon = "⛔️"; tint = .systemRed
        case "success": icon = "✅"; tint = .systemGreen
        default: icon = "💡"; tint = theme.colors.link
        }

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.tailIndent = -12
        style.lineSpacing = theme.paragraphStyles.body.lineSpacing
        style.paragraphSpacing = theme.paragraphStyles.body.paragraphSpacing
        style.paragraphSpacingBefore = 6

        return NSAttributedString(
            string: "\(icon) \(body)",
            attributes: [
                .font: theme.fonts.body,
                .foregroundColor: tint,
                .backgroundColor: tint.withAlphaComponent(0.12),
                .paragraphStyle: style,
            ]
        )
    }
}


public struct ImageGroupRule: BlockRule {
    static let regex = try? NSRegularExpression(pattern: #"(?m)^(?:[ \t]*!\[[^\]]*\]\([^)\r\n]+\)[ \t]*(?:\r?\n|$)){2,}"#)
    public var identifier: String = "ImageGroupRule"
    public func matches(in string: String, options: NSRegularExpression.MatchingOptions, range: NSRange) -> [NSTextCheckingResult]? {
        let matches = Self.regex?.matches(in: string, options: options, range: range)
        return matches
    }
    public func renderView(context: MarkupContext<Paragraph>) -> (any ViewLoadable)? {
        return CarouselView()
    }
}
