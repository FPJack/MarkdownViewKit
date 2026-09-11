//
//  MarkdownAttributedStringBuilder.swift
//  MarkdownKit
//
//  渲染核心：基于 swift-markdown 的 `MarkupVisitor` 遍历语法树，
//  产出 `NSAttributedString`。采用访问者模式，每种节点各自负责自己的样式，
//  新增节点样式只需修改对应方法，互不影响，易于维护与测试。
//
//  ┌─────────────────────────────────────────────────────────────────┐
//  │ 工作原理（一句话）：                                                 │
//  │ swift-markdown 先把 Markdown 文本解析成一棵“语法树”，本类顺着树    │
//  │ 走一遍，把每一种节点“翻译”成带样式的富文本片段，最后拼成整段。      │
//  └─────────────────────────────────────────────────────────────────┘
//
//  例如输入：
//      # 标题
//      这是**粗体**文字
//  会被解析成这样一棵树：
//      Document                （文档，根节点）
//      ├─ Heading(level:1)      （一级标题）
//      │  └─ Text("标题")
//      └─ Paragraph             （段落）
//         ├─ Text("这是")
//         ├─ Strong             （粗体）
//         │  └─ Text("粗体")
//         └─ Text("文字")
//  本类为树上的每种节点提供一个 visitXXX 方法，负责它的样式。
//

import UIKit

import Markdown

/// 将 Markdown 语法树转换为富文本的访问者。
///
/// 遵循 swift-markdown 的 `MarkupVisitor` 协议：
/// - `Result` 指定“访问每个节点后得到的东西”，这里是富文本 `NSAttributedString`。
/// - 只需实现 `defaultVisit`（兜底）+ 想定制的 `visitXXX`，其余节点库会自动走兜底。
///
/// 注意：`visitXXX` 只负责“当前这一个节点”的样式，**不会**自动处理它的子节点；
/// 想处理子节点必须自己再调用 `visit(child)`（见 `defaultVisit` / `renderInline`）。
public struct MarkdownAttributedStringBuilder: MarkupVisitor {

    /// 访问结果类型：每访问一个节点，返回一段富文本。
    public typealias Result = NSAttributedString

    /// 视觉主题：集中管理字体、颜色、间距，换肤只需换它。
    let theme: MarkdownTheme
    /// 自定义指令注册表：处理 `[music:...]`、```mermaid 等非标准语法。
    let directives: MarkdownDirectiveRegistry

    /// 当前列表嵌套深度（用于缩进）。
    /// 每进入一层列表 +1、离开 -1，层数越深缩进越大，从而实现多级列表。
    private var listDepth: Int = 0

    /// - Parameters:
    ///   - theme: 视觉主题。
    ///   - directives: 自定义指令注册表。
    init(theme: MarkdownTheme, directives: MarkdownDirectiveRegistry) {
        self.theme = theme
        self.directives = directives
    }

    // MARK: - 默认遍历

