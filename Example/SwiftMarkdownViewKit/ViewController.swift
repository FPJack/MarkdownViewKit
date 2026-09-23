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

    /// 🔀 验证开关：true = 加载阿拉伯语样本并按 RTL 排版；false = 加载原来的 html.md。
    private let isArabicDemo = false
    

    lazy var markdown = MarkdownView()
    
    lazy var testView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemPink.withAlphaComponent(0.2)
        self.observer = ViewBoundsObserver(view: view) { [weak self] view,old,new  in
            guard let self = self else { return }
            print("testView bounds changed: \(new)")
        }
        return view
    }()
    var observer: ViewBoundsObserver?

    /// 持有 scrollView 的高度上限约束。
    ///
    /// ⚠️ 不能在旋转时反复调用 `box.maxHeight(_:)`——它每次都会**新建**一条
    /// `heightAnchor <= constant` 约束。多次旋转后这些约束会叠加，
    /// 最终被最小的那条锁死，表现为「转回竖屏后高度再也回不来」。
    /// 正确做法是持有约束、只更新 `constant`。
    private var hostScrollViewMaxHeight: NSLayoutConstraint?

    /// MarkdownView 左右各留的边距，统一成常量，避免旋转时两处算得不一致。
    private let horizontalPadding: CGFloat = 20

    private lazy var displayLink = {
      let timer =  DisplayLinkTimer(preferredFramesPerSecond: 5) { tick in
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
        let length = min(30, source.count - readOffset)
        let piece = String(source[readOffset ..< readOffset + length])
      
        readOffset += length
        self.markdown.appendText(fromMarkdown: piece)

    }
    // 每个元素都是一个完整的用户感知字符（含 ZWJ emoji 序列、变体选择符等）
    lazy var source: [Character] = Array(loadMarkdown())
    private var readOffset: Int = 0


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
//        self.view.addSubview(testView)
//        testView.frame = CGRect(x: 100, y: 100, width: 100, height: 100)
//        testView.frame = CGRect(x: 100, y: 100, width: 50, height: 50)
//        testView.frame = CGRect(x: 100, y: 100, width: 80, height: 80)
//
//        return

        // ⚠️ 样式必须在开始（流式）渲染之前配置好，否则已渲染出来的内容不会自动重排。
        configureMarkdownStyle()

        markdown.maxTextWidth = self.view.bounds.width - horizontalPadding * 2
        markdown.frameInterval = 10
        markdown.charactersPerFrame = 5
        markdown.textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        markdown.textView.backgroundColor = UIColor.black.withAlphaComponent(0.05)
        let scrollView =
            VStackView {
                markdown
            }
//            .align(.fill)
            .wrapScrollView()
            
            scrollView.box
            .addTo(view)
            .top(100)
            .leading(horizontalPadding)
            .trailing(-horizontalPadding)
//            .width(300)

            // 高度上限单独建约束并持有，方便旋转时直接改 constant（见属性注释）。
            let maxHeight = scrollView.heightAnchor
                .constraint(lessThanOrEqualToConstant: view.bounds.height - 140)
            maxHeight.isActive = true
            self.hostScrollViewMaxHeight = maxHeight

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

    // MARK: - 横竖屏切换
    //
    // MarkdownView 的排版宽度由 `maxTextWidth` 决定，它不会自己跟随屏幕变化，
    // 需要宿主在尺寸变化时更新。更新后库内部会自动：
    //   1. 重新推导每个附件（表格 / 代码块 / 图片 / WebView）的可用宽度；
    //   2. 让这些子视图按新宽度重新测量；
    //   3. 让 TextKit 对受影响的区间重新排版。
    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self else { return }
            self.applyLayout(for: size)
        }, completion: { [weak self] _ in
            // 旋转动画结束后再补一次：
            // WebView 内容（图表 / 公式）的高度是异步回报的，
            // 动画期间拿到的往往还是旧值。
            self?.markdown.invalidateLayoutForWidthChange()
        })
    }

    /// 按给定的容器尺寸更新排版宽度与滚动区域高度。
    private func applyLayout(for size: CGSize) {
        markdown.maxTextWidth = size.width - horizontalPadding * 2
        // 高度上限跟随屏幕，不能写死 700——横屏时会超出可视区域。
        // 顶部留了 100，底部再留 40 的安全边距。
        hostScrollViewMaxHeight?.constant = max(200, size.height - 140)
        // maxTextWidth 的 didSet 已经会触发重排，这里显式调用是为了
        // 覆盖「宽度没变但容器变了」的情况（例如只改了高度）。
        markdown.invalidateLayoutForWidthChange()
    }

    private func loadMarkdown() -> String {
//        if isArabicDemo { return Self.arabicSample }
        if let url = Bundle.main.url(forResource: "test", withExtension: "md"),

//        if let url = Bundle.main.url(forResource: "html", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        } else {
            return "# 未找到 html.md\n请确认该文件已加入 App Target 的资源中。"
        }
    }

}

