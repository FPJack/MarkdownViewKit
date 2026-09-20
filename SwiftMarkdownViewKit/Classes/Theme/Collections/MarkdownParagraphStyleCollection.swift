//
//  MarkdownParagraphStyleCollection.swift
//  SwiftMarkdownViewKit
//
//  段落样式集合。设计参考 Down 的 `ParagraphStyleCollection`。
//

import UIKit

/// 描述 Markdown 渲染所需的段落样式（行距、段距、缩进等）。
public protocol MarkdownParagraphStyleCollection {

    var heading1: NSParagraphStyle { get }
    var heading2: NSParagraphStyle { get }
    var heading3: NSParagraphStyle { get }
    var heading4: NSParagraphStyle { get }
    var heading5: NSParagraphStyle { get }
    var heading6: NSParagraphStyle { get }
    var body: NSParagraphStyle { get }
    var code: NSParagraphStyle { get }
}

public extension MarkdownParagraphStyleCollection {

    /// 返回指定级别（1...6）的标题段落样式。
    func heading(for level: Int) -> NSParagraphStyle {
        switch level {
        case ...1: return heading1
        case 2: return heading2
        case 3: return heading3
        case 4: return heading4
        case 5: return heading5
        default: return heading6
        }
    }
}

/// 默认的静态段落样式集合。
///
/// 既可以直接传入 `NSParagraphStyle`，也可以用「行距 / 段距」这种更直观的参数构造：
/// ```swift
/// StaticMarkdownParagraphStyleCollection(lineSpacing: 4,
///                                        paragraphSpacing: 12,
///                                        headingSpacingBefore: 14)
/// ```
public struct StaticMarkdownParagraphStyleCollection: MarkdownParagraphStyleCollection {

    // MARK: - Properties

    public var heading1: NSParagraphStyle
    public var heading2: NSParagraphStyle
    public var heading3: NSParagraphStyle
    public var heading4: NSParagraphStyle
    public var heading5: NSParagraphStyle
    public var heading6: NSParagraphStyle
    public var body: NSParagraphStyle
    public var code: NSParagraphStyle

    // MARK: - Life cycle

    /// 用「行距 / 段距」构造一整套段落样式（默认值与旧主题保持一致）。
    public init(lineSpacing: CGFloat = 4,
                paragraphSpacing: CGFloat = 12,
                headingSpacingBefore: CGFloat = 14) {

        let heading = NSMutableParagraphStyle()
        heading.lineSpacing = lineSpacing
        heading.paragraphSpacing = paragraphSpacing
        heading.paragraphSpacingBefore = headingSpacingBefore

        let body = NSMutableParagraphStyle()
        body.lineSpacing = lineSpacing
        body.paragraphSpacing = paragraphSpacing

        let code = NSMutableParagraphStyle()
        code.lineSpacing = lineSpacing
        code.paragraphSpacing = paragraphSpacing
        code.paragraphSpacingBefore = paragraphSpacing / 2

        self.heading1 = heading
        self.heading2 = heading
        self.heading3 = heading
        self.heading4 = heading
        self.heading5 = heading
        self.heading6 = heading
        self.body = body
        self.code = code
    }

    /// 逐项指定段落样式。
    public init(heading1: NSParagraphStyle,
                heading2: NSParagraphStyle,
                heading3: NSParagraphStyle,
                heading4: NSParagraphStyle,
                heading5: NSParagraphStyle,
                heading6: NSParagraphStyle,
                body: NSParagraphStyle,
                code: NSParagraphStyle) {
        self.heading1 = heading1
        self.heading2 = heading2
        self.heading3 = heading3
        self.heading4 = heading4
        self.heading5 = heading5
        self.heading6 = heading6
        self.body = body
        self.code = code
    }
}

// MARK: - 便捷派生

public extension NSParagraphStyle {

    /// 复制一份并做局部修改，避免在渲染过程中误改共享实例。
    func markdown_modified(_ transform: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        guard let mutable = mutableCopy() as? NSMutableParagraphStyle else { return self }
        transform(mutable)
        return mutable
    }

    /// 整体缩进（首行与正文同时缩进，并同步偏移 tabStops）。
    func markdown_indented(by indentation: CGFloat) -> NSParagraphStyle {
        markdown_modified { style in
            style.firstLineHeadIndent += indentation
            style.headIndent += indentation
            style.tabStops = tabStops.map {
                NSTextTab(textAlignment: $0.alignment, location: $0.location + indentation, options: $0.options)
            }
        }
    }

    /// 四周内缩（用于代码块这类带背景的容器）。
    func markdown_inset(by amount: CGFloat) -> NSParagraphStyle {
        markdown_modified { style in
            style.paragraphSpacingBefore += amount
            style.paragraphSpacing += amount
            style.firstLineHeadIndent += amount
            style.headIndent += amount
            style.tailIndent = -amount
        }
    }
}
