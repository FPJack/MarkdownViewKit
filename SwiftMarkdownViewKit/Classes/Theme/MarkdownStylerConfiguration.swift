//
//  MarkdownStylerConfiguration.swift
//  SwiftMarkdownViewKit
//
//  样式配置对象。设计完全参考 Down 的 `DownStylerConfiguration`：
//  「字体集合 + 颜色集合 + 段落样式集合 + 若干 Options」，
//  由 `MarkdownStyler` 消费，渲染器本身不关心具体数值。
//
//  用法（与 Down 一致的书写体验）：
//  ```swift
//  var configuration = MarkdownStylerConfiguration()
//  configuration.fonts = StaticMarkdownFontCollection(body: .systemFont(ofSize: 16))
//  configuration.colors = StaticMarkdownColorCollection(body: .darkGray, link: .systemPink)
//  configuration.paragraphStyles = StaticMarkdownParagraphStyleCollection(lineSpacing: 6,
//                                                                         paragraphSpacing: 14)
//  configuration.quoteStripeOptions = MarkdownQuoteStripeOptions(thickness: 3, spacingAfter: 10)
//
//  markdownView.parser.styler = DefaultMarkdownStyler(configuration: configuration)
//  ```
//

import UIKit

public struct MarkdownStylerConfiguration {

    // MARK: - Properties

    public var fonts: MarkdownFontCollection
    public var colors: MarkdownColorCollection
    public var paragraphStyles: MarkdownParagraphStyleCollection

    public var listItemOptions: MarkdownListItemOptions
    public var quoteStripeOptions: MarkdownQuoteStripeOptions
    public var thematicBreakOptions: MarkdownThematicBreakOptions
    public var codeBlockOptions: MarkdownCodeBlockOptions
    public var imageOptions: MarkdownImageOptions
    public var tableOptions: MarkdownTableOptions

    // MARK: - Life cycle

    public init(fonts: MarkdownFontCollection = StaticMarkdownFontCollection(),
                colors: MarkdownColorCollection = StaticMarkdownColorCollection(),
                paragraphStyles: MarkdownParagraphStyleCollection = StaticMarkdownParagraphStyleCollection(),
                listItemOptions: MarkdownListItemOptions = MarkdownListItemOptions(),
                quoteStripeOptions: MarkdownQuoteStripeOptions = MarkdownQuoteStripeOptions(),
                thematicBreakOptions: MarkdownThematicBreakOptions = MarkdownThematicBreakOptions(),
                codeBlockOptions: MarkdownCodeBlockOptions = MarkdownCodeBlockOptions(),
                imageOptions: MarkdownImageOptions = MarkdownImageOptions(),
                tableOptions: MarkdownTableOptions = MarkdownTableOptions()) {
        self.fonts = fonts
        self.colors = colors
        self.paragraphStyles = paragraphStyles
        self.listItemOptions = listItemOptions
        self.quoteStripeOptions = quoteStripeOptions
        self.thematicBreakOptions = thematicBreakOptions
        self.codeBlockOptions = codeBlockOptions
        self.imageOptions = imageOptions
        self.tableOptions = tableOptions
    }

    /// 默认配置（自动适配系统明暗模式）。
    public static var `default`: MarkdownStylerConfiguration { MarkdownStylerConfiguration() }
}

// MARK: - 兼容旧 `MarkdownTheme` 的扁平访问方式
//
// 旧代码里大量出现 `theme.bodyFont` / `theme.textColor` / `theme.lineSpacing` 这类写法，
// 这里把它们映射到新的「集合 + Options」结构上，读写都能正常工作，方便渐进迁移。

public extension MarkdownStylerConfiguration {

    // MARK: 字体

    var bodyFont: MarkdownFont {
        get { fonts.body }
        set { mutateFonts { $0.body = newValue } }
    }

    var codeFont: MarkdownFont {
        get { fonts.code }
        set { mutateFonts { $0.code = newValue } }
    }

