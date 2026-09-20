//
//  ViewController.swift
//  SwiftMarkdownViewKit
//
//  Created by fanpeng on 09/10/2026.
//  Copyright (c) 2026 fanpeng. All rights reserved.
//

import UIKit
import SwiftMarkdownViewKit
import ZLFlexKit
class ViewController: UIViewController {
    
    lazy var markdown = MarkdownView()
    private lazy var displayLink = {
      let timer =  DisplayLinkTimer(preferredFramesPerSecond: 2) { tick in
            self.readNextChunk()
        }
      return timer
    }()
    private func readNextChunk() {
        guard readOffset < source.count else {
            displayLink.stop()
            return
        }
        // 按字形簇（Character）切片，保证不会把 emoji / 组合字符从中间截断
        let length = min(100, source.count - readOffset)
        let piece = String(source[readOffset ..< readOffset + length])
        self.markdown.appendText(fromMarkdown: piece)
        readOffset += length
    }
    // 每个元素都是一个完整的用户感知字符（含 ZWJ emoji 序列、变体选择符等）
    lazy var source: [Character] = Array(loadMarkdown())
    private var readOffset: Int = 0


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        // ⚠️ 样式必须在开始（流式）渲染之前配置好，否则已渲染出来的内容不会自动重排。
        configureMarkdownStyle()

        markdown.maxTextWidth = self.view.bounds.width - 40
        markdown.frameInterval = 30
        markdown.charactersPerFrame = 2
        markdown.textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        markdown.textView.backgroundColor = UIColor.orange
        let scrollView =
            VStackView {
                markdown
                30
                UISwitch()
            }
            .wrapScrollView()
            
            scrollView.box
            .addTo(view)
            .top(100)
            .leading(20)
            .trailing(-20)
//            .width(300)
            .maxHeight(700)
            markdown.onContentSizeChange = {newSize in
                let offset = scrollView.contentSize.height - scrollView.frame.height
                scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: true)
            }
            scrollView.backgroundColor = .black.withAlphaComponent(0.1)

        // 启动流式渲染
        displayLink.start()
//        let str = source.map { String($0) }.joined()
//        markdown.startStreamingText(markdown: str)
    }

    private func loadMarkdown() -> String {
        if let url = Bundle.main.url(forResource: "html", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        } else {
            return "# 未找到 html.md\n请确认该文件已加入 App Target 的资源中。"
        }
    }

}

// MARK: - Markdown 样式配置（参考 Down 的配置方式）
//
// 样式分三层，越往下定制能力越强：
//   1. MarkdownStylerConfiguration —— 纯数据：字体集合 / 颜色集合 / 段落样式集合 / 各类 Options
//   2. MarkdownStyler             —— 规则：每种节点怎么套用上面的数据（DefaultMarkdownStyler 可继承覆写）
//   3. MarkdownAttributedStringBuilder —— 只负责遍历语法树，不关心样式
//
// 日常换肤只需要动第 1 层；需要“某种节点特殊处理”时再动第 2 层。
extension ViewController {

