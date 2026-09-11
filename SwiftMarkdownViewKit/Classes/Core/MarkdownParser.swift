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

    /// 渲染主题。
    public var theme: MarkdownTheme
    /// 自定义指令注册表（音频、视频、mermaid、echarts 等）。
    public var directives: MarkdownDirectiveRegistry

    /// - Parameters:
    ///   - theme: 视觉主题，默认自动适配明暗模式。
    ///   - directives: 自定义指令注册表，默认包含内置指令。
    public init(theme: MarkdownTheme = .default,
                directives: MarkdownDirectiveRegistry = .default) {
        self.theme = theme
        self.directives = directives
    }

    /// 将 Markdown 文本渲染为富文本。
    /// - Parameter markdown: 原始 Markdown 字符串。
    /// - Returns: 可直接赋给 `UITextView.attributedText` 的富文本。
    public func attributedString(from markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var builder = MarkdownAttributedStringBuilder(theme: theme, directives: directives)
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
        if blocks.count >= 2,
           let lastRange = blocks.last?.range,
           let lastStart = tail.index(for: lastRange.lowerBound) {
            var builder = MarkdownAttributedStringBuilder(theme: theme, directives: directives)
            // 除最后一个块外，其余块都已定稿
            for block in blocks.dropLast() {
                if stableAttr.length > 0 {
                    stableAttr.append(NSAttributedString(string: "\n")) // 块间分隔，与 visitDocument 行为一致
                }
                stableAttr.append(builder.visit(block))
            }
            // 推进绝对偏移到「最后一个块的起点」
            stableCharCount += tail.distance(from: tail.startIndex, to: lastStart)
        }

        // 3) 渲染实时尾巴（从更新后的偏移重新取，避免复用上面已推进的 tail）
        let liveStart = originMarkdown.index(originMarkdown.startIndex, offsetBy: stableCharCount)
        let liveTail = String(originMarkdown[liveStart...])
        var liveBuilder = MarkdownAttributedStringBuilder(theme: theme, directives: directives)
        let liveAttr = liveBuilder.visit(Document(parsing: liveTail))

        // 4) 拼接：已定稿前缀 + 实时尾巴
        let full = NSMutableAttributedString(attributedString: stableAttr)
        if full.length > 0, liveAttr.length > 0 {
            full.append(NSAttributedString(string: "\n"))
        }
        full.append(liveAttr)

        let rendAttr = renderView(attr: full)
        self.attributedString = rendAttr
        return rendAttr
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
                    attachment = oldAttachment
                    let attr = NSAttributedString(attachment: attachment)
                    mAttr.replaceCharacters(in: range, with: attr)
                }
            }
        })
        return mAttr
    }
    func getAttachment(range: NSRange) -> BaseAttachment? {
        guard let markdownView = markdownView else {
            return nil
        }
        let attachments = markdownView.loadableAttachments
        let old = attachments.first {
             $0.range?.location == range.location
        }
        return old
    }
}