    /// 兜底访问方法：任何“没有单独实现 visitXXX”的节点都会走到这里。
    ///
    /// 作用：把当前节点的**所有子节点**依次访问并拼接起来。
    /// 这是整个递归遍历的“引擎”之一——`visit(child)` 会把每个子节点
    /// 再分派到它自己的 visitXXX。
    ///
    /// 例：一个 `Strong`（粗体）节点走到这里时，会把它内部的
    /// `Text("粗体")` 取出来拼好返回（加粗动作在 `visitStrong` 里做）。
    mutating public func defaultVisit(_ markup: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child)) // 递归：让每个子节点各自渲染
        }
        return result
    }

    // MARK: - 文档 / 块级容器

    /// 访问文档根节点 `Document`——整篇 Markdown 的入口。
    ///
    /// 它的子节点是一个个“块级元素”（标题、段落、列表、代码块……）。
    /// 这里逐块渲染，并在块与块之间插入一个换行 `\n`，让它们上下分开。
    ///
    /// 例：整篇文档 = 标题 + 段落 + 列表，渲染结果就是三段依次拼接、以换行分隔。
    mutating public func visitDocument(_ document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = Array(document.children)
        for (index, block) in blocks.enumerated() {
            result.append(visit(block))
            if index < blocks.count - 1 {
                result.append(NSAttributedString(string: "\n")) // 块间换行
            }
        }
        return result
    }

    /// 访问段落 `Paragraph`——对应普通的一段文字。
    ///
    /// 对应 Markdown：
    ///     这是一段普通文字，可以包含**粗体**、[链接](url)、`代码` 等。
    ///
    /// 步骤：
    /// 1. `renderInline` 把段落内的行内元素（文字/粗体/链接/图片…）渲染并拼好；
    /// 2. 设置段落级排版（段后间距、行间距）；
    /// 3. 仅给“还没有段落样式”的地方套用，避免覆盖图片已设的居中样式。
    mutating public func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let content = NSMutableAttributedString(attributedString: renderInline(paragraph))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = theme.paragraphSpacing
        style.lineSpacing = theme.lineSpacing
        // 仅在未设置段落样式处应用，保留图片等已居中的段落样式。
        let whole = NSRange(location: 0, length: content.length)
        content.enumerateAttribute(.paragraphStyle, in: whole, options: []) { value, range, _ in
            if value == nil {
                content.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }
        content.addAttribute(AttrKey.markup_key, value: paragraph, range: NSRange(location: 0, length: content.length))
        return content
    }

    /// 访问标题 `Heading`——对应 `#` 到 `######` 六级标题。
    ///
    /// 对应 Markdown：
    ///     # 一级标题       → level = 1，字号最大
    ///     ### 三级标题     → level = 3
    ///
    /// 做法：先渲染标题里的文字，再整体换成对应级别的大号字体，
    /// 并在标题前留出较大间距（`headingSpacingBefore`）与主题拉开距离。
    mutating public func visitHeading(_ heading: Heading) -> NSAttributedString {
        let content = NSMutableAttributedString(attributedString: renderInline(heading))
        let whole = NSRange(location: 0, length: content.length)
        content.addAttribute(.font, value: theme.headingFont(level: heading.level), range: whole)
        content.addAttribute(.foregroundColor, value: theme.textColor, range: whole)

        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = theme.paragraphSpacing
        style.paragraphSpacingBefore = theme.headingSpacingBefore // 标题前额外留白
        style.lineSpacing = theme.lineSpacing
        content.addAttribute(.paragraphStyle, value: style, range: whole)
        return content
    }

    /// 访问引用块 `BlockQuote`——对应以 `>` 开头的引用。
    ///
    /// 对应 Markdown：
    ///     > 这是一段引用
    ///     > 可以有多行
    ///
    /// 引用块里可以再包含段落、列表等（所以用 `renderBlockChildren` 渲染块级子节点），
    /// 最后整体加左缩进 + 灰色文字，形成引用观感。
    mutating public func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let content = NSMutableAttributedString(attributedString: renderBlockChildren(blockQuote))
        let whole = NSRange(location: 0, length: content.length)

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = theme.quoteIndent // 首行缩进
        style.headIndent = theme.quoteIndent          // 换行后也保持缩进
        style.paragraphSpacing = theme.paragraphSpacing
        style.lineSpacing = theme.lineSpacing
        content.addAttribute(.paragraphStyle, value: style, range: whole)
        content.addAttribute(.foregroundColor, value: theme.quoteTextColor, range: whole)
        return content
    }

    /// 访问分割线 `ThematicBreak`——对应 `---`、`***`、`___`。
    ///
    /// 对应 Markdown：
    ///     ---
    ///
    /// `NSAttributedString` 没有真正的“横线”概念，这里用 40 个 `─` 字符
    /// 拼一条细灰线来模拟视觉上的分割效果。
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

    /// 访问代码块 `CodeBlock`——对应三个反引号围起来的多行代码。
    ///
    /// 对应 Markdown：
    ///     ```swift
    ///     let a = 1
    ///     ```
    ///
    /// 逻辑：
    /// 1. 先看语言标识（如 `mermaid`、`echarts`）是否注册了自定义指令，
    ///    有就交给指令渲染成图表占位卡片；
    /// 2. 否则按普通代码块渲染：等宽字体 + 背景色 + 左右缩进。
    /// （末尾多余的换行会被去掉，避免代码块底部空一行。）
    mutating public func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        if let directive = directives.codeBlockDirective(for: codeBlock.language) {
            return directive.render(code: codeBlock.code, theme: theme)
        }
        
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 10
        style.headIndent = 10
        style.tailIndent = -10 // 负值表示距右边界 10pt
        style.paragraphSpacing = theme.paragraphSpacing
        style.paragraphSpacingBefore = 6
        style.lineSpacing = 2

        return NSAttributedString(
            string: code,
            attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.codeTextColor,
                .backgroundColor: theme.codeBackgroundColor,
                .paragraphStyle: style,
            ]
        )
    }

    /// 访问行内代码 `InlineCode`——对应一行文字中间用单反引号括起来的代码。
    ///
    /// 对应 Markdown：
    ///     请调用 `viewDidLoad()` 方法
    ///                ~~~~~~~~~~~~~ 这部分就是 InlineCode
    ///
    /// 用等宽字体 + 浅色背景，与周围普通文字区分开。
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

    /// 访问纯文本 `Text`——最基础的叶子节点，就是一段没有格式的文字。
    ///
    /// 这里不直接返回文字，而是先交给 `renderTextWithInlineDirectives`
    /// 扫描其中的自定义指令（如 `[music:https://a.mp3]`），命中就替换成徽标，
    /// 没命中就当普通文字处理。
    mutating public func visitText(_ text: Text) -> NSAttributedString {
        renderTextWithInlineDirectives(text.string)
    }

    /// 访问斜体 `Emphasis`——对应 `*斜体*` 或 `_斜体_`。
    ///
    /// 先用 `defaultVisit` 把内部文字取出来，再统一叠加“斜体”字体特征。
    /// （用叠加而非覆盖，这样“粗体里再套斜体”能同时生效，见 `addTrait`。）
    mutating public func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: defaultVisit(emphasis))
        addTrait(.traitItalic, to: result)
        return result
    }

    /// 访问粗体 `Strong`——对应 `**粗体**` 或 `__粗体__`。
    ///
    /// 同样先取内部文字，再叠加“粗体”特征。
    mutating public func visitStrong(_ strong: Strong) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: defaultVisit(strong))
        addTrait(.traitBold, to: result)
        return result
    }

    /// 访问删除线 `Strikethrough`——对应 `~~删除线~~`（GFM 扩展语法）。
    ///
    /// 取出内部文字后，整体加上单线删除线属性。
    mutating public func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: defaultVisit(strikethrough))
        result.addAttribute(.strikethroughStyle,
                            value: NSUnderlineStyle.single.rawValue,
                            range: NSRange(location: 0, length: result.length))
        return result
    }

    /// 访问链接 `Link`——对应 `[显示文字](https://example.com)`。
    ///
    /// - `defaultVisit` 取出方括号里的“显示文字”；
    /// - `link.destination` 是圆括号里的网址；
    /// - 给整段加 `.link` 属性（使其可点击）+ 链接色。
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

    /// 访问软换行 `SoftBreak`——源码里“单个回车换行”，但按 Markdown 规范
    /// 应渲染成**空格**（同一段落内的换行不真正换行）。
    ///
    /// 对应 Markdown：
    ///     第一行
    ///     第二行     → 实际显示为“第一行 第二行”
    mutating public func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [.font: theme.bodyFont])
    }

    /// 访问硬换行 `LineBreak`——对应行尾“两个空格 + 回车”或反斜杠换行，
    /// 这种才是真正的换行，渲染成 `\n`。
    mutating public func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: theme.bodyFont])
    }

    // MARK: - 图片

    /// 访问图片 `Image`——对应 `![替代文字](https://example.com/a.png)`。
    ///
    /// 网络图片无法立刻显示，所以：
    /// 1. 创建一个 `AsyncImageTextAttachment`（占位 → 后台下载 → 完成后自动刷新）；
    /// 2. 用 `NSAttributedString(attachment:)` 把图片当成一个“特殊字符”插入文本流；
    /// 3. 设为居中显示。
    mutating public func visitImage(_ image: Image) -> NSAttributedString {
        return ImageDirective().render(image, visitor: self)
        
        let url = image.source.flatMap { URL(string: $0) } // image.source 就是图片网址
        let attachment = AsyncImageTextAttachment(url: url, placeholderHeight: theme.imagePlaceholderHeight)
        let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))

        let style = NSMutableParagraphStyle()
        style.alignment = .center // 图片居中
        style.paragraphSpacing = theme.paragraphSpacing
        style.paragraphSpacingBefore = 4
        result.addAttribute(.paragraphStyle,
                            value: style,
                            range: NSRange(location: 0, length: result.length))
        return result
    }

    // MARK: - 列表

    /// 访问无序列表 `UnorderedList`——对应用 `-`、`*`、`+` 开头的列表。
    ///
    /// 对应 Markdown：
    ///     - 苹果
    ///     - 香蕉
    ///
    /// 具体渲染交给通用的 `renderList`，标记用 `•`。
    mutating public func visitUnorderedList(_ unorderedList: UnorderedList) -> NSAttributedString {
        renderList(items: listItems(of: unorderedList), ordered: false, start: 1)
    }

    /// 访问有序列表 `OrderedList`——对应 `1.`、`2.` 开头的列表。
    ///
    /// 对应 Markdown：
    ///     1. 第一步
    ///     2. 第二步
    ///
    /// `startIndex` 是起始序号（有的列表从 3 开始编号），传给 `renderList`。
    mutating public func visitOrderedList(_ orderedList: OrderedList) -> NSAttributedString {
        renderList(items: listItems(of: orderedList), ordered: true, start: Int(orderedList.startIndex))
    }

    // MARK: - 表格

    /// 访问表格 `Table`——对应 GFM 的管道符表格。
    ///
    /// 对应 Markdown：
    ///     | 名称 | 价格 |
    ///     | ---- | ---- |
    ///     | 苹果 | 3元  |
    ///     | 香蕉 | 2元  |
    ///
    /// `NSAttributedString` 没有真正的表格控件，这里用“制表符 `\t` + 制表位”
    /// 把每个单元格对齐成一列列：
    /// - `table.head.cells` 是表头单元格（加粗 + 背景色）；
    /// - `table.body.rows` 是每一行数据，每行再取 `row.cells`。
    mutating public func visitTable(_ table: Table) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        // 预设 12 个制表位，每个间隔 92pt，单元格用 \t 跳到下一列位置。
        paragraph.tabStops = (1...12).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * 92) }
        paragraph.defaultTabInterval = 92
        paragraph.lineSpacing = theme.lineSpacing
        paragraph.paragraphSpacing = 2

        let result = NSMutableAttributedString()

        // 表头（加粗 + 背景色）
        let header = renderTableRow(cells: Array(table.head.cells), bold: true, paragraph: paragraph)
        header.addAttribute(.backgroundColor,
                           value: theme.tableHeaderBackgroundColor,
                           range: NSRange(location: 0, length: header.length))
        result.append(header)
        result.append(NSAttributedString(string: "\n"))

        // 表体：逐行渲染，行间换行
        let rows = Array(table.body.rows)
        for (index, row) in rows.enumerated() {
            let att = renderTableRow(cells: Array(row.cells), bold: false, paragraph: paragraph)
            
            result.append(att)
            if index < rows.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        // 收尾段落间距：让表格最后一行与后面内容拉开距离
        let trailing = NSMutableParagraphStyle()
        trailing.tabStops = paragraph.tabStops
        trailing.defaultTabInterval = paragraph.defaultTabInterval
        trailing.lineSpacing = theme.lineSpacing
        trailing.paragraphSpacing = theme.paragraphSpacing
        if result.length > 0 {
            print(result.string)
            // 让最后一行拥有段落间距
            let lastLineRange = (result.string as NSString).paragraphRange(for: NSRange(location: result.length - 1, length: 1))
            result.addAttribute(.paragraphStyle, value: trailing, range: lastLineRange)
        }
        return result
    }

    // MARK: - HTML（原样降级为普通文本）

    /// 访问 HTML 块 `HTMLBlock`——Markdown 里整段的原始 HTML。
    ///
    /// 对应 Markdown：
    ///     <div class="box">内容</div>
    ///
    /// 我们不解析 HTML，直接用等宽灰字把原始代码显示出来（降级处理，信息不丢失）。
    mutating public func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        NSAttributedString(string: html.rawHTML,
                          attributes: [.font: theme.codeFont, .foregroundColor: theme.secondaryTextColor])
    }

    /// 访问行内 HTML `InlineHTML`——一行文字中间夹杂的 HTML 标签，如 `<br/>`。
    ///
    /// 同样按原始文字降级显示，不做 HTML 解析。
    mutating public func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        NSAttributedString(string: inlineHTML.rawHTML,
                          attributes: [.font: theme.bodyFont, .foregroundColor: theme.secondaryTextColor])
    }
}

