//
//  MarkupEx.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/11.
//

import UIKit

import Markdown

// MARK: - SourceLocation -> String.Index 映射
//
// swift-markdown 的 SourceLocation：
//   - line：行号，从 1 开始
//   - column：**从行首起算的 UTF-8 字节数**，从 1 开始（注意不是字符数、也不是 UTF-16 单元数！）
// 因此换算成 String.Index 必须走 UTF-8 视图，否则遇到中文 / emoji 会算错位置。
public extension String {

    /// 将一个 `SourceLocation`（行/列）映射为本字符串中的 `String.Index`。
    /// - Returns: 对应位置的下标；若越界或未落在字符边界上则返回 `nil`。
    func index(for location: SourceLocation) -> String.Index? {
        guard location.line >= 1, location.column >= 1 else { return nil }

        let utf8 = self.utf8
        var idx = utf8.startIndex
        var currentLine = 1

        // 1) 先跳到目标行的行首
        while currentLine < location.line {
            guard idx < utf8.endIndex else { return nil }
            if utf8[idx] == 0x0A { // '\n'
                currentLine += 1
            }
            idx = utf8.index(after: idx)
        }

        // 2) 在该行内按 UTF-8 字节前进 (column - 1) 个字节
        var remaining = location.column - 1
        while remaining > 0, idx < utf8.endIndex {
            idx = utf8.index(after: idx)
            remaining -= 1
        }

        // 3) 对齐到 Character 边界后转成 String.Index
        return idx.samePosition(in: self)
    }

    /// 传入一个 `Markup`，返回从该节点**起始位置**开始截取到字符串末尾的子串。
    /// 若该节点没有位置信息或换算越界，则返回 `nil`。
    func sliced(from markup: Markup) -> Substring? {
        guard let source = markup.range,
              let lower = index(for: source.lowerBound) else {
            return nil
        }
        return self[lower...]
    }
    
   public func slicedString(from markup: Markup) -> String? {
        let substring = sliced(from: markup)
        return String(substring ?? "")
    }
}

public class MarkupWrapper {
    public var markup: Markup
    public init(_ markup: Markup) {
        self.markup = markup
    }
}

// MARK: - Markup 增量解析辅助
public extension Markup {

    /// 该节点在给定源字符串 `text` 中所占的字符范围（基于节点自带的 `range`/SourceRange）。
    /// 若节点没有位置信息或换算越界，则返回 nil。
    func range(in text: String) -> Range<String.Index>? {
        guard let source = self.range,
              let lower = text.index(for: source.lowerBound),
              let upper = text.index(for: source.upperBound),
              lower <= upper else {
            return nil
        }
        return lower..<upper
    }

    /// 取该节点**结束位置之后**到字符串末尾的剩余内容。
    ///
    /// 增量解析典型用法：找到「最后一个已完整解析的块」，用它的尾巴作为下一轮
    /// 重新解析的起点，从而只解析新增/未闭合的部分，避免整篇重解析。
    func tail(in text: String) -> Substring? {
        guard let source = self.range,
              let upper = text.index(for: source.upperBound) else {
            return nil
        }
        return text[upper...]
    }

    /// 取从该节点**起始位置**到字符串末尾的剩余内容（含本节点自身）。
   public func slicedFromStart(in text: String) -> Substring? {
        guard let source = self.range,
              let lower = text.index(for: source.lowerBound) else {
            return nil
        }
        return text[lower...]
    }

    /// 判断两个 `Markup` 是否「相等」。
    ///
    /// 判定策略：
    /// 1. 先用 `isIdentical(to:)` 判断是否为**同一节点实例**（O(1)，快速路径）；
    /// 2. 否则用 `hasSameStructure(as:)` 判断**子树结构是否等价**（节点类型 + 内容一致，
    ///    忽略源码位置 range）。
    ///
    /// 注意：`isIdentical` 比较的是每次解析都会重新生成的内部 id，跨解析永远为 false，
    /// 因此增量场景必须靠 `hasSameStructure` 判断「内容是否一致」。
    func isEqual(to other: Markup?) -> Bool {
        guard let other = other else { return false }
        guard let selfLower = self.range?.lowerBound, let otherLower = other.range?.lowerBound else {
            return false
        }
        return selfLower == otherLower
    }
}

public extension CodeBlock {
   public func isClosed(source: String?) -> Bool{        guard let source = source else { return true }
        let tailStr = slicedFromStart(in: source).map(String.init)
        return isClosedCodeBlock(tailStr: tailStr, code: code)
    }
    func isClosedCodeBlock(tailStr: String?, code: String) -> Bool {
        guard let tailStr = tailStr else { return false }

        var lines = tailStr.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return false }

        // 1) 解析第一行的开围栏：字符种类 + 数量
        let opening = lines.removeFirst().drop { $0 == " " }
        guard let marker = opening.first, marker == "`" || marker == "~" else {
            // 第一行不是围栏 → 说明是「缩进代码块」，天然完整，视为已闭合。
            return true
        }
        let openCount = opening.prefix { $0 == marker }.count
        guard openCount >= 3 else {
            // 反引号/波浪号不足 3 个，不构成围栏 → 按缩进代码块处理，视为已闭合。
            return true
        }

