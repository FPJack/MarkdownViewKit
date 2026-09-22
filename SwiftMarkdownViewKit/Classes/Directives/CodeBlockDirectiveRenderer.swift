//
//  CodeBlockDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/17.
//

import UIKit
import Markdown
// MARK: - 代码块指令

/// 代码块自定义指令，用于处理带特定语言标识的围栏代码块。
///
/// 例如：` ```mermaid `、` ```echarts `。
/// 若未命中任何指令，渲染器会退回到普通代码块样式。
public struct CodeBlockContext {
    let codeBlock: CodeBlock
    let visitor: MarkdownAttributedStringBuilder
    let isClosed: Bool
    init(codeBlock: CodeBlock, visitor: MarkdownAttributedStringBuilder) {
        self.codeBlock = codeBlock
        self.visitor = visitor
        self.isClosed = codeBlock.isClosed(source: visitor.text)
    }
}
public protocol CodeBlockDirectiveRenderer: DirectiveRenderer {
    /// 代码块语言标识（小写），如 "mermaid"、"echarts"。
    var language: String { get }
    typealias MarkupType = CodeBlock
}