// MARK: - 阿拉伯语（RTL）验证样本
//
// 覆盖各类节点，逐条对照「预期表现」即可验证 RTL 适配是否生效。
extension ViewController {

    static let arabicSample = """
    # مرحبا بك في محرر ماركداون

    هذه فقرة عربية عادية لاختبار اتجاه النص من اليمين إلى اليسار. \
    يجب أن يبدأ السطر من الجانب الأيمن من الشاشة.

     ![山川风景](https://img2.baidu.com/it/u=2838910375,3102156952&fm=253&app=138&f=JPEG?w=800&h=1067)
    
    ## قائمة غير مرتبة

    - العنصر الأول
    - العنصر الثاني
      - عنصر متداخل
    - العنصر الثالث

    ## قائمة مرتبة

    1. الخطوة الأولى
    2. الخطوة الثانية
    3. الخطوة الثالثة

    ## قائمة مهام

    - [x] مهمة منجزة
    - [ ] مهمة قيد التنفيذ

    ## اقتباس

    > هذا اقتباس عربي. الشريط الجانبي والمسافة البادئة يجب أن يكونا على اليمين.

    ---

    ## نص مختلط واتجاه ثنائي

    استخدم الدالة `calculateTotal(items)` في الملف `main.swift` للحصول على النتيجة (مهم جدا).

    رابط للتوثيق: [موقع أبل للمطورين](https://developer.apple.com)

    إصدار النظام هو iOS 18.0 والرقم 12345 يجب أن يظهر بشكل صحيح.

    ## كتلة شيفرة (يجب أن تبقى من اليسار إلى اليمين)

    ```swift
    func greet(name: String) -> String {
        if name.isEmpty { return "Hello, World!" }
        return "Hello, \\(name)!"
    }
    ```

    ## جدول

    | الاسم | العمر | المدينة |
    | --- | --- | --- |
    | أحمد | 30 | الرياض |
    | فاطمة | 25 | دبي |
    | محمد | 41 | القاهرة |

    ## تنسيقات النص

    نص **عريض** ونص *مائل* ونص ~~مشطوب~~ ونص `شيفرة مضمنة`.

    ## صور صغيرة (اختبار المحاذاة)

    صورة صغيرة يجب أن تلتصق بالجانب الأيمن:

    ![شارة](https://img.shields.io/badge/Swift-5.9-orange.svg)

    صورة صغيرة أخرى، وهي أيضا يجب أن تكون على اليمين:

    ![أيقونة](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIj48Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI0MCIgZmlsbD0iIzRjYWY1MCIvPjwvc3ZnPg==)

    صورة عريضة تملأ العرض كله:

    ## معادلة رياضية (يجب أن تبقى من اليسار إلى اليمين)

    $$
    \\sum_{i=1}^{n} x_i = \\frac{a + b}{c - d}
    $$

    ## مخطط انسيابي (يجب أن تبقى من اليسار إلى اليمين)

    ```mermaid
    graph LR
      A[Start] --> B{Check}
      B -->|Yes| C[Done]
      B -->|No| D[Retry]
    ```

    ## مخطط بياني (ECharts)

    مخطط أعمدة بعناوين عربية لاختبار اتجاه المحاور والعنوان ووسيلة الإيضاح:

    ```echarts
    {
      "title": { "text": "المبيعات الفصلية 2025", "left": "left" },
      "tooltip": { "trigger": "axis" },
      "legend": { "data": ["المبيعات"], "left": "left", "top": "bottom" },
      "grid": { "top": 60, "bottom": 60 },
      "xAxis": { "type": "category", "data": ["الربع 1", "الربع 2", "الربع 3", "الربع 4"] },
      "yAxis": { "type": "value" },
      "series": [
        { "name": "المبيعات", "type": "bar", "data": [120, 200, 150, 280] }
      ]
    }
    ```

    ## محتوى HTML
    <div>
    <p>هذه فقرة عربية داخل HTML ويجب أن تكون على اليمين.</p>
    <ul>
      <li>عنصر أول</li>
      <li>عنصر ثان</li>
    </ul>
    <blockquote>اقتباس داخل HTML، الشريط الجانبي على اليمين.</blockquote>
    <pre><code>const total = items.reduce((a, b) => a + b, 0);</code></pre>
    <table>
      <tr><th>الاسم</th><th>القيمة</th></tr>
      <tr><td>الأول</td><td>100</td></tr>
    </table>
    </div>

    ## العنوان الأخير

    انتهى الاختبار. شكرا لك.
    """
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
        // 给所有字体挂上阿拉伯语回退链（code 字体会被跳过，保持等宽）。
        // 系统字体本身就覆盖阿拉伯文，这一步主要是给「自定义字体」兜底，
        // 避免出现豆腐块 □□□。在中文 / 英文场景下调用也完全无副作用。
        .supportingArabic()

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
            heading1: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 3
                style.paragraphSpacingBefore = 10
                style.paragraphSpacing = 6
                return style
            }(),

            heading2: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 3
                style.paragraphSpacingBefore = 8
                style.paragraphSpacing = 5
                return style
            }(),

            heading3: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 3
                style.paragraphSpacingBefore = 7
                style.paragraphSpacing = 4
                return style
            }(),

            heading4: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                style.paragraphSpacingBefore = 6
                style.paragraphSpacing = 4
                return style
            }(),

            heading5: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                style.paragraphSpacingBefore = 5
                style.paragraphSpacing = 3
                return style
            }(),

            heading6: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                style.paragraphSpacingBefore = 4
                style.paragraphSpacing = 3
                return style
            }(),

            body: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 4
                style.paragraphSpacing = 6
                return style
            }(),

            code: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                style.paragraphSpacing = 4
                return style
            }()
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

        // —— 排版方向（RTL / 阿拉伯语适配的总开关）——
        //  .automatic   跟随 App 界面语言（中文 / 英文 → LTR；阿拉伯语 → RTL）
        //  .leftToRight 强制从左到右
        //  .rightToLeft 强制从右到左
        // 也可以按内容自动推断：MarkdownLayoutDirection.inferred(from: markdownText)
        configuration.layoutDirection = isArabicDemo ? .rightToLeft : .automatic

        // —— RTL 行高补偿 ——
        // 阿拉伯语的变音符号（تشكيل）和字母降部会超出拉丁字体的默认行框，
        // 不抬高会被裁切。1.0 表示不调整；只在 RTL 时生效。
        configuration.rightToLeftLineHeightMultiple = 1.25

        // —— 强调 `*文字*` 的呈现方式 ——
        // 阿拉伯语 / 希伯来语没有斜体，机械倾斜会让连笔断裂，所以 RTL 默认改用加粗。
        // 可选：.italic / .bold / .underline / .color(UIColor) / .none
        configuration.emphasisStyle = .italic              // LTR：保持斜体
        configuration.rightToLeftEmphasisStyle = .bold     // RTL：改用加粗

        // —— 库内置 UI 文案（代码块的「代码 / 复制 / 已复制」）——
        // 默认跟随 App 首选语言；这里 App 是中文但内容是阿拉伯语，所以显式指定。
        configuration.localizedStrings = isArabicDemo ? .forLanguageCode("ar") : .current

        // —— 流程图流向是否跟随 RTL 镜像 ——
        // 默认 false：保持作者写在 ```mermaid 里的 `graph LR` 不动。
        // 设为 true 时，RTL 下会把 `graph LR` 改写成 `graph RL`，
        // 整张图从右往左排布（箭头语义不变，A --> B 仍是 A 指向 B）。
        // 纵向流程图 TB / TD / BT 不受影响。
        //
        // ⚠️ 这是「改写用户内容」，属于产品决策，所以默认关闭、需显式开启。
        configuration.mirrorsDiagramFlowInRightToLeft = isArabicDemo

        // —— 列表：缩进与间距 ——
        configuration.listItemOptions = MarkdownListItemOptions(
            maxPrefixDigits: 2,         // 有序列表序号最多按几位数字预留宽度
            spacingAfterPrefix: 8,      // “1.” 与内容之间的距离
            spacingAbove: 2,            // 列表项上方间距
            spacingBelow: 6,            // 列表项下方间距
            nestedIndentation: 26,      // 每嵌套一层增加的缩进
            alignment: .natural
        )

        // —— 引用块：左侧竖条 + 整块背景 ——
        configuration.quoteStripeOptions = MarkdownQuoteStripeOptions(
            thickness: 4,               // 竖条粗细
            spacingAfter: 12,           // 竖条与文字的间距（整体缩进
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

    /// 引用块的文字再压暗一点。
    ///
    /// ⚠️ 这里只改**文字颜色**，不要用 `.backgroundColor` 去做引用底色——
    /// 那个属性只给字形外接矩形上色，缩进区和行尾空白会漏底，
    /// 多行引用会变成一条条断开的色块。
    /// 整块背景请用 `colors.quoteBackground` + `quoteStripeOptions`，
    /// 由 `MarkdownLayoutManager` 统一绘制。
    override func style(blockQuote str: NSMutableAttributedString, nestDepth: Int) {
        super.style(blockQuote: str, nestDepth: nestDepth)
        str.markdown_addAttribute(.foregroundColor, value: UIColor.secondaryLabel)
    }
}

