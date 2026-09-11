//
//  MarkdownTheme.swift
//  MarkdownKit
//
//  可复用的 Markdown 渲染主题。集中管理所有字体、颜色与间距，
//  业务方只需替换 Theme 即可整体换肤，无需改动渲染逻辑。
//

import UIKit

/// 描述一段富文本渲染时使用的全部视觉样式。
///
/// 设计目标：
/// - 所有样式集中在一处，方便统一修改与主题切换（明/暗）。
/// - 渲染器（`MarkdownAttributedStringBuilder`）只依赖本协议式的数据结构，
///   与具体样式解耦，便于扩展。
public struct MarkdownTheme {

    // MARK: - 字体

    /// 正文字体。
    public var bodyFont: UIFont
    /// 一至六级标题字体（下标 0 对应 H1）。
    public var headingFonts: [UIFont]
    /// 行内代码 / 代码块字体（等宽）。
    public var codeFont: UIFont

    // MARK: - 颜色

    /// 正文颜色。
    public var textColor: UIColor
    /// 次要文字颜色（引用、说明等）。
    public var secondaryTextColor: UIColor
    /// 链接颜色。
    public var linkColor: UIColor
    /// 行内代码 / 代码块文字颜色。
    public var codeTextColor: UIColor
    /// 代码块背景色。
    public var codeBackgroundColor: UIColor
    /// 引用文字颜色。
    public var quoteTextColor: UIColor
    /// 引用左侧竖条颜色。
    public var quoteBarColor: UIColor
    /// 分割线颜色。
    public var ruleColor: UIColor
    /// 表格表头背景色。
    public var tableHeaderBackgroundColor: UIColor
    /// 表格边框 / 分隔色。
    public var tableBorderColor: UIColor

    // MARK: - 间距

    /// 段落之间的垂直间距。
    public var paragraphSpacing: CGFloat
    /// 行间距。
    public var lineSpacing: CGFloat
    /// 标题前的额外间距。
    public var headingSpacingBefore: CGFloat
    /// 列表每一级的缩进宽度。
    public var listIndent: CGFloat
    /// 引用块的缩进宽度。
    public var quoteIndent: CGFloat
    /// 图片默认占位高度（图片加载完成前）。
    public var imagePlaceholderHeight: CGFloat

    public init(bodyFont: UIFont,
                headingFonts: [UIFont],
                codeFont: UIFont,
                textColor: UIColor,
                secondaryTextColor: UIColor,
                linkColor: UIColor,
                codeTextColor: UIColor,
                codeBackgroundColor: UIColor,
                quoteTextColor: UIColor,
                quoteBarColor: UIColor,
                ruleColor: UIColor,
                tableHeaderBackgroundColor: UIColor,
                tableBorderColor: UIColor,
                paragraphSpacing: CGFloat,
                lineSpacing: CGFloat,
                headingSpacingBefore: CGFloat,
                listIndent: CGFloat,
                quoteIndent: CGFloat,
                imagePlaceholderHeight: CGFloat) {
        self.bodyFont = bodyFont
        self.headingFonts = headingFonts
        self.codeFont = codeFont
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.codeTextColor = codeTextColor
        self.codeBackgroundColor = codeBackgroundColor
        self.quoteTextColor = quoteTextColor
        self.quoteBarColor = quoteBarColor
        self.ruleColor = ruleColor
        self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
        self.tableBorderColor = tableBorderColor
        self.paragraphSpacing = paragraphSpacing
        self.lineSpacing = lineSpacing
        self.headingSpacingBefore = headingSpacingBefore
        self.listIndent = listIndent
        self.quoteIndent = quoteIndent
        self.imagePlaceholderHeight = imagePlaceholderHeight
    }

    /// 返回指定级别（1...6）标题字体，越界时回退到最接近的一个。
    public func headingFont(level: Int) -> UIFont {
        let index = min(max(level, 1), headingFonts.count) - 1
        return headingFonts[index]
    }
}

// MARK: - 预设主题

public extension MarkdownTheme {

    /// 自动适配系统明暗模式的默认主题。
    static var `default`: MarkdownTheme {
        MarkdownTheme(
            bodyFont: .systemFont(ofSize: 17),
            headingFonts: [
                .systemFont(ofSize: 28, weight: .bold),
                .systemFont(ofSize: 24, weight: .bold),
                .systemFont(ofSize: 20, weight: .semibold),
                .systemFont(ofSize: 18, weight: .semibold),
                .systemFont(ofSize: 17, weight: .semibold),
                .systemFont(ofSize: 16, weight: .semibold),
            ],
            codeFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .systemBlue,
            codeTextColor: .label,
            codeBackgroundColor: UIColor.secondarySystemBackground,
            quoteTextColor: .secondaryLabel,
            quoteBarColor: .systemGray3,
            ruleColor: .separator,
            tableHeaderBackgroundColor: UIColor.secondarySystemBackground,
            tableBorderColor: .separator,
            paragraphSpacing: 12,
            lineSpacing: 4,
            headingSpacingBefore: 14,
            listIndent: 22,
            quoteIndent: 16,
            imagePlaceholderHeight: 180
        )
    }
}