    var headingFonts: [MarkdownFont] {
        get { fonts.headings }
        set { mutateFonts { $0 = StaticMarkdownFontCollection(headings: newValue,
                                                              body: $0.body,
                                                              code: $0.code,
                                                              listItemPrefix: $0.listItemPrefix) } }
    }

    /// 返回指定级别（1...6）标题字体。
    func headingFont(level: Int) -> MarkdownFont { fonts.heading(for: level) }

    // MARK: 颜色

    var textColor: MarkdownColor {
        get { colors.body }
        set { mutateColors { $0.body = newValue } }
    }

    var secondaryTextColor: MarkdownColor {
        get { colors.secondaryBody }
        set { mutateColors { $0.secondaryBody = newValue } }
    }

    var linkColor: MarkdownColor {
        get { colors.link }
        set { mutateColors { $0.link = newValue } }
    }

    var codeTextColor: MarkdownColor {
        get { colors.code }
        set { mutateColors { $0.code = newValue } }
    }

    var codeBackgroundColor: MarkdownColor {
        get { colors.inlineCodeBackground }
        set { mutateColors { $0.inlineCodeBackground = newValue; $0.codeBlockBackground = newValue } }
    }

    var quoteTextColor: MarkdownColor {
        get { colors.quote }
        set { mutateColors { $0.quote = newValue } }
    }

    var quoteBarColor: MarkdownColor {
        get { colors.quoteStripe }
        set { mutateColors { $0.quoteStripe = newValue } }
    }

    var ruleColor: MarkdownColor {
        get { colors.thematicBreak }
        set { mutateColors { $0.thematicBreak = newValue } }
    }

    var tableHeaderBackgroundColor: MarkdownColor {
        get { colors.tableHeaderBackground }
        set { mutateColors { $0.tableHeaderBackground = newValue } }
    }

    var tableBorderColor: MarkdownColor {
        get { colors.tableBorder }
        set { mutateColors { $0.tableBorder = newValue } }
    }

    // MARK: 间距

    var paragraphSpacing: CGFloat {
        get { paragraphStyles.body.paragraphSpacing }
        set { mutateSpacing(paragraphSpacing: newValue) }
    }

    var lineSpacing: CGFloat {
        get { paragraphStyles.body.lineSpacing }
        set { mutateSpacing(lineSpacing: newValue) }
    }

    var headingSpacingBefore: CGFloat {
        get { paragraphStyles.heading1.paragraphSpacingBefore }
        set { mutateSpacing(headingSpacingBefore: newValue) }
    }

    var listIndent: CGFloat {
        get { listItemOptions.nestedIndentation }
        set { listItemOptions.nestedIndentation = newValue }
    }

    var quoteIndent: CGFloat {
        get { quoteStripeOptions.layoutWidth }
        set { quoteStripeOptions.spacingAfter = max(0, newValue - quoteStripeOptions.thickness) }
    }

    var imagePlaceholderHeight: CGFloat {
        get { imageOptions.placeholderHeight }
        set { imageOptions.placeholderHeight = newValue }
    }

    // MARK: 旧式初始化（逐项传字体 / 颜色 / 间距）

