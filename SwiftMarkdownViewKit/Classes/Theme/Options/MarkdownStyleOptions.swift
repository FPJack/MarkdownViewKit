//
//  MarkdownStyleOptions.swift
//  SwiftMarkdownViewKit
//
//  各类细节样式参数。设计参考 Down 的
//  `ListItemOptions` / `QuoteStripeOptions` / `ThematicBreakOptions` / `CodeBlockOptions`，
//  并按本库的能力补充了图片与表格的参数。
//

import UIKit

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

    /// 引用整体的缩进宽度（竖条 + 间距）。
    public var layoutWidth: CGFloat { thickness + spacingAfter }

    public init(thickness: CGFloat = 4, spacingAfter: CGFloat = 12) {
        self.thickness = thickness
        self.spacingAfter = spacingAfter
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
