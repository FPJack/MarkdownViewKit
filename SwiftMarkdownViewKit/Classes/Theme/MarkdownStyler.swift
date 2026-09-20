//
//  MarkdownStyler.swift
//  SwiftMarkdownViewKit
//
//  样式器。设计参考 Down 的 `Styler` / `DownStyler`：
//  渲染器（`MarkdownAttributedStringBuilder`）只负责「遍历语法树 + 组装结构」，
//  所有「长什么样」的决定权都交给 Styler，业务方可以：
//    1. 只改配置：`DefaultMarkdownStyler(configuration: myConfiguration)`；
//    2. 或继承覆写：`class MyStyler: DefaultMarkdownStyler { override func style(heading:…) }`。
//

import UIKit

// MARK: - 协议

public protocol MarkdownStyler: AnyObject {

    /// 当前使用的样式配置（字体 / 颜色 / 段落样式 / Options）。
    var configuration: MarkdownStylerConfiguration { get }

    /// 正文基础属性：所有纯文本片段的起点样式。
    var baseTextAttributes: [NSAttributedString.Key: Any] { get }

    func style(document str: NSMutableAttributedString)
    func style(paragraph str: NSMutableAttributedString)
    func style(heading str: NSMutableAttributedString, level: Int)
    func style(blockQuote str: NSMutableAttributedString, nestDepth: Int)
    func style(thematicBreak str: NSMutableAttributedString)

    func style(list str: NSMutableAttributedString, nestDepth: Int)
    func style(listItemPrefix str: NSMutableAttributedString)
    func style(item str: NSMutableAttributedString, nestDepth: Int)

    func style(codeBlock str: NSMutableAttributedString, fenceInfo: String?)
    func style(code str: NSMutableAttributedString)

    func style(text str: NSMutableAttributedString)
    func style(softBreak str: NSMutableAttributedString)
    func style(lineBreak str: NSMutableAttributedString)
    func style(emphasis str: NSMutableAttributedString)
    func style(strong str: NSMutableAttributedString)
    func style(strikethrough str: NSMutableAttributedString)
    func style(link str: NSMutableAttributedString, title: String?, url: String?)
    func style(image str: NSMutableAttributedString, title: String?, url: String?)

    func style(tableHeaderRow str: NSMutableAttributedString)
    func style(tableBodyRow str: NSMutableAttributedString)

    /// 分割线的文本表示（默认是一整行 `─`）。
    func thematicBreakString() -> NSAttributedString
}

// MARK: - 默认实现

open class DefaultMarkdownStyler: MarkdownStyler {

    // MARK: - Properties

    public let configuration: MarkdownStylerConfiguration

    public var fonts: MarkdownFontCollection { configuration.fonts }
    public var colors: MarkdownColorCollection { configuration.colors }
    public var paragraphStyles: MarkdownParagraphStyleCollection { configuration.paragraphStyles }

    public var listItemOptions: MarkdownListItemOptions { configuration.listItemOptions }
    public var quoteStripeOptions: MarkdownQuoteStripeOptions { configuration.quoteStripeOptions }
    public var thematicBreakOptions: MarkdownThematicBreakOptions { configuration.thematicBreakOptions }
    public var codeBlockOptions: MarkdownCodeBlockOptions { configuration.codeBlockOptions }
    public var imageOptions: MarkdownImageOptions { configuration.imageOptions }
    public var tableOptions: MarkdownTableOptions { configuration.tableOptions }

    open var baseTextAttributes: [NSAttributedString.Key: Any] {
        [.font: fonts.body, .foregroundColor: colors.body]
    }

    open var listItemPrefixAttributes: [NSAttributedString.Key: Any] {
        [.font: fonts.listItemPrefix, .foregroundColor: colors.listItemPrefix]
    }

    // MARK: - Life cycle