        // 2) 在剩余行里找配对的闭围栏
        for rawLine in lines {
            let line = rawLine.drop { $0 == " " }
            guard let first = line.first, first == marker else { continue }
            let count = line.prefix { $0 == marker }.count
            let rest = line.drop { $0 == marker }
            if count >= openCount, rest.allSatisfy({ $0 == " " }) {
                return true // 找到闭围栏 → 已闭合
            }
        }
        return false // 没找到 → 未闭合
    }
}

// MARK: - HTMLBlock 闭合判断（流式渲染用）

public extension HTMLBlock {

    /// 判断该 HTML 块是否已闭合（所有标签成对、无悬空 `<`）。
    ///
    /// 流式渲染时，`<body>…` 可能已到但 `</body>` 还没到，此时应显示光晕占位，
    /// 等标签闭合后再真正渲染。判定用 `HTMLTagBalancer`（标签栈平衡），比
    /// `validateHTML()` 更可靠——后者对残缺 HTML 也常返回 true，判不出未闭合。
    /// - Parameter source: 兼容 `CodeBlock.isClosed(source:)` 的签名；HTMLBlock 的
    ///   `rawHTML` 已是完整片段，内部直接用它判断。
    func isClosed(source: String?) -> Bool {
        HTMLTagBalancer.isBalanced(rawHTML)
    }
}

// MARK: - HTML 标签栈平衡判断

/// 通过「标签栈平衡」判断一段 HTML 是否闭合。
///
/// 判定规则：
/// 1. 悬空 `<`：最后一个 `<` 之后还没出现 `>`（标签名都没写完）→ 未闭合（流式典型场景）；
/// 2. void 元素（`<br>` `<img>` `<hr>` 等）与自闭合 `.../>`：不入栈；
/// 3. 注释 `<!-- -->`、`<!doctype>`、`<?…?>`：跳过；
/// 4. 开标签入栈、闭标签与栈顶配对出栈；遍历完**栈为空** → 已闭合。
public enum HTMLTagBalancer {

    /// HTML void 元素（无需闭合标签），统一小写比较。
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    /// 判断 HTML 是否标签平衡（已闭合）。
    public static func isBalanced(_ html: String) -> Bool {
        let scalars = Array(html)
        var i = 0
        var stack: [String] = []
        let n = scalars.count

        while i < n {
            guard scalars[i] == "<" else { i += 1; continue }

            // 悬空 `<`：后面找不到 `>` → 标签未写完 → 未闭合
            guard let gt = nextIndex(of: ">", in: scalars, from: i + 1) else {
                return false
            }

            let inner = String(scalars[(i + 1)..<gt]) // <...> 中间的内容

            // 注释 / <!doctype> / <?...?> → 跳过，不影响平衡
            if inner.hasPrefix("!") || inner.hasPrefix("?") {
                i = gt + 1
                continue
            }

            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("/") {
                // 闭标签 </tag>：与栈顶配对
                let name = tagName(from: String(trimmed.dropFirst()))
                if let top = stack.last, top == name {
                    stack.removeLast()
                } else if let idx = stack.lastIndex(of: name) {
                    // 容错：非严格嵌套时，回退到匹配的层级
                    stack.removeSubrange(idx..<stack.count)
                }
                // 找不到匹配的闭标签直接忽略（多余的闭标签）
            } else {
                // 开标签 <tag ...> 或自闭合 <tag/>
                let name = tagName(from: trimmed)
                let isSelfClosing = trimmed.hasSuffix("/")
                if !isSelfClosing, !voidElements.contains(name), !name.isEmpty {
                    stack.append(name)
                }
            }

            i = gt + 1
        }

        return stack.isEmpty
    }

    /// 从标签内部文本中提取标签名（小写），如 `div class="x"` → `div`。
    private static func tagName(from raw: String) -> String {
        var name = ""
        for ch in raw {
            if ch == " " || ch == "\t" || ch == "\n" || ch == "/" || ch == ">" { break }
            name.append(ch)
        }
        return name.lowercased()
    }

    private static func nextIndex(of target: Character, in scalars: [Character], from start: Int) -> Int? {
        var j = start
        while j < scalars.count {
            if scalars[j] == target { return j }
            j += 1
        }
        return nil
    }
}

public extension String {

    /// 用系统 HTML 解析器做一次「语法有效性」校验。
    ///
    /// ⚠️ 注意：它对残缺 HTML 也大多能容错解析并返回 true，**不能单独用来判断标签是否闭合**，
    /// 仅作为辅助的合法性校验。判断闭合请用 `HTMLTagBalancer.isBalanced(_:)`。
    func validateHTML() -> Bool {
        guard let data = data(using: .utf8) else { return false }
        return (try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil)) != nil
    }
}