    private func configureMarkdownStyle() {

        // ============================================================
        // 1. 字体集合（MarkdownFontCollection）
        //    heading1...heading6 / body / code / listItemPrefix
        //    未显式传入的字段会使用库内默认值。
        // ============================================================
        let fonts = StaticMarkdownFontCollection(
            heading1: .systemFont(ofSize: 28, weight: .heavy),      // # 一级标题
            heading2: .systemFont(ofSize: 24, weight: .bold),       // ## 二级标题
            heading3: .systemFont(ofSize: 20, weight: .semibold),   // ### 三级标题
            heading4: .systemFont(ofSize: 18, weight: .semibold),
            heading5: .systemFont(ofSize: 17, weight: .semibold),
            heading6: .systemFont(ofSize: 16, weight: .semibold),
            body: .systemFont(ofSize: 16),                          // 正文
            code: .monospacedSystemFont(ofSize: 13, weight: .regular), // 行内代码 / 代码块
            listItemPrefix: .monospacedDigitSystemFont(ofSize: 16, weight: .medium) // 列表的 “1.” “•”
        )

        // 也可以用标题数组的写法（下标 0 = H1，不足 6 个自动用最后一个补齐）：
        // let fonts = StaticMarkdownFontCollection(
        //     headings: [.boldSystemFont(ofSize: 30), .boldSystemFont(ofSize: 25)],
        //     body: .systemFont(ofSize: 16),
        //     code: .monospacedSystemFont(ofSize: 13, weight: .regular)
        // )

        // ============================================================
        // 2. 颜色集合（MarkdownColorCollection）
        //    全部支持 UIColor.dynamic，可自动适配明暗模式。
        // ============================================================
        let colors = StaticMarkdownColorCollection(
            heading1: .label,                       // 各级标题颜色
            heading2: .label,
            heading3: .label,
            heading4: .label,
            heading5: .label,
            heading6: .label,
            body: .label,                           // 正文文字
            secondaryBody: .secondaryLabel,         // 次要文字（HTML 兜底、说明文字）
            code: .systemPurple,                    // 代码文字
            link: .systemPink,                      // 链接
            quote: .secondaryLabel,                 // 引用文字
            quoteStripe: .systemPink,               // 引用左侧竖条
            thematicBreak: .separator,              // --- 分割线
            listItemPrefix: .systemPink,            // 列表前缀（序号 / 圆点）
            inlineCodeBackground: .secondarySystemBackground,   // `行内代码` 背景
            codeBlockBackground: .secondarySystemBackground,    // ``` 代码块 ``` 背景
            tableHeaderBackground: .systemGray5,    // 表头背景
            tableBorder: .separator                 // 表格边框 / 分隔线
        )

        // ============================================================
        // 3. 段落样式集合（MarkdownParagraphStyleCollection）
        //    最简单的写法：用行距 / 段距一次性生成全套样式。
        // ============================================================
        let paragraphStyles = StaticMarkdownParagraphStyleCollection(
            lineSpacing: 6,             // 行间距
            paragraphSpacing: 14,       // 段落之间的距离
            headingSpacingBefore: 18    // 标题上方额外留白
        )

        // 需要逐项精细控制时（例如标题居中、代码块单独调距）可以这样写：
        // let headingStyle = NSMutableParagraphStyle()
        // headingStyle.lineSpacing = 4
        // headingStyle.paragraphSpacing = 14
        // headingStyle.paragraphSpacingBefore = 20
        // let bodyStyle = NSMutableParagraphStyle()
        // bodyStyle.lineSpacing = 6
        // bodyStyle.paragraphSpacing = 14
        // let codeStyle = NSMutableParagraphStyle()
        // codeStyle.lineSpacing = 3
        // codeStyle.paragraphSpacing = 12
        // let paragraphStyles = StaticMarkdownParagraphStyleCollection(
        //     heading1: headingStyle, heading2: headingStyle, heading3: headingStyle,
        //     heading4: headingStyle, heading5: headingStyle, heading6: headingStyle,
        //     body: bodyStyle, code: codeStyle
        // )

        // ============================================================
        // 4. 组装配置对象（MarkdownStylerConfiguration，即 MarkdownTheme）
        // ============================================================
        var configuration = MarkdownStylerConfiguration(
            fonts: fonts,
            colors: colors,
            paragraphStyles: paragraphStyles
        )

        // —— 列表：缩进与间距 ——
        configuration.listItemOptions = MarkdownListItemOptions(
            maxPrefixDigits: 2,         // 有序列表序号最多按几位数字预留宽度
            spacingAfterPrefix: 8,      // “1.” 与内容之间的距离
            spacingAbove: 2,            // 列表项上方间距
            spacingBelow: 6,            // 列表项下方间距
            nestedIndentation: 26,      // 每嵌套一层增加的缩进
            alignment: .natural
        )

        // —— 引用块：左侧竖条 ——
        configuration.quoteStripeOptions = MarkdownQuoteStripeOptions(
            thickness: 4,               // 竖条粗细
            spacingAfter: 12            // 竖条与文字的间距（整体缩进 = thickness + spacingAfter）
        )

        // —— 分割线 `---` ——
        configuration.thematicBreakOptions = MarkdownThematicBreakOptions(
            character: "─",             // 组成线条的字符
            repeatCount: 36,            // 重复次数（决定线条长度）
            fontSize: 12,               // 字号（决定视觉粗细）
            indentation: 0,             // 左侧缩进
            spacingBefore: 8            // 上方额外留白
        )

        // —— 代码块容器 ——
        configuration.codeBlockOptions = MarkdownCodeBlockOptions(
            containerInset: 10,         // 代码块内缩（上下左右）
            cornerRadius: 8             // 圆角（供自定义代码块视图使用）
        )

        // —— 图片 ——
        configuration.imageOptions = MarkdownImageOptions(
            placeholderHeight: 200      // 图片下载完成前的占位高度
        )

        // —— 表格（纯文本兜底渲染时生效；GridTableView 正常工作时走自定义视图）——
        configuration.tableOptions = MarkdownTableOptions(
            columnWidth: 96,            // 每列制表位宽度
            rowSpacing: 4,              // 行间距
            boldHeader: true            // 表头是否加粗
        )

        // ============================================================
        // 5. 应用样式
        //    方式 A：只改配置 —— 赋值 theme 会自动重建默认 styler
        // ============================================================
        markdown.parser.theme = configuration

        // 方式 B：注入自定义 styler，做“某类节点特殊处理”（下方 DemoMarkdownStyler）
        markdown.parser.styler = DemoMarkdownStyler(configuration: configuration)

        // ============================================================
        // 6. 兼容旧的扁平写法（内部会映射到上面的集合 / Options）
        // ============================================================
        // markdown.parser.theme.bodyFont = .systemFont(ofSize: 16)
        // markdown.parser.theme.textColor = .darkGray
        // markdown.parser.theme.linkColor = .systemPink
        // markdown.parser.theme.lineSpacing = 6
        // markdown.parser.theme.paragraphSpacing = 14
        // markdown.parser.theme.listIndent = 26
        // markdown.parser.theme.quoteIndent = 16
        // markdown.parser.theme.imagePlaceholderHeight = 200
    }
}

// MARK: - 自定义样式器：继承默认实现，只覆写需要特殊处理的节点

final class DemoMarkdownStyler: DefaultMarkdownStyler {

    /// 一级标题加下划线，其余保持默认。
    override func style(heading str: NSMutableAttributedString, level: Int) {
        super.style(heading: str, level: level)
        if level == 1 {
            str.markdown_addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue)
        }
    }

    /// 行内代码额外加一点字距，观感更像“药丸标签”。
    override func style(code str: NSMutableAttributedString) {
        super.style(code: str)
        str.markdown_addAttribute(.kern, value: 0.5)
    }

    /// 链接加下划线。
    override func style(link str: NSMutableAttributedString, title: String?, url: String?) {
        super.style(link: str, title: title, url: url)
        str.markdown_addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue)
    }

    /// 引用块整体再压暗一点。
    override func style(blockQuote str: NSMutableAttributedString, nestDepth: Int) {
        super.style(blockQuote: str, nestDepth: nestDepth)
        str.markdown_addAttribute(.backgroundColor, value: UIColor.systemGray6)
    }
}

