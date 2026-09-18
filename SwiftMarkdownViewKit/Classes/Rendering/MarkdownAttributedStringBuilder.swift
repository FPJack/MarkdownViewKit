//
//  MarkdownAttributedStringBuilder.swift
//  MarkdownKit
//
//  渲染核心：基于 swift-markdown 的 `MarkupVisitor` 遍历语法树，产出 `NSAttributedString`。
//

import UIKit

import Markdown

/// 将 Markdown 语法树转换为富文本的访问者。
public struct MarkdownAttributedStringBuilder: MarkupVisitor {

    public typealias Result = NSAttributedString
    
    private(set) weak var markdownView: MarkdownView?

    public var text: String = ""

    let theme: MarkdownTheme
    
    let directives: MarkdownDirectiveRegistry

    private var listDepth: Int = 0

    init(theme: MarkdownTheme,
         directives: MarkdownDirectiveRegistry,
         markdownView: MarkdownView?) {
        self.theme = theme
        self.directives = directives
        self.markdownView = markdownView
    }

    // MARK: - 默认遍历

    mutating public func defaultVisit(_ markup: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    // MARK: - 文档 / 块级容器

    mutating public func visitDocument(_ document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in document.children {
            let rendered = visit(block)
            // 跳过渲染为空的块（如被忽略的 HTML 注释 <!-- -->），
            // 否则块间的 "\n" 分隔符会为每个空块累积成一片空白。
            if rendered.length == 0 { continue }
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(rendered)
        }
        return result
    }

    mutating public func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        // 段落级自定义规则：整段纯文本命中某条 BlockRule 时，整段替换成自定义渲染。
        
        let blockRules = directives.allBlockRules
        if !blockRules.isEmpty {
            if let custom = BlockRuleResolver(rules: blockRules).render(paragraph,visitor: self) {
                return custom
            }
        }
        let content = NSMutableAttributedString(attributedString: renderInline(paragraph))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = theme.paragraphSpacing
        style.lineSpacing = theme.lineSpacing
        let whole = NSRange(location: 0, length: content.length)
        content.enumerateAttribute(.paragraphStyle, in: whole, options: []) { value, range, _ in
            if value == nil {
                content.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }
        return content
    }

    mutating public func visitHeading(_ heading: Heading) -> NSAttributedString {
        let content = NSMutableAttributedString(attributedString: renderInline(heading))
        let whole = NSRange(location: 0, length: content.length)
        content.addAttribute(.font, value: theme.headingFont(level: heading.level), range: whole)
        content.addAttribute(.foregroundColor, value: theme.textColor, range: whole)

        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = theme.paragraphSpacing
        style.paragraphSpacingBefore = theme.headingSpacingBefore
        style.lineSpacing = theme.lineSpacing
        content.addAttribute(.paragraphStyle, value: style, range: whole)
        return content
    }

    mutating public func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let content = NSMutableAttributedString(attributedString: renderBlockChildren(blockQuote))
        let whole = NSRange(location: 0, length: content.length)

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = theme.quoteIndent
        style.headIndent = theme.quoteIndent
        style.paragraphSpacing = theme.paragraphSpacing
        style.lineSpacing = theme.lineSpacing
        content.addAttribute(.paragraphStyle, value: style, range: whole)
        content.addAttribute(.foregroundColor, value: theme.quoteTextColor, range: whole)
        return content
    }

    mutating public func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = theme.paragraphSpacing
        style.paragraphSpacingBefore = 6
        return NSAttributedString(
            string: String(repeating: "─", count: 40),
            attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: theme.ruleColor,
                .paragraphStyle: style,
            ]
        )
    }

    // MARK: - 代码

    mutating public func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        directives.codeBlockDirective(for: codeBlock.language)?.render(codeBlockCtx: CodeBlockContext(codeBlock: codeBlock, visitor: self)) ?? NSAttributedString()
