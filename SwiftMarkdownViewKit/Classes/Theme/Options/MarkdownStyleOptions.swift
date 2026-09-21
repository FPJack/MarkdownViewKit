//
//  MarkdownStyleOptions.swift
//  SwiftMarkdownViewKit
//
//  各类细节样式参数。设计参考 Down 的
//  `ListItemOptions` / `QuoteStripeOptions` / `ThematicBreakOptions` / `CodeBlockOptions`，
//  并按本库的能力补充了图片与表格的参数。
//

import UIKit

// MARK: - 强调（*斜体*）

/// `*强调*` 的呈现方式。
///
/// 存在的意义：**阿拉伯语 / 希伯来语没有「斜体」这个概念**。
/// 对这些文字套 `.traitItalic`，系统只能生成「机械倾斜」（synthetic oblique）——
/// 把字形整体切变一个角度，结果是连笔断裂、可读性明显下降。
/// 所以 RTL 场景通常改用其他视觉手段来表达强调。
public enum MarkdownEmphasisStyle {

    /// 斜体（拉丁文 / 中文的常规做法）。
    case italic
    /// 加粗。
    case bold
    /// 下划线。
    case underline
    /// 换一种颜色（用 `colors.link` 之外的自定义色）。
    case color(MarkdownColor)
    /// 不做任何视觉区分。
    case none
}

// MARK: - 列表

public struct MarkdownListItemOptions {

    /// 有序列表序号最多按几位数字预留宽度。
    public var maxPrefixDigits: UInt
    /// 序号 / 圆点与内容之间的间距。
    public var spacingAfterPrefix: CGFloat
    /// 列表项上方间距。
    public var spacingAbove: CGFloat
    /// 列表项下方间距。
    public var spacingBelow: CGFloat
    /// 每嵌套一层增加的缩进宽度。
    public var nestedIndentation: CGFloat
    public var alignment: NSTextAlignment

    public init(maxPrefixDigits: UInt = 2,
                spacingAfterPrefix: CGFloat = 8,
                spacingAbove: CGFloat = 0,
                spacingBelow: CGFloat = 4,
                nestedIndentation: CGFloat = 22,
                alignment: NSTextAlignment = .natural) {
        self.maxPrefixDigits = maxPrefixDigits
        self.spacingAfterPrefix = spacingAfterPrefix
        self.spacingAbove = spacingAbove
        self.spacingBelow = spacingBelow
        self.nestedIndentation = nestedIndentation
        self.alignment = alignment
    }
}

// MARK: - 引用

public struct MarkdownQuoteStripeOptions {

    /// 左侧竖条粗细。
    public var thickness: CGFloat
    /// 竖条与文字之间的间距。
    public var spacingAfter: CGFloat
    /// 整块背景的圆角。
    public var backgroundCornerRadius: CGFloat
    /// 整块背景相对文字行片段的外扩量。
    ///
    /// 正数表示背景比文字更大一圈（视觉上的内边距）。
    /// `top` / `bottom` 只作用于引用块的首行上方与末行下方，
    /// 中间行不加，否则块内会出现横向条纹。
    public var backgroundInsets: UIEdgeInsets
    /// 背景是否把左侧竖条所占的区域一起覆盖。
    ///
    /// `true`（默认）：背景从竖条外缘开始，竖条压在背景之上，观感是「一整块卡片」。
    /// `false`：背景只覆盖文字区，竖条独立在外。
    public var backgroundCoversStripe: Bool

    /// 引用整体的缩进宽度（竖条 + 间距）。
    public var layoutWidth: CGFloat { thickness + spacingAfter }

    public init(thickness: CGFloat = 4,
                spacingAfter: CGFloat = 12,
                backgroundCornerRadius: CGFloat = 0,
                backgroundInsets: UIEdgeInsets = .zero,
                backgroundCoversStripe: Bool = true) {
        self.thickness = thickness
        self.spacingAfter = spacingAfter
        self.backgroundCornerRadius = backgroundCornerRadius
        self.backgroundInsets = backgroundInsets
        self.backgroundCoversStripe = backgroundCoversStripe
    }
}

// MARK: - 分割线

public struct MarkdownThematicBreakOptions {

    /// 组成分割线的字符。
    public var character: Character
    /// 重复次数。
    public var repeatCount: Int
    /// 字号（决定线条视觉粗细）。
    public var fontSize: CGFloat
    /// 左侧缩进。
    public var indentation: CGFloat
    /// 分割线上方的额外间距。
    public var spacingBefore: CGFloat

    public init(character: Character = "─",
                repeatCount: Int = 40,
                fontSize: CGFloat = 12,
                indentation: CGFloat = 0,
                spacingBefore: CGFloat = 6) {
        self.character = character
        self.repeatCount = repeatCount
        self.fontSize = fontSize
        self.indentation = indentation
        self.spacingBefore = spacingBefore
    }
}

// MARK: - 代码块

public struct MarkdownCodeBlockOptions {

    /// 代码块容器内缩。
    public var containerInset: CGFloat
    /// 圆角（供自定义代码块视图使用）。
    public var cornerRadius: CGFloat

    public init(containerInset: CGFloat = 8, cornerRadius: CGFloat = 8) {
        self.containerInset = containerInset
        self.cornerRadius = cornerRadius
    }
}

// MARK: - 图片

public struct MarkdownImageOptions {

    /// 图片加载完成前的占位高度。
    public var placeholderHeight: CGFloat

    public init(placeholderHeight: CGFloat = 180) {
        self.placeholderHeight = placeholderHeight
    }
}

// MARK: - 表格

public struct MarkdownTableOptions {

    /// 纯文本兜底渲染时每列的制表位宽度。
    public var columnWidth: CGFloat
    /// 行间距。
    public var rowSpacing: CGFloat
    /// 表头是否加粗。
    public var boldHeader: Bool

    public init(columnWidth: CGFloat = 92, rowSpacing: CGFloat = 2, boldHeader: Bool = true) {
        self.columnWidth = columnWidth
        self.rowSpacing = rowSpacing
        self.boldHeader = boldHeader
    }
}