    public init(configuration: MarkdownStylerConfiguration = MarkdownStylerConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - 块级

    open func style(document str: NSMutableAttributedString) {}

    open func style(paragraph str: NSMutableAttributedString) {
        // 只填补「还没有段落样式」的区间，避免覆盖嵌套结构（列表 / 引用）已设置的样式。
        str.markdown_addAttributeInMissingRanges(.paragraphStyle, value: paragraphStyles.body)
    }

    open func style(heading str: NSMutableAttributedString, level: Int) {
        str.markdown_addAttributes([
            .font: fonts.heading(for: level),
            .foregroundColor: colors.heading(for: level),
            .paragraphStyle: paragraphStyles.heading(for: level),
        ])
    }

    open func style(blockQuote str: NSMutableAttributedString, nestDepth: Int) {
        let indentation = quoteStripeOptions.layoutWidth * CGFloat(nestDepth + 1)
        let style = paragraphStyles.body.markdown_indented(by: indentation)
        str.markdown_addAttributes([
            .paragraphStyle: style,
            .foregroundColor: colors.quote,
        ])
    }

    open func style(thematicBreak str: NSMutableAttributedString) {
        let style = paragraphStyles.body.markdown_modified {
            $0.paragraphSpacingBefore = thematicBreakOptions.spacingBefore
            $0.firstLineHeadIndent = thematicBreakOptions.indentation
            $0.headIndent = thematicBreakOptions.indentation
            $0.lineSpacing = 0
        }
        str.markdown_setAttributes([
            .font: MarkdownFont.systemFont(ofSize: thematicBreakOptions.fontSize),
            .foregroundColor: colors.thematicBreak,
            .paragraphStyle: style,
        ])
    }

    open func thematicBreakString() -> NSAttributedString {
        let line = String(repeating: String(thematicBreakOptions.character),
                          count: max(1, thematicBreakOptions.repeatCount))
        let result = NSMutableAttributedString(string: line)
        style(thematicBreak: result)
        return result
    }

    // MARK: - 列表

    open func style(list str: NSMutableAttributedString, nestDepth: Int) {}

    open func style(listItemPrefix str: NSMutableAttributedString) {
        str.markdown_setAttributes(listItemPrefixAttributes)
    }

    open func style(item str: NSMutableAttributedString, nestDepth: Int) {
        let indentation = CGFloat(max(0, nestDepth)) * listItemOptions.nestedIndentation
        let style = paragraphStyles.body.markdown_modified {
            $0.firstLineHeadIndent = indentation
            $0.headIndent = indentation + listItemOptions.nestedIndentation
            $0.paragraphSpacingBefore = listItemOptions.spacingAbove
            $0.paragraphSpacing = listItemOptions.spacingBelow
            $0.alignment = listItemOptions.alignment
        }
        str.markdown_addAttribute(.paragraphStyle, value: style)
    }

    // MARK: - 代码

    open func style(codeBlock str: NSMutableAttributedString, fenceInfo: String?) {
        str.markdown_setAttributes([
            .font: fonts.code,
            .foregroundColor: colors.code,
            .backgroundColor: colors.codeBlockBackground,
            .paragraphStyle: paragraphStyles.code.markdown_inset(by: codeBlockOptions.containerInset),
        ])
    }

    open func style(code str: NSMutableAttributedString) {
        str.markdown_setAttributes([
            .font: fonts.code,
            .foregroundColor: colors.code,
            .backgroundColor: colors.inlineCodeBackground,
        ])
    }

    // MARK: - 行内

    open func style(text str: NSMutableAttributedString) {
        str.markdown_setAttributes(baseTextAttributes)
    }

    open func style(softBreak str: NSMutableAttributedString) {
        str.markdown_addAttribute(.font, value: fonts.body)
    }

    open func style(lineBreak str: NSMutableAttributedString) {
        str.markdown_addAttribute(.font, value: fonts.body)
    }

    open func style(emphasis str: NSMutableAttributedString) {
        addTrait(.traitItalic, to: str)
    }

    open func style(strong str: NSMutableAttributedString) {
        addTrait(.traitBold, to: str)
    }

    open func style(strikethrough str: NSMutableAttributedString) {
        str.markdown_addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue)
    }

    open func style(link str: NSMutableAttributedString, title: String?, url: String?) {
        if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines),
           let target = URL(string: url) {
            str.markdown_addAttribute(.link, value: target)
        }
        str.markdown_addAttribute(.foregroundColor, value: colors.link)
    }

    open func style(image str: NSMutableAttributedString, title: String?, url: String?) {
        style(link: str, title: title, url: url)
    }

    // MARK: - 表格（纯文本兜底渲染）

    open func style(tableHeaderRow str: NSMutableAttributedString) {
        if tableOptions.boldHeader { addTrait(.traitBold, to: str) }
        str.markdown_addAttribute(.backgroundColor, value: colors.tableHeaderBackground)
    }

    open func style(tableBodyRow str: NSMutableAttributedString) {}

    // MARK: - Helpers

    /// 在保持原字号 / 原字体的前提下追加一个字形特征（加粗、斜体）。
    open func addTrait(_ trait: UIFontDescriptor.SymbolicTraits, to str: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: str.length)
        guard whole.length > 0 else { return }

        str.enumerateAttribute(.font, in: whole, options: []) { value, range, _ in
            let base = (value as? MarkdownFont) ?? fonts.body
            var traits = base.fontDescriptor.symbolicTraits
            traits.insert(trait)
            if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                str.addAttribute(.font, value: MarkdownFont(descriptor: descriptor, size: base.pointSize), range: range)
            }
        }
        str.enumerateAttribute(.foregroundColor, in: whole, options: []) { value, range, _ in
            if value == nil {
                str.addAttribute(.foregroundColor, value: colors.body, range: range)
            }
        }
    }
}

// MARK: - NSMutableAttributedString 便捷方法（对应 Down 的同名 helpers）

public extension NSMutableAttributedString {

    var markdown_wholeRange: NSRange { NSRange(location: 0, length: length) }

    func markdown_addAttribute(_ key: NSAttributedString.Key, value: Any) {
        guard length > 0 else { return }
        addAttribute(key, value: value, range: markdown_wholeRange)
    }

    func markdown_addAttributes(_ attributes: [NSAttributedString.Key: Any]) {
        guard length > 0 else { return }
        addAttributes(attributes, range: markdown_wholeRange)
    }

    func markdown_setAttributes(_ attributes: [NSAttributedString.Key: Any]) {
        guard length > 0 else { return }
        setAttributes(attributes, range: markdown_wholeRange)
    }

    /// 只给「尚未设置该属性」的区间赋值，避免覆盖嵌套结构已有的样式。
    func markdown_addAttributeInMissingRanges(_ key: NSAttributedString.Key, value: Any) {
        guard length > 0 else { return }
        enumerateAttribute(key, in: markdown_wholeRange, options: []) { existing, range, _ in
            if existing == nil {
                addAttribute(key, value: value, range: range)
            }
        }
    }
}