//        return CodeDirective().render(codeBlock, visitor: self)
    }

    mutating public func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        NSAttributedString(
            string: inlineCode.code,
            attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.codeTextColor,
                .backgroundColor: theme.codeBackgroundColor,
            ]
        )
    }

    // MARK: - 行内文本样式

    mutating public func visitText(_ text: Text) -> NSAttributedString {
        renderTextWithInlineDirectives(text)
    }

    mutating public func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: defaultVisit(emphasis))
        addTrait(.traitItalic, to: result)
        return result
    }

    mutating public func visitStrong(_ strong: Strong) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: defaultVisit(strong))
        addTrait(.traitBold, to: result)
        return result
    }

    mutating public func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: defaultVisit(strikethrough))
        result.addAttribute(.strikethroughStyle,
                            value: NSUnderlineStyle.single.rawValue,
                            range: NSRange(location: 0, length: result.length))
        return result
    }

    mutating public func visitLink(_ link: Link) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: defaultVisit(link))
        let whole = NSRange(location: 0, length: result.length)
        if let destination = link.destination,
           let url = URL(string: destination.trimmingCharacters(in: .whitespacesAndNewlines)) {
            result.addAttribute(.link, value: url, range: whole)
        }
        result.addAttribute(.foregroundColor, value: theme.linkColor, range: whole)
        return result
    }

    mutating public func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [.font: theme.bodyFont])
    }

    mutating public func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: theme.bodyFont])
    }

    // MARK: - 图片

    mutating public func visitImage(_ image: Image) -> NSAttributedString {
        directives.imageDirective(for: image.title).render(image, visitor: self)
    }

    // MARK: - 列表

    mutating public func visitUnorderedList(_ unorderedList: UnorderedList) -> NSAttributedString {
        renderList(items: listItems(of: unorderedList), ordered: false, start: 1)
    }

    mutating public func visitOrderedList(_ orderedList: OrderedList) -> NSAttributedString {
        renderList(items: listItems(of: orderedList), ordered: true, start: Int(orderedList.startIndex))
    }

    // MARK: - 表格

    mutating public func visitTable(_ table: Table) -> NSAttributedString {
        
        return  directives.tableDirective().render(markup: table, visitor: self) ?? renderTableAsText(table)
    }

    /// 纯文本方式渲染表格（tab 分隔），作为无法使用 `GridTableView` 时的兜底。
    mutating func renderTableAsText(_ table: Table) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = (1...12).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * 92) }
        paragraph.defaultTabInterval = 92
        paragraph.lineSpacing = theme.lineSpacing
        paragraph.paragraphSpacing = 2

        let result = NSMutableAttributedString()

        let header = renderTableRow(cells: Array(table.head.cells), bold: true, paragraph: paragraph)
        header.addAttribute(.backgroundColor,
                           value: theme.tableHeaderBackgroundColor,
                           range: NSRange(location: 0, length: header.length))
        result.append(header)
        result.append(NSAttributedString(string: "\n"))

        let rows = Array(table.body.rows)
        for (index, row) in rows.enumerated() {
            let att = renderTableRow(cells: Array(row.cells), bold: false, paragraph: paragraph)
            result.append(att)
            if index < rows.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        let trailing = NSMutableParagraphStyle()
        trailing.tabStops = paragraph.tabStops
        trailing.defaultTabInterval = paragraph.defaultTabInterval
        trailing.lineSpacing = theme.lineSpacing
        trailing.paragraphSpacing = theme.paragraphSpacing
        if result.length > 0 {
            let lastLineRange = (result.string as NSString).paragraphRange(for: NSRange(location: result.length - 1, length: 1))
            result.addAttribute(.paragraphStyle, value: trailing, range: lastLineRange)
        }
        return result
    }

    // MARK: - HTML（分级路由：媒体/内联/importer/WebView，见 HTMLRouter）

    mutating public func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        directives.htmlBlockDirective().render(markup: html, visitor: self) ?? NSAttributedString()
    }

    mutating public func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        // 主路径是 renderInline 的栈式配对；这里仅兜底单独访问到 InlineHTML 的场景。
        guard let token = HTMLRouter.parseTag(inlineHTML.rawHTML) else {
            return NSAttributedString()
        }
        if token.kind == .selfClosing {
            return HTMLRouter.renderInlineSelfClosing(token, theme: theme)
        }
        // 开/闭/注释标签单独出现时不显示裸标签。
        return NSAttributedString()
    }
}

// MARK: - 私有辅助

private extension MarkdownAttributedStringBuilder {

    /// 行内遍历：普通子节点正常渲染；行内 HTML（碎片化的 `<b>`/`</b>` 等）用**样式栈**配对。
    ///
    /// swift-markdown 里 `InlineHTML` 每个节点只是「一个标签」，开/闭/内容是独立兄弟节点，
    /// 所以必须在这一层用栈把成对标签配起来，转成 `NSAttributedString` 属性（不上 WebView）。
    mutating func renderInline(_ markup: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // 用可选元素：未知开标签压入 nil 占位，保证 open/close 配对平衡。
        var styleStack: [HTMLInlineStyle?] = []

        for child in markup.children {
            if let inlineHTML = child as? InlineHTML {
                guard let token = HTMLRouter.parseTag(inlineHTML.rawHTML) else { continue }
                switch token.kind {
                case .comment:
                    continue
                case .open:
                    // 行内媒体标签 <audio>/<video> 不是 void 标签，会被判成 .open，
                    // 这里直接渲染成徽标（复用 renderMedia），并压 nil 占位以配对可能的闭合标签。
                    if token.name == "audio" || token.name == "video" {
                        result.append(HTMLRouter.renderMedia(tag: token.name,
                                                             attrs: token.attributes,
                                                             theme: theme))
                        styleStack.append(nil)
                    } else {
                        styleStack.append(HTMLRouter.inlineStyle(forOpenTag: token.name,
                                                                 attrs: token.attributes,
                                                                 theme: theme))
                    }
                case .close:
                    if !styleStack.isEmpty { styleStack.removeLast() }
                case .selfClosing:
                    result.append(HTMLRouter.renderInlineSelfClosing(token, theme: theme))
                }
                continue
            }

            let rendered = NSMutableAttributedString(attributedString: visit(child))
            if !styleStack.isEmpty {
                HTMLRouter.apply(styleStack, to: rendered, theme: theme)
            }
            result.append(rendered)
        }
        return result
    }

