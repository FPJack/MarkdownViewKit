//
//  MarkdownColorCollection.swift
//  SwiftMarkdownViewKit
//
//  颜色集合。设计参考 Down 的 `ColorCollection`。
//

import UIKit

/// 与 Down 的 `DownColor` 对齐的平台颜色别名。
public typealias MarkdownColor = UIColor

/// 描述 Markdown 渲染所需的全部颜色。
public protocol MarkdownColorCollection {

    var heading1: MarkdownColor { get }
    var heading2: MarkdownColor { get }
    var heading3: MarkdownColor { get }
    var heading4: MarkdownColor { get }
    var heading5: MarkdownColor { get }
    var heading6: MarkdownColor { get }
    var body: MarkdownColor { get }
    /// 次要文字（HTML 兜底、说明文字等）。
    var secondaryBody: MarkdownColor { get }
    var code: MarkdownColor { get }
    var link: MarkdownColor { get }
    var quote: MarkdownColor { get }
    var quoteStripe: MarkdownColor { get }
    var thematicBreak: MarkdownColor { get }
    var listItemPrefix: MarkdownColor { get }
    /// 行内代码背景。
    var inlineCodeBackground: MarkdownColor { get }
    /// 代码块背景。
    var codeBlockBackground: MarkdownColor { get }
    var tableHeaderBackground: MarkdownColor { get }
    var tableBorder: MarkdownColor { get }
}

public extension MarkdownColorCollection {

    /// 返回指定级别（1...6）的标题颜色。
    func heading(for level: Int) -> MarkdownColor {
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

/// 默认的静态颜色集合：自动适配系统明暗模式，所有字段均可单独覆盖。
public struct StaticMarkdownColorCollection: MarkdownColorCollection {

    // MARK: - Properties

    public var heading1: MarkdownColor
    public var heading2: MarkdownColor
    public var heading3: MarkdownColor
    public var heading4: MarkdownColor
    public var heading5: MarkdownColor
    public var heading6: MarkdownColor
    public var body: MarkdownColor
    public var secondaryBody: MarkdownColor
    public var code: MarkdownColor
    public var link: MarkdownColor
    public var quote: MarkdownColor
    public var quoteStripe: MarkdownColor
    public var thematicBreak: MarkdownColor
    public var listItemPrefix: MarkdownColor
    public var inlineCodeBackground: MarkdownColor
    public var codeBlockBackground: MarkdownColor
    public var tableHeaderBackground: MarkdownColor
    public var tableBorder: MarkdownColor

    // MARK: - Life cycle

    public init(
        heading1: MarkdownColor = .label,
        heading2: MarkdownColor = .label,
        heading3: MarkdownColor = .label,
        heading4: MarkdownColor = .label,
        heading5: MarkdownColor = .label,
        heading6: MarkdownColor = .label,
        body: MarkdownColor = .label,
        secondaryBody: MarkdownColor = .secondaryLabel,
        code: MarkdownColor = .label,
        link: MarkdownColor = .systemBlue,
        quote: MarkdownColor = .secondaryLabel,
        quoteStripe: MarkdownColor = .systemGray3,
        thematicBreak: MarkdownColor = .separator,
        listItemPrefix: MarkdownColor = .label,
        inlineCodeBackground: MarkdownColor = .secondarySystemBackground,
        codeBlockBackground: MarkdownColor = .secondarySystemBackground,
        tableHeaderBackground: MarkdownColor = .secondarySystemBackground,
        tableBorder: MarkdownColor = .separator
    ) {
        self.heading1 = heading1
        self.heading2 = heading2
        self.heading3 = heading3
        self.heading4 = heading4
        self.heading5 = heading5
        self.heading6 = heading6
        self.body = body
        self.secondaryBody = secondaryBody
        self.code = code
        self.link = link
        self.quote = quote
        self.quoteStripe = quoteStripe
        self.thematicBreak = thematicBreak
        self.listItemPrefix = listItemPrefix
        self.inlineCodeBackground = inlineCodeBackground
        self.codeBlockBackground = codeBlockBackground
        self.tableHeaderBackground = tableHeaderBackground
        self.tableBorder = tableBorder
    }

    /// 用同一个颜色填充全部标题色（常见需求：正文与标题同色）。
    public init(allHeadings color: MarkdownColor) {
        self.init(heading1: color,
                  heading2: color,
                  heading3: color,
                  heading4: color,
                  heading5: color,
                  heading6: color)
    }
}
