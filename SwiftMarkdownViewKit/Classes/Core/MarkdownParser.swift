//
//  MarkdownParser.swift
//  MarkdownKit
//
//  对外统一入口（Facade）。业务方只需与本类型打交道：
//  传入 Markdown 字符串 + 主题，拿到可直接用于 UITextView 的富文本。
//

import UIKit
import Markdown

/// MarkdownKit 的公开门面：把 Markdown 文本解析并渲染成富文本。
///
/// ```swift
/// let parser = MarkdownParser()                       // 使用默认主题与内置指令
/// let attributed = parser.attributedString(from: md)  // 得到 NSAttributedString
/// textView.attributedText = attributed
/// ```
public struct MarkdownParser {

    weak var markdownView: MarkdownView?
    
    var originMarkdown: String = ""
    /// 已「定稿」的 Markdown 字符数（以 Character 计）。
    /// 该偏移之前的内容对应的块都已完整解析并缓存在 `stableAttr` 中，不会再变。
    private var stableCharCount: Int = 0

    /// 已定稿部分渲染好的富文本（builder 原始输出，未做 attachment 去重）。
    private var stableAttr: NSMutableAttributedString = NSMutableAttributedString()

    var attributedString: NSMutableAttributedString?

    /// 渲染主题（即样式配置 `MarkdownStylerConfiguration`）。
    /// 赋值后会自动重建默认样式器。
    public var theme: MarkdownTheme {
        didSet { styler = DefaultMarkdownStyler(configuration: theme) }
    }

    /// 样式器：决定每种节点「长什么样」（参考 Down 的 `Styler` / `DownStyler`）。
    /// 需要更深度的定制时，可继承 `DefaultMarkdownStyler` 并覆写对应的 `style(...)`。
    public var styler: MarkdownStyler

    /// 自定义指令注册表（音频、视频、mermaid、echarts 等）。
    public var directives: MarkdownDirectiveRegistry

    /// - Parameters:
    ///   - theme: 视觉主题（样式配置），默认自动适配明暗模式。
    ///   - directives: 自定义指令注册表，默认包含内置指令。
    public init(theme: MarkdownTheme = .default,
                directives: MarkdownDirectiveRegistry = .default) {
        self.theme = theme
        self.styler = DefaultMarkdownStyler(configuration: theme)
        self.directives = directives
    }

    /// 直接注入自定义样式器（与 Down 的 `toAttributedString(styler:)` 用法对应）。
    /// - Parameters:
    ///   - styler: 自定义样式器。
    ///   - directives: 自定义指令注册表，默认包含内置指令。
    public init(styler: MarkdownStyler,
                directives: MarkdownDirectiveRegistry = .default) {
        self.theme = styler.configuration
        self.styler = styler
        self.directives = directives
    }