// MARK: - 私有辅助

private extension MarkdownAttributedStringBuilder {

    /// 渲染某个节点的所有**行内**子节点并拼接（用于段落 / 标题 / 单元格）。
    ///
    /// 与 `defaultVisit` 类似，都是遍历子节点并 `visit`，
    /// 区别是这里语义上专门用于“行内内容”（文字、粗体、链接、图片…）。
    mutating func renderInline(_ markup: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    /// 渲染块级子节点，块之间以换行分隔（用于引用块等“容器里还有多个块”的场景）。
    ///
    /// 例：引用块里有两个段落，就渲染成“段落1 \n 段落2”。
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

    /// 从列表节点里筛出所有列表项 `ListItem`（列表的直接子节点就是列表项）。
    func listItems(of markup: Markup) -> [ListItem] {
        markup.children.compactMap { $0 as? ListItem }
    }

    /// 渲染一个列表（有序 / 无序 / 任务列表通用）。
    ///
    /// - Parameters:
    ///   - items: 该列表的所有列表项。
    ///   - ordered: 是否有序列表（`true` 用数字，`false` 用圆点）。
    ///   - start: 有序列表的起始编号。
    ///
    /// 关键点：进入前 `listDepth += 1`、退出时 `defer` 自动 `-= 1`，
    /// 这样嵌套列表（列表里还有列表）会自动加深缩进。
    ///
    /// 标记规则：
    /// - 任务项（`- [x]` / `- [ ]`）→ `☑︎` / `☐`
    /// - 有序 → `1.` `2.` …
    /// - 无序 → `•`
    mutating func renderList(items: [ListItem], ordered: Bool, start: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        listDepth += 1
        defer { listDepth -= 1 } // 无论从哪里 return 都会执行，保证层数正确回退

        var number = start
        for (index, item) in items.enumerated() {
            let marker: String
            if let checkbox = item.checkbox {
                // 任务列表：根据勾选状态显示不同符号
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

    /// 渲染单个列表项 `ListItem`：在内容前加上标记（•/数字/勾选框），并处理缩进。
    ///
    /// 缩进要点：
    /// - `firstLineHeadIndent`：首行（含标记）的缩进；
    /// - `headIndent`：内容换行后的缩进，比首行多一个 `listIndent`，
    ///   这样长文本折行时会对齐到标记右边，而不是顶到标记下面。
    ///
    /// 列表项内部可能不只有一段文字，还可能嵌套子列表，
    /// 所以这里区分处理：`Paragraph` 直接渲染行内内容并加标记，
    /// 其它块（如嵌套列表）换行后按各自样式 `visit`。
    mutating func renderListItem(_ item: ListItem, marker: String) -> NSAttributedString {
        let baseIndent = CGFloat(listDepth - 1) * theme.listIndent

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = baseIndent
        style.headIndent = baseIndent + theme.listIndent
        style.paragraphSpacing = 4
        style.lineSpacing = theme.lineSpacing

        let out = NSMutableAttributedString()
        let blocks = Array(item.children)
        var markerWritten = false // 标记只在列表项的第一段前加一次

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
                // 嵌套列表或其它块级内容：换行后按各自样式渲染。
                if out.length > 0, out.string.hasSuffix("\n") == false {
                    out.append(NSAttributedString(string: "\n"))
                }
                out.append(visit(block))
            }
        }
        return out
    }

    /// 渲染表格的一行：把每个单元格内容用 `\t`（制表符）连接，靠制表位对齐成列。
    ///
    /// - Parameters:
    ///   - cells: 该行的所有单元格。
    ///   - bold: 是否加粗（表头行为 `true`）。
    ///   - paragraph: 含制表位设置的段落样式。
    ///
    /// 空单元格用一个空格占位，避免 `\t` 连在一起导致错列。
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
                line.append(NSAttributedString(string: "\t", attributes: [.font: theme.bodyFont])) // 用制表符分列
            }
        }
        line.addAttribute(.paragraphStyle,
                         value: paragraph,
                         range: NSRange(location: 0, length: line.length))
        return line
    }

    /// 为整段富文本**叠加**某个字体特征（粗体 / 斜体），并保留原有嵌套样式。
    ///
    /// 为什么要“叠加”而不是直接换字体？
    /// 因为存在嵌套，比如 `**粗体里的*斜体***`：
    /// - 处理 `Strong` 时整段已是粗体；
    /// - 再处理内部 `Emphasis` 时，需要在“粗体”基础上**再加**斜体，
    ///   得到“又粗又斜”，而不是把粗体覆盖成普通斜体。
    ///
    /// 做法：遍历每一处已有字体，取它现有的特征集合，插入新特征后重建字体。
    func addTrait(_ trait: UIFontDescriptor.SymbolicTraits, to attributed: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.font, in: whole, options: []) { value, range, _ in
            let base = (value as? UIFont) ?? theme.bodyFont
            var traits = base.fontDescriptor.symbolicTraits
            traits.insert(trait) // 在原有特征上追加，实现“又粗又斜”
            if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                attributed.addAttribute(.font,
                                       value: UIFont(descriptor: descriptor, size: base.pointSize),
                                       range: range)
            }
        }
        // 确保有前景色（防止某些片段没颜色）
        attributed.enumerateAttribute(.foregroundColor, in: whole, options: []) { value, range, _ in
            if value == nil {
                attributed.addAttribute(.foregroundColor, value: theme.textColor, range: range)
            }
        }
    }

    /// 扫描文本中的行内自定义指令 `[name:payload]` 并替换为对应渲染结果。
    ///
    /// 背景：像 `[music:https://a.mp3]`、`[video:https://b.mp4]` 这类写法
    /// 不是标准 Markdown（因为方括号后面没有 `()`），会被解析成普通文字。
    /// 我们用正则把它们找出来，交给对应指令渲染成徽标。
    ///
    /// 处理流程（把文字按匹配位置切成若干段）：
    ///     "看这个 [music:xxx] 很好听"
    ///      └普通文字┘└─指令─┘└普通文字┘
    /// - `cursor` 记录“已经处理到哪里”；
    /// - 每遇到一个匹配，先把匹配前的普通文字加进去，再加指令渲染结果；
    /// - 循环结束后把最后剩余的普通文字补上。
    func renderTextWithInlineDirectives(_ string: String) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont,
            .foregroundColor: theme.textColor,
        ]

        // 没有注册任何指令 → 直接当普通文字返回。
        guard let regex = directives.inlineDirectivePattern else {
            return NSAttributedString(string: string, attributes: baseAttributes)
        }

        let nsString = string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: string, options: [], range: fullRange)
        // 没匹配到任何指令 → 也当普通文字返回。
        guard !matches.isEmpty else {
            return NSAttributedString(string: string, attributes: baseAttributes)
        }

        let result = NSMutableAttributedString()
        var cursor = 0
        for match in matches {
            // 1) 先补上“上一个匹配结束 ~ 当前匹配开始”之间的普通文字
            if match.range.location > cursor {
                let prefix = nsString.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result.append(NSAttributedString(string: prefix, attributes: baseAttributes))
            }
            // 2) 取出指令名与参数：group1 = name，group2 = payload
            let name = nsString.substring(with: match.range(at: 1))
            let payload = nsString.substring(with: match.range(at: 2))
            if let directive = directives.inlineDirective(named: name) {
                result.append(directive.render(payload: payload, theme: theme)) // 命中 → 渲染徽标
            } else {
                // 未注册的名字 → 原样保留 [name:payload]
                result.append(NSAttributedString(string: nsString.substring(with: match.range), attributes: baseAttributes))
            }
            cursor = match.range.location + match.range.length
        }
        // 3) 补上最后一个匹配之后剩余的普通文字
        if cursor < nsString.length {
            result.append(NSAttributedString(string: nsString.substring(from: cursor), attributes: baseAttributes))
        }
        return result
    }
}
