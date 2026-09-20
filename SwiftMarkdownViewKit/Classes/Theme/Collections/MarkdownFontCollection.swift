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

// MARK: - 字体回退（阿拉伯语 / 希伯来语等）

public extension MarkdownFont {

    /// iOS 上可用的阿拉伯语字体候选（按优先级排列）。
    ///
    /// `.SF Arabic` 是 iOS 13+ 系统字体的阿拉伯语变体，覆盖最好；
    /// 其余是老版本系统自带的阿拉伯语字体，作为兜底。
    static let markdown_arabicFontFamilies = [
        ".SF Arabic",
        "Geeza Pro",
        "Al Nile",
        "Baghdad",
        "Damascus",
    ]

    /// 给字体挂上回退链（cascade list）。
    ///
    /// 用途：业务方传入的自定义字体常常只含拉丁字形，遇到阿拉伯文会渲染成「豆腐块」□□□。
    /// 挂上回退链后，缺失的字形会自动去候选字体里找，**不影响已有字形的显示**，
    /// 所以即使在纯中文 / 英文场景下调用也是安全的。
    ///
    /// - Parameter familyNames: 候选字体族名，按优先级排列。
    /// - Returns: 带回退链的新字体；没有任何候选可用时原样返回。
    func markdown_withFallback(_ familyNames: [String]) -> MarkdownFont {
        let fallbacks = familyNames
            .map { UIFontDescriptor(fontAttributes: [.family: $0]) }
        guard !fallbacks.isEmpty else { return self }

        // 保留原字体已有的回退链，把新的候选追加在后面。
        let existing = fontDescriptor.fontAttributes[.cascadeList] as? [UIFontDescriptor] ?? []
        let descriptor = fontDescriptor.addingAttributes([
            .cascadeList: existing + fallbacks
        ])
        return MarkdownFont(descriptor: descriptor, size: pointSize)
    }

    /// 挂上阿拉伯语回退链的便捷写法。
    var markdown_supportingArabic: MarkdownFont {
        markdown_withFallback(MarkdownFont.markdown_arabicFontFamilies)
    }
}

public extension StaticMarkdownFontCollection {

    /// 给集合里**所有**字体挂上阿拉伯语回退链。
    ///
    /// ```swift
    /// configuration.fonts = StaticMarkdownFontCollection(body: myCustomFont)
    ///     .supportingArabic()
    /// ```
    func supportingArabic() -> StaticMarkdownFontCollection {
        withFallback(MarkdownFont.markdown_arabicFontFamilies)
    }

    /// 给集合里所有字体挂上指定的回退链。
    func withFallback(_ familyNames: [String]) -> StaticMarkdownFontCollection {
        var result = self
        result.heading1 = heading1.markdown_withFallback(familyNames)
        result.heading2 = heading2.markdown_withFallback(familyNames)
        result.heading3 = heading3.markdown_withFallback(familyNames)
        result.heading4 = heading4.markdown_withFallback(familyNames)
        result.heading5 = heading5.markdown_withFallback(familyNames)
        result.heading6 = heading6.markdown_withFallback(familyNames)
        result.body = body.markdown_withFallback(familyNames)
        result.listItemPrefix = listItemPrefix.markdown_withFallback(familyNames)
        // 注意：`code` 故意不挂回退链。
        // 代码字体必须保持等宽，挂上比例字体的回退会破坏对齐。
        return result
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