    mutating func renderBlockChildren(_ markup: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = Array(markup.children)
        for (index, block) in blocks.enumerated() {
            result.append(visit(block))
            if index < blocks.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    func listItems(of markup: Markup) -> [ListItem] {
        markup.children.compactMap { $0 as? ListItem }
    }

    mutating func renderList(items: [ListItem], ordered: Bool, start: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        listDepth += 1
        defer { listDepth -= 1 }

        var number = start
        for (index, item) in items.enumerated() {
            let marker: String
            if let checkbox = item.checkbox {
                marker = checkbox == .checked ? "☑︎  " : "☐  "
            } else if ordered {
                marker = "\(number).  "
            } else {
                marker = "•  "
            }
            result.append(renderListItem(item, marker: marker))
            if index < items.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
            number += 1
        }
        return result
    }

    mutating func renderListItem(_ item: ListItem, marker: String) -> NSAttributedString {
        let baseIndent = CGFloat(listDepth - 1) * theme.listIndent

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = baseIndent
        style.headIndent = baseIndent + theme.listIndent
        style.paragraphSpacing = 4
        style.lineSpacing = theme.lineSpacing

        let out = NSMutableAttributedString()
        let blocks = Array(item.children)
        var markerWritten = false

        for (index, block) in blocks.enumerated() {
            if let paragraph = block as? Paragraph {
                let line = NSMutableAttributedString()
                if !markerWritten {
                    line.append(NSAttributedString(
                        string: marker,
                        attributes: [.font: theme.bodyFont, .foregroundColor: theme.textColor]
                    ))
                    markerWritten = true
                }
                line.append(renderInline(paragraph))
                line.addAttribute(.paragraphStyle,
                                 value: style,
                                 range: NSRange(location: 0, length: line.length))
                out.append(line)
                if index < blocks.count - 1 {
                    out.append(NSAttributedString(string: "\n"))
                }
            } else {
                if out.length > 0, out.string.hasSuffix("\n") == false {
                    out.append(NSAttributedString(string: "\n"))
                }
                out.append(visit(block))
            }
        }
        return out
    }

    mutating func renderTableRow(cells: [Table.Cell], bold: Bool, paragraph: NSParagraphStyle) -> NSMutableAttributedString {
        let line = NSMutableAttributedString()
        for (index, cell) in cells.enumerated() {
            let rendered = NSMutableAttributedString(attributedString: renderInline(cell))
            if rendered.length == 0 {
                rendered.append(NSAttributedString(string: " ",
                                                  attributes: [.font: theme.bodyFont, .foregroundColor: theme.textColor]))
            }
            if bold { addTrait(.traitBold, to: rendered) }
            line.append(rendered)
            if index < cells.count - 1 {
                line.append(NSAttributedString(string: "\t", attributes: [.font: theme.bodyFont]))
            }
        }
        line.addAttribute(.paragraphStyle,
                         value: paragraph,
                         range: NSRange(location: 0, length: line.length))
        return line
    }

    func addTrait(_ trait: UIFontDescriptor.SymbolicTraits, to attributed: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.font, in: whole, options: []) { value, range, _ in
            let base = (value as? UIFont) ?? theme.bodyFont
            var traits = base.fontDescriptor.symbolicTraits
            traits.insert(trait)
            if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                attributed.addAttribute(.font,
                                       value: UIFont(descriptor: descriptor, size: base.pointSize),
                                       range: range)
            }
        }
        attributed.enumerateAttribute(.foregroundColor, in: whole, options: []) { value, range, _ in
            if value == nil {
                attributed.addAttribute(.foregroundColor, value: theme.textColor, range: range)
            }
        }
    }

    /// 扫描一段纯文本里的自定义行内规则并替换为对应渲染结果。
    ///
    /// 规则引擎架构：每条规则自带正则 + 渲染逻辑（见 `InlineRule`），
    /// 由 `InlineRuleScanner` 统一跑所有规则、处理重叠冲突、拼接文本。
    /// 想扩展任意“正则匹配 → 自定义展示”，只需实现 `InlineRule` 并注册。
    func renderTextWithInlineDirectives(_ markup: Text) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont,
            .foregroundColor: theme.textColor,
        ]

        let rules = directives.allInlineRules
        guard !rules.isEmpty else {
            return NSAttributedString(string: markup.string, attributes: baseAttributes)
        }

        return InlineRuleScanner(rules: rules).render(markup,
                                                      visitor: self,
                                                      baseAttributes: baseAttributes)
    }
}