    /// 将 Markdown 文本渲染为富文本。
    /// - Parameter markdown: 原始 Markdown 字符串。
    /// - Returns: 可直接赋给 `UITextView.attributedText` 的富文本。
    public func attributedString(from markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var builder = MarkdownAttributedStringBuilder(styler: styler, directives: directives, markdownView: markdownView)
        builder.text = markdown
        let attr = builder.visit(document)
        return renderView(attr: attr)
    }
    /// 流式增量渲染：追加一段 Markdown 文本并返回**完整**富文本。
    ///
    /// 核心思路（基于「绝对偏移 + 稳定块提交」，避免切片坐标错位）：
    /// 1. 以 `stableCharCount` 为绝对分界，把全文分成「已定稿前缀」和「未定稿尾巴」；
    /// 2. 只对尾巴重新解析；当尾巴里出现 **≥2 个顶层块**时，说明除最后一个块以外的块
    ///    都已经输入完整 → 把它们渲染后并入 `stableAttr`，并推进 `stableCharCount`；
    /// 3. 最后一个块（可能还没输入完）作为「实时尾巴」单独渲染；
    /// 4. 结果 = 已定稿前缀 + 实时尾巴，再走 `renderView` 复用 attachment。
    public mutating func appendString(from markdown: String) -> NSAttributedString {
        originMarkdown += markdown

        // 1) 取未定稿的尾巴（相对坐标都以这个 tail 为基准，保证一致）
        let stableStart = originMarkdown.index(originMarkdown.startIndex, offsetBy: stableCharCount)
        
        let tail = String(originMarkdown[stableStart...])

        // 2) 解析尾巴，尝试把「已完整的顶层块」提交为稳定内容
        let tailDoc = Document(parsing: tail)
        let blocks = Array(tailDoc.children)
        if blocks.count >= 2 {
            // 提交块数：默认最后一个块留作「实时尾巴」，其余提交。
            // 表格等「会随流式增长」的特殊块的处理被抽到 `stableCommitCount(for:)`，
            // 便于后续整体移除（移除时把这里换回 `blocks.count - 1` 即可）。
            let commitCount = stableCommitCount(for: blocks)

            // commitCount == 0 时无块可提交（边界不前移），直接跳过提交。
            //
            // 前进基准使用「最后一个已提交块的结束位置(upperBound)」，而不是
            // 「第一个未提交块的起始位置(lowerBound)」。
            //
            // 原因：当一个段落后紧跟表格且中间没有空行时（例如 `333\n| 表头 |...`），
            // cmark-gfm 会把 `Table.range.lowerBound` 报告成与前面段落**相同的起点**，
            // 于是「下一个未提交块的起点」会落在 tail 的起点上，导致 `advance == 0`、
            // `stableCharCount` 不前进 → 同一个段落被每帧重复提交（stableAttr 里
            // 出现 `333\n333\n333…` 的无限叠加）。改用已提交块的 upperBound 可保证
            // 前进量始终越过已提交内容，规避该范围重叠问题。
            if commitCount >= 1,
               let lastCommitted = blocks.prefix(commitCount).last,
               let cutoffRange = lastCommitted.range,
               let cutoffEnd = tail.index(for: cutoffRange.upperBound) {
                let advance = tail.distance(from: tail.startIndex, to: cutoffEnd)
                // 保护：若无法前进（范围退化/重叠导致 advance <= 0），本轮不提交，
                // 让这些块全部留在「实时尾巴」重解析，彻底避免重复叠加。
                if advance > 0 {
                    var builder = MarkdownAttributedStringBuilder(styler: styler, directives: directives, markdownView: markdownView)
                    builder.text = tail
                    // 提交 [0, commitCount) 这些已完整的块
                    for block in blocks.prefix(commitCount) {
                        let rendered = builder.visit(block)
                        // 跳过渲染为空的块（如被忽略的 HTML 注释），避免累积空白 "\n"。
                        if rendered.length == 0 { continue }
                        if stableAttr.length > 0 {
                            stableAttr.append(NSAttributedString(string: "\n")) // 块间分隔，与 visitDocument 行为一致
                        }
                        stableAttr.append(rendered)
                    }
                    // 推进绝对偏移到「最后一个已提交块的结束位置」
                    stableCharCount += advance
                }
            }
        }

        // 3) 渲染实时尾巴（从更新后的偏移重新取，避免复用上面已推进的 tail）
        let liveStart = originMarkdown.index(originMarkdown.startIndex, offsetBy: stableCharCount)
        let liveTail = String(originMarkdown[liveStart...])
        var liveBuilder = MarkdownAttributedStringBuilder(styler: styler, directives: directives, markdownView: markdownView)
        liveBuilder.text = liveTail

        var liveBlocks = Array(Document(parsing: liveTail).children)
        // 丢弃实时尾巴末尾的「半截表格行/分隔行」段落：
        // 流式中下一行只输入了 `|`（或 `|---` 等）时，swift-markdown 会把这个孤立的 `|`
        // 当成独立段落、并中断前面的表格 → 渲染出一根游离竖线。它只是「下一行正在输入」
        // 的残影，等该行补全会自动并回表格，这里直接不渲染它。
        //
        // 但要避免误伤「真正独立、就想显示的 `|`」：markdown 里独立段落本应由空行隔开，
        // 而「正在输入的新行」一定紧贴上一行、中间没有空行。因此仅当该 `|` 残影段落
        // **前面没有空行**（紧贴内容）时才丢弃；被空行隔开的 `|` 视为真实内容，正常显示。
        // 仅作用在 live tail（从不进 stableAttr），所以安全、可自愈。

        let liveAttr = NSMutableAttributedString()
        for block in liveBlocks {
            let rendered = liveBuilder.visit(block)
            // 跳过渲染为空的块（如被忽略的 HTML 注释），避免累积空白 "\n"。
            if rendered.length == 0 { continue }
            if liveAttr.length > 0 {
                liveAttr.append(NSAttributedString(string: "\n")) // 块间分隔，与 visitDocument 行为一致
            }
            liveAttr.append(rendered)
        }

        // 4) 拼接：已定稿前缀 + 实时尾巴
        let full = NSMutableAttributedString(attributedString: stableAttr)
        if full.length > 0, liveAttr.length > 0 {
            full.append(NSAttributedString(string: "\n"))
        }
        full.append(liveAttr)

        let rendAttr = renderView(attr: full)
        self.attributedString = rendAttr

        // —— 流式诊断日志（定位竖线/表格异常用，问题解决后可整段删除）——
        return rendAttr
    }

