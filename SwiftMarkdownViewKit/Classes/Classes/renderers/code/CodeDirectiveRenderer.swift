//
//  CodeDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/14.
//

import UIKit
import Markdown

public struct CodeDirective: CodeBlockDirectiveRenderer {
    public var language: String = ""
    public func renderView(context: MarkupContext<CodeBlock>) -> (any ViewLoadable)? {
        let cb = CodeBlockView()
        var configuration = CodeBlockOption()
        configuration.allowsVerticalScroll = false
        configuration.allowsHorizontalScroll = false
        // 只把方向透传给头部工具栏；代码正文 / 行号栏在 CodeBlockView 内部恒为 LTR。
        configuration.layoutDirection = context.visitor.theme.layoutDirection
        // 头部文案跟随样式配置里的语言（默认 = App 首选语言）。
        let strings = context.visitor.theme.localizedStrings
        configuration.defaultTitle = strings.codeBlockTitle
        configuration.copyTitle = strings.copy
        configuration.copiedTitle = strings.copied
        configuration.codeFont = UIFont(name: "Menlo", size: 15)
        ?? .systemFont(ofSize: 15)
        configuration.lineNumberFont = configuration.codeFont
        cb.clipsToBounds = true
        cb.layer.cornerRadius = configuration.cornerRadius
        cb.layer.borderWidth = 1
        cb.layer.borderColor = configuration.borderColor.cgColor
        cb.showsLineNumbers = configuration.showsLineNumbers
        cb.allowsHorizontalScroll = configuration.allowsHorizontalScroll
        cb.allowsVerticalScroll = configuration.allowsVerticalScroll
        cb.maxCellWidth = configuration.maxCellWidth
        // 0 表示不限制；真正的可用宽度会在 updateViewOptions 里由容器推导后写入，
        // 容器宽度变化（横竖屏 / 分屏）时也走同一条路径刷新。
        cb.maxViewWidth = configuration.maxWidth
        cb.maxViewHeight = configuration.maxHeight
        cb.codeFont = configuration.codeFont
        cb.lineNumberFont = configuration.lineNumberFont
        cb.lineNumberColor = configuration.lineNumberColor
        cb.gutterBackgroundColor = configuration.gutterBackgroundColor
        cb.codeBackgroundColor = configuration.codeBackgroundColor
        // RTL 时：行号栏移到右侧、代码行右对齐（字符顺序仍是 LTR）。
        cb.layoutDirection = configuration.layoutDirection
        cb.codeLineAlignment = configuration.codeLineAlignment
        // 头部：语言名（或默认文字）+ 复制按钮。
        //
        // 注意：这里必须取 `codeBlockCtx.codeBlock.language`（这段代码块实际的语言），
        // 而不是 `self.language`——后者是「指令注册用的 key」，
        // 通用代码块指令注册时它恒为空串，用它会导致头部标题永远是空的。
        let fenceLanguage = context.markup.language?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let header = CodeBlockHeaderView(title: fenceLanguage.isEmpty ? configuration.defaultTitle : fenceLanguage,
                                         config: configuration,
                                         onCopy: {
        })
        cb.headerView = header
        return cb
    }

}
