//
//  MarkdownFontCollection.swift
//  SwiftMarkdownViewKit
//
//  字体集合。设计参考 Down 的 `FontCollection`：
//  用「协议 + 静态实现」描述一套字体，业务方既可以直接改 `StaticMarkdownFontCollection`
//  的某几个字段，也可以自己实现协议（例如接入动态字体 / 跟随系统字号）。
//

import UIKit

/// 与 Down 的 `DownFont` 对齐的平台字体别名。
public typealias MarkdownFont = UIFont

/// 描述 Markdown 渲染所需的全部字体。
public protocol MarkdownFontCollection {

    var heading1: MarkdownFont { get }
    var heading2: MarkdownFont { get }
    var heading3: MarkdownFont { get }
    var heading4: MarkdownFont { get }
    var heading5: MarkdownFont { get }
    var heading6: MarkdownFont { get }
    var body: MarkdownFont { get }
    var code: MarkdownFont { get }
    var listItemPrefix: MarkdownFont { get }
}

public extension MarkdownFontCollection {

    /// 返回指定级别（1...6）的标题字体，越界时回退到最接近的一级。
    func heading(for level: Int) -> MarkdownFont {
        switch level {
        case ...1: return heading1
        case 2: return heading2
        case 3: return heading3
        case 4: return heading4
        case 5: return heading5
        default: return heading6
        }
    }

    /// 便于遍历 / 兼容旧的 `headingFonts` 数组写法。
    var headings: [MarkdownFont] {
        [heading1, heading2, heading3, heading4, heading5, heading6]
    }
}

/// 默认的静态字体集合：所有字段都可以在初始化时单独覆盖。
public struct StaticMarkdownFontCollection: MarkdownFontCollection {

    // MARK: - Properties

    public var heading1: MarkdownFont
    public var heading2: MarkdownFont
    public var heading3: MarkdownFont
    public var heading4: MarkdownFont
    public var heading5: MarkdownFont
    public var heading6: MarkdownFont
    public var body: MarkdownFont
    public var code: MarkdownFont
    public var listItemPrefix: MarkdownFont

    // MARK: - Life cycle

    public init(
        heading1: MarkdownFont = .systemFont(ofSize: 28, weight: .bold),
        heading2: MarkdownFont = .systemFont(ofSize: 24, weight: .bold),
        heading3: MarkdownFont = .systemFont(ofSize: 20, weight: .semibold),
        heading4: MarkdownFont = .systemFont(ofSize: 18, weight: .semibold),
        heading5: MarkdownFont = .systemFont(ofSize: 17, weight: .semibold),
        heading6: MarkdownFont = .systemFont(ofSize: 16, weight: .semibold),
        body: MarkdownFont = .systemFont(ofSize: 17),
        code: MarkdownFont = .monospacedSystemFont(ofSize: 14, weight: .regular),
        listItemPrefix: MarkdownFont = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
    ) {
        self.heading1 = heading1
        self.heading2 = heading2
        self.heading3 = heading3
        self.heading4 = heading4
        self.heading5 = heading5
        self.heading6 = heading6
        self.body = body
        self.code = code
        self.listItemPrefix = listItemPrefix
    }

    /// 用一组标题字体数组构造（下标 0 对应 H1），不足 6 个时用最后一个补齐。
    public init(headings: [MarkdownFont],
                body: MarkdownFont = .systemFont(ofSize: 17),
                code: MarkdownFont = .monospacedSystemFont(ofSize: 14, weight: .regular),
                listItemPrefix: MarkdownFont = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)) {
        let fallback = headings.last ?? body
        func font(_ index: Int) -> MarkdownFont { index < headings.count ? headings[index] : fallback }
        self.init(heading1: font(0),
                  heading2: font(1),
                  heading3: font(2),
                  heading4: font(3),
                  heading5: font(4),
                  heading6: font(5),
                  body: body,
                  code: code,
                  listItemPrefix: listItemPrefix)
    }
}