    /// 计算本轮可提交为「稳定内容」的块数量。
    ///
    /// 基础规则：最后一个块留作「实时尾巴」（可能还没输入完），其余块可提交 → `blocks.count - 1`。
    ///
    /// 在此基础上单独处理**会随流式逐步增长的块（当前仅表格）**的特殊情况：
    /// 表格是逐行增长的，流式过程中后面常会临时冒出一个「半截行被误判成的段落块」，
    /// 使表格提前变成倒数第二块；若此时提交，会把「只有部分行的表格」冻结进 `stableAttr`，
    /// 后续行再也补不回来。因此当倒数第二块是表格时，把它也留到实时尾巴继续重解析，
    /// 等它后面出现真正独立的块（不再是倒数第二块）时才提交，此时表格必然已闭合、body 完整。
    ///
    /// - Note: 此方法是可插拔的特殊处理入口。若后续要**整体移除**表格特殊逻辑，
    ///   直接删除本方法、并把调用处 `stableCommitCount(for: blocks)` 换回 `blocks.count - 1` 即可，
    ///   不会影响主流程。
    private func stableCommitCount(for blocks: [Markup]) -> Int {
        var commitCount = blocks.count - 1

        // —— 表格特殊处理（可整段删除）——
        if commitCount >= 1, blocks[commitCount - 1] is Table,!(blocks.last is Table) {
            commitCount -= 1
        }
        // —— 表格特殊处理结束 ——

        return commitCount
    }



    /// 从 Bundle 中读取 `.md` 文件并渲染。
    /// - Parameters:
    ///   - name: 资源名（不含扩展名）。
    ///   - ext: 扩展名，默认 `md`。
    ///   - bundle: 资源所在 Bundle，默认主 Bundle。
    /// - Returns: 渲染后的富文本；文件不存在或读取失败时返回 `nil`。
    public func attributedString(resource name: String,
                                 withExtension ext: String = "md",
                                 in bundle: Bundle = .main) -> NSAttributedString? {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return attributedString(from: content)
    }
    
    private func renderView(attr: NSAttributedString) -> NSMutableAttributedString{
        let mAttr = NSMutableAttributedString(attributedString: attr)
        mAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mAttr.length), options: [.reverse], using: { value, range, stop in
            if let value = value as? BaseAttachment {
                var attachment: BaseAttachment = value
                if let oldAttachment = getAttachment(range: range){
                    ///  1. 如果已经存在相同位置的 attachment，则使用旧的 attachment 替换新的 attachment，避免重复渲染。
                    if oldAttachment.streamState != .none, type(of: oldAttachment.view) == type(of: value.view) {// 2. 如果类型相同，则复用旧的 attachment，避免重复渲染。
                        oldAttachment.markupCtx = value.markupCtx
                        attachment = oldAttachment
                        attachment.updataData(attachment.view)
                        let attr = NSAttributedString(attachment: attachment)
                        mAttr.replaceCharacters(in: range, with: attr)
                    }else {
                        /// 3. 如果类型不同，则移除旧的 attachment，使用新的 attachment。
                        ///
                        oldAttachment.removeView()
                    }
                }
            }
        })
        return mAttr
    }
    func getAttachment(range: NSRange) -> BaseAttachment? {
        guard let markdownView = markdownView else {return nil}
        let attachments = markdownView.loadableAttachments
        let old = attachments.first {
            $0.range?.location == range.location
        }
        return old
    }
    
   
}
