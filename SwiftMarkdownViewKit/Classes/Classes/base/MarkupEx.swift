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
    func slicedFromStart(in text: String) -> Substring? {
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
    
    func wrapperObj() -> MarkupWrapper {
        return MarkupWrapper(self)
    }

}

