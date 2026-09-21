//
//  MarkdownLayoutManager.swift
//  SwiftMarkdownViewKit
//
//  负责绘制「靠属性描述不出来」的块级装饰：引用块的整块背景与左侧竖条。
//  设计参考 Down 的 `DownLayoutManager` + `QuoteStripeAttribute`。
//
//  为什么必须自定义 LayoutManager：
//  `NSAttributedString.Key.backgroundColor` 只会给**字形外接矩形**上色，
//  缩进区、行尾空白、行间距都会漏底，多行引用看起来是一条条断开的色块。
//  真正的「整块背景」必须按 line fragment 逐行绘制，这只有 LayoutManager 能做。
//

import UIKit

// MARK: - 自定义属性

public extension NSAttributedString.Key {

    /// 标记一段文本属于引用块，值为 `MarkdownQuoteDecoration`。
    static let markdownQuote = NSAttributedString.Key("MarkdownQuote")
}

/// 描述一段引用文本需要绘制的装饰。
///
/// 之所以把颜色 / 参数整包塞进属性，而不是让 LayoutManager 去读全局配置：
/// 同一个 `UITextView` 里可能先后渲染多份配置不同的内容（换肤、A/B 对比），
/// 装饰信息跟着文本走才不会串味。
public struct MarkdownQuoteDecoration {

    /// 嵌套层级，0 表示最外层。
    public let nestDepth: Int
    /// 整块背景色。`.clear` 表示不绘制。
    public let backgroundColor: MarkdownColor
    /// 左侧竖条颜色。`.clear` 表示不绘制。
    public let stripeColor: MarkdownColor
    /// 竖条与背景的尺寸参数。
    public let options: MarkdownQuoteStripeOptions
    /// 排版方向。RTL 时竖条与缩进在右侧。
    public let isRightToLeft: Bool

    public init(nestDepth: Int,
                backgroundColor: MarkdownColor,
                stripeColor: MarkdownColor,
                options: MarkdownQuoteStripeOptions,
                isRightToLeft: Bool) {
        self.nestDepth = nestDepth
        self.backgroundColor = backgroundColor
        self.stripeColor = stripeColor
        self.options = options
        self.isRightToLeft = isRightToLeft
    }

    /// 是否有任何需要绘制的东西。全透明时直接跳过，省掉一次遍历。
    var hasVisibleDecoration: Bool {
        backgroundColor.cgColor.alpha > 0 || stripeColor.cgColor.alpha > 0
    }
}

// MARK: - LayoutManager

/// 绘制引用块装饰的 `NSLayoutManager`。
open class MarkdownLayoutManager: NSLayoutManager {

    open override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawQuoteDecorations(forGlyphRange: glyphsToShow, at: origin)
    }

    // MARK: - 引用块装饰

    private func drawQuoteDecorations(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let textStorage = textStorage, let context = UIGraphicsGetCurrentContext() else { return }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.markdownQuote,
                                       in: characterRange,
                                       options: []) { value, range, _ in
            guard let decoration = value as? MarkdownQuoteDecoration,
                  decoration.hasVisibleDecoration else { return }
            draw(decoration, characterRange: range, origin: origin, in: context)
        }
    }

    private func draw(_ decoration: MarkdownQuoteDecoration,
                      characterRange: NSRange,
                      origin: CGPoint,
                      in context: CGContext) {

        let glyphRange = self.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        // 先把这段引用涉及的所有行片段收集起来，再统一绘制。
        //
        // 不能「边遍历边画」：首行 / 末行需要额外的上下留白（backgroundInsets），
        // 而是否首行末行只有把整段扫完才知道。
        var fragments: [CGRect] = []
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            fragments.append(usedRect)
        }
        guard !fragments.isEmpty else { return }

        let options = decoration.options
        let insets = options.backgroundInsets

        context.saveGState()
        defer { context.restoreGState() }

        // 背景：把所有行片段合并成一个矩形整块绘制。
        //
        // 逐行画会在行与行之间留下 1px 级别的接缝（行片段高度取整导致），
        // 圆角也没法只加在首尾。合并成一块既没缝也好加圆角。
        if decoration.backgroundColor.cgColor.alpha > 0 {
            let minY = fragments.map { $0.minY }.min()! - insets.top
            let maxY = fragments.map { $0.maxY }.max()! + insets.bottom
            // 横向取最宽的那一行，保证短行也有完整背景。
            let minX = fragments.map { $0.minX }.min()!
            let maxX = fragments.map { $0.maxX }.max()!

            var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            // 背景默认覆盖竖条区域：RTL 时向右扩，LTR 时向左扩。
            // 扩的宽度要按嵌套层数算，否则内层引用的背景会盖不住外层竖条。
            if options.backgroundCoversStripe {
                let extra = options.layoutWidth * CGFloat(decoration.nestDepth + 1)
                if decoration.isRightToLeft {
                    rect.size.width += extra
                } else {
                    rect.origin.x -= extra
                    rect.size.width += extra
                }
            }
            rect = rect.insetBy(dx: -insets.left, dy: 0)
            rect = rect.offsetBy(dx: origin.x, dy: origin.y)

            decoration.backgroundColor.setFill()
            if options.backgroundCornerRadius > 0 {
                UIBezierPath(roundedRect: rect,
                             cornerRadius: options.backgroundCornerRadius).fill()
            } else {
                context.fill(rect)
            }
        }

        // 竖条：逐行绘制，这样引用块中间被图片 / 代码块打断时也能正确跟随。
        //
        // 嵌套引用要画 nestDepth + 1 条：三级嵌套就是三条平行竖条，
        // 与 GitHub / Typora 的观感一致。
        if decoration.stripeColor.cgColor.alpha > 0, options.thickness > 0 {
            decoration.stripeColor.setFill()
            let levelCount = decoration.nestDepth + 1
            for fragment in fragments {
                for level in 0..<levelCount {
                    // 文字起点距最外层竖条 layoutWidth * levelCount，
                    // 第 level 条竖条再从文字起点往外推回去。
                    let outwardOffset = options.layoutWidth * CGFloat(levelCount - level)
                    let x: CGFloat = decoration.isRightToLeft
                        ? fragment.maxX + outwardOffset - options.layoutWidth + options.spacingAfter
                        : fragment.minX - outwardOffset
                    let rect = CGRect(x: x + origin.x,
                                      y: fragment.minY + origin.y,
                                      width: options.thickness,
                                      height: fragment.height)
                    context.fill(rect)
                }
            }
        }
    }
}
