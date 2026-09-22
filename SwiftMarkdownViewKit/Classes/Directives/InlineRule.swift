//
//  InlineRule.swift
//  MarkdownKit
//
//  行内“规则”扩展点：与 `BlockRule` 对称，但作用于一段文字内部。
//
//  区别：
//  - `InlineRule` 在一段文字**内部**做局部替换（如 `@某人`、`¥9.9`、`:smile:`）。
//  - `BlockRule`  判断**整段**是否命中某正则，命中就把整段替换成自定义渲染。
//
//  旧的 `InlineDirectiveRenderer` 把语法写死成 `[name:payload]`，只能改 name/payload，
//  无法表达 `@用户`、`#话题`、`$1.99`、行内 `$E=mc^2$` 公式 等其它形态。
//
//  这里把“匹配什么(正则)”与“渲染成什么(富文本)”封装进同一个规则对象：
//  每条规则自己拥有 `matches(...)` 与 `render(...)`；再由 `InlineRuleScanner`
//  统一跑所有规则、处理重叠冲突、拼接文本。新增一种行内元素 = 新增一个 `InlineRule`，不改核心。
//

import UIKit

import Markdown

// MARK: - 规则协议

/// 行内自定义规则：自带匹配逻辑，命中后把匹配片段渲染成你想展示的富文本。
public protocol InlineRule: DirectiveRenderer {
    
    typealias MarkupType = Text

    /// 唯一标识（用于去重 / 覆盖 / 调试）。
    var identifier: String { get }

    /// 优先级：多个规则命中同一段文本（重叠）时，数值大者胜出。默认 100。
    var priority: Int { get }

    /// 在文本里查找所有命中位置（规则自己拥有匹配逻辑，互不影响）。
    /// - Returns: 命中结果数组；无命中时可返回空数组或 `nil`。
    func matches(in string: String,
                 options: NSRegularExpression.MatchingOptions,
                 range: NSRange) -> [NSTextCheckingResult]?
}


public extension InlineRule {
    var priority: Int { 100 }
    public var viewType: any ViewLoadable.Type { PlaceholdView.self }

}

// MARK: - 扫描引擎

/// 跑完所有规则、处理重叠冲突、把整段文本拼成富文本。
///
/// 冲突裁决：位置靠前优先 → 优先级高优先 → 匹配更长优先；已占用区间会被跳过。
struct InlineRuleScanner {

    let rules: [InlineRule]
    
    

    func render(_ markup: Text,
                visitor: MarkdownAttributedStringBuilder,
                baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {

        let string = markup.string
        let source = string as NSString
        let fullRange = NSRange(location: 0, length: source.length)

        // 1) 收集所有规则命中的片段
        struct Hit { let range: NSRange; let priority: Int; let attributed: NSAttributedString }
        var hits: [Hit] = []
        for rule in rules {
            guard let matches = rule.matches(in: string, options: [], range: fullRange) else { continue }
            for match in matches {
                
                guard let attributed = rule.render(context:MarkupContext(markup: markup, visitor: visitor,match: match)) else { continue }
                hits.append(Hit(range: match.range, priority: rule.priority, attributed: attributed))
            }
        }
        guard !hits.isEmpty else {
            return NSAttributedString(string: string, attributes: baseAttributes)
        }

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
                result.append(NSAttributedString(string: plain, attributes: baseAttributes))
            }
            result.append(hit.attributed)
            cursor = hit.range.location + hit.range.length
        }
        if cursor < source.length {
            result.append(NSAttributedString(string: source.substring(from: cursor),
                                             attributes: baseAttributes))
        }
        return result
    }
}

// MARK: - 兼容适配：把旧的 [name:payload] 指令包成一条规则（优先级最低）

struct LegacyNamedInlineRule: InlineRule {

    let identifier = "builtin.named-directive"
    let priority = 0

    private let regex: NSRegularExpression
    private let lookup: (String) -> InlineDirectiveRenderer?

    /// 用注册表里已有的指令名构造 `[(a|b|c):payload]` 正则；无指令时返回 nil。
    init?(names: [String], lookup: @escaping (String) -> InlineDirectiveRenderer?) {
        guard !names.isEmpty else { return nil }
        let escaped = names.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\[(\(escaped.joined(separator: "|"))):([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        self.regex = regex
        self.lookup = lookup
    }

    func matches(in string: String,
                 options: NSRegularExpression.MatchingOptions,
                 range: NSRange) -> [NSTextCheckingResult]? {
        regex.matches(in: string, options: options, range: range)
    }
    func renderAttr(context: MarkupContext<Text>) -> NSAttributedString? {
        guard let match = context.match else { return nil }
        let source = context.markup.string as NSString
        let name = source.substring(with: match.range(at: 1))
        let payload = source.substring(with: match.range(at: 2))
        guard let directive = lookup(name) else { return nil } // 未注册 → 回退普通文本
        return directive.render(payload: payload, theme: context.visitor.theme)
    }

}

// MARK: - 示例：任意“正则 → 自定义展示”规则

/// 示例：把 `@某人` 渲染成可点击的蓝色徽标。业务方可仿此实现自己的规则。
public struct MentionInlineRule: InlineRule {

    public let identifier = "mention"
    public let priority = 200

    private let regex = try! NSRegularExpression(pattern: "@([^\\s]+)")

    public init() {}

    public func matches(in string: String,
                        options: NSRegularExpression.MatchingOptions,
                        range: NSRange) -> [NSTextCheckingResult]? {
        regex.matches(in: string, options: options, range: range)
    }
    public func renderAttr(context: MarkupContext<Text>) -> NSAttributedString? {
        guard let match = context.match else { return nil }
        let source = context.markup.string as NSString
        let whole = source.substring(with: match.range)
        let name = source.substring(with: match.range(at: 1))
        let result = NSMutableAttributedString(
            string: whole,
            attributes: [.font: context.visitor.theme.fonts.body, .foregroundColor: context.visitor.theme.colors.link]
        )
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? name
        if let url = URL(string: "mention://\(encoded)") {
            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

}


public struct YuanInlineRule: InlineRule {

    public let identifier = "yuan"
    
    public let priority = 300

    private let regex = try! NSRegularExpression(pattern: "¥([\\w\\p{Han}]+)")

    public init() {}

    public func matches(in string: String,
                        options: NSRegularExpression.MatchingOptions,
                        range: NSRange) -> [NSTextCheckingResult]? {
        regex.matches(in: string, options: options, range: range)
    }

    public func renderAttr(context: MarkupContext<Text>) -> NSAttributedString? {
        guard let match = context.match else { return nil }
        let source = context.markup.string as NSString
        let whole = source.substring(with: match.range)
        let name = source.substring(with: match.range(at: 1))
        let result = NSMutableAttributedString(
            string: whole,
            attributes: [.font: context.visitor.theme.fonts.body, .foregroundColor: UIColor.orange]
        )
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? name
        if let url = URL(string: "yuan://\(encoded)") {
//            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

}
