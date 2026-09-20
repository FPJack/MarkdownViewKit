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

    /// 当前排版方向（LTR / RTL）。
    public var layoutDirection: MarkdownLayoutDirection { configuration.layoutDirection }

    /// 当前是否按从右到左排版。
    public var isRightToLeft: Bool { configuration.isRightToLeft }

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

    // MARK: - 方向化的段落样式
    //
    // 配置里存的 `paragraphStyles` 是「方向无关」的纯数值（行距 / 段距）。
    // 这里统一补上 `baseWritingDirection`，TextKit 会据此把
    // firstLineHeadIndent / headIndent / tailIndent 以及 `.natural` 对齐
    // 自动镜像到正确的一侧，业务方无需关心左右。

    /// 正文段落样式（已套用当前排版方向）。
    open var bodyParagraphStyle: NSParagraphStyle {
        directed(paragraphStyles.body)
    }

    /// 指定级别标题的段落样式（已套用当前排版方向）。
    open func headingParagraphStyle(for level: Int) -> NSParagraphStyle {
        directed(paragraphStyles.heading(for: level))
    }

    /// 代码段落样式。
    ///
    /// 注意：代码**永远强制从左到右**。否则在 RTL 段落里，
    /// `if (a > b) {` 这类文本会被 Unicode 双向算法重排成乱序。
    /// 行高也不做 RTL 抬高——代码是等宽排版，抬高行框会破坏观感。
    open var codeParagraphStyle: NSParagraphStyle {
        paragraphStyles.code.markdown_forcedLeftToRight()
    }

    /// 套用方向 + RTL 行高补偿。
    ///
    /// 行高补偿的原因：阿拉伯语的变音符号（تشكيل）与部分字母降部会超出
    /// 拉丁字体的默认行框，不抬高会被裁切。
    private func directed(_ style: NSParagraphStyle) -> NSParagraphStyle {
        let directed = style.markdown_directed(layoutDirection)
        guard isRightToLeft,
              configuration.rightToLeftLineHeightMultiple > 1 else { return directed }
        return directed.markdown_modified {
            $0.lineHeightMultiple = configuration.rightToLeftLineHeightMultiple
        }
    }

    // MARK: - 块级

    open func style(document str: NSMutableAttributedString) {}

    open func style(paragraph str: NSMutableAttributedString) {
        // 只填补「还没有段落样式」的区间，避免覆盖嵌套结构（列表 / 引用）已设置的样式。
        str.markdown_addAttributeInMissingRanges(.paragraphStyle, value: bodyParagraphStyle)
    }

    open func style(heading str: NSMutableAttributedString, level: Int) {
        str.markdown_addAttributes([
            .font: fonts.heading(for: level),
            .foregroundColor: colors.heading(for: level),
            .paragraphStyle: headingParagraphStyle(for: level),
        ])
    }

    open func style(blockQuote str: NSMutableAttributedString, nestDepth: Int) {
        let indentation = quoteStripeOptions.layoutWidth * CGFloat(nestDepth + 1)
        // RTL 下 headIndent 表示「右侧」缩进，方向由 baseWritingDirection 决定，无需手工镜像。
        let style = bodyParagraphStyle.markdown_indented(by: indentation)
        str.markdown_addAttributes([
            .paragraphStyle: style,
            .foregroundColor: colors.quote,
        ])
    }

    open func style(thematicBreak str: NSMutableAttributedString) {
        let style = bodyParagraphStyle.markdown_modified {
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
        let style = bodyParagraphStyle.markdown_modified {
            // headIndent 是「行首一侧」的缩进：RTL 下自动作用于右侧。
            $0.firstLineHeadIndent = indentation
            $0.headIndent = indentation + listItemOptions.nestedIndentation
            $0.paragraphSpacingBefore = listItemOptions.spacingAbove
            $0.paragraphSpacing = listItemOptions.spacingBelow
            // 同样要显式解析：`.natural` 跟的是 App 语言，不是段落方向。
            $0.alignment = layoutDirection.resolvedAlignment(listItemOptions.alignment)
        }
        str.markdown_addAttribute(.paragraphStyle, value: style)
    }

    // MARK: - 代码

    open func style(codeBlock str: NSMutableAttributedString, fenceInfo: String?) {
        str.markdown_setAttributes([
            .font: fonts.code,
            .foregroundColor: colors.code,
            .backgroundColor: colors.codeBlockBackground,
            // 代码块强制 LTR，避免 RTL 段落把代码重排乱。
            .paragraphStyle: codeParagraphStyle.markdown_inset(by: codeBlockOptions.containerInset),
        ])
    }

    open func style(code str: NSMutableAttributedString) {
        str.markdown_setAttributes([
            .font: fonts.code,
            .foregroundColor: colors.code,
            .backgroundColor: colors.inlineCodeBackground,
            // 行内代码用「首字符定向隔离」包住，避免夹在阿拉伯语中间时标点跑位。
            .writingDirection: [NSWritingDirection.leftToRight.rawValue | NSWritingDirectionFormatType.override.rawValue],
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
        // 强调的呈现方式按方向切换：阿拉伯语 / 希伯来语没有斜体，
        // 机械倾斜会让连笔断裂，默认改用加粗。详见 `MarkdownEmphasisStyle`。
        apply(configuration.effectiveEmphasisStyle, to: str)
    }

    /// 按指定方式给一段文本加上「强调」的视觉表现。
    open func apply(_ style: MarkdownEmphasisStyle, to str: NSMutableAttributedString) {
        switch style {
        case .italic:
            addTrait(.traitItalic, to: str)
        case .bold:
            addTrait(.traitBold, to: str)
        case .underline:
            str.markdown_addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue)
        case .color(let color):
            str.markdown_addAttribute(.foregroundColor, value: color)
        case .none:
            break
        }
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