    init(bodyFont: MarkdownFont,
         headingFonts: [MarkdownFont],
         codeFont: MarkdownFont,
         textColor: MarkdownColor,
         secondaryTextColor: MarkdownColor,
         linkColor: MarkdownColor,
         codeTextColor: MarkdownColor,
         codeBackgroundColor: MarkdownColor,
         quoteTextColor: MarkdownColor,
         quoteBarColor: MarkdownColor,
         ruleColor: MarkdownColor,
         tableHeaderBackgroundColor: MarkdownColor,
         tableBorderColor: MarkdownColor,
         paragraphSpacing: CGFloat,
         lineSpacing: CGFloat,
         headingSpacingBefore: CGFloat,
         listIndent: CGFloat,
         quoteIndent: CGFloat,
         imagePlaceholderHeight: CGFloat) {

        self.init(
            fonts: StaticMarkdownFontCollection(headings: headingFonts, body: bodyFont, code: codeFont),
            colors: StaticMarkdownColorCollection(heading1: textColor,
                                                  heading2: textColor,
                                                  heading3: textColor,
                                                  heading4: textColor,
                                                  heading5: textColor,
                                                  heading6: textColor,
                                                  body: textColor,
                                                  secondaryBody: secondaryTextColor,
                                                  code: codeTextColor,
                                                  link: linkColor,
                                                  quote: quoteTextColor,
                                                  quoteStripe: quoteBarColor,
                                                  thematicBreak: ruleColor,
                                                  listItemPrefix: textColor,
                                                  inlineCodeBackground: codeBackgroundColor,
                                                  codeBlockBackground: codeBackgroundColor,
                                                  tableHeaderBackground: tableHeaderBackgroundColor,
                                                  tableBorder: tableBorderColor),
            paragraphStyles: StaticMarkdownParagraphStyleCollection(lineSpacing: lineSpacing,
                                                                    paragraphSpacing: paragraphSpacing,
                                                                    headingSpacingBefore: headingSpacingBefore),
            listItemOptions: MarkdownListItemOptions(nestedIndentation: listIndent),
            quoteStripeOptions: MarkdownQuoteStripeOptions(thickness: 4,
                                                           spacingAfter: max(0, quoteIndent - 4)),
            imageOptions: MarkdownImageOptions(placeholderHeight: imagePlaceholderHeight)
        )
    }

    // MARK: 私有：把当前集合「具体化」成可修改的静态集合

    private mutating func mutateFonts(_ transform: (inout StaticMarkdownFontCollection) -> Void) {
        var statics = (fonts as? StaticMarkdownFontCollection)
            ?? StaticMarkdownFontCollection(heading1: fonts.heading1,
                                            heading2: fonts.heading2,
                                            heading3: fonts.heading3,
                                            heading4: fonts.heading4,
                                            heading5: fonts.heading5,
                                            heading6: fonts.heading6,
                                            body: fonts.body,
                                            code: fonts.code,
                                            listItemPrefix: fonts.listItemPrefix)
        transform(&statics)
        fonts = statics
    }

    private mutating func mutateColors(_ transform: (inout StaticMarkdownColorCollection) -> Void) {
        var statics = (colors as? StaticMarkdownColorCollection)
            ?? StaticMarkdownColorCollection(heading1: colors.heading1,
                                             heading2: colors.heading2,
                                             heading3: colors.heading3,
                                             heading4: colors.heading4,
                                             heading5: colors.heading5,
                                             heading6: colors.heading6,
                                             body: colors.body,
                                             secondaryBody: colors.secondaryBody,
                                             code: colors.code,
                                             link: colors.link,
                                             quote: colors.quote,
                                             quoteStripe: colors.quoteStripe,
                                             thematicBreak: colors.thematicBreak,
                                             listItemPrefix: colors.listItemPrefix,
                                             inlineCodeBackground: colors.inlineCodeBackground,
                                             codeBlockBackground: colors.codeBlockBackground,
                                             tableHeaderBackground: colors.tableHeaderBackground,
                                             tableBorder: colors.tableBorder)
        transform(&statics)
        colors = statics
    }

    private mutating func mutateSpacing(lineSpacing: CGFloat? = nil,
                                        paragraphSpacing: CGFloat? = nil,
                                        headingSpacingBefore: CGFloat? = nil) {
        paragraphStyles = StaticMarkdownParagraphStyleCollection(
            lineSpacing: lineSpacing ?? paragraphStyles.body.lineSpacing,
            paragraphSpacing: paragraphSpacing ?? paragraphStyles.body.paragraphSpacing,
            headingSpacingBefore: headingSpacingBefore ?? paragraphStyles.heading1.paragraphSpacingBefore)
    }
}
